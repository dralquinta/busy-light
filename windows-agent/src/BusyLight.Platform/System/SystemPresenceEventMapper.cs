namespace BusyLight.Platform.System;

public enum SystemPresenceSignal { SessionLock, SessionUnlock, DisplayOff, DisplayOn, Suspend, Resume }

public static class SystemPresenceEventMapper
{
    public static bool IsAwaySignal(SystemPresenceSignal signal) => signal is SystemPresenceSignal.SessionLock or SystemPresenceSignal.DisplayOff or SystemPresenceSignal.Suspend;
}
