//
//  DemoViewController.swift
//  LinkBluCon
//
//  Created by Gorugantham, Ramu Raghu Vams on 2/4/17.
//  Copyright © 2017 Gorugantham, Ramu Raghu Vams. All rights reserved.
//

import UIKit

class DemoViewController: UIViewController, BEMSimpleLineGraphDataSource, BEMSimpleLineGraphDelegate {

    @IBOutlet weak var currentValue: UILabel!
    
    @IBOutlet weak var timeLabel: UILabel!
    
    @IBOutlet weak var graph: BEMSimpleLineGraphView!
    
    @IBOutlet weak var todayLabel: UILabel!
    
    var dataValues: [String] = [String]()
    var dateValues: [String] = [String]()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
            return .lightContent
        }

        
    
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.statusBarStyle = .lightContent
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action:#selector(dismissVC))
        self.navigationItem.leftBarButtonItem?.tintColor = UIColor.black
        initialSetup()
        // Do any additional setup after loading the view.
    }
    
    func initialSetup(){
        dateValues.append(contentsOf: ["9:00","10:00","11:00", "12:00","13:00","14:00", "15:00","16:00","17:00", "18:00","19:00","20:00", "21:00"])
        dataValues.append(contentsOf: ["210", "230", "200", "180", "190","200", "230", "215", "250","215", "250", "265", "260"])
        currentValue.text = dataValues.last
        timeLabel.text = getTime()
        setupGraph()
    }
    
    func fireTimer() {
        if #available(iOS 10.0, *) {
            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
                (_) in
                self.timerFired()
            }
            timer.fire()

        } else {
            // Fallback on earlier versions
            let timer = Timer(fireAt: Date(timeIntervalSinceNow: 0), interval: 5, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
            timer.fire()
        }
        
        
    }
    
    func timerFired() {
        let i: Int = Int(arc4random_uniform(201) % 10) + 100
//        dataValues.add("\(200+i)")
//        dateValues.add(getTime())
//        currentValue.text = dataValues.lastObject as? String
//        timeLabel.text = dateValues.lastObject as? String
        graph.reloadGraph()
    }
    
    func setupGraph() {
        
        // Enable and disable various graph properties and axis displays
        graph.enableTouchReport = true
        graph.enablePopUpReport = true
        graph.enableYAxisLabel = true
        graph.autoScaleYAxis = true
        graph.alwaysDisplayDots = false
        graph.enableReferenceXAxisLines = true
        graph.enableReferenceYAxisLines = true
        graph.enableReferenceAxisFrame = true
        
        // Draw an average line
        graph.averageLine.enableAverageLine = true
        graph.averageLine.alpha = 0.6
        graph.averageLine.color = UIColor.black
        graph.averageLine.width = 2.5
        graph.averageLine.yValue = 200
        
        
        // Set the graph's animation style to draw, fade, or none
        graph.animationGraphStyle = .draw
        graph.clearsContextBeforeDrawing = true
        
        // Dash the y reference lines
        graph.lineDashPatternForReferenceYAxisLines = [2,2]
        
        // Show the y axis values with this format string
//        graph.formatStringForValues = "%0.1f"
        
        // Setup initial curve selection segment
        graph.enableBezierCurve = true
        graph.dataSource = self
        graph.delegate = self
        graph.reloadGraph()

    }
    
    func getTime() -> String {
        return DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    }
    
    func dismissVC() {
        self.dismiss(animated: true, completion: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    // MARK: - SimpleLineGraph Data Source
    func numberOfPoints( inLineGraph graph: BEMSimpleLineGraphView) -> Int {
        return dataValues.count
    }
    
    func lineGraph(_ graph: BEMSimpleLineGraphView, valueForPointAt index: Int) -> CGFloat {
        if let str = dataValues[index] as? String, let n = NumberFormatter().number(from: str) {
            return CGFloat(n)
        }
        else {
            return 0
        }
    }
    
    // MARK: - SimpleLineGraph Delegate

     func numberOfGapsBetweenLabels(onLineGraph graph: BEMSimpleLineGraphView) -> Int {
        return 0
    }
    
     func lineGraph(_ graph: BEMSimpleLineGraphView, labelOnXAxisFor index: Int) -> String {
        let str = dateValues[index]
        return str
    }
    
    func yAxisSuffix(onLineGraph graph: BEMSimpleLineGraphView) -> String {
        return " mg/dl"
    }
    
}
