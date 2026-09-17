using BusyLight.Core.Network;

namespace BusyLight.Platform.Network;

public sealed class WledProbe(IWledHttpClient client)
{
    public async Task<IReadOnlyList<WledDevice>> VerifyAsync(IEnumerable<WledDevice> candidates, CancellationToken cancellationToken = default)
    {
        var checks = candidates.Select(async device => (device, valid: await client.IsHealthyAsync(device, cancellationToken)));
        return (await Task.WhenAll(checks)).Where(result => result.valid).Select(result => result.device).ToArray();
    }
}
