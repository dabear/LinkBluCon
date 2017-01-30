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

protocol BluConDeviceManagerDelegate: class {
    func didStartWithDeviceStatus(status: DeviceStatus)
    func didStartWithError(error: Error)
    func didDiscoverBluConPeripherals(peripherals: [Peripheral])
    func peripheralConnected(peripheral: Peripheral)
    func peripheralDisconnected(status: PeripheralError)
    func didStartListeningToCharacteristicNotifications(status: Bool)
    func didReceiveUpdateValueFromPeripheral(hexString: String)
    func reconnectingBluConDevice()
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

class BluConDeviceManager {
    
    weak var delegate: BluConDeviceManagerDelegate? = nil
    static let sharedInstance: BluConDeviceManager = BluConDeviceManager()
    private let connectionManager: CentralManager = CentralManager(options: [CBCentralManagerOptionRestoreIdentifierKey : "com.ambrosia.linkblucon.central-manager" as NSString])
    private var discoveredPeripherals = [Peripheral]()
    private var peripheralConnected: Peripheral? = nil
    private let desiredReceiveCharacteristicUUID: CBUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private let desiredServiceUUID: CBUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let bluconBluetoothDeviceName: String = "blucon"
    
    
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
            
            if Peripheral.name.lowercased() == self.bluconBluetoothDeviceName {
                self.discoveredPeripherals.append(Peripheral)
                let orderedSet = NSOrderedSet.init(array: self.discoveredPeripherals)
                if let array = orderedSet.array as? [Peripheral] {
                    self.discoveredPeripherals = array
                }
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
        }
        
        connectionFuture.onFailure { [weak self] error in
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
                    if peripheral.disconnectionCount < 10 {
                        self?.delegate?.reconnectingBluConDevice()
                        peripheral.reconnect(withDelay: 1.0)
                        print("Disconnected retrying '\(peripheral.name)', \(peripheral.identifier.uuidString), disconnect count=\(peripheral.disconnectionCount), max disconnections=\(10)")
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
        
        let peripheralCharacteristicsFuture = service.discoverCharacteristics([desiredReceiveCharacteristicUUID])
        
        peripheralCharacteristicsFuture.onSuccess { (Service) in
            for (_, characteristic) in service.characteristics.enumerated() {
                
                let notifiedFuture: Future<Characteristic>? = characteristic.canNotify ? characteristic.startNotifying(): nil
                
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
        }
        
    }
    
    private func getNotificationUpdatesForCharacteristic(futureCharacteristic: Future<Characteristic>, characteristic: Characteristic ) {
        
        let receiveNotificationUpdatesFuture = futureCharacteristic.flatMap { [ ] _ -> FutureStream<(characteristic: Characteristic, data: Data?)> in
            return characteristic.receiveNotificationUpdates()
        }
        
        receiveNotificationUpdatesFuture.onSuccess { (characteristic: Characteristic, data: Data?) in
            var values = [UInt8](repeating:0, count:data!.count)
            data?.copyBytes(to: &values, count: data!.count)
            print(values)
            let hexString = NSMutableString()
            for byte in values {
                hexString.appendFormat("%02x", UInt(byte))
            }
            print(NSString(string: hexString))
            self.delegate?.didReceiveUpdateValueFromPeripheral(hexString: hexString as String)
        }
        
        receiveNotificationUpdatesFuture.onFailure { (Error) in
            // try discovering the services again...
            print("notification updates failed for characteristic \(characteristic)")
            self.discoverServices()
        }
    }
    
}
