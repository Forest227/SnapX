using System.Text.Json;
using System.Text.Json.Serialization;
using SnapX.Core.Models;

namespace SnapX.Core.Services;

public sealed record ScreenshotHistoryItem(
    Guid Id,
    string ImagePath,
    DateTimeOffset CreatedAt,
    SnapSize Size);

public sealed class ScreenshotHistoryStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly string _metadataPath;
    private readonly int _limit;

    public ScreenshotHistoryStore(string metadataPath, int limit = 50)
    {
        _metadataPath = metadataPath;
        _limit = Math.Max(limit, 1);
    }

    public async Task<IReadOnlyList<ScreenshotHistoryItem>> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_metadataPath))
        {
            return Array.Empty<ScreenshotHistoryItem>();
        }

        await using var stream = File.OpenRead(_metadataPath);
        return await JsonSerializer.DeserializeAsync<List<ScreenshotHistoryItem>>(stream, JsonOptions, cancellationToken)
            ?? Array.Empty<ScreenshotHistoryItem>();
    }

    public async Task<IReadOnlyList<ScreenshotHistoryItem>> AddAsync(
        ScreenshotHistoryItem item,
        CancellationToken cancellationToken = default)
    {
        var items = (await LoadAsync(cancellationToken)).ToList();
        items.RemoveAll(existing => existing.Id == item.Id);
        items.Insert(0, item);

        var trimmed = items.Take(_limit).ToList();
        await SaveAsync(trimmed, cancellationToken);
        return trimmed;
    }

    public async Task SaveAsync(IReadOnlyList<ScreenshotHistoryItem> items, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_metadataPath)!);
        await using var stream = File.Create(_metadataPath);
        await JsonSerializer.SerializeAsync(stream, items.Take(_limit).ToList(), JsonOptions, cancellationToken);
    }
}
