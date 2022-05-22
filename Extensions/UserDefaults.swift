import Foundation

extension UserDefaults {
    
    public enum Key: String {
        
        /// used as local copy of cgmTransmitterDeviceAddress, will be compared regularly against value in shared UserDefaults
        ///
        /// this is the local stored (ie not shared with xDrip4iOS) copy of the cgm (bluetooth) device address
        case cgmTransmitterDeviceAddress = "cgmTransmitterDeviceAddress"
        
        /// did user ask heartbeat from CGM that is used by xDrip4iOS, default : true
        case useCGMAsHeartbeat = "useCGMAsHeartbeat"
        
        /// status of Loop vs CGM, see enum HeartBeatState for description
        case heartBeatState = "heartBeatState"
        
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
    
    /// status of Loop vs CGM, see enum HeartBeatState for description
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
