using BusyLight.Core.Calendar;
using BusyLight.Core.Models;
using BusyLight.Core.Network;
using System.Globalization;

namespace BusyLight.Core.Tests;

public sealed class CoreDomainTests
{
    [Theory]
    [InlineData("192.168.1.1", true)]
    [InlineData("0.0.0.0", true)]
    [InlineData("256.1.1.1", false)]
    [InlineData("1.2.3", false)]
    [InlineData("1.2.3.04", true)]
    public void IPv4Validator_RequiresFourNumericOctets(string address, bool expected) => Assert.Equal(expected, NetworkAddressValidator.IsValidIpv4(address));

    [Fact]
    public void OfficeHours_UsesPreviousWeekdayForOvernightWindow()
    {
        var officeHours = new OfficeHoursConfiguration(true, 22 * 60, 2 * 60, new HashSet<int> { 2 }); // Monday night to Tuesday 02:00
        var calendar = new GregorianCalendar();
        var tuesdayAtOne = new DateTimeOffset(2026, 9, 15, 1, 0, 0, TimeSpan.Zero);
        Assert.True(officeHours.Contains(tuesdayAtOne, calendar));
    }

    [Fact]
    public void CalendarResolver_TreatsNotSupportedAsBusy()
    {
        var now = DateTimeOffset.UtcNow;
        var state = CalendarAvailabilityResolver.Resolve([new CalendarEvent(now.AddMinutes(-1), now.AddMinutes(1), CalendarAvailability.NotSupported)], now);
        Assert.Equal(PresenceState.Busy, state);
    }

    [Fact]
    public void WledRequest_UsesProtocolCompatibleBody()
    {
        Assert.Equal("{\"ps\":3,\"v\":true}", WledStateRequest.ForPreset(3).ToJson());
    }

    [Theory]
    [InlineData(0)]
    [InlineData(251)]
    public void WledRequest_RejectsPresetOutsideProtocolRange(int preset)
        => Assert.Throws<ArgumentOutOfRangeException>(() => WledStateRequest.ForPreset(preset));
}
