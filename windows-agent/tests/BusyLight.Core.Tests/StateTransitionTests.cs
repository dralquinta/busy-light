using BusyLight.Core.Models;
using BusyLight.Core.State;

namespace BusyLight.Core.Tests;

public sealed class StateTransitionTests
{
    [Theory]
    [InlineData(StateSource.Calendar, StateSource.Manual, OperatingMode.Manual, false, "manual-override-active")]
    [InlineData(StateSource.Calendar, StateSource.System, OperatingMode.Auto, true, null)]
    [InlineData(StateSource.System, StateSource.Calendar, OperatingMode.Auto, false, "insufficient-priority")]
    public void IsAllowed_UsesSwiftParityGuards(StateSource current, StateSource requested, OperatingMode mode, bool expectedAllowed, string? expectedReason)
    {
        var decision = StateTransition.IsAllowed(PresenceState.Busy, PresenceState.Available, current, requested, mode);
        Assert.Equal(expectedAllowed, decision.Allowed);
        Assert.Equal(expectedReason, decision.Reason);
    }

    [Fact]
    public void OffMode_RejectsSystemCalendarAndMeetingSources()
    {
        foreach (var source in new[] { StateSource.Calendar, StateSource.System, StateSource.Meeting })
            Assert.Equal("system-is-off", StateTransition.IsAllowed(PresenceState.Off, PresenceState.Away, StateSource.Startup, source, OperatingMode.Off).Reason);
    }
}
