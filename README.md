# SnapBoard

macOS 原生截图工具，体验接近 Snipaste。截完图直接在原位编辑，支持标注、钉图、OCR 文字提取。

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/github/license/Forest227/SnapBoard)
![Release](https://img.shields.io/github/v/release/Forest227/SnapBoard)

## 功能一览

### 截图

| 模式 | 说明 |
|------|------|
| 框选截图 | 自动高亮指针所在窗口，单击确认窗口或拖动自由框选 |
| 全屏截图 | 移动鼠标到目标屏幕，单击即可截取整个显示器 |

两种截图时机可选：

- **先冻结** — 触发截图时立即冻结屏幕，在静止画面上框选和编辑
- **先选择** — 在实时画面上框选，确认后才捕获对应区域

### 标注编辑

截图后原位弹出编辑菜单，支持 7 种标注工具（键盘 1-7 快速切换）：

| 快捷键 | 工具 |
|--------|------|
| `1` | 矩形 |
| `2` | 高亮 |
| `3` | 文字 |
| `4` | 箭头 |
| `5` | 直线 |
| `6` | 画笔 |
| `7` | 马赛克 |

编辑完成后可：

- **复制到剪贴板** — 完成编辑按 Enter 或点击复制按钮
- **保存到下载文件夹** — 自动以时间戳命名
- **提取文字** — 基于 Apple Vision 的 OCR，支持中英文
- **钉住图片** — 创建浮动置顶窗口

### 截图历史

- 保留最近 50 张截图，支持缩放预览
- 多选模式：按住 ⌘ 多选，支持批量复制
- 右键菜单：快速复制、钉住或删除

### 钉图管理

- 透明度调节（25%–100%）
- 鼠标穿透开关
- 一键关闭所有钉图

### 其他

- **全局快捷键** — 完全可自定义，支持字母和数字键
- **主题切换** — 跟随系统 / 浅色 / 深色
- **开机启动** — 设置中一键开启
- **闪退日志** — 自动捕获崩溃信息，下次启动时提示保存到下载文件夹

## 默认快捷键

| 操作 | 快捷键 |
|------|--------|
| 框选截图 | `⌘⇧S` |
| 全屏截图 | `⌘⇧F` |
| 截图历史 | `⌘⇧H` |

所有快捷键均可在设置中修改。

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- 需要授权：**屏幕录制**权限

## 安装

### 直接下载

前往 [Releases](https://github.com/Forest227/SnapBoard/releases/latest) 下载 `SnapBoard-vX.X.X.dmg`，挂载后将 SnapBoard.app 拖入应用程序文件夹。

### 从源码构建

```bash
git clone https://github.com/Forest227/SnapBoard.git
cd SnapBoard

# 直接运行
swift run

# 打包 .app（输出到 Build/SnapBoard.app）
./Scripts/build_app.sh
```

需要 Swift 6.2+ 工具链。

## 项目结构

```
Sources/SnapBoard/
├── SnapBoardApp.swift              # 应用入口
├── AppDelegate.swift               # 应用生命周期
├── AppState.swift                  # 全局状态、权限、快捷键管理
├── CaptureCoordinator.swift        # 截图流程编排
├── SelectionOverlay.swift          # 框选 / 全屏选择遮罩
├── ScreenshotEditorWindowController.swift  # 标注编辑器、OCR
├── PinnedScreenshotWindowController.swift  # 浮动钉图窗口
├── ScreenshotHistory.swift         # 截图历史模型
├── HistoryWindowController.swift   # 截图历史面板
├── HotKeyConfiguration.swift       # 快捷键配置
├── HotKeyMonitor.swift             # Carbon 全局热键监听
├── StatusBarController.swift       # 菜单栏图标
├── MenuBarContentView.swift        # 菜单栏面板
├── SettingsView.swift              # 设置面板
├── SettingsWindowController.swift  # 设置窗口
├── ThemeManager.swift              # 主题管理
└── CrashReporter.swift             # 崩溃日志捕获
```

零外部依赖，仅使用 Apple 原生框架（AppKit、CoreGraphics、Vision、Carbon）。

## 许可

[MIT](LICENSE)
