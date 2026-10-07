<# 2026-10-07：按实际宿主函数验证路径身份，测试只查询自有进程，不调用任何桌面输入接口。 #>
param([string[]]$PowerShellEngines = @('powershell.exe', 'pwsh.exe'), [string]$ScannerSourcePath = '', [switch]$InProcess)

$ErrorActionPreference = 'Stop'
$scannerPath = if ([string]::IsNullOrWhiteSpace($ScannerSourcePath)) { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1')) } else { [IO.Path]::GetFullPath($ScannerSourcePath) }
if (-not $InProcess) {
    <# 2026-10-07：显式 UTF-8 解析保留文件上下文，同时收集两条输出流，超时只终止本测试持有的子进程。 #>
    $engines = @($PowerShellEngines | ForEach-Object { (Get-Command $_ -ErrorAction Stop).Source } | Select-Object -Unique)
    if ($engines.Count -eq 0) { throw 'No requested PowerShell engine' }
    foreach ($engine in $engines) {
        $testLiteral = $PSCommandPath.Replace("'", "''")
        $scannerLiteral = $scannerPath.Replace("'", "''")
        $command = '$ProgressPreference=''SilentlyContinue''; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); '
        $command += "`$testPath='$testLiteral'; `$tokens=`$null; `$errors=`$null; `$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText(`$testPath,[Text.Encoding]::UTF8),`$testPath,[ref]`$tokens,[ref]`$errors); if (`$errors.Count) { throw 'Host test parse errors' }; & `$ast.GetScriptBlock() -InProcess -ScannerSourcePath '$scannerLiteral'"
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $engine
        $start.Arguments = '-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        [void]$process.Start()
        $pendingOut = $process.StandardOutput.ReadToEndAsync()
        $pendingError = $process.StandardError.ReadToEndAsync()
        try {
            if (-not $process.WaitForExit(45000)) { throw "Host test timeout: $engine" }
            $output = $pendingOut.GetAwaiter().GetResult()
            $errorOutput = $pendingError.GetAwaiter().GetResult()
            Write-Output $output.TrimEnd()
            if ($process.ExitCode -ne 0 -or $errorOutput.Length -gt 0 -or $output -notmatch '___HOST_PROCESS_TEST_DONE___:passed=\d+') { throw "Host test failed: engine=$engine exit=$($process.ExitCode) stderr=$errorOutput" }
            Write-Output "PASS host process engine: $engine"
        }
        finally {
            if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
            $process.Dispose()
        }
    }
    exit 0
}

<# 2026-10-07：仅抽取实际宿主匹配与查询函数，预期 PID 手工指定；路径查询只替最底层依赖。 #>
$source = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, $scannerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Host source parse errors' }
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class HostProcessMapMemory {
    /* 2026-10-07：按 PID 提供当前路径，不让测试回退至 Process.Path 或缓存上轮结果。 */
    public static Dictionary<uint, string> Paths = new Dictionary<uint, string>();
    public static List<uint> Reads = new List<uint>();
    public static HashSet<uint> Failures = new HashSet<uint>();
    public static string GetProcessImagePath(uint processId) {
        Reads.Add(processId);
        if (Failures.Contains(processId)) { throw new InvalidOperationException("Path query denied"); }
        string path;
        return Paths.TryGetValue(processId, out path) ? path : null;
    }
}
'@
foreach ($name in @('Test-HostProcessPath', 'Get-TargetProcessIds')) {
    $definition = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definition.Count -ne 1) { throw "Host function missing: $name" }
    $functionText = $definition[0].Extent.Text.Replace('[MouseHelper]::GetProcessImagePath(', '[HostProcessMapMemory]::GetProcessImagePath(')
    . ([scriptblock]::Create($functionText))
}
function New-HostProcessMemory([int]$ProcessId) {
    <# 2026-10-07：Process.Path 故意模拟跨位数读取失败；保留旧函数红灯替身检测任何全局枚举回退。 #>
    $item = [pscustomobject]@{ Id = $ProcessId; PathReads = 0; DisposeCalls = 0 }
    $item | Add-Member ScriptProperty Path { $this.PathReads++; throw 'MainModule unavailable in host test' }
    $item | Add-Member ScriptMethod Dispose { $this.DisposeCalls++ }
    return $item
}
function Get-Process {
    [CmdletBinding()]
    param([string[]]$Name)
    $script:hostEnumerations++
    return $script:hostProcesses
}
$script:hostEnumerations = 0
$HostExecutablePath = 'F:\IDE\Antigravity IDE.exe'
$script:hostProcesses = @(New-HostProcessMemory 123)
[HostProcessMapMemory]::Paths[123] = $HostExecutablePath
$targetIds = Get-TargetProcessIds 123
if (-not $targetIds.ContainsKey(123)) {
    Write-Output "FAIL valid host: expected-pid=123 actual-count=$($targetIds.Count) process-path-reads=$($script:hostProcesses[0].PathReads) native-path-reads=$([HostProcessMapMemory]::Reads.Count)"
    throw 'Valid host omitted when Process.Path is unavailable'
}
Write-Output 'PASS valid host: expected-pid=123'
$script:checks = 1
<# 2026-10-07：逐项断言手工预期，失败立即退出，成功计数供包装进程与 CI 检查。 #>
function Assert-Host([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL host process: $Name" }
    $script:checks++
}
function Assert-HostMap($Map, [string]$Expected, [string]$Name) {
    $actual = (@($Map.Keys | Sort-Object) -join ',')
    Assert-Host ($actual -ceq $Expected) "$Name expected=$Expected actual=$actual"
    foreach ($key in $Map.Keys) { Assert-Host ($Map[$key] -eq $true) "$Name positive value" }
}
Assert-HostMap $targetIds '123' 'exact current pid'
Assert-Host ($script:hostEnumerations -eq 0 -and $script:hostProcesses[0].PathReads -eq 0) 'no system enumeration or Process.Path'
Assert-Host (([HostProcessMapMemory]::Reads -join ',') -eq '123') 'only window pid queried'
[HostProcessMapMemory]::Paths[123] = 'F:\Different\Antigravity IDE.exe'
Assert-HostMap (Get-TargetProcessIds 123) '' 'same pid changed path rejected'
Assert-Host (([HostProcessMapMemory]::Reads -join ',') -eq '123,123') 'same pid rechecked without cache'
[HostProcessMapMemory]::Paths[124] = 'F:\IDE\Antigravity IDE.exe'
Assert-HostMap (Get-TargetProcessIds 124) '124' 'second matching pid queried individually'
[HostProcessMapMemory]::Paths[125] = 'F:\IDE\Chrome.exe'
Assert-HostMap (Get-TargetProcessIds 125) '' 'different basename rejected'
Assert-HostMap (Get-TargetProcessIds 126) '' 'missing native path rejected'
[void][HostProcessMapMemory]::Failures.Add(127)
Assert-HostMap (Get-TargetProcessIds 127) '' 'native error isolated'
Assert-HostMap (Get-TargetProcessIds 124) '124' 'valid next query after error'
$readCount = [HostProcessMapMemory]::Reads.Count
Assert-HostMap (Get-TargetProcessIds 0) '' 'zero pid rejected'
Assert-HostMap (Get-TargetProcessIds -1) '' 'negative pid rejected'
Assert-Host ([HostProcessMapMemory]::Reads.Count -eq $readCount) 'invalid pid does not query native'
$HostExecutablePath = "F:\中文目录\O'Brien `$IDE\Antigravity IDE.exe"
[HostProcessMapMemory]::Paths[128] = $HostExecutablePath.ToLowerInvariant()
Assert-HostMap (Get-TargetProcessIds 128) '128' 'unicode apostrophe and case matching'
$HostExecutablePath = ''
[HostProcessMapMemory]::Paths[129] = 'G:\Other\Antigravity.exe'
[HostProcessMapMemory]::Paths[130] = 'G:\Other\Antigravity IDE.exe'
[HostProcessMapMemory]::Paths[131] = 'G:\Other\Antigravity IDE.exe.bak'
Assert-HostMap (Get-TargetProcessIds 129) '129' 'unknown expected path supported basename'
Assert-HostMap (Get-TargetProcessIds 130) '130' 'unknown expected path spaced basename'
Assert-HostMap (Get-TargetProcessIds 131) '' 'unknown expected path unsupported basename'
Assert-Host ($script:hostEnumerations -eq 0 -and $script:hostProcesses[0].PathReads -eq 0) 'all map cases avoid enumeration'
Write-Output 'PASS host map: exact PID, fresh path, isolated errors, supported basename'

<# 2026-10-07：先编译完整且未改动的生产 C#；只用其进程 API，鼠标和窗口 API 不参与测试。 #>
$match = [regex]::Match($source, '(?s)Add-Type -TypeDefinition @"\r?\n(.*?)\r?\n"@')
if (-not $match.Success -or -not $match.Groups[1].Value.Contains('public class MouseHelper')) { throw 'Production helper not found' }
$csharp = $match.Groups[1].Value
Add-Type -TypeDefinition $csharp -ErrorAction Stop
Assert-Host ($null -ne [MouseHelper].GetMethod('GetProcessImagePath')) 'production path method compiled'
foreach ($name in @('OpenProcess', 'QueryFullProcessImageNameW', 'WaitForSingleObject', 'CloseHandle')) {
    $method = [MouseHelper].GetMethod($name)
    Assert-Host ($null -ne $method) "native declaration $name"
    $import = @($method.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false))[0]
    Assert-Host ($import.Value -eq 'kernel32.dll' -and $import.SetLastError) "native error contract $name"
    if ($name -eq 'QueryFullProcessImageNameW') { Assert-Host ($import.CharSet -eq [Runtime.InteropServices.CharSet]::Unicode -and $import.ExactSpelling) 'unicode exact process path declaration' }
}

<# 2026-10-07：仅替换四个原生进程边界和最后错误读取，保留真实缓冲、等待和 finally 控制流。 #>
$memoryFields = @'
    /* 2026-10-07：原生替身记录实参和调用顺序；其它原生 API 一旦被调用就失败。 */
    public static List<string> Calls = new List<string>();
    public static List<uint> Sizes = new List<uint>();
    public static List<int> Capacities = new List<int>();
    public static List<uint> WaitValues = new List<uint>();
    public static List<int> QueryErrors = new List<int>();
    public static uint Access, Pid;
    public static bool Inherit, OpenFails, OpenThrows, QueryThrows, WaitThrows, CloseResult;
    public static int Error, OpenCalls, QueryCalls, WaitCalls, CloseCalls, ThrowQueryAt, ThrowWaitAt;
    public static string Image;
    public static IntPtr Handle = new IntPtr(77);
    public static void Reset() {
        Calls.Clear(); Sizes.Clear(); Capacities.Clear(); WaitValues.Clear(); QueryErrors.Clear();
        Access = Pid = 0; Inherit = OpenFails = OpenThrows = QueryThrows = WaitThrows = false;
        Error = OpenCalls = QueryCalls = WaitCalls = CloseCalls = ThrowQueryAt = ThrowWaitAt = 0;
        Image = @"F:\IDE\Antigravity IDE.exe"; CloseResult = true;
    }
    public static int ReadLastError() { return Error; }
'@
$nativeBodies = @{
    OpenProcess = @'
        Calls.Add("open"); OpenCalls++; Access = desiredAccess; Inherit = inheritHandle; Pid = processId;
        if (OpenThrows) { throw new InvalidOperationException("Open failed"); }
        return OpenFails ? IntPtr.Zero : Handle;
'@
    QueryFullProcessImageNameW = @'
        Calls.Add("query"); QueryCalls++; Sizes.Add(size); Capacities.Add(imagePath.Capacity);
        if (process != Handle || flags != 0) { throw new InvalidOperationException("Wrong query arguments"); }
        if (QueryThrows || QueryCalls == ThrowQueryAt) { throw new InvalidOperationException("Query failed"); }
        int code = QueryCalls <= QueryErrors.Count ? QueryErrors[QueryCalls - 1] : 0;
        Error = code;
        if (code != 0) { return false; }
        if (Image.Length + 1 > size) { throw new InvalidOperationException("Insufficient successful buffer"); }
        imagePath.Append(Image); size = (uint)Image.Length; return true;
'@
    WaitForSingleObject = @'
        Calls.Add("wait"); WaitCalls++;
        if (handle != Handle || milliseconds != 0) { throw new InvalidOperationException("Wrong wait arguments"); }
        if (WaitThrows || WaitCalls == ThrowWaitAt) { throw new InvalidOperationException("Wait failed"); }
        return WaitCalls <= WaitValues.Count ? WaitValues[WaitCalls - 1] : 258;
'@
    CloseHandle = @'
        Calls.Add("close"); CloseCalls++;
        if (handle != Handle) { throw new InvalidOperationException("Wrong close handle"); }
        return CloseResult;
'@
}
$declarationPattern = '(?m)^    \[DllImport\([^\r\n]+\)\]\r?\n    public static extern (?<signature>[^\r\n]+);'
$declarations = [regex]::Matches($csharp, $declarationPattern)
$memorySource = $csharp.Replace('using System;', 'using System;' + "`r`nusing System.Collections.Generic;").Replace('public class MouseHelper', 'public class HostProcessNativeMemory')
foreach ($declaration in $declarations) {
    $signature = $declaration.Groups['signature'].Value
    $methodName = [regex]::Match($signature, '(\w+)\(').Groups[1].Value
    $body = if ($nativeBodies.ContainsKey($methodName)) { $nativeBodies[$methodName] } else { '        throw new InvalidOperationException("Unexpected desktop native call: ' + $methodName + '");' }
    $memorySource = $memorySource.Replace($declaration.Value, "    public static $signature {`r`n$body`r`n    }")
}
$memorySource = $memorySource.Replace('Marshal.GetLastWin32Error()', 'ReadLastError()')
$lastBrace = $memorySource.LastIndexOf('}')
$memorySource = $memorySource.Insert($lastBrace, $memoryFields + "`r`n")
Add-Type -TypeDefinition $memorySource -ErrorAction Stop

function Assert-NativeClosed([string]$ExpectedCalls, [string]$Name) {
    Assert-Host ([HostProcessNativeMemory]::CloseCalls -eq 1) "$Name closes exactly once"
    Assert-Host (([HostProcessNativeMemory]::Calls -join ',') -ceq $ExpectedCalls) "$Name native call order"
}
[HostProcessNativeMemory]::Reset()
$path = [HostProcessNativeMemory]::GetProcessImagePath(123)
Assert-Host ($path -ceq 'F:\IDE\Antigravity IDE.exe') 'native ordinary path'
Assert-Host ([HostProcessNativeMemory]::Access -eq 0x101000 -and -not [HostProcessNativeMemory]::Inherit -and [HostProcessNativeMemory]::Pid -eq 123) 'limited query synchronize and noninherited pid'
Assert-Host (([HostProcessNativeMemory]::Sizes -join ',') -eq '512' -and ([HostProcessNativeMemory]::Capacities -join ',') -eq '512') 'ordinary buffer 512'
Assert-NativeClosed 'open,wait,query,wait,close' 'ordinary path'
[HostProcessNativeMemory]::Reset()
Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(0)) 'native zero pid rejected'
Assert-Host ([HostProcessNativeMemory]::Calls.Count -eq 0) 'zero pid no native calls'
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::OpenFails = $true
Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(999)) 'unavailable process rejected'
Assert-Host (([HostProcessNativeMemory]::Calls -join ',') -eq 'open' -and [HostProcessNativeMemory]::CloseCalls -eq 0) 'zero handle never closed'
foreach ($wait in @([uint32]0, [uint32]128, [uint32]259, [uint32]4294967295)) {
    [HostProcessNativeMemory]::Reset()
    [HostProcessNativeMemory]::WaitValues.Add($wait)
    Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(123)) "prequery wait rejects $wait"
    Assert-NativeClosed 'open,wait,close' "prequery wait $wait"
    [HostProcessNativeMemory]::Reset()
    [HostProcessNativeMemory]::WaitValues.Add(258)
    [HostProcessNativeMemory]::WaitValues.Add($wait)
    Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(123)) "postquery wait rejects $wait"
    Assert-NativeClosed 'open,wait,query,wait,close' "postquery wait $wait"
}
foreach ($code in @(5, 87, 299)) {
    [HostProcessNativeMemory]::Reset()
    [HostProcessNativeMemory]::QueryErrors.Add($code)
    Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(123)) "query error rejected $code"
    Assert-Host ([HostProcessNativeMemory]::QueryCalls -eq 1) "no retry for error $code"
    Assert-NativeClosed 'open,wait,query,close' "query error $code"
}
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::Image = 'F:\' + ('长' * 800) + '\Antigravity IDE.exe'
$longExpected = 'F:\' + ('长' * 800) + '\Antigravity IDE.exe'
[HostProcessNativeMemory]::QueryErrors.Add(122)
Assert-Host ([HostProcessNativeMemory]::GetProcessImagePath(123) -ceq $longExpected) 'long unicode path retry success'
Assert-Host (([HostProcessNativeMemory]::Sizes -join ',') -eq '512,32768' -and ([HostProcessNativeMemory]::Capacities -join ',') -eq '512,32768') '122 retry uses 32768 once'
Assert-NativeClosed 'open,wait,query,query,wait,close' 'long path'
foreach ($code in @(122, 5)) {
    [HostProcessNativeMemory]::Reset()
    [HostProcessNativeMemory]::QueryErrors.Add(122)
    [HostProcessNativeMemory]::QueryErrors.Add($code)
    Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(123)) "retry failure $code rejected"
    Assert-Host ([HostProcessNativeMemory]::QueryCalls -eq 2) "retry bounded for error $code"
    Assert-NativeClosed 'open,wait,query,query,close' "retry error $code"
}
foreach ($boundary in @('QueryThrows', 'WaitThrows')) {
    [HostProcessNativeMemory]::Reset()
    [HostProcessNativeMemory].GetField($boundary).SetValue($null, $true)
    $thrown = $false
    try { [void][HostProcessNativeMemory]::GetProcessImagePath(123) } catch { $thrown = $true }
    Assert-Host $thrown "$boundary exception propagated"
    Assert-Host ([HostProcessNativeMemory]::CloseCalls -eq 1 -and [HostProcessNativeMemory]::Calls[[HostProcessNativeMemory]::Calls.Count - 1] -eq 'close') "$boundary finally close"
}
<# 2026-10-07：重试查询及返回前等待发生异常时，也必须经过同一句柄的 finally 关闭。 #>
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::QueryErrors.Add(122)
[HostProcessNativeMemory]::ThrowQueryAt = 2
$thrown = $false
try { [void][HostProcessNativeMemory]::GetProcessImagePath(123) } catch { $thrown = $true }
Assert-Host $thrown 'retry query exception propagated'
Assert-NativeClosed 'open,wait,query,query,close' 'retry query exception'
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::ThrowWaitAt = 2
$thrown = $false
try { [void][HostProcessNativeMemory]::GetProcessImagePath(123) } catch { $thrown = $true }
Assert-Host $thrown 'postquery wait exception propagated'
Assert-NativeClosed 'open,wait,query,wait,close' 'postquery wait exception'
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::QueryErrors.Add(122)
[HostProcessNativeMemory]::WaitValues.Add(258)
[HostProcessNativeMemory]::WaitValues.Add(0)
Assert-Host ($null -eq [HostProcessNativeMemory]::GetProcessImagePath(123)) 'exit during long path retry rejected'
Assert-NativeClosed 'open,wait,query,query,wait,close' 'exit during retry'
[HostProcessNativeMemory]::Reset()
[HostProcessNativeMemory]::OpenThrows = $true
$thrown = $false
try { [void][HostProcessNativeMemory]::GetProcessImagePath(123) } catch { $thrown = $true }
Assert-Host ($thrown -and [HostProcessNativeMemory]::CloseCalls -eq 0) 'open exception never closes nonexistent handle'
Write-Output 'PASS native process flow: access, wait before/after, buffer retry, finally close'

<# 2026-10-07：真实验证当前进程及本测试启动的两个位数子进程；退出码 259 仍必须拒绝。 #>
$current = [Diagnostics.Process]::GetCurrentProcess()
try {
    $expectedCurrentPath = $current.MainModule.FileName
    Assert-Host ([MouseHelper]::GetProcessImagePath([uint32]$current.Id) -ieq $expectedCurrentPath) 'real current process path'
}
finally { $current.Dispose() }
Assert-Host ($null -eq [MouseHelper]::GetProcessImagePath(0)) 'real zero pid rejected'
Assert-Host ($null -eq [MouseHelper]::GetProcessImagePath([uint32]4294967295)) 'real nonexistent pid rejected'
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Cross-bitness test requires Windows x64' }
$system32 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$native64 = if ([IntPtr]::Size -eq 4) { Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' } else { $system32 }
$native32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
foreach ($fixture in @(@{ Engine = $native64; Expected = $system32; Bits = 8 }, @{ Engine = $native32; Expected = $native32; Bits = 4 })) {
    if (-not [IO.File]::Exists($fixture.Engine)) { throw "Owned child engine missing: $($fixture.Engine)" }
    $childCommand = '[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::WriteLine("READY:"+[IntPtr]::Size+":"+$PID); [void][Console]::ReadLine(); exit 259'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $fixture.Engine
    $start.Arguments = '-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $child = New-Object Diagnostics.Process
    $child.StartInfo = $start
    $retained = [IntPtr]::Zero
    try {
        if (-not $child.Start()) { throw 'Owned child did not start' }
        $pendingReady = $child.StandardOutput.ReadLineAsync()
        $pendingError = $child.StandardError.ReadToEndAsync()
        if (-not $pendingReady.Wait(10000)) { throw 'Owned child ready timeout' }
        $ready = $pendingReady.GetAwaiter().GetResult()
        $pendingTail = $child.StandardOutput.ReadToEndAsync()
        Assert-Host ($ready -ceq "READY:$($fixture.Bits):$($child.Id)") 'owned child actual bitness and pid'
        $retained = [MouseHelper]::OpenProcess(0x101000, $false, [uint32]$child.Id)
        Assert-Host ($retained -ne [IntPtr]::Zero) 'owned child retained native handle'
        Assert-Host ([MouseHelper]::WaitForSingleObject($retained, 0) -eq 258) 'owned child alive wait timeout'
        Assert-Host ([MouseHelper]::GetProcessImagePath([uint32]$child.Id) -ieq $fixture.Expected) 'owned child native path cross bitness'
        $child.StandardInput.WriteLine('finish')
        $child.StandardInput.Flush()
        if (-not $child.WaitForExit(10000)) { throw 'Owned child exit timeout' }
        Assert-Host ($child.ExitCode -eq 259) 'owned child normal exit 259'
        Assert-Host ([MouseHelper]::WaitForSingleObject($retained, 0) -eq 0) 'owned exited child handle signaled'
        Assert-Host ($null -eq [MouseHelper]::GetProcessImagePath([uint32]$child.Id)) 'owned exited 259 child rejected with retained handle'
        Assert-Host ($pendingTail.GetAwaiter().GetResult().Length -eq 0 -and $pendingError.GetAwaiter().GetResult().Length -eq 0) 'owned child output streams complete'
        Write-Output "PASS owned child: caller=$([IntPtr]::Size * 8) child=$($fixture.Bits * 8) alive-path=yes exited-259=rejected"
    }
    finally {
        if ($retained -ne [IntPtr]::Zero) { [void][MouseHelper]::CloseHandle($retained) }
        try { if (-not $child.HasExited) { $child.Kill(); [void]$child.WaitForExit(5000) } } catch { }
        $child.Dispose()
    }
}
Write-Output "___HOST_PROCESS_TEST_DONE___:passed=$script:checks"
