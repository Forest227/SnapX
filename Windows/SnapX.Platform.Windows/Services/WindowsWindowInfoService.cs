using System.Runtime.InteropServices;
using SnapX.Core.Models;
using SnapX.Platform.Windows.Interop;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsWindowInfoService
{
    public nint GetRootWindowAt(int x, int y)
    {
        var hwnd = NativeMethods.WindowFromPoint(new NativeMethods.POINT(x, y));
        return hwnd == 0 ? 0 : NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT);
    }

    public SnapRect? TryGetExtendedFrameBounds(nint hwnd)
    {
        if (hwnd == 0)
        {
            return null;
        }

        var hr = NativeMethods.DwmGetWindowAttribute(
            hwnd,
            NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS,
            out var rect,
            Marshal.SizeOf<NativeMethods.RECT>());

        if (hr != 0)
        {
            return null;
        }

        return new SnapRect(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top);
    }
}
