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
            if (IntPtr.Size != 8 || args.Length != 4) { throw new InvalidOperationException("Expected x64 owned collector arguments"); }
            int pid = int.Parse(args[0], CultureInfo.InvariantCulture);
            long started = long.Parse(args[1], CultureInfo.InvariantCulture);
            using (Process target = Process.GetProcessById(pid))
            {
                if (target.StartTime.ToUniversalTime().Ticks != started ||
                    !string.Equals(target.MainModule.FileName, args[2], StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Owned dump target identity changed");
                }
                HostChildDiagnostics.Write(target, args[3]);
            }
            Console.WriteLine("___HOST_DUMP_WRITTEN___");
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
