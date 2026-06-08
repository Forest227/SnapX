using System.Text.Json.Serialization;

namespace SnapX.Core.Models;

[Flags]
public enum HotKeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Windows = 8,
}

public sealed record HotKeyDefinition(string Key, HotKeyModifiers Modifiers)
{
    public bool IsValid => !string.IsNullOrWhiteSpace(Key) && Modifiers != HotKeyModifiers.None;

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotKeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotKeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotKeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotKeyModifiers.Windows)) parts.Add("Win");
        parts.Add(Key.ToUpperInvariant());
        return string.Join("+", parts);
    }
}

[JsonConverter(typeof(JsonStringEnumConverter<HotKeyAction>))]
public enum HotKeyAction
{
    FramedCapture,
    FullScreenCapture,
    History,
}

public static class DefaultHotKeys
{
    public static IReadOnlyDictionary<HotKeyAction, HotKeyDefinition> Create() =>
        new Dictionary<HotKeyAction, HotKeyDefinition>
        {
            [HotKeyAction.FramedCapture] = new("S", HotKeyModifiers.Control | HotKeyModifiers.Shift),
            [HotKeyAction.FullScreenCapture] = new("F", HotKeyModifiers.Control | HotKeyModifiers.Shift),
            [HotKeyAction.History] = new("H", HotKeyModifiers.Control | HotKeyModifiers.Shift),
        };
}
