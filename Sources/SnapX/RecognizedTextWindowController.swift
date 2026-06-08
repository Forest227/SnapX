import AppKit
import SwiftUI

@MainActor
final class RecognizedTextWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)
        configureWindow(panel, text: text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        if let parent = window?.parent {
            parent.removeChildWindow(window!)
        }
        onClose()
    }

    func show(relativeTo parentWindow: NSWindow?) {
        guard let window else { return }

        if let parentWindow {
            parentWindow.addChildWindow(window, ordered: .above)
            let origin = CGPoint(
                x: parentWindow.frame.midX - (window.frame.width / 2),
                y: parentWindow.frame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
            parentWindow.makeKey()
        } else {
            window.center()
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureWindow(_ window: NSPanel, text: String) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "提取到的文字"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let container = NSView(frame: CGRect(x: 0, y: 0, width: 420, height: 280))
        container.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "识别结果已复制到剪贴板。")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = CGSize(width: 2, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        container.addSubview(subtitle)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            subtitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])

        window.contentView = container
    }
}