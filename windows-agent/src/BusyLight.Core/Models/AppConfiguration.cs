namespace BusyLight.Core.Models;

/// <summary>Portable configuration values. Storage maps these values to the documented app.* keys.</summary>
public sealed record AppConfiguration
{
    public const int MinimumWledHttpTimeout = 2500;
    public PresenceState PresenceState { get; init; } = PresenceState.Available;
    public string DeviceNetworkAddress { get; init; } = "";
    public IReadOnlyList<string> DeviceNetworkAddresses { get; init; } = [];
    public int DeviceNetworkPort => 80;
    public int WledPresetAvailable { get; init; } = 1;
    public int WledPresetTentative { get; init; } = 2;
    public int WledPresetBusy { get; init; } = 3;
    public int WledPresetAway { get; init; } = 4;
    public int WledPresetUnknown { get; init; } = 5;
    public int WledPresetOff { get; init; } = 6;
    public int WledHttpTimeout { get; init; } = MinimumWledHttpTimeout;
    public int NormalizedWledHttpTimeout => Math.Max(MinimumWledHttpTimeout, WledHttpTimeout);
    public int WledHealthCheckInterval { get; init; } = 10;
    public bool WledEnableDiscovery { get; init; } = true;
    public bool LaunchOnStartup { get; init; }
    public int? ManualOverrideTimeoutMinutes { get; init; } = 30;
    public int StateStabilizationSeconds { get; init; }
    public OfficeHoursConfiguration OfficeHours { get; init; } = OfficeHoursConfiguration.Default;
    public bool MeetingDetectionEnabled { get; init; } = true;
    public int MeetingConfidenceThreshold { get; init; } = 3;
    public double MeetingPollIntervalSeconds { get; init; } = 3;
    public int PresetFor(PresenceState state) => state switch { PresenceState.Available => WledPresetAvailable, PresenceState.Tentative => WledPresetTentative, PresenceState.Busy => WledPresetBusy, PresenceState.Away => WledPresetAway, PresenceState.Unknown => WledPresetUnknown, PresenceState.Off => WledPresetOff, _ => throw new ArgumentOutOfRangeException(nameof(state)) };
}
