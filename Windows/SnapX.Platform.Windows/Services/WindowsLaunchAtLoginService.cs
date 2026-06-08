using SnapX.Core.Models;
using Windows.ApplicationModel;

namespace SnapX.Platform.Windows.Services;

public sealed class WindowsLaunchAtLoginService : ILaunchAtLoginService
{
    public bool IsSupported => true;

    public async Task SetEnabledAsync(bool enabled, CancellationToken cancellationToken = default)
    {
        var task = await StartupTask.GetAsync("SnapXStartupTask").AsTask(cancellationToken);
        if (enabled)
        {
            await task.RequestEnableAsync().AsTask(cancellationToken);
        }
        else
        {
            task.Disable();
        }
    }
}
