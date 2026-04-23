import AppKit
import CoreGraphics
import Foundation

enum CaptureTimingMode: String, CaseIterable, Identifiable, Codable {
    case freezeFirst = "freezeFirst"
    case liveSelect = "liveSelect"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freezeFirst:
            "先冻结"
        case .liveSelect:
            "先选择"
        }
    }

    var description: String {
        switch self {
        case .freezeFirst:
            "触发截图时立即冻结屏幕，在静止画面上框选和编辑"
        case .liveSelect:
            "先在实时画面上框选，确认后才捕获对应区域"
        }
    }

    var icon: String {
        switch self {
        case .freezeFirst:
            "snow"
        case .liveSelect:
            "cursorarrow.and.square.on.square.dashed"
        }
    }
}

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
    var captureTimingMode: CaptureTimingMode = .liveSelect
    private var frozenScreenImages: [CGDirectDisplayID: CGImage] = [:]
    private lazy var captureSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "capture", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()
    private lazy var selectCaptureSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "select_capture", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

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
        alert.informativeText = "SnapX 需要屏幕录制权限才能截图。授权后重新点击菜单栏按钮，或按快捷键 \(allHotKeyHints)。"
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

        if captureTimingMode == .freezeFirst {
            captureSound?.play()
        } else {
            selectCaptureSound?.play()
        }

        // In freeze-first mode, capture all screens before showing overlay
        frozenScreenImages = [:]
        if captureTimingMode == .freezeFirst {
            for screen in NSScreen.screens {
                guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                      let cgImage = CGDisplayCreateImage(displayID) else {
                    continue
                }
                frozenScreenImages[displayID] = cgImage
            }
        }

        pushCrosshairCursor()

        overlayWindowControllers = NSScreen.screens.compactMap { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let frozenImage = frozenScreenImages[displayID]

            let controller = SelectionOverlayWindowController(
                screen: screen,
                mode: mode,
                hotKeyHint: hotKeyHint,
                frozenImage: frozenImage,
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
        frozenScreenImages = [:]
        popCrosshairCursor()
    }

    func closeAllPinnedWindows() {
        let windows = pinnedWindowControllers
        windows.forEach { $0.close() }
    }

    func pinImage(_ image: NSImage) {
        presentPinnedWindow(for: image)
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
        // For display capture, overlay covers the whole screen so must hide first
        if case .display = request {
            overlayWindowControllers.forEach { $0.window?.orderOut(nil) }
        }

        let image: NSImage?
        if frozenScreenImages.isEmpty {
            // Live-select mode: capture now
            image = ScreenshotCapturer.capture(request: request)
        } else {
            // Freeze-first mode: crop from pre-captured image
            image = ScreenshotCapturer.cropFromFrozen(request: request, frozenImages: frozenScreenImages)
        }

        guard let image else {
            NSSound.beep()
            cancelSelectionMode()
            return
        }

        if transitionSelectionOverlayToEditor(with: image, request: request) {
            return
        }

        cancelSelectionMode()
        presentCapturedImage(image, request: request)
    }

    private func presentCapturedImage(_ image: NSImage, request: ScreenshotCaptureRequest) {
        let sourceRect = editorSourceRect(for: request)
        presentCapturedImage(image, sourceRect: sourceRect)
    }

    private func presentCapturedImage(_ image: NSImage, sourceRect: CGRect?, existingWindow: NSWindow? = nil) {
        screenshotEditorWindowController?.close()

        let controller = ScreenshotEditorWindowController(
            image: image,
            sourceRect: sourceRect,
            existingWindow: existingWindow,
            onPin: { [weak self] editedImage in
                self?.presentPinnedWindow(for: editedImage)
            },
            onCopy: { [weak self] editedImage in
                ScreenshotHistory.shared.add(image)
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

    private func transitionSelectionOverlayToEditor(with image: NSImage, request: ScreenshotCaptureRequest) -> Bool {
        guard let sourceRect = editorSourceRect(for: request),
              let targetIndex = overlayWindowControllers.firstIndex(where: { $0.contains(globalRect: sourceRect) }),
              let transitionWindow = overlayWindowControllers[targetIndex].takeWindowForTransition() else {
            return false
        }

        let controllersToClose = overlayWindowControllers.enumerated().compactMap { index, controller in
            index == targetIndex ? nil : controller
        }
        overlayWindowControllers.removeAll()
        frozenScreenImages = [:]

        controllersToClose.forEach { $0.close() }

        popCrosshairCursor()
        presentCapturedImage(image, sourceRect: sourceRect, existingWindow: transitionWindow)
        return true
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
            cocoaGlobalRect(forWindowScreenRect: selection.bounds)
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

    private func cocoaGlobalRect(forWindowScreenRect rect: CGRect) -> CGRect {
        let desktopTopEdge = NSScreen.screens.map(\.frame.maxY).max() ?? rect.maxY
        return CGRect(
            x: rect.minX,
            y: desktopTopEdge - rect.maxY,
            width: rect.width,
            height: rect.height
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

    /// Crop from a pre-captured frozen full-screen image.
    @MainActor
    static func cropFromFrozen(request: ScreenshotCaptureRequest, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        switch request {
        case let .area(selection):
            cropFrozenArea(selection: selection, frozenImages: frozenImages)

        case let .display(selection):
            cropFrozenDisplay(selection: selection, frozenImages: frozenImages)

        case let .window(selection):
            // Window capture in freeze-first mode: crop the window bounds from the frozen screen
            cropFrozenWindow(selection: selection, frozenImages: frozenImages)
        }
    }

    @MainActor
    private static func captureArea(selection: ScreenSelection) -> NSImage? {
        let captureRect = selection.rect.integral

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

    // MARK: - Freeze-first cropping

    @MainActor
    private static func cropFrozenArea(selection: ScreenSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        guard let fullImage = frozenImages[selection.displayID] else { return nil }

        let cropRect = CGRect(
            x: selection.rect.minX * selection.scaleFactor,
            y: selection.rect.minY * selection.scaleFactor,
            width: selection.rect.width * selection.scaleFactor,
            height: selection.rect.height * selection.scaleFactor
        ).integral

        guard let cropped = fullImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: selection.rect.size)
    }

    @MainActor
    private static func cropFrozenDisplay(selection: ScreenSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        guard let fullImage = frozenImages[selection.displayID] else { return nil }
        return NSImage(cgImage: fullImage, size: selection.rect.size)
    }

    @MainActor
    private static func cropFrozenWindow(selection: WindowCaptureSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        // Find which screen contains this window
        let windowBounds = selection.bounds

        for screen in NSScreen.screens {
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let fullImage = frozenImages[displayID] else {
                continue
            }

            let screenFrame = screen.frame
            let scaleFactor = screen.backingScaleFactor

            // Convert window bounds (CGWindowServer coords, top-left origin) to screen-local coords
            let desktopTopEdge = NSScreen.screens.map(\.frame.maxY).max() ?? screenFrame.maxY
            let windowCocoaY = desktopTopEdge - windowBounds.maxY
            let localX = windowBounds.minX - screenFrame.minX
            let localY = screenFrame.maxY - windowCocoaY - windowBounds.height

            // Check if this window is on this screen
            let localRect = CGRect(x: localX, y: localY, width: windowBounds.width, height: windowBounds.height)
            let screenLocalBounds = CGRect(origin: .zero, size: screenFrame.size)
            guard screenLocalBounds.intersects(localRect) else { continue }

            let cropRect = CGRect(
                x: localX * scaleFactor,
                y: localY * scaleFactor,
                width: windowBounds.width * scaleFactor,
                height: windowBounds.height * scaleFactor
            ).integral

            guard let cropped = fullImage.cropping(to: cropRect) else { continue }
            return NSImage(cgImage: cropped, size: windowBounds.size)
        }

        return nil
    }
}
