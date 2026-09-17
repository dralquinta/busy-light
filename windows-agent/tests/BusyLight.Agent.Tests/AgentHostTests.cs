using BusyLight.Agent;
using BusyLight.Core.Models;
using BusyLight.Core.State;

namespace BusyLight.Agent.Tests;

public sealed class AgentHostTests
{
    [Fact]
    public void SystemPresenceEvents_UpdateMachineAndTrayStatus()
    {
        var machine = new PresenceStateMachine();
        machine.HandleEvent(new StateEvent.CalendarUpdated(PresenceState.Busy));
        var presence = new FakeSystemPresenceSource();
        var statuses = new List<string>();

        using var host = new AgentHost(machine, presence, statuses.Add);
        host.Start();
        presence.Publish(isAway: true);

        Assert.True(presence.Started);
        Assert.Equal(PresenceState.Away, machine.CurrentState);
        Assert.Equal(StateSource.System, machine.CurrentSource);
        Assert.Equal("Status: Away (System)", Assert.Single(statuses));

        presence.Publish(isAway: false);
        Assert.Equal(PresenceState.Busy, machine.CurrentState);
        Assert.Equal(StateSource.Calendar, machine.CurrentSource);
        Assert.Equal("Status: Busy (Calendar)", statuses.Last());
    }

    [Fact]
    public void Dispose_UnsubscribesAndStopsPresenceSource()
    {
        var presence = new FakeSystemPresenceSource();
        var machine = new PresenceStateMachine();
        var statuses = new List<string>();
        var host = new AgentHost(machine, presence, statuses.Add);
        host.Start();

        host.Dispose();
        presence.Publish(isAway: true);

        Assert.True(presence.Stopped);
        Assert.Empty(statuses);
        Assert.Equal(PresenceState.Unknown, machine.CurrentState);
    }

    private sealed class FakeSystemPresenceSource : ISystemPresenceSource
    {
        public event Action<bool>? PresenceChanged;
        public bool Started { get; private set; }
        public bool Stopped { get; private set; }
        public void Start() => Started = true;
        public void Stop() => Stopped = true;
        public void Publish(bool isAway) => PresenceChanged?.Invoke(isAway);
    }
}
