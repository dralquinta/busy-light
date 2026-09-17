using BusyLight.Platform.Hotkeys;
using Xunit;

namespace BusyLight.Platform.Tests.Hotkeys;

public sealed class GlobalHotkeyManagerTests
{
    [Fact]
    public void Start_RegistersAllSixDefaultCommands()
    {
        var registration = new FakeRegistration();
        using var manager = new GlobalHotkeyManager((nint)42, registration);

        manager.Start();

        Assert.Equal(6, registration.Registered.Count);
        Assert.Equal(new[] { HotkeyCommand.Available, HotkeyCommand.Tentative, HotkeyCommand.Busy, HotkeyCommand.ResumeCalendar, HotkeyCommand.TurnOff, HotkeyCommand.Away }, registration.Registered.Select(binding => binding.Command));
        Assert.All(registration.Registered, binding => Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, binding.Modifiers));
        Assert.Equal(new uint[] { 0x31, 0x32, 0x33, 0x34, 0x35, 0x36 }, registration.Registered.Select(binding => binding.VirtualKey));
    }

    [Fact]
    public void HotkeyMessage_RaisesMatchingCommandAndSkipsFailedRegistrations()
    {
        var registration = new FakeRegistration { RejectId = (int)HotkeyCommand.Busy };
        using var manager = new GlobalHotkeyManager((nint)42, registration);
        var commands = new List<HotkeyCommand>();
        manager.CommandPressed += commands.Add;
        manager.Start();

        manager.HandleWindowMessage(GlobalHotkeyManager.WmHotkey, (nint)(int)HotkeyCommand.Available);
        manager.HandleWindowMessage(GlobalHotkeyManager.WmHotkey, (nint)(int)HotkeyCommand.Busy);

        Assert.Equal([HotkeyCommand.Available], commands);
        Assert.Contains(HotkeyCommand.Busy, manager.FailedCommands);
        Assert.Equal(1409, manager.FailureCodes[HotkeyCommand.Busy]);
    }

    [Fact]
    public void Dispose_UnregistersEverySuccessfullyRegisteredHotkey()
    {
        var registration = new FakeRegistration();
        var manager = new GlobalHotkeyManager((nint)42, registration);
        manager.Start();

        manager.Dispose();

        Assert.Equal(registration.Registered.Select(binding => binding.Id).Order(), registration.Unregistered.Order());
    }

    private sealed class FakeRegistration : IHotkeyRegistration
    {
        public int? RejectId { get; init; }
        public List<HotkeyBinding> Registered { get; } = [];
        public List<int> Unregistered { get; } = [];
        public bool Register(nint windowHandle, HotkeyBinding binding, out int errorCode)
        {
            if (binding.Id == RejectId) { errorCode = 1409; return false; }
            Registered.Add(binding); errorCode = 0; return true;
        }
        public void Unregister(nint windowHandle, int id) => Unregistered.Add(id);
    }
}
