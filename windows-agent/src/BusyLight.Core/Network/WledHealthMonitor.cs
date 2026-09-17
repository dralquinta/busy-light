namespace BusyLight.Core.Network;

public sealed class WledHealthMonitor(IWledHttpClient transport)
{
    public async Task<IReadOnlyList<WledDevice>> CheckAsync(IEnumerable<WledDevice> devices, CancellationToken cancellationToken = default)
    {
        var list = devices.ToList();
        var checks = list.Select(async device => (device, online: await transport.IsHealthyAsync(device, cancellationToken)));
        return (await Task.WhenAll(checks)).Where(result => result.online).Select(result => result.device).ToArray();
    }
}
