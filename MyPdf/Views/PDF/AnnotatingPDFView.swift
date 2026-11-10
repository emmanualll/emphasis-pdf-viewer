import AppKit
import PDFKit
import UniformTypeIdentifiers

// PDFView with our own mouse handling for highlight/erase/text boxes
final class AnnotatingPDFView: PDFView, NSDraggingSource {
    var tool: Tool = .browse {
        didSet {
            if tool != .textBox {
                deselectAllTextBoxes()
            }
            updateCursor()
        }
    }
    var highlightMode: HighlightMode = .free
    var highlightColor: NSColor = HighlightColor.yellow.nsColor
    var highlightStrength: Double = 0.4
    var useFixedHeight: Bool = false
    var fixedHeight: CGFloat = 20.0

    static let eraserCursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: "Eraser")?
                .withSymbolConfiguration(config) {
                let drawRect = NSRect(x: 2, y: 2, width: 20, height: 20)
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 2.0, color: NSColor.white.cgColor)
                let whiteConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
                symbol.withSymbolConfiguration(whiteConfig)?.draw(in: drawRect)
                ctx.restoreGState()

                let darkConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.1, alpha: 1.0)])
                symbol.withSymbolConfiguration(darkConfig)?.draw(in: drawRect)
                return true
            } else {
                let path = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 16, height: 16), xRadius: 3, yRadius: 3)
                NSColor.black.setFill()
                path.fill()
                return true
            }
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 7, y: 19))
    }()

    var currentToolCursor: NSCursor {
        switch tool {
        case .erase: return Self.eraserCursor
        case .highlight: return .crosshair
        case .textBox: return .iBeam
        case .browse: return .arrow
        }
    }

    func updateCursor() {
        window?.invalidateCursorRects(for: self)
        if let window, window.isKeyWindow {
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let mouseInView = convert(mouseInWindow, from: nil)
            if bounds.contains(mouseInView) {
                currentToolCursor.set()
            }
        }
    }

    private var cursorTrackingArea: NSTrackingArea?

    var onDocumentChanged: (() -> Void)?
    var onCurrentPageChanged: ((Int) -> Void)?
    var onToolChanged: ((Tool) -> Void)?
    var lastJumpID: UUID?
    private var activeTextBoxes: [CanvaTextBoxView] = []
    private var selectedTextBox: CanvaTextBoxView?
    private var observersAdded = false

    func resetToolToBrowse() {
        if tool != .browse {
            tool = .browse
            onToolChanged?(.browse)
        }
    }

    func finishEditingActiveTextBox() {
        guard let box = selectedTextBox else {
            resetToolToBrowse()
            return
        }
        let text = box.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            removeActiveTextBox(box)
        } else {
            if window?.firstResponder == box.textView {
                window?.makeFirstResponder(self)
            }
            box.isSelected = false
            selectedTextBox = nil
        }
        resetToolToBrowse()
    }

    func removeActiveTextBox(_ box: CanvaTextBoxView) {
        if selectedTextBox === box {
            selectedTextBox = nil
        }
        if let idx = activeTextBoxes.firstIndex(where: { $0 === box }) {
            activeTextBoxes.remove(at: idx)
        }
        box.removeFromSuperview()
        onDocumentChanged?()
    }

    var appUndoManager: UndoManager? {
        return self.undoManager ?? self.window?.undoManager ?? NSApplication.shared.keyWindow?.undoManager ?? NSApplication.shared.windows.first?.undoManager
    }

    override var acceptsFirstResponder: Bool { true }

    @objc func undo(_ sender: Any?) {
        appUndoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        appUndoManager?.redo()
    }

    override var document: PDFDocument? {
        didSet {
            if oldValue !== document {
                appUndoManager?.removeAllActions()
                for box in activeTextBoxes {
                    box.removeFromSuperview()
                }
                activeTextBoxes.removeAll()
                selectedTextBox = nil
                updateCurrentPage()
            }
        }
    }

    private var holdTimer: Timer?
    private var holdStartWindowPoint = CGPoint.zero
    private var holdStartTime = Date()
    private var holdEvent: NSEvent?
    private var holdRing: HoldRingView?
    private var holdPage: PDFPage?
    private var holdReady = false              // 2 seconds are up, drag should start
    private var insideSuperMouseDown = false
    private let holdDuration: TimeInterval = 2.0
    private var dragStart: CGPoint?
    private var startPage: PDFPage?
    private let preview = NSView()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupObserversIfNeeded()
        appUndoManager?.levelsOfUndo = 50
        updateCursor()
    }

    private func setupObserversIfNeeded() {
        guard !observersAdded, window != nil else { return }
        observersAdded = true

        NotificationCenter.default.addObserver(self, selector: #selector(commitAllTextBoxesToPDF),
                                               name: .commitCanvaTextBoxes, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(viewDidScrollOrZoom),
                                               name: .PDFViewScaleChanged, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(viewDidScrollOrZoom),
                                               name: .PDFViewVisiblePagesChanged, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(viewDidScrollOrZoom),
                                               name: .PDFViewPageChanged, object: self)

        if let scrollView = subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewDidScrollOrZoom),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }
    }

    @objc private func viewDidScrollOrZoom() {
        updateTextBoxFrames()
        updateCurrentPage()
    }

    private func updateCurrentPage() {
        guard let doc = document, let page = currentPage else { return }
        let idx = doc.index(for: page)
        if idx != NSNotFound {
            onCurrentPageChanged?(idx)
        }
    }

    override func layout() {
        super.layout()
        setupObserversIfNeeded()
        updateTextBoxFrames()
    }

    func updateTextBoxFrames() {
        for box in activeTextBoxes {
            guard let doc = document, doc.index(for: box.page) != NSNotFound else {
                box.isHidden = true
                continue
            }
            let viewRect = convert(box.pageRect, from: box.page)
            box.frame = CGRect(
                x: round(viewRect.origin.x),
                y: round(viewRect.origin.y),
                width: round(viewRect.size.width),
                height: round(viewRect.size.height)
            )
            box.updateScale(scaleFactor)
            box.isHidden = !bounds.intersects(box.frame)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = cursorTrackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.cursorUpdate, .activeInActiveApp, .inVisibleRect],
                                owner: self,
                                userInfo: nil)
        addTrackingArea(ta)
        cursorTrackingArea = ta
    }

    override func cursorUpdate(with event: NSEvent) {
        if tool != .browse {
            currentToolCursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if tool != .browse {
            discardCursorRects()
            addCursorRect(bounds, cursor: currentToolCursor)
        }
    }

    override func setCursorFor(_ area: PDFAreaOfInterest) {
        if tool != .browse {
            currentToolCursor.set()
        } else {
            super.setCursorFor(area)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if tool != .browse {
            currentToolCursor.set()
        }
        super.mouseMoved(with: event)
    }

    // In non-browse modes we grab the mouse ourselves,
    // otherwise PDFKit's inner views swallow the clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if tool == .browse || tool == .textBox {
            for box in activeTextBoxes.reversed() {
                if box.frame.insetBy(dx: -8, dy: -8).contains(p) {
                    return box.hitTest(point)
                }
            }
        }
        return tool == .browse ? super.hitTest(point) : self
    }

    // Since we grab events, pass scrolling to PDFKit's inner scroll view
    override func scrollWheel(with event: NSEvent) {
        if let scroller = subviews.first(where: { $0 is NSScrollView }) {
            scroller.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if tool != .browse {
            currentToolCursor.set()
        }
        let p = convert(event.locationInWindow, from: nil)

        // Erase tool: active text boxes take precedence, then saved annotations
        if tool == .erase {
            if let box = activeTextBoxes.first(where: { $0.frame.contains(p) }) {
                eraseActiveTextBox(box)
                return
            }
            if let page = page(for: p, nearest: true) {
                let pagePoint = convert(p, to: page)
                if let annotation = page.annotation(at: pagePoint) {
                    guard annotation.userName != searchMarkTag else { return }
                    erasePageAnnotation(annotation, from: page)
                }
            }
            return
        }

        // If a text box was active and user clicked outside it: finish it and return to normal browsing
        if let currentBox = selectedTextBox, !currentBox.frame.insetBy(dx: -8, dy: -8).contains(p) {
            finishEditingActiveTextBox()
            return
        }

        guard tool != .browse else {
            deselectAllTextBoxes()
            startHold(event)
            insideSuperMouseDown = true
            super.mouseDown(with: event)   // PDFKit tracks the click in here until release
            insideSuperMouseDown = false
            if holdReady { startQueuedDrag() }
            return
        }

        guard let page = page(for: p, nearest: true) else { return }

        // If in textBox mode and clicked on an existing box: select it
        if tool == .textBox {
            if let clickedBox = activeTextBoxes.first(where: { $0.frame.insetBy(dx: -8, dy: -8).contains(p) }) {
                selectTextBox(clickedBox)
                return
            }
            deselectAllTextBoxes()
        }

        // highlight / text box: remember where the drag started
        dragStart = p
        startPage = page
        preview.wantsLayer = true

        if tool == .textBox {
            preview.layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.96, alpha: 0.7).cgColor
            preview.layer?.borderColor = NSColor.controlAccentColor.cgColor
            preview.layer?.borderWidth = 1.0
            preview.layer?.cornerRadius = 4
            preview.layer?.masksToBounds = true
            preview.frame = CGRect(origin: p, size: .zero)
        } else {
            let effectiveColor = highlightColor.withAlphaComponent(CGFloat(highlightStrength))
            preview.layer?.backgroundColor = effectiveColor.cgColor
            preview.layer?.borderColor = nil
            preview.layer?.borderWidth = 0
            preview.layer?.cornerRadius = (tool == .highlight && highlightMode == .free) ? 5 : 0
            preview.layer?.masksToBounds = true

            if tool == .highlight && highlightMode == .free && useFixedHeight {
                let viewH = fixedHeight * scaleFactor
                preview.frame = CGRect(x: p.x, y: p.y - viewH / 2, width: 0, height: viewH)
            } else {
                preview.frame = CGRect(origin: p, size: .zero)
            }
        }
        addSubview(preview)
    }

    override func mouseDragged(with event: NSEvent) {
        guard tool != .browse, let start = dragStart else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if tool == .highlight && highlightMode == .free && useFixedHeight {
            let viewH = fixedHeight * scaleFactor
            let minX = min(start.x, p.x)
            let width = abs(start.x - p.x)
            preview.frame = CGRect(x: minX, y: start.y - viewH / 2, width: width, height: viewH)
        } else {
            preview.frame = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                                   width: abs(start.x - p.x), height: abs(start.y - p.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard tool != .browse, let start = dragStart, let page = startPage else { super.mouseUp(with: event); return }
        defer { preview.removeFromSuperview(); dragStart = nil; startPage = nil }

        if tool == .textBox {
            let upPoint = convert(event.locationInWindow, from: nil)
            var boxFrame = CGRect(x: min(start.x, upPoint.x), y: min(start.y, upPoint.y),
                                  width: abs(start.x - upPoint.x), height: abs(start.y - upPoint.y))
            if boxFrame.width < 25 || boxFrame.height < 20 {
                // plain click: default size, click is the top-left corner
                let w: CGFloat = 160
                let h: CGFloat = 50
                boxFrame = CGRect(x: start.x, y: isFlipped ? start.y : start.y - h, width: w, height: h)
            }
            createNewTextBox(frame: boxFrame, on: page)
            return
        }

        guard let page = startPage else { return }
        let end = convert(event.locationInWindow, from: nil)
        let effectiveColor = highlightColor.withAlphaComponent(CGFloat(highlightStrength))

        if highlightMode == .text {
            // Snap to the text under the drag, one highlight per line
            let a = convert(start, to: page)
            let b = convert(end, to: page)
            guard let selection = page.selection(from: a, to: b) else { return }
            var added: [(PDFAnnotation, PDFPage)] = []
            for line in selection.selectionsByLine() {
                for linePage in line.pages {
                    let annot = PDFAnnotation(bounds: line.bounds(for: linePage), forType: .highlight, withProperties: nil)
                    annot.color = effectiveColor
                    annot.quadrilateralPoints = [
                        NSValue(point: CGPoint(x: 0, y: line.bounds(for: linePage).height)),
                        NSValue(point: CGPoint(x: line.bounds(for: linePage).width, y: line.bounds(for: linePage).height)),
                        NSValue(point: CGPoint(x: 0, y: 0)),
                        NSValue(point: CGPoint(x: line.bounds(for: linePage).width, y: 0))
                    ]
                    linePage.addAnnotation(annot)
                    added.append((annot, linePage))
                }
            }
            if !added.isEmpty {
                onDocumentChanged?()
                if let um = appUndoManager {
                    um.registerUndo(withTarget: self) { [weak self] _ in
                        self?.undoMultipleHighlights(added)
                    }
                    um.setActionName("Highlight")
                }
            }
        } else {
            let pageStart = convert(start, to: page)
            let pageEnd = convert(end, to: page)
            var rect: CGRect
            if useFixedHeight {
                let minX = min(pageStart.x, pageEnd.x)
                let width = abs(pageStart.x - pageEnd.x)
                let y = pageStart.y - fixedHeight / 2
                rect = CGRect(x: minX, y: y, width: width, height: fixedHeight)
            } else {
                rect = CGRect(x: min(pageStart.x, pageEnd.x), y: min(pageStart.y, pageEnd.y),
                              width: abs(pageStart.x - pageEnd.x), height: abs(pageStart.y - pageEnd.y))
            }
            rect = rect.intersection(page.bounds(for: .cropBox))
            guard rect.width > 3, rect.height > 3 else { return }
            addFreeHighlight(rect: rect, on: page, color: effectiveColor)
        }
    }

    private func addFreeHighlight(rect: CGRect, on page: PDFPage, color: NSColor) {
        let annotation = RoundedHighlightAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
        annotation.color = color
        annotation.userName = "FreeHighlight"
        annotation.quadrilateralPoints = [
            NSValue(point: CGPoint(x: 0, y: rect.height)),
            NSValue(point: CGPoint(x: rect.width, y: rect.height)),
            NSValue(point: CGPoint(x: 0, y: 0)),
            NSValue(point: CGPoint(x: rect.width, y: 0))
        ]
        page.addAnnotation(annotation)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak page, weak annotation] _ in
                guard let self, let page, let annotation else { return }
                self.undoHighlight(annotation, on: page)
            }
            um.setActionName("Highlight")
        }
    }

    private func undoHighlight(_ annotation: PDFAnnotation, on page: PDFPage) {
        page.removeAnnotation(annotation)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak page, weak annotation] _ in
                guard let self, let page, let annotation else { return }
                self.redoHighlight(annotation, on: page)
            }
            um.setActionName("Highlight")
        }
    }

    private func redoHighlight(_ annotation: PDFAnnotation, on page: PDFPage) {
        page.addAnnotation(annotation)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak page, weak annotation] _ in
                guard let self, let page, let annotation else { return }
                self.undoHighlight(annotation, on: page)
            }
            um.setActionName("Highlight")
        }
    }

    private func undoMultipleHighlights(_ list: [(PDFAnnotation, PDFPage)]) {
        for (annot, page) in list {
            page.removeAnnotation(annot)
        }
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self] _ in
                self?.redoMultipleHighlights(list)
            }
            um.setActionName("Highlight")
        }
    }

    private func redoMultipleHighlights(_ list: [(PDFAnnotation, PDFPage)]) {
        for (annot, page) in list {
            page.addAnnotation(annot)
        }
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self] _ in
                self?.undoMultipleHighlights(list)
            }
            um.setActionName("Highlight")
        }
    }

    private func createNewTextBox(frame: CGRect, on page: PDFPage) {
        let alignedFrame = CGRect(
            x: round(frame.origin.x),
            y: round(frame.origin.y),
            width: round(frame.size.width),
            height: round(frame.size.height)
        )
        let pageRect = convert(alignedFrame, to: page)
        let box = CanvaTextBoxView(page: page, pageRect: pageRect, baseFontSize: 10.0)
        box.frame = alignedFrame
        box.updateScale(scaleFactor)

        box.onSelected = { [weak self, weak box] in
            guard let self, let box else { return }
            self.selectTextBox(box)
        }
        box.onDelete = { [weak self, weak box] in
            guard let self, let box else { return }
            self.eraseActiveTextBox(box)
        }
        box.onGeometryChanged = { [weak self, weak box] in
            guard let self, let box else { return }
            box.pageRect = self.convert(box.frame, to: box.page)
            self.onDocumentChanged?()
        }
        box.onContentChanged = { [weak self] in
            self?.onDocumentChanged?()
        }
        box.onFinishEditing = { [weak self] in
            self?.finishEditingActiveTextBox()
        }

        addSubview(box)
        activeTextBoxes.append(box)
        selectTextBox(box)
        window?.makeFirstResponder(box.textView)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak box] _ in
                guard let self, let box else { return }
                self.undoAddTextBox(box)
            }
            um.setActionName("Text Box")
        }
    }

    private func undoAddTextBox(_ box: CanvaTextBoxView) {
        if selectedTextBox === box {
            deselectAllTextBoxes()
        }
        if let idx = activeTextBoxes.firstIndex(where: { $0 === box }) {
            activeTextBoxes.remove(at: idx)
        }
        box.removeFromSuperview()
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak box] _ in
                guard let self, let box else { return }
                self.redoAddTextBox(box)
            }
            um.setActionName("Text Box")
        }
    }

    private func redoAddTextBox(_ box: CanvaTextBoxView) {
        addSubview(box)
        activeTextBoxes.append(box)
        updateTextBoxFrames()
        selectTextBox(box)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak box] _ in
                guard let self, let box else { return }
                self.undoAddTextBox(box)
            }
            um.setActionName("Text Box")
        }
    }

    func selectTextBox(_ box: CanvaTextBoxView) {
        if selectedTextBox === box { return }
        selectedTextBox?.isSelected = false
        selectedTextBox = box
        box.isSelected = true
    }

    func deselectAllTextBoxes() {
        if let selected = selectedTextBox {
            let text = selected.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                removeActiveTextBox(selected)
            } else {
                if window?.firstResponder == selected.textView {
                    window?.makeFirstResponder(self)
                }
                selected.isSelected = false
                selectedTextBox = nil
            }
        }
    }

    func removeTextBox(_ box: CanvaTextBoxView) {
        removeActiveTextBox(box)
    }

    func eraseActiveTextBox(_ box: CanvaTextBoxView) {
        if selectedTextBox === box {
            deselectAllTextBoxes()
        }
        if let idx = activeTextBoxes.firstIndex(where: { $0 === box }) {
            activeTextBoxes.remove(at: idx)
        }
        box.removeFromSuperview()
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak box] _ in
                guard let self, let box else { return }
                self.undoEraseActiveTextBox(box)
            }
            um.setActionName("Erase")
        }
    }

    private func undoEraseActiveTextBox(_ box: CanvaTextBoxView) {
        addSubview(box)
        activeTextBoxes.append(box)
        updateTextBoxFrames()
        selectTextBox(box)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak box] _ in
                guard let self, let box else { return }
                self.eraseActiveTextBox(box)
            }
            um.setActionName("Erase")
        }
    }

    func erasePageAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak page, weak annotation] _ in
                guard let self, let page, let annotation else { return }
                self.undoErasePageAnnotation(annotation, on: page)
            }
            um.setActionName("Erase")
        }
    }

    private func undoErasePageAnnotation(_ annotation: PDFAnnotation, on page: PDFPage) {
        page.addAnnotation(annotation)
        onDocumentChanged?()

        if let um = appUndoManager {
            um.registerUndo(withTarget: self) { [weak self, weak page, weak annotation] _ in
                guard let self, let page, let annotation else { return }
                self.erasePageAnnotation(annotation, from: page)
            }
            um.setActionName("Erase")
        }
    }

    // Press and hold still for 2 seconds (Browse tool) to drag the page out.
    // We poll the real mouse state instead of listening for events, because
    // PDFKit swallows the mouse-up while it is tracking a click.
    private func startHold(_ event: NSEvent) {
        cancelHold()
        guard document != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let page = page(for: p, nearest: false) else { return }

        holdPage = page
        holdEvent = event
        holdStartWindowPoint = event.locationInWindow
        holdStartTime = Date()
        holdReady = false

        let size = HoldRingView.size
        let ring = HoldRingView(frame: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        ring.isHidden = true   // shown after a short delay so quick clicks don't flicker
        addSubview(ring)
        ring.start(duration: holdDuration)
        holdRing = ring

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.holdTick() }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func holdTick() {
        guard holdTimer != nil, let window else { cancelHold(); return }

        // let go of the button: not a hold
        if NSEvent.pressedMouseButtons & 1 == 0 { cancelHold(); return }

        // moved too far: not a hold
        let now = window.mouseLocationOutsideOfEventStream
        if hypot(now.x - holdStartWindowPoint.x, now.y - holdStartWindowPoint.y) > 10 { cancelHold(); return }

        let elapsed = Date().timeIntervalSince(holdStartTime)
        if elapsed > 0.35 { holdRing?.isHidden = false }
        if elapsed >= holdDuration { holdFired() }
    }

    private func holdFired() {
        guard let window else { cancelHold(); return }
        holdTimer?.invalidate()
        holdTimer = nil
        holdRing?.removeFromSuperview()
        holdRing = nil
        holdReady = true

        if insideSuperMouseDown {
            // End PDFKit's click tracking so it doesn't stay stuck waiting for a mouse-up.
            // mouseDown() starts the drag as soon as PDFKit returns.
            if let up = NSEvent.mouseEvent(with: .leftMouseUp,
                                           location: window.mouseLocationOutsideOfEventStream,
                                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: 1, pressure: 0) {
                window.postEvent(up, atStart: true)
            }
        } else {
            startQueuedDrag()
        }
    }

    private func startQueuedDrag() {
        guard holdReady, let page = holdPage, let window else { return }
        holdReady = false
        holdPage = nil
        holdEvent = nil
        // fresh drag event at the current mouse position (the original click is 2 seconds old)
        guard let dragEvent = NSEvent.mouseEvent(with: .leftMouseDragged,
                                                 location: window.mouseLocationOutsideOfEventStream,
                                                 modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        beginPageDrag(page, event: dragEvent)
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdEvent = nil
        holdPage = nil
        holdReady = false
        holdRing?.removeFromSuperview()
        holdRing = nil
    }

    // Render the page (annotations included) to a PNG and drag it out like a file
    private func beginPageDrag(_ page: PDFPage, event: NSEvent) {
        let box = page.bounds(for: .cropBox)
        let scale: CGFloat = 2   // 2x so it stays sharp
        let image = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .cropBox)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let number = (document?.index(for: page) ?? 0) + 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Page \(number).png")
        do { try png.write(to: url) } catch { return }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let h: CGFloat = 140
        let w = h * image.size.width / max(image.size.height, 1)
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    @objc func commitAllTextBoxesToPDF() {
        for box in activeTextBoxes {
            let text = box.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let annotation = PDFAnnotation(bounds: box.pageRect, forType: .freeText, withProperties: nil)
                annotation.contents = text
                annotation.font = .systemFont(ofSize: box.currentFontSize)
                annotation.fontColor = .black
                annotation.color = CanvaTextBoxView.boxBackgroundColor
                let border = PDFBorder()
                border.lineWidth = 0
                annotation.border = border
                box.page.addAnnotation(annotation)
            }
            box.removeFromSuperview()
        }
        activeTextBoxes.removeAll()
        selectedTextBox = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.characters == String(UnicodeScalar(NSDeleteCharacter)!) {
            if let selected = selectedTextBox {
                eraseActiveTextBox(selected)
                return
            }
        }
        super.keyDown(with: event)
    }
}
