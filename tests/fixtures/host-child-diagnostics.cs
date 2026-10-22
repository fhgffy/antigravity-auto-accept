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

    /* 2026-10-22：显式解析系统目录的库及导出，区分首次加载与后续原转储调用，不改变原五秒期限。 */
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

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
            /* 2026-10-22：独立收集器只写一次，加载引用由其进程退出释放；原P/Invoke和完整标志保持原样。 */
            RecordPhase(path, "dbghelp-load-entered");
            IntPtr module = LoadLibraryExW("dbghelp.dll", IntPtr.Zero, 0x800);
            int loadError = module == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
            RecordPhase(path, "dbghelp-load-returned:" + loadError.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (module == IntPtr.Zero) { throw new Win32Exception(loadError, "System dump library load failed error-code=" + loadError); }
            RecordPhase(path, "dbghelp-export-entered");
            IntPtr address = GetProcAddress(module, "MiniDumpWriteDump");
            int exportError = address == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
            RecordPhase(path, "dbghelp-export-returned:" + exportError.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (address == IntPtr.Zero) { throw new Win32Exception(exportError, "System dump export resolve failed error-code=" + exportError); }
            bool written = MiniDumpWriteDump(processHandle, (uint)process.Id, dumpHandle, 0x1124, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            int error = written ? 0 : Marshal.GetLastWin32Error();
            RecordPhase(path, "native-returned:" + error.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (!written) { throw new Win32Exception(error, "MiniDumpWriteDump failed error-code=" + error); }
        }
        RecordPhase(path, "complete");
    }
}
