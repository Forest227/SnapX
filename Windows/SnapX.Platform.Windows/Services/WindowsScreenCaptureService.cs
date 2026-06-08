using SnapX.Core.Models;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsScreenCaptureService : IScreenCaptureService
{
    public Task<CapturedImage> CaptureAsync(CaptureRequest request, CancellationToken cancellationToken = default)
    {
        throw new NotImplementedException(
            "Windows.Graphics.Capture frame acquisition is wired as the platform boundary; " +
            "the Direct3D frame copy implementation must be completed on a Windows development machine.");
    }
}
