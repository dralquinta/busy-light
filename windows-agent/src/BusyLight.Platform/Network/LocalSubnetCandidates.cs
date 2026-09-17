using System.Net;

namespace BusyLight.Platform.Network;

public static class LocalSubnetCandidates
{
    public static IEnumerable<IPAddress> FromAddress(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        if (bytes.Length != 4) return [];
        return Enumerable.Range(1, 254)
            .Select(last => new IPAddress([bytes[0], bytes[1], bytes[2], (byte)last]))
            .Where(candidate => !candidate.Equals(address));
    }
}
