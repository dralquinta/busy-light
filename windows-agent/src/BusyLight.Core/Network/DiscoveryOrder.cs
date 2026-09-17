namespace BusyLight.Core.Network;

public static class DiscoveryOrder
{
    public static IReadOnlyList<string> SelectCandidates(IEnumerable<string> configured, IEnumerable<string> mdns, IEnumerable<string> subnet)
    {
        var first = configured.Where(NetworkAddressValidator.IsValidIpv4).Distinct().ToArray();
        if (first.Length > 0) return first;
        var second = mdns.Where(NetworkAddressValidator.IsValidIpv4).Distinct().ToArray();
        return second.Length > 0 ? second : subnet.Where(NetworkAddressValidator.IsValidIpv4).Distinct().ToArray();
    }
}
