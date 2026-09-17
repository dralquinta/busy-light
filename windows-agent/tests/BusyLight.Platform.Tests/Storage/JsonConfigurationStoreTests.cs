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

    [Fact]
    public void SaveThenLoad_PreservesAllDocumentedConfigurationValues()
    {
        var store = new JsonConfigurationStore(_directory);
        var expected = new AppConfiguration
        {
            DeviceNetworkAddress = "192.168.1.15",
            DeviceNetworkAddresses = ["192.168.1.15", "192.168.1.16"],
            WledPresetAvailable = 11,
            WledPresetTentative = 12,
            WledPresetBusy = 13,
            WledPresetAway = 14,
            WledPresetUnknown = 15,
            WledPresetOff = 16,
            WledHttpTimeout = 4000,
            WledHealthCheckInterval = 20,
            WledEnableDiscovery = false,
            LaunchOnStartup = true,
            ManualOverrideTimeoutMinutes = 60,
            StateStabilizationSeconds = 5,
            MeetingDetectionEnabled = false,
            MeetingConfidenceThreshold = 2,
            MeetingPollIntervalSeconds = 2.5,
            OfficeHours = new OfficeHoursConfiguration(true, 600, 1080, new HashSet<int> { 2, 3 }),
        };

        store.Save(expected);

        var actual = store.Load();

        Assert.Equal(expected.DeviceNetworkAddress, actual.DeviceNetworkAddress);
        Assert.Equal(expected.DeviceNetworkAddresses, actual.DeviceNetworkAddresses);
        Assert.Equal(expected.WledPresetAvailable, actual.WledPresetAvailable);
        Assert.Equal(expected.WledPresetTentative, actual.WledPresetTentative);
        Assert.Equal(expected.WledPresetBusy, actual.WledPresetBusy);
        Assert.Equal(expected.WledPresetAway, actual.WledPresetAway);
        Assert.Equal(expected.WledPresetUnknown, actual.WledPresetUnknown);
        Assert.Equal(expected.WledPresetOff, actual.WledPresetOff);
        Assert.Equal(expected.WledHttpTimeout, actual.WledHttpTimeout);
        Assert.Equal(expected.WledHealthCheckInterval, actual.WledHealthCheckInterval);
        Assert.Equal(expected.WledEnableDiscovery, actual.WledEnableDiscovery);
        Assert.Equal(expected.LaunchOnStartup, actual.LaunchOnStartup);
        Assert.Equal(expected.ManualOverrideTimeoutMinutes, actual.ManualOverrideTimeoutMinutes);
        Assert.Equal(expected.StateStabilizationSeconds, actual.StateStabilizationSeconds);
        Assert.Equal(expected.MeetingDetectionEnabled, actual.MeetingDetectionEnabled);
        Assert.Equal(expected.MeetingConfidenceThreshold, actual.MeetingConfidenceThreshold);
        Assert.Equal(expected.MeetingPollIntervalSeconds, actual.MeetingPollIntervalSeconds);
        Assert.Equal(expected.OfficeHours, actual.OfficeHours);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }
}
