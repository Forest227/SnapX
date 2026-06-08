namespace SnapX.Core.Services;

public static class FileNameGenerator
{
    public static string CreateTimestampedPngName(DateTimeOffset now, string prefix = "SnapX")
    {
        var safePrefix = string.IsNullOrWhiteSpace(prefix) ? "SnapX" : prefix.Trim();
        return $"{safePrefix} {now:yyyy-MM-dd HH.mm.ss}.png";
    }

    public static string CreateAvailablePath(string folder, DateTimeOffset now, Func<string, bool> exists, string prefix = "SnapX")
    {
        var baseName = Path.GetFileNameWithoutExtension(CreateTimestampedPngName(now, prefix));
        var candidate = Path.Combine(folder, $"{baseName}.png");
        var index = 1;

        while (exists(candidate))
        {
            candidate = Path.Combine(folder, $"{baseName} {index}.png");
            index++;
        }

        return candidate;
    }
}
