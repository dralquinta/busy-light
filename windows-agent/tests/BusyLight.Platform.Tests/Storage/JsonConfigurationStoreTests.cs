using BusyLight.Core.Models;
using BusyLight.Platform.Storage;
using Xunit;

namespace BusyLight.Platform.Tests.Storage;

public sealed class JsonConfigurationStoreTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));

    [Fact]
    public void SaveThenLoad_PreservesKnownValuesAndWritesSchemaVersion()
    {
        var store = new JsonConfigurationStore(_directory);
        store.Save(new AppConfiguration { DeviceNetworkAddress = "192.168.1.8", WledPresetBusy = 12 });

        var loaded = store.Load();

        Assert.Equal("192.168.1.8", loaded.DeviceNetworkAddress);
        Assert.Equal(12, loaded.WledPresetBusy);
        Assert.Contains("\"schema_version\": 1", File.ReadAllText(Path.Combine(_directory, "config.json")));
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }
}
