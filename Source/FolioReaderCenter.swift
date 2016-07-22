//
//  FolioReaderCenter.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import ZFDragableModalTransition

let reuseIdentifier = "Cell"
var isScrolling = false
var recentlyScrolled = false
var recentlyScrolledDelay = 2.0 // 2 second delay until we clear recentlyScrolled
var recentlyScrolledTimer: NSTimer!
var scrollDirection = ScrollDirection()
var pageWidth: CGFloat!
var pageHeight: CGFloat!
var previousPageNumber: Int!
var currentPageNumber: Int!
var nextPageNumber: Int!
private var tempReference: FRTocReference?
private var isFirstLoad = true

enum ScrollDirection: Int {
    case None
    case Right
    case Left
    case Up
    case Down
    
    init() {
        self = .None
    }
}


class ScrollScrubber: NSObject, UIScrollViewDelegate {
    
    weak var delegate: FolioReaderCenter!
    var showSpeed = 0.6
    var hideSpeed = 0.6
    var hideDelay = 1.0
    
    var visible = false
    var usingSlider = false
    var slider: UISlider!
    var hideTimer: NSTimer!
    var scrollStart: CGFloat!
    var scrollDelta: CGFloat!
    var scrollDeltaTimer: NSTimer!
    
    init(frame:CGRect) {
        super.init()
        
        slider = UISlider()
        slider.layer.anchorPoint = CGPoint(x: 0, y: 0)
        slider.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
        slider.frame = frame
        slider.alpha = 0
        
        updateColors()
        
        // less obtrusive knob and fixes jump: http://stackoverflow.com/a/22301039/484780
        let thumbImg = UIImage(readerImageNamed: "knob")
        let thumbImgColor = thumbImg!.imageTintColor(readerConfig.tintColor).imageWithRenderingMode(.AlwaysOriginal)
        slider.setThumbImage(thumbImgColor, forState: .Normal)
        slider.setThumbImage(thumbImgColor, forState: .Selected)
        slider.setThumbImage(thumbImgColor, forState: .Highlighted)
        
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderChange(_:)), forControlEvents: .ValueChanged)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchDown(_:)), forControlEvents: .TouchDown)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchUp(_:)), forControlEvents: .TouchUpInside)
        slider.addTarget(self, action: #selector(ScrollScrubber.sliderTouchUp(_:)), forControlEvents: .TouchUpOutside)
    }
    
    func updateColors() {
        slider.minimumTrackTintColor = readerConfig.tintColor
        slider.maximumTrackTintColor = isNight(readerConfig.nightModeSeparatorColor, readerConfig.menuSeparatorColor)
    }
    
    // MARK: - slider events
    
    func sliderTouchDown(slider:UISlider) {
        usingSlider = true
        show()
    }
    
    func sliderTouchUp(slider:UISlider) {
        usingSlider = false
        hideAfterDelay()
    }
    
    func sliderChange(slider:UISlider) {
        let offset = CGPointMake(height()*CGFloat(slider.value), 0 )
        scrollView().setContentOffset(offset, animated: false)
    }
    
    // MARK: - show / hide
    
    func show() {
        
        cancelHide()
        
        visible = true
        
        if slider.alpha <= 0 {
            UIView.animateWithDuration(showSpeed, animations: {
                
                self.slider.alpha = 1
                
                }, completion: { (Bool) -> Void in
                    self.hideAfterDelay()
            })
        } else {
            slider.alpha = 1
            if usingSlider == false {
                hideAfterDelay()
            }
        }
    }
    
    
    func hide() {
        visible = false
        resetScrollDelta()
        UIView.animateWithDuration(hideSpeed, animations: {
            self.slider.alpha = 0
        })
    }
    
    func hideAfterDelay() {
        cancelHide()
        hideTimer = NSTimer.scheduledTimerWithTimeInterval(hideDelay, target: self, selector: #selector(ScrollScrubber.hide), userInfo: nil, repeats: false)
    }
    
    func cancelHide() {
        
        if hideTimer != nil {
            hideTimer.invalidate()
            hideTimer = nil
        }
        
        if visible == false {
            slider.layer.removeAllAnimations()
        }
        
        visible = true
    }
    
    func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        
        if scrollDeltaTimer != nil {
            scrollDeltaTimer.invalidate()
            scrollDeltaTimer = nil
        }
        
        if scrollStart == nil {
            scrollStart = scrollView.contentOffset.y
        }
    }
    
    func scrollViewDidScroll(scrollView: UIScrollView) {
        
        if visible && usingSlider == false {
            setSliderVal()
        }
        
        if( slider.alpha > 0 ){
            
            show()
            
        } else if delegate.currentPage != nil && scrollStart != nil {
            scrollDelta = scrollView.contentOffset.y - scrollStart
            
            if scrollDeltaTimer == nil && scrollDelta > (pageHeight * 0.2 ) || (scrollDelta * -1) > (pageHeight * 0.2) {
                show()
                resetScrollDelta()
            }
        }
    }
    
    func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        resetScrollDelta()
    }
    
    func scrollViewDidEndScrollingAnimation(scrollView: UIScrollView) {
        scrollDeltaTimer = NSTimer(timeInterval:0.5, target: self, selector: #selector(ScrollScrubber.resetScrollDelta), userInfo: nil, repeats: false)
        NSRunLoop.currentRunLoop().addTimer(scrollDeltaTimer, forMode: NSRunLoopCommonModes)
    }
    
    
    func resetScrollDelta(){
        if scrollDeltaTimer != nil {
            scrollDeltaTimer.invalidate()
            scrollDeltaTimer = nil
        }
        
        scrollStart = scrollView().contentOffset.y
        scrollDelta = 0
    }
    
    
    func setSliderVal(){
        slider.value = Float(scrollTop() / height())
    }
    
    // MARK: - utility methods
    
    private func scrollView() -> UIScrollView {
        return delegate.currentPage.webView.scrollView
    }
    
    private func height() -> CGFloat {
        return delegate.currentPage.webView.scrollView.contentSize.height - pageHeight + 44
    }
    
    private func scrollTop() -> CGFloat {
        return delegate.currentPage.webView.scrollView.contentOffset.y
    }
    
}



public class FolioReaderCenter: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, FolioPageDelegate, FolioReaderContainerDelegate, UIPopoverPresentationControllerDelegate {
    
    var collectionView: UICollectionView!
    var loadingView: UIActivityIndicatorView!
    var pages: [String]!
    var totalPages: Int!
    var tempFragment: String?
    var currentPage: FolioReaderPage!
    weak var folioReaderContainer: FolioReaderContainer!
    var animator: ZFModalTransitionAnimator!
    var pageIndicatorView: FolioReaderPageIndicator!
    var bookShareLink: String?
    
    var scrollScrubber: ScrollScrubber!
    var markButton : UIBarButtonItem!
    
    private var screenBounds: CGRect!
    private var pointNow = CGPointZero
    private let pageIndicatorHeight = 20 as CGFloat
    
    // MARK: - View life cicle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        screenBounds = UIScreen.mainScreen().bounds
        setPageSize(UIApplication.sharedApplication().statusBarOrientation)
        
        // Layout
        let layout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsetsZero
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = UICollectionViewScrollDirection.Horizontal
        
        let background = isNight(readerConfig.nightModeBackground, UIColor.whiteColor())
        view.backgroundColor = UIColor.clearColor() /*background*/
        
        // CollectionView
        collectionView = UICollectionView(frame: screenBounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.pagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = UIColor.clearColor()
        collectionView.decelerationRate = UIScrollViewDecelerationRateFast
        view.addSubview(collectionView)
        
        // Register cell classes
        collectionView!.registerClass(FolioReaderPage.self, forCellWithReuseIdentifier: reuseIdentifier)
        
        // Delegate container
        folioReaderContainer.delegate = self
        totalPages = book.spine.spineReferences.count
        
        // Configure navigation bar and layout
        automaticallyAdjustsScrollViewInsets = false
        extendedLayoutIncludesOpaqueBars = true
        configureNavBar()
        
        // Page indicator view
        if readerConfig.showPageCount {//<---MOD BY JUANES
            pageIndicatorView = FolioReaderPageIndicator(frame: CGRect(x: 0, y: view.frame.height-pageIndicatorHeight, width: view.frame.width, height: pageIndicatorHeight))
            view.addSubview(pageIndicatorView)
        }
        
        let scrubberY: CGFloat = readerConfig.shouldHideNavigationOnTap == true ? 50 : 74
        scrollScrubber = ScrollScrubber(frame: CGRect(x: pageWidth + 10, y: scrubberY, width: 40, height: pageHeight - 100))
        scrollScrubber.delegate = self
//        view.addSubview(scrollScrubber.slider)
        
        // Loading indicator
        let style: UIActivityIndicatorViewStyle = isNight(/*.White*/.Gray, .Gray)
        loadingView = UIActivityIndicatorView(activityIndicatorStyle: style)
        loadingView.center = view.center
        loadingView.hidesWhenStopped = true
        loadingView.startAnimating()
        view.addSubview(loadingView)
    }
    
    
    override public func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        // Reset load
        isFirstLoad = true
        
        // Update pages
        
        if readerConfig.showPageCount {//<---MOD BY JUANES
            pagesForCurrentPage(currentPage)
            pageIndicatorView.reloadView(updateShadow: true)
        }
    }

    func configureNavBar() {
        let navBackground = UIColor.whiteColor() /*isNight(readerConfig.nightModeMenuBackground, UIColor.whiteColor())*/
        let tintColor = readerConfig.tintColor
        let navText = UIColor.blackColor() /*isNight(UIColor.whiteColor(), UIColor.blackColor())*/
        let font = UIFont(name: "Avenir-Light", size: 17)!
        setTranslucentNavigation(color: navBackground, tintColor: tintColor, titleColor: navText, andFont: font)
    }
    
    public func configureNavBarButtons() {

        // Navbar buttons
        let shareIcon = UIImage(readerImageNamed: "btn-navbar-share")!.imageTintColor(readerConfig.tintColor).imageWithRenderingMode(.AlwaysOriginal)
        let audioIcon = UIImage(readerImageNamed: "man-speech-icon")!.imageTintColor(readerConfig.tintColor).imageWithRenderingMode(.AlwaysOriginal)
        let menuIcon = UIImage(readerImageNamed: "btn-navbar-menu")!.imageTintColor(readerConfig.tintColor).imageWithRenderingMode(.AlwaysOriginal)
        
            //MOD BY QUATIO
            let fontSmall = UIImage(readerImageNamed: "icon-font-small")
            let fontBig = UIImage(readerImageNamed: "icon-font-big")
            let imageClose = UIImage(readerImageNamed: "icon-close")
        
            let checkmark = UIImage(named:"checkmark")
            let search = UIImage(named: "search")
            let options = UIImage(named: "options")
        
        
        let navBarItem = UIBarButtonItem(image: imageClose, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.didSelectClose(_:)))
        var items = [UIBarButtonItem]()
        items.append(navBarItem)
        var creators = ""
        for c in book.metadata.creators {
            creators += "\(c.name), "
        }
        let d = creators.characters.count - 2
        creators = (creators.substringToIndex(creators.endIndex.advancedBy(-2)))
        var title = "\(book.title()!) - \(creators)"
        if(title.characters.count > 50){
            title = (title.substringToIndex(title.startIndex.advancedBy(47))) + "..."
        }
        items.append(UIBarButtonItem(title: title, style: UIBarButtonItemStyle.Plain, target: self, action: nil))
        
        navigationItem.leftBarButtonItems = items
        
        var rightBarIcons = [UIBarButtonItem]()
        
            //MOD BY QUATIO
        rightBarIcons.append(UIBarButtonItem(image: options, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.presentOptionsMenu)))
        rightBarIcons.append(UIBarButtonItem(image: menuIcon, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.didSelectHighlight)))
        rightBarIcons.append(UIBarButtonItem(image: search, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.SearchText(_:))))
        
        markButton = UIBarButtonItem(image: checkmark, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.markPage))
        
        rightBarIcons.append(markButton)
        rightBarIcons.append(UIBarButtonItem(image: fontBig, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.increaceFontSize)))
        rightBarIcons.append(UIBarButtonItem(image: fontSmall, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.reduceFontSize)))
            //
        
        if readerConfig.allowSharing {
            rightBarIcons.append(UIBarButtonItem(image: shareIcon, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.shareChapter(_:))))
        }

        if book.hasAudio() || readerConfig.enableTTS {
            rightBarIcons.append(UIBarButtonItem(image: audioIcon, style: UIBarButtonItemStyle.Plain, target: self, action:#selector(FolioReaderCenter.togglePlay(_:))))
        }

        navigationItem.rightBarButtonItems = rightBarIcons
    }

    func reloadData() {
        loadingView.stopAnimating()
        bookShareLink = readerConfig.localizedShareWebLink
        totalPages = book.spine.spineReferences.count

        collectionView.reloadData()
        configureNavBarButtons()
        
        if let position = FolioReader.defaults.valueForKey(kBookId) as? NSDictionary,
            let pageNumber = position["pageNumber"] as? Int where pageNumber > 0 {
            changePageWith(page: pageNumber)
            currentPageNumber = pageNumber
            return
        }
        
        currentPageNumber = 1
    }
    
    func reloadWebView() {
        
        collectionView.reloadData()
        changePageWith(page: currentPageNumber)
    }
    
    // MARK: Status bar and Navigation bar
    
    func hideBars() {

        if readerConfig.shouldHideNavigationOnTap == false { return }

        let shouldHide = true
        FolioReader.sharedInstance.readerContainer.shouldHideStatusBar = shouldHide
        
        UIView.animateWithDuration(0.25, animations: {
            FolioReader.sharedInstance.readerContainer.setNeedsStatusBarAppearanceUpdate()
            
            // Show minutes indicator
//            self.pageIndicatorView.minutesLabel.alpha = 0
        })
        navigationController?.setNavigationBarHidden(shouldHide, animated: true)
    }
    
    func showBars() {
        configureNavBar()
        
        let shouldHide = false
        FolioReader.sharedInstance.readerContainer.shouldHideStatusBar = shouldHide
        
        UIView.animateWithDuration(0.25, animations: {
            FolioReader.sharedInstance.readerContainer.setNeedsStatusBarAppearanceUpdate()
        })
        navigationController?.setNavigationBarHidden(shouldHide, animated: true)
    }
    
    func toggleBars() {
        if readerConfig.shouldHideNavigationOnTap == false { return }
        
        let shouldHide = !navigationController!.navigationBarHidden
        if !shouldHide { configureNavBar() }
        
        FolioReader.sharedInstance.readerContainer.shouldHideStatusBar = shouldHide
        
        UIView.animateWithDuration(0.25, animations: {
            FolioReader.sharedInstance.readerContainer.setNeedsStatusBarAppearanceUpdate()
            
            // Show minutes indicator
//            self.pageIndicatorView.minutesLabel.alpha = shouldHide ? 0 : 1
        })
        navigationController?.setNavigationBarHidden(shouldHide, animated: true)
    }

    func togglePlay(sender: UIBarButtonItem) {
        presentPlayerMenu()
    }

    // MARK: Toggle menu
    
    func toggleMenu() {
        FolioReader.sharedInstance.readerContainer.toggleLeftPanel()
    }
        
    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MOD BY QUATIO
    //MARK: CloseController
    
    internal func didSelectClose(sender: UIBarButtonItem) {
        FolioReader.saveReaderState()
        self.dismissViewControllerAnimated(true, completion: {
            FolioReader.sharedInstance.isReaderOpen = false
            FolioReader.sharedInstance.isReaderReady = false
            
        })
    }
    
    // MARK: UICollectionViewDataSource
    
    public func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 1
    }
    
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return totalPages
    }
    
    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(reuseIdentifier, forIndexPath: indexPath) as! FolioReaderPage
        
        cell.pageNumber = indexPath.row+1
        cell.webView.scrollView.delegate = self
        cell.delegate = self
        cell.backgroundColor = UIColor.clearColor()
        

        let resource = book.spine.spineReferences[indexPath.row].resource
        let html = createHtmlForPage(indexPath.row)!
        cell.setOriginalHTML()
        cell.loadHTMLString(html, baseURL: NSURL(fileURLWithPath: (resource.fullHref as NSString).stringByDeletingLastPathComponent))
        return cell
    }
    
    public func changeBackgroundColor(i: Int){
        switch i {
        case 0:
            view.backgroundColor = UIColor.whiteColor()
            collectionView.backgroundColor = UIColor.whiteColor()
        case 1:
            view.backgroundColor = UIColor.grayColor()
            collectionView.backgroundColor = UIColor.grayColor()
        case 2:
            view.backgroundColor = UIColor.lightGrayColor()
            collectionView.backgroundColor = UIColor.lightGrayColor()
        case 3:
            view.backgroundColor = UIColor.darkGrayColor()
            collectionView.backgroundColor = UIColor.darkGrayColor()
        default:
            break
        }
        if FolioReader.sharedInstance.nightMode {
            view.backgroundColor = UIColor.blackColor()
            collectionView.backgroundColor = UIColor.blackColor()
        }
        
    }
    
    func createHtmlForPage(index : Int) -> String? {
    
        // Configure the cell
        let resource = book.spine.spineReferences[index].resource
        var html = try? String(contentsOfFile: resource.fullHref, encoding: NSUTF8StringEncoding)
        let mediaOverlayStyleColors = "\"\(readerConfig.mediaOverlayColor.hexString(false))\", \"\(readerConfig.mediaOverlayColor.highlightColor().hexString(false))\""
        
        // Inject CSS
        let jsFilePath = NSBundle.frameworkBundle().pathForResource("Bridge", ofType: "js")
        let cssFilePath = NSBundle.frameworkBundle().pathForResource("Style", ofType: "css")
        let cssTag = "<link rel=\"stylesheet\" type=\"text/css\" href=\"\(cssFilePath!)\">"
        let jsTag = "<script type=\"text/javascript\" src=\"\(jsFilePath!)\"></script>" +
            "<script type=\"text/javascript\">setMediaOverlayStyleColors(\(mediaOverlayStyleColors))</script>"
        
        let toInject = "\n\(cssTag)\n\(jsTag)\n</head>"
        html = html?.stringByReplacingOccurrencesOfString("</head>", withString: toInject)
        
        // Font class name
        var classes = ""
        if html!.containsString("<meta name=\"viewport\"") {
            
            print("Fixed layout")
            changeBackgroundColor(0)
        }else{
            
            let currentFontName = FolioReader.sharedInstance.currentFontName
            switch currentFontName {
            case 0:
                classes = "andada"
                break
            case 1:
                classes = "lato"
                break
            case 2:
                classes = "lora"
                break
            case 3:
                classes = "raleway"
                break
            default:
                break
            }
            
            classes += " "+FolioReader.sharedInstance.currentMediaOverlayStyle.className()
            
            // Night mode
            if FolioReader.sharedInstance.nightMode {
                classes += " nightMode"
            }
            
            // Font Size
            let currentFontSize = FolioReader.sharedInstance.currentFontSize
            switch currentFontSize {
            case 0:
                classes += " textSize1"
                break
            case 1:
                classes += " textSize2"
                break
            case 2:
                classes += " textSize3"
                break
            case 3:
                classes += " textSize4"
                break
            case 4:
                classes += " textSize5"
                break
            default:
                break
            }
            
            // Margin
            let currentMargin = FolioReader.sharedInstance.currentMargin
            classes += " margin-\(currentMargin)"
            
            // Interlineado
            let currentInter = FolioReader.sharedInstance.currentInterline
            classes += " interline-\(currentInter)"
            
            // Two Columns
            if FolioReader.sharedInstance.TwoColumns {
                classes += " two-cols"
            }
            
            //Font Color
            switch FolioReader.sharedInstance.currentFontColor {
            case 0:
                classes += " color-1"
            case 1:
                classes += " color-2"
            case 2:
                classes += " color-3"
            case 3:
                classes += " color-4"
            default: break
            }
            
            var st = ""
            switch FolioReader.sharedInstance.currentBackgroundColor {
            case 0:
                classes += " background-1"
            case 1:
                classes += " background-2"
            case 2:
                classes += " background-3"
            case 3:
                classes += " background-4"
            default:
                break
            }
            changeBackgroundColor(FolioReader.sharedInstance.currentBackgroundColor)
            
        }
        
        html = html?.stringByReplacingOccurrencesOfString("<html ", withString: "<html class=\"\(classes)\"")
        return html
    }
    
    public func pressentAlertForHighlight(){
    
        
        let alert = UIAlertController(title: "Alerta", message: "No se puede crear la nota porque hay otra nota en la selección", preferredStyle: UIAlertControllerStyle.Alert)
        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertActionStyle.Default, handler: { action in
            alert.dismiss()
        }))
        self.presentViewController(alert, animated: true, completion: nil)
    }
    
    public func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        return CGSizeMake(pageWidth, pageHeight)
    }
    
    // MARK: - Device rotation
    
    override public func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        if !FolioReader.sharedInstance.isReaderReady { return }
        
        setPageSize(toInterfaceOrientation)
        updateCurrentPage()
        
        var pageIndicatorFrame = collectionView.frame
        if readerConfig.showPageCount {//<---MOD BY JUANES
            pageIndicatorFrame = pageIndicatorView.frame
            pageIndicatorFrame.origin.y = pageHeight-pageIndicatorHeight
            pageIndicatorFrame.origin.x = 0
            pageIndicatorFrame.size.width = pageWidth
        }
        
        var scrollScrubberFrame = scrollScrubber.slider.frame;
        scrollScrubberFrame.origin.x = pageWidth + 10
        scrollScrubberFrame.size.height = pageHeight - 100
        
        UIView.animateWithDuration(duration, animations: {
            
            // Adjust page indicator view
            if readerConfig.showPageCount {//<---MOD BY JUANES
                self.pageIndicatorView.frame = pageIndicatorFrame
                self.pageIndicatorView.reloadView(updateShadow: true)
            }
            
            // adjust scroll scrubber slider
            self.scrollScrubber.slider.frame = scrollScrubberFrame
            
            // Adjust collectionView
            self.collectionView.contentSize = CGSizeMake(pageWidth, pageHeight * CGFloat(self.totalPages))
            self.collectionView.setContentOffset(self.frameForPage(currentPageNumber).origin, animated: false)
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }
    
    override public func didRotateFromInterfaceOrientation(fromInterfaceOrientation: UIInterfaceOrientation) {
        if !FolioReader.sharedInstance.isReaderReady { return }
        
        // Update pages
        if readerConfig.showPageCount {//<---MOD BY JUANES
            pagesForCurrentPage(currentPage)
        }
        scrollScrubber.setSliderVal()
    }
    
    override public func willAnimateRotationToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        if !FolioReader.sharedInstance.isReaderReady { return }
        
        if currentPageNumber+1 >= totalPages {
            UIView.animateWithDuration(duration, animations: {
                self.collectionView.setContentOffset(self.frameForPage(currentPageNumber).origin, animated: false)
            })
        }
    }
    
    // MARK: - Page
    
    func setPageSize(orientation: UIInterfaceOrientation) {
        if orientation.isPortrait {
            if screenBounds.size.width < screenBounds.size.height {
                pageWidth = screenBounds.size.width
                pageHeight = screenBounds.size.height
            } else {
                pageWidth = screenBounds.size.height
                pageHeight = screenBounds.size.width
            }
        } else {
            if screenBounds.size.width > screenBounds.size.height {
                pageWidth = screenBounds.size.width
                pageHeight = screenBounds.size.height
            } else {
                pageWidth = screenBounds.size.height
                pageHeight = screenBounds.size.width
            }
        }
    }
    
    func updateCurrentPage(completion: (() -> Void)? = nil) {
        updateCurrentPage(nil) { () -> Void in
            if (completion != nil) { completion!() }
        }
    }
    
    func updateCurrentPage(page: FolioReaderPage!, completion: (() -> Void)? = nil) {
        if let page = page {
            currentPage = page
            previousPageNumber = page.pageNumber-1
            currentPageNumber = page.pageNumber
            changeMarkValue()
        } else {
            let currentIndexPath = getCurrentIndexPath()
            if currentIndexPath != NSIndexPath(forRow: 0, inSection: 0) {
                currentPage = collectionView.cellForItemAtIndexPath(currentIndexPath) as! FolioReaderPage
            }
            
            previousPageNumber = currentIndexPath.row
            currentPageNumber = currentIndexPath.row+1
//            print("currentPageNumber \(currentPageNumber) currentPage \(currentPage.pageNumber)")
            changeMarkValue()
        }
        nextPageNumber = currentPageNumber+1 <= totalPages ? currentPageNumber+1 : currentPageNumber
        
        // Set navigation title
        if let chapterName = getCurrentChapterName() {
            title = chapterName
        } else { title = ""}
        
        // Set pages
        if let page = currentPage {
            page.webView.becomeFirstResponder()
            
//            scrollScrubber.setSliderVal()
            
            if readerConfig.showPageCount {//<---MOD BY JUANES
                if let readingTime = page.webView.js("getReadingTime()") {
                    pageIndicatorView.totalMinutes = Int(readingTime)!
                    pagesForCurrentPage(page)
                }
            }
        }
        
        if (completion != nil) { completion!() }
    }
    
    func pagesForCurrentPage(page: FolioReaderPage?) {
        if let page = page {
            pageIndicatorView.totalPages = Int(ceil(page.webView.scrollView.contentSize.height/pageHeight))
            let webViewPage = pageForOffset(currentPage.webView.scrollView.contentOffset.y, pageHeight: pageHeight)
            pageIndicatorView.currentPage = webViewPage
        }
    }
    
    func pageForOffset(offset: CGFloat, pageHeight height: CGFloat) -> Int {
        let page = Int(ceil(offset / height))+1
        return page
    }
    
    func getCurrentIndexPath() -> NSIndexPath {
        let indexPaths = collectionView.indexPathsForVisibleItems()
        var indexPath = NSIndexPath()
        
        if indexPaths.count > 1 {
            let first = indexPaths.first! as NSIndexPath
            let last = indexPaths.last! as NSIndexPath
            
            switch scrollDirection {
            case .Up:
                if first.compare(last) == NSComparisonResult.OrderedAscending {
                    indexPath = last
                } else {
                    indexPath = first
                }
            default:
                if first.compare(last) == NSComparisonResult.OrderedAscending {
                    indexPath = first
                } else {
                    indexPath = last
                }
            }
        } else {
            indexPath = indexPaths.first ?? NSIndexPath(forRow: 0, inSection: 0)
        }
        
        return indexPath
    }
    
    func frameForPage(page: Int) -> CGRect {
        return CGRectMake(pageWidth * CGFloat(page), 0 , pageWidth, pageHeight)
    }
    //2
    func changePageWith(page page: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
        if page > 0 && page-1 < totalPages {
            let indexPath = NSIndexPath(forRow: page-1, inSection: 0)
            changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
                self.updateCurrentPage({ () -> Void in
                    if (completion != nil) { completion!() }
                })
            })
        }
    }
    //1
    func changePageWith(page page: Int, andFragment fragment: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if currentPageNumber == page {
            if fragment != "" && currentPage != nil {
                currentPage.handleAnchor(fragment, avoidBeginningAnchors: true, animating: animated)
                if (completion != nil) { completion!() }
            }
        } else {
            tempFragment = fragment
            changePageWith(page: page, animated: animated, completion: { () -> Void in
                self.updateCurrentPage({ () -> Void in
                    if (completion != nil) { completion!() }
//                    self.currentPage.handleAnchor(fragment, avoidBeginningAnchors: true, animating: animated)
                })
            })
        }
    }
    
    func changePageWith(href href: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        let item = findPageByHref(href)
        let indexPath = NSIndexPath(forRow: item, inSection: 0)
        changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
            self.updateCurrentPage({ () -> Void in
                if (completion != nil) { completion!() }
            })
        })
    }

    func changePageWith(href href: String, andAudioMarkID markID: String) {
        if recentlyScrolled { return } // if user recently scrolled, do not change pages or scroll the webview

        let item = findPageByHref(href)
        let pageUpdateNeeded = item+1 != currentPage.pageNumber
        let indexPath = NSIndexPath(forRow: item, inSection: 0)
        changePageWith(indexPath: indexPath, animated: true) { () -> Void in
            if pageUpdateNeeded {
                self.updateCurrentPage({ () -> Void in
                    self.currentPage.audioMarkID(markID);
                })
            } else {
                self.currentPage.audioMarkID(markID);
            }
        }
    }
    //3
    func changePageWith(indexPath indexPath: NSIndexPath, animated: Bool = false, completion: (() -> Void)? = nil) {
        UIView.animateWithDuration(animated ? 0.3 : 0, delay: 0, options: .CurveEaseInOut, animations: { () -> Void in
            self.collectionView.scrollToItemAtIndexPath(indexPath, atScrollPosition: .Left, animated: false)
            }) { (finished: Bool) -> Void in
                if (completion != nil) { completion!() }
        }
    }
    
    func isLastPage() -> Bool{
        return currentPageNumber == nextPageNumber
    }

    func changePageToNext(completion: (() -> Void)? = nil) {
        changePageWith(page: nextPageNumber, animated: true) { () -> Void in
            if (completion != nil) { completion!() }
        }
    }
    
    func changePageToPrevious(completion: (() -> Void)? = nil) {
        changePageWith(page: previousPageNumber, animated: true) { () -> Void in
            if (completion != nil) { completion!() }
        }
    }

    /**
    Find a page by FRTocReference.
    */
    func findPageByResource(reference: FRTocReference) -> Int {
        var count = 0
        for item in book.spine.spineReferences {
            if let resource = reference.resource where item.resource.href == resource.href {
                return count
            }
            count += 1
        }
        return count
    }
    
    /**
    Find a page by href.
    */
    func findPageByHref(href: String) -> Int {
        var count = 0
        for item in book.spine.spineReferences {
            if item.resource.href == href {
                return count
            }
            count += 1
        }
        return count
    }
    
    /**
    Find and return the current chapter resource.
    */
    func getCurrentChapter() -> FRResource? {
        if let currentPageNumber = currentPageNumber {
            for item in FolioReader.sharedInstance.readerSidePanel.tocItems {
                if let reference = book.spine.spineReferences[safe: currentPageNumber-1], resource = item.resource
                    where resource.href == reference.resource.href {
                    return item.resource
                }
            }
        }
        return nil
    }

    /**
     Find and return the current chapter name.
     */
    func getCurrentChapterName() -> String? {
        if let currentPageNumber = currentPageNumber {
            for item in FolioReader.sharedInstance.readerSidePanel.tocItems {
                if let reference = book.spine.spineReferences[safe: currentPageNumber-1], resource = item.resource
                    where resource.href == reference.resource.href {
                    if let title = item.title {
                        return title
                    }
                    return nil
                }
            }
        }
        return nil
    }
    
    // MARK: - Audio Playing

    func playAudio(fragmentID: String){

        let chapter = getCurrentChapter()
        let href = chapter != nil ? chapter!.href : "";
        FolioReader.sharedInstance.readerAudioPlayer.playAudio(href, fragmentID: fragmentID)
    }

    func audioMark(href href: String, fragmentID: String) {
        changePageWith(href: href, andAudioMarkID: fragmentID)
    }

    // MARK: - Sharing
    
    /**
    Sharing chapter method.
    */
    func shareChapter(sender: UIBarButtonItem) {
        
        if let chapterText = currentPage.webView.js("getBodyText()") {
            
            let htmlText = chapterText.stringByReplacingOccurrencesOfString("[\\n\\r]+", withString: "<br />", options: .RegularExpressionSearch)

            var subject = readerConfig.localizedShareChapterSubject
            var html = ""
            var text = ""
            var bookTitle = ""
            var chapterName = ""
            var authorName = ""
            
            // Get book title
            if let title = book.title() {
                bookTitle = title
                subject += " “\(title)”"
            }
            
            // Get chapter name
            if let chapter = getCurrentChapterName() {
                chapterName = chapter
            }
            
            // Get author name
            if let author = book.metadata.creators.first {
                authorName = author.name
            }
            
            // Sharing html and text
            html = "<html><body>"
            html += "<br /><hr> <p>\(htmlText)</p> <hr><br />"
            html += "<center><p style=\"color:gray\">"+readerConfig.localizedShareAllExcerptsFrom+"</p>"
            html += "<b>\(bookTitle)</b><br />"
            html += readerConfig.localizedShareBy+" <i>\(authorName)</i><br />"
            if (bookShareLink != nil) { html += "<a href=\"\(bookShareLink!)\">\(bookShareLink!)</a>" }
            html += "</center></body></html>"
            text = "\(chapterName)\n\n“\(chapterText)” \n\n\(bookTitle) \nby \(authorName)"
            if (bookShareLink != nil) { text += " \n\(bookShareLink!)" }
            
            
            let act = FolioReaderSharingProvider(subject: subject, text: text, html: html)
            let shareItems = [act, ""]
            let activityViewController = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
            activityViewController.excludedActivityTypes = [UIActivityTypePrint, UIActivityTypePostToVimeo, UIActivityTypePostToFacebook]
            
            // Pop style on iPad
            if let actv = activityViewController.popoverPresentationController {
                actv.barButtonItem = sender
            }
            
            presentViewController(activityViewController, animated: true, completion: nil)
        }
    }
    
    /**
    Sharing highlight method.
    */
    func shareHighlight(string: String, rect: CGRect) {
        
        var subject = readerConfig.localizedShareHighlightSubject
        var html = ""
        var text = ""
        var bookTitle = ""
        var chapterName = ""
        var authorName = ""
        
        // Get book title
        if let title = book.title() {
            bookTitle = title
            subject += " “\(title)”"
        }
        
        // Get chapter name
        if let chapter = getCurrentChapterName() {
            chapterName = chapter
        }
        
        // Get author name
        if let author = book.metadata.creators.first {
            authorName = author.name
        }
        
        // Sharing html and text
        html = "<html><body>"
        html += "<br /><hr> <p>\(chapterName)</p>"
        html += "<p>\(string)</p> <hr><br />"
        html += "<center><p style=\"color:gray\">"+readerConfig.localizedShareAllExcerptsFrom+"</p>"
        html += "<b>\(bookTitle)</b><br />"
        html += readerConfig.localizedShareBy+" <i>\(authorName)</i><br />"
        if (bookShareLink != nil) { html += "<a href=\"\(bookShareLink!)\">\(bookShareLink!)</a>" }
        html += "</center></body></html>"
        text = "\(chapterName)\n\n“\(string)” \n\n\(bookTitle) \nby \(authorName)"
        if (bookShareLink != nil) { text += " \n\(bookShareLink!)" }
        
        
        let act = FolioReaderSharingProvider(subject: subject, text: text, html: html)
        let shareItems = [act, ""]
        let activityViewController = UIActivityViewController(activityItems: shareItems, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [UIActivityTypePrint, UIActivityTypePostToVimeo, UIActivityTypePostToFacebook]
        
        // Pop style on iPad
        if let actv = activityViewController.popoverPresentationController {
            actv.sourceView = currentPage
            actv.sourceRect = rect
        }
        
        presentViewController(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - Folio Page Delegate
    
    func pageDidLoad(page: FolioReaderPage) {
        
        if let position = FolioReader.defaults.valueForKey(kBookId) as? NSDictionary {
            let pageNumber = position["pageNumber"]! as! Int
            let pageOffset = position["pageOffset"]! as! CGFloat
            
            if isFirstLoad {
                updateCurrentPage(page)
                isFirstLoad = false
                
                if currentPageNumber == pageNumber && pageOffset > 0 {
                    page.scrollPageToOffset("\(pageOffset)", animating: false)
                }
            }
            
        } else if isFirstLoad {
            updateCurrentPage(page)
            isFirstLoad = false
        }
        
        // Go to fragment if needed
        if let fragment = tempFragment where fragment != "" && currentPage != nil {
            currentPage.handleAnchor(fragment, avoidBeginningAnchors: true, animating: true)
            tempFragment = nil
        }
    }
    
    // MARK: - ScrollView Delegate
    
    public func scrollViewWillBeginDragging(scrollView: UIScrollView) {
        isScrolling = true
        clearRecentlyScrolled()
        recentlyScrolled = true
        pointNow = scrollView.contentOffset
        
        if let currentPage = currentPage {
            currentPage.webView.createMenu(options: true)
            currentPage.webView.setMenuVisible(false)
        }
        
        scrollScrubber.scrollViewWillBeginDragging(scrollView)
    }
    
    public func scrollViewDidScroll(scrollView: UIScrollView) {
        
        if !navigationController!.navigationBarHidden {
            toggleBars()
        }
        
        scrollScrubber.scrollViewDidScroll(scrollView)
        
        // Update current reading page
        if scrollView is UICollectionView {} else {
            if let page = currentPage where page.webView.scrollView.contentOffset.y+pageHeight <= page.webView.scrollView.contentSize.height {
                let webViewPage = pageForOffset(page.webView.scrollView.contentOffset.y, pageHeight: pageHeight)
                if readerConfig.showPageCount { //<---MOD BY JUANES
                    if pageIndicatorView.currentPage != webViewPage {
                        pageIndicatorView.currentPage = webViewPage
                    }
                }
            }
        }
        
        scrollDirection = scrollView.contentOffset.y < pointNow.y ? .Down : .Up
    }
    
    public func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
        isScrolling = false
        
        if scrollView is UICollectionView {
            if totalPages > 0 {
//                updateCurrentPage()
                let int = scrollView.contentOffset.x / pageWidth
//                currentPageNumber = (collectionView.indexPathForCell(collectionView.visibleCells()[0])?.row)! + 1
                let currentIndexPath = NSIndexPath(forRow: Int(int), inSection: 0)
                currentPage = collectionView.cellForItemAtIndexPath(currentIndexPath) as! FolioReaderPage
                updateCurrentPage(currentPage)
            }
        }
//        scrollScrubber.scrollViewDidEndDecelerating(scrollView)
    }
    
    public func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        recentlyScrolledTimer = NSTimer(timeInterval:recentlyScrolledDelay, target: self, selector: #selector(FolioReaderCenter.clearRecentlyScrolled), userInfo: nil, repeats: false)
        NSRunLoop.currentRunLoop().addTimer(recentlyScrolledTimer, forMode: NSRunLoopCommonModes)
    }

    func clearRecentlyScrolled(){
        if( recentlyScrolledTimer != nil ){
            recentlyScrolledTimer.invalidate()
            recentlyScrolledTimer = nil
        }
        recentlyScrolled = false
    }

    public func scrollViewDidEndScrollingAnimation(scrollView: UIScrollView) {
        scrollScrubber.scrollViewDidEndScrollingAnimation(scrollView)
    }
    
    // MARK: - Container delegate
    
    func container(didExpandLeftPanel sidePanel: FolioReaderSidePanel) {
        collectionView.userInteractionEnabled = false
        FolioReader.saveReaderState()
    }
    
    func container(didCollapseLeftPanel sidePanel: FolioReaderSidePanel) {
        collectionView.userInteractionEnabled = true
        updateCurrentPage()
        
        // Move to #fragment
        if tempReference != nil {
            if tempReference!.fragmentID != "" && currentPage != nil {
                currentPage.handleAnchor(tempReference!.fragmentID!, avoidBeginningAnchors: true, animating: true)
            }
            tempReference = nil
        }
    }
    
    func container(sidePanel: FolioReaderSidePanel, didSelectRowAtIndexPath indexPath: NSIndexPath, withTocReference reference: FRTocReference) {
        let item = findPageByResource(reference)
//        print("item: \(item) totalPages: \(totalPages) reference: \(reference)") // <----Esto no debería ir aquí
        if item < totalPages {
            let indexPath = NSIndexPath(forRow: item, inSection: 0)
            changePageWith(indexPath: indexPath, animated: false, completion: { () -> Void in
                self.updateCurrentPage()
                self.frameForPage(item)
            })
            tempReference = reference
        } else {
            print("Failed to load book because the requested resource is missing.")
        }
    }
    
    // MARK: - Fonts Menu
    
    func presentFontsMenu() {
        hideBars()
        
        let menu = FolioReaderFontsMenu()
        menu.modalPresentationStyle = .Custom

        animator = ZFModalTransitionAnimator(modalViewController: menu)
        animator.dragable = false
        animator.bounces = false
        animator.behindViewAlpha = 0.4
        animator.behindViewScale = 1
        animator.transitionDuration = 0.6
        animator.direction = ZFModalTransitonDirection.Bottom

        menu.transitioningDelegate = animator
        presentViewController(menu, animated: true, completion: nil)
    }
    
    //MOD QUATIO
    func presentOptionsMenu() {
        let menu = FolioReaderOptionsController()
        menu.modalPresentationStyle = UIModalPresentationStyle.OverCurrentContext
        presentViewController(menu, animated: true, completion: nil)
    }
    
    
    internal func changeFontSize(i : Int){
        let currentPage = FolioReader.sharedInstance.readerCenter.currentPage
        
        switch i {
        case 0:
            currentPage.webView.js("setFontSize('textSize1')")
            break
        case 1:
            currentPage.webView.js("setFontSize('textSize2')")
            break
        case 2:
            currentPage.webView.js("setFontSize('textSize3')")
            break
        case 3:
            currentPage.webView.js("setFontSize('textSize4')")
            break
        case 4:
            currentPage.webView.js("setFontSize('textSize5')")
            break
        default:
            break
        }
        FolioReader.sharedInstance.currentFontSize = i
    }
    
    internal func reduceFontSize(){
        
        var size = FolioReader.sharedInstance.currentFontSize
        size--
        if size < 0 {
            size = 0
        }
        changeFontSize(size)
    }
    
    internal func increaceFontSize(){
        
        var size = FolioReader.sharedInstance.currentFontSize
        size++
        if size > 4 {
            size = 4
        }
        changeFontSize(size)
    }
    
    func openOptionsPanel() {
//        FolioReader.sharedInstance.readerContainer.toggleLeftPanel()
        FolioReader.sharedInstance.readerCenter.presentFontsMenu()
    }
    
    func SearchText(sender : UIBarButtonItem){
        
//        let searchView = UINavigationController(rootViewController: FolioReaderSearchView())
//        presentViewController(searchView, animated: true, completion: nil)
    
        
        let alertController = SearchTextController()
        let menu = UINavigationController(rootViewController: alertController)
//        alertController.modalPresentationStyle = .Popover
//        let popover: UIPopoverPresentationController = alertController.popoverPresentationController!
//        popover.barButtonItem = sender
////        popover.sourceRect = CGRect(x: 0, y: 0, width: 250, height: 50)
//        popover.delegate = self
        presentViewController(menu, animated: true, completion:nil)
    }
    
    func markPage() {
        
        if !book.pageMarks.contains(currentPageNumber) {
            book.pageMarks.append(currentPageNumber)
        }else{
            print(book.pageMarks)
            book.pageMarks.removeAtIndex(book.pageMarks.indexOf(currentPageNumber)!)
        }
        
//        print("Actualise defaults: \(book.pageMarks)")
        changeMarkValue()
    }
    
    func changeMarkValue(){
        if book.pageMarks.contains(currentPageNumber){
            markButton.image = UIImage(named:"checkmark")!.imageTintColor(readerConfig.tintColor.darkerColor(10)).imageWithRenderingMode(.AlwaysOriginal)
        }else{
            markButton.image = UIImage(named:"checkmark")!
        }
    }
    
    func didSelectHighlight(sender: UIBarButtonItem) {
//        FolioReader.sharedInstance.readerContainer.toggleLeftPanel()
        
        let alertController = PopOverMarks()
        alertController.modalPresentationStyle = .Popover
        let popover: UIPopoverPresentationController = alertController.popoverPresentationController!
        popover.barButtonItem = sender
        popover.sourceRect = CGRect(x: 0, y: 0, width: 250, height: 150)
        popover.delegate = self
        presentViewController(alertController, animated: true, completion:nil)
        
    }
    
    public func addNoteToHighlight (id : String){
    
        let alertController = PopOverNote()
        
        for h in Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension) {
            if h.highlightId == id {
            
                alertController.highlight = h
            }
        }
        alertController.modalPresentationStyle = UIModalPresentationStyle.OverCurrentContext
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    public func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.None
    }
    
    func showHiglightList(){
        FolioReader.sharedInstance.readerCenter.presentHighlightsList()
    }
    //------
    
    // MARK: - Highlights List
    
    func presentHighlightsList() {
        let menu = UINavigationController(rootViewController: FolioReaderHighlightList())
        presentViewController(menu, animated: true, completion: nil)
    }
    
    func presentPageMarksList() {
        let menu = UINavigationController(rootViewController: PageMarkList())
        presentViewController(menu, animated: true, completion: nil)
    }

    // MARK: - Audio Player Menu

    func presentPlayerMenu() {
        hideBars()

        let menu = FolioReaderPlayerMenu()
        menu.modalPresentationStyle = .Custom

        animator = ZFModalTransitionAnimator(modalViewController: menu)
        animator.dragable = true
        animator.bounces = false
        animator.behindViewAlpha = 0.4
        animator.behindViewScale = 1
        animator.transitionDuration = 0.6
        animator.direction = ZFModalTransitonDirection.Bottom

        menu.transitioningDelegate = animator
        presentViewController(menu, animated: true, completion: nil)
    }
}
