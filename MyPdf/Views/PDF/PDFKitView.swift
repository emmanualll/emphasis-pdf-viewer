import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument?
    let tool: Tool
    let highlightMode: HighlightMode
    let highlightColor: HighlightColor
    let highlightStrength: Double
    let useFixedHeight: Bool
    let fixedHeight: CGFloat
    let bookView: Bool
    let jump: JumpTarget?
    var onDocumentChanged: (() -> Void)? = nil
    var onCurrentPageChanged: ((Int) -> Void)? = nil
    var onToolChanged: ((Tool) -> Void)? = nil

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let view = AnnotatingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ nsView: AnnotatingPDFView, context: Context) {
        if nsView.document !== document { nsView.document = document }
        nsView.tool = tool
        nsView.highlightMode = highlightMode
        nsView.highlightColor = highlightColor.nsColor
        nsView.highlightStrength = highlightStrength
        nsView.useFixedHeight = useFixedHeight
        nsView.fixedHeight = fixedHeight
        nsView.onDocumentChanged = onDocumentChanged
        nsView.onCurrentPageChanged = onCurrentPageChanged
        nsView.onToolChanged = onToolChanged

        // only touch the display mode when it actually changes, so scroll position isn't reset
        let wanted: PDFDisplayMode = bookView ? .twoUpContinuous : .singlePageContinuous
        if nsView.displayMode != wanted {
            nsView.displayMode = wanted
            nsView.autoScales = true
        }
        nsView.displaysAsBook = bookView

        if let jump, jump.id != nsView.lastJumpID {
            nsView.lastJumpID = jump.id
            if let page = nsView.document?.page(at: jump.pageIndex) {
                if jump.rect == .zero {
                    nsView.go(to: page)
                } else {
                    nsView.go(to: jump.rect.insetBy(dx: -80, dy: -80), on: page)
                }
            }
        }
    }
}
