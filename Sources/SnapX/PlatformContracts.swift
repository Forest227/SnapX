import Foundation

enum PortablePlatformFamily: String, CaseIterable, Codable, Hashable {
    case macOS
    case windows
}

enum PortableArchitecture: String, CaseIterable, Codable, Hashable {
    case x86
    case x64
    case arm64
}

struct SupportedDistributionTarget: Identifiable, Codable, Hashable {
    let platform: PortablePlatformFamily
    let architecture: PortableArchitecture

    var id: String {
        "\(platform.rawValue)-\(architecture.rawValue)"
    }
}

enum PortableCaptureMode: String, Codable, Hashable {
    case framed
    case fullscreen
    case window
}

struct PortablePoint: Codable, Hashable {
    let x: Double
    let y: Double
}

struct PortableSize: Codable, Hashable {
    let width: Double
    let height: Double
}

struct PortableRect: Codable, Hashable {
    let origin: PortablePoint
    let size: PortableSize
}

struct PortableImagePayload: Codable, Hashable {
    let pngData: Data
    let size: PortableSize
}

enum PortablePermissionKind: String, Codable, CaseIterable, Hashable {
    case screenCapture
    case accessibility
}

enum PortablePermissionStatus: String, Codable, Hashable {
    case granted
    case denied
    case requiresPrompt
    case unsupported
}

enum PortableHotKeyModifier: String, Codable, CaseIterable, Hashable {
    case command
    case control
    case option
    case shift
    case windows
}

struct PortableHotKey: Codable, Hashable {
    let key: String
    let modifiers: Set<PortableHotKeyModifier>
}

protocol PlatformScreenCaptureBackend {
    func capture(mode: PortableCaptureMode, rect: PortableRect?) async throws -> PortableImagePayload
}

protocol PlatformPermissionBackend {
    func status(for permission: PortablePermissionKind) -> PortablePermissionStatus
    func request(_ permission: PortablePermissionKind) async -> PortablePermissionStatus
}

protocol PlatformHotKeyBackend {
    func register(identifier: String, hotKey: PortableHotKey) throws
    func unregisterAll()
}

protocol PlatformOCRBackend {
    func recognizeText(from image: PortableImagePayload) async throws -> String
}

protocol PlatformLaunchAtLoginBackend {
    var isSupported: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

protocol PlatformPinnedWindowBackend {
    func pin(image: PortableImagePayload) throws
    func closeAll()
}

enum PortabilitySupportMatrix {
    static let plannedTargets: [SupportedDistributionTarget] = [
        SupportedDistributionTarget(platform: .macOS, architecture: .arm64),
        SupportedDistributionTarget(platform: .windows, architecture: .x64),
        SupportedDistributionTarget(platform: .windows, architecture: .arm64),
        SupportedDistributionTarget(platform: .windows, architecture: .x86),
    ]
}
