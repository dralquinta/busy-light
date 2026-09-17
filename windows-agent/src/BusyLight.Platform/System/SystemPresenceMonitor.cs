using Microsoft.Win32;

namespace BusyLight.Platform.System;

public sealed class SystemPresenceMonitor : IDisposable
{
    public event Action<bool>? PresenceChanged;

    public void Start()
    {
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    private void OnSessionSwitch(object? sender, SessionSwitchEventArgs args) =>
        Publish(args.Reason is SessionSwitchReason.SessionLock ? SystemPresenceSignal.SessionLock : SystemPresenceSignal.SessionUnlock);

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs args) =>
        Publish(args.Mode is PowerModes.Suspend ? SystemPresenceSignal.Suspend : SystemPresenceSignal.Resume);

    private void Publish(SystemPresenceSignal signal) => PresenceChanged?.Invoke(SystemPresenceEventMapper.IsAwaySignal(signal));

    public void Dispose()
    {
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
    }
}
