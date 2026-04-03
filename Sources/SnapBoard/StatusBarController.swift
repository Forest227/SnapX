import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()

        configureStatusItem()
        configurePopover()

        appState.dismissStatusPanel = { [weak self] in
            self?.closePopover()
        }
    }

    func tearDown() {
        appState.dismissStatusPanel = nil
        closePopover()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapBoard")
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "SnapBoard"
    }

    private func configurePopover() {
        let hostingController = NSHostingController(rootView: MenuBarContentView(appState: appState))
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = CGSize(width: 320, height: 430)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        appState.refreshPermissionStates()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
}
