# SnapBoard

一个用 SwiftUI + AppKit 写的 macOS 截图工具原型，目标体验接近 Snipaste：

- 框选截图
- 全屏截图
- 截图后进入浮动编辑菜单
  - 颜色线框标记
  - 添加文字
  - 指示箭头
  - 马赛克涂抹
  - 提取文字
  - 保存到下载文件夹
  - 钉住图片
  - 完成后复制到剪贴板
- 钉图透明度调节与鼠标穿透
- 设置面板（开机启动、截图快捷键）
- 菜单栏常驻入口
- 全局快捷键
  - 框选截图：`Command + Shift + S`
  - 全屏截图：`Command + Shift + F`

## 运行

```bash
swift run
```

首次截图时，macOS 会要求授予「屏幕录制」权限。
首次运行时，SnapBoard 会直接触发系统的「屏幕录制」和「辅助功能」权限请求。

## 打包 App

```bash
./Scripts/build_app.sh
```

打包完成后，成品会输出到 `Build/SnapBoard.app`。

## 当前架构

- `AppState`：应用状态、权限、登录项和快捷键入口
- `CaptureCoordinator`：截图流程编排、编辑窗口与钉图窗口管理
- `SelectionOverlay`：框选 / 全屏选择遮罩和交互反馈
- `ScreenshotEditorWindowController`：截图编辑浮层、标注与系统动作
- `PinnedScreenshotWindowController`：浮动钉图窗口
- `MenuBarContentView`：菜单栏窗口内容
- `SettingsView`：设置面板 UI

## 下一步建议

- 增加撤销历史与更多标注样式
- 支持开机自启与快捷键自定义
