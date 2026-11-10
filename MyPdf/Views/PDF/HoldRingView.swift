import AppKit
import QuartzCore

// Little ring that fills up while you hold, so you can see the page drag is about to start
final class HoldRingView: NSView {
    static let size: CGFloat = 44
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: 16,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for l in [track, ring] {
            l.frame = bounds
            l.path = path
            l.fillColor = nil
            l.lineWidth = 5
            l.lineCap = .round
            layer?.addSublayer(l)
        }
        track.strokeColor = NSColor.black.withAlphaComponent(0.25).cgColor
        ring.strokeColor = NSColor.systemBlue.cgColor
        ring.strokeEnd = 0
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func start(duration: TimeInterval) {
        let a = CABasicAnimation(keyPath: "strokeEnd")
        a.fromValue = 0
        a.toValue = 1
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        ring.strokeEnd = 1
        ring.add(a, forKey: "fill")
    }

    // never steal clicks
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
