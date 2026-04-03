import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                header
                launchAtLoginSection
                shortcutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 430, idealWidth: 430, minHeight: 500, idealHeight: 500)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            appState.refreshLaunchAtLoginState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设置")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("管理开机启动和截图快捷键。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("开机启动", systemImage: "power.circle")
                .font(.system(size: 15, weight: .semibold))

            HStack(alignment: .top, spacing: 16) {
                Text("登录 macOS 时自动启动 SnapBoard")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { appState.isLaunchAtLoginEnabled },
                        set: { appState.setLaunchAtLoginEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if !appState.launchAtLoginStatusMessage.isEmpty {
                Text(appState.launchAtLoginStatusMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("截图快捷键", systemImage: "keyboard")
                .font(.system(size: 15, weight: .semibold))

            Text("支持字母和数字键；至少选择一个修饰键。修改后立即生效。")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HotKeyEditorCard(
                action: .framed,
                currentConfiguration: appState.framedHotKeyConfiguration,
                onSave: { try appState.updateHotKey(for: .framed, configuration: $0) },
                onReset: { try appState.resetHotKey(for: .framed) }
            )

            HotKeyEditorCard(
                action: .display,
                currentConfiguration: appState.displayHotKeyConfiguration,
                onSave: { try appState.updateHotKey(for: .display, configuration: $0) },
                onReset: { try appState.resetHotKey(for: .display) }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HotKeyEditorCard: View {
    let action: CaptureShortcutAction
    let currentConfiguration: HotKeyConfiguration
    let onSave: (HotKeyConfiguration) throws -> Void
    let onReset: () throws -> Void

    @State private var draftKeyCode: UInt32
    @State private var draftModifiersRawValue: UInt32
    @State private var errorMessage = ""

    init(
        action: CaptureShortcutAction,
        currentConfiguration: HotKeyConfiguration,
        onSave: @escaping (HotKeyConfiguration) throws -> Void,
        onReset: @escaping () throws -> Void
    ) {
        self.action = action
        self.currentConfiguration = currentConfiguration
        self.onSave = onSave
        self.onReset = onReset
        _draftKeyCode = State(initialValue: currentConfiguration.keyCode)
        _draftModifiersRawValue = State(initialValue: currentConfiguration.modifiersRawValue)
    }

    private let modifierColumns = [
        GridItem(.flexible(minimum: 150), spacing: 10),
        GridItem(.flexible(minimum: 150), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(currentConfiguration.displayString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 14) {
                Text("主按键")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Picker("主按键", selection: $draftKeyCode) {
                    ForEach(HotKeyKeyOption.supportedKeys) { option in
                        Text(option.label).tag(option.keyCode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("修饰键")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: modifierColumns, alignment: .leading, spacing: 8) {
                    ForEach(ModifierToggle.allCases) { item in
                        Toggle(isOn: modifierBinding(for: item)) {
                            Label(item.title, systemImage: item.systemImage)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("恢复默认") {
                    restoreDefaults()
                }
                .buttonStyle(.bordered)

                Button("应用快捷键") {
                    applyChanges()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: currentConfiguration) { _ in
            draftKeyCode = currentConfiguration.keyCode
            draftModifiersRawValue = currentConfiguration.modifiersRawValue
            errorMessage = ""
        }
    }

    private var draftModifiers: HotKeyModifiers {
        HotKeyModifiers(rawValue: draftModifiersRawValue)
    }

    private func modifierBinding(for item: ModifierToggle) -> Binding<Bool> {
        Binding(
            get: {
                draftModifiers.contains(item.modifier)
            },
            set: { isEnabled in
                var next = draftModifiers
                if isEnabled {
                    next.insert(item.modifier)
                } else {
                    next.remove(item.modifier)
                }
                draftModifiersRawValue = next.rawValue
            }
        )
    }

    private func applyChanges() {
        do {
            try onSave(HotKeyConfiguration(keyCode: draftKeyCode, modifiers: draftModifiers))
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreDefaults() {
        do {
            try onReset()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ModifierToggle {
    var systemImage: String {
        switch self {
        case .control:
            "control"
        case .option:
            "option"
        case .shift:
            "shift"
        case .command:
            "command"
        }
    }
}
