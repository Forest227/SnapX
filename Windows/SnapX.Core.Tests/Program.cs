using SnapX.Core.Models;
using SnapX.Core.Services;

var tests = new (string Name, Action Test)[]
{
    ("Default hotkeys are Windows-friendly", DefaultHotKeysAreWindowsFriendly),
    ("File names avoid collisions", FileNamesAvoidCollisions),
    ("Area rect normalizes drag direction", AreaRectNormalizesDragDirection),
    ("History is trimmed to configured limit", HistoryIsTrimmedToLimit),
};

var failed = 0;
foreach (var (name, test) in tests)
{
    try
    {
        test();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception ex)
    {
        failed++;
        Console.Error.WriteLine($"FAIL {name}: {ex.Message}");
    }
}

return failed == 0 ? 0 : 1;

static void DefaultHotKeysAreWindowsFriendly()
{
    var hotKeys = DefaultHotKeys.Create();
    AssertEqual("Ctrl+Shift+S", hotKeys[HotKeyAction.FramedCapture].ToString());
    AssertEqual("Ctrl+Shift+F", hotKeys[HotKeyAction.FullScreenCapture].ToString());
    AssertEqual("Ctrl+Shift+H", hotKeys[HotKeyAction.History].ToString());
}

static void FileNamesAvoidCollisions()
{
    var now = new DateTimeOffset(2026, 5, 8, 12, 30, 45, TimeSpan.Zero);
    var first = Path.Combine("Downloads", "SnapX 2026-05-08 12.30.45.png");
    var second = Path.Combine("Downloads", "SnapX 2026-05-08 12.30.45 1.png");
    var path = FileNameGenerator.CreateAvailablePath("Downloads", now, candidate => candidate == first);
    AssertEqual(second, path);
}

static void AreaRectNormalizesDragDirection()
{
    var rect = SnapRect.FromPoints(new SnapPoint(20, 30), new SnapPoint(5, 7));
    AssertEqual(new SnapRect(5, 7, 15, 23), rect);
}

static void HistoryIsTrimmedToLimit()
{
    var temp = Path.Combine(Path.GetTempPath(), $"snapx-history-test-{Guid.NewGuid():N}", "history.json");
    var store = new ScreenshotHistoryStore(temp, limit: 2);

    store.AddAsync(new ScreenshotHistoryItem(Guid.NewGuid(), "1.png", DateTimeOffset.UtcNow, new SnapSize(1, 1))).GetAwaiter().GetResult();
    store.AddAsync(new ScreenshotHistoryItem(Guid.NewGuid(), "2.png", DateTimeOffset.UtcNow, new SnapSize(1, 1))).GetAwaiter().GetResult();
    var items = store.AddAsync(new ScreenshotHistoryItem(Guid.NewGuid(), "3.png", DateTimeOffset.UtcNow, new SnapSize(1, 1))).GetAwaiter().GetResult();

    AssertEqual(2, items.Count);
    AssertEqual("3.png", items[0].ImagePath);
}

static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected `{expected}`, got `{actual}`.");
    }
}
