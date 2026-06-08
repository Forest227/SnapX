namespace SnapX.Core.Models;

public interface IScreenCaptureService
{
    Task<CapturedImage> CaptureAsync(CaptureRequest request, CancellationToken cancellationToken = default);
}

public interface IHotKeyService : IDisposable
{
    event EventHandler<HotKeyAction>? HotKeyPressed;

    void Register(HotKeyAction action, HotKeyDefinition hotKey);

    void UnregisterAll();
}

public interface IOcrService
{
    Task<string> RecognizeTextAsync(CapturedImage image, CancellationToken cancellationToken = default);
}

public interface IClipboardService
{
    Task SetImageAsync(CapturedImage image, CancellationToken cancellationToken = default);

    Task SetTextAsync(string text, CancellationToken cancellationToken = default);
}

public interface IPinnedWindowService
{
    void Pin(CapturedImage image);

    void CloseAll();
}

public interface ILaunchAtLoginService
{
    bool IsSupported { get; }

    Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken = default);
}
