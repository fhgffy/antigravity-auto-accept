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
        # 2026-10-16：单独标记原四十五秒超时，finally 保留旁证时不能覆盖原失败。
        $timedOut = $false
        try {
            $timedOut = -not $process.WaitForExit(45000)
            if ($timedOut) { throw "Host test timeout: $engine" }
            $output = $pendingOut.GetAwaiter().GetResult()
            $errorOutput = $pendingError.GetAwaiter().GetResult()
            Write-Output $output.TrimEnd()
            if ($process.ExitCode -ne 0 -or $errorOutput.Length -gt 0 -or $output -notmatch '___HOST_PROCESS_TEST_DONE___:passed=\d+') { throw "Host test failed: engine=$engine exit=$($process.ExitCode) stderr=$errorOutput" }
            Write-Output "PASS host process engine: $engine"
        }
        finally {
            # 2026-10-16：超时只停止持有的子进程，有限收集已写输出；读取或清理失败仍保留原超时。
            if ($timedOut) {
                $diagnostic = [ordered]@{ Pid = $process.Id; ExitConfirmed = $false; StdoutComplete = $false; StderrComplete = $false; Stdout = $null; Stderr = $null; StopError = ''; ReadError = ''; DisposeError = '' }
                try {
                    if (-not $process.HasExited) { $process.Kill() }
                    $diagnostic.ExitConfirmed = $process.WaitForExit(5000)
                } catch { $diagnostic.StopError = $_.Exception.GetType().FullName }
                foreach ($stream in @(@{ Name = 'Stdout'; Task = $pendingOut }, @{ Name = 'Stderr'; Task = $pendingError })) {
                    try {
                        if ($stream.Task.Wait(1000)) {
                            $diagnostic[$stream.Name] = $stream.Task.GetAwaiter().GetResult()
                            $diagnostic[$stream.Name + 'Complete'] = $true
                        }
                    } catch { $diagnostic.ReadError += $stream.Name + ':' + $_.Exception.GetType().FullName + ';' }
                }
                try { $process.Dispose() } catch { $diagnostic.DisposeError = $_.Exception.GetType().FullName }
                try { [Console]::WriteLine('___HOST_WRAPPER_TIMEOUT___:' + ($diagnostic | ConvertTo-Json -Compress)) } catch { }
            } else {
                if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
                $process.Dispose()
            }
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
# 2026-10-07：桩字段只插入顶层 MouseHelper 类；完整原生契约仍先按生产文本编译。
$mouseClassSource = [regex]::Match($csharp, '(?s)\A.*?public class MouseHelper\s*\{.*?\r?\n\}').Value
if ([string]::IsNullOrWhiteSpace($mouseClassSource)) { throw 'MouseHelper class boundary missing' }
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
$declarations = [regex]::Matches($mouseClassSource, $declarationPattern)
$memorySource = $mouseClassSource.Replace('using System;', 'using System;' + "`r`nusing System.Collections.Generic;").Replace('public class MouseHelper', 'public class HostProcessNativeMemory')
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

<# 2026-10-08：旁证只读取本例三个精确路径与有限字节；只有 PID/nonce 整行匹配才证明到达阶段。 #>
function Read-HostChildStage([string]$OwnedDirectory, [string]$Stage, [string]$StagePath, [string]$ExpectedLine) {
    $result = [pscustomobject]@{ Stage = $Stage; Exists = $null; Complete = $false; State = 'unknown'; Length = $null; ReadError = '' }
    $stream = $null
    $validated = $false
    try {
        $directory = [IO.Path]::GetFullPath($OwnedDirectory)
        $path = [IO.Path]::GetFullPath($StagePath)
        $name = switch ($Stage) { 'ENTERED' { 'entered.stage' }; 'ENCODING_SET' { 'encoding-set.stage' }; 'READY_WRITTEN' { 'ready-written.stage' }; default { throw 'Unknown owned child stage' } }
        if (-not [IO.Path]::IsPathRooted($OwnedDirectory) -or -not [IO.Path]::IsPathRooted($StagePath) -or
            -not [String]::Equals([IO.Path]::GetDirectoryName($path), $directory, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($path) -cne $name) { throw 'Owned stage path escaped directory' }
        $expected = [Text.Encoding]::ASCII.GetBytes($ExpectedLine)
        if ($expected.Length -eq 0 -or $expected.Length -gt 256) { throw 'Owned stage line size invalid' }
        $validated = $true
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $result.Exists = $true
        $buffer = New-Object byte[] ($expected.Length + 1)
        $count = 0
        while ($count -lt $buffer.Length) {
            $read = $stream.Read($buffer, $count, $buffer.Length - $count)
            if ($read -eq 0) { break }
            $count += $read
        }
        $result.Length = $stream.Length
        $observed = [Text.Encoding]::ASCII.GetString($buffer, 0, $count)
        if ($count -eq $expected.Length -and $result.Length -eq $expected.Length -and $observed -ceq $ExpectedLine) {
            $result.Complete = $true; $result.State = 'complete'
        } elseif ($result.Length -gt $expected.Length -or $count -gt $expected.Length) { $result.State = 'extra' }
        elseif ($count -lt $expected.Length -and $ExpectedLine.StartsWith($observed, [StringComparison]::Ordinal)) { $result.State = 'partial' }
        else { $result.State = 'mismatch' }
    } catch {
        # 2026-10-08：只按本次实际异常归类；路径守卫失败或其他读取错误不能被误记为 missing。
        $stageException = $_.Exception.GetBaseException()
        if ($validated -and ($stageException -is [IO.FileNotFoundException] -or $stageException -is [IO.DirectoryNotFoundException])) {
            $result.Exists = $false; $result.State = 'missing'
        } else { $result.State = if ($validated) { 'read-error' } else { 'ownership-error' }; $result.ReadError = $_.Exception.GetType().FullName }
    }
    finally {
        if ($null -ne $stream) {
            try { $stream.Dispose() } catch { $result.Complete = $false; $result.State = 'read-error'; $result.ReadError = $_.Exception.GetType().FullName }
        }
    }
    return $result
}

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
# 2026-10-22：外部64位收集器只读取持有目标；固定五秒上限和独立回收，不能占满原45秒宿主截止时间。
function Save-HostTimeoutDump {
    # 2026-10-23：默认不改收集器模式；原生x86控制显式要求真实EXE的JIT回执。
    param([Diagnostics.Process]$Target,[string]$ExpectedImage,[string]$DumpPath,[string]$CollectorEngine='',[switch]$ExecutableCollector,[string]$CollectorStackTool='',[switch]$CollectorJit) # 2026-10-22：仅失败后的可选旁路工具。
    # 2026-10-22：此回执只有固定的字符串/整数/布尔字段，直接编码避免首次ConvertTo-Json自动加载阻塞取证收尾。
    function ConvertTo-DumpJsonString([string]$Value) {
        $text = [Text.StringBuilder]::new()
        [void]$text.Append('"')
        foreach ($character in $Value.ToCharArray()) {
            $code = [int]$character
            if ($code -eq 34 -or $code -eq 92) { [void]$text.Append('\'); [void]$text.Append($character) }
            elseif ($code -lt 32 -or $code -ge 127) { [void]$text.Append('\u'); [void]$text.Append($code.ToString('x4',[Globalization.CultureInfo]::InvariantCulture)) }
            else { [void]$text.Append($character) }
        }
        [void]$text.Append('"')
        return $text.ToString()
    }
    $record=[ordered]@{Pid=$Target.Id;Path=$DumpPath;Written=$false;TimedOut=$false;Error='';CollectorPid=$null;CollectorExited=$false}
    $collector=$null;$started=$false
    try {
        if([string]::IsNullOrWhiteSpace($CollectorEngine)){$CollectorEngine=[IO.Path]::Combine($env:ProgramW6432,'PowerShell\7\pwsh.exe')} # 2026-10-22：默认路径不依赖命令模块冷加载。
        $source=[IO.Path]::Combine($PSScriptRoot,'fixtures\host-child-diagnostics.cs') # 2026-10-22：原生EXE分支也能在禁止自动加载时建立相同源路径。
        $command='$ErrorActionPreference=''Stop''; if([IntPtr]::Size -ne 8){throw ''Dump collector requires x64''}; $p=[Diagnostics.Process]::GetProcessById('+ $Target.Id +'); try { if($p.StartTime.ToUniversalTime().Ticks -ne '+$Target.StartTime.ToUniversalTime().Ticks+' -or -not [String]::Equals($p.MainModule.FileName,'''+$ExpectedImage.Replace("'","''")+''',[StringComparison]::OrdinalIgnoreCase)){throw ''Owned dump target identity changed''}; Add-Type -TypeDefinition ([IO.File]::ReadAllText('''+$source.Replace("'","''")+''',[Text.Encoding]::UTF8)); [HostChildDiagnostics]::Write($p,'''+$DumpPath.Replace("'","''")+'''); [Console]::WriteLine(''___HOST_DUMP_WRITTEN___'') } finally {$p.Dispose()}'
        $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$CollectorEngine
        $start.Arguments='-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        # 2026-10-22：独立预编译测试工具通过普通参数接收同一目标身份，五秒期限内无需启动PowerShell及现场编译。
        if($ExecutableCollector){
            if($ExpectedImage.Contains('"') -or $DumpPath.Contains('"')){throw 'Invalid owned collector path'}
            $start.Arguments=$Target.Id.ToString([Globalization.CultureInfo]::InvariantCulture)+' '+$Target.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)+' "'+$ExpectedImage+'" "'+$DumpPath+'"'
            if($CollectorJit){$start.Arguments+=' --require-jit'} # 2026-10-23：该标志只交给自有EXE，不追加给EncodedCommand分支。
        }
        # 2026-10-23：只改变本次自有收集器的启动环境，不向当前pwsh或其它测试进程传播。
        if($CollectorJit){$start.EnvironmentVariables['COMPlus_ZapDisable']='1'}
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $collector=[Diagnostics.Process]::new();$collector.StartInfo=$start
        if(-not $collector.Start()){throw 'Dump collector did not start'}
        $started=$true;$record.CollectorPid=$collector.Id
        $output=$collector.StandardOutput.ReadToEndAsync();$errors=$collector.StandardError.ReadToEndAsync()
        if(-not $collector.WaitForExit(5000)){
            $record.TimedOut=$true
            # 2026-10-22：原失败已成立，最多再用1.5秒取超时收集器自身的最小栈；不递归、不改原回执或目标存活状态。
            if(-not [string]::IsNullOrWhiteSpace($CollectorStackTool)){
                $secondary=$null;$secondaryStarted=$false;$stackClock=[Diagnostics.Stopwatch]::StartNew()
                $stackRecord=[ordered]@{Pid=$collector.Id;StartTicks='';Image='';Written=$false;TimedOut=$false;ExitConfirmed=$false;Error='';ElapsedMs=0;Stdout='';Stderr=''}
                try {
                    $stackRecord.StartTicks=$collector.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
                    $stackRecord.Image=[IO.Path]::GetFullPath($CollectorEngine) # 2026-10-22：32位调用者不能读64位MainModule；工具仍独立核验真实路径。
                    if($stackRecord.Image.Contains('"') -or $DumpPath.Contains('"')){throw 'Invalid owned stack path'}
                    $stackStart=[Diagnostics.ProcessStartInfo]::new();$stackStart.FileName=$CollectorStackTool
                    $stackStart.Arguments=$stackRecord.Pid.ToString([Globalization.CultureInfo]::InvariantCulture)+' '+$stackRecord.StartTicks+' "'+$stackRecord.Image+'" "'+$DumpPath+'.collector.dmp" --collector-stack'
                    if($CollectorJit){$stackStart.Arguments+=' --require-jit'} # 2026-10-23：次级取证也必须验证相同运行模式。
                    # 2026-10-23：次级自有收集器也使用同一局部模式，仍受原1.5秒独立预算约束。
                    if($CollectorJit){$stackStart.EnvironmentVariables['COMPlus_ZapDisable']='1'}
                    $stackStart.UseShellExecute=$false;$stackStart.CreateNoWindow=$true;$stackStart.RedirectStandardOutput=$true;$stackStart.RedirectStandardError=$true
                    $secondary=[Diagnostics.Process]::new();$secondary.StartInfo=$stackStart
                    if(-not $secondary.Start()){throw 'Collector stack tool did not start'}
                    $secondaryStarted=$true
                    $stackOut=$secondary.StandardOutput.ReadToEndAsync();$stackErr=$secondary.StandardError.ReadToEndAsync()
                    if(-not $secondary.WaitForExit([Math]::Max(0,1000-[int]$stackClock.ElapsedMilliseconds))){$stackRecord.TimedOut=$true;throw 'Collector stack deadline expired'}
                    if(-not $stackOut.Wait([Math]::Max(0,1200-[int]$stackClock.ElapsedMilliseconds)) -or -not $stackErr.Wait([Math]::Max(0,1200-[int]$stackClock.ElapsedMilliseconds))){throw 'Collector stack streams incomplete'}
                    $stackRecord.Stdout=$stackOut.GetAwaiter().GetResult();$stackRecord.Stderr=$stackErr.GetAwaiter().GetResult()
                    if($secondary.ExitCode -ne 0 -or $stackRecord.Stderr.Length -ne 0 -or $stackRecord.Stdout.Trim() -cne '___HOST_COLLECTOR_STACK_WRITTEN___'){throw 'Collector stack tool failed'}
                    $stackRecord.Written=$true
                } catch {$stackRecord.Error=$_.Exception.GetBaseException().GetType().FullName+':'+$_.Exception.GetBaseException().Message}
                finally {
                    if($null -ne $secondary){
                        if($secondaryStarted){try{if(-not $secondary.get_HasExited()){$secondary.Kill()};$stackRecord.ExitConfirmed=$secondary.WaitForExit([Math]::Max(0,1500-[int]$stackClock.ElapsedMilliseconds))}catch{$stackRecord.Error+=';cleanup:'+ $_.Exception.GetType().FullName}}
                        try{$secondary.Dispose()}catch{$stackRecord.Error+=';dispose:'+ $_.Exception.GetType().FullName}
                    }
                    $stackRecord.ElapsedMs=$stackClock.ElapsedMilliseconds
                    try {
                        $stackJson='{"Pid":'+$stackRecord.Pid.ToString([Globalization.CultureInfo]::InvariantCulture)+',"StartTicks":'+(ConvertTo-DumpJsonString $stackRecord.StartTicks)+',"Image":'+(ConvertTo-DumpJsonString $stackRecord.Image)+',"Written":'+$stackRecord.Written.ToString().ToLowerInvariant()+',"TimedOut":'+$stackRecord.TimedOut.ToString().ToLowerInvariant()+',"ExitConfirmed":'+$stackRecord.ExitConfirmed.ToString().ToLowerInvariant()+',"Error":'+(ConvertTo-DumpJsonString $stackRecord.Error)+',"ElapsedMs":'+$stackRecord.ElapsedMs.ToString([Globalization.CultureInfo]::InvariantCulture)+',"Stdout":'+(ConvertTo-DumpJsonString $stackRecord.Stdout)+',"Stderr":'+(ConvertTo-DumpJsonString $stackRecord.Stderr)+'}'
                        [IO.File]::WriteAllText($DumpPath+'.collector.json',$stackJson,[Text.UTF8Encoding]::new($false))
                    } catch { }
                }
            }
            throw 'Dump collector deadline expired'
        }
        if(-not $output.Wait(1000) -or -not $errors.Wait(1000)){throw 'Dump collector streams incomplete'}
        $outText=$output.GetAwaiter().GetResult();$errText=$errors.GetAwaiter().GetResult()
        if($collector.ExitCode -ne 0 -or $errText.Length -ne 0 -or $outText.Trim() -cne '___HOST_DUMP_WRITTEN___'){throw ('Dump collector failed: '+$errText.Trim())}
        $record.Written=$true
    } catch {$cause=$_.Exception.GetBaseException();$record.Error=$cause.GetType().FullName+':'+$cause.Message}
    finally {
        if($null -ne $collector){
            if($started){try{if(-not $collector.get_HasExited()){$collector.Kill()};$record.CollectorExited=$collector.WaitForExit(1000)}catch{$record.Error+=';cleanup:'+ $_.Exception.GetType().FullName}}
            try{$collector.Dispose()}catch{$record.Error+=';dispose:'+ $_.Exception.GetType().FullName}
        }
        # 2026-10-22：保留原JSON字段与null语义；字符串包含控制字符或UTF-16代理对也须按原文往返。
        try {
            $collectorPidJson = if ($null -eq $record.CollectorPid) { 'null' } else { $record.CollectorPid.ToString([Globalization.CultureInfo]::InvariantCulture) }
            $json = '{"Pid":' + $record.Pid.ToString([Globalization.CultureInfo]::InvariantCulture) + ',"Path":' + (ConvertTo-DumpJsonString $record.Path) + ',"Written":' + $record.Written.ToString().ToLowerInvariant() + ',"TimedOut":' + $record.TimedOut.ToString().ToLowerInvariant() + ',"Error":' + (ConvertTo-DumpJsonString $record.Error) + ',"CollectorPid":' + $collectorPidJson + ',"CollectorExited":' + $record.CollectorExited.ToString().ToLowerInvariant() + '}'
            [Console]::WriteLine('___HOST_CHILD_DUMP___:' + $json)
        } catch { }
    }
}

<# 2026-10-09：进程身份断言使用最小明确架构 EXE；PowerShell 启动语义留在独立冻结诊断。 #>
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$fixtureSourcePath = Join-Path $PSScriptRoot 'fixtures\host-process-child.cs'
if (-not [IO.File]::Exists($compilerPath) -or -not [IO.File]::Exists($fixtureSourcePath)) { throw 'Owned native child compiler or source missing' }
foreach ($fixture in @(@{ Platform = 'x64'; Bits = 8 }, @{ Platform = 'x86'; Bits = 4 })) {
    $ownedBinaryDirectory = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetTempPath(), 'AntigravityAA-HostBinary-' + [Guid]::NewGuid().ToString('N')))
    $ownedExpectedBinaryDirectory = $ownedBinaryDirectory
    $fixture.Engine = [IO.Path]::Combine($ownedBinaryDirectory, 'host-child.exe')
    $fixture.Expected = $fixture.Engine
    <# 2026-10-08：每例独占 GUID 目录和 nonce；阶段文件先于对应 Console getter/写入后的 stderr 标记。 #>
    $ownedStageDirectory = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetTempPath(), 'AntigravityAA-HostChild-' + [Guid]::NewGuid().ToString('N')))
    $ownedExpectedDirectory = $ownedStageDirectory
    $ownedStageNonce = [Guid]::NewGuid().ToString('N')
    $ownedStagePaths = @(
        [pscustomobject]@{ Stage = 'ENTERED'; Path = [IO.Path]::Combine($ownedStageDirectory, 'entered.stage'); Protocol = 'HOST_CHILD_ENTERED' },
        [pscustomobject]@{ Stage = 'ENCODING_SET'; Path = [IO.Path]::Combine($ownedStageDirectory, 'encoding-set.stage'); Protocol = 'HOST_CHILD_ENCODING_SET' },
        [pscustomobject]@{ Stage = 'READY_WRITTEN'; Path = [IO.Path]::Combine($ownedStageDirectory, 'ready-written.stage'); Protocol = 'HOST_CHILD_READY_WRITTEN' }
    )
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $fixture.Engine
    $start.Arguments = '"' + $ownedStageDirectory + '" "' + $ownedStageNonce + '"' # 2026-10-09：只传独占阶段目录与本轮 nonce。
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
    $ownedDirectoryCreated = $false
    # 2026-10-09：分别记录编译产物与编译进程的本轮归属。
    $ownedBinaryDirectoryCreated = $false
    $compilerStarted = $false
    $compilerExitConfirmed = $false
    $compilerCleanupError = ''
    $compilerPid = $null
    $childStarted = $false
    $ownedChildId = $null
    $exitWaitCompleted = $null
    $hasExitedAfterStop = $null
    $processQueryError = ''
    $stopError = ''
    $ownedDiagnosticPath = $null # 2026-10-22：超时现场只写本例编译目录，保留二进制与转储用于定位。
    try {
        if ([IO.Directory]::Exists($ownedStageDirectory)) { throw 'Owned stage directory collision' }
        [void][IO.Directory]::CreateDirectory($ownedStageDirectory)
        $ownedDirectoryCreated = $true
        <# 2026-10-09：编译目录独立于三个阶段文件；编译失败仍只回收持有的 compiler 和准确 EXE。 #>
        if ([IO.Directory]::Exists($ownedBinaryDirectory)) { throw 'Owned binary directory collision' }
        [void][IO.Directory]::CreateDirectory($ownedBinaryDirectory)
        $ownedBinaryDirectoryCreated = $true
        $compileStart = New-Object Diagnostics.ProcessStartInfo
        $compileStart.FileName = $compilerPath
        $compileStart.Arguments = '/nologo /noconfig /reference:System.dll /target:exe /codepage:65001 /platform:' + $fixture.Platform + ' /out:"' + $fixture.Engine + '" "' + $fixtureSourcePath + '"' # 2026-10-22：只引用夹具所需System，原源和平台不变。
        $compileStart.UseShellExecute = $false
        $compileStart.CreateNoWindow = $true
        $compileStart.RedirectStandardOutput = $true
        $compileStart.RedirectStandardError = $true
        $compiler = New-Object Diagnostics.Process
        $compiler.StartInfo = $compileStart
        try {
            if (-not $compiler.Start()) { throw 'Owned child compiler did not start' }
            $compilerStarted = $true; $compilerPid = $compiler.Id
            $compileOut = $compiler.StandardOutput.ReadToEndAsync()
            $compileError = $compiler.StandardError.ReadToEndAsync()
            if (-not $compiler.WaitForExit(10000)) {
                # 2026-10-22：编译器同样保留活实例转储，仍抛原十秒编译超时，不延长成功截止时间。
                $ownedDiagnosticPath = [IO.Path]::Combine($ownedBinaryDirectory, 'compiler-timeout.dmp')
                Save-HostTimeoutDump $compiler $compilerPath $ownedDiagnosticPath
                throw 'Owned child compile timeout'
            }
            if ($compiler.ExitCode -ne 0 -or $compileOut.GetAwaiter().GetResult().Length -ne 0 -or $compileError.GetAwaiter().GetResult().Length -ne 0) { throw 'Owned child compile failed' }
        } finally {
            # 2026-10-09：清理旁证不覆盖原编译异常；无法确认退出时保留自有目录。
            if ($compilerStarted) {
                try {
                    if (-not $compiler.get_HasExited()) { $compiler.Kill(); [void]$compiler.WaitForExit(5000) }
                    $compilerExitConfirmed = $compiler.get_HasExited()
                } catch { $compilerCleanupError = $_.Exception.GetType().FullName }
            }
            try { $compiler.Dispose() } catch { $compilerCleanupError = $_.Exception.GetType().FullName }
        }
        if (-not $compilerExitConfirmed -or $compilerCleanupError.Length -ne 0) { throw 'Owned child compiler cleanup failed' }
        if (-not $child.Start()) { throw 'Owned child did not start' }
        $childStarted = $true; $ownedChildId = $child.Id # 2026-10-08：只保留本次启动对象的 PID。
        $pendingReady = $child.StandardOutput.ReadLineAsync()
        $pendingError = $child.StandardError.ReadToEndAsync()
        <# 2026-10-08：缺失阶段仍是未知；有限读后保留 WaitForExit 布尔值、EOF/null 和读取任务前后状态。 #>
        # 2026-10-08：显式调用同一状态 getter，避免 PowerShell 点属性吞掉查询异常。
        if (-not $pendingReady.Wait(10000)) {
            $exitedBeforeStop = $null
            try { $exitedBeforeStop = $child.get_HasExited() } catch { $processQueryError = $_.Exception.GetType().FullName }
            $readyState = $pendingReady.Status.ToString()
            $errorState = $pendingError.Status.ToString()
            # 2026-10-22：原十秒 READY 已失败，独立有界收集器退出后仍按原路径停止目标并抛超时。
            if ($exitedBeforeStop -eq $false) {
                $ownedDiagnosticPath = [IO.Path]::Combine($ownedBinaryDirectory, 'ready-timeout.dmp')
                Save-HostTimeoutDump $child $fixture.Expected $ownedDiagnosticPath
            }
            try { if ($exitedBeforeStop -ne $true) { $child.Kill() } } catch { $stopError = $_.Exception.GetType().FullName }
            try { if ($exitedBeforeStop -ne $true) { $exitWaitCompleted = $child.WaitForExit(5000) } } catch { $stopError = $_.Exception.GetType().FullName }
            try { $hasExitedAfterStop = $child.get_HasExited() } catch { $processQueryError = $_.Exception.GetType().FullName }
            $readyAfterStop = $null; $errorAfterStop = $null
            $readyCompleted = $false; $errorCompleted = $false
            $readyReadError = ''; $errorReadError = ''
            try { if ($pendingReady.Wait(1000)) { $readyAfterStop = $pendingReady.GetAwaiter().GetResult(); $readyCompleted = $true } } catch { $readyReadError = $_.Exception.GetType().FullName }
            try { if ($pendingError.Wait(1000)) { $errorAfterStop = $pendingError.GetAwaiter().GetResult(); $errorCompleted = $true } } catch { $errorReadError = $_.Exception.GetType().FullName }
            $diagnosticStage = 'stage-read'
            try {
                $stages = @($ownedStagePaths | ForEach-Object { Read-HostChildStage $ownedStageDirectory $_.Stage $_.Path ($_.Protocol + ':' + $ownedChildId + ':' + $ownedStageNonce + [Environment]::NewLine) })
                $diagnostic = [ordered]@{
                    ExitedBeforeStop = $exitedBeforeStop; ExitWaitCompleted = $exitWaitCompleted; HasExitedAfterStop = $hasExitedAfterStop
                    QueryError = $processQueryError; StopError = $stopError; ReadyTaskBefore = $readyState; ErrorTaskBefore = $errorState
                    ReadyTaskAfter = $pendingReady.Status.ToString(); ErrorTaskAfter = $pendingError.Status.ToString()
                    ReadyReadCompleted = $readyCompleted; ReadyIsNull = if ($readyCompleted) { $null -eq $readyAfterStop } else { $null }
                    ReadyLength = if (-not $readyCompleted) { $null } elseif ($null -eq $readyAfterStop) { -1 } else { $readyAfterStop.Length }
                    ReadyReadError = $readyReadError; StderrReadCompleted = $errorCompleted
                    StderrLength = if (-not $errorCompleted) { $null } elseif ($null -eq $errorAfterStop) { -1 } else { $errorAfterStop.Length }
                    StderrReadError = $errorReadError; Stages = $stages
                }
                $diagnosticStage = 'serialize'
                $diagnosticJson = $diagnostic | ConvertTo-Json -Compress -Depth 5
            } catch {
                # 2026-10-08：旁证读取/序列化失败只保留阶段和类型，仍抛原 READY 超时。
                $diagnosticJson = '{"DiagnosticStage":"' + $diagnosticStage + '","DiagnosticError":"' + $_.Exception.GetType().FullName + '"}'
            }
            throw "Owned child ready timeout: engine=$($fixture.Engine) pid=$ownedChildId caller=$([IntPtr]::Size * 8) expected=$($fixture.Bits * 8) diagnostic=$diagnosticJson"
        }
        $ready = $pendingReady.GetAwaiter().GetResult()
        $pendingTail = $child.StandardOutput.ReadToEndAsync()
        Assert-Host ($ready -ceq "READY:$($fixture.Bits):$($child.Id)") 'owned child actual bitness and pid'
        $retained = [MouseHelper]::OpenProcess(0x101000, $false, [uint32]$child.Id)
        Assert-Host ($retained -ne [IntPtr]::Zero) 'owned child retained native handle'
        Assert-Host ([MouseHelper]::WaitForSingleObject($retained, 0) -eq 258) 'owned child alive wait timeout'
        Assert-Host ([MouseHelper]::GetProcessImagePath([uint32]$child.Id) -ieq $fixture.Expected) 'owned child native path cross bitness'
        $child.StandardInput.WriteLine('finish')
        $child.StandardInput.Flush()
        $exitWaitCompleted = $child.WaitForExit(10000) # 2026-10-08：保留原十秒退出等待的布尔结果。
        if (-not $exitWaitCompleted) { throw 'Owned child exit timeout' }
        Assert-Host ($child.ExitCode -eq 259) 'owned child normal exit 259'
        Assert-Host ([MouseHelper]::WaitForSingleObject($retained, 0) -eq 0) 'owned exited child handle signaled'
        Assert-Host ($null -eq [MouseHelper]::GetProcessImagePath([uint32]$child.Id)) 'owned exited 259 child rejected with retained handle'
        <# 2026-10-08：成功路径只允许自有child的三个阶段标记，任何额外stderr内容仍为失败。 #>
        $expectedChildError = @("HOST_CHILD_ENTERED:$($child.Id)", "HOST_CHILD_ENCODING_SET:$($child.Id)", "HOST_CHILD_READY_WRITTEN:$($child.Id)") -join [Environment]::NewLine
        $expectedChildError += [Environment]::NewLine
        Assert-Host ($pendingTail.GetAwaiter().GetResult().Length -eq 0 -and $pendingError.GetAwaiter().GetResult() -ceq $expectedChildError) 'owned child output streams complete'
        <# 2026-10-08：成功时额外要求三个独占文件整行等于当前 PID/nonce，不替代原 READY/退出/strict stderr 断言。 #>
        foreach ($ownedStage in $ownedStagePaths) {
            $record = Read-HostChildStage $ownedStageDirectory $ownedStage.Stage $ownedStage.Path ($ownedStage.Protocol + ':' + $ownedChildId + ':' + $ownedStageNonce + [Environment]::NewLine)
            Assert-Host ($record.Complete -and $record.State -ceq 'complete') ("owned child stage file $($ownedStage.Stage) exact pid and nonce")
        }
        Write-Output "PASS owned child: caller=$([IntPtr]::Size * 8) child=$($fixture.Bits * 8) alive-path=yes exited-259=rejected"
    }
    finally {
        if ($retained -ne [IntPtr]::Zero) { [void][MouseHelper]::CloseHandle($retained) }
        <# 2026-10-08：只清理确认退出后的三个自有文件，先验证全部最终绝对路径，再删除空目录；失败保留诊断。 #>
        if ($childStarted) {
            $finalExited = $null
            try { $finalExited = $child.get_HasExited() } catch { $processQueryError = $_.Exception.GetType().FullName }
            if ($finalExited -ne $true) {
                try { $child.Kill() } catch { $stopError = $_.Exception.GetType().FullName }
                try { $exitWaitCompleted = $child.WaitForExit(5000) } catch { $stopError = $_.Exception.GetType().FullName }
            }
            try { $hasExitedAfterStop = $child.get_HasExited() } catch { $processQueryError = $_.Exception.GetType().FullName }
        }
        $cleanup = [ordered]@{
            Pid = $ownedChildId; ChildStarted = $childStarted; ExitWaitCompleted = $exitWaitCompleted; HasExitedAfterStop = $hasExitedAfterStop
            QueryError = $processQueryError; StopError = $stopError; OwnedDirectory = $ownedStageDirectory
            StageFiles = @(); DirectoryState = 'not-created'; DirectoryError = ''; DisposeError = ''
        }
        if ($ownedDirectoryCreated) {
            if (-not $childStarted -or $hasExitedAfterStop -eq $true) {
                try {
                    $directory = [IO.Path]::GetFullPath($ownedStageDirectory)
                    if (-not [String]::Equals($directory, $ownedExpectedDirectory, [StringComparison]::OrdinalIgnoreCase)) { throw 'Owned stage directory changed' }
                    # 2026-10-08：先确认恰好三个原始 basename，拒绝同目录其他文件及相对路径，再执行任何删除。
                    $names = @('entered.stage', 'encoding-set.stage', 'ready-written.stage')
                    if ($ownedStagePaths.Count -ne $names.Count) { throw 'Owned cleanup target count changed' }
                    $paths = @($ownedStagePaths | ForEach-Object {
                        if (-not [IO.Path]::IsPathRooted($_.Path)) { throw 'Owned cleanup target is relative' }
                        [IO.Path]::GetFullPath($_.Path)
                    })
                    for ($pathIndex = 0; $pathIndex -lt $paths.Count; $pathIndex++) {
                        if (-not [String]::Equals([IO.Path]::GetDirectoryName($paths[$pathIndex]), $directory, [StringComparison]::OrdinalIgnoreCase) -or
                            -not [String]::Equals([IO.Path]::GetFileName($paths[$pathIndex]), $names[$pathIndex], [StringComparison]::Ordinal)) { throw 'Owned cleanup target changed' }
                    }
                    foreach ($path in $paths) {
                        $fileResult = [ordered]@{ Name = [IO.Path]::GetFileName($path); State = 'unknown'; Error = '' }
                        try { $existed = [IO.File]::Exists($path); [IO.File]::Delete($path); $fileResult.State = if ($existed) { 'deleted' } else { 'absent' } }
                        catch { $fileResult.State = 'delete-error'; $fileResult.Error = $_.Exception.GetType().FullName }
                        $cleanup.StageFiles += [pscustomobject]$fileResult
                    }
                    try { [IO.Directory]::Delete($directory, $false); $cleanup.DirectoryState = 'removed' }
                    catch { $cleanup.DirectoryState = 'delete-error'; $cleanup.DirectoryError = $_.Exception.GetType().FullName }
                } catch { $cleanup.DirectoryState = 'ownership-error'; $cleanup.DirectoryError = $_.Exception.GetType().FullName }
            } else { $cleanup.DirectoryState = 'kept-exit-unconfirmed' }
        }
        <# 2026-10-09：子进程和编译器均确认退出后，只删登记的绝对 EXE，非递归删除独占空目录。 #>
        $binaryCleanup = [ordered]@{ CompilerPid = $compilerPid; CompilerStarted = $compilerStarted; CompilerExitConfirmed = $compilerExitConfirmed; CompilerError = $compilerCleanupError; Directory = $ownedBinaryDirectory; State = 'not-created'; Error = '' }
        if ($ownedBinaryDirectoryCreated) {
            if ($null -ne $ownedDiagnosticPath) { $binaryCleanup.State = 'kept-timeout-diagnostic' } # 2026-10-22：失败现场不进入成功清理分支。
            elseif ((-not $childStarted -or $hasExitedAfterStop -eq $true) -and (-not $compilerStarted -or $compilerExitConfirmed)) {
                try {
                    $binaryDirectory = [IO.Path]::GetFullPath($ownedBinaryDirectory)
                    $binaryPath = [IO.Path]::GetFullPath($fixture.Engine)
                    if (-not [String]::Equals($binaryDirectory, $ownedExpectedBinaryDirectory, [StringComparison]::OrdinalIgnoreCase) -or
                        -not [IO.Path]::IsPathRooted($fixture.Engine) -or
                        -not [String]::Equals([IO.Path]::GetDirectoryName($binaryPath), $binaryDirectory, [StringComparison]::OrdinalIgnoreCase) -or
                        [IO.Path]::GetFileName($binaryPath) -cne 'host-child.exe') { throw 'Owned binary cleanup path changed' }
                    [IO.File]::Delete($binaryPath)
                    [IO.Directory]::Delete($binaryDirectory, $false)
                    $binaryCleanup.State = 'removed'
                } catch { $binaryCleanup.State = 'cleanup-error'; $binaryCleanup.Error = $_.Exception.GetType().FullName }
            } else { $binaryCleanup.State = 'kept-exit-unconfirmed' }
        }
        try { [Console]::WriteLine('___HOST_BINARY_CLEANUP___:' + ($binaryCleanup | ConvertTo-Json -Compress)) } catch { }
        try { $child.Dispose() } catch { $cleanup.DisposeError = $_.Exception.GetType().FullName }
        try { [Console]::WriteLine('___HOST_CHILD_CLEANUP___:' + ($cleanup | ConvertTo-Json -Compress -Depth 5)) } catch { }
    }
    # 2026-10-09：正常断言路径必须确认资源回收；置于 finally 后，原失败不被清理检查覆盖。
    if ($binaryCleanup.State -cne 'removed' -or $binaryCleanup.Error.Length -ne 0 -or
        -not $binaryCleanup.CompilerExitConfirmed -or $binaryCleanup.CompilerError.Length -ne 0) { throw 'Owned binary cleanup failed' }
    if ($cleanup.HasExitedAfterStop -ne $true -or $cleanup.DirectoryState -cne 'removed' -or
        $cleanup.QueryError.Length -ne 0 -or $cleanup.StopError.Length -ne 0 -or $cleanup.DirectoryError.Length -ne 0 -or $cleanup.DisposeError.Length -ne 0 -or
        @($cleanup.StageFiles | Where-Object { $_.State -cne 'deleted' -or $_.Error.Length -ne 0 }).Count -ne 0) { throw 'Owned child cleanup failed' }
}
Write-Output "___HOST_PROCESS_TEST_DONE___:passed=$script:checks"
