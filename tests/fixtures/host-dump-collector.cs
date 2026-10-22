/* 2026-10-22：预编译的独占64位取证进程，只读取同PID、同.NET创建时间与同绝对路径的持有目标。 */
using System;
using System.Diagnostics;
using System.Globalization;
using System.Text;

internal static class HostDumpCollector
{
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.SetError(new System.IO.StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false)) { AutoFlush = true });
        try
        {
            /* 2026-10-22：附加模式只接受明确标志，仍核验同一持有进程的PID、创建时间和绝对路径。 */
            bool collectorStack = args.Length == 5 && args[4] == "--collector-stack";
            /* 2026-10-22：可选编译的同位数工具为x86目标保留原生上下文；默认x64工具及身份核验不变。 */
#if OWNED_X86_COLLECTOR
            if (IntPtr.Size != 4 || (args.Length != 4 && !collectorStack)) { throw new InvalidOperationException("Expected x86 owned collector arguments"); }
#else
            if (IntPtr.Size != 8 || (args.Length != 4 && !collectorStack)) { throw new InvalidOperationException("Expected x64 owned collector arguments"); }
#endif
            HostChildDiagnostics.RecordPhase(args[3], "collector-entered"); // 2026-10-22：身份失败前的工具进入阶段单独保留。
            int pid = int.Parse(args[0], CultureInfo.InvariantCulture);
            long started = long.Parse(args[1], CultureInfo.InvariantCulture);
            using (Process target = Process.GetProcessById(pid))
            {
                if (target.StartTime.ToUniversalTime().Ticks != started ||
                    !string.Equals(target.MainModule.FileName, args[2], StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Owned dump target identity changed");
                }
                HostChildDiagnostics.RecordPhase(args[3], "identity-verified"); // 2026-10-22：只有严格身份通过后才进入取证函数。
                if (collectorStack) HostChildDiagnostics.WriteCollectorStack(target, args[3]); // 2026-10-22：仅超时收集器的旁路最小栈。
                else HostChildDiagnostics.Write(target, args[3]);
            }
            Console.WriteLine(collectorStack ? "___HOST_COLLECTOR_STACK_WRITTEN___" : "___HOST_DUMP_WRITTEN___"); // 2026-10-22：不混淆两种取证回执。
            return 0;
        }
        catch (Exception error)
        {
            Exception cause = error.GetBaseException();
            Console.Error.WriteLine(cause.GetType().FullName + ":" + cause.Message);
            return 1;
        }
    }
}
