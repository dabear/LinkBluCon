//
//  ViewController.swift
//  LinkBluCon
//
//  Created by Gorugantham, Ramu Raghu Vams on 1/26/17.
//  Copyright © 2017 Gorugantham, Ramu Raghu Vams. All rights reserved.
//

import UIKit
import BlueCapKit

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, BluConDeviceManagerDelegate {
    
    @IBOutlet weak var peripheralsTableView: UITableView!
    
    @IBOutlet weak var scanButton: UIButton!
    
    @IBOutlet weak var postConnectionDeviceNameLabel: UILabel!
    @IBOutlet weak var postConnectionDeviceStatusLabel: UILabel!
    var devicesDiscovered:[Peripheral] = [Peripheral]()
    let bluConManager = BluConDeviceManager.sharedInstance
    var connectedPeripheral: Peripheral?
    var deviceReadyForScanning: Bool = false
    var deviceRecentlyDisconnected: Bool = false
    var dataFromBluConDevice = [String]()
    var mode: DeviceMode = .deviceScanning
    var fab = KCFloatingActionButton()
    
    enum DeviceMode {
        case deviceScanning, readingData
    }
    
    @IBAction func addBluetoothDevice(_ sender: Any) {
        if deviceReadyForScanning {
            bluConManager.scanForPeripherals()
        }
    }
    
    func initialSetup() {
        peripheralsTableView.delegate = self
        peripheralsTableView.dataSource = self
        peripheralsTableView.layer.borderColor = self.view.tintColor.cgColor
        peripheralsTableView.layer.borderWidth = 2.0
        let config = KVNProgressConfiguration.default()
        config?.isFullScreen = true
        postConnectionDeviceNameLabel.isHidden = true
        postConnectionDeviceStatusLabel.isHidden = true
        KVNProgress.setConfiguration(config)
        devicesDiscovered.removeAll()
        dataFromBluConDevice.removeAll()
        mode = .deviceScanning
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initialSetup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        initialUIElements()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        bluConManager.delegate = self
        bluConManager.start()
        KVNProgress.show(withStatus: "Loading, Please wait...")
        scanButton.titleLabel?.font = UIFont(name: "HelveticaNeue-Light", size: 17.0)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: TableViewDelegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (mode == .deviceScanning) ? devicesDiscovered.count : dataFromBluConDevice.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = UITableViewCell(style:.default, reuseIdentifier: "blucon")
        let value = (mode == .deviceScanning) ? devicesDiscovered[indexPath.row].name : dataFromBluConDevice[indexPath.row]
        cell.textLabel?.text = value
        cell.textLabel?.numberOfLines = 0
        if let text = cell.textLabel?.text?.lowercased(), text.contains("reading data from device") {
            cell.textLabel?.textAlignment = .center
        }
        cell.textLabel?.font = UIFont(name: "HelveticaNeue-Light", size: 15.0)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell: UITableViewCell = tableView.cellForRow(at: indexPath)!
        cell.setSelected(false, animated: true)
        
        if mode == .readingData {
            return
        }
        
        bluConManager.stopScanForPeripherals()
        KVNProgress.show(withStatus: "Connecting to \(devicesDiscovered[indexPath.row].name)...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("device selected" + self.devicesDiscovered[indexPath.row].name)
            self.bluConManager.connectToPeripheral(peripheral: self.devicesDiscovered[indexPath.row])
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    
    // MARK:BluConDeviceManagerDelegate
    func didStartWithDeviceStatus(status: DeviceStatus) {
        initialUIElements()
        switch status {
        case .ready:
            self.deviceReadyForScanning = true
            self.deviceIsReadyFn()
        case .poweredOff, .unknown:
            self.showAlertForDeviceStatus(showSettingsButton: true, status: status)
        default:
            self.showAlertForDeviceStatus(status: status)
        }
        print(status.toString())
    }
    
    func didStartWithError(error: Error) {
        print("error occured when starting the device manager")
        deviceReadyForScanning = false
    }
    func didDiscoverBluConPeripherals(peripherals: [Peripheral]) {
        devicesDiscovered = peripherals
        peripheralsTableView.reloadData()
    }
    
    func peripheralConnected(peripheral: Peripheral) {
        connectedPeripheral = peripheral
    }
    
    func peripheralDisconnected(status: PeripheralError) {
        if mode == .readingData {
            postConnectionDeviceStatusLabel.text = "Status : Disconnected"
        }
        connectedPeripheral = nil
        let str = PeripheralErrorToString(error: status)
        if str != "" {
            KVNProgress.showError(withStatus: "BLUCON device disconnected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                KVNProgress.dismiss()
            }
        }
    }
    
    func didStartListeningToCharacteristicNotifications(status: Bool) {
        
        dataFromBluConDevice.removeAll()
        let peripheralName = self.connectedPeripheral?.name
        dataFromBluConDevice.append("Reading data from device - \(peripheralName!)")
        
        KVNProgress.showSuccess(withStatus: (deviceRecentlyDisconnected) ? "BLUCON device re-connected." : "BLUCON device connected.")
        deviceRecentlyDisconnected = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            
            self.mode = .readingData
            if self.mode == .readingData {
                self.postConnectionDeviceStatusLabel.text = "Status : Connected"
                self.postConnectionDeviceNameLabel.text = "Device Name : \(peripheralName!)"
            }
            self.toggleMode()
            self.addFabButton()
            self.peripheralsTableView.reloadData()
            KVNProgress.dismiss()
            
        }
        
        print("started listening to characteristics")
    }
    
    func toggleMode() {
        postConnectionDeviceNameLabel.isHidden = (mode == .deviceScanning)
        postConnectionDeviceStatusLabel.isHidden = (mode == .deviceScanning)
        scanButton.isHidden = (mode == .readingData)
    }
    
    func reconnectingBluConDevice() {
        KVNProgress.show(withStatus: "Reconnecting to the  device...")
        self.postConnectionDeviceStatusLabel.text = "Status : Disconnected"
        deviceRecentlyDisconnected = true
    }
    
    func didReceiveUpdateValueFromPeripheral(hexString: String) {
        print("value received - \(hexString)")
        let timeStamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        dataFromBluConDevice.append("\(timeStamp)" + "  :  " + hexString)
        peripheralsTableView.reloadData()
    }
    
    // MARK: Helper Fns
    private func deviceIsReadyFn() {
        KVNProgress.showSuccess(withStatus: "Device is ready for scanning")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.scanButton.isHidden = false
            self.peripheralsTableView.isHidden = false
            KVNProgress.dismiss()
        }
    }
    
    private func initialUIElements() {
        self.scanButton.isHidden = true
        self.peripheralsTableView.isHidden = true
        KVNProgress.dismiss()
    }
    
    private func showAlertForDeviceStatus(showSettingsButton: Bool = false, status: DeviceStatus) {
        let alertController: UIAlertController = UIAlertController(title: "Device Status", message: status.toString(), preferredStyle: .alert)
        let cancelAction: UIAlertAction = UIAlertAction(title: "Cancel", style: .cancel) { action -> Void in
        }
        let settingsAction: UIAlertAction = UIAlertAction.init(title: "Settings", style: .default, handler: { (action) in
            let url = NSURL(string: "App-Prefs:root=Bluetooth")
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url as! URL, options: [:], completionHandler: nil)
            } else {
                // Fallback on earlier versions
                UIApplication.shared.openURL(url as! URL)
            }
        })
        alertController.addAction(cancelAction)
        if showSettingsButton {
            alertController.addAction(settingsAction)
        }
        self.present(alertController, animated: true, completion: nil)
    }
    
    private func PeripheralErrorToString(error: PeripheralError) -> String {
        switch error {
        case .connectionTimeout:
            return "Connection Time out. Please try again."
        case .disconnected:
            return "Device is disconnected."
        case .serviceDiscoveryTimeout:
            return "Error connecting to the device. Connection timed out."
        case .forcedDisconnect:
            return "Device is diconnected (by force)."
        }
    }
    
    private func addFabButton() {
        fab.buttonImage = UIImage(named: "custom-add")?.withRenderingMode(.alwaysOriginal)
        let image = UIImage(named: "bluetooth")?.withRenderingMode(.alwaysTemplate)
        fab.addItem("Scan for devices", icon: image) { item in
            KVNProgress.show(withStatus: "Disconnecting device ...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.connectedPeripheral?.disconnect()
                self.mode = .deviceScanning
                self.dataFromBluConDevice.removeAll()
                self.devicesDiscovered.removeAll()
                self.toggleMode()
                self.peripheralsTableView.reloadData()
                self.removeFabButton()
                KVNProgress.dismiss()
            }
        }
        fab.sticky = true
        self.view.addSubview(fab)
    }
    
    private func removeFabButton() {
        fab.removeItem(index: 0)
        fab.removeFromSuperview()
    }
    
}

