using BusyLight.Agent.Tray;
using BusyLight.Core.State;

namespace BusyLight.Agent;

/// <summary>Composition root for the long-lived tray agent and its platform event sources.</summary>
public sealed class AgentHost : IDisposable
{
    private readonly PresenceStateMachine _stateMachine;
    private readonly ISystemPresenceSource _systemPresence;
    private readonly Action<string> _setTrayStatus;
    private bool _started;
    private bool _disposed;

    public AgentHost(PresenceStateMachine stateMachine, ISystemPresenceSource systemPresence, Action<string> setTrayStatus)
    {
        _stateMachine = stateMachine ?? throw new ArgumentNullException(nameof(stateMachine));
        _systemPresence = systemPresence ?? throw new ArgumentNullException(nameof(systemPresence));
        _setTrayStatus = setTrayStatus ?? throw new ArgumentNullException(nameof(setTrayStatus));
        _stateMachine.OnStateChanged = OnStateChanged;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_started) return;
        _systemPresence.PresenceChanged += OnPresenceChanged;
        _systemPresence.Start();
        _started = true;
    }

    private void OnPresenceChanged(bool isAway) =>
        _stateMachine.HandleEvent(isAway ? new StateEvent.SystemAway() : new StateEvent.SystemReturned());

    private void OnStateChanged(BusyLight.Core.Models.PresenceState state, StateSource source, BusyReason _) =>
        _setTrayStatus(TrayStatusFormatter.Format(state, source));

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_started)
        {
            _systemPresence.PresenceChanged -= OnPresenceChanged;
            _systemPresence.StopMonitoring();
        }
        _stateMachine.OnStateChanged = null;
    }
}

/// <summary>Platform-independent event source for lock, unlock, suspend, and resume signals.</summary>
public interface ISystemPresenceSource
{
    event Action<bool>? PresenceChanged;
    void Start();
    void StopMonitoring();
}
