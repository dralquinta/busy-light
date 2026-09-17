using BusyLight.Core.Models;

namespace BusyLight.Core.Tests;

public sealed class ConfigurationTests
{
    [Fact]
    public void DefaultConfiguration_UsesParityDefaultsAndPinsPort()
    {
        var configuration = new AppConfiguration();
        Assert.Equal(80, configuration.DeviceNetworkPort);
        Assert.Equal(2500, configuration.NormalizedWledHttpTimeout);
        Assert.Equal(1, configuration.PresetFor(PresenceState.Available));
        Assert.Equal(6, configuration.PresetFor(PresenceState.Off));
    }

    [Fact]
    public void HttpTimeout_IsNeverBelow2500Milliseconds()
    {
        Assert.Equal(2500, new AppConfiguration { WledHttpTimeout = 1 }.NormalizedWledHttpTimeout);
    }
}
