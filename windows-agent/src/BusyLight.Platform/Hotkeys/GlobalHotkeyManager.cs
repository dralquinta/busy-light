using System.Runtime.InteropServices;

namespace BusyLight.Platform.Hotkeys;

[Flags]
public enum HotkeyModifiers : uint
{
    Alt = 0x0001,
    Control = 0x0002,
    NoRepeat = 0x4000,
}

public enum HotkeyCommand
{
    Available = 1,
    Tentative = 2,
    Busy = 3,
    ResumeCalendar = 4,
    TurnOff = 5,
    Away = 6,
}

public sealed record HotkeyBinding(HotkeyCommand Command, uint VirtualKey, HotkeyModifiers Modifiers)
{
    public int Id => (int)Command;
    public static IReadOnlyList<HotkeyBinding> Defaults { get; } =
    [
        new(HotkeyCommand.Available, 0x31, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
        new(HotkeyCommand.Tentative, 0x32, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
        new(HotkeyCommand.Busy, 0x33, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
        new(HotkeyCommand.ResumeCalendar, 0x34, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
        new(HotkeyCommand.TurnOff, 0x35, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
        new(HotkeyCommand.Away, 0x36, HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat),
    ];
}

/// <summary>Win32 registration boundary. Tests use a fake; production calls User32.</summary>
public interface IHotkeyRegistration
{
    bool Register(nint windowHandle, HotkeyBinding binding, out int errorCode);
    void Unregister(nint windowHandle, int id);
}

public sealed class Win32HotkeyRegistration : IHotkeyRegistration
{
    public bool Register(nint windowHandle, HotkeyBinding binding, out int errorCode)
    {
        if (RegisterHotKey(windowHandle, binding.Id, (uint)binding.Modifiers, binding.VirtualKey)) { errorCode = 0; return true; }
        errorCode = Marshal.GetLastWin32Error();
        return false;
    }

    public void Unregister(nint windowHandle, int id) => UnregisterHotKey(windowHandle, id);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);
}

/// <summary>Registers global Ctrl+Alt hotkeys against a message-only window.</summary>
public sealed class GlobalHotkeyManager : IDisposable
{
    public const uint WmHotkey = 0x0312;
    private readonly nint _windowHandle;
    private readonly IHotkeyRegistration _registration;
    private readonly HashSet<int> _registeredIds = [];
    private IReadOnlyList<HotkeyBinding> _bindings;
    private bool _disposed;

    public event Action<HotkeyCommand>? CommandPressed;
    public IReadOnlyCollection<HotkeyCommand> FailedCommands => _failureCodes.Keys;
    public IReadOnlyDictionary<HotkeyCommand, int> FailureCodes => _failureCodes;
    private readonly Dictionary<HotkeyCommand, int> _failureCodes = [];

    public GlobalHotkeyManager(nint windowHandle, IHotkeyRegistration? registration = null, IReadOnlyList<HotkeyBinding>? bindings = null)
    {
        if (windowHandle == nint.Zero) throw new ArgumentOutOfRangeException(nameof(windowHandle), "A message-only window handle is required.");
        _windowHandle = windowHandle;
        _registration = registration ?? new Win32HotkeyRegistration();
        _bindings = bindings ?? HotkeyBinding.Defaults;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_registeredIds.Count > 0 || _failureCodes.Count > 0) return;
        RegisterBindings();
    }

    public void UpdateBindings(IReadOnlyList<HotkeyBinding> bindings)
    {
        ArgumentNullException.ThrowIfNull(bindings);
        ObjectDisposedException.ThrowIf(_disposed, this);
        UnregisterAll();
        _failureCodes.Clear();
        _bindings = bindings;
        RegisterBindings();
    }

    public void HandleWindowMessage(uint message, nint wParam)
    {
        if (message != WmHotkey || _disposed) return;
        var id = unchecked((int)wParam);
        if (!_registeredIds.Contains(id) || !Enum.IsDefined((HotkeyCommand)id)) return;
        CommandPressed?.Invoke((HotkeyCommand)id);
    }

    private void RegisterBindings()
    {
        foreach (var binding in _bindings)
        {
            if (_registration.Register(_windowHandle, binding, out var errorCode)) _registeredIds.Add(binding.Id);
            else _failureCodes[binding.Command] = errorCode;
        }
    }

    private void UnregisterAll()
    {
        foreach (var id in _registeredIds) _registration.Unregister(_windowHandle, id);
        _registeredIds.Clear();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        UnregisterAll();
        CommandPressed = null;
    }
}
