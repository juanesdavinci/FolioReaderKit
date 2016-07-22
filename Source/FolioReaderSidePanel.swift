//
//  FolioReaderSidePanel.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

@objc
protocol FolioReaderSidePanelDelegate: class {
    /**
    Notifies when the user selected some item on menu.
    */
    func sidePanel(sidePanel: FolioReaderSidePanel, didSelectRowAtIndexPath indexPath: NSIndexPath, withTocReference reference: FRTocReference)
}

public class FolioReaderSidePanel: UIViewController, UITableViewDelegate, UITableViewDataSource {

    weak var delegate: FolioReaderSidePanelDelegate?
    var tableView: UITableView!
    var toolBar: UIToolbar!
    let toolBarHeight: CGFloat = 50
    var tocItems = [FRTocReference]()
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        var tableViewFrame = screenBounds()
        tableViewFrame.size.height = tableViewFrame.height/*-toolBarHeight*/
        
        tableView = UITableView(frame: tableViewFrame)
        tableView.delaysContentTouches = true
        tableView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
        tableView.backgroundColor = isNight(readerConfig.nightModeMenuBackground, readerConfig.menuBackgroundColor)
        tableView.separatorColor = isNight(readerConfig.nightModeSeparatorColor, UIColor.grayColor())
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        
        
        // Register cell classes
        tableView.registerClass(FolioReaderSidePanelCell.self, forCellReuseIdentifier: reuseIdentifier)
        tableView.separatorInset = UIEdgeInsetsZero
//        tableView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        
        // Create TOC list
        createTocList()
    }

    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Recursive add items to a list
    
    func createTocList() {
        for item in book.tableOfContents {
            tocItems.append(item)
            countTocChild(item)
        }
    }
    
    func countTocChild(item: FRTocReference) {
        if item.children.count > 0 {
            for item in item.children {
                tocItems.append(item)
            }
        }
    }

    // MARK: - Table view data source

    public func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tocItems.count
    }

    public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(reuseIdentifier, forIndexPath: indexPath) as! FolioReaderSidePanelCell
        
        let tocReference = tocItems[indexPath.row]
        let isSection = tocReference.children.count > 0
        
        cell.indexLabel.text = tocReference.title.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
        cell.indexLabel.font = UIFont(name: "Avenir-Light", size: 17)
        cell.indexLabel.textColor = readerConfig.menuTextColor

        if let resource = tocReference.resource {
            if(resource.mediaOverlay != nil){
                let duration = book.durationFor("#"+resource.mediaOverlay);
                let durationFormatted = (duration != nil ? duration : "")?.clockTimeToMinutesString()

                cell.indexLabel.text = cell.indexLabel.text! + (duration != nil ? " - "+durationFormatted! : "");
            }
        }

        // Mark current reading chapter
        if let currentPageNumber = currentPageNumber, reference = book.spine.spineReferences[safe: currentPageNumber-1] where tocReference.resource != nil {
            let resource = reference.resource
            cell.indexLabel.textColor = tocReference.resource!.href == resource.href ? readerConfig.tintColor : readerConfig.menuTextColor
        }
//        cell.indexLabel.text = cell.indexLabel.text! + "\t p.\(currentPageNumber)";

        
//        cell.layoutMargins = UIEdgeInsetsZero
//        cell.preservesSuperviewLayoutMargins = false
        cell.contentView.backgroundColor = isSection ? UIColor(white: 0.7, alpha: 0.1) : UIColor.clearColor()
        cell.backgroundColor = UIColor.clearColor()
        // Adjust text position
        cell.indexLabel.center = cell.contentView.center
        var frame = cell.indexLabel.frame
        frame.origin = isSection ? CGPoint(x: 40, y: frame.origin.y) : CGPoint(x: 20, y: frame.origin.y)
        cell.indexLabel.frame = frame
        let separator = UIView(frame: CGRect(x: 0, y: 60, width: 1024, height: 0.5))
        separator.backgroundColor = isNight(readerConfig.nightModeSeparatorColor, UIColor.lightGrayColor())
        cell.contentView.addSubview(separator)
        tableView.separatorInset = UIEdgeInsetsMake(0, 100000, 100000, 0.5)
        return cell
    }
    
    // MARK: - Table view delegate
    
    public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let tocReference = tocItems[indexPath.row]
        delegate?.sidePanel(self, didSelectRowAtIndexPath: indexPath, withTocReference: tocReference)
        
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
    }
    
    // MARK: - Table view data source
    
    public func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return 60
    }
    
    // MARK: - Get Screen bounds
    
    func screenBounds() -> CGRect {
        return UIScreen.mainScreen().bounds
    }
    
    // MARK: - Rotation
    
    override public func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        UIView.animateWithDuration(duration, animations: { () -> Void in
            if  self.toolBar != nil {
                var frame = self.toolBar.frame
                frame.origin.y = pageHeight-self.toolBarHeight
                self.toolBar.frame = frame
            }
        })
    }
    
    // MARK: - Toolbar actions
    
    func didSelectHighlight(sender: UIBarButtonItem) {
        FolioReader.sharedInstance.readerContainer.toggleLeftPanel()
        FolioReader.sharedInstance.readerCenter.presentHighlightsList()
    }
    
    func didSelectClose(sender: UIBarButtonItem) {
        self.dismissViewControllerAnimated(true, completion: {
            FolioReader.sharedInstance.isReaderOpen = false
            FolioReader.sharedInstance.isReaderReady = false
            FolioReader.sharedInstance.readerAudioPlayer.stop()
        })
    }
    
    func didSelectFont(sender: UIBarButtonItem) {
        FolioReader.sharedInstance.readerContainer.toggleLeftPanel()
        FolioReader.sharedInstance.readerCenter.presentFontsMenu()
    }

}
