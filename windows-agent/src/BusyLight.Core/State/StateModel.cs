using BusyLight.Core.Meetings;
using BusyLight.Core.Models;

namespace BusyLight.Core.State;

public enum OperatingMode { Auto, Manual, Off }
public static class OperatingModeExtensions { public static string ToRawValue(this OperatingMode mode) => mode switch { OperatingMode.Auto => "auto", OperatingMode.Manual => "manual", OperatingMode.Off => "off", _ => throw new ArgumentOutOfRangeException(nameof(mode)) }; }

public enum StateSource { Calendar, Meeting, Manual, OfficeHours, System, Startup }
public static class StateSourceExtensions
{
    public static int Priority(this StateSource source) => source switch { StateSource.System => 3, StateSource.OfficeHours or StateSource.Manual => 2, StateSource.Calendar or StateSource.Meeting => 1, _ => 0 };
    public static string ToRawValue(this StateSource source) => source switch { StateSource.Calendar => "calendar", StateSource.Meeting => "meeting", StateSource.Manual => "manual", StateSource.OfficeHours => "officeHours", StateSource.System => "system", StateSource.Startup => "startup", _ => throw new ArgumentOutOfRangeException(nameof(source)) };
}

public enum BusyReason { Calendar, Zoom, Teams, Meet, Manual, Unknown }
public static class BusyReasonExtensions { public static string ToRawValue(this BusyReason reason) => reason.ToString().ToLowerInvariant(); }

public abstract record StateEvent
{
    public sealed record CalendarUpdated(PresenceState State) : StateEvent;
    public sealed record ManualOverride(PresenceState State) : StateEvent;
    public sealed record HotkeyPressed(PresenceState State) : StateEvent;
    public sealed record MeetingDetected(MeetingStatus Status) : StateEvent;
    public sealed record OfficeHoursChanged(bool IsWithinOfficeHours) : StateEvent;
    public sealed record SystemAway : StateEvent;
    public sealed record SystemReturned : StateEvent;
    public sealed record ResumeAuto : StateEvent;
    public sealed record StartupInitialize : StateEvent;
    public sealed record CheckOverrideExpiry : StateEvent;
    public sealed record TurnOff : StateEvent;
}

public readonly record struct TransitionDecision(bool Allowed, string? Reason);
public static class StateTransition
{
    public static TransitionDecision IsAllowed(PresenceState from, PresenceState to, StateSource currentSource, StateSource requestedBy, OperatingMode mode)
    {
        if (mode == OperatingMode.Off && requestedBy is StateSource.Calendar or StateSource.System or StateSource.Meeting) return new(false, "system-is-off");
        if (requestedBy == StateSource.System) return new(true, null);
        if (mode == OperatingMode.Manual && requestedBy is StateSource.Calendar or StateSource.Meeting) return new(false, "manual-override-active");
        if (requestedBy.Priority() < currentSource.Priority() && currentSource != StateSource.Startup) return new(false, "insufficient-priority");
        return new(true, null);
    }
    public static StateSource SourceForEvent(StateEvent value) => value switch
    {
        StateEvent.CalendarUpdated => StateSource.Calendar, StateEvent.MeetingDetected => StateSource.Meeting,
        StateEvent.ManualOverride or StateEvent.HotkeyPressed => StateSource.Manual,
        StateEvent.SystemAway or StateEvent.SystemReturned => StateSource.System,
        StateEvent.OfficeHoursChanged => StateSource.OfficeHours, StateEvent.TurnOff or StateEvent.StartupInitialize => StateSource.Startup,
        _ => StateSource.Manual
    };
}
