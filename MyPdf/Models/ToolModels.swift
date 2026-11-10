import SwiftUI
import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case browse = "Browse"
    case highlight = "Highlight"
    case textBox = "Text Box"
    case erase = "Erase"
    var id: String { rawValue }
}

enum HighlightMode: String, CaseIterable, Identifiable {
    case free = "Free"
    case text = "Text"
    var id: String { rawValue }
}

enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow = "Yellow"
    case green = "Green"
    case pink = "Pink"
    case blue = "Blue"
    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.90, blue: 0.25, alpha: 1.0)
        case .green: return NSColor(calibratedRed: 0.45, green: 0.88, blue: 0.45, alpha: 1.0)
        case .pink: return NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.65, alpha: 1.0)
        case .blue: return NSColor(calibratedRed: 0.40, green: 0.75, blue: 1.0, alpha: 1.0)
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}
