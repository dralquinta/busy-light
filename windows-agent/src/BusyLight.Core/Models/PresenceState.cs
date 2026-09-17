namespace BusyLight.Core.Models;

public enum PresenceState { Available, Busy, Away, Tentative, Unknown, Off }

public static class PresenceStateExtensions
{
    public static string ToRawValue(this PresenceState state) => state switch
    {
        PresenceState.Available => "available", PresenceState.Busy => "busy",
        PresenceState.Away => "away", PresenceState.Tentative => "tentative",
        PresenceState.Unknown => "unknown", PresenceState.Off => "off", _ => throw new ArgumentOutOfRangeException(nameof(state))
    };
    public static PresenceState? FromRawValue(string raw) => raw switch
    {
        "available" => PresenceState.Available, "busy" => PresenceState.Busy, "away" => PresenceState.Away,
        "tentative" => PresenceState.Tentative, "unknown" => PresenceState.Unknown, "off" => PresenceState.Off, _ => null
    };
    public static string DisplayName(this PresenceState state) => state switch
    {
        PresenceState.Available => "Available", PresenceState.Busy => "Busy", PresenceState.Away => "Away",
        PresenceState.Tentative => "Tentative", PresenceState.Unknown => "Unknown", PresenceState.Off => "Off", _ => throw new ArgumentOutOfRangeException(nameof(state))
    };
}

public enum DeviceConnectionStatus { Online, Offline, Unknown }
public enum DeviceStatus { Connected, Disconnected, Searching }
