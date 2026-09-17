using System.Globalization;

namespace BusyLight.Core.Models;

public sealed record OfficeHoursConfiguration(bool IsEnabled = false, int StartMinuteOfDay = 540, int EndMinuteOfDay = 1020, ISet<int>? ActiveWeekdays = null)
{
    public static OfficeHoursConfiguration Default { get; } = new(true, 540, 1020, new HashSet<int> { 2, 3, 4, 5, 6 });
    public ISet<int> Weekdays { get; init; } = new HashSet<int>((ActiveWeekdays ?? new HashSet<int> { 2, 3, 4, 5, 6 }).Where(day => day is >= 1 and <= 7));
    public int Start { get; init; } = Math.Clamp(StartMinuteOfDay, 0, 1439);
    public int End { get; init; } = Math.Clamp(EndMinuteOfDay, 0, 1439);

    public bool Contains(DateTimeOffset date, System.Globalization.Calendar? calendar = null)
    {
        if (!IsEnabled) return true;
        calendar ??= CultureInfo.CurrentCulture.Calendar;
        var local = date.LocalDateTime;
        var weekday = (int)calendar.GetDayOfWeek(local) + 1;
        var minute = local.Hour * 60 + local.Minute;
        if (Start == End) return Weekdays.Contains(weekday);
        if (Start < End) return Weekdays.Contains(weekday) && minute >= Start && minute < End;
        if (minute >= Start) return Weekdays.Contains(weekday);
        var previous = weekday == 1 ? 7 : weekday - 1;
        return minute < End && Weekdays.Contains(previous);
    }
    public bool ContainsMinute(int minute) => !IsEnabled || Start == End || (Start < End ? minute >= Start && minute < End : minute >= Start || minute < End);
    public string ScheduleDescription => $"{WeekdayDescription()} {FormatMinute(Start)}-{FormatMinute(End)}";
    public static string FormatMinute(int minute) => $"{Math.Clamp(minute, 0, 1439) / 60:D2}:{Math.Clamp(minute, 0, 1439) % 60:D2}";
    private string WeekdayDescription() => Weekdays.SetEquals([2, 3, 4, 5, 6]) ? "Mon-Fri" : Weekdays.SetEquals([1, 2, 3, 4, 5, 6, 7]) ? "Sun-Sat" : string.Join(',', Weekdays.Order().Select(day => new[] { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }[day - 1]));
}
