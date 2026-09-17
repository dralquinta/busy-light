namespace BusyLight.Core.Meetings;

public enum MeetingConfidence { None = 0, Low = 1, Medium = 2, High = 3 }
public enum MeetingProvider { Zoom, Teams, Meet, Browser }
public enum MeetingSignal { Process, WindowTitle, Combined, CaptureDevice }
public abstract record MeetingStatus
{
    public sealed record None : MeetingStatus;
    public sealed record InMeeting(MeetingConfidence Confidence, MeetingProvider Provider, MeetingSignal Signal) : MeetingStatus;
    public bool IsInMeeting => this is InMeeting;
}
