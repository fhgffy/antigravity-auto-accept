/* 2026-10-16：只提供包装器的真实子进程输出与停滞边界，不调用桌面输入或生产扫描器。 */
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

internal static class HostWrapperOutput
{
    private static int Main()
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        File.WriteAllText(Environment.GetEnvironmentVariable("AAA_HOST_WRAPPER_PIDFILE"), Process.GetCurrentProcess().Id.ToString());
        string mode = Environment.GetEnvironmentVariable("AAA_HOST_WRAPPER_CASE");
        Console.Out.WriteLine("HOST_WRAPPER_STDOUT:中文诊断");
        if (mode != "missing-done") { Console.Out.WriteLine("___HOST_PROCESS_TEST_DONE___:passed=1"); }
        Console.Out.Flush();
        if (mode == "timeout" || mode == "stderr")
        {
            Console.Error.WriteLine("HOST_WRAPPER_STDERR:partial-error");
            Console.Error.Flush();
        }
        if (mode == "timeout") { Thread.Sleep(120000); }
        return mode == "exit" ? 7 : 0;
    }
}
