import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(appState: AppState) {
        let hostingView = NSHostingView(rootView: SettingsView(appState: appState))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 430, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.title = "SnapBoard 设置"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 430, height: 500)
        window.center()
        window.contentView = hostingView
        window.delegate = self
        window.setFrameAutosaveName("SnapBoardSettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        if let window {
            var frame = window.frame
            frame.size.width = max(frame.size.width, window.minSize.width)
            frame.size.height = max(frame.size.height, window.minSize.height)
            window.setFrame(frame, display: true)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
