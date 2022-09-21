import Foundation

extension UserDefaults {
    
    public enum Key: String {
        
        /// used as local copy of cgmTransmitterDeviceAddress, will be compared regularly against value in shared UserDefaults
        ///
        /// this is the local stored (ie not shared with xDrip4iOS) copy of the cgm (bluetooth) device address
        case cgmTransmitterDeviceAddress = "cgmTransmitterDeviceAddress"
        
        /// did user ask heartbeat from CGM that is used by xDrip4iOS, default false
        case useCGMAsHeartbeat = "useCGMAsHeartbeat"
        
        /// status of freeaps vs CGM, this is text shown to user in UI. Text shows the status of heartbeat
        case heartBeatState = "heartBeatState"
        
        /// should freepas upload bg readings to remote service or not. Default false
        case shouldSyncToRemoteService = "shouldSyncToRemoteService"
        
    }

    /// used as local copy of cgmTransmitterDeviceAddress, will be compared regularly against value in shared UserDefaults
    var cgmTransmitterDeviceAddress: String? {
        get {
            return string(forKey: Key.cgmTransmitterDeviceAddress.rawValue)
        }
        set {
            set(newValue, forKey: Key.cgmTransmitterDeviceAddress.rawValue)
        }
    }
 
    /// should freeaps upload bg readings to remote service or not. Default false
    @objc dynamic public var shouldSyncToRemoteService: Bool {
        
        // default value for bool in userdefaults is false
        get {
            return bool(forKey: Key.shouldSyncToRemoteService.rawValue)
        }
        set {
            set(newValue, forKey: Key.shouldSyncToRemoteService.rawValue)
        }
        
    }

    /// did user ask heartbeat from CGM that is used by xDrip4iOS, default : true
    @objc public dynamic var useCGMAsHeartbeat: Bool {
        
        // default value for bool in userdefaults is false, by default we want to use heartbeat
        get {
            return bool(forKey: Key.useCGMAsHeartbeat.rawValue)
        }
        set {
            set(newValue, forKey: Key.useCGMAsHeartbeat.rawValue)
        }
        
    }
    
    /// status of freeaps vs CGM, see enum HeartBeatState for description
    @objc public dynamic var heartBeatState: String? {
        
        // default value for bool in userdefaults is false, by default we want to use heartbeat
        get {
            return string(forKey: Key.heartBeatState.rawValue)
        }
        set {
            set(newValue, forKey: Key.heartBeatState.rawValue)
        }
        
    }
    
}
