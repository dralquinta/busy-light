using BusyLight.Platform.System;
using Xunit;

namespace BusyLight.Platform.Tests.System;

public sealed class SystemPresenceEventMapperTests
{
    [Theory]
    [InlineData(SystemPresenceSignal.SessionLock, true)]
    [InlineData(SystemPresenceSignal.DisplayOff, true)]
    [InlineData(SystemPresenceSignal.SessionUnlock, false)]
    [InlineData(SystemPresenceSignal.DisplayOn, false)]
    public void IsAwaySignalMapsWindowsPresenceEvents(SystemPresenceSignal signal, bool expectedAway) =>
        Assert.Equal(expectedAway, SystemPresenceEventMapper.IsAwaySignal(signal));
}
