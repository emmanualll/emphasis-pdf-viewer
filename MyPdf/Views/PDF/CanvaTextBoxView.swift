import AppKit
import PDFKit

// Interactive Canva-style text box with corner/edge handles and dynamic font scaling
final class CanvaTextBoxView: NSView, NSTextViewDelegate {
    let page: PDFPage
    var pageRect: CGRect
    var baseFontSize: CGFloat = 10.0
    var currentFontSize: CGFloat = 10.0
    var scaleFactor: CGFloat = 1.0

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var onDelete: (() -> Void)?
    var onSelected: (() -> Void)?
    var onGeometryChanged: (() -> Void)?
    var onContentChanged: (() -> Void)?
    var onFinishEditing: (() -> Void)?

    let textView = NSTextView()

    enum CornerHandle {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    enum EdgeHandle {
        case top, bottom, left, right
    }

    enum HitZone: Equatable {
        case none
        case move
        case corner(CornerHandle)
        case edge(EdgeHandle)
    }

    private enum DragMode {
        case none
        case move
        case resizeCorner(CornerHandle)
        case resizeEdge(EdgeHandle)
    }

    private var dragMode: DragMode = .none
    private var dragStartMouse = CGPoint.zero
    private var dragStartFrame = CGRect.zero
    private var dragStartFontSize: CGFloat = 10.0

    private let handleSize: CGFloat = 8.0
    private var handleViews: [CornerHandle: NSView] = [:]
    private var trackingArea: NSTrackingArea?

    static let boxBackgroundColor = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.95, alpha: 1.0)

    init(page: PDFPage, pageRect: CGRect, baseFontSize: CGFloat = 10.0) {
        self.page = page
        self.pageRect = pageRect
        self.baseFontSize = baseFontSize
        self.currentFontSize = baseFontSize
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = Self.boxBackgroundColor.cgColor

        textView.wantsLayer = true
        textView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        textView.drawsBackground = true
        textView.backgroundColor = Self.boxBackgroundColor
        textView.isRichText = false
        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.font = .systemFont(ofSize: max(6, round(currentFontSize * scaleFactor)))
        textView.allowsUndo = false
        addSubview(textView)

        // 4 corner handles
        for handle in [CornerHandle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let h = NSView()
            h.wantsLayer = true
            h.layerContentsRedrawPolicy = .onSetNeedsDisplay
            h.layer?.backgroundColor = NSColor.white.cgColor
            h.layer?.borderColor = NSColor.controlAccentColor.cgColor
            h.layer?.borderWidth = 1.5
            h.layer?.cornerRadius = handleSize / 2
            h.layer?.shadowColor = NSColor.black.cgColor
            h.layer?.shadowOpacity = 0.2
            h.layer?.shadowOffset = CGSize(width: 0, height: -1)
            h.layer?.shadowRadius = 1.5
            h.isHidden = true
            addSubview(h)
            handleViews[handle] = h
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncBackingScale()
    }

    private func syncBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        textView.layer?.contentsScale = scale
        for h in handleViews.values {
            h.layer?.contentsScale = scale
        }
    }

    func updateScale(_ factor: CGFloat) {
        self.scaleFactor = factor
        textView.font = .systemFont(ofSize: max(6, round(currentFontSize * scaleFactor)))
        syncBackingScale()
        layoutSubviews()
        setNeedsDisplay(bounds)
        textView.setNeedsDisplay(textView.bounds)
    }

    func updateAppearance() {
        if isSelected {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.0
            handleViews.values.forEach { $0.isHidden = false }
        } else {
            layer?.borderWidth = 0.0
            handleViews.values.forEach { $0.isHidden = true }
        }
    }

    override func layout() {
        super.layout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        textView.frame = bounds
        let half = handleSize / 2

        handleViews[.topLeft]?.frame = CGRect(x: -half, y: -half, width: handleSize, height: handleSize)
        handleViews[.topRight]?.frame = CGRect(x: bounds.width - half, y: -half, width: handleSize, height: handleSize)
        handleViews[.bottomLeft]?.frame = CGRect(x: -half, y: bounds.height - half, width: handleSize, height: handleSize)
        handleViews[.bottomRight]?.frame = CGRect(x: bounds.width - half, y: bounds.height - half, width: handleSize, height: handleSize)
    }

    private func hitZone(at point: CGPoint) -> HitZone {
        // While actively editing text, clicks inside the text area edit text
        if window?.firstResponder == textView && bounds.insetBy(dx: 6, dy: 6).contains(point) {
            return .none
        }

        let cornerRadius: CGFloat = 14.0
        let edgeMargin: CGFloat = 8.0

        // 1. Corners
        if point.x <= cornerRadius && point.y <= cornerRadius {
            return .corner(.topLeft)
        }
        if point.x >= bounds.width - cornerRadius && point.y <= cornerRadius {
            return .corner(.topRight)
        }
        if point.x <= cornerRadius && point.y >= bounds.height - cornerRadius {
            return .corner(.bottomLeft)
        }
        if point.x >= bounds.width - cornerRadius && point.y >= bounds.height - cornerRadius {
            return .corner(.bottomRight)
        }

        // 2. Edges
        if point.y <= edgeMargin {
            return .edge(.top)
        }
        if point.y >= bounds.height - edgeMargin {
            return .edge(.bottom)
        }
        if point.x <= edgeMargin {
            return .edge(.left)
        }
        if point.x >= bounds.width - edgeMargin {
            return .edge(.right)
        }

        // 3. Body (Move)
        if bounds.contains(point) {
            return .move
        }

        return .none
    }

    func cursor(for point: CGPoint) -> NSCursor {
        switch hitZone(at: point) {
        case .corner(.topLeft), .corner(.bottomRight):
            return CursorFactory.nwseCursor
        case .corner(.topRight), .corner(.bottomLeft):
            return CursorFactory.neswCursor
        case .edge(.left), .edge(.right):
            return .resizeLeftRight
        case .edge(.top), .edge(.bottom):
            return .resizeUpDown
        case .move:
            return CursorFactory.moveCursor
        case .none:
            return window?.firstResponder == textView ? .iBeam : .arrow
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursor(for: p).set()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        cursor(for: p).set()
        super.mouseMoved(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: CursorFactory.moveCursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let hitRect = bounds.insetBy(dx: -handleSize, dy: -handleSize)
        guard hitRect.contains(p) else { return nil }

        if window?.firstResponder == textView && bounds.insetBy(dx: 6, dy: 6).contains(p) {
            return textView.hitTest(point) ?? self
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let zone = hitZone(at: p)

        if event.clickCount >= 2 || (bounds.contains(p) && textView.string.isEmpty) {
            window?.makeFirstResponder(textView)
            dragMode = .none
            return
        }

        if !isSelected {
            onSelected?()
        }

        dragStartMouse = superview?.convert(event.locationInWindow, from: nil) ?? p
        dragStartFrame = frame
        dragStartFontSize = currentFontSize

        switch zone {
        case .corner(let handle):
            dragMode = .resizeCorner(handle)
        case .edge(let edge):
            dragMode = .resizeEdge(edge)
        case .move:
            dragMode = .move
        case .none:
            dragMode = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sv = superview else { return }
        let currentMouse = sv.convert(event.locationInWindow, from: nil)
        let dx = currentMouse.x - dragStartMouse.x
        let dy = currentMouse.y - dragStartMouse.y

        let minW: CGFloat = 50.0
        let minH: CGFloat = 24.0

        switch dragMode {
        case .none:
            break

        case .move:
            let newX = round(dragStartFrame.origin.x + dx)
            let newY = round(dragStartFrame.origin.y + dy)
            setFrameOrigin(CGPoint(x: newX, y: newY))
            onGeometryChanged?()

        case .resizeEdge(let edge):
            var newFrame = dragStartFrame
            switch edge {
            case .left:
                let w = max(minW, dragStartFrame.width - dx)
                newFrame.origin.x = round(dragStartFrame.maxX - w)
                newFrame.size.width = round(w)
            case .right:
                let w = max(minW, dragStartFrame.width + dx)
                newFrame.size.width = round(w)
            case .top:
                let h = max(minH, dragStartFrame.height - dy)
                newFrame.origin.y = round(dragStartFrame.maxY - h)
                newFrame.size.height = round(h)
            case .bottom:
                let h = max(minH, dragStartFrame.height + dy)
                newFrame.size.height = round(h)
            }
            frame = newFrame
            onGeometryChanged?()

        case .resizeCorner(let handle):
            let startW = dragStartFrame.width
            let startH = dragStartFrame.height
            guard startW > 0, startH > 0 else { break }

            var scale: CGFloat = 1.0
            switch handle {
            case .bottomRight:
                let targetW = max(minW, startW + dx)
                let targetH = max(minH, startH + dy)
                scale = max(minW / startW, max(minH / startH, (targetW / startW + targetH / startH) / 2))
                let newW = round(startW * scale)
                let newH = round(startH * scale)
                frame = CGRect(x: dragStartFrame.minX, y: dragStartFrame.minY, width: newW, height: newH)

            case .bottomLeft:
                let targetW = max(minW, startW - dx)
                let targetH = max(minH, startH + dy)
                scale = max(minW / startW, max(minH / startH, (targetW / startW + targetH / startH) / 2))
                let newW = round(startW * scale)
                let newH = round(startH * scale)
                frame = CGRect(x: round(dragStartFrame.maxX - newW), y: dragStartFrame.minY, width: newW, height: newH)

            case .topRight:
                let targetW = max(minW, startW + dx)
                let targetH = max(minH, startH - dy)
                scale = max(minW / startW, max(minH / startH, (targetW / startW + targetH / startH) / 2))
                let newW = round(startW * scale)
                let newH = round(startH * scale)
                frame = CGRect(x: dragStartFrame.minX, y: round(dragStartFrame.maxY - newH), width: newW, height: newH)

            case .topLeft:
                let targetW = max(minW, startW - dx)
                let targetH = max(minH, startH - dy)
                scale = max(minW / startW, max(minH / startH, (targetW / startW + targetH / startH) / 2))
                let newW = round(startW * scale)
                let newH = round(startH * scale)
                frame = CGRect(x: round(dragStartFrame.maxX - newW), y: round(dragStartFrame.maxY - newH), width: newW, height: newH)
            }

            currentFontSize = max(6.0, min(96.0, round(dragStartFontSize * scale)))
            textView.font = .systemFont(ofSize: max(6, round(currentFontSize * scaleFactor)))
            onGeometryChanged?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
    }

    override func keyDown(with event: NSEvent) {
        // Delete or Backspace key
        if event.keyCode == 51 || event.characters == String(UnicodeScalar(NSDeleteCharacter)!) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }

    func textDidChange(_ notification: Notification) {
        onContentChanged?()
    }

    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onFinishEditing?()
            return true
        }
        return false
    }
}
