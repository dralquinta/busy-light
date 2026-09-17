using BusyLight.Core.Network;

namespace BusyLight.Core.Tests;

public sealed class NetworkAddressValidatorTests
{
    [Theory]
    [InlineData("192.168.0.1", true)]
    [InlineData("256.0.0.1", false)]
    [InlineData("1.2.3", false)]
    public void IsValidIpv4MatchesExpectedAddressRules(string address, bool expected) => Assert.Equal(expected, NetworkAddressValidator.IsValidIpv4(address));
}
