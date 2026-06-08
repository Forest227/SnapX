namespace SnapX.Windows;

public static class AppPaths
{
    public static string Root =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapX");

    public static string SettingsPath => Path.Combine(Root, "settings.json");

    public static string HistoryFolder => Path.Combine(Root, "History");

    public static string HistoryMetadataPath => Path.Combine(HistoryFolder, "history.json");
}
