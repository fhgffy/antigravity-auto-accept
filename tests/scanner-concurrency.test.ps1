# 2026-10-07：运行真实单实例生命周期并以空窗口集合隔离桌面，复现多 IDE 宿主并发和退出接管。
param([string[]]$PowerShellEngines = @('powershell.exe', 'pwsh.exe'), [ValidateRange(1, 5)][int]$Rounds = 2)

$ErrorActionPreference = 'Stop'
$scannerPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))
$source = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Scanner parse errors' }
$parentFunction = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ParentAlive' }, $true))
if ($parentFunction.Count -ne 1) { throw 'Parent lifecycle function not found' }
$tailIndex = $source.IndexOf('$script:parentProcess = $null', [StringComparison]::Ordinal)
if ($tailIndex -lt 0) { throw 'Scanner lifecycle entry not found' }
$engines = @($PowerShellEngines | ForEach-Object { (Get-Command $_ -ErrorAction Stop).Source } | Select-Object -Unique)
if ($engines.Count -eq 0) { throw 'No requested PowerShell engine' }
$checks = 0

# 2026-10-07：独立进程采用显式 UTF-8 输出与隐藏窗口，避免 PS5 无 BOM 解码和多应用界面干扰。
function Start-ConcurrencyProcess([string]$Executable, [string]$Command) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = "-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    return $process
}

# 2026-10-07：协议必须在期限内实际到达，不以进程仍存活推断扫描器获得互斥锁。
function Read-ConcurrencyLine($Process, [string]$Expected) {
    $pending = $Process.StandardOutput.ReadLineAsync()
    if (-not $pending.Wait(10000)) { throw "Concurrency protocol timeout: $Expected" }
    if ($pending.Result -cne $Expected) { throw "Concurrency protocol mismatch: expected=$Expected actual=$($pending.Result)" }
}

# 2026-10-07：只有已创建的测试进程会被终止，非测试 IDE 和用户的扫描器不受影响。
function Assert-ConcurrencyExit($Process) {
    # 2026-10-07：等待退出前先持续收集尾部输出，诊断写满管道不能阻塞父进程退出检查。
    $pendingOutput = $Process.StandardOutput.ReadToEndAsync()
    $pendingError = $Process.StandardError.ReadToEndAsync()
    if (-not $Process.WaitForExit(10000)) { throw 'Scanner did not stop after parent exit' }
    $output = $pendingOutput.GetAwaiter().GetResult()
    $errorOutput = $pendingError.GetAwaiter().GetResult()
    if ($Process.ExitCode -ne 0 -or $errorOutput.Length -gt 0 -or $output -match '___CLICK_|___ERROR___') {
        throw "Unexpected scanner exit: code=$($Process.ExitCode) stdout=$output stderr=$errorOutput"
    }
}

for ($round = 1; $round -le $Rounds; $round++) {
    $processes = New-Object Collections.Generic.List[Diagnostics.Process]
    $slots = New-Object Collections.Generic.List[object]
    $mutexName = 'Local\AntigravityAutoAcceptScanner.ConcurrencyTest.' + [Guid]::NewGuid().ToString('N')
    $lifecycle = $source.Substring($tailIndex).Replace('Local\AntigravityAutoAcceptScanner', $mutexName)
    $common = '$ProgressPreference = ''SilentlyContinue''; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $PollMs = 25; $CooldownMs = 0; '
    # 2026-10-07：窗口 PID 查询前已有窗口枚举；只加载枚举类型并提供空树，不能靠空进程图跳过桌面入口。
    $common += $parentFunction[0].Extent.Text + [Environment]::NewLine
    $common += @'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
function Get-TargetProcessIds([int]$ProcessId) { return @{} }
$automation = [pscustomobject]@{}
$automation | Add-Member ScriptMethod FindAll { param($scope, $condition) return @() }
'@
    $common += [Environment]::NewLine
    try {
        for ($index = 0; $index -lt 5; $index++) {
            $engine = $engines[$index % $engines.Count]
            $parent = Start-ConcurrencyProcess $engine 'Start-Sleep -Seconds 120'
            $processes.Add($parent)
            $scanner = Start-ConcurrencyProcess $engine "$common `$ParentProcessId = $($parent.Id); $lifecycle"
            $processes.Add($scanner)
            $slots.Add([pscustomobject]@{ Parent = $parent; Scanner = $scanner; Pending = $null; Active = $false })
            if ($index -eq 0) {
                Read-ConcurrencyLine $scanner '___AUTOCLICK_READY___'
                $slots[$index].Active = $true
            }
            else {
                Read-ConcurrencyLine $scanner '___SCANNER_WAITING___'
                if ($scanner.HasExited) { throw 'Waiting scanner exited prematurely' }
            }
            $checks++
        }

        # 2026-10-07：停止一个等待宿主应只退出它自己的扫描器，其余宿主继续保持等待。
        $slots[4].Parent.Kill()
        $slots[4].Parent.WaitForExit()
        Assert-ConcurrencyExit $slots[4].Scanner
        $checks++
        $waiters = @($slots | Select-Object -Skip 1 -First 3)
        foreach ($waiter in $waiters) { $waiter.Pending = $waiter.Scanner.StandardOutput.ReadLineAsync() }
        if (@($waiters | Where-Object { $_.Pending.IsCompleted }).Count -ne 0) { throw 'More than one scanner became owner' }
        $checks++
        $owner = $slots[0]
        $abandon = $false
        while ($waiters.Count -gt 0) {
            if ($abandon) {
                $owner.Scanner.Kill()
                $owner.Scanner.WaitForExit()
                $owner.Parent.Kill()
                $owner.Parent.WaitForExit()
            }
            else {
                $owner.Parent.Kill()
                $owner.Parent.WaitForExit()
                Assert-ConcurrencyExit $owner.Scanner
            }
            $tasks = [Threading.Tasks.Task[]]@($waiters | ForEach-Object { $_.Pending })
            $readyIndex = [Threading.Tasks.Task]::WaitAny($tasks, 10000)
            if ($readyIndex -lt 0) { throw 'No waiting scanner acquired released mutex' }
            $owner = $waiters[$readyIndex]
            if ($owner.Pending.Result -cne '___AUTOCLICK_READY___') { throw 'Unexpected takeover protocol' }
            $remaining = @($waiters | Where-Object { $_ -ne $owner })
            if (@($remaining | Where-Object { $_.Pending.IsCompleted }).Count -ne 0) { throw 'Multiple waiting scanners acquired the mutex' }
            Write-Output "PASS concurrent handoff: round=$round abandoned=$abandon remaining=$($remaining.Count)"
            $waiters = $remaining
            $abandon = -not $abandon
            $checks++
        }
        $owner.Parent.Kill()
        $owner.Parent.WaitForExit()
        Assert-ConcurrencyExit $owner.Scanner
        $checks++
    }
    finally {
        foreach ($process in $processes) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            $process.Dispose()
        }
    }
}
Write-Output "___SCANNER_CONCURRENCY_TEST_DONE___:passed=${checks}:rounds=${Rounds}:engines=$($engines.Count)"
