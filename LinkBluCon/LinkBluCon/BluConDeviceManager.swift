//
//  BluConDeviceManager.swift
//  LinkBluCon
//
//  Created by Gorugantham, Ramu Raghu Vams on 1/27/17.
//  Copyright © 2017 Gorugantham, Ramu Raghu Vams. All rights reserved.
//

import UIKit
import CoreBluetooth
import BlueCapKit

extension String {
    
    internal func hexStringToData() -> Data? {
        var data = Data(capacity: characters.count / 2)
        
        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, options: [], range: NSMakeRange(0, characters.count)) { match, flags, stop in
            let byteString = (self as NSString).substring(with: match!.range)
            var num = UInt8(byteString, radix: 16)!
            data.append(&num, count: 1)
        }
        
        guard data.count > 0 else {
            return nil
        }
        
        return data
    }
}

protocol BluConDeviceManagerDelegate: class {
    
    // device status / connectivity methods
    func didStartWithDeviceStatus(status: DeviceStatus)
    func didStartWithError(error: Error)
    func didDiscoverBluConPeripherals(peripherals: [Peripheral])
    func peripheralConnected(peripheral: Peripheral)
    func peripheralDisconnected(status: PeripheralError)
    func didStartListeningToCharacteristicNotifications(status: Bool)
    func reconnectingBluConDevice()
    
    // glucose path methods
    func didReceiveUpdatedGlucoseValue(dateAndTime: String, value: String)
    func didUpdateSensorActiveTime(status: String)
    func glucosePatchReadError()
    
    //    func updateUIForDataSizeReceived(size: String)
    //    func didReceiveCompleteDataFromPeripheral(hexString: String)

    
}

public enum DeviceStatus {
    case ready
    case resetting
    case poweredOff
    case unknown
    case unsupported
    
    func toString() -> String {
        switch self {
        case .ready:
            return "device is ready to scan for BLUCON devices"
        case .resetting:
            return "Bluetooth device is resetting... please wait..."
        case .unsupported:
            return "This device is either unauthorized or unsupported to connect to BLUCON Device. Please close the app."
        case .unknown:
            return "Unable to determine bluetooth state. Please turn On/Off the bluetooth and try again."
        case .poweredOff:
            return "Please turn ON your bluetooth device to scan for BlueCon devices."
        }
    }
}

private enum BluConCommands: String {
    
    // wakeup & sleep commands...
    case initalState = ""
    case wakeup = "cb010000"
    case ackWakeup = "810a00"
    case sleep = "010c0e00"
    
    // sensor info commands...
    case getSerialNumber = "010d0e0100"
    case getPatchInfo = "010d0900"
    case getSensorTime = "010d0e0127"
    
    // data commands...
    case getNowDataIndex = "010d0e0103"
    case getNowGlucoseData = "9999999999"
    case getTrendData = "010d0f02030c"
    case getHistoricData = "010d0f020f18"
    
    
    
}

private enum BluConCommandResponse: String {
    
    // response prefixes...
    case patchInfoResponsePrefix = "8bd9"
    case singleBlockInfoResponsePrefix = "8bde"
    case multipleBlockInfoResponsePrefix = "8bdf"
    case sensorTimeResponsePrefix = "8bde27"
    case bluconACKResponse = "8b0a00"
    case bluconNACKResponsePrefix = "8b1a02"
}

private enum BluConNACKResponse: String {
    case patchNotFound = "8b1a02000f"
    case patchReadError = "8b1a020011"
}


class BluConDeviceManager {
    
    // constants
    private static let connectionRetryInterval: TimeInterval = 10.0 // try after every 10 sec and not anytime soon...
    private static let connectionMaxRetries: UInt = 10 // max connection retries limit...
    private static let requiredDataSize = 3904 // 1952 bytes
    private let desiredTransmitCharacteristicUUID: CBUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let desiredReceiveCharacteristicUUID: CBUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private let desiredServiceUUID: CBUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let bluconBluetoothDeviceName: String = "blu"
    private var currentCommand: BluConCommands = .initalState
    private var writeCharacteristic: Characteristic?
    private var readCharacteristic: Characteristic?
    
    private var decoder: BluConGlucoseDecoder = BluConGlucoseDecoder.sharedInstance
    
    // now glucose params
    private var nowGlucoseIndex2: Int = 0
    private var nowGlucoseIndex3: Int = 0
    private var nowGlucoseOffset: Int = 0
    
    // vars
    weak var delegate: BluConDeviceManagerDelegate? = nil
    static let sharedInstance: BluConDeviceManager = BluConDeviceManager()
    private let connectionManager: CentralManager = CentralManager(options: [CBCentralManagerOptionRestoreIdentifierKey : "com.ambrosia.linkblucon.central-manager" as NSString])
    private var discoveredPeripherals = [Peripheral]()
    private var peripheralConnected: Peripheral? = nil
    private var completeDataHexString = NSMutableString() // limited for full data fetch
    internal var responseString = NSMutableString()
    
    private var isWakeupSignal: Bool {
        return (responseString.lowercased == BluConCommands.wakeup.rawValue)
    }
    
    private var isPatchInfoResponse: Bool {
        return (responseString.lowercased.hasPrefix(BluConCommandResponse.patchInfoResponsePrefix.rawValue))
    }
    
    private var isSingleBlockResponse: Bool {
        return (responseString.lowercased.hasPrefix(BluConCommandResponse.singleBlockInfoResponsePrefix.rawValue))
    }
    
    private var isSensorTimeResponse: Bool {
        return (responseString.lowercased.hasPrefix(BluConCommandResponse.sensorTimeResponsePrefix.rawValue))
    }
    
    private var isBluconACKResponse: Bool {
        return (responseString.lowercased == BluConCommandResponse.bluconACKResponse.rawValue)
    }
    
    private var isBluconNACKResponse: Bool {
        return (responseString.lowercased.hasPrefix(BluConCommandResponse.bluconNACKResponsePrefix.rawValue))
    }
    
    private var patchInfo: String {
        let response = responseString.copy() as! String
        let startIndex = response.index(response.startIndex, offsetBy: 4)
        let endIndex = response.index(response.startIndex, offsetBy: 25)
        let result = response[startIndex...endIndex] // get 11 bytes of patch info data...
        return (result.characters.count == 22) ? result : "" // check if there are 11 bytes if not its not the right data we got...
    }
    
    private var sensorTime: String {
        let blockPairs = parseSingleBlockResponseIntoByteArray(response: responseString.copy() as! String)
        let time = blockPairs[(blockPairs.count-1)-2]+blockPairs[(blockPairs.count-1)-3] // 39[2]39[3]
        return decoder.getTotalSensorActiveTime(timeInMinutes: time)!
    }
    
    private var nowGlucoseValue: String {
        let blockPairs = parseSingleBlockResponseIntoByteArray(response: responseString.copy() as! String)
        return decoder.getGlucose(data: "\(blockPairs[7-nowGlucoseOffset])\(blockPairs[7-nowGlucoseOffset-1])")
    }
    
    private var blockNumberForNowGlucoseData: String {
        let getNowDataIndexResponse = parseSingleBlockResponseIntoByteArray(response: responseString.copy() as! String)
        // get the 3rd block 5th byte hex to decimal conversion
        // Index2 = (3rd Block[5] * 6)+ 4;
        nowGlucoseIndex2 = (Int(UInt64(getNowDataIndexResponse[(getNowDataIndexResponse.count-1)-5], radix:16)!) * 6) + 4
        //offset = Index2 % 8;
        nowGlucoseOffset = nowGlucoseIndex2 % 8
        //Index3 = 3 + (Index2/8);
        nowGlucoseIndex3 = 3 + (nowGlucoseIndex2/8)
        let hexString = String(format:"%2X", nowGlucoseIndex3)
        if hexString.characters.count == 1 {
            return "0\(hexString)".replacingOccurrences(of: " ", with: "")
        }
        else {
            return hexString
        }
    }
    
    func parseSingleBlockResponseIntoByteArray(response: String) -> [String] {
        let startIndex = response.index(response.startIndex, offsetBy: 6)
        let endIndex = response.index(response.startIndex, offsetBy: response.characters.count-1)
        return response[startIndex...endIndex].pairs
    }
    
    
    
    private func resetTempData() {
        completeDataHexString = NSMutableString()
        responseString = NSMutableString()
    }
    
    func start() {
        
        let bluetoothDeviceStateChanges = connectionManager.whenStateChanges()
        
        bluetoothDeviceStateChanges.onSuccess { (ManagerState) in
            switch ManagerState {
            case .poweredOn:
                self.delegate?.didStartWithDeviceStatus(status: DeviceStatus.ready)
            case .poweredOff:
                self.delegate?.didStartWithDeviceStatus(status: DeviceStatus.poweredOff)
            case .unauthorized, .unsupported:
                self.delegate?.didStartWithDeviceStatus(status: DeviceStatus.unsupported)
            case .resetting:
                self.connectionManager.reset()
                self.delegate?.didStartWithDeviceStatus(status: DeviceStatus.resetting)
            case .unknown:
                self.delegate?.didStartWithDeviceStatus(status: DeviceStatus.unknown)
            }
        }
        
        bluetoothDeviceStateChanges.onFailure { (Error) in
            self.delegate?.didStartWithError(error: Error)
        }
    }
    
    func scanForPeripherals() {
        
        discoveredPeripherals.removeAll()
        
        let scanningResults = connectionManager.startScanning(forServiceUUIDs: nil, capacity: 10, timeout: Double(60), options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
        
        scanningResults.onSuccess { (Peripheral) in
            
            if Peripheral.name.lowercased().hasPrefix(self.bluconBluetoothDeviceName) {
                self.discoveredPeripherals.append(Peripheral)
                self.discoveredPeripherals = Array<Peripheral>(Set<Peripheral>(self.discoveredPeripherals))
                self.delegate?.didDiscoverBluConPeripherals(peripherals: self.discoveredPeripherals)
            }
            
            print("Discovered peripheral: '\(Peripheral.name)', \(Peripheral.identifier.uuidString)")
            
        }
        
        scanningResults.onFailure { (Error) in
            print("scanning peripherals failed due to error - \(Error)")
        }
        
    }
    
    func stopScanForPeripherals() {
        connectionManager.stopScanning()
    }
    
    func connectToPeripheral(peripheral: Peripheral) {
        
        peripheralConnected = nil
        let connectionFuture = peripheral.connect(connectionTimeout: 10, capacity: 1)
        
        connectionFuture.onSuccess { (Peripheral) in
            print("connected to peripheral: '\(Peripheral.name)', \(Peripheral.identifier.uuidString)")
            self.peripheralConnected = Peripheral
            self.discoverServices()
            self.delegate?.peripheralConnected(peripheral: Peripheral)
            self.resetTempData()
            self.currentCommand = .initalState
        }
        
        connectionFuture.onFailure { [weak self] error in
            self?.currentCommand = .initalState
            self?.completeDataHexString = NSMutableString()
            self.forEach { strongSelf in
                
                print("Connection failed: '\(peripheral.name)', \(peripheral.identifier.uuidString), timeout count=\(peripheral.timeoutCount), max timeouts=\(10), disconnect count=\(peripheral.disconnectionCount), max disconnections=\(10)")
                
                switch error {
                case PeripheralError.forcedDisconnect:
                    self?.delegate?.peripheralDisconnected(status:.forcedDisconnect)
                    print("Forced Disconnection '\(peripheral.name)', \(peripheral.identifier.uuidString)")
                    return
                case PeripheralError.connectionTimeout:
                    self?.delegate?.peripheralDisconnected(status:.connectionTimeout)
                    print("Connection timeout retrying '\(peripheral.name)', \(peripheral.identifier.uuidString), timeout count=\(peripheral.timeoutCount), max timeouts=\(10)")
                default:
                    if let err = error as? PeripheralError {
                        self?.delegate?.peripheralDisconnected(status: err)
                    }
                    if peripheral.disconnectionCount < BluConDeviceManager.connectionMaxRetries {
                        self?.delegate?.reconnectingBluConDevice()
                        peripheral.reconnect(withDelay: BluConDeviceManager.connectionRetryInterval) // retry interval 10 sec
                        print("Disconnected retrying '\(peripheral.name)', \(peripheral.identifier.uuidString), disconnect count=\(peripheral.disconnectionCount), max disconnections=\(BluConDeviceManager.connectionMaxRetries)")
                        return
                    }
                }
                print("Connection failed giving up '\(error), \(peripheral.name)', \(peripheral.identifier.uuidString)")
                
            }
        }
    }
    
    private func discoverServices() {
        
        if let connectedPeripheral = peripheralConnected {
            
            let peripheralDiscoveryFuture = connectedPeripheral.discoverServices(nil)
            
            peripheralDiscoveryFuture.onSuccess(completion: { (Peripheral) in
                if Peripheral.services.count == 1  {
                    if let service = Peripheral.services.first{
                        self.discoverCharacteristicsForService(service: service)
                    }
                }
            })
            
            peripheralDiscoveryFuture.onFailure(completion: { (Error) in
                print("Service discovery failed peripheral: \(Error), \(connectedPeripheral.name), \(connectedPeripheral.identifier.uuidString)")
            })
        }
        
    }
    
    private func discoverCharacteristicsForService(service: Service) {
        
        let peripheralCharacteristicsFuture = service.discoverCharacteristics([desiredReceiveCharacteristicUUID, desiredTransmitCharacteristicUUID])
        
        peripheralCharacteristicsFuture.onSuccess { (Service) in
            for (_, characteristic) in service.characteristics.enumerated() {
                
                if characteristic.canWrite {
                    self.writeCharacteristic = characteristic
                }
                else if characteristic.canNotify || characteristic.canRead {
                    self.readCharacteristic = characteristic
                }
            }
            
            if let _ = self.readCharacteristic {
                // start reading...
                self.startReadingData(characteristic: self.readCharacteristic!)
            }
        }
    }
    
    private func startReadingData(characteristic: Characteristic) {
        
        let notifiedFuture: Future<Characteristic>? = (characteristic.canNotify) ? characteristic.startNotifying(): nil
        
        notifiedFuture?.onSuccess(completion: { (characteristic) in
            print("started notifications for characteristic - \(characteristic.uuid)")
            if let futureNotifications = notifiedFuture {
                self.delegate?.didStartListeningToCharacteristicNotifications(status: true)
                self.getNotificationUpdatesForCharacteristic(futureCharacteristic: futureNotifications, characteristic: characteristic)
            }
        })
        
        notifiedFuture?.onFailure(completion: { (Error) in
            self.delegate?.didStartListeningToCharacteristicNotifications(status: false)
            print("notifications failed for characteristic - \(self.desiredReceiveCharacteristicUUID)")
            
        })
    }
    
    func timeStamp() -> String {
        return DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
    }
    
    
    private func getNotificationUpdatesForCharacteristic(futureCharacteristic: Future<Characteristic>, characteristic: Characteristic ) {
        
        let receiveNotificationUpdatesFuture = futureCharacteristic.flatMap { [ ] _ -> FutureStream<(characteristic: Characteristic, data: Data?)> in
            return characteristic.receiveNotificationUpdates()
        }
        
        receiveNotificationUpdatesFuture.onSuccess { (characteristic: Characteristic, data: Data?) in
            if let responseData = data {
                
                self.responseString = NSMutableString.init(string: responseData.hexStringValue())
                if self.isWakeupSignal {
                    self.currentCommand = .initalState
                    print("----------------------------------------------------------------------------------\n\(self.timeStamp()) wakeup received - \(self.responseString)")
                }
                
                if self.isBluconACKResponse {
                    self.currentCommand = .initalState
                    print("\(self.timeStamp()) ACK received from BluCon - \(self.responseString)\n----------------------------------------------------------------------------------")
                }
                
                if self.isBluconNACKResponse {
                    self.currentCommand = .initalState
                    if self.responseString.lowercased == BluConNACKResponse.patchReadError.rawValue {
                        self.delegate?.glucosePatchReadError()
                    }
                    print("\(self.timeStamp()) NACK received from BluCon - \(self.responseString)\n----------------------------------------------------------------------------------")
                }
                
                if self.currentCommand == .initalState && self.isWakeupSignal {
                    // Get Patch Info
                    self.getPatchInfoCommand()
                }
                else if self.currentCommand == .getPatchInfo && self.isPatchInfoResponse {
                    print("\(self.timeStamp())  Patch Info received \(self.patchInfo)")
                    self.ackWakeupCommand()
                }
                else if self.currentCommand == .getSensorTime && self.isSingleBlockResponse { // single block response...
                    print("\(self.timeStamp()) sensorTime -> single block response \(self.responseString)")
                    print("\(self.timeStamp()) sensorTimeCalculated -> \(self.sensorTime)")
                    self.delegate?.didUpdateSensorActiveTime(status: self.sensorTime)
                    self.getNowGlucoseDataIndexCommand()
                }
                else if self.currentCommand == .getNowDataIndex && self.isSingleBlockResponse {
                    print("\(self.timeStamp()) getNowDataIndex -> single block response \(self.responseString)")
                    self.getNowGlucoseDataCommand()
                }
                else if self.currentCommand == .getNowGlucoseData && self.isSingleBlockResponse {
                    print("\(self.timeStamp()) getNowGlucoseData -> single block response \(self.responseString)")
                    print("\(self.timeStamp()) now glucose value -> \(self.nowGlucoseValue)")
                    self.delegate?.didReceiveUpdatedGlucoseValue(dateAndTime: self.timeStamp(), value: self.nowGlucoseValue)
                    self.sleepCommand()
                }
            }
        }
        
        receiveNotificationUpdatesFuture.onFailure { (Error) in
            // try discovering the services again...
            print("notification updates failed for characteristic \(characteristic)")
            self.discoverServices()
        }
    }
    
    private func getPatchInfoCommand() {
        self.currentCommand = .getPatchInfo
        self.sendCommand(completion: { (status, error) in
            if status == true {
                print("getPatchInfo command sent successfully...")
            }
        })
    }
    
    private func ackWakeupCommand() {
        self.currentCommand = .ackWakeup
        self.sendCommand(completion: { (status, error) in
            if status == true {
                print("\(self.timeStamp()) ack command sent successfully...")
                self.getSensorTimeCommand()
            }
            
        })
    }
    
    private func getSensorTimeCommand() {
        self.currentCommand = .getSensorTime
        self.sendCommand(completion: { (status, error) in
            if status == true {
                print("\(self.timeStamp()) getSensorTime command sent successfully...")
            }
            
        })
    }
    
    private func getNowGlucoseDataIndexCommand() {
        self.currentCommand = .getNowDataIndex
        self.sendCommand(completion: { (status, error) in
            if status == true {
                print("\(self.timeStamp()) getNowDataIndex command sent successfully...")
            }
            
        })
    }
    
    private func getNowGlucoseDataCommand() {
        self.currentCommand = .getNowGlucoseData
        self.sendCommand(completion: { (status, error) in
            if status == true {
                print("\(self.timeStamp()) getNowGlucoseData command sent successfully...")
            }
            
        })
    }
    
    private func sleepCommand() {
        self.currentCommand = .sleep
        self.sendCommand(completion: { (status, error) in
            if status == true {
                self.currentCommand = .initalState
                print("\(self.timeStamp()) sleep command sent successfully...")
            }
        })
    }
    
    private func sendCommand(completion: @escaping (_ status: Bool, _ error: NSError? ) -> Void) {
        if let commandToBeSent: Data = (self.currentCommand == .getNowGlucoseData) ? ("010d0e01" + blockNumberForNowGlucoseData).hexStringToData() : self.currentCommand.rawValue.hexStringToData() {
            print("\(self.timeStamp())  commandToBeSent - \(commandToBeSent.hexStringValue())")
            let notifiedFuture: Future<Characteristic>? = self.writeCharacteristic?.write(data: commandToBeSent)
            notifiedFuture?.onSuccess(completion: { (characteristic) in
                // command sent successfully....
                completion(true, nil)
                
            })
            notifiedFuture?.onFailure(completion: { (error) in
                // commant sent error occured
                print("command sent error...")
                completion(false, NSError.init(domain: "BluconErrorDomain", code: 128, userInfo: ["message" : "unable to send command"]))
            })
        }
    }
    
    
    /*
    private func processDataReceivedFromBluCon(data: Data?) {
        
        if let response: Data = data {
            
        }
        
    }
    
    fileprivate func collectedCompleteDataFromBluCon(responseData: Data?) {
        
        if let data: Data = responseData {
            var values = [UInt8](repeating:0, count:data.count)
            data.copyBytes(to: &values, count: data.count)
            print(values)
            if (self.completeDataHexString as String).characters.count == BluConDeviceManager.requiredDataSize {
                // we already have some old info... so lets reset it...
                self.completeDataHexString = NSMutableString()
            }
            
            for byte in values {
                self.completeDataHexString.appendFormat("%02x", UInt(byte))
            }
            
            print(NSString(string: self.completeDataHexString))
            
            if (self.completeDataHexString as String).characters.count == BluConDeviceManager.requiredDataSize {
                // we got the data we are expecting
                self.delegate?.didReceiveCompleteDataFromPeripheral(hexString: self.completeDataHexString as String)
                self.completeDataHexString = NSMutableString() // reset the tempVariable
            }
            else {
                self.delegate?.updateUIForDataSizeReceived(size: "Reading Data...\n\(((self.completeDataHexString as String).characters.count)/2) bytes of \(BluConDeviceManager.requiredDataSize/2) bytes")
            }
        }
    }
 */
    
}
