namespace BusyLight.Core.Network;

public interface IDeviceDiscovery
{
    Task<IReadOnlyList<WledDevice>> DiscoverAsync(CancellationToken cancellationToken = default);
}

public interface IDeviceScanner
{
    Task<IReadOnlyList<WledDevice>> ScanAsync(CancellationToken cancellationToken = default);
}
