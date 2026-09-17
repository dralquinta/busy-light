using BusyLight.Core.Network;
using BusyLight.Platform.Network;
using Xunit;

namespace BusyLight.Platform.Tests.Network;

public sealed class WledProbeTests
{
    [Fact]
    public async Task VerifyAsyncReturnsOnlyHealthyCandidates()
    {
        var online = await new WledProbe(new ProbeTransport()).VerifyAsync([new WledDevice("ok", "1.1.1.1"), new WledDevice("bad", "1.1.1.2")]);
        Assert.Single(online);
        Assert.Equal("ok", online[0].Mac);
    }

    private sealed class ProbeTransport : IWledHttpClient
    {
        public Task<bool> SendStateAsync(WledDevice device, WledStateRequest request, CancellationToken cancellationToken = default) => Task.FromResult(false);
        public Task<bool> IsHealthyAsync(WledDevice device, CancellationToken cancellationToken = default) => Task.FromResult(device.Mac == "ok");
    }
}
