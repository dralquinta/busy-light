using BusyLight.Agent.Tray;
using BusyLight.Core.Models;
using BusyLight.Core.State;
using Xunit;

namespace BusyLight.Agent.Tests.Tray;

public sealed class TrayStatusFormatterTests
{
    [Fact]
    public void Format_UsesParityQualifierForCalendarState()
    {
        Assert.Equal("Status: Busy (Calendar)", TrayStatusFormatter.Format(PresenceState.Busy, StateSource.Calendar));
    }

    [Fact]
    public void Format_UsesDisabledQualifierForOffMode()
    {
        Assert.Equal("Status: Off (Disabled)", TrayStatusFormatter.Format(PresenceState.Off, StateSource.Startup));
    }
}
