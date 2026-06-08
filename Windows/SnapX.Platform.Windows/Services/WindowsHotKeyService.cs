using SnapX.Core.Models;
using SnapX.Platform.Windows.Interop;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsHotKeyService : IHotKeyService
{
    private readonly nint _hwnd;
    private readonly Dictionary<int, HotKeyAction> _actionsById = new();
    private int _nextId = 100;

    public WindowsHotKeyService(nint hwnd)
    {
        _hwnd = hwnd;
    }

    public event EventHandler<HotKeyAction>? HotKeyPressed;

    public void Register(HotKeyAction action, HotKeyDefinition hotKey)
    {
        if (!hotKey.IsValid)
        {
            throw new ArgumentException("Hotkey must include a key and at least one modifier.", nameof(hotKey));
        }

        var id = _nextId++;
        var modifiers = ToNativeModifiers(hotKey.Modifiers);
        var virtualKey = ToVirtualKey(hotKey.Key);

        if (!NativeMethods.RegisterHotKey(_hwnd, id, modifiers, virtualKey))
        {
            throw new InvalidOperationException($"Unable to register hotkey `{hotKey}`.");
        }

        _actionsById[id] = action;
    }

    public void UnregisterAll()
    {
        foreach (var id in _actionsById.Keys.ToArray())
        {
            NativeMethods.UnregisterHotKey(_hwnd, id);
        }
        _actionsById.Clear();
    }

    public bool TryHandleMessage(uint message, nuint wParam)
    {
        if (message != NativeMethods.WM_HOTKEY)
        {
            return false;
        }

        var id = unchecked((int)wParam);
        if (!_actionsById.TryGetValue(id, out var action))
        {
            return false;
        }

        HotKeyPressed?.Invoke(this, action);
        return true;
    }

    public void Dispose()
    {
        UnregisterAll();
    }

    private static uint ToNativeModifiers(HotKeyModifiers modifiers)
    {
        uint value = 0;
        if (modifiers.HasFlag(HotKeyModifiers.Alt)) value |= NativeMethods.MOD_ALT;
        if (modifiers.HasFlag(HotKeyModifiers.Control)) value |= NativeMethods.MOD_CONTROL;
        if (modifiers.HasFlag(HotKeyModifiers.Shift)) value |= NativeMethods.MOD_SHIFT;
        if (modifiers.HasFlag(HotKeyModifiers.Windows)) value |= NativeMethods.MOD_WIN;
        return value;
    }

    private static uint ToVirtualKey(string key)
    {
        if (key.Length != 1)
        {
            throw new ArgumentException("Only single letter and digit hotkeys are supported in the first Windows version.", nameof(key));
        }

        var character = char.ToUpperInvariant(key[0]);
        if (character is >= 'A' and <= 'Z' or >= '0' and <= '9')
        {
            return character;
        }

        throw new ArgumentException($"Unsupported hotkey key `{key}`.", nameof(key));
    }
}
