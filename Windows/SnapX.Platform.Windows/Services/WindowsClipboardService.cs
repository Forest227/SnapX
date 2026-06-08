using SnapX.Core.Models;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsClipboardService : IClipboardService
{
    public async Task SetImageAsync(CapturedImage image, CancellationToken cancellationToken = default)
    {
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream))
        {
            writer.WriteBytes(image.PngBytes);
            await writer.StoreAsync().AsTask(cancellationToken);
        }

        stream.Seek(0);
        var package = new DataPackage();
        package.SetBitmap(RandomAccessStreamReference.CreateFromStream(stream));
        Clipboard.SetContent(package);
        Clipboard.Flush();
    }

    public Task SetTextAsync(string text, CancellationToken cancellationToken = default)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
        Clipboard.Flush();
        return Task.CompletedTask;
    }
}
