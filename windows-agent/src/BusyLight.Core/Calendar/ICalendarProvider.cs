namespace BusyLight.Core.Calendar;

/// <summary>Platform calendar adapters expose already-normalized event data to Core.</summary>
public interface ICalendarProvider
{
    Task<IReadOnlyList<CalendarEvent>> GetEventsAsync(DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken = default);
}
