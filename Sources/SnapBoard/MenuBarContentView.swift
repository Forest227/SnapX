import SwiftUI

@MainActor
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            permissionCard
            pinControls
            actionButtons
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            appState.refreshPermissionStates()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SnapBoard")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("像 Snipaste 一样，抬手就截，复制后可一键钉住。")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: allPermissionsGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(allPermissionsGranted ? .green : .orange)
                Text(allPermissionsGranted ? "权限已就绪" : "权限状态")
                    .font(.system(size: 13, weight: .semibold))
            }

            permissionStatusRow(
                title: "屏幕录制",
                isGranted: appState.permissionStatus == .granted,
                grantedDetail: "截图功能可用",
                missingDetail: "未授权会导致无法截图"
            )

            permissionStatusRow(
                title: "辅助功能",
                isGranted: appState.isAccessibilityPermissionGranted,
                grantedDetail: "Command 全局快捷键可用",
                missingDetail: "未授权时快捷键可能无响应"
            )

            if allPermissionsGranted {
                Text("全局快捷键 \(appState.hotKeySummaryDisplay)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    if appState.permissionStatus == .needsPermission {
                        Button("授权屏幕录制", action: appState.requestScreenCaptureAccess)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }

                    if !appState.isAccessibilityPermissionGranted {
                        Button("授权辅助功能", action: appState.requestAccessibilityAccess)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(
            (allPermissionsGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: appState.startFramedCapture) {
                actionLabel(
                    title: "框选截图",
                    shortcut: appState.framedHotKeyDisplay,
                    systemImage: "camera.viewfinder"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: appState.startDisplayCapture) {
                actionLabel(
                    title: "全屏截图",
                    shortcut: appState.displayHotKeyDisplay,
                    systemImage: "rectangle.inset.filled"
                )
            }
            .buttonStyle(.bordered)

            Button(action: appState.clearPinnedShots) {
                Label("清空所有钉图", systemImage: "rectangle.stack.badge.minus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(appState.pinnedCount == 0)

            Button(action: appState.openSettings) {
                Label("设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)

            Button(action: appState.restart) {
                Label("重启 SnapBoard", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)

            Button(action: appState.quit) {
                Label("退出 SnapBoard", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private var pinControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("钉图透明度", systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(appState.pinOpacity * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Slider(value: pinOpacityBinding, in: 0.25 ... 1)
            }

            Toggle(isOn: mousePassthroughBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("允许钉图鼠标穿透")
                        .font(.system(size: 13, weight: .semibold))
                    Text("开启后可直接点击下层窗口，恢复交互可在菜单栏关闭。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pinOpacityBinding: Binding<Double> {
        Binding(
            get: { appState.pinOpacity },
            set: { newValue in
                appState.updatePinOpacity(newValue)
            }
        )
    }

    private var mousePassthroughBinding: Binding<Bool> {
        Binding(
            get: { appState.isMousePassthroughEnabled },
            set: { newValue in
                appState.setMousePassthroughEnabled(newValue)
            }
        )
    }

    private func actionLabel(title: String, shortcut: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前钉图 \(appState.pinnedCount) 张")
                .font(.system(size: 12.5, weight: .semibold))
            Text("框选截图会先锁定指针所在窗口；单击确认窗口，拖动则切换为区域截图。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private var allPermissionsGranted: Bool {
        appState.permissionStatus == .granted && appState.isAccessibilityPermissionGranted
    }

    private func permissionStatusRow(title: String, isGranted: Bool, grantedDetail: String, missingDetail: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(isGranted ? grantedDetail : missingDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(isGranted ? "已开启" : "未开启")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isGranted ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((isGranted ? Color.green : Color.orange).opacity(0.12), in: Capsule())
        }
    }
}
