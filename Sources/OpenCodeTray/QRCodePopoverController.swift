import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class QRCodePopoverController {
    private let popover = NSPopover()
    private let viewController = QRCodeViewController()

    init() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 296, height: 374)
    }

    func show(target: ServerAccessTarget, relativeTo button: NSStatusBarButton) {
        viewController.update(target: target)

        if popover.isShown {
            popover.close()
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

private final class QRCodeViewController: NSViewController {
    private let imageView = NSImageView()
    private let subtitleField = NSTextField(labelWithString: "")
    private let urlField = NSTextField(labelWithString: "")
    private let noteField = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy URL", target: nil, action: nil)
    private var urlString = ""

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 374))

        let title = NSTextField(labelWithString: "OpenCode Server")
        title.font = .boldSystemFont(ofSize: 14)
        title.alignment = .center

        subtitleField.font = .systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.alignment = .center

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 220).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.textColor = .secondaryLabelColor
        urlField.alignment = .center
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.maximumNumberOfLines = 1
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 256).isActive = true

        noteField.font = .systemFont(ofSize: 11)
        noteField.textColor = .secondaryLabelColor
        noteField.alignment = .center
        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.widthAnchor.constraint(equalToConstant: 256).isActive = true

        copyButton.target = self
        copyButton.action = #selector(copyURL(_:))

        let stack = NSStackView(views: [title, subtitleField, imageView, urlField, noteField, copyButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])

        view = container
    }

    func update(target: ServerAccessTarget) {
        urlString = target.urlString
        subtitleField.stringValue = target.subtitle
        urlField.stringValue = target.displayURLString
        noteField.stringValue = target.note ?? "Scan from a device that can reach this address."
        imageView.image = QRCodeImageFactory.image(for: target.urlString, size: 220)
    }

    @objc private func copyURL(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }
}

private enum QRCodeImageFactory {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(for string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = size / max(outputImage.extent.width, outputImage.extent.height)
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
