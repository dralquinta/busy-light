using BusyLight.Core.Network;

namespace BusyLight.Core.Tests;

public sealed class DiscoveryOrderTests
{
    [Fact]
    public void SelectCandidatesPrefersConfiguredThenMdnsThenSubnet()
    {
        Assert.Equal(["10.0.0.2"], DiscoveryOrder.SelectCandidates(["10.0.0.2"], ["10.0.0.3"], ["10.0.0.4"]));
        Assert.Equal(["10.0.0.3"], DiscoveryOrder.SelectCandidates([], ["10.0.0.3"], ["10.0.0.4"]));
    }
}
