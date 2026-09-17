using BusyLight.Platform.Network;
using Xunit;

namespace BusyLight.Platform.Tests.Network;

public sealed class WledHttpClientOptionsTests
{
    [Fact]
    public void Create_UsesTheSpecificationTimeoutAndDisablesProxy()
    {
        var options = WledHttpClientOptions.Create(TimeSpan.FromMilliseconds(1));

        Assert.Equal(TimeSpan.FromMilliseconds(2500), options.Timeout);
        Assert.False(options.UseProxy);
        Assert.Equal(3, options.MaxAttempts);
    }
}
