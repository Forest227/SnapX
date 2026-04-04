import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SwiftUI

enum ScreenCapturePermissionStatus {
    case granted
    case needsPermission
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var framedHotKeyConfiguration: HotKeyConfiguration
    @Published private(set) var displayHotKeyConfiguration: HotKeyConfiguration
    @Published private(set) var historyHotKeyConfiguration: HotKeyConfiguration
    @Published private(set) var permissionStatus: ScreenCapturePermissionStatus = .needsPermission
    @Published private(set) var isAccessibilityPermissionGranted = false
    @Published private(set) var pinnedCount = 0
    @Published private(set) var pinOpacity = 1.0
    @Published private(set) var isMousePassthroughEnabled = false
    @Published private(set) var isLaunchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusMessage = ""
    @Published var currentTheme: AppTheme {
        didSet {
            ThemeManager.shared.currentTheme = currentTheme
        }
    }

    var dismissStatusPanel: (() -> Void)?

    private let captureCoordinator = CaptureCoordinator()
    private var hotKeyMonitors: [GlobalHotKeyMonitor] = []
    private var settingsWindowController: SettingsWindowController?
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
    private var accessibilityPermissionMonitor: Timer?
    private var isConfigured = false
    private var pendingLaunchScreenCapturePrompt = false

    init() {
        framedHotKeyConfiguration = Self.loadHotKeyConfiguration(for: .framed)
        displayHotKeyConfiguration = Self.loadHotKeyConfiguration(for: .display)
        historyHotKeyConfiguration = Self.loadHotKeyConfiguration(for: .history)
        currentTheme = ThemeManager.shared.currentTheme
    }

    var framedHotKeyDisplay: String {
        framedHotKeyConfiguration.displayString
    }

    var displayHotKeyDisplay: String {
        displayHotKeyConfiguration.displayString
    }

    var historyHotKeyDisplay: String {
        historyHotKeyConfiguration.displayString
    }

    var hotKeySummaryDisplay: String {
        "\(framedHotKeyDisplay) / \(displayHotKeyDisplay)"
    }

    func configureApplication() {
        guard !isConfigured else { return }
        isConfigured = true

        NSApp.setActivationPolicy(.accessory)
        syncCaptureCoordinatorHotKeyHints()
        installApplicationDidBecomeActiveObserver()

        captureCoordinator.onPinnedWindowsChanged = { [weak self] count in
            self?.pinnedCount = count
        }

        refreshPermissionStates()
        refreshLaunchAtLoginState()

        requestMissingPermissionsOnLaunchIfNeeded()
        registerHotKeys()
    }

    func tearDown() {
        hotKeyMonitors.forEach { $0.unregister() }
        hotKeyMonitors.removeAll()

        if let applicationDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(applicationDidBecomeActiveObserver)
            self.applicationDidBecomeActiveObserver = nil
        }

        accessibilityPermissionMonitor?.invalidate()
        accessibilityPermissionMonitor = nil
    }

    func refreshPermissionStatus() {
        permissionStatus = captureCoordinator.hasScreenCapturePermission ? .granted : .needsPermission
    }

    func refreshAccessibilityPermissionStatus() {
        isAccessibilityPermissionGranted = Self.hasAccessibilityPermission(prompt: false)
    }

    func refreshPermissionStates() {
        refreshPermissionStatus()
        refreshAccessibilityPermissionStatus()
    }

    func requestScreenCaptureAccess() {
        dismissStatusPanel?()

        CGRequestScreenCaptureAccess()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if CGPreflightScreenCaptureAccess() {
                self.permissionStatus = .granted
            } else {
                self.presentRestartPrompt()
            }
        }
    }

    private func presentRestartPrompt() {
        let alert = NSAlert()
        alert.messageText = "需要重启 SnapBoard"
        alert.informativeText = "屏幕录制权限已授予，请退出并重新打开 SnapBoard 使权限生效。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    func requestAccessibilityAccess() {
        dismissStatusPanel?()

        if permissionStatus == .needsPermission {
            pendingLaunchScreenCapturePrompt = true
        }

        _ = Self.hasAccessibilityPermission(prompt: true)
        refreshAccessibilityPermissionStatus()

        if pendingLaunchScreenCapturePrompt {
            startMonitoringAccessibilityPermissionIfNeeded()
        }
    }

    func startCapture() {
        startFramedCapture()
    }

    func startFramedCapture() {
        beginCaptureFlow {
            captureCoordinator.beginFramedSelectionMode()
        }
    }

    func startDisplayCapture() {
        beginCaptureFlow {
            captureCoordinator.beginDisplaySelectionMode()
        }
    }

    private func beginCaptureFlow(_ action: () -> Void) {
        dismissStatusPanel?()

        if captureCoordinator.hasScreenCapturePermission || captureCoordinator.requestScreenCapturePermission() {
            permissionStatus = .granted
            action()
            return
        }

        permissionStatus = .needsPermission
    }

    func clearPinnedShots() {
        captureCoordinator.closeAllPinnedWindows()
    }

    func pinImage(_ image: NSImage) {
        captureCoordinator.pinImage(image)
    }

    func updatePinOpacity(_ opacity: Double) {
        let normalizedOpacity = min(max(opacity, 0.25), 1)
        guard abs(pinOpacity - normalizedOpacity) > 0.001 else { return }

        pinOpacity = normalizedOpacity
        captureCoordinator.updatePinnedWindowOpacity(normalizedOpacity)
    }

    func setMousePassthroughEnabled(_ enabled: Bool) {
        guard isMousePassthroughEnabled != enabled else { return }

        isMousePassthroughEnabled = enabled
        captureCoordinator.updatePinnedWindowMousePassthrough(enabled)
    }

    func quit() {
        dismissStatusPanel?()
        NSApp.terminate(nil)
    }

    func openHistory() {
        dismissStatusPanel?()
        HistoryWindowController.present()
    }

    func openSettings() {
        dismissStatusPanel?()
        refreshLaunchAtLoginState()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self)
        }
        settingsWindowController?.present()
    }

    func restart() {
        do {
            dismissStatusPanel?()
            try relaunchApplication()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        } catch {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "无法重启 SnapBoard"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
    }

    func refreshLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else {
            isLaunchAtLoginEnabled = false
            launchAtLoginStatusMessage = "当前系统版本不支持这个设置。"
            return
        }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            isLaunchAtLoginEnabled = true
            launchAtLoginStatusMessage = "已启用开机启动。"

        case .requiresApproval:
            isLaunchAtLoginEnabled = true
            launchAtLoginStatusMessage = "已请求启用，请前往“系统设置 > 通用 > 登录项”批准。"

        case .notRegistered:
            isLaunchAtLoginEnabled = false
            launchAtLoginStatusMessage = "未启用开机启动。"

        case .notFound:
            isLaunchAtLoginEnabled = false
            launchAtLoginStatusMessage = "当前运行环境不支持开机启动，请使用打包后的 .app。"

        @unknown default:
            isLaunchAtLoginEnabled = false
            launchAtLoginStatusMessage = "无法确认开机启动状态。"
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            refreshLaunchAtLoginState()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            presentAlert(
                title: enabled ? "无法启用开机启动" : "无法关闭开机启动",
                message: error.localizedDescription
            )
        }

        refreshLaunchAtLoginState()
    }

    func updateHotKey(for action: CaptureShortcutAction, configuration: HotKeyConfiguration) throws {
        guard !configuration.modifiers.isEmpty else {
            throw HotKeyConfigurationError.missingModifiers
        }

        guard HotKeyKeyOption.isSupported(keyCode: configuration.keyCode) else {
            throw HotKeyConfigurationError.unsupportedKey
        }

        let otherAction = CaptureShortcutAction.allCases.first { $0 != action && hotKeyConfiguration(for: $0) == configuration }
        if let otherAction {
            throw HotKeyConfigurationError.duplicateShortcut(actionTitle: otherAction.title)
        }

        setHotKeyConfiguration(configuration, for: action)
        saveHotKeyConfiguration(configuration, for: action)
        registerHotKeys()
    }

    func resetHotKey(for action: CaptureShortcutAction) throws {
        try updateHotKey(for: action, configuration: action.defaultConfiguration)
    }

    func hotKeyConfiguration(for action: CaptureShortcutAction) -> HotKeyConfiguration {
        switch action {
        case .framed:
            framedHotKeyConfiguration
        case .display:
            displayHotKeyConfiguration
        case .history:
            historyHotKeyConfiguration
        }
    }

    private func registerHotKeys() {
        hotKeyMonitors.forEach { $0.unregister() }
        hotKeyMonitors.removeAll()
        syncCaptureCoordinatorHotKeyHints()

        var requiresAccessibilityPermission = false
        var registrationFailureStatus: OSStatus?

        let definitions: [(CaptureShortcutAction, HotKeyConfiguration, @MainActor () -> Void)] = [
            (.framed, framedHotKeyConfiguration, startFramedCapture),
            (.display, displayHotKeyConfiguration, startDisplayCapture),
            (.history, historyHotKeyConfiguration, openHistory),
        ]

        hotKeyMonitors = definitions.map { shortcutAction, configuration, action in
            let monitor = GlobalHotKeyMonitor(
                identifier: shortcutAction.hotKeyIdentifier,
                keyCode: configuration.keyCode,
                modifiers: configuration.modifiers
            ) {
                Task { @MainActor in
                    action()
                }
            }
            switch monitor.register() {
            case .registered:
                break

            case .requiresAccessibilityPermission:
                requiresAccessibilityPermission = true

            case let .failed(status):
                registrationFailureStatus = status
            }
            return monitor
        }

        if let registrationFailureStatus {
            presentAlert(
                title: "无法注册全局快捷键",
                message: "系统未能完成快捷键注册，错误代码：\(registrationFailureStatus)。"
            )
        } else if requiresAccessibilityPermission {
            refreshAccessibilityPermissionStatus()
        }
    }

    private func setHotKeyConfiguration(_ configuration: HotKeyConfiguration, for action: CaptureShortcutAction) {
        switch action {
        case .framed:
            framedHotKeyConfiguration = configuration
        case .display:
            displayHotKeyConfiguration = configuration
        case .history:
            historyHotKeyConfiguration = configuration
        }
    }

    private func saveHotKeyConfiguration(_ configuration: HotKeyConfiguration, for action: CaptureShortcutAction) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: action.userDefaultsKey)
    }

    private func syncCaptureCoordinatorHotKeyHints() {
        captureCoordinator.updateHotKeyHints(
            framed: framedHotKeyDisplay,
            display: displayHotKeyDisplay
        )
    }

    private func installApplicationDidBecomeActiveObserver() {
        guard applicationDidBecomeActiveObserver == nil else { return }

        applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePendingLaunchScreenCapturePromptIfNeeded()
            }
        }
    }

    private func requestMissingPermissionsOnLaunchIfNeeded() {
        let needsScreenCapture = !captureCoordinator.hasScreenCapturePermission
        let needsAccessibility = !Self.hasAccessibilityPermission(prompt: false)

        guard needsScreenCapture || needsAccessibility else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.requestLaunchPermissions(
                needsScreenCapture: needsScreenCapture,
                needsAccessibility: needsAccessibility
            )
        }
    }

    private func requestLaunchPermissions(needsScreenCapture: Bool, needsAccessibility: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        if needsAccessibility {
            pendingLaunchScreenCapturePrompt = needsScreenCapture
            requestAccessibilityAccess()
            return
        }

        if needsScreenCapture {
            let isGranted = captureCoordinator.requestScreenCapturePermission()
            permissionStatus = isGranted ? .granted : .needsPermission
        }
    }

    private func handlePendingLaunchScreenCapturePromptIfNeeded() {
        guard pendingLaunchScreenCapturePrompt else { return }

        refreshAccessibilityPermissionStatus()
        guard isAccessibilityPermissionGranted else { return }

        accessibilityPermissionMonitor?.invalidate()
        accessibilityPermissionMonitor = nil
        pendingLaunchScreenCapturePrompt = false
        guard !captureCoordinator.hasScreenCapturePermission else {
            refreshPermissionStatus()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let isGranted = captureCoordinator.requestScreenCapturePermission()
        permissionStatus = isGranted ? .granted : .needsPermission
    }

    private func startMonitoringAccessibilityPermissionIfNeeded() {
        guard accessibilityPermissionMonitor == nil else { return }

        accessibilityPermissionMonitor = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }

                guard self.pendingLaunchScreenCapturePrompt else {
                    self.accessibilityPermissionMonitor?.invalidate()
                    self.accessibilityPermissionMonitor = nil
                    return
                }

                self.handlePendingLaunchScreenCapturePromptIfNeeded()
                if !self.pendingLaunchScreenCapturePrompt {
                    self.accessibilityPermissionMonitor?.invalidate()
                    self.accessibilityPermissionMonitor = nil
                }
            }
        }
    }

    private static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func loadHotKeyConfiguration(for action: CaptureShortcutAction) -> HotKeyConfiguration {
        let decoder = JSONDecoder()
        guard let data = UserDefaults.standard.data(forKey: action.userDefaultsKey),
              let configuration = try? decoder.decode(HotKeyConfiguration.self, from: data),
              HotKeyKeyOption.isSupported(keyCode: configuration.keyCode),
              !configuration.modifiers.isEmpty else {
            return action.defaultConfiguration
        }

        if configuration == action.legacyDefaultConfiguration {
            let migratedConfiguration = action.defaultConfiguration
            let encoder = JSONEncoder()
            if let migratedData = try? encoder.encode(migratedConfiguration) {
                UserDefaults.standard.set(migratedData, forKey: action.userDefaultsKey)
            }
            return migratedConfiguration
        }

        return configuration
    }

    private func relaunchApplication() throws {
        if let bundleURL = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try process.run()
            return
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let process = Process()
        process.executableURL = executableURL
        process.arguments = Array(CommandLine.arguments.dropFirst())

        let currentDirectory = FileManager.default.currentDirectoryPath
        if !currentDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }

        try process.run()
    }

    private func presentAlert(title: String, message: String) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}
