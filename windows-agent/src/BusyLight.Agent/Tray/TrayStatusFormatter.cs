using BusyLight.Core.Models;
using BusyLight.Core.State;

namespace BusyLight.Agent.Tray;

public static class TrayStatusFormatter
{
    public static string Format(PresenceState state, StateSource source) =>
        $"Status: {state.DisplayName()} ({Qualifier(state, source)})";

    private static string Qualifier(PresenceState state, StateSource source) =>
        state == PresenceState.Off ? "Disabled" : source switch
        {
            StateSource.Calendar => "Calendar",
            StateSource.Meeting => "Meeting",
            StateSource.System => "System",
            StateSource.OfficeHours => "Office Hours",
            StateSource.Manual => "Manual Override",
            _ => "Automatic",
        };
}
