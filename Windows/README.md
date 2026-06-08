# SnapX Windows

Windows 版本采用 `C# + WinUI 3 + Windows App SDK`，目标发布架构：

- `win-x86`
- `win-x64`
- `win-arm64`

## Projects

| Project | Purpose |
|---|---|
| `SnapX.Core` | Shared Windows business models: hotkeys, settings, annotations, capture requests, history |
| `SnapX.Platform.Windows` | Windows API boundary: hotkeys, OCR, clipboard, launch-at-login, capture service interface |
| `SnapX.Windows` | WinUI 3 packaged desktop host |
| `SnapX.Core.Tests` | Dependency-free console test runner for core behavior |

## Build

Run on Windows with .NET 8 SDK and Windows App SDK support installed:

```powershell
dotnet build Windows/SnapX.Windows.sln -c Release
./Scripts/build_windows.ps1 -Architectures x86,x64,arm64
```

Packages are written to:

```text
Build/Windows/win-x86
Build/Windows/win-x64
Build/Windows/win-arm64
```

## Current Implementation State

Implemented in this pass:

- Windows solution and project structure.
- Core models for capture, hotkeys, annotations, settings, history and file naming.
- Core test runner for default hotkeys, filename collision handling, drag rect normalization and history trimming.
- WinUI 3 packaged app shell.
- Windows hotkey registration boundary using `RegisterHotKey`.
- OCR boundary using `Windows.Media.Ocr`.
- Clipboard boundary using `Windows.ApplicationModel.DataTransfer`.
- Startup task boundary using packaged `StartupTask`.
- x86/x64/arm64 build script.

Still requiring Windows-machine implementation and validation:

- `Windows.Graphics.Capture` Direct3D frame acquisition and PNG encoding.
- Per-monitor overlay windows and window hit-testing polish.
- Full WinUI editor surface and Win2D annotation rendering.
- Shell tray icon via `Shell_NotifyIcon`.
- Pinned image topmost windows with mouse passthrough.
- MSIX signing and install verification on real x86/x64/ARM64 targets.
