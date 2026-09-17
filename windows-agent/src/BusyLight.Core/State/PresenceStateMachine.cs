using BusyLight.Core.Meetings;
using BusyLight.Core.Models;

namespace BusyLight.Core.State;

/// <summary>Pure, serialized state coordinator. Platform code must marshal calls to its UI dispatcher.</summary>
public sealed class PresenceStateMachine : IDisposable
{
    private (PresenceState State, StateSource Source)? _beforeSystemAway;
    private DateTimeOffset? _manualOverrideExpiry;
    private CancellationTokenSource? _expiryCts;
    private CancellationTokenSource? _stabilizationCts;
    private bool _offBecauseOutsideOfficeHours;

    public PresenceState CurrentState { get; private set; }
    public OperatingMode CurrentMode { get; private set; }
    public StateSource CurrentSource { get; private set; } = StateSource.Startup;
    public BusyReason CurrentBusyReason { get; private set; } = BusyReason.Unknown;
    public int? ManualOverrideTimeoutMinutes { get; set; } = 30;
    public int StateStabilizationSeconds { get; set; }
    public Action<PresenceState, StateSource, BusyReason>? OnStateChanged { get; set; }
    public Action<OperatingMode>? OnModeChanged { get; set; }
    public Action? OnRequestCalendarSync { get; set; }

    public PresenceStateMachine(PresenceState initialState = PresenceState.Unknown, OperatingMode initialMode = OperatingMode.Auto)
    { CurrentState = initialState; CurrentMode = initialMode; }

    public void HandleEvent(StateEvent value)
    {
        if (value is StateEvent.ResumeAuto) { ResumeAuto(); return; }
        if (CurrentMode == OperatingMode.Manual) CheckExpiry();
        switch (value)
        {
            case StateEvent.CalendarUpdated e: CalendarUpdated(e.State); break;
            case StateEvent.ManualOverride e: ManualOverride(e.State); break;
            case StateEvent.HotkeyPressed e: ManualOverride(e.State); break;
            case StateEvent.SystemAway: SystemAway(); break;
            case StateEvent.SystemReturned: SystemReturned(); break;
            case StateEvent.StartupInitialize: Transition(PresenceState.Unknown, StateSource.Startup, force: true); break;
            case StateEvent.CheckOverrideExpiry: CheckExpiry(); break;
            case StateEvent.TurnOff: _offBecauseOutsideOfficeHours = false; TurnOff(StateSource.Startup); break;
            case StateEvent.OfficeHoursChanged e: ApplyOfficeHours(e.IsWithinOfficeHours); break;
            case StateEvent.MeetingDetected e: MeetingUpdated(e.Status); break;
        }
    }

    public TransitionDecision CanTransition(PresenceState state, StateSource source) => StateTransition.IsAllowed(CurrentState, state, CurrentSource, source, CurrentMode);
    public (PresenceState State, StateSource Source, OperatingMode Mode) GetCurrentState() => (CurrentState, CurrentSource, CurrentMode);
    public void ApplyOfficeHours(bool within)
    {
        if (within) { if (_offBecauseOutsideOfficeHours) { _offBecauseOutsideOfficeHours = false; ResumeAuto(); } return; }
        if (CurrentMode is OperatingMode.Off or OperatingMode.Manual) return;
        _offBecauseOutsideOfficeHours = true; TurnOff(StateSource.OfficeHours);
    }
    private void CalendarUpdated(PresenceState state) { if (state == CurrentState) return; if (CanTransition(state, StateSource.Calendar).Allowed) Transition(state, StateSource.Calendar); }
    private void ManualOverride(PresenceState state)
    {
        _stabilizationCts?.Cancel(); _offBecauseOutsideOfficeHours = false;
        if (CurrentSource == StateSource.System) return;
        SetMode(OperatingMode.Manual);
        _manualOverrideExpiry = ManualOverrideTimeoutMinutes is int minutes ? DateTimeOffset.UtcNow.AddMinutes(minutes) : null;
        if (ManualOverrideTimeoutMinutes is int timeout) ScheduleExpiry(timeout);
        Transition(state, StateSource.Manual);
    }
    private void SystemAway() { if (CurrentMode == OperatingMode.Off) return; if (CurrentState != PresenceState.Away) _beforeSystemAway = (CurrentState, CurrentSource); Transition(PresenceState.Away, StateSource.System, force: true); }
    private void SystemReturned() { if (CurrentMode == OperatingMode.Off) return; if (_beforeSystemAway is { } prior) { Transition(prior.State, prior.Source, force: true); _beforeSystemAway = null; } else Transition(PresenceState.Unknown, StateSource.System); }
    private void MeetingUpdated(MeetingStatus status)
    {
        if (CurrentMode == OperatingMode.Off) return;
        if (status is MeetingStatus.InMeeting meeting && CanTransition(PresenceState.Busy, StateSource.Meeting).Allowed) Transition(PresenceState.Busy, StateSource.Meeting, meeting.Provider);
        else if (status is MeetingStatus.None && CurrentSource == StateSource.Meeting) { Transition(PresenceState.Available, StateSource.Startup, force: true); OnRequestCalendarSync?.Invoke(); }
    }
    private void ResumeAuto() { CancelTimers(); _manualOverrideExpiry = null; _offBecauseOutsideOfficeHours = false; CurrentSource = StateSource.Startup; SetMode(OperatingMode.Auto); OnRequestCalendarSync?.Invoke(); }
    private void TurnOff(StateSource source) { CancelTimers(); _manualOverrideExpiry = null; CurrentSource = StateSource.Startup; SetMode(OperatingMode.Off); Transition(PresenceState.Off, source, force: true); }
    private void CheckExpiry() { if (_manualOverrideExpiry is { } expiry && DateTimeOffset.UtcNow >= expiry) ResumeAuto(); }
    private void ScheduleExpiry(int minutes) { _expiryCts?.Cancel(); _expiryCts = new(); var token = _expiryCts.Token; _ = Task.Run(async () => { try { await Task.Delay(TimeSpan.FromMinutes(minutes), token); HandleEvent(new StateEvent.CheckOverrideExpiry()); } catch (OperationCanceledException) { } }, token); }
    private void Transition(PresenceState state, StateSource source, MeetingProvider? provider = null, bool force = false)
    {
        if (!force && StateStabilizationSeconds > 0) { _stabilizationCts?.Cancel(); _stabilizationCts = new(); var token = _stabilizationCts.Token; _ = Task.Run(async () => { try { await Task.Delay(TimeSpan.FromSeconds(StateStabilizationSeconds), token); if (!token.IsCancellationRequested) Transition(state, source, provider, true); } catch (OperationCanceledException) { } }, token); return; }
        CurrentState = state; CurrentSource = source; CurrentBusyReason = state != PresenceState.Busy ? BusyReason.Unknown : source switch { StateSource.Calendar => BusyReason.Calendar, StateSource.Manual => BusyReason.Manual, StateSource.Meeting when provider == MeetingProvider.Zoom => BusyReason.Zoom, StateSource.Meeting when provider == MeetingProvider.Teams => BusyReason.Teams, StateSource.Meeting when provider == MeetingProvider.Meet => BusyReason.Meet, _ => BusyReason.Unknown }; OnStateChanged?.Invoke(state, source, CurrentBusyReason);
    }
    private void SetMode(OperatingMode mode) { if (CurrentMode == mode) return; CurrentMode = mode; OnModeChanged?.Invoke(mode); }
    private void CancelTimers() { _expiryCts?.Cancel(); _stabilizationCts?.Cancel(); }
    public void Dispose() => CancelTimers();
}
