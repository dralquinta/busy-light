using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace BusyLight.Platform.Hotkeys;

/// <summary>A hidden HWND_MESSAGE host for WM_HOTKEY notifications.</summary>
public sealed class HotkeyMessageWindow : IDisposable
{
    private const uint WmHotkey = GlobalHotkeyManager.WmHotkey;
    private static readonly ConcurrentDictionary<nint, HotkeyMessageWindow> Windows = new();
    private static readonly WndProcDelegate WindowProcedure = WndProc;
    private readonly string _className = $"BusyLight.HotkeyWindow.{Guid.NewGuid():N}";
    private nint _handle;

    public event Action<uint, nint>? MessageReceived;
    public nint Handle => _handle;

    public HotkeyMessageWindow()
    {
        var instance = GetModuleHandle(null);
        var windowClass = new WndClassEx { cbSize = (uint)Marshal.SizeOf<WndClassEx>(), hInstance = instance, lpszClassName = _className, lpfnWndProc = Marshal.GetFunctionPointerForDelegate(WindowProcedure) };
        if (RegisterClassEx(ref windowClass) == 0) throw new InvalidOperationException("Could not register BusyLight message window class.");
        _handle = CreateWindowEx(0, _className, null, 0, 0, 0, 0, 0, new nint(-3), nint.Zero, instance, nint.Zero);
        if (_handle == nint.Zero) { UnregisterClass(_className, instance); throw new InvalidOperationException("Could not create BusyLight message-only window."); }
        Windows[_handle] = this;
    }

    private static nint WndProc(nint handle, uint message, nint wParam, nint lParam)
    {
        if (message == WmHotkey && Windows.TryGetValue(handle, out var window)) window.MessageReceived?.Invoke(message, wParam);
        return DefWindowProc(handle, message, wParam, lParam);
    }

    public void Dispose()
    {
        if (_handle == nint.Zero) return;
        var handle = _handle;
        _handle = nint.Zero;
        Windows.TryRemove(handle, out _);
        DestroyWindow(handle);
        UnregisterClass(_className, GetModuleHandle(null));
        MessageReceived = null;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WndProcDelegate(nint hWnd, uint message, nint wParam, nint lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WndClassEx { public uint cbSize; public uint style; public nint lpfnWndProc; public int cbClsExtra; public int cbWndExtra; public nint hInstance; public nint hIcon; public nint hCursor; public nint hbrBackground; public string? lpszMenuName; public string? lpszClassName; public nint hIconSm; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern nint GetModuleHandle(string? moduleName);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern ushort RegisterClassEx(ref WndClassEx windowClass);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern nint CreateWindowEx(uint exStyle, string className, string? windowName, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);
    [DllImport("user32.dll")] private static extern nint DefWindowProc(nint hWnd, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyWindow(nint hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool UnregisterClass(string className, nint instance);
}
