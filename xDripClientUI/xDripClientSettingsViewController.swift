//
//  xDripClientSettingsViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopKit
import LoopKitUI
import xDripClient
import MessageUI

public class xDripClientSettingsViewController: UITableViewController {
    
    public let cgmManager: xDripClientManager
    
    public let glucoseUnit: HKUnit
    
    public let allowsDeletion: Bool
    
    public init(cgmManager: xDripClientManager, glucoseUnit: HKUnit, allowsDeletion: Bool) {
        self.cgmManager = cgmManager
        self.glucoseUnit = glucoseUnit
        self.allowsDeletion = allowsDeletion
        
        super.init(style: .grouped)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        title = cgmManager.localizedTitle
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44
        
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        tableView.estimatedSectionHeaderHeight = 55
        
        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.className)
        
        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        self.navigationItem.setRightBarButton(button, animated: false)
        
        // add observer for heartBeatState, this is a text that will be shown in the heartBeat section. We need to observe the value
        UserDefaults.standard.addObserver(self, forKeyPath: UserDefaults.Key.heartBeatState.rawValue, options: .new, context: nil)

    }
    
    @objc func doneTapped(_ sender: Any) {
        complete()
    }
    
    private func complete() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
    }
    
    // override to observe useCGMAsHeartbeat and keyForcgmTransmitterDeviceAddressInSharedUserDefaults
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if let keyPath = keyPath {
            
            if let keyPathEnum = UserDefaults.Key(rawValue: keyPath) {
                
                switch keyPathEnum {
                    
                case UserDefaults.Key.heartBeatState :
                    tableView.reloadData()
                    
                default:
                    break
                }
                
            }
        }
    }

    // MARK: - UITableViewDataSource
    
    private enum Section: Int, CaseIterable {
        case latestReading
        case heartbeat
        case syncToRemoveService
        case delete
    }
    
    override public func numberOfSections(in tableView: UITableView) -> Int {
        return allowsDeletion ? Section.allCases.count : Section.allCases.count - 1
    }
    
    private enum LatestReadingRow: Int, CaseIterable {
        case glucose
        case date
        case trend
    }
    
    private enum HeartBeatRow: Int, CaseIterable {
        case useCgmAsHeartbeat
    }
    
    private enum SyncToRemoteServiceRow: Int, CaseIterable {
        case shouldSyncToRemoveService
    }
    
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LatestReadingRow.allCases.count
        case .heartbeat:
            return HeartBeatRow.allCases.count
        case .syncToRemoveService:
            return SyncToRemoteServiceRow.allCases.count
        case .delete:
            return 1
        }
    }
    
    private lazy var glucoseFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: glucoseUnit)
        return formatter
    }()
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
    
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .latestReading:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let glucose = cgmManager.latestBackfill
            
            cell.accessoryView = nil
            
            switch LatestReadingRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.textLabel?.text = LocalizedString("Glucose", comment: "Title describing glucose value")
                
                if let quantity = glucose?.quantity, let formatted = glucoseFormatter.string(from: quantity, for: glucoseUnit) {
                    cell.detailTextLabel?.text = formatted
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            case .date:
                cell.textLabel?.text = LocalizedString("Date", comment: "Title describing glucose date")
                
                if let date = glucose?.timestamp {
                    cell.detailTextLabel?.text = dateFormatter.string(from: date)
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            case .trend:
                cell.textLabel?.text = LocalizedString("Trend", comment: "Title describing glucose trend")
                
                cell.detailTextLabel?.text = glucose?.trendType?.localizedDescription ?? SettingsTableViewCell.NoValueString
            }
            
            return cell
        case .delete:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            
            cell.textLabel?.text = LocalizedString("Delete CGM", comment: "Title text for the button to remove a CGM from Loop")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true
            return cell
            
        case .heartbeat:
            
            // row to enable or disable use CGM as heartbeat.
            // shows text + UISwitch
            
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            cell.textLabel?.text = LocalizedString("Use CGM as heartbeat", comment: "The title text for the cgm heartbeat enabled switch cell")
            
            // create UISwitch to toggle the value of UserDefaults.standard.useCGMAsHeartbeat
            let useCgmAsHeartBeatUISwitch  = UISwitch(frame: CGRect.zero) as UISwitch
            useCgmAsHeartBeatUISwitch.isOn = UserDefaults.standard.useCGMAsHeartbeat
            useCgmAsHeartBeatUISwitch.addTarget(self, action: #selector(useCGMAsHeartbeatSwitchTriggered), for: .valueChanged)
            useCgmAsHeartBeatUISwitch.tag = indexPath.row
            
            cell.accessoryView = useCgmAsHeartBeatUISwitch
            return cell

        case .syncToRemoveService:
            
            // row to enable or disable sync to remote service
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            cell.textLabel?.text = LocalizedString("Loop should sync to remote service", comment: "The title text for sync to remote service enabled switch cell")
            
            // create UISwitch to toggle the value of UserDefaults.standard.shouldSyncToRemoteService
            let shouldSyncToRemoteServiceUISwitch  = UISwitch(frame: CGRect.zero) as UISwitch
            shouldSyncToRemoteServiceUISwitch.isOn = UserDefaults.standard.shouldSyncToRemoteService
            shouldSyncToRemoteServiceUISwitch.addTarget(self, action: #selector(shouldSyncToRemoteServiceSwitchTriggered), for: .valueChanged)
            shouldSyncToRemoteServiceUISwitch.tag = indexPath.row
            
            cell.accessoryView = shouldSyncToRemoteServiceUISwitch
            return cell

        }
    }
    
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
            
        case .heartbeat:
            return UserDefaults.standard.heartBeatState
        default:
            return nil
        }
        
    }
    
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LocalizedString("Latest Reading", comment: "Section title for latest glucose reading")
        case .delete:
            return nil
        case .heartbeat:
            return LocalizedString("Heartbeat", comment: "Section title for heartbeat info")
        case .syncToRemoveService:
            return LocalizedString("Sync", comment: "Section title for sync to remote service section")
        }
    }
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .latestReading:
            tableView.deselectRow(at: indexPath, animated: true)
        case .delete:
            let confirmVC = UIAlertController(cgmDeletionHandler: {
                self.cgmManager.notifyDelegateOfDeletion {
                    DispatchQueue.main.async {
                        self.complete()
                    }
                }
            })
            
            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        case .heartbeat:
            break
            
        case .syncToRemoveService:
            break
            
        }
    }
    
    @objc private func useCGMAsHeartbeatSwitchTriggered(sender: UISwitch) {
        UserDefaults.standard.useCGMAsHeartbeat = sender.isOn
    }
    
    @objc private func shouldSyncToRemoteServiceSwitchTriggered(sender: UISwitch) {
        UserDefaults.standard.shouldSyncToRemoteService = sender.isOn
    }

}


private extension UIAlertController {
    convenience init(cgmDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to delete this CGM?", comment: "Confirmation message for deleting a CGM"),
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: LocalizedString("Delete CGM", comment: "Button title to delete CGM"),
            style: .destructive,
            handler: { (_) in
                handler()
        }
        ))
        
        let cancel = LocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
    }
}

extension xDripClientSettingsViewController: MFMailComposeViewControllerDelegate {
    
    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        
        controller.dismiss(animated: true)
        
    }
    
}
