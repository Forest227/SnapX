# SnapX Windows 迁移路线

这份文档记录 SnapX 从当前的 macOS 原生实现，迁移到 Windows `x86 / x64 / ARM64` 的落地路线。

## 当前结论

当前仓库是 **macOS-only** 实现，不是“轻微调整后即可多平台编译”的状态。

主要原因：

- UI 完全基于 `AppKit + SwiftUI(macOS host)`。
- 全局快捷键依赖 `Carbon.HIToolbox`。
- 截屏依赖 `CGWindowList / CGDisplay / 屏幕录制权限`。
- OCR 依赖 `Vision`。
- 开机启动依赖 `ServiceManagement.SMAppService`。
- 钉图、遮罩、历史窗口都依赖 macOS 的窗口层级和事件模型。

也就是说，Windows 适配不是改几行条件编译，而是要把“产品逻辑”和“平台宿主”分开。

## 第一阶段已经做了什么

- 增加了 [`Sources/SnapX/PlatformContracts.swift`](../Sources/SnapX/PlatformContracts.swift)，把跨平台会用到的核心能力先抽成协议：
  - `PlatformScreenCaptureBackend`
  - `PlatformPermissionBackend`
  - `PlatformHotKeyBackend`
  - `PlatformOCRBackend`
  - `PlatformLaunchAtLoginBackend`
  - `PlatformPinnedWindowBackend`
- 增加了 [`Scripts/audit_platform_dependencies.py`](../Scripts/audit_platform_dependencies.py)，用来持续审计哪些文件仍然强绑定 macOS。
- 增加了 [`Windows/`](../Windows/) Windows 工程骨架，包含 WinUI 3 宿主、核心模型库、Windows 平台层、核心测试入口和三架构构建脚本。

这一步的目的不是直接产出 Windows 版本，而是先把后续改造的边界固定住。

## 推荐技术路线

### 1. 保留 macOS 宿主

现有 macOS 版本继续用 Swift + AppKit/SwiftUI，不强行回退。

### 2. Windows 单独做宿主层

Windows 版本建议使用 **C# + WinUI 3 + Windows App SDK** 作为原生桌面宿主。

原因：

- WinUI 3 官方定位就是现代原生 Windows 桌面 UI。
- Windows App SDK 可用于桌面应用，并覆盖 x86 / x64 / ARM64 分发。
- Windows 原生截图、热键、窗口、权限和 OCR API 更容易直接接入。

### 3. 共享“产品核心”，不要共享“窗口壳”

真正值得共享的是这些内容：

- 截图模式定义
- 快捷键配置模型
- 标注数据结构
- 历史记录模型
- 文件命名规则
- OCR 结果流转
- 设置项 schema

不建议强行共享这些内容：

- 菜单栏/托盘 UI
- 选区遮罩窗口
- 钉图窗口
- 平台权限引导
- 全局热键注册实现

## Windows 侧能力映射

| 现有能力 | macOS 实现 | Windows 对应方向 |
|---|---|---|
| 全局快捷键 | Carbon | Win32 `RegisterHotKey` |
| 屏幕/窗口截图 | CoreGraphics | `Windows.Graphics.Capture` |
| OCR | Vision | `Windows.Media.Ocr` |
| 置顶钉图 | NSWindow floating | WinUI/Win32 topmost window |
| 开机启动 | SMAppService | Windows Startup Task / registry / packaged startup |
| 状态栏入口 | NSStatusBar | Taskbar tray icon |

## 建议实施顺序

### Phase 1

目标：把现有 macOS 工程中的共享模型继续抽离。

优先拆出：

- 快捷键 schema
- 截图模式与动作枚举
- 标注数据模型
- OCR 结果模型
- 历史记录元数据

### Phase 2

目标：做 Windows 宿主工程骨架。

建议先完成：

- 托盘图标
- 全局快捷键
- 空白遮罩窗口
- 设置面板

### Phase 3

目标：实现截图主流程。

顺序建议：

- 全屏截图
- 区域截图
- 窗口截图
- 结果复制/保存

### Phase 4

目标：补高级体验。

- OCR
- 钉图
- 历史记录
- 开机启动
- 动画与主题

## 分发建议

如果用户明确需要 `x86 + ARM`，建议同时把 `x64` 也纳入发布矩阵，因为 Windows 桌面主流仍会用到 `x64` 包。

建议最终发布矩阵：

- Windows x86
- Windows x64
- Windows ARM64
- macOS arm64

## 下一步最值得做的事

如果继续推进，下一步应该不是直接写 Windows UI，而是先把以下几份文件从 macOS 宿主里拆成共享核心：

- `HotKeyConfiguration.swift`
- `ScreenshotHistory.swift`
- `CaptureCoordinator.swift` 里与平台无关的动作枚举和流程状态
- `ScreenshotEditorWindowController.swift` 里与平台无关的标注模型

这样等 Windows 宿主接进来时，我们可以直接复用“产品数据”和“编辑结果”，不用把所有逻辑再写一遍。
