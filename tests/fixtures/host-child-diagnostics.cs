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

    /* 2026-10-22：阶段文件只作最佳努力旁证；缺失代表未观测，不能改变原取证结果或期限。 */
    internal static void RecordPhase(string path, string phase)
    {
        try { File.AppendAllText(path + ".phases.log", DateTime.UtcNow.ToString("o") + " " + phase + Environment.NewLine, new System.Text.UTF8Encoding(false)); }
        catch { }
    }

    public static void Write(Process process, string path)
    {
        RecordPhase(path, "write-entered"); // 2026-10-22：后续标记分别包围文件准备、句柄解析及原生调用点。
        if (process == null || process.HasExited) throw new InvalidOperationException("Owned child is not alive");
        using (FileStream file = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read))
        {
            RecordPhase(path, "file-opened");
            IntPtr processHandle = process.Handle;
            IntPtr dumpHandle = file.SafeFileHandle.DangerousGetHandle();
            RecordPhase(path, "handles-ready");
            bool written = MiniDumpWriteDump(processHandle, (uint)process.Id, dumpHandle, 0x1124, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            int error = written ? 0 : Marshal.GetLastWin32Error();
            RecordPhase(path, "native-returned:" + error.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (!written) { throw new Win32Exception(error, "MiniDumpWriteDump failed error-code=" + error); }
        }
        RecordPhase(path, "complete");
    }
}
