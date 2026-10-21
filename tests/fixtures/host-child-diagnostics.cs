using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

/* 2026-10-22：只读转储本次持有的测试子进程；不终止目标，不改变原 READY/退出截止时间。 */
public static class HostChildDiagnostics
{
    [DllImport("dbghelp.dll", SetLastError = true)]
    private static extern bool MiniDumpWriteDump(IntPtr process, uint processId, IntPtr file, uint type, IntPtr exception, IntPtr userStream, IntPtr callback);

    public static void Write(Process process, string path)
    {
        if (process == null || process.HasExited) throw new InvalidOperationException("Owned child is not alive");
        using (FileStream file = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read))
        {
            if (!MiniDumpWriteDump(process.Handle, (uint)process.Id, file.SafeFileHandle.DangerousGetHandle(), 0x1124, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
