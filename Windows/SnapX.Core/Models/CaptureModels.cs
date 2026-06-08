namespace SnapX.Core.Models;

public enum CaptureMode
{
    Framed,
    FullScreen,
    Window,
}

public enum CaptureTiming
{
    FreezeBeforeSelection,
    CaptureAfterSelection,
}

public sealed record CaptureRequest(
    CaptureMode Mode,
    SnapRect? Region = null,
    nint WindowHandle = 0,
    string? DisplayId = null);

public sealed record CapturedImage(byte[] PngBytes, SnapSize Size)
{
    public bool IsEmpty => PngBytes.Length == 0 || Size.IsEmpty;
}
