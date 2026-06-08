using SnapX.Platform.Windows.Interop;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowMessageHook : IDisposable
{
    private readonly nint _hwnd;
    private readonly NativeMethods.WndProc _wndProc;
    private readonly nint _previousWndProc;
    private bool _disposed;

    public WindowMessageHook(nint hwnd)
    {
        _hwnd = hwnd;
        _wndProc = HandleWindowMessage;
        _previousWndProc = NativeMethods.SetWindowLongPtrW(hwnd, -4, _wndProc);
    }

    public event Func<uint, nuint, nint, bool>? MessageReceived;

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        NativeMethods.SetWindowLongPtr(_hwnd, -4, _previousWndProc);
        _disposed = true;
    }

    private nint HandleWindowMessage(nint hWnd, uint msg, nuint wParam, nint lParam)
    {
        if (MessageReceived?.Invoke(msg, wParam, lParam) == true)
        {
            return 0;
        }

        return NativeMethods.CallWindowProc(_previousWndProc, hWnd, msg, wParam, lParam);
    }
}
