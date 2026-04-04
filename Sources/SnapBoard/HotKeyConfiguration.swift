import Carbon.HIToolbox
import Foundation

enum CaptureShortcutAction: String, CaseIterable, Identifiable {
    case framed
    case display
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .framed:
            "框选截图"
        case .display:
            "全屏截图"
        case .history:
            "截图历史"
        }
    }

    var userDefaultsKey: String {
        "capture_shortcut_\(rawValue)"
    }

    var hotKeyIdentifier: UInt32 {
        switch self {
        case .framed:
            1
        case .display:
            2
        case .history:
            3
        }
    }

    var defaultConfiguration: HotKeyConfiguration {
        switch self {
        case .framed:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
        case .display:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_F), modifiers: [.command, .shift])
        case .history:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_H), modifiers: [.command, .shift])
        }
    }

    var legacyDefaultConfiguration: HotKeyConfiguration {
        switch self {
        case .framed:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_S), modifiers: [.control, .option])
        case .display:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_F), modifiers: [.control, .option])
        case .history:
            HotKeyConfiguration(keyCode: UInt32(kVK_ANSI_H), modifiers: [.control, .option])
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiersRawValue: UInt32

    init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers.rawValue
    }

    var modifiers: HotKeyModifiers {
        HotKeyModifiers(rawValue: modifiersRawValue)
    }

    var displayString: String {
        "\(modifiers.symbolString)\(HotKeyKeyOption.label(for: keyCode))"
    }
}

enum HotKeyConfigurationError: LocalizedError {
    case missingModifiers
    case unsupportedKey
    case duplicateShortcut(actionTitle: String)

    var errorDescription: String? {
        switch self {
        case .missingModifiers:
            "快捷键至少需要选择一个修饰键。"
        case .unsupportedKey:
            "当前按键暂不支持，请改用字母或数字键。"
        case let .duplicateShortcut(actionTitle):
            "这个快捷键已经被“\(actionTitle)”使用了。"
        }
    }
}

struct HotKeyKeyOption: Identifiable, Hashable {
    let keyCode: UInt32
    let label: String

    var id: UInt32 { keyCode }

    static let supportedKeys: [HotKeyKeyOption] = [
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_A), label: "A"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_B), label: "B"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_C), label: "C"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_D), label: "D"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_E), label: "E"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_F), label: "F"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_G), label: "G"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_H), label: "H"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_I), label: "I"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_J), label: "J"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_K), label: "K"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_L), label: "L"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_M), label: "M"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_N), label: "N"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_O), label: "O"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_P), label: "P"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Q), label: "Q"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_R), label: "R"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_S), label: "S"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_T), label: "T"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_U), label: "U"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_V), label: "V"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_W), label: "W"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_X), label: "X"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Y), label: "Y"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Z), label: "Z"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_0), label: "0"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_1), label: "1"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_2), label: "2"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_3), label: "3"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_4), label: "4"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_5), label: "5"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_6), label: "6"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_7), label: "7"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_8), label: "8"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_9), label: "9"),
    ]

    static func label(for keyCode: UInt32) -> String {
        supportedKeys.first(where: { $0.keyCode == keyCode })?.label ?? "?"
    }

    static func isSupported(keyCode: UInt32) -> Bool {
        supportedKeys.contains(where: { $0.keyCode == keyCode })
    }
}

enum ModifierToggle: CaseIterable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: Self { self }

    var title: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        }
    }

    var symbol: String {
        switch self {
        case .control:
            "⌃"
        case .option:
            "⌥"
        case .shift:
            "⇧"
        case .command:
            "⌘"
        }
    }

    var modifier: HotKeyModifiers {
        switch self {
        case .control:
            .control
        case .option:
            .option
        case .shift:
            .shift
        case .command:
            .command
        }
    }
}

extension HotKeyModifiers {
    var symbolString: String {
        var symbols = ""
        if contains(.control) { symbols += "⌃" }
        if contains(.option) { symbols += "⌥" }
        if contains(.shift) { symbols += "⇧" }
        if contains(.command) { symbols += "⌘" }
        return symbols
    }
}
