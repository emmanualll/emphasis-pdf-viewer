import AppKit

final class CursorFactory {
    static func makeCursor(symbolName: String, pointSize: CGFloat = 16, hotSpot: NSPoint? = nil) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return false }
            let drawRect = NSRect(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 2.0, color: NSColor.white.cgColor)
            symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))?.draw(in: drawRect)
            ctx.restoreGState()
            symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.1, alpha: 1.0)]))?.draw(in: drawRect)
            return true
        }
        let spot = hotSpot ?? NSPoint(x: size.width / 2, y: size.height / 2)
        return NSCursor(image: image, hotSpot: spot)
    }

    static let moveCursor = makeCursor(symbolName: "arrow.up.and.down.and.arrow.left.and.right")
    static let nwseCursor = makeCursor(symbolName: "arrow.up.left.and.arrow.down.right")
    static let neswCursor = makeCursor(symbolName: "arrow.up.right.and.arrow.down.left")
}
