namespace SnapX.Core.Models;

public enum ThemeMode
{
    System,
    Light,
    Dark,
}

public sealed record AppSettings
{
    public CaptureTiming CaptureTiming { get; init; } = CaptureTiming.FreezeBeforeSelection;

    public ThemeMode Theme { get; init; } = ThemeMode.System;

    public bool LaunchAtLogin { get; init; }

    public double PinnedWindowOpacity { get; init; } = 1.0;

    public bool PinnedWindowMousePassthrough { get; init; }

    public int HistoryLimit { get; init; } = 50;

    public string? DefaultSaveFolder { get; init; }

    public Dictionary<HotKeyAction, HotKeyDefinition> HotKeys { get; init; } =
        DefaultHotKeys.Create().ToDictionary(pair => pair.Key, pair => pair.Value);
}
