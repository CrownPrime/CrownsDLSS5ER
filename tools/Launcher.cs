// CrownsDLSS5ER.exe: opens the manager (CrownsDLSSManager.ps1 next to it) in Windows PowerShell, with no console
// window, and carries the CrownsDLSS5ER icon. Built into the release by tools\Build-Release.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher
{
    const string Title = "CrownsDLSS5ER";

    [STAThread]
    static int Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "CrownsDLSSManager.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("CrownsDLSSManager.ps1 was not found next to CrownsDLSS5ER.exe.\r\n\r\nExtract the whole release zip and start CrownsDLSS5ER.exe from that folder.",
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        // CreateNoWindow: PowerShell gets no console window at all (Windows Terminal ignores -WindowStyle Hidden).
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = dir,
        };
        try
        {
            Process.Start(start);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("Could not start Windows PowerShell:\r\n" + e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
