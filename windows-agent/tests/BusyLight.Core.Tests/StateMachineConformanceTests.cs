using System.Text.Json;
using BusyLight.Core.Models;
using BusyLight.Core.State;

namespace BusyLight.Core.Tests;

public sealed class StateMachineConformanceTests
{
    [Fact]
    public void ManualOverride_BlocksCalendarUpdates()
    {
        var machine = new PresenceStateMachine();
        machine.HandleEvent(new StateEvent.ManualOverride(PresenceState.Busy));
        machine.HandleEvent(new StateEvent.CalendarUpdated(PresenceState.Available));

        Assert.Equal(PresenceState.Busy, machine.CurrentState);
        Assert.Equal(OperatingMode.Manual, machine.CurrentMode);
        Assert.Equal(StateSource.Manual, machine.CurrentSource);
    }

    [Fact]
    public void SharedConformanceCorpus_HasAtLeastOneExecutableCase()
    {
        var path = FindCorpus();
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var cases = document.RootElement.EnumerateArray().ToArray();
        Assert.NotEmpty(cases);

        foreach (var testCase in cases)
        {
            var machine = new PresenceStateMachine();
            foreach (var step in testCase.GetProperty("steps").EnumerateArray())
            {
                machine.HandleEvent(ParseEvent(step.GetProperty("event")));
                var expected = step.GetProperty("expect");
                Assert.Equal(expected.GetProperty("state").GetString(), machine.CurrentState.ToRawValue());
                Assert.Equal(expected.GetProperty("mode").GetString(), machine.CurrentMode.ToRawValue());
                Assert.Equal(expected.GetProperty("source").GetString(), machine.CurrentSource.ToRawValue());
                if (expected.TryGetProperty("busyReason", out var busyReason))
                    Assert.Equal(busyReason.GetString(), machine.CurrentBusyReason.ToRawValue());
            }
        }
    }

    private static StateEvent ParseEvent(JsonElement value) => value.GetProperty("kind").GetString() switch
    {
        "startupInitialize" => new StateEvent.StartupInitialize(),
        "systemAway" => new StateEvent.SystemAway(),
        "systemReturned" => new StateEvent.SystemReturned(),
        "resumeAuto" => new StateEvent.ResumeAuto(),
        "turnOff" => new StateEvent.TurnOff(),
        "calendarUpdated" => new StateEvent.CalendarUpdated(ParseState(value)),
        "manualOverride" => new StateEvent.ManualOverride(ParseState(value)),
        _ => throw new InvalidOperationException("Unsupported corpus event"),
    };

    private static PresenceState ParseState(JsonElement value) =>
        PresenceStateExtensions.FromRawValue(value.GetProperty("state").GetString()!)!.Value;

    private static string FindCorpus()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var candidate = Path.Combine(directory.FullName, "docs", "specs", "state-machine-conformance.json");
            if (File.Exists(candidate)) return candidate;
        }
        throw new FileNotFoundException("Shared state-machine corpus was not found.");
    }
}
