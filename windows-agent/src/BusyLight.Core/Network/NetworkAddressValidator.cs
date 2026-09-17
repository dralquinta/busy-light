using System.Globalization;

namespace BusyLight.Core.Network;

public static class NetworkAddressValidator
{
    public static bool IsValidIpv4(string? address)
    {
        if (string.IsNullOrWhiteSpace(address)) return false;
        var octets = address.Split('.');
        return octets.Length == 4 && octets.All(octet => octet.Length is >= 1 and <= 3 && octet.All(char.IsAsciiDigit) && byte.TryParse(octet, NumberStyles.None, CultureInfo.InvariantCulture, out _));
    }
}
