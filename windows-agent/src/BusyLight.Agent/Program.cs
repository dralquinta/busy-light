using BusyLight.Agent.Tray;
using BusyLight.Core.Models;
using BusyLight.Core.State;

namespace BusyLight.Agent;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var tray = new NotifyIcon
        {
            Visible = true,
            Text = TrayStatusFormatter.Format(PresenceState.Unknown, StateSource.Startup),
            ContextMenuStrip = BuildMenu(),
        };
        Application.Run();
    }

    private static ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Status: Unknown (Automatic)").Enabled = false;
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Settings");
        menu.Items.Add("Quit", null, (_, _) => Application.Exit());
        return menu;
    }
}
