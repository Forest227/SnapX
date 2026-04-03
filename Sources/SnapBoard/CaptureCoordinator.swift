import AppKit
import CoreGraphics
import Foundation

enum CaptureSelectionMode {
    case framed
    case display

    var instructionTitle: String {
        switch self {
        case .framed:
            "框选截图"
        case .display:
            "移动鼠标选择屏幕"
        }
    }

    func instructionCaption(hotKeyHint: String) -> String {
        switch self {
        case .framed:
            "默认高亮指针所在窗口；单击确认窗口，拖动框选区域 • 截图后可标注、提取文字、保存或钉住 • Esc 取消 • \(hotKeyHint) 唤起"
        case .display:
            "单击目标屏幕后进入编辑菜单，可标注、提取文字、保存或钉住 • 右键或 Esc 取消"
        }
    }
}

struct ScreenSelection: Equatable {
    let displayID: CGDirectDisplayID
    let rect: CGRect
    let scaleFactor: CGFloat
}

struct WindowCaptureSelection: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
    let ownerName: String
    let windowName: String?

    var displayName: String {
        guard let windowName else { return ownerName }

        let trimmedName = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return ownerName }

        return "\(ownerName) • \(trimmedName)"
    }
}

enum ScreenshotCaptureRequest: Equatable {
    case area(ScreenSelection)
    case display(ScreenSelection)
    case window(WindowCaptureSelection)
}

@MainActor
final class CaptureCoordinator {
    var onPinnedWindowsChanged: ((Int) -> Void)?

    private var overlayWindowControllers: [SelectionOverlayWindowController] = []
    private var pinnedWindowControllers: [PinnedScreenshotWindowController] = []
    private var screenshotEditorWindowController: ScreenshotEditorWindowController?
    private var cursorIsPushed = false
    private var pinnedWindowOpacity = 1.0
    private var isPinnedWindowMousePassthroughEnabled = false
    private var framedHotKeyHint = "⌘⇧S"
    private var displayHotKeyHint = "⌘⇧F"

    var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() -> Bool {
        if hasScreenCapturePermission {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func presentScreenRecordingHelp() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "SnapBoard 需要屏幕录制权限才能截图。授权后重新点击菜单栏按钮，或按快捷键 \(allHotKeyHints)。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    func beginFramedSelectionMode() {
        beginSelectionMode(for: .framed)
    }

    func beginDisplaySelectionMode() {
        beginSelectionMode(for: .display)
    }

    private func beginSelectionMode(for mode: CaptureSelectionMode) {
        guard overlayWindowControllers.isEmpty else { return }

        pushCrosshairCursor()

        overlayWindowControllers = NSScreen.screens.compactMap { screen in
            let controller = SelectionOverlayWindowController(
                screen: screen,
                mode: mode,
                hotKeyHint: hotKeyHint,
                captureHandler: { [weak self] request in
                    self?.finishCapture(with: request)
                },
                cancelHandler: { [weak self] in
                    self?.cancelSelectionMode()
                }
            )
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            return controller
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func cancelSelectionMode() {
        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers.removeAll()
        popCrosshairCursor()
    }

    func closeAllPinnedWindows() {
        let windows = pinnedWindowControllers
        windows.forEach { $0.close() }
    }

    func updatePinnedWindowOpacity(_ opacity: Double) {
        pinnedWindowOpacity = min(max(opacity, 0.25), 1)
        pinnedWindowControllers.forEach { $0.setWindowOpacity(pinnedWindowOpacity) }
    }

    func updatePinnedWindowMousePassthrough(_ enabled: Bool) {
        isPinnedWindowMousePassthroughEnabled = enabled
        pinnedWindowControllers.forEach { $0.setMousePassthrough(enabled) }
    }

    func updateHotKeyHints(framed: String, display: String) {
        framedHotKeyHint = framed
        displayHotKeyHint = display
    }

    private var hotKeyHint: String {
        framedHotKeyHint
    }

    private var allHotKeyHints: String {
        "\(framedHotKeyHint) / \(displayHotKeyHint)"
    }

    private func finishCapture(with request: ScreenshotCaptureRequest) {
        cancelSelectionMode()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            guard let image = ScreenshotCapturer.capture(request: request) else {
                NSSound.beep()
                return
            }

            self.presentCapturedImage(image, request: request)
        }
    }

    private func presentCapturedImage(_ image: NSImage, request: ScreenshotCaptureRequest) {
        screenshotEditorWindowController?.close()

        let controller = ScreenshotEditorWindowController(
            image: image,
            sourceRect: editorSourceRect(for: request),
            onPin: { [weak self] editedImage in
                self?.presentPinnedWindow(for: editedImage)
            },
            onCopy: { [weak self] editedImage in
                self?.copyToPasteboard(editedImage)
            },
            onClose: { [weak self] in
                self?.screenshotEditorWindowController = nil
            }
        )

        screenshotEditorWindowController = controller
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentPinnedWindow(for image: NSImage) {
        let windowController = PinnedScreenshotWindowController(image: image) { [weak self] controller in
            self?.removePinnedWindow(controller)
        }

        windowController.setWindowOpacity(pinnedWindowOpacity)
        windowController.setMousePassthrough(isPinnedWindowMousePassthroughEnabled)
        pinnedWindowControllers.append(windowController)
        onPinnedWindowsChanged?(pinnedWindowControllers.count)
        windowController.showWindow(nil)
        windowController.window?.orderFrontRegardless()
    }

    private func removePinnedWindow(_ controller: PinnedScreenshotWindowController) {
        pinnedWindowControllers.removeAll { $0 === controller }
        onPinnedWindowsChanged?(pinnedWindowControllers.count)
    }

    private func editorSourceRect(for request: ScreenshotCaptureRequest) -> CGRect? {
        switch request {
        case let .area(selection):
            globalRect(for: selection)

        case let .display(selection):
            globalRect(for: selection)

        case let .window(selection):
            selection.bounds
        }
    }

    private func globalRect(for selection: ScreenSelection) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
                return false
            }

            return screenID == selection.displayID
        }) else {
            return nil
        }

        return CGRect(
            x: screen.frame.minX + selection.rect.minX,
            y: screen.frame.maxY - selection.rect.maxY,
            width: selection.rect.width,
            height: selection.rect.height
        )
    }

    private func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func pushCrosshairCursor() {
        guard !cursorIsPushed else { return }
        cursorIsPushed = true
        NSCursor.crosshair.push()
    }

    private func popCrosshairCursor() {
        guard cursorIsPushed else { return }
        cursorIsPushed = false
        NSCursor.pop()
    }
}

enum ScreenshotCapturer {
    @MainActor
    static func capture(request: ScreenshotCaptureRequest) -> NSImage? {
        switch request {
        case let .area(selection):
            captureArea(selection: selection)

        case let .display(selection):
            captureDisplay(selection: selection)

        case let .window(selection):
            captureWindow(selection: selection)
        }
    }

    @MainActor
    private static func captureArea(selection: ScreenSelection) -> NSImage? {
        let captureRect = CGRect(
            x: selection.rect.origin.x * selection.scaleFactor,
            y: selection.rect.origin.y * selection.scaleFactor,
            width: selection.rect.width * selection.scaleFactor,
            height: selection.rect.height * selection.scaleFactor
        ).integral

        guard let image = CGDisplayCreateImage(selection.displayID, rect: captureRect) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.rect.size)
    }

    @MainActor
    private static func captureDisplay(selection: ScreenSelection) -> NSImage? {
        guard let image = CGDisplayCreateImage(selection.displayID) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.rect.size)
    }

    @MainActor
    private static func captureWindow(selection: WindowCaptureSelection) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            selection.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.bounds.size)
    }
}
