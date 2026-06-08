using Microsoft.UI.Xaml;
using SnapX.Core.Models;
using SnapX.Core.Services;
using SnapX.Platform.Windows.Services;
using WinRT.Interop;

namespace SnapX.Windows;

public sealed partial class MainWindow : Window
{
    private readonly SettingsStore _settingsStore;
    private readonly WindowsScreenCaptureService _captureService = new();
    private readonly WindowsOcrService _ocrService = new();
    private readonly WindowsClipboardService _clipboardService = new();
    private readonly WindowsLaunchAtLoginService _launchAtLoginService = new();
    private WindowMessageHook? _messageHook;
    private WindowsHotKeyService? _hotKeyService;
    private AppSettings _settings = new();

    public MainWindow()
    {
        InitializeComponent();
        _settingsStore = new SettingsStore(AppPaths.SettingsPath);
        Activated += MainWindow_Activated;
    }

    private async void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= MainWindow_Activated;
        _settings = await _settingsStore.LoadAsync();
        RegisterHotKeys();
        UpdateStatus("Windows 宿主已启动。截图捕获的 Direct3D frame copy 需要在 Windows 开发机上完成。");
    }

    private void RegisterHotKeys()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        _messageHook = new WindowMessageHook(hwnd);
        _hotKeyService = new WindowsHotKeyService(hwnd);
        _messageHook.MessageReceived += (message, wParam, _) => _hotKeyService.TryHandleMessage(message, wParam);
        _hotKeyService.HotKeyPressed += async (_, action) => await HandleHotKeyAsync(action);

        foreach (var pair in _settings.HotKeys)
        {
            _hotKeyService.Register(pair.Key, pair.Value);
        }
    }

    private async Task HandleHotKeyAsync(HotKeyAction action)
    {
        switch (action)
        {
            case HotKeyAction.FramedCapture:
                await StartCaptureAsync(CaptureMode.Framed);
                break;
            case HotKeyAction.FullScreenCapture:
                await StartCaptureAsync(CaptureMode.FullScreen);
                break;
            case HotKeyAction.History:
                ShowHistory();
                break;
        }
    }

    private async Task StartCaptureAsync(CaptureMode mode)
    {
        try
        {
            var image = await _captureService.CaptureAsync(new CaptureRequest(mode));
            await _clipboardService.SetImageAsync(image);
            UpdateStatus($"{mode} 截图已复制到剪贴板。");
        }
        catch (NotImplementedException ex)
        {
            UpdateStatus(ex.Message);
        }
        catch (Exception ex)
        {
            UpdateStatus($"截图失败：{ex.Message}");
        }
    }

    private async void FramedCaptureButton_Click(object sender, RoutedEventArgs e)
    {
        await StartCaptureAsync(CaptureMode.Framed);
    }

    private async void FullScreenCaptureButton_Click(object sender, RoutedEventArgs e)
    {
        await StartCaptureAsync(CaptureMode.FullScreen);
    }

    private void HistoryButton_Click(object sender, RoutedEventArgs e)
    {
        ShowHistory();
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        UpdateStatus("设置面板入口已接入；完整设置 UI 将复用 AppSettings 模型继续展开。");
    }

    private void RestartButton_Click(object sender, RoutedEventArgs e)
    {
        Microsoft.Windows.AppLifecycle.AppInstance.Restart(string.Empty);
    }

    private void ExitButton_Click(object sender, RoutedEventArgs e)
    {
        App.Current.Exit();
    }

    private async void LaunchAtLoginSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        try
        {
            await _launchAtLoginService.SetEnabledAsync(LaunchAtLoginSwitch.IsOn);
        }
        catch (Exception ex)
        {
            UpdateStatus($"开机启动设置失败：{ex.Message}");
        }
    }

    private void ShowHistory()
    {
        UpdateStatus("历史窗口入口已接入；历史数据模型和存储层已在 SnapX.Core 中实现。");
    }

    private void UpdateStatus(string message)
    {
        StatusText.Text = message;
    }
}
