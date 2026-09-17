namespace BusyLight.Core.Network;

public sealed class WledClient(IWledHttpClient transport)
{
    public async Task<WledStateSendResult> SendAsync(IEnumerable<WledDevice> devices, string state, int preset, CancellationToken cancellationToken = default)
    {
        var list = devices.ToList();
        var sends = list.Select(async device => device.LastPresetSent == preset ? false : await transport.SendStateAsync(device, WledStateRequest.ForPreset(preset), cancellationToken));
        var delivered = (await Task.WhenAll(sends)).Count(result => result);
        return new WledStateSendResult(state, delivered, list.Count);
    }
}
