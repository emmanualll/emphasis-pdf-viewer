import AppKit
import PDFKit

enum TwoUpPDFExporter {
    static func buildTwoUpPDFData(from sourceDoc: PDFDocument) -> Data? {
        let pageCount = sourceDoc.pageCount
        guard pageCount > 0 else { return nil }

        // Standard A4 landscape dimensions: 297mm x 210mm (841.89 x 595.28 pt)
        let sheetSize = CGSize(width: 841.89, height: 595.28)
        var mediaBox = CGRect(origin: .zero, size: sheetSize)

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        let margin: CGFloat = 20.0
        let innerGap: CGFloat = 16.0
        let usableWidth = sheetSize.width - (margin * 2) - innerGap
        let pageTargetWidth = usableWidth / 2.0
        let pageTargetHeight = sheetSize.height - (margin * 2)

        let leftTargetRect = CGRect(x: margin, y: margin, width: pageTargetWidth, height: pageTargetHeight)
        let rightTargetRect = CGRect(x: margin + pageTargetWidth + innerGap, y: margin, width: pageTargetWidth, height: pageTargetHeight)

        func drawPageContent(_ page: PDFPage, into targetRect: CGRect, in ctx: CGContext) {
            let box = page.bounds(for: .cropBox)
            let isRotated90or270 = (page.rotation == 90 || page.rotation == 270)
            let pageWidth = isRotated90or270 ? box.height : box.width
            let pageHeight = isRotated90or270 ? box.width : box.height
            guard pageWidth > 0, pageHeight > 0 else { return }

            let scale = min(targetRect.width / pageWidth, targetRect.height / pageHeight)
            let drawW = pageWidth * scale
            let drawH = pageHeight * scale
            let drawX = targetRect.minX + (targetRect.width - drawW) / 2.0
            let drawY = targetRect.minY + (targetRect.height - drawH) / 2.0

            ctx.saveGState()
            ctx.translateBy(x: drawX, y: drawY)
            ctx.scaleBy(x: scale, y: scale)

            let hadAnnotations = page.displaysAnnotations
            page.displaysAnnotations = true
            page.draw(with: .cropBox, to: ctx)
            page.displaysAnnotations = hadAnnotations
            ctx.restoreGState()
        }

        let sheetCount = (pageCount + 1) / 2
        for sheet in 0..<sheetCount {
            context.beginPage(mediaBox: &mediaBox)

            // Crisp white sheet background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)

            let leftPageIndex = sheet * 2
            let rightPageIndex = sheet * 2 + 1

            if let leftPage = sourceDoc.page(at: leftPageIndex) {
                drawPageContent(leftPage, into: leftTargetRect, in: context)
            }

            if rightPageIndex < pageCount, let rightPage = sourceDoc.page(at: rightPageIndex) {
                drawPageContent(rightPage, into: rightTargetRect, in: context)
            }

            context.endPage()
        }

        context.closePDF()
        return mutableData as Data
    }
}
