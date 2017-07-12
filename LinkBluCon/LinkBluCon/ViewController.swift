//
//  ViewController.swift
//  LinkBluCon
//
//  Created by Gorugantham, Ramu Raghu Vams on 1/26/17.
//  Copyright © 2017 Gorugantham, Ramu Raghu Vams. All rights reserved.
//

import UIKit
import BlueCapKit
import CoreFoundation

class NonRotatingNavigationController : UINavigationController {
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    override var shouldAutorotate: Bool {
        return false
    }
}

extension UITableView {
    func reloadData(with animation: UITableViewRowAnimation) {
        reloadSections(IndexSet(integersIn: 0..<numberOfSections), with: animation)
    }
}


class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, BluConDeviceManagerDelegate {
    
    @IBOutlet weak var peripheralsTableView: UITableView!
    
    @IBOutlet weak var scanButton: UIButton!
    
    @IBOutlet weak var postConnectionDeviceNameLabel: UILabel!
    @IBOutlet weak var postConnectionDeviceStatusLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    var devicesDiscovered:[Peripheral] = [Peripheral]()
    let bluConManager = BluConDeviceManager.sharedInstance
    var connectedPeripheral: Peripheral?
    var deviceReadyForScanning: Bool = false
    var deviceRecentlyDisconnected: Bool = false
    var dataFromBluConDevice = [String]()
    var mode: DeviceMode = .deviceScanning
    var fab = KCFloatingActionButton()
    let tapRecognizer = UITapGestureRecognizer()
    var finalvalue = NSMutableString()
    let decoder = BluConGlucoseDecoder.sharedInstance
    var trendValues = [[String: String]]()
    var historicValues = [[String: String]]()
    
    var sensorActiveTime = ""
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    
    enum DeviceMode {
        case deviceScanning, readingData, dataDecoded
    }
    
    @IBAction func addBluetoothDevice(_ sender: Any) {
        if deviceReadyForScanning {
            bluConManager.scanForPeripherals()
        }
    }
    
    func initialSetup() {
        peripheralsTableView.delegate = self
        peripheralsTableView.dataSource = self
//        decoder.delegate = self
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
    
    func invokeDebugMode() {
        print("debugMode")
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let controller = storyboard.instantiateViewController(withIdentifier: "demoNav")
        self.present(controller, animated: true, completion: nil)

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.statusBarStyle = .default
        initialSetup()
    }
    
    func timeStamp() -> String {
        return DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
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
        addDemoFabButton()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: TableViewDelegate
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if mode == .dataDecoded {
            return 2
        }
        else {
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if mode == .dataDecoded {
            if section == 0 {
                return "Trend Values"
            }
            else {
                return "Historic Values"
            }
        }
        else {
            return sensorActiveTime
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if mode == .dataDecoded {
            if section == 0 {
                return trendValues.count
            }
            else {
                return historicValues.count
            }
        }
        else {
            return (mode == .deviceScanning) ? devicesDiscovered.count : dataFromBluConDevice.count
        }
    }
    
    func getglucoseReading(data: [String:String]) -> String {
        if let key = data.keys.first {
            return data[key]! as String
        }
        else {
            return "invalid reading"
        }
    }
    
    func getMinutesData(data: [String:String]) -> String {
        var str = "invalid time"
        if let key = data.keys.first {
            if key.isNumeric {
                str = "\(key) min"
            } else {
                str = key as String
            }
            
        }
        return str
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = UITableViewCell(style:.default, reuseIdentifier: "blucon")
        var value = ""
        if mode == .dataDecoded {
            if indexPath.section == 0 {
                value = "Time: \(getMinutesData(data: trendValues[indexPath.row]))     |     Glucose: \(getglucoseReading(data: trendValues[indexPath.row]))"
            }
            else {
                value = "Time: \(getMinutesData(data: historicValues[indexPath.row]))     |     Glucose: \(getglucoseReading(data: historicValues[indexPath.row]))"
            }
        }
        else {
            value = (mode == .deviceScanning) ? devicesDiscovered[indexPath.row].name : dataFromBluConDevice[indexPath.row]
        }
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
        
        if mode == .readingData || mode == .dataDecoded{
            return
        }
        
        bluConManager.stopScanForPeripherals()
        KVNProgress.show(withStatus: "Connecting to \(devicesDiscovered[indexPath.row].name)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("device selected" + self.devicesDiscovered[indexPath.row].name)
            self.bluConManager.connectToPeripheral(peripheral: self.devicesDiscovered[indexPath.row])
            print("device connected I think")
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
        self.devicesDiscovered = Array<Peripheral>(Set<Peripheral>(peripherals))
        peripheralsTableView.reloadData(with: .right)
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
        
        KVNProgress.showSuccess(withStatus: (deviceRecentlyDisconnected) ? "BLUCON device re-connected." : "\(peripheralName!) connected.")
        deviceRecentlyDisconnected = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            
            self.mode = .readingData
            if self.mode == .readingData {
                self.postConnectionDeviceStatusLabel.text = "Status : Connected"
                self.postConnectionDeviceNameLabel.text = "Device Name : \(peripheralName!)"
            }
            self.toggleMode()
            self.addFabButton()
            self.peripheralsTableView.reloadData(with: .right)
            KVNProgress.dismiss()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                KVNProgress.show(withStatus: "waiting for \(peripheralName!) to send data...")
            }
        }
        
        print(" \(self.timeStamp()) started listening to characteristics")
    }
    
    func toggleMode() {
        postConnectionDeviceNameLabel.isHidden = (mode == .deviceScanning)
        postConnectionDeviceStatusLabel.isHidden = (mode == .deviceScanning)
        scanButton.isHidden = (mode == .readingData)
    }
    
    func reconnectingBluConDevice() {
        KVNProgress.show(withStatus: "Reconnecting to the  \((connectedPeripheral?.name) ?? "BluCon")")
        self.postConnectionDeviceStatusLabel.text = "Status : Disconnected"
        deviceRecentlyDisconnected = true
    }
    
    func didUpdateSensorActiveTime(status: String) {
        KVNProgress.dismiss()
        sensorActiveTime = status
        let peripheralName = self.connectedPeripheral?.name
        if self.dataFromBluConDevice.count > 0 && self.dataFromBluConDevice[0] == "Reading data from device - \(peripheralName!)" {
            self.dataFromBluConDevice.remove(at: 0)
        }
        
//        if self.dataFromBluConDevice.count > 0 {
//                self.dataFromBluConDevice[0] = status
//            }
//            else {
//                self.dataFromBluConDevice.append(status)
//            }
    }
    
    func didReceiveUpdatedGlucoseValue(dateAndTime: String, value: String) {
        dataFromBluConDevice.append("\(dateAndTime)" + "  :  " + value + " mg/dl")
        peripheralsTableView.reloadData(with: .right)

    }
    
    func glucosePatchReadError() {
        print("patch read error.. please check the connectivity and re-initiate...")
            KVNProgress.showError(withStatus: "unable to read the patch... \nplease check & try again.", completion: {
                self.dataFromBluConDevice.removeAll()
                self.dataFromBluConDevice.append("unable to read the patch. please check & try again.")
                self.peripheralsTableView.reloadData(with: .right)
            })
    }
    
    /*
    func didReceiveUpdateValueFromPeripheral(hexString: String) {
        print("value received - \(hexString)")
        finalvalue.append(hexString)
        print("totalString: \(finalvalue)")
        let timeStamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        dataFromBluConDevice.append("\(timeStamp)" + "  :  " + hexString)
        peripheralsTableView.reloadData()
    }
    
    func didReceiveCompleteDataFromPeripheral(hexString: String) {
        // run the algo here
        finalvalue.setString("")
        finalvalue.append(hexString)
        trendValues.removeAll()
        historicValues.removeAll()
        peripheralsTableView.reloadData()
        decoder.decodeValuesForData(hexData: finalvalue as String)
    }
    
    func updateUIForDataSizeReceived(size: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            KVNProgress.show(withStatus: size, on: self.view)
        }
    }
    
    // MARK: Decoder Delegate 
    
    
    func didStartDecoding() {
        print("decoding started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            KVNProgress.show(withStatus: "Data conversion in progress...", on: self.view)
        }
    }
    func didFinishDecoding() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            KVNProgress.dismiss(completion: { 
                if self.trendValues.count > 0 && self.historicValues.count > 0 {
                    self.peripheralsTableView.reloadData()
                }
                self.peripheralsTableView.scrollsToTop = true
            })
        }
    }
    
    func updateTotalSensorActiveTime(status: String) {
        print(status)
    }
    
    func glucoseTrendValuesUpdated(data: [[String: String]]) {
        mode = .dataDecoded
        trendValues.removeAll()
        trendValues.append(contentsOf: data)
    }
    
    func glucoseHistoryValuesUpdated(data: [[String: String]]) {
        mode = .dataDecoded
        historicValues.removeAll()
        historicValues.append(contentsOf: data)
    }
    
    func currentGlucoseValueUpdated(data: String) {
        print(data)
    }
  */

    
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
    
    private func addDemoFabButton() {
        fab.buttonImage = UIImage(named: "custom-add")?.withRenderingMode(.alwaysOriginal)
        let image = UIImage(named: "bluetooth")?.withRenderingMode(.alwaysTemplate)
        fab.addItem("Demo Mode", icon: image) { item in
            KVNProgress.dismiss()
            self.removeFabButton()
            self.invokeDebugMode()
        }
        fab.sticky = true
        self.view.addSubview(fab)
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
                self.peripheralsTableView.reloadData(with: .right)
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

