using BusyLight.Core.Network;

namespace BusyLight.Core.Tests;

public sealed class WledClientTests
{
    [Fact]
    public async Task SendAsyncSkipsDeviceWhosePresetWasAlreadySent()
    {
        var transport = new FakeTransport();
        var client = new WledClient(transport);
        var result = await client.SendAsync([new WledDevice("a", "1.1.1.1"), new WledDevice("b", "1.1.1.2", LastPresetSent: 3)], "busy", 3);

        Assert.Equal(1, transport.SendCount);
        Assert.Equal(1, result.DeliveredCount);
        Assert.Equal(2, result.TotalCount);
    }

    [Fact]
    public async Task HealthMonitorReturnsOnlyOnlineDevices()
    {
        var transport = new FakeTransport { HealthyMac = "a" };
        var online = await new WledHealthMonitor(transport).CheckAsync([new WledDevice("a", "1.1.1.1"), new WledDevice("b", "1.1.1.2")]);
        Assert.Single(online);
        Assert.Equal("a", online[0].Mac);
    }

    private sealed class FakeTransport : IWledHttpClient
    {
        public string? HealthyMac { get; init; }
        public int SendCount { get; private set; }
        public Task<bool> SendStateAsync(WledDevice device, WledStateRequest request, CancellationToken cancellationToken = default) { SendCount++; return Task.FromResult(true); }
        public Task<bool> IsHealthyAsync(WledDevice device, CancellationToken cancellationToken = default) => Task.FromResult(HealthyMac is null || device.Mac == HealthyMac);
    }
}
