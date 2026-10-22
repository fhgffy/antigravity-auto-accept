# 2026-10-22：独立观察原Node测试的自有PowerShell子进程，原spawnSync命令与二十五秒截止保持不变。
# 2026-10-22：可选生命周期模式保留原二十秒同步命令，精确来源过滤且仅读栈，不作转储暂停。
param([string]$Repository, [string]$NodePath, [string]$TestFile, [string]$Engine = 'powershell.exe', [ValidateRange(1,20)][int]$Repetitions = 1, [string]$EvidenceDirectory, [switch]$FullSuite, [switch]$RequireControlledCapture, [string]$SelfTestSourcePath = '', [string]$X86CollectorPath = '')
$ErrorActionPreference = 'Stop'
$Repository = [IO.Path]::GetFullPath($Repository)
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if ([IO.Directory]::Exists($EvidenceDirectory)) { throw 'Preserve existing observer evidence' }
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$allowed = @((Get-Command powershell.exe).Source, (Get-Command pwsh.exe).Source, (Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'))
$utilityPath = Join-Path $Repository 'tests\host-process.test.ps1'
# 2026-10-22：生命周期只识别同一编码命令中的精确源码与SelfTest；该模式仅读栈，不转储或改原二十秒。
$expectedSelfTestSource = if ($SelfTestSourcePath) { [IO.Path]::GetFullPath($SelfTestSourcePath).Replace("'", "''") } else { '' }
$expectedTestName = [IO.Path]::GetFileName($TestFile)
$t = $null; $e = $null
$ast = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($utilityPath,[Text.Encoding]::UTF8),$utilityPath,[ref]$t,[ref]$e)
$function = @($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-HostTimeoutDump'},$true))
if ($e.Count -or $function.Count -ne 1) { throw 'Exact owned dump helper boundary missing' }
$ast = [Management.Automation.Language.Parser]::ParseInput($function[0].Extent.Text,$utilityPath,[ref]$t,[ref]$e)
if ($e.Count) { throw 'Owned dump helper parse failed' }
. ($ast.GetScriptBlock())

# 2026-10-22：只在ArgumentException且CIM再次确认PID已消失时返回空；仍存在或查询错误必须保留原诊断失败。
function Open-ObserverCandidateProcess([ValidateRange(1,2147483647)][int]$CandidatePid) {
    try { return [Diagnostics.Process]::GetProcessById($CandidatePid) }
    catch [ArgumentException] {
        $present = Get-CimInstance Win32_Process -OperationTimeoutSec 1 -Filter ('ProcessId=' + $CandidatePid)
        if ($null -ne $present) { throw }
        return $null
    }
}

foreach ($iteration in 1..$Repetitions) {
    $directory = Join-Path $EvidenceDirectory ('case-' + $iteration)
    [void][IO.Directory]::CreateDirectory($directory)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $NodePath
    $start.Arguments = '--test --test-name-pattern="bounded x64 minidump success" "' + $TestFile + '"'
    if ($FullSuite) { $start.Arguments = '--test "' + $TestFile + '"' } # 2026-10-22：真实诊断执行完整原Node测试，不用筛选代替原回归。
    $start.WorkingDirectory = $Repository
    $start.EnvironmentVariables['HOST_WRAPPER_ENGINE'] = $Engine
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8; $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $node = [Diagnostics.Process]::new(); $node.StartInfo = $start
    $started = $false; $failure = $null; $cleanupErrors = @(); $observationErrors = @(); $observationRaces = @()
    $owned = [Collections.Generic.List[Diagnostics.Process]]::new(); $seen = @{}
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $node.Start()) { throw 'Owned Node did not start' }
        $started = $true; [void]$node.Handle
        $out = $node.StandardOutput.ReadToEndAsync(); $err = $node.StandardError.ReadToEndAsync()
        while (-not $node.get_HasExited()) {
            if ($clock.ElapsedMilliseconds -ge 180000) { throw 'Independent Node observer ceiling exceeded' }
            # 2026-10-22：查询、读栈或旁证异常只记诊断错误，不能提前终止仍在执行的原Node。
            try {
                foreach ($workerInfo in @(Get-CimInstance Win32_Process -OperationTimeoutSec 1 -Filter ('ParentProcessId=' + $node.Id))) {
                    if ($workerInfo.ExecutablePath -ine $NodePath -or ([string]$workerInfo.CommandLine).IndexOf($expectedTestName,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                    if (-not $seen.ContainsKey('worker-' + $workerInfo.ProcessId)) {
                        $worker = $null
                        try {
                            $worker = [Diagnostics.Process]::GetProcessById([int]$workerInfo.ProcessId); [void]$worker.Handle
                            $workerFresh = Get-CimInstance Win32_Process -OperationTimeoutSec 1 -Filter ('ProcessId=' + $worker.Id)
                            if ($null -eq $workerFresh -or $workerFresh.ParentProcessId -ne $node.Id -or $workerFresh.CreationDate -ne $workerInfo.CreationDate -or $workerFresh.ExecutablePath -ine $NodePath) { $worker.Dispose(); continue }
                            $owned.Add($worker); $seen['worker-' + $workerInfo.ProcessId] = $true
                        } catch { if ($null -ne $worker) { $worker.Dispose() }; continue }
                    }
                    foreach ($info in @(Get-CimInstance Win32_Process -OperationTimeoutSec 1 -Filter ('ParentProcessId=' + $workerInfo.ProcessId))) {
                        if ($allowed -inotcontains $info.ExecutablePath -or ([DateTime]::UtcNow - $info.CreationDate.ToUniversalTime()).TotalSeconds -lt 8 -or $seen.ContainsKey('target-' + $info.ProcessId)) { continue }
                        $match = [regex]::Match([string]$info.CommandLine, '(?i)-EncodedCommand\s+([A-Za-z0-9+/=]+)')
                        if (-not $match.Success) { continue }
                        $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($match.Groups[1].Value))
                        # 2026-10-22：只读原生命周期SelfTest或既有转储夹具，不能把同一Node下的其他PowerShell当目标。
                        if ($expectedSelfTestSource) {
                            if (-not $command.Contains(("'" + $expectedSelfTestSource + "'")) -or -not $command.Contains(' -SelfTest')) { continue }
                        } elseif (-not $command.Contains('DUMP_DIAGNOSTIC_CHILD_READY') -or -not $command.Contains('host-dump-collector.exe')) { continue }
                        $target = Open-ObserverCandidateProcess ([int]$info.ProcessId); $targetRegistered = $false
                        if ($null -eq $target) {
                            # 2026-10-22：保留退出竞争的原PID/创建时间；不登记新目标，也不把原测试成功改成故障。
                            $observationRaces += [ordered]@{Stage='target-handle';Pid=$info.ProcessId;CreationDate=$info.CreationDate.ToUniversalTime().ToString('o');Reason='confirmed-exited-before-handle'}
                            continue
                        }
                        # 2026-10-22：临时持有对象遇到元数据竞争也要释放，登记后才交给统一只读收尾。
                        try {
                            [void]$target.Handle
                            $fresh = Get-CimInstance Win32_Process -OperationTimeoutSec 1 -Filter ('ProcessId=' + $target.Id)
                            if ($null -eq $fresh -or $fresh.ParentProcessId -ne $workerInfo.ProcessId -or $fresh.CreationDate -ne $info.CreationDate -or $fresh.ExecutablePath -ine $info.ExecutablePath) { continue }
                            $owned.Add($target); $targetRegistered = $true; $seen['target-' + $info.ProcessId] = $true
                            $identity = [ordered]@{Pid=$target.Id;ParentPid=$workerInfo.ProcessId;NodeRootPid=$node.Id;Image=$fresh.ExecutablePath;CreationDate=$fresh.CreationDate.ToUniversalTime().ToString('o');StartTicks=$target.StartTime.ToUniversalTime().Ticks.ToString();ObservedMs=$clock.ElapsedMilliseconds}
                            [IO.File]::WriteAllText((Join-Path $directory ('slow-' + $target.Id + '.json')),($identity|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
                            # 2026-10-22：旁路读栈进程同样五秒有界，只读目标；原Node命令/25秒期限和原持有者回收均不改。
                            $readerStart=[Diagnostics.ProcessStartInfo]::new();$readerStart.FileName=(Get-Command pwsh.exe).Source
                            $readerStart.Arguments='-NoProfile -NonInteractive -OutputFormat Text -File "'+(Join-Path $PSScriptRoot 'read-owned-callstack.ps1')+'" -TargetPid '+$target.Id+' -StartTicks "'+$identity.StartTicks+'" -ExpectedImage "'+$fresh.ExecutablePath+'" -ExpectedParentId '+$workerInfo.ProcessId+' -OutputFile "'+(Join-Path $directory ('slow-'+$target.Id+'.callstack.json'))+'"'
                            $readerStart.UseShellExecute=$false;$readerStart.CreateNoWindow=$true;$readerStart.RedirectStandardOutput=$true;$readerStart.RedirectStandardError=$true
                            $reader=[Diagnostics.Process]::new();$reader.StartInfo=$readerStart;$readerStarted=$false
                            $readerRecord=[ordered]@{Pid=$null;TimedOut=$false;ExitConfirmed=$false;Stdout='';Stderr=''}
                            try {
                                if(-not $reader.Start()){throw 'Owned stack reader did not start'};$readerStarted=$true;$readerRecord.Pid=$reader.Id
                                $readerOut=$reader.StandardOutput.ReadToEndAsync();$readerErr=$reader.StandardError.ReadToEndAsync()
                                $readerRecord.TimedOut=-not $reader.WaitForExit(5000)
                            } finally {
                                if($readerStarted){if(-not $reader.HasExited){$reader.Kill()};$readerRecord.ExitConfirmed=$reader.WaitForExit(1000)
                                    if($readerOut.Wait(1000)){$readerRecord.Stdout=$readerOut.GetAwaiter().GetResult()};if($readerErr.Wait(1000)){$readerRecord.Stderr=$readerErr.GetAwaiter().GetResult()}}
                                $reader.Dispose()
                                [IO.File]::WriteAllText((Join-Path $directory ('slow-'+$target.Id+'.reader.json')),($readerRecord|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
                            }
                            # 2026-10-22：已知SysWOW64目标可用同位数工具保留可读上下文；生命周期模式仍不转储。
                            if (-not $expectedSelfTestSource) {
                                $dumpPath = Join-Path $directory ('slow-' + $target.Id + '.dmp')
                                if ($X86CollectorPath -and [String]::Equals($fresh.ExecutablePath,$allowed[2],[StringComparison]::OrdinalIgnoreCase)) {
                                    Save-HostTimeoutDump $target $fresh.ExecutablePath $dumpPath -CollectorEngine $X86CollectorPath -ExecutableCollector -CollectorStackTool $X86CollectorPath
                                } else { Save-HostTimeoutDump $target $fresh.ExecutablePath $dumpPath }
                            }
                        } finally { if (-not $targetRegistered) { $target.Dispose() } }
                    }
                }
            } catch {
                $observationErrors += [ordered]@{Stage='observe';Type=$_.Exception.GetBaseException().GetType().FullName;Message=$_.Exception.GetBaseException().Message}
            }
            [Threading.Thread]::Sleep(200)
        }
        # 2026-10-22：先保留原退出码，再独立落盘两流；旁证IO失败不得覆盖原Node失败。
        if (-not $node.WaitForExit(1000)) { throw 'Original Node exit unconfirmed' }
        $exitCode = $node.ExitCode
        $complete = @{Stdout=$false;Stderr=$false}
        foreach ($stream in @(@{Name='Stdout';Task=$out;File='node.stdout'},@{Name='Stderr';Task=$err;File='node.stderr'})) {
            try {
                if (-not $stream.Task.Wait(1000)) { throw 'Original Node stream read incomplete' }
                $text = $stream.Task.GetAwaiter().GetResult(); $complete[$stream.Name] = $true
                [IO.File]::WriteAllText((Join-Path $directory $stream.File),$text,[Text.UTF8Encoding]::new($false))
            } catch { $observationErrors += [ordered]@{Stage=$stream.File;Type=$_.Exception.GetBaseException().GetType().FullName;Message=$_.Exception.GetBaseException().Message} }
        }
        $result = [ordered]@{ExitCode=$exitCode;ElapsedMs=$clock.ElapsedMilliseconds;ObservedTargets=@($seen.Keys|Where-Object {$_ -like 'target-*'});StdoutComplete=$complete.Stdout;StderrComplete=$complete.Stderr;ObservationErrors=$observationErrors;ObservationRaces=$observationRaces}
        try { [IO.File]::WriteAllText((Join-Path $directory 'result.json'),($result|ConvertTo-Json -Depth 6 -Compress),[Text.UTF8Encoding]::new($false)) }
        catch { $observationErrors += [ordered]@{Stage='result.json';Type=$_.Exception.GetBaseException().GetType().FullName;Message=$_.Exception.GetBaseException().Message} }
        $result.ObservationErrors = $observationErrors
        try { [Console]::WriteLine('___HOST_OBSERVER_RESULT___:'+($result|ConvertTo-Json -Depth 6 -Compress)) } catch { }
        if ($exitCode -ne 0) { throw 'Original host-wrapper test failed; retained without retry' }
        if (-not $complete.Stdout -or -not $complete.Stderr) { throw 'Original Node streams incomplete' }
        # 2026-10-22：受控验证必须真正取得目标栈，不能只凭原测试成功便宣称观察工具可用。
        if ($RequireControlledCapture) {
            $snapshots = @(Get-ChildItem -LiteralPath $directory -Filter '*.callstack.json' -File)
            if ($snapshots.Count -ne 1) { throw 'Controlled stack snapshot missing or ambiguous' }
            $snapshot = [IO.File]::ReadAllText($snapshots[0].FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $frames = @($snapshot.Stacks | Where-Object Name -eq 'Runspace1' | ForEach-Object Frames)
            if ($snapshot.Error -or @($frames | Where-Object PositionText -eq 'Start-Sleep -Seconds 20').Count -ne 1) { throw 'Controlled target statement absent from stack' }
            $receipt = [IO.File]::ReadAllText(($snapshots[0].FullName.Replace('.callstack.json', '.reader.json')), [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($receipt.TimedOut -or -not $receipt.ExitConfirmed -or $receipt.Stderr) { throw 'Controlled reader completion failed' }
            # 2026-10-22：同位数控制必须得到Intel上下文，不能把可写的AMD64/WOW64头当成原生x86栈。
            if ($X86CollectorPath -and -not $expectedSelfTestSource) {
                $dumps = @(Get-ChildItem -LiteralPath $directory -Filter '*.dmp' -File)
                if ($dumps.Count -ne 1) { throw 'Controlled native x86 dump missing or ambiguous' }
                $bytes = [IO.File]::ReadAllBytes($dumps[0].FullName)
                if ($bytes.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($bytes,0,4) -cne 'MDMP') { throw 'Controlled native x86 dump header invalid' }
                $count = [BitConverter]::ToUInt32($bytes,8); $streamDirectory = [BitConverter]::ToUInt32($bytes,12); $architecture = -1
                if ([long]$streamDirectory + [long]$count * 12 -gt $bytes.Length) { throw 'Controlled dump directory out of bounds' }
                for ($stream = 0; $stream -lt $count; $stream++) {
                    $entry = $streamDirectory + $stream * 12
                    if ([BitConverter]::ToUInt32($bytes,$entry) -eq 7) {
                        $offset = [BitConverter]::ToUInt32($bytes,$entry+8)
                        if ([long]$offset + 2 -gt $bytes.Length) { throw 'Controlled system information out of bounds' }
                        $architecture = [BitConverter]::ToUInt16($bytes,$offset)
                    }
                }
                if ($architecture -ne 0) { throw 'Controlled dump does not contain native Intel context' }
            }
        }
        if ($observationErrors.Count) { throw 'Observer diagnostics failed after original Node completed' } # 2026-10-22：原测试成功时，观察失败本身仍须明确失败。

    }
    catch { $failure = $_ }
    finally {
        foreach ($process in $owned) {
            # 2026-10-22：观察器不终止被观察子进程，由原Node包装器执行原有回收；未退出必须如实报告。
            try { if (-not $process.WaitForExit(2000)) { throw 'Original observed child exit unconfirmed' } } catch { $cleanupErrors += $_.Exception.GetType().FullName }
            try { $process.Dispose() } catch { $cleanupErrors += $_.Exception.GetType().FullName }
        }
        if ($started) { try { if (-not $node.get_HasExited()) { $node.Kill() }; if (-not $node.WaitForExit(2000)) { throw 'Owned Node exit unconfirmed' } } catch { $cleanupErrors += $_.Exception.GetType().FullName } }
        try { $node.Dispose() } catch { $cleanupErrors += $_.Exception.GetType().FullName }
        try { [IO.File]::WriteAllText((Join-Path $directory 'cleanup.json'),([ordered]@{Errors=$cleanupErrors}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false)) } catch { $cleanupErrors += $_.Exception.GetType().FullName }
    }
    if ($null -ne $failure) { throw $failure }
    if ($cleanupErrors.Count) { throw 'Owned observer cleanup failed' }
}
