//
//  BluConGlucoseDecoder.swift
//  LinkBluCon
//
//  Created by Gorugantham, Ramu Raghu Vams on 2/13/17.
//  Copyright © 2017 Gorugantham, Ramu Raghu Vams. All rights reserved.
//

import UIKit

extension String {
    var pairs:[String] {
        var result:[String] = []
        let chars = Array(characters)
        for index in stride(from: 0, to: chars.count, by: 2) {
            result.append(String(chars[index..<min(index+2, chars.count)]))
        }
        return result
    }
    
    var isNumeric: Bool {
        let nums: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return Set(self.characters).isSubset(of: nums)
    }
}

protocol BluConGlucoseDecoderDelegate: class {
    func didStartDecoding()
    func didFinishDecoding()
    func updateTotalSensorActiveTime(status: String)
    func glucoseTrendValuesUpdated(data: [[String: String]])
    func glucoseHistoryValuesUpdated(data: [[String: String]])
    func currentGlucoseValueUpdated(data: String)
}


class BluConGlucoseDecoder: NSObject {
    
    static let sharedInstance: BluConGlucoseDecoder = BluConGlucoseDecoder()
    weak var delegate: BluConGlucoseDecoderDelegate? = nil
    private var dataString = ""
    private let sensorTimeStartingBytes = [317,316]
    private let trendValuesRange = [56, 248]
    private let historicalDataRange = [248, 632]
    private let glucoseBytesLength = 12 // 6 bytes
    private let nextWriteBlock1StartIndex = 26*2
    private let nextWriteBlock2StartIndex = 27*2
    
    
    func decodeValuesForData(hexData: String) {
        self.delegate?.didStartDecoding()
        dataString = hexData
        
        // get sensor active time...
        if let sensorActivityString: String = getSenorActiveTime(allData: dataString), !sensorActivityString.isEmpty {
            self.delegate?.updateTotalSensorActiveTime(status: sensorActivityString)
        }
        
        // get trend values...
        
        if let trendValues = getTrendValues(allcontent: dataString), trendValues.count > 0 {
            self.delegate?.glucoseTrendValuesUpdated(data: trendValues)
            for (index, element) in trendValues.enumerated() {
                if let key:String = element.keys.first, !key.isEmpty && key.lowercased() == "now" {
                    let currentValue = trendValues[index][key]! as String
                    self.delegate?.currentGlucoseValueUpdated(data: currentValue)
                    print("currenValue - \(currentValue)")
                }
            }
        }
        
        // get historic data...
        
        if let historicValues = getHistoricValues(allcontent: dataString), historicValues.count > 0 {
            self.delegate?.glucoseHistoryValuesUpdated(data: historicValues)
        }
        self.delegate?.didFinishDecoding()
    }
    
    private func getTrendValues(allcontent: String) -> [[String: String]]? {
        var lineNumber = 0
        let startIndex = allcontent.index(allcontent.startIndex, offsetBy: nextWriteBlock1StartIndex)
        let endIndex = allcontent.index(allcontent.startIndex, offsetBy: nextWriteBlock1StartIndex+1)
        var nextWriteBlock1 = Int(UInt64(allcontent[startIndex...endIndex], radix:16)!)
        var result = [[String: String]]() // ["minutes": "glucoseValues"]
        
        for (_,ele) in stride(from: trendValuesRange[0], to: trendValuesRange[1], by: glucoseBytesLength).enumerated() {
            let start = allcontent.index(allcontent.startIndex, offsetBy: ele)
            let end = allcontent.index(allcontent.startIndex, offsetBy: ele+11)
            let record = (allcontent[start...end])
            var bytes = record.pairs
            let line = bytes.joined(separator: " ")
            let gludata = getGlucose(data: "\(bytes[1])\(bytes[0])")
            
            if nextWriteBlock1 - lineNumber != 0 {
                let minutes = "\(nextWriteBlock1 - lineNumber)"
                result.append([minutes:gludata])
                print("\(line)   |   \((minutes)) min   \(gludata)")
            }
            
            if nextWriteBlock1 == lineNumber {
                print("\(line)   |   now   \(gludata)")
                result.append(["now":gludata]) // this is current value
                nextWriteBlock1 += 16
            }
            
            lineNumber += 1
        }
        
        return sortTrendValues(trendData: result)
    }
    
    private func getHistoricValues(allcontent: String) -> [[String: String]]? {
        var lineNumber = 0
        let startIndex = allcontent.index(allcontent.startIndex, offsetBy: nextWriteBlock2StartIndex)
        let endIndex = allcontent.index(allcontent.startIndex, offsetBy: nextWriteBlock2StartIndex+1)
        var nextWriteBlock2 = Int(UInt64(allcontent[startIndex...endIndex], radix:16)!)
        var result = [[String: String]]() // ["minutes": "glucoseValues"]
        
        for (_,ele) in stride(from: historicalDataRange[0], to: historicalDataRange[1], by: glucoseBytesLength).enumerated() {
            let start = allcontent.index(allcontent.startIndex, offsetBy: ele)
            let end = allcontent.index(allcontent.startIndex, offsetBy: ele+11)
            let record = (allcontent[start...end])
            var bytes = record.pairs
            let line = bytes.joined(separator: " ")
            let gludata = getGlucose(data: "\(bytes[1])\(bytes[0])")
            
            if nextWriteBlock2 - lineNumber != 0 {
                let minutes = "\((nextWriteBlock2 - lineNumber)*15)"
                result.append([minutes:gludata])
                print("\(line)   |   \((minutes)) min   \(gludata)")
            }
            
            if nextWriteBlock2 == lineNumber {
                print("\(line)   |   last   \(gludata)")
                result.append(["last":gludata]) // this is current value
                nextWriteBlock2 += 32
            }
            
            lineNumber += 1
        }
        
        return sortHistoricDataValues(historicData: result)
    }
    
    func sortTrendValues(trendData: [[String:String]]) -> [[String:String]] {
        return trendData.sorted{
            if Array($0.keys)[0].lowercased() == "now" {
                return true
            }
            if let int1 = Int(Array($0.keys)[0]),  let int2 = Int(Array($1.keys)[0]){
                return  int1 < int2
            }
            return false
        }
    }
    
    func sortHistoricDataValues(historicData: [[String:String]]) -> [[String:String]] {
        return historicData.sorted{
            if Array($0.keys)[0].lowercased() == "last" {
                return false
            }
            if let int1 = Int(Array($0.keys)[0]),  let int2 = Int(Array($1.keys)[0]){
                return  int1 < int2
            }
            return true
        }
    }
    
    private func getSenorActiveTime(allData: String) -> String? {
        let startByte1 = allData.index(allData.startIndex, offsetBy: sensorTimeStartingBytes[0]*2)
        let endByte1 = allData.index(allData.startIndex, offsetBy: sensorTimeStartingBytes[0]*2+1)
        let startByte0 = allData.index(allData.startIndex, offsetBy: sensorTimeStartingBytes[1]*2)
        let endByte0 = allData.index(allData.startIndex, offsetBy: sensorTimeStartingBytes[1]*2+1)
        return getTotalSensorActiveTime(timeInMinutes: (allData[startByte1...endByte1])+(allData[startByte0...endByte0]) )
    }
    
    func getTotalSensorActiveTime(timeInMinutes: String) -> String? {
        if !timeInMinutes.isEmpty {
            let time: Int = Int(UInt64(timeInMinutes, radix:16)!)
            let days = time/1440
            let hours = ((time - (days * 1440))/60)
            let minutes = (time - (days * 1440)) - (hours * 60)
            return "Sensor active for \(days) days, \(hours) hrs and \(minutes) min"
        }
        return nil
    }

    func getGlucoseDividedBy8p5(data: String) -> String {
        let glucose = Int(UInt64(data, radix:16)!) & Int(0x0FFF) // bit mask
        let result = (Double(glucose)/8.5) //(glucose/6)-37
        return "\((result >= 0) ? result : 0)"
    }
    
    func getGlucose(data: String) -> String {
        let glucose = Int(UInt64(data, radix:16)!) & Int(0x0FFF) // bit mask
        let result = (glucose/10) //(glucose/6)-37
        return "\((result >= 0) ? result : 0)"
    }
    
}
