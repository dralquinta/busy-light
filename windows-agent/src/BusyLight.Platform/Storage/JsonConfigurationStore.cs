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

    public JsonConfigurationStore(string? directory = null)
    {
        _directory = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BusyLight");
    }

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
            var corruptPath = Path.Combine(_directory, $"config.corrupt-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}.json");
            File.Move(path, corruptPath, overwrite: true);
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
        [property: JsonPropertyName("app.wled_preset_busy")] int WledPresetBusy)
    {
        public static ConfigurationDocument From(AppConfiguration value) =>
            new(1, value.DeviceNetworkAddress, value.WledPresetBusy);

        public AppConfiguration ToConfiguration() => new()
        {
            DeviceNetworkAddress = DeviceNetworkAddress,
            WledPresetBusy = WledPresetBusy,
        };
    }
}
