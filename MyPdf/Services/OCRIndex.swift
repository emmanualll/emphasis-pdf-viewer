import Foundation
import PDFKit
import Vision
import CoreGraphics
import Combine

nonisolated func foldForSearch(_ s: String) -> String {
    let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

nonisolated func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    for i in 1...a.count {
        var cur = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return prev[b.count]
}

nonisolated func wordMatches(_ word: String, _ query: String) -> Bool {
    if word == query { return true }
    if query.count >= 3 && word.contains(query) { return true }
    if query.count >= 4 {
        let allowed = query.count >= 8 ? 2 : 1   // typos allowed grow with word length
        if abs(word.count - query.count) <= allowed && editDistance(word, query) <= allowed { return true }
    }
    return false
}

// Reads every page once with Vision and searches the result
@MainActor
final class OCRIndex: ObservableObject {
    @Published var isIndexing = false
    @Published var progress = 0.0

    // Sensible threshold: pages with fewer than 60 alphanumeric characters are treated
    // as scanned pages (e.g. only page number, header, or stamp on top of a scanned image).
    private static let minTextLayerCharacters = 60

    private var pages: [Int: [OCRWord]] = [:]
    private var indexedDocument: PDFDocument?
    private var generation = 0

    func reset() {
        generation += 1
        pages = [:]
        indexedDocument = nil
        progress = 0
        isIndexing = false
    }

    private static func extractWordsFromTextLayer(page: PDFPage) -> [OCRWord]? {
        guard let fullText = page.string else { return nil }
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let alphanumericCount = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        guard alphanumericCount >= minTextLayerCharacters else { return nil }

        let cropBox = page.bounds(for: .cropBox)
        guard cropBox.width > 0, cropBox.height > 0 else { return nil }

        var words: [OCRWord] = []
        let nsText = fullText as NSString
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byWords) { sub, range, _, _ in
            guard let sub, let sel = page.selection(for: range) else { return }
            let rect = sel.bounds(for: page)
            guard rect.width > 0, rect.height > 0 else { return }
            let folded = foldForSearch(sub)
            guard !folded.isEmpty else { return }
            let norm = CGRect(
                x: (rect.minX - cropBox.minX) / cropBox.width,
                y: (rect.minY - cropBox.minY) / cropBox.height,
                width: rect.width / cropBox.width,
                height: rect.height / cropBox.height
            )
            words.append(OCRWord(text: sub, folded: folded, box: norm))
        }
        return words.isEmpty ? nil : words
    }

    func ensureIndexed(_ document: PDFDocument) async {
        if indexedDocument !== document { reset(); indexedDocument = document }
        let gen = generation
        let total = document.pageCount

        // Pass 1: Extract words from pages with real text layer (fast, synchronous on MainActor)
        var scannedPageIndices: [Int] = []
        for i in 0..<total {
            guard gen == generation else { return }
            if pages[i] == nil {
                if let page = document.page(at: i), let words = Self.extractWordsFromTextLayer(page: page) {
                    pages[i] = words
                } else {
                    scannedPageIndices.append(i)
                }
            }
        }

        // If all pages had text layers (or were already cached), no OCR is needed!
        guard !scannedPageIndices.isEmpty else {
            isIndexing = false
            progress = 0
            return
        }

        // Pass 2: OCR only the scanned pages
        isIndexing = true
        progress = 0
        let scannedTotal = scannedPageIndices.count
        for (step, i) in scannedPageIndices.enumerated() {
            guard gen == generation else { return }
            if let page = document.page(at: i), let image = Self.render(page) {
                let words = await Task.detached(priority: .userInitiated) { Self.recognize(image) }.value
                guard gen == generation else { return }
                pages[i] = words
            } else {
                pages[i] = []
            }
            progress = Double(step + 1) / Double(scannedTotal)
        }
        isIndexing = false
    }

    func search(_ query: String, in document: PDFDocument) -> [OCRHit] {
        let q = query.split(whereSeparator: { $0.isWhitespace })
            .map { foldForSearch(String($0)) }
            .filter { !$0.isEmpty }
        guard !q.isEmpty else { return [] }

        var hits: [OCRHit] = []
        for i in 0..<document.pageCount {
            guard let words = pages[i], !words.isEmpty, let page = document.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)
            var start = 0
            while start + q.count <= words.count {
                if (0..<q.count).allSatisfy({ wordMatches(words[start + $0].folded, q[$0]) }) {
                    let rects = words[start..<start + q.count].map { w in
                        CGRect(x: box.minX + w.box.minX * box.width,
                               y: box.minY + w.box.minY * box.height,
                               width: w.box.width * box.width,
                               height: w.box.height * box.height)
                    }
                    hits.append(OCRHit(pageIndex: i, rects: rects))
                    start += q.count
                } else {
                    start += 1
                }
            }
        }
        return hits
    }

    // Draw the page onto a white background at about 3000px on the long side
    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = 3000 / max(box.width, box.height)
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)

        let hadAnnotations = page.displaysAnnotations
        page.displaysAnnotations = false   // read the page itself, not your highlights
        page.draw(with: .cropBox, to: ctx)
        page.displaysAnnotations = hadAnnotations
        return ctx.makeImage()
    }

    nonisolated private static func recognize(_ image: CGImage) -> [OCRWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        var words: [OCRWord] = []
        for obs in request.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let s = cand.string
            s.enumerateSubstrings(in: s.startIndex..<s.endIndex, options: .byWords) { sub, range, _, _ in
                guard let sub, let box = try? cand.boundingBox(for: range) else { return }
                let folded = foldForSearch(sub)
                if !folded.isEmpty { words.append(OCRWord(text: sub, folded: folded, box: box.boundingBox)) }
            }
        }
        return words
    }
}
