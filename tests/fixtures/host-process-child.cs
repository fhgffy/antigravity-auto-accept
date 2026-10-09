using System;
using System.Diagnostics;
using System.IO;
using System.Text;

/* 2026-10-09：仅供原生进程身份测试的自有子进程；不依赖 PowerShell 脚本引擎启动。 */
internal static class HostProcessChild
{
    private static void WriteStage(string directory, string name, string protocol, int pid, string nonce)
    {
        byte[] bytes = Encoding.ASCII.GetBytes(protocol + ":" + pid + ":" + nonce + Environment.NewLine);
        using (FileStream file = new FileStream(Path.Combine(directory, name), FileMode.CreateNew, FileAccess.Write, FileShare.Read))
            file.Write(bytes, 0, bytes.Length);
    }

    private static int Main(string[] args)
    {
        if (args.Length != 2) return 1;
        int pid;
        using (Process current = Process.GetCurrentProcess()) pid = current.Id;
        WriteStage(args[0], "entered.stage", "HOST_CHILD_ENTERED", pid, args[1]);
        Console.Error.WriteLine("HOST_CHILD_ENTERED:" + pid);
        Console.OutputEncoding = new UTF8Encoding(false);
        WriteStage(args[0], "encoding-set.stage", "HOST_CHILD_ENCODING_SET", pid, args[1]);
        Console.Error.WriteLine("HOST_CHILD_ENCODING_SET:" + pid);
        Console.WriteLine("READY:" + IntPtr.Size + ":" + pid);
        WriteStage(args[0], "ready-written.stage", "HOST_CHILD_READY_WRITTEN", pid, args[1]);
        Console.Error.WriteLine("HOST_CHILD_READY_WRITTEN:" + pid);
        Console.ReadLine();
        return 259;
    }
}
