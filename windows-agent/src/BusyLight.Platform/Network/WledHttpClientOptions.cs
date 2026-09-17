namespace BusyLight.Platform.Network;

/// <summary>
/// Transport settings shared by all WLED HTTP requests.
/// </summary>
public sealed record WledHttpClientOptions(
    TimeSpan Timeout,
    bool UseProxy,
    int MaxAttempts)
{
    public static readonly TimeSpan MinimumTimeout = TimeSpan.FromMilliseconds(2500);

    public static WledHttpClientOptions Create(TimeSpan configuredTimeout)
    {
        var timeout = configuredTimeout < MinimumTimeout
            ? MinimumTimeout
            : configuredTimeout;

        return new WledHttpClientOptions(timeout, UseProxy: false, MaxAttempts: 3);
    }
}
