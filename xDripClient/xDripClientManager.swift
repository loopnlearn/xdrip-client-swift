//
//  xDripClientManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit

public class xDripClientManager: NSObject, CGMManager {
    
    public static var managerIdentifier = "xDripClient"

    /// - instance of bluetoothTransmitter that will connect to the CGM, with goal to achieve heartbeat mechanism,  nothing else
    /// - if nil then there's no heartbeat generated
    private var bluetoothTransmitter: BluetoothTransmitter?
    
    /// define notification center, to be informed when app comes in background, so that fetchNewData can be forced
    let notificationCenter = NotificationCenter.default

    public override init() {
        
        // call super.init
        super.init()
        
        client = xDripClient()
        
        // add observer for will enter foreground
        notificationCenter.addObserver(self, selector: #selector(runWhenAppWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        // add observer for did finish launching
        notificationCenter.addObserver(self, selector: #selector(runWhenAppWillEnterForeground(_:)), name: UIApplication.didFinishLaunchingNotification, object: nil)

        // add observer for useCGMAsHeartbeat - this is a user setting. If user enables/disables, then the bluetoothTransmitter must be initialized or set to nil
        UserDefaults.standard.addObserver(self, forKeyPath: UserDefaults.Key.useCGMAsHeartbeat.rawValue, options: .new, context: nil)

        // possibly cgmTransmitterDeviceAddess in shared user defaults has been changed by xDrip4iOS while Loop was not running. Reassign the value in UserDefaults
        UserDefaults.standard.cgmTransmitterDeviceAddress = client?.cgmTransmitterDeviceAddressInSharedUserDefaults
        
        // add observer for shared userdefaults key keyForcgmTransmitterDeviceAddressInSharedUserDefaults - if value of transmitter device address changes, it means xDrip4iOS did connect to a new CGM - bluetoothTransmitter must be reinitialized
        client?.shared?.addObserver(self, forKeyPath: xDripClient.keyForcgmTransmitterDeviceAddressInSharedUserDefaults, context: nil)
        
        // see if bluetoothTransmitter needs to be instantiated
        bluetoothTransmitter = setupBluetoothTransmitter()
        
        // set heartbeat state text in userdefaults, this is used in the UI
        setHeartbeatStateText()

    }
    
    private enum Config {
        static let filterNoise = 2.5
    }
    
    public var useFilter = true

    required convenience public init?(rawState: CGMManager.RawStateValue) {
        self.init()
    }

    public var rawState: CGMManager.RawStateValue {
        return [:]
    }

    public var client: xDripClient?
    
    public static let localizedTitle = LocalizedString("xDrip4iO5", comment: "Title for the CGMManager option")

    public let appURL: URL? = URL(string: "xdripswift://")

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }
    
    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }
    
    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    
    public var shouldSyncToRemoteService: Bool {
        get {
            return UserDefaults.standard.shouldSyncToRemoteService
        }
    }
    
    public var providesBLEHeartbeat: Bool {
        get {
            return UserDefaults.standard.useCGMAsHeartbeat
        }
    }

    public var sensorState: SensorDisplayable? {
        return latestBackfill
    }

    public let managedDataInterval: TimeInterval? = nil
    
    public private(set) var latestBackfill: Glucose?
    
    public var latestCollector: String? {
        if let glucose = latestBackfill, let collector = glucose.collector, collector != "unknown" {
            return collector
        }
        return nil
    }

    /// for use in trace
    private let categoryxDripCGMManager      =        "xDripClient.xDripCGMManager"
    
    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {

        // check if bluetoothTransmitter is still valid - used for heartbeating
        checkCGMBluetoothTransmitter()
        
        guard let manager = self.client else {
            self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
            return
        }
        
        // If our last glucose was less than 0.5 minutes ago, don't fetch.
        if let latestGlucose = self.latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 0.5) {
            self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
            return
        }
        
        do {
            
            let glucose = try manager.fetchLastBGs(60)
            
            guard !glucose.isEmpty else {
                self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
                return
            }
            
            // Ignore glucose readings that are more than 65 minutes old
            let last_65_min_glucose = glucose.filterDateRange( Date( timeInterval: -TimeInterval(minutes: 65), since: Date() ), nil )
            
            
            guard !last_65_min_glucose.isEmpty else {
                self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
                return
            }
            
            
            var filteredGlucose = last_65_min_glucose
            if self.useFilter {
                var filter = KalmanFilter(stateEstimatePrior: Double(last_65_min_glucose.last!.glucose), errorCovariancePrior: Config.filterNoise)
                filteredGlucose.removeAll()
                for var item in last_65_min_glucose.reversed() {
                    let prediction = filter.predict(stateTransitionModel: 1, controlInputModel: 0, controlVector: 0, covarianceOfProcessNoise: Config.filterNoise)
                    let update = prediction.update(measurement: Double(item.glucose), observationModel: 1, covarienceOfObservationNoise: Config.filterNoise)
                    filter = update
                    let signed_glucose = Int(filter.stateEstimatePrior.rounded())
                    
                    // I don't think that the Kalman filter should ever produce BG values outside of the valid range - just to be on the safe side
                    // this does also prevent negative glucose values from being cast to UInt16
                    guard ( ( ( signed_glucose >= 39 ) && ( signed_glucose <= 500 ) ) ) else {
                        self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
                        return
                    }
                    
                    item.glucose = UInt16(signed_glucose)
                    filteredGlucose.append(item)
                }
                filteredGlucose = filteredGlucose.reversed()
            }

            
            var startDate: Date?
            
            if let latestGlucose = self.latestBackfill {
                startDate = latestGlucose.startDate
            }
            else {
                startDate = self.delegate.call { (delegate) -> Date? in
                    return delegate?.startDateToFilterNewData(for: self)
                }
            }
        
            let newGlucose = filteredGlucose.filterDateRange(startDate, nil)
            
            let newSamples = newGlucose.filter({ $0.isStateValid }).map {
                return NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: false, syncIdentifier: "\(Int($0.startDate.timeIntervalSince1970))", device: self.device)
            }
                       
            self.latestBackfill = newGlucose.first
            
            guard !newSamples.isEmpty else {
                self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
                return
            }

            self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .newData(newSamples)) }

        } catch let error {
            
            if let error = error as? ClientError {

                switch error {
                case .dataError (let text):
                    trace("in fetchNewDataIfNeeded, failed to get readings, error = %{public}@", category: categoryxDripCGMManager, text)
                case .fetchError:
                    trace("in fetchNewDataIfNeeded, failed to get readings, error = fetcherror", category: categoryxDripCGMManager)
                case .dateError:
                    trace("in fetchNewDataIfNeeded, failed to get readings, error = dateError", category: categoryxDripCGMManager)
                }

            } else {
                trace("in fetchNewDataIfNeeded, failed to get readings", category: categoryxDripCGMManager)
            }
            
            self.delegate.notify { (delegate) in delegate?.cgmManager(self, didUpdateWith: .noData) }
            
        }
        
    }
    
    public var device: HKDevice? {
        
        return HKDevice(
            name: "xDripClient",
            manufacturer: "xDrip",
            model: latestCollector,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    public override var debugDescription: String {
        return [
            "## xDripClientManager",
            "latestBackfill: \(String(describing: latestBackfill))",
            "latestCollector: \(String(describing: latestCollector))",
            ""
        ].joined(separator: "\n")
    }
    
    // override to observe useCGMAsHeartbeat and keyForcgmTransmitterDeviceAddressInSharedUserDefaults
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if let keyPath = keyPath {
            
            if let keyPathEnum = UserDefaults.Key(rawValue: keyPath) {
                
                switch keyPathEnum {
                    
                case UserDefaults.Key.useCGMAsHeartbeat :
                    bluetoothTransmitter = setupBluetoothTransmitter()
                    
                    setHeartbeatStateText()
                    
                default:
                    break
                    
                }
            } else {
                
                if keyPath == xDripClient.keyForcgmTransmitterDeviceAddressInSharedUserDefaults {
                    
                    checkCGMBluetoothTransmitter()
                    
                    setHeartbeatStateText()
                    
                }
                
            }
        }
    }

    /// check if a new bluetoothTransmitter needs to be assigned and if yes, assign it
    private func checkCGMBluetoothTransmitter() {
        
        if UserDefaults.standard.cgmTransmitterDeviceAddress != client?.cgmTransmitterDeviceAddressInSharedUserDefaults {
            
            // assign new bluetoothTransmitter. If return value is nil, and if it was not nil before, and if it was currently connected then it will disconnect automatically, because there's no other reference to it, hence deinit will be called
            bluetoothTransmitter = setupBluetoothTransmitter()
            
            // assign local copy of cgmTransmitterDeviceAddress to the value stored in sharedUserDefaults (possibly nil value)
            UserDefaults.standard.cgmTransmitterDeviceAddress = client?.cgmTransmitterDeviceAddressInSharedUserDefaults

            setHeartbeatStateText()
            
        }
        
    }
    
    /// will call fetchNewDataIfNeeded with completionhandler
    /// used as heartbeat function
    private func fetchNewDataIfNeeded() {
        
        self.fetchNewDataIfNeeded { result in
            // no need to process the result, it's already processed in fetchNewDataIfNeeded and sent to delegate
        }

    }

    /// if UserDefaults.standard.useCGMAsHeartbeat is true and sharedUserDefaults.cgmTransmitterDeviceAddress  then create new BluetoothTransmitter
    private func setupBluetoothTransmitter() -> BluetoothTransmitter? {
        
        // if sharedUserDefaults.cgmTransmitterDeviceAddress is not nil then, create a new bluetoothTranmsitter instance
        if UserDefaults.standard.useCGMAsHeartbeat, let cgmTransmitterDeviceAddress = client?.cgmTransmitterDeviceAddressInSharedUserDefaults {
            
            // unwrap cgmTransmitter_CBUUID_Service and cgmTransmitter_CBUUID_Receive
            if let cgmTransmitter_CBUUID_Service = client?.cgmTransmitter_CBUUID_ServiceInSharedUserDefaults, let cgmTransmitter_CBUUID_Receive = client?.cgmTransmitter_CBUUID_ReceiveInSharedUserDefaults {

                // a new cgm transmitter has been setup in xDrip4iOS
                // we will connect to the same transmitter here so it can be used as heartbeat
                let newBluetoothTransmitter = BluetoothTransmitter(deviceAddress: cgmTransmitterDeviceAddress, servicesCBUUID: cgmTransmitter_CBUUID_Service, CBUUID_Receive: cgmTransmitter_CBUUID_Receive, onHeartBeatStatusChange: setHeartbeatStateText, heartbeat: fetchNewDataIfNeeded)
                
                return newBluetoothTransmitter

            } else {
                
                trace("in setupBluetoothTransmitter, looks like a coding error, xdrip4iOS did set a value for cgmTransmitterDeviceAddress in sharedUserDefaults but did not set a value for cgmTransmitter_CBUUID_Service or cgmTransmitter_CBUUID_Receive", category: categoryxDripCGMManager)
                
                return nil
                
            }
            
        }
        
        return nil

    }
    
    /// will set text in UserDefaults heartBeatState depending on BluetoothTransmitter status, this is then used in UI
    private func setHeartbeatStateText() {

        let scanning = LocalizedString("Scanning for CGM. Force close xDrip4iOS (do not disconnect but force close the app). Keep Loop running in the foreground (prevent phone lock). This text will change as soon as a first connection is made. ", comment: "This is when Loop did not yet make a first connection to the CGM. It is scanning. Need to make sure that no other app (like xDrip4iOS) is connected to the CGM")
        
        let firstConnectionMade = LocalizedString("Did connect to CGM. You can now run both xDrip4iOS and Loop. The CGM will be used as heartbeat for Loop.", comment: "Did connect to CGM. Even though it's not connected now, this state remains valid. The CGM will be used as heartbeat for Loop.")
        
        let cgmUnknown = LocalizedString("You first need to have made a successful connection between xDrip4iOS and the CGM. Force close Loop, open xDrip4iOS and make sure it's connected to the CGM. Once done, Force close xDrip4iOS (do not disconnect but force close the app), open Loop and come back to here", comment: "There hasn't been a connectin to xDrip4iOS to the CGM. First need to have a made a successful connection between xDrip4iOS and the CGM. Force close Loop, open xDrip4iOS and make sure it's connected to the CGM. Once done, Force close xDrip4iOS (do not disconnect but force close the app), open Loop and come back to here")
        
        // in case user has selected not to use cgm as heartbeat
        if !UserDefaults.standard.useCGMAsHeartbeat {
            UserDefaults.standard.heartBeatState = nil
            return
        }
        
        // in case xDrip4iOS did not make a first connection to the CGM (or explicitly disconnected from the CGM)
        if UserDefaults.standard.cgmTransmitterDeviceAddress == nil {
            UserDefaults.standard.heartBeatState = cgmUnknown
            return
        }
        
        // now there should be a bluetoothTransmitter, if not there's a coding error
        guard let bluetoothTransmitter = bluetoothTransmitter else {
            UserDefaults.standard.heartBeatState = nil
            return
        }

        // if peripheral in bluetoothTransmitter is still nil, then it means Loop is still scanning for the CGM, it didn't make a first connection yet
        if bluetoothTransmitter.peripheral == nil {
            UserDefaults.standard.heartBeatState = scanning
            return
        }
        
        // in all other cases, the state should be ok
        UserDefaults.standard.heartBeatState = firstConnectionMade
        
    }

    @objc private func runWhenAppWillEnterForeground(_ : Notification) {
        
        fetchNewDataIfNeeded()
        
    }

}
