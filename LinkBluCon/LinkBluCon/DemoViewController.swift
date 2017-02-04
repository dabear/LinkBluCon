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
    
    @IBOutlet weak var graphValueLabel: UILabel!
    
    @IBOutlet weak var graphTimeLabel: UILabel!
    
    @IBOutlet weak var todayLabel: UILabel!
    
    var dataValues: NSMutableArray = NSMutableArray()
    var dateValues: NSMutableArray = NSMutableArray()
        
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action:#selector(dismissVC))
        self.navigationItem.leftBarButtonItem?.tintColor = UIColor.white
        initialSetup()
        // Do any additional setup after loading the view.
    }
    
    func initialSetup(){
        todayLabel.text = "Today - \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))"
        dateValues.add(getTime())
        dataValues.add("70")
        currentValue.text = dataValues.firstObject as? String
        timeLabel.text = dateValues.firstObject as? String
        setupGraph()
        fireTimer()
    }
    
    func fireTimer() {
        if #available(iOS 10.0, *) {
            let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
                (_) in
                self.timerFired()
            }
            timer.fire()

        } else {
            // Fallback on earlier versions
            let timer = Timer(fireAt: Date(timeIntervalSinceNow: 0), interval: 60, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
            timer.fire()
        }
        
        
    }
    
    func timerFired() {
        let i: Int = Int(arc4random() % 10) + 1
        dataValues.add("\(100+i)")
        dateValues.add(getTime())
        currentValue.text = dataValues.lastObject as? String
        timeLabel.text = dateValues.lastObject as? String
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
        graph.averageLine.dashPattern = [5, 5]
        
        // Set the graph's animation style to draw, fade, or none
        graph.animationGraphStyle = .draw
        graph.clearsContextBeforeDrawing = true
        
        // Dash the y reference lines
        graph.lineDashPatternForReferenceYAxisLines = [2,2]
        
        // Show the y axis values with this format string
        graph.formatStringForValues = "%0.1f"
        
        // Setup initial curve selection segment
        graph.enableBezierCurve = true
        graph.dataSource = self
        graph.delegate = self
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
        return 4
    }
    
     func lineGraph(_ graph: BEMSimpleLineGraphView, labelOnXAxisFor index: Int) -> String {
        return (dateValues[index] as? String)!
    }
    
    func yAxisSuffix(onLineGraph graph: BEMSimpleLineGraphView) -> String {
        return " mg/dl"
    }
    
    func lineGraph(_ graph: BEMSimpleLineGraphView, didTouchGraphWithClosestIndex index: Int) {
        graphValueLabel.text = dataValues[index] as? String
        graphTimeLabel.text = "@ \(dateValues[index] as! String)"
    }
    
    func setValues() {
        let avgValue = "Avg : \(self.graph.calculatePointValueSum().intValue / self.dataValues.count) mg/dl"
        let timeValue = (self.dateValues.count == 1) ? "at \(self.dateValues.firstObject!)" : "between \(self.dateValues.firstObject!) and \(self.dateValues.lastObject!)"
        self.graphValueLabel.text = avgValue
        self.graphTimeLabel.text = timeValue
    }
    
    func lineGraph(_ graph: BEMSimpleLineGraphView, didReleaseTouchFromGraphWithClosestIndex index: CGFloat) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            self.graphValueLabel.alpha = 0.0
            self.graphTimeLabel.alpha = 0.0
        }) { (state) in
            self.setValues()
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
                self.graphValueLabel.alpha = 1.0
                self.graphTimeLabel.alpha = 1.0

            }, completion: nil)

        }
    }
    
    
     func lineGraphDidFinishLoading(_ graph: BEMSimpleLineGraphView) {
        setValues()
    }
    
    func lineGraphDidBeginLoading(_ graph: BEMSimpleLineGraphView) {
        
    }

    
}
