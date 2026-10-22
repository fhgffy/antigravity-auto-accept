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

    /* 2026-10-22：旁路只读已超时的自有收集器；同位数寄存器取证不依赖可能同样停滞的DbgHelp。 */
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenThread(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint GetProcessIdOfThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint SuspendThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetThreadContext(IntPtr thread, IntPtr context);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool IsWow64Process(IntPtr process, out bool wow64);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr handle);

    /* 2026-10-22：阶段文件只作最佳努力旁证；缺失代表未观测，不能改变原取证结果或期限。 */
    internal static void RecordPhase(string path, string phase)
    {
        try { File.AppendAllText(path + ".phases.log", DateTime.UtcNow.ToString("o") + " " + phase + Environment.NewLine, new System.Text.UTF8Encoding(false)); }
        catch { }
    }

    /* 2026-10-22：先落原始寄存器和至多一页栈，再做原最小转储；每次只暂停一条已核对归属的线程并在finally恢复。
       CONTEXT按微软winnt.h的x64/x86布局取控制及整数部分，16字节对齐；不改寄存器、不解码或执行目标内存。 */
    private static void WriteCollectorContext(Process process, string path)
    {
        bool wow64;
        if (!IsWow64Process(process.Handle, out wow64)) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (Environment.Is64BitOperatingSystem && wow64 != (IntPtr.Size == 4)) throw new InvalidOperationException("Collector context bitness mismatch");
        int size = IntPtr.Size == 8 ? 1232 : 716;
        int flagsOffset = IntPtr.Size == 8 ? 48 : 0;
        int ipOffset = IntPtr.Size == 8 ? 248 : 184;
        int spOffset = IntPtr.Size == 8 ? 152 : 196;
        Stopwatch budget = Stopwatch.StartNew();
        using (StreamWriter writer = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read), new System.Text.UTF8Encoding(false)))
        {
            writer.AutoFlush = true;
            writer.WriteLine("AAA_CONTEXT\t1\t" + IntPtr.Size + "\t" + process.Id + "\t" + process.StartTime.ToUniversalTime().Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture));
            int count = 0;
            foreach (ProcessThread target in process.Threads)
            {
                if (count >= 16 || budget.ElapsedMilliseconds >= 400) break; // 2026-10-22：原附加工具1.5秒预算不变，旁证明确有界。
                IntPtr thread = IntPtr.Zero, memory = IntPtr.Zero;
                uint suspended = uint.MaxValue;
                byte[] context = new byte[size], stack = null;
                ulong ip = 0, sp = 0;
                int readError = 0;
                try
                {
                    if (process.HasExited) break;
                    thread = OpenThread(0x4A, false, (uint)target.Id);
                    if (thread == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                    if (GetProcessIdOfThread(thread) != (uint)process.Id) throw new InvalidOperationException("Collector thread owner changed");
                    memory = Marshal.AllocHGlobal(size + 15);
                    IntPtr aligned = new IntPtr((memory.ToInt64() + 15) & ~15L);
                    Marshal.Copy(context, 0, aligned, size);
                    Marshal.WriteInt32(aligned, flagsOffset, IntPtr.Size == 8 ? 0x100003 : 0x10003);
                    suspended = SuspendThread(thread);
                    if (suspended == uint.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                    if (!GetThreadContext(thread, aligned)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    Marshal.Copy(aligned, context, 0, size);
                    ip = IntPtr.Size == 8 ? BitConverter.ToUInt64(context, ipOffset) : BitConverter.ToUInt32(context, ipOffset);
                    sp = IntPtr.Size == 8 ? BitConverter.ToUInt64(context, spOffset) : BitConverter.ToUInt32(context, spOffset);
                    byte[] page = new byte[4096 - (int)(sp & 4095)];
                    UIntPtr read;
                    bool copied = ReadProcessMemory(process.Handle, IntPtr.Size == 8 ? new IntPtr((long)sp) : new IntPtr(unchecked((int)sp)), page, new UIntPtr((uint)page.Length), out read);
                    readError = copied ? 0 : Marshal.GetLastWin32Error();
                    int length = checked((int)read.ToUInt64());
                    if (length < 0 || length > page.Length) throw new InvalidOperationException("Collector stack length invalid");
                    stack = new byte[length]; Buffer.BlockCopy(page, 0, stack, 0, length);
                }
                finally
                {
                    // 2026-10-22：只撤销本次增加的一层暂停；即便读栈失败也先恢复，再释放句柄/缓冲区和写文件。
                    uint resumed = suspended == uint.MaxValue ? 0 : ResumeThread(thread);
                    int resumeError = resumed == uint.MaxValue ? Marshal.GetLastWin32Error() : 0;
                    if (thread != IntPtr.Zero) CloseHandle(thread);
                    if (memory != IntPtr.Zero) Marshal.FreeHGlobal(memory);
                    if (resumeError != 0) throw new Win32Exception(resumeError, "Collector thread resume failed");
                }
                writer.WriteLine("T\t" + target.Id + "\t" + ip.ToString("x") + "\t" + sp.ToString("x") + "\t" + Convert.ToBase64String(context) + "\t" + Convert.ToBase64String(stack) + "\t" + readError);
                count++;
            }
            foreach (ProcessModule module in process.Modules)
            {
                ulong address = IntPtr.Size == 8 ? unchecked((ulong)module.BaseAddress.ToInt64()) : unchecked((uint)module.BaseAddress.ToInt32());
                writer.WriteLine("M\t" + address.ToString("x") + "\t" + module.ModuleMemorySize + "\t" + Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(module.FileName)));
            }
            writer.WriteLine("END\t" + count + "\t" + budget.ElapsedMilliseconds);
        }
    }

    /* 2026-10-22：原收集器已超过期限后，仅为它自身写最小栈；不替换原目标的完整转储或延长其五秒判定。 */
    public static void WriteCollectorStack(Process process, string path)
    {
        RecordPhase(path, "collector-stack-entered");
        if (process == null || process.HasExited) throw new InvalidOperationException("Owned collector is not alive");
        try { WriteCollectorContext(process, path + ".context.tsv"); }
        catch (Exception error) { RecordPhase(path, "collector-context-error:" + error.GetType().FullName); } // 2026-10-22：旁证失败不跳过原最小转储。
        using (FileStream file = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read))
        {
            IntPtr module = LoadLibraryExW("dbghelp.dll", IntPtr.Zero, 0x800);
            int loadError = module == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
            if (module == IntPtr.Zero) throw new Win32Exception(loadError, "Collector stack library load failed");
            bool written = MiniDumpWriteDump(process.Handle, (uint)process.Id, file.SafeFileHandle.DangerousGetHandle(), 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            int error = written ? 0 : Marshal.GetLastWin32Error();
            RecordPhase(path, "collector-stack-returned:" + error.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (!written) throw new Win32Exception(error, "Collector stack write failed");
        }
        RecordPhase(path, "complete");
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
