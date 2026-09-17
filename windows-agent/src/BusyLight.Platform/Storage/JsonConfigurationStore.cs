using System.Text.Json;
using System.Text.Json.Serialization;
using BusyLight.Core.Models;

namespace BusyLight.Platform.Storage;

/// <summary>Atomic JSON configuration storage rooted in local application data.</summary>
public sealed class JsonConfigurationStore
{
    private const string FileName = "config.json";
    private readonly string _directory;
    private readonly JsonSerializerOptions _serializerOptions = new() { WriteIndented = true };

    public JsonConfigurationStore(string? directory = null) => _directory = directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BusyLight");

    public AppConfiguration Load()
    {
        var path = Path.Combine(_directory, FileName);
        if (!File.Exists(path)) return new AppConfiguration();
        try
        {
            var document = JsonSerializer.Deserialize<ConfigurationDocument>(File.ReadAllText(path), _serializerOptions);
            return document?.ToConfiguration() ?? new AppConfiguration();
        }
        catch (JsonException)
        {
            File.Move(path, Path.Combine(_directory, $"config.corrupt-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}.json"), overwrite: true);
            return new AppConfiguration();
        }
    }

    public void Save(AppConfiguration configuration)
    {
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, FileName);
        var temporaryPath = Path.Combine(_directory, $"{FileName}.tmp");
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(ConfigurationDocument.From(configuration), _serializerOptions));
        File.Move(temporaryPath, path, overwrite: true);
    }

    private sealed record ConfigurationDocument(
        [property: JsonPropertyName("schema_version")] int SchemaVersion,
        [property: JsonPropertyName("app.device_network_address")] string DeviceNetworkAddress,
        [property: JsonPropertyName("app.device_network_addresses")] IReadOnlyList<string> DeviceNetworkAddresses,
        [property: JsonPropertyName("app.wled_preset_available")] int WledPresetAvailable,
        [property: JsonPropertyName("app.wled_preset_tentative")] int WledPresetTentative,
        [property: JsonPropertyName("app.wled_preset_busy")] int WledPresetBusy,
        [property: JsonPropertyName("app.wled_preset_away")] int WledPresetAway,
        [property: JsonPropertyName("app.wled_preset_unknown")] int WledPresetUnknown,
        [property: JsonPropertyName("app.wled_preset_off")] int WledPresetOff,
        [property: JsonPropertyName("app.wled_http_timeout")] int WledHttpTimeout,
        [property: JsonPropertyName("app.wled_health_check_interval")] int WledHealthCheckInterval,
        [property: JsonPropertyName("app.wled_enable_discovery")] bool WledEnableDiscovery,
        [property: JsonPropertyName("app.launch_on_startup")] bool LaunchOnStartup,
        [property: JsonPropertyName("app.manual_override_timeout_minutes")] int? ManualOverrideTimeoutMinutes,
        [property: JsonPropertyName("app.state_stabilization_seconds")] int StateStabilizationSeconds,
        [property: JsonPropertyName("app.meeting_detection_enabled")] bool MeetingDetectionEnabled,
        [property: JsonPropertyName("app.meeting_confidence_threshold")] int MeetingConfidenceThreshold,
        [property: JsonPropertyName("app.meeting_poll_interval_seconds")] double MeetingPollIntervalSeconds,
        [property: JsonPropertyName("app.office_hours")] OfficeHoursConfiguration OfficeHours)
    {
        public static ConfigurationDocument From(AppConfiguration value) => new(1, value.DeviceNetworkAddress, value.DeviceNetworkAddresses, value.WledPresetAvailable, value.WledPresetTentative, value.WledPresetBusy, value.WledPresetAway, value.WledPresetUnknown, value.WledPresetOff, value.WledHttpTimeout, value.WledHealthCheckInterval, value.WledEnableDiscovery, value.LaunchOnStartup, value.ManualOverrideTimeoutMinutes, value.StateStabilizationSeconds, value.MeetingDetectionEnabled, value.MeetingConfidenceThreshold, value.MeetingPollIntervalSeconds, value.OfficeHours);

        public AppConfiguration ToConfiguration() => new()
        {
            DeviceNetworkAddress = DeviceNetworkAddress, DeviceNetworkAddresses = DeviceNetworkAddresses,
            WledPresetAvailable = WledPresetAvailable, WledPresetTentative = WledPresetTentative,
            WledPresetBusy = WledPresetBusy, WledPresetAway = WledPresetAway,
            WledPresetUnknown = WledPresetUnknown, WledPresetOff = WledPresetOff,
            WledHttpTimeout = WledHttpTimeout, WledHealthCheckInterval = WledHealthCheckInterval,
            WledEnableDiscovery = WledEnableDiscovery, LaunchOnStartup = LaunchOnStartup,
            ManualOverrideTimeoutMinutes = ManualOverrideTimeoutMinutes, StateStabilizationSeconds = StateStabilizationSeconds,
            MeetingDetectionEnabled = MeetingDetectionEnabled, MeetingConfidenceThreshold = MeetingConfidenceThreshold,
            MeetingPollIntervalSeconds = MeetingPollIntervalSeconds, OfficeHours = OfficeHours,
        };
    }
}
