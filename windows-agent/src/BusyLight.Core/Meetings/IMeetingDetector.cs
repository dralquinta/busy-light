namespace BusyLight.Core.Meetings;

public interface IMeetingDetector
{
    MeetingProvider Provider { get; }
    bool IsEnabled { get; set; }
    Task<MeetingStatus> DetectAsync(CancellationToken cancellationToken = default);
}
