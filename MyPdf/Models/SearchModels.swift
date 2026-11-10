import Foundation
import CoreGraphics

let searchMarkTag = "__ocr_search__"

// One recognised word and where it sits on the page (0-1 coordinates, origin bottom-left)
nonisolated struct OCRWord: Sendable {
    let text: String
    let folded: String   // lowercase, no accents or punctuation, used for matching
    let box: CGRect
}

struct OCRHit {
    let pageIndex: Int
    let rects: [CGRect]   // in PDF page coordinates
}

struct JumpTarget: Equatable {
    let id = UUID()
    let pageIndex: Int
    let rect: CGRect
}

struct SearchPageItem: Identifiable {
    let pageIndex: Int
    let hitIndices: [Int]
    var id: Int { pageIndex }
}
