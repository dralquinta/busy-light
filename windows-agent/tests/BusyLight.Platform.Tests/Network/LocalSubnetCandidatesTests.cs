using System.Net;
using BusyLight.Platform.Network;

namespace BusyLight.Platform.Tests.Network;

public sealed class LocalSubnetCandidatesTests
{
    [Fact]
    public void FromAddressReturnsAllOtherHostsInIpv4Slash24()
    {
        var candidates = LocalSubnetCandidates.FromAddress(IPAddress.Parse("192.168.1.10")).ToArray();
        Assert.Equal(253, candidates.Length);
        Assert.DoesNotContain(IPAddress.Parse("192.168.1.10"), candidates);
        Assert.Contains(IPAddress.Parse("192.168.1.1"), candidates);
    }
}
