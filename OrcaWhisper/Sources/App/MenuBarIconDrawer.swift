import AppKit

final class MenuBarIconDrawer {
    static func createOrcaIcon(isRecording: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Orca Dorsal Fin Path
            let finPath = NSBezierPath()
            // Base left
            finPath.move(to: NSPoint(x: 3.0, y: 3.0))
            // Front curve sweeping upward to fin tip
            finPath.curve(to: NSPoint(x: 14.5, y: 15.0),
                          controlPoint1: NSPoint(x: 6.5, y: 4.5),
                          controlPoint2: NSPoint(x: 12.0, y: 9.0))
            // Trailing edge curved downward
            finPath.curve(to: NSPoint(x: 10.0, y: 3.0),
                          controlPoint1: NSPoint(x: 14.0, y: 9.5),
                          controlPoint2: NSPoint(x: 11.5, y: 5.5))
            finPath.close()

            if isRecording {
                NSColor.systemRed.setFill()
            } else {
                NSColor.black.setFill()
            }
            finPath.fill()

            // Outer acoustic wave arc
            let wavePath = NSBezierPath()
            wavePath.appendArc(withCenter: NSPoint(x: 4.0, y: 4.0), radius: 11.0, startAngle: 15, endAngle: 75)
            wavePath.lineWidth = 1.5
            wavePath.lineCapStyle = .round

            if isRecording {
                NSColor.systemRed.setStroke()
            } else {
                NSColor.black.setStroke()
            }
            wavePath.stroke()

            return true
        }

        image.isTemplate = !isRecording
        return image
    }
}
