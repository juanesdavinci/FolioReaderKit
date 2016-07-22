//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SafariServices
import UIMenuItem_CXAImageSupport
import JSQWebViewController

@objc protocol FolioPageDelegate: class {
    optional func pageDidLoad(page: FolioReaderPage)
}

public class FolioReaderPage: UICollectionViewCell, UIWebViewDelegate, UIGestureRecognizerDelegate, FolioReaderAudioPlayerDelegate {
    
    var pageNumber: Int!
    var webView: UIWebView!
    var bURL : NSURL!
    weak var delegate: FolioPageDelegate!
    private var shouldShowBar = true
    private var menuIsVisible = false
    private var loadedHighlights = false
    private var originalHtlm = ""
    var scroll : CGPoint = CGPointZero
    //Search Highlight after Load
    private var shouldSearchHighlight : Bool = false
    private var highlightForSearch : String!
    private var shouldLoadOriginalHTML: Bool = false
    // MARK: - View life cicle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.whiteColor()
        
        if webView == nil {
            webView = UIWebView(frame: webViewFrame())
            webView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
            webView.dataDetectorTypes = [.None, .Link]
            webView.scrollView.showsVerticalScrollIndicator = false
            webView.backgroundColor = UIColor.clearColor()
            self.contentView.addSubview(webView)
        }
        webView.delegate = self
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(FolioReaderPage.handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.delegate = self
        webView.addGestureRecognizer(tapGestureRecognizer)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        webView.frame = webViewFrame()
    }
    
    func webViewFrame() -> CGRect {
        if readerConfig.shouldHideNavigationOnTap == false {
            let statusbarHeight = UIApplication.sharedApplication().statusBarFrame.size.height
            let navBarHeight = FolioReader.sharedInstance.readerCenter.navigationController?.navigationBar.frame.size.height
            let navTotal = statusbarHeight + navBarHeight!
            let newFrame = CGRect(x: self.bounds.origin.x, y: self.bounds.origin.y+navTotal, width: self.bounds.width, height: self.bounds.height-navTotal)
            return newFrame
        } else {
            return self.bounds
        }
    }
    
    func setOriginalHTML() {
        shouldLoadOriginalHTML = true
    }
    func loadHTMLString(string: String!, baseURL: NSURL!) {
        
        bURL = baseURL
        var html = (string as NSString)
        if !html.containsString("<!DOCTYPE") {
            html = "<!DOCTYPE html>  \(html) "
        }
        
        //Eliminar elemento xHTML
        html = html.stringByReplacingOccurrencesOfString("<title />", withString: "<title></title>")
        loadedHighlights = false
        webView.alpha = 0
        webView.loadHTMLString(html as String, baseURL: baseURL)
        
//        Leer como xHTML
//        let data = html.dataUsingEncoding(NSUTF8StringEncoding)
//        webView.loadData(data!, MIMEType: "application/xhtml+xml", textEncodingName: "", baseURL: baseURL)
//        [swepuWebView loadData:[decryptedString dataUsingEncoding:NSUTF8StringEncoding] MIMEType:@"application/xhtml+xml" textEncodingName:@"UTF-8" baseURL:nil]
    }
  
    
    func proccessHighlights() -> String{
    
        var highlights = Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension, andPage: pageNumber)
        var newHtml = getHTML()!
        
        highlights.sortInPlace { $0.startPos.compare($1.startPos) == .OrderedAscending }
        
        if highlights.count > 0 {
            for item in highlights {
                let style = HighlightStyle.classForStyle(item.type.integerValue)
                let tag = "<highlight id=\"\(item.highlightId)\" onclick=\"callHighlightURL('\(item.highlightId)');\" class=\"\(style)\">\(item.content)</highlight>"
                let bodyIndex = newHtml.rangeOfString("<body")?.startIndex
//                print("startPos \(item.startPos)  endPos\(item.endPos) bodyIndex \(bodyIndex)")
                let end = bodyIndex?.advancedBy(Int(item.endPos))
                var selectionHtml = newHtml.substringWithRange(Range<String.Index>(start: (bodyIndex?.advancedBy(Int(item.startPos)))!, end: end!))
//                print("bodyIndex \(bodyIndex!.advancedBy(Int(item.startPos))) end: \(end) selectionHtml \(selectionHtml)")
//                print("\n\n\nnewHtml \n\(newHtml)")
                var countChild : Int = 0
                for tag in tags{
                    //            print("op: \(d.operation.rawValue) text: \(d.text)")
                    var replaced = [String]()
                    var preHL = "<highlight onclick=\"callHighlightURL('\(item.highlightId)');\" class=\"\(style)\">"
                    var strs = selectionHtml.matchesForRegexInText("<\(tag)[^>]*>") //<---- Garantizar que sea sólo un >
                    for s in strs {
                        if !replaced.contains(s) {
                            selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(s, withString: "</highlight>\(s)\(preHL)")
                            
                            replaced.append(s)
                        }
                    }
                    preHL = "<highlight onclick=\"callHighlightURL('\(item.highlightId)');\" class=\"\(style)\">"
                    strs = selectionHtml.matchesForRegexInText("</\(tag)[^>]*>")
                    for s in strs {
                        if !replaced.contains(s) {
                            selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(s, withString: "</highlight>\(s)\(preHL)")
                            replaced.append(s)
                        }
                    }
                }
                selectionHtml = tag
                let start = bodyIndex!.advancedBy(Int(item.startPos))
                let finish = bodyIndex!.advancedBy(Int(item.endPos))
                newHtml.replaceRange(Range<String.Index>(start: start, end: finish), with: selectionHtml)
                let emptyTag = "<highlight onclick=\"callHighlightURL('\(item.highlightId)');\" class=\"\(style)\"></highlight>"
                newHtml.stringByReplacingOccurrencesOfString(emptyTag, withString: "")
            }
        }
//        print("\n\n\nnewHtml \(newHtml)")
        return newHtml
    }
    
    let tags : [String] = ["p","span","div"]
    var htmlPrev : String = ""
    
    func setPrevHtml() {
        htmlPrev = getHTML()!
    }
    
    func makeHighlights(value value:String, selection: Int, higID : String) -> FRHighlight?{
    
        var ntd : [Highlight] = Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension, andPage: pageNumber)
        var selectedText = selection
        
        var dmp : DiffMatchPatch = DiffMatchPatch()
        var htmlSub = getHTML()
//        print("\n\n\nhtmlSub \n\(htmlSub!) \n\n\nhtmlPrev \n\(htmlPrev)")
        let bodyIndex = htmlSub!.rangeOfString("<body")?.startIndex
        // computing diff at word level...
        var diffs : [Diff] = dmp.diff_mainOfOldString(htmlPrev, andNewString: htmlSub!)
        let style = HighlightStyle.classForStyle(selection)
        let initTag = "<highlight id=\"\(higID)\" onclick=\"callHighlightURL('\(higID)');\" class=\"\(style)\">"
        
        let startIndex = diffs[0].text.characters.count
        let finTagIndex = startIndex + diffs[2].text.characters.count
        
        var selectionHtml = diffs[2].text
        
        if selectionHtml.containsString("highlight") {
            return nil
        }
        
        let initHtml = diffs[0].text
        let finalHtml = diffs[4].text
        
        var relativeIDs = [String]()
        var countChild : Int = 0
        for tag in tags{
//            print("op: \(d.operation.rawValue) text: \(d.text)")
            var replaced = [String]()
            var preHL = "<highlight onclick=\"callHighlightURL('\(higID)');\" class=\"\(style)\">"
            var strs = selectionHtml.matchesForRegexInText("<\(tag)[^>]*>") //<---- Garantizar que sea sólo un >
            for s in strs {
                if !replaced.contains(s) {
                    selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(s, withString: "</highlight>\(s)\(preHL)")
//                    countChild += 1
                    replaced.append(s)
                }
                countChild += 1
                
            }
            preHL = "<highlight onclick=\"callHighlightURL('\(higID)');\" class=\"\(style)\">"
            strs = selectionHtml.matchesForRegexInText("</\(tag)[^>]*>")
            for s in strs {
                if !replaced.contains(s) {
                    selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(s, withString: "</highlight>\(s)\(preHL)")
//                    countChild += 1
                    replaced.append(s)
                }
                countChild += 1
            }
        }
        
        var emptyTag = "<highlight onclick=\"callHighlightURL('\(higID)');\" class=\"\(style)\"></highlight>"
        var strs = selectionHtml.rangesOfString(emptyTag)
        print("\n\ncantidad de tags vacíos \(strs.count)")
        selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(emptyTag, withString: "")
        countChild -= strs.count
        
        emptyTag = "<highlight onclick=\"callHighlightURL('\(higID)');\" class=\"\(style)\">\n</highlight>"
        strs = selectionHtml.rangesOfString(emptyTag)
        print("\n\ncantidad de tags vacíos \(strs.count)")
        selectionHtml = selectionHtml.stringByReplacingOccurrencesOfString(emptyTag, withString: "")
        countChild -= strs.count
        
        
        
//        print("\nselectionHtml \(selectionHtml)")
        htmlSub = initHtml + initTag + selectionHtml + "</highlight>" + finalHtml
        
        
        var html = getHTML()!
        let occ = html.matchesForRegexInText("<body.*</body>")
        if occ.count > 0 {
            html.stringByReplacingOccurrencesOfString(occ[0], withString: htmlSub!)
        }
        let highl = FRHighlight()
        highl.bookId = (kBookId as NSString).stringByDeletingPathExtension
        highl.id = higID
        highl.type = HighlightStyle.styleForClass(style)
        highl.content = selectionHtml
        highl.contentPre = ""
        highl.contentPost = ""
        highl.page = currentPageNumber
        highl.startPos = startIndex - htmlSub!.startIndex.distanceTo(bodyIndex!)
        highl.endPos = finTagIndex - htmlSub!.startIndex.distanceTo(bodyIndex!)
        highl.date = NSDate()
        highl.childCount = countChild
        
        FolioReader.sharedInstance.readerCenter.reloadWebView()
        
        var s = ""
        for h in Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension) {
            if h.highlightId == highl.id {
                s = h.notes
            }
        }
        
        Highlight.persistHighlight(highl, completion: nil, note: s)
        
        for ndo in ntd{
            let ind = ntd.indexOf(ndo)
            var iTag = "<highlight id=\"\(ndo.highlightId)\" onclick=\"callHighlightURL('\(ndo.highlightId)');\" class=\"\(HighlightStyle.classForStyle(ndo.type.integerValue))\">"
            var nStartIndex = htmlSub?.rangeOfString(iTag)
            if nStartIndex == nil {
                iTag = "<highlight id=\"\(ndo.highlightId)\" onclick=\"callHighlightURL(this);\" class=\"\(HighlightStyle.classForStyle(ndo.type.integerValue))\">"
                nStartIndex = htmlSub?.rangeOfString(iTag)
            }
            let difference = htmlSub!.startIndex.distanceTo(nStartIndex!.startIndex) - Int(ndo.startPos) - htmlSub!.startIndex.distanceTo(bodyIndex!)
            ndo.startPos = Int(ndo.startPos) + difference
            ndo.endPos = Int(ndo.endPos) + difference
        }
        return highl
    }
    
    func reloadWebView(){
        FolioReader.sharedInstance.readerCenter.reloadWebView()
    }
    
    // MARK: - FolioReaderAudioPlayerDelegate
    func didReadSentence() {
        self.readCurrentSentence();
    }
    
    // MARK: - UIWebView Delegate
    
    public func webViewDidFinishLoad(webView: UIWebView) {
        if (!book.hasAudio()) {
            FolioReader.sharedInstance.readerAudioPlayer.delegate = self;
//            self.webView.js("wrappingSentencesWithinPTags()");
            if (FolioReader.sharedInstance.readerAudioPlayer.isPlaying()) {
                readCurrentSentence()
            }
        }
        if shouldLoadOriginalHTML {
            if let s = getHTML(){
                originalHtlm = s
                shouldLoadOriginalHTML = false
            }
        }
        webView.scrollView.contentSize = CGSizeMake(pageWidth, webView.scrollView.contentSize.height)
        
        if scrollDirection == .Down && isScrolling {
            let bottomOffset = CGPointMake(0, webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
            if bottomOffset.y >= 0 {
                dispatch_async(dispatch_get_main_queue(), {
                    webView.scrollView.setContentOffset(bottomOffset, animated: false)
                })
            }
        }
        
        UIView.animateWithDuration(0.2, animations: {webView.alpha = 1}) { finished in
            webView.isColors = false
            self.webView.createMenu(options: false)
        }

        delegate.pageDidLoad!(self)
        
        if !loadedHighlights {
            let html = proccessHighlights()// <-- Cargar el archivo y después leerlo
            loadHTMLString(html as String, baseURL: bURL)
            loadedHighlights = true
        }else{
            if scroll.y != 0 {
                webView.scrollView.contentOffset = scroll
                scroll = CGPointZero
            }
        }
        
        if shouldSearchHighlight {
            handleAnchor(highlightForSearch, avoidBeginningAnchors: true, animating: true)
        }
    }
    
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        
        let url = request.URL
        
        if url?.scheme == "highlight" {
            
            shouldShowBar = false
            
            let decoded = url?.absoluteString.stringByRemovingPercentEncoding as String!
            let rect = CGRectFromString(decoded.substringFromIndex(decoded.startIndex.advancedBy(12)))
            
            webView.createMenu(options: true)
            webView.setMenuVisible(true, andRect: rect)
            menuIsVisible = true
            
            return false
        } else if url?.scheme == "play-audio" {

            let decoded = url?.absoluteString.stringByRemovingPercentEncoding as String!
            let playID = decoded.substringFromIndex(decoded.startIndex.advancedBy(13))

            FolioReader.sharedInstance.readerCenter.playAudio(playID)

            return false
        } else if url?.scheme == "file" {
            
            let anchorFromURL = url?.fragment
            
            // Handle internal url
            if (url!.path! as NSString).pathExtension != "" {
                let base = (book.opfResource.href as NSString).stringByDeletingLastPathComponent
                let path = url?.path
                let splitedPath = path!.componentsSeparatedByString(base.isEmpty ? kBookId : base)
                
                // Return to avoid crash
                if splitedPath.count <= 1 || splitedPath[1].isEmpty {
                    return true
                }
                
                let href = splitedPath[1].stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "/"))
                let hrefPage = FolioReader.sharedInstance.readerCenter.findPageByHref(href)+1
                
                if hrefPage == pageNumber {
                    // Handle internal #anchor
                    if anchorFromURL != nil {
                        handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animating: true)
                        return false
                    }
                } else {
                    FolioReader.sharedInstance.readerCenter.changePageWith(href: href, animated: true)
                }
                
                return false
            }
            
            // Handle internal #anchor
            if anchorFromURL != nil {
                handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animating: true)
                return false
            }
            
            return true
        } else if url?.scheme == "mailto" {
            print("Email")
            return true
        } else if request.URL!.absoluteString != "about:blank" && navigationType == .LinkClicked {
            
            if #available(iOS 9.0, *) {
                let safariVC = SFSafariViewController(URL: request.URL!)
                safariVC.view.tintColor = readerConfig.tintColor
                FolioReader.sharedInstance.readerCenter.presentViewController(safariVC, animated: true, completion: nil)
            } else {
                let webViewController = WebViewController(url: request.URL!)
                let nav = UINavigationController(rootViewController: webViewController)
                nav.view.tintColor = readerConfig.tintColor
                FolioReader.sharedInstance.readerCenter.presentViewController(nav, animated: true, completion: nil)
            }
            
            return false
        }
        
        return true
    }
    
    func getHTML()-> String? {
        
        if let html = self.webView.js("getHTML()"){
            return html
        }else{
            return "<html></html>"
        }
    }
    
    func getHTMLBody()-> String? {
        let htmlBody = self.webView.js("getHTMLBody()")
        return htmlBody
    }
    
    // MARK: Gesture recognizer
    
    public func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer.view is UIWebView {
            if otherGestureRecognizer is UILongPressGestureRecognizer {
                if UIMenuController.sharedMenuController().menuVisible {
                    webView.setMenuVisible(false)
                }
                return false
            }
            return true
        }
        return false
    }
    
    func handleTapGesture(recognizer: UITapGestureRecognizer) {
//        webView.setMenuVisible(false)
        
        if FolioReader.sharedInstance.readerCenter.navigationController!.navigationBarHidden {
            let menuIsVisibleRef = menuIsVisible
            
            let selected = webView.js("getSelectedText()")

            if selected == nil || selected!.characters.count == 0 {
                let seconds = 0.4
                let delay = seconds * Double(NSEC_PER_SEC)  // nanoseconds per seconds
                let dispatchTime = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))

                dispatch_after(dispatchTime, dispatch_get_main_queue(), {
                    
                    if self.shouldShowBar && !menuIsVisibleRef {
                        FolioReader.sharedInstance.readerCenter.toggleBars()
                    }
                    self.shouldShowBar = true
                })
            }
        } else if readerConfig.shouldHideNavigationOnTap == true {
            FolioReader.sharedInstance.readerCenter.hideBars()
        }
        
        // Reset menu
        menuIsVisible = false
    }
    
    // MARK: - Scroll positioning
    
    func scrollPageToOffset(offset: String, animating: Bool) {
        let jsCommand = "window.scrollTo(0,\(offset));"
        if animating {
            UIView.animateWithDuration(0.35, animations: {
                self.webView.js(jsCommand)
            })
        } else {
            webView.js(jsCommand)
        }
    }
    func handleAnchor(anchor: String,  avoidBeginningAnchors: Bool, animating: Bool) {
        if !anchor.isEmpty {
//            print("currentPageNumber \(currentPageNumber) anchor \(anchor)")
            if let offset = getAnchorOffset(anchor) {
//                print("offset: \(offset)")
                let isBeginning = CGFloat((offset as NSString).floatValue) > self.frame.height/2
                
                if !avoidBeginningAnchors {
                    scrollPageToOffset(offset, animating: animating)
                } else if avoidBeginningAnchors && isBeginning {
                    scrollPageToOffset(offset, animating: animating)
                }
                shouldSearchHighlight = false
            }else{
                shouldSearchHighlight = true
                highlightForSearch = anchor
            }
        }
    }
    
    func getAnchorOffset(anchor: String) -> String? {
        let jsAnchorHandler = "(function() {var target = '\(anchor)';var elem = document.getElementById(target); if (!elem) elem=document.getElementsByName(target)[0];return elem.offsetTop;})();"
        return webView.js(jsAnchorHandler)
    }
    
    override public func canPerformAction(action: Selector, withSender sender: AnyObject?) -> Bool {

        if UIMenuController.sharedMenuController().menuItems?.count == 0 {
            webView.isColors = false
            webView.createMenu(options: false)
        }
        
        return super.canPerformAction(action, withSender: sender)
    }

    func playAudio(){
		if (book.hasAudio()) {
            webView.js("playAudio()")
		} else {
			readCurrentSentence()
		}
    }
    
    func speakSentence(){
        let sentence = self.webView.js("getSentenceWithIndex('\(book.playbackActiveClass())')")
        if sentence != nil {
            let chapter = FolioReader.sharedInstance.readerCenter.getCurrentChapter()
            let href = chapter != nil ? chapter!.href : "";
            FolioReader.sharedInstance.readerAudioPlayer.playText(href, text: sentence!)
        } else {
            if(FolioReader.sharedInstance.readerCenter.isLastPage()){
                FolioReader.sharedInstance.readerAudioPlayer.stop()
            } else{
                FolioReader.sharedInstance.readerCenter.changePageToNext()
            }
        }
    }
    
	func readCurrentSentence() {
		if (FolioReader.sharedInstance.readerAudioPlayer.synthesizer == nil ) {
            speakSentence()
		} else {
            if(FolioReader.sharedInstance.readerAudioPlayer.synthesizer.paused){
                FolioReader.sharedInstance.readerAudioPlayer.synthesizer.continueSpeaking()
            }else{
                if(FolioReader.sharedInstance.readerAudioPlayer.synthesizer.speaking){
                    FolioReader.sharedInstance.readerAudioPlayer.stopSynthesizer({ () -> Void in
                        self.webView.js("resetCurrentSentenceIndex()")
                        self.speakSentence()
                    })
                }else{
                    speakSentence()
                }
            }
		}
	}

    func audioMarkID(ID: String){
        self.webView.js("audioMarkID('\(book.playbackActiveClass())','\(ID)')");
    }
    
    func forceReload(newBackground: Bool = false){
        scroll = webView.scrollView.contentOffset
//        var html = originalHtlm
//        if newBackground {
//            if let s = getHTML() {
//                html = s
//            }
//        }
        
        let html = FolioReader.sharedInstance.readerCenter.createHtmlForPage(currentPageNumber - 1)!
        loadHTMLString(html as String, baseURL: bURL)
//        originalHtlm = html
//        print("this page is \(currentPageNumber) \(pageNumber)")
        
        
    }
}

// MARK: - WebView Highlight and share implementation

private var cAssociationKey: UInt8 = 0
private var sAssociationKey: UInt8 = 0

extension UIWebView {
    
    var isColors: Bool {
        get { return objc_getAssociatedObject(self, &cAssociationKey) as? Bool ?? false }
        set(newValue) {
            objc_setAssociatedObject(self, &cAssociationKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var isShare: Bool {
        get { return objc_getAssociatedObject(self, &sAssociationKey) as? Bool ?? false }
        set(newValue) {
            objc_setAssociatedObject(self, &sAssociationKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    public override func canPerformAction(action: Selector, withSender sender: AnyObject?) -> Bool {

        // menu on existing highlight
        if isShare {
            if action == #selector(UIWebView.colors(_:)) || (action == #selector(UIWebView.share(_:)) && readerConfig.allowSharing == true) || action == #selector(UIWebView.remove(_:)) || action == #selector(UIWebView.addNote(_:)){
                return true
            }
            return false

        // menu for selecting highlight color
        } else if isColors {
            if action == #selector(UIWebView.setYellow(_:)) || action == #selector(UIWebView.setGreen(_:)) || action == #selector(UIWebView.setBlue(_:)) || action == #selector(UIWebView.setPink(_:)) || action == #selector(UIWebView.setUnderline(_:)) {
                return true
            }
            return false

        // default menu
        } else {
            var isOneWord = false
            if let result = js("getSelectedText()") where result.componentsSeparatedByString(" ").count == 1 {
                isOneWord = true
            }
            
            if action == #selector(UIWebView.highlight(_:))
//            || (action == #selector(UIWebView.define(_:)) && isOneWord)
            || (action == #selector(UIWebView.play(_:)) && (book.hasAudio() || readerConfig.enableTTS))
            || (action == #selector(UIWebView.share(_:)) && readerConfig.allowSharing == true)
            || (action == #selector(NSObject.copy(_:)) && readerConfig.allowSharing == true) {
                return true
            }
            return false
        }
    }
    
    public override func canBecomeFirstResponder() -> Bool {
        return true
    }
    
    func share(sender: UIMenuController) {
        
        if isShare {
            if let textToShare = js("getHighlightContent()") {
                FolioReader.sharedInstance.readerCenter.shareHighlight(textToShare, rect: sender.menuFrame)
            }
        } else {
            if let textToShare = js("getSelectedText()") {
                FolioReader.sharedInstance.readerCenter.shareHighlight(textToShare, rect: sender.menuFrame)
            }
        }
        
        setMenuVisible(false)
    }
    
    func colors(sender: UIMenuController?) {
        isColors = true
        createMenu(options: false)
        setMenuVisible(true)
    }
    
    func remove(sender: UIMenuController?) {
        let html = js("getHTML();")!
        var ntd : [Highlight] = Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension, andPage: currentPageNumber)
        ntd.sortInPlace { $0.startPos.compare($1.startPos) == .OrderedAscending }
        if let removedId = js("removeThisHighlight()") {
            
            if let h = Highlight.getHighlightById(removedId){
                let index = ntd.indexOf(h)
                
                let iTag = "<highlight id=\"\(h.highlightId)\" onclick=\"callHighlightURL('\(h.highlightId)');\" class=\"\(HighlightStyle.classForStyle(h.type.integerValue))\"></highlight>"
                let childTag = "<highlight onclick=\"callHighlightURL('\(h.highlightId)');\" class=\"\(HighlightStyle.classForStyle(h.type.integerValue))\"></highlight>"
                let difference = Int(h.childCount) * childTag.characters.count + iTag.characters.count
                
                Highlight.removeById(removedId)
                moveHighlights(array: ntd, index: index, difference: difference)
                setMenuVisible(false)
//                FolioReader.sharedInstance.readerCenter.currentPage.reloadWebView()]'
//                FolioReader.sharedInstance.readerCenter.reloadData()
                FolioReader.sharedInstance.readerCenter.currentPage.forceReload()
            }
        }
    }
    
    
    func removeHighlight(removedId : String, page : Int){
        var ntd : [Highlight] = Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension, andPage: page)
        ntd.sortInPlace { $0.startPos.compare($1.startPos) == .OrderedAscending }
        if let h = Highlight.getHighlightById(removedId){
            let index = ntd.indexOf(h)
            
            let iTag = "<highlight id=\"\(h.highlightId)\" onclick=\"callHighlightURL('\(h.highlightId)');\" class=\"\(HighlightStyle.classForStyle(h.type.integerValue))\"></highlight>"
            let childTag = "<highlight onclick=\"callHighlightURL('\(h.highlightId)');\" class=\"\(HighlightStyle.classForStyle(h.type.integerValue))\"></highlight>"
            let difference = Int(h.childCount) * childTag.characters.count + iTag.characters.count
            
            Highlight.removeById(removedId)
            moveHighlights(array: ntd, index: index, difference: difference)
            if page == currentPageNumber {
                FolioReader.sharedInstance.readerCenter.currentPage.forceReload()
            }
        }
    }
    
    func moveHighlights(array ntd : [Highlight], index : Int?, difference : Int){
        let html = js("getHTML();")!
        if ntd.count >= (index! + 2) {
            for ndo in (index! + 1)...ntd.count-1{
                ntd[ndo].startPos = Int(ntd[ndo].startPos) - difference
                ntd[ndo].endPos = Int(ntd[ndo].endPos) - difference
                Highlight.persistHighlight()
            }
        }
        
    }
    
    func highlight(sender: UIMenuController?) {
        js("uiWebview_RemoveAllHighlights();")// Highlights de la búsqueda
        FolioReader.sharedInstance.readerCenter.currentPage.setPrevHtml()
        
        let highlightAndReturn = js("highlightString('\(HighlightStyle.classForStyle(FolioReader.sharedInstance.currentHighlightStyle))')")
        let jsonData = highlightAndReturn?.dataUsingEncoding(NSUTF8StringEncoding)
        
        if jsonData == nil {
            userInteractionEnabled = false
            userInteractionEnabled = true
            return
        }
        
        do {
            let json = try NSJSONSerialization.JSONObjectWithData(jsonData!, options: []) as! NSArray
            let dic = json.firstObject as! [String: String]
            let rect = CGRectFromString(dic["rect"]!)
            
            // Force remove text selection
            userInteractionEnabled = false
            userInteractionEnabled = true

            createMenu(options: true)
            setMenuVisible(true, andRect: rect)
            
            // Persist
            let html = js("getHTML()")!
            let id = dic["id"]!
            
            if let highlight = FolioReader.sharedInstance.readerCenter.currentPage.makeHighlights(value: html, selection: FolioReader.sharedInstance.currentHighlightStyle, higID: id){
            
//            if let highlight = FRHighlight.matchHighlight(html, andId: dic["id"]!) {
            
                //Search note
                var s = ""
                for h in Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension) {
                    if h.highlightId == highlight.id {
                        s = h.notes
                    }
                }
                
                Highlight.persistHighlight(highlight, completion: nil, note: s)
                FolioReader.sharedInstance.readerCenter.currentPage.forceReload()
            }else{
                setMenuVisible(false)
                js("removeThisHighlight()")
                // Force remove text selection
                userInteractionEnabled = false
                userInteractionEnabled = true
                FolioReader.sharedInstance.readerCenter.pressentAlertForHighlight()
                FolioReader.sharedInstance.readerCenter.currentPage.forceReload()
            }
        } catch {
            print("Could not receive JSON")
        }
    }

    func define(sender: UIMenuController?) {
        let selectedText = js("getSelectedText()")
        
        setMenuVisible(false)
        userInteractionEnabled = false
        userInteractionEnabled = true
        
        let vc = UIReferenceLibraryViewController(term: selectedText! )
        vc.view.tintColor = readerConfig.tintColor
        FolioReader.sharedInstance.readerContainer.showViewController(vc, sender: nil)
    }

    func play(sender: UIMenuController?) {
        FolioReader.sharedInstance.readerCenter.currentPage.playAudio()

        // Force remove text selection
        // @NOTE: this doesn't seem to always work
        userInteractionEnabled = false
        userInteractionEnabled = true
    }


    // MARK: - Set highlight styles
    
    func setYellow(sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .Yellow)
    }
    
    func setGreen(sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .Green)
    }
    
    func setBlue(sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .Blue)
    }
    
    func setPink(sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .Pink)
    }
    
    func setUnderline(sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .Underline)
    }

    func changeHighlightStyle(sender: UIMenuController?, style: HighlightStyle) {
        FolioReader.sharedInstance.currentHighlightStyle = style.rawValue

        if let updateId = js("setHighlightStyle('\(HighlightStyle.classForStyle(style.rawValue))')") {
            
            let h = Highlight.getHighlightById(updateId)
            
            let newStyle = HighlightStyle.classForStyle(style.rawValue)
            let oldStyle = HighlightStyle.classForStyle(Int(h!.type))
            
            var content = h?.content
            
            content = content?.stringByReplacingOccurrencesOfString(oldStyle, withString: newStyle)
            h?.content = content!
            
            let difference = (newStyle.characters.count - oldStyle.characters.count) * (Int(h!.childCount) + 1)
            var ntd : [Highlight] = Highlight.allByBookId((kBookId as NSString).stringByDeletingPathExtension, andPage: currentPageNumber)
            ntd.sortInPlace { $0.startPos.compare($1.startPos) == .OrderedAscending }
            let index = ntd.indexOf(h!)
            Highlight.updateById(updateId, type: style)
            
            moveHighlights(array: ntd, index: index, difference: -difference)
            
            FolioReader.sharedInstance.readerCenter.currentPage.forceReload()
        }
        colors(sender)
        

    }
    
    func addNote(sender: UIMenuController?){
        
        if let id = js("getThisHighlightID()"){
            FolioReader.sharedInstance.readerCenter.addNoteToHighlight(id)
        }
    }
    
    // MARK: - Create and show menu
    
    func createMenu(options options: Bool) {
        isShare = options
        
        let colors = UIImage(readerImageNamed: "colors-marker")
        let share = UIImage(readerImageNamed: "share-marker")
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")
        
        //Comments
        let note = UIImage(readerImageNamed: "icon-highlight")
        
        let highlightItem = UIMenuItem(title: readerConfig.localizedHighlightMenu, action: #selector(UIWebView.highlight(_:)))
        let playAudioItem = UIMenuItem(title: readerConfig.localizedPlayMenu, action: #selector(UIWebView.play(_:)))
        let defineItem = UIMenuItem(title: readerConfig.localizedDefineMenu, action: #selector(UIWebView.define(_:)))
        let colorsItem = UIMenuItem(title: "C", image: colors!, action: #selector(UIWebView.colors(_:)))
        let shareItem = UIMenuItem(title: "S", image: share!, action: #selector(UIWebView.share(_:)))
        let removeItem = UIMenuItem(title: "R", image: remove!, action: #selector(UIWebView.remove(_:)))
        let yellowItem = UIMenuItem(title: "Y", image: yellow!, action: #selector(UIWebView.setYellow(_:)))
        let greenItem = UIMenuItem(title: "G", image: green!, action: #selector(UIWebView.setGreen(_:)))
        let blueItem = UIMenuItem(title: "B", image: blue!, action: #selector(UIWebView.setBlue(_:)))
        let pinkItem = UIMenuItem(title: "P", image: pink!, action: #selector(UIWebView.setPink(_:)))
        let underlineItem = UIMenuItem(title: "U", image: underline!, action: #selector(UIWebView.setUnderline(_:)))
        let noteItem = UIMenuItem(title: "N", image: note!, action: #selector(UIWebView.addNote(_:)))
        
        let menuItems = [playAudioItem, highlightItem, defineItem, colorsItem, removeItem, yellowItem, greenItem, blueItem, pinkItem, underlineItem, shareItem, noteItem]

        UIMenuController.sharedMenuController().menuItems = menuItems
    }
    
    func setMenuVisible(menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRectZero) {
        if !menuVisible && isShare || !menuVisible && isColors {
            isColors = false
            isShare = false
        }
        
        if menuVisible  {
            if !CGRectEqualToRect(rect, CGRectZero) {
                UIMenuController.sharedMenuController().setTargetRect(rect, inView: self)
            }
        }
        
        UIMenuController.sharedMenuController().setMenuVisible(menuVisible, animated: animated)
    }
    
    func js(script: String) -> String? {
        let callback = self.stringByEvaluatingJavaScriptFromString(script)
        if callback!.isEmpty { return nil }
        return callback
    }
}

extension UIMenuItem {
    convenience init(title: String, image: UIImage, action: Selector) {
        self.init(title: title, action: action)
        self.cxa_initWithTitle(title, action: action, image: image, hidesShadow: true)
    }
}
