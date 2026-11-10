import AppKit
import PDFKit

final class RoundedHighlightAnnotation: PDFAnnotation {
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        let cornerRadius = min(5.0, min(bounds.width, bounds.height) / 3)
        let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }
}
