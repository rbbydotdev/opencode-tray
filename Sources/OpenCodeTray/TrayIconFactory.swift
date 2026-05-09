import AppKit

enum TrayIconFactory {
    static func image(running: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let outer = NSRect(x: 4.5, y: 2.5, width: 9, height: 13)
            let inner = NSRect(x: 6.6, y: 5.0, width: 4.8, height: 7.6)
            let centerBlock = NSRect(x: 6.6, y: 8.4, width: 4.8, height: 4.2)

            if running {
                let mark = NSBezierPath()
                mark.append(NSBezierPath(rect: outer))
                mark.append(NSBezierPath(rect: inner))
                mark.windingRule = .evenOdd
                mark.fill()
                NSBezierPath(rect: centerBlock).fill()
            } else {
                let outerPath = NSBezierPath(rect: outer)
                outerPath.lineWidth = 1.8
                outerPath.stroke()

                let innerPath = NSBezierPath(rect: inner)
                innerPath.lineWidth = 1.4
                innerPath.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
