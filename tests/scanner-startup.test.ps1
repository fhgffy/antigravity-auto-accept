# 2026-10-21：执行完整扫描入口，只把重型编译替成失败哨兵，证明等待阶段不初始化且初始化失败释放真实互斥。
param([string[]]$PowerShellEngines = @('powershell.exe','pwsh.exe'), [string]$ScannerSourcePath = '')
$ErrorActionPreference = 'Stop'
$scannerPath = if ($ScannerSourcePath) { [IO.Path]::GetFullPath($ScannerSourcePath) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1')) }
$source = [IO.File]::ReadAllText($scannerPath,[Text.Encoding]::UTF8)
$tokens = $null; $errors = $null
$sourceAst = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Scanner parse failed' }
$compile = @($sourceAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Add-Type' -and @($node.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'TypeDefinition' }).Count -eq 1},$true))
if ($compile.Count -ne 1) { throw 'Expected one actual native compilation boundary' }
$sentinel = "[Console]::WriteLine('___HEAVY_INITIALIZATION___'); throw 'Expected initialization sentinel'"
$instrumented = $source.Substring(0,$compile[0].Extent.StartOffset) + $sentinel + $source.Substring($compile[0].Extent.EndOffset)
# 2026-10-21：等待阶段也不应为进程查询、构造互斥或休眠自动加载完整管理/工具模块。
$waitingProtocol = "[Console]::WriteLine('___SCANNER_WAITING___')"
if (($instrumented.Split(@($waitingProtocol),[StringSplitOptions]::None).Count - 1) -ne 1) { throw 'Exact waiting boundary missing' }
$instrumented = $instrumented.Replace($waitingProtocol, $waitingProtocol + "; [Console]::WriteLine('___COLD_MODULES___:' + @(Get-Module -Name Microsoft.PowerShell.Management,Microsoft.PowerShell.Utility).Count); [Console]::WriteLine('___WAITING_APPROVAL_FUNCTIONS___:' + @(Get-Command -Name Invoke-BrowserPermissionCards -CommandType Function -ErrorAction SilentlyContinue).Count)")
# 2026-10-21：复用既有隐藏子进程与有界协议工具，不执行其回归主体，不启动任何桌面动作。
$utilityPath = Join-Path $PSScriptRoot 'scanner.test.ps1'
$utilityAst = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($utilityPath,[Text.Encoding]::UTF8),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Utility parse failed' }
foreach ($name in @('Start-TestProcess','Read-ProtocolLine')) {
    $definition = @($utilityAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true))
    if ($definition.Count -ne 1) { throw 'Exact process utility missing' }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$checks = 0
foreach ($engine in @($PowerShellEngines | ForEach-Object { (Get-Command $_ -ErrorAction Stop).Source } | Select-Object -Unique)) {
    $mutexName = 'Local\AntigravityAutoAcceptScanner.StartupTest.' + [Guid]::NewGuid().ToString('N')
    $mutex = [Threading.Mutex]::new($true,$mutexName)
    $process = $null; $parent = $null; $owned = $true
    try {
        $payload = $instrumented.Replace('Local\AntigravityAutoAcceptScanner',$mutexName)
        $bootstrap = '$ErrorActionPreference=''Stop''; $ProgressPreference=''SilentlyContinue''; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); '
        $command = $bootstrap + 'try { & { ' + $payload + "`r`n} -PollMs 50 -ParentProcessId $PID } catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }"
        $process = Start-TestProcess $engine $command
        Read-ProtocolLine $process '___SCANNER_WAITING___'
        Read-ProtocolLine $process '___COLD_MODULES___:0'
        Read-ProtocolLine $process '___WAITING_APPROVAL_FUNCTIONS___:0'
        if ($process.HasExited) { throw 'Waiting scanner exited before release' }
        $checks++
        $mutex.ReleaseMutex(); $owned = $false
        Read-ProtocolLine $process '___SCANNER_INITIALIZING___' # 2026-10-22：拿锁后、任何重型初始化前通知宿主恢复截止时间。
        Read-ProtocolLine $process '___HEAVY_INITIALIZATION___'
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(8000)) { throw 'Initialization failure did not exit' }
        if ($process.ExitCode -eq 0 -or $stdout.GetAwaiter().GetResult().Length -ne 0 -or $stderr.GetAwaiter().GetResult() -notmatch 'Expected initialization sentinel') { throw 'Initialization failure was swallowed or READY was emitted' }
        $process.Dispose(); $process = $null
        if (-not $mutex.WaitOne(0)) { throw 'Initialization failure leaked scanner mutex' }
        $owned = $true; $checks++
        # 2026-10-21：等待宿主退出必须直接结束，不能借接管路径再加载重型组件。
        $parent = Start-TestProcess $engine 'Start-Sleep -Seconds 60'
        $command = $bootstrap + 'try { & { ' + $payload + "`r`n} -PollMs 50 -ParentProcessId $($parent.Id) } catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }"
        $process = Start-TestProcess $engine $command
        Read-ProtocolLine $process '___SCANNER_WAITING___'
        Read-ProtocolLine $process '___COLD_MODULES___:0'
        Read-ProtocolLine $process '___WAITING_APPROVAL_FUNCTIONS___:0'
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $parent.Kill(); $parent.WaitForExit()
        if (-not $process.WaitForExit(8000)) { throw 'Waiting scanner ignored parent exit' }
        if ($process.ExitCode -ne 0 -or $stdout.GetAwaiter().GetResult().Length -ne 0 -or $stderr.GetAwaiter().GetResult().Length -ne 0) { throw 'Waiting parent exit initialized or failed' }
        $checks++
        Write-Output "PASS cold waiter, initialization failure release, waiting parent exit: $engine"
    }
    catch {
        # 2026-10-21：协议失败也保留子进程两流与退出码，不能只留下父观察器的超时文字。
        if ($null -ne $process) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
            [Console]::WriteLine('___STARTUP_FAILURE_DIAGNOSTIC___:exit=' + $process.ExitCode + ':stdout=' + $process.StandardOutput.ReadToEnd() + ':stderr=' + $process.StandardError.ReadToEnd())
        }
        throw
    }
    finally {
        foreach ($child in @($process,$parent)) { if ($null -ne $child) { if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose() } }
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
Write-Output "___SCANNER_STARTUP_TEST_DONE___:passed=$checks"
