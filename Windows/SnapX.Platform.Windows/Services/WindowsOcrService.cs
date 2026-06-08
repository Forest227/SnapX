using SnapX.Core.Models;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsOcrService : IOcrService
{
    public async Task<string> RecognizeTextAsync(CapturedImage image, CancellationToken cancellationToken = default)
    {
        if (image.IsEmpty)
        {
            return string.Empty;
        }

        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream))
        {
            writer.WriteBytes(image.PngBytes);
            await writer.StoreAsync().AsTask(cancellationToken);
        }

        stream.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellationToken);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied).AsTask(cancellationToken);

        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
            ?? OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-US"));

        if (engine is null)
        {
            return string.Empty;
        }

        var result = await engine.RecognizeAsync(bitmap).AsTask(cancellationToken);
        return string.Join(Environment.NewLine, result.Lines.Select(line => line.Text));
    }
}
