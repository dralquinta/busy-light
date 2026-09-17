using BusyLight.Core.Models;

namespace BusyLight.Core.Calendar;

public enum CalendarAvailability { Busy, Unavailable, NotSupported, Tentative, Free }
public sealed record CalendarEvent(DateTimeOffset Start, DateTimeOffset End, CalendarAvailability Availability)
{ public bool OccursAt(DateTimeOffset at) => Start <= at && at < End; }
public sealed class CalendarAvailabilityResolver
{
    public PresenceState Resolve(IEnumerable<CalendarEvent> events, DateTimeOffset at)
    {
        var overlapping = events.Where(e => e.OccursAt(at)).Select(e => e.Availability).ToArray();
        if (overlapping.Any(value => value is CalendarAvailability.Busy or CalendarAvailability.Unavailable or CalendarAvailability.NotSupported)) return PresenceState.Busy;
        return overlapping.Contains(CalendarAvailability.Tentative) ? PresenceState.Tentative : PresenceState.Available;
    }
}
