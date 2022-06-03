//
//  xDripClient.swift
//  xDripClient
//
//  Created by Mark Wilson on 5/7/16.
//  Copyright © 2016 Mark Wilson. All rights reserved.
//

import Foundation
import Combine

public enum ClientError: Error {
    case fetchError
    case dataError(reason: String)
    case dateError
}


public class xDripClient {
    
    public let shared: UserDefaults?
    
    /// key for shared userdefaults - the bluetooth device address to which Loop will connect, in order to get a heartbeat
    public static let keyForcgmTransmitterDeviceAddressInSharedUserDefaults = "cgmTransmitterDeviceAddress"

    /// the mac address of the cgm to which xDrip4iOS is connecting. Nil if none defined
    /// - set by xdrip4ios. xDripClient will need to read it regularly to check if it has changed
    public var cgmTransmitterDeviceAddressInSharedUserDefaults: String? {
        
        return shared?.string(forKey: xDripClient.keyForcgmTransmitterDeviceAddressInSharedUserDefaults)

    }

    /// key for shared userdefaults - the service uuid of the device to which Loop will connect, in order to get a heartbeat
    public static let keyForCgmTransmitter_CBUUID_ServiceInSharedUserDefaults = "cgmTransmitter_CBUUID_Service"

    /// the service uuid of the device to which Loop will connect, in order to get a heartbeat
    /// - set by xdrip4ios. xDripClient will need to read it regularly to check if it has changed
    public var cgmTransmitter_CBUUID_ServiceInSharedUserDefaults: String? {
        
        if let service_UUID = shared?.string(forKey: xDripClient.keyForCgmTransmitter_CBUUID_ServiceInSharedUserDefaults) {
            return service_UUID
        } else {
            return nil
        }
        
    }

    /// key for shared userdefaults - receive characteristic uuid of the device to which Loop will connect, in order to get a heartbeat
    public static let keyForCgmTransmitter_CBUUID_ReceiveInSharedUserDefaults = "cgmTransmitter_CBUUID_Receive"

    /// the receive characteristic uuid of the device to which Loop will connect, in order to get a heartbeat
    /// - set by xdrip4ios. xDripClient will need to read it regularly to check if it has changed
    public var cgmTransmitter_CBUUID_ReceiveInSharedUserDefaults: String? {
        
        if let receive_UUID = shared?.string(forKey: xDripClient.keyForCgmTransmitter_CBUUID_ReceiveInSharedUserDefaults) {
            return receive_UUID
        } else {
            return nil
        }
        
    }

    public init(_ group: String? = Bundle.main.appGroupSuiteName) {
        shared = UserDefaults.init(suiteName: group)
    }
    
    public func fetchLastBGs(_ n: Int) throws -> Array<Glucose> {
        
        do
        {
            guard let sharedData = shared?.data(forKey: "latestReadings") else {
                throw ClientError.fetchError
            }
        
            let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
            guard let sgvs = decoded as? Array<AnyObject> else {
                    throw ClientError.dataError(reason: "Failed to decode SGVs as array from recieved data.")
            }
        

            var transformed: Array<Glucose> = []
            for sgv in sgvs.prefix(n) {
                // Collector might not be available
                var collector : String? = nil
                if let _col = sgv["Collector"] as? String {
                    collector = _col
                }
                
                if let glucose = sgv["Value"] as? Int, let trend = sgv["Trend"] as? Int, let dt = sgv["DT"] as? String, let from = sgv["from"] as? String {
                    
                          
                    // only add glucose readings in a valid range - skip unrealistically low or high readings
                    // this does also prevent negative glucose values from being cast to UInt16
                    if ( ( ( glucose >= 39 ) && ( glucose <= 500 ) && from == "xDrip") ) {
                    
                    transformed.append(Glucose(
                        glucose: UInt16(glucose),
                        trend: UInt8(trend),
                        timestamp: try self.parseDate(dt),
                        collector: collector
                    ))
                        
                    }
                } else {
                    throw ClientError.dataError(reason: "Failed to decode an SGV record.")
                }
            }
            
            return transformed
            
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.fetchError
        }
    }

    private func parseDate(_ wt: String) throws -> Date {
        // wt looks like "/Date(1462404576000)/"
        let re = try NSRegularExpression(pattern: "\\((.*)\\)")
        if let match = re.firstMatch(in: wt, range: NSMakeRange(0, wt.count)) {
            #if swift(>=4)
                let matchRange = match.range(at: 1)
            #else
                let matchRange = match.rangeAt(1)
            #endif
            let epoch = Double((wt as NSString).substring(with: matchRange))! / 1000
            return Date(timeIntervalSince1970: epoch)
        } else {
            throw ClientError.dateError
        }
    }
}

extension Bundle {
    public var appGroupSuiteName: String {
        return object(forInfoDictionaryKey: "AppGroupIdentifier") as! String
    }
}
