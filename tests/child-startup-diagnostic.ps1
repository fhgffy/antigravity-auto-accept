<# 2026-10-08：每个新 runner 只启动一个自有 x86 child，比较输入方式；复用冻结测试，不改原必需回归。 #>
param(
    [Parameter(Mandatory = $true)][ValidateSet('EncodedCommand', 'File')][string]$InputMode,
    [Parameter(Mandatory = $true)][ValidateSet(5, 7)][int]$ExpectedMajor,
    [string]$RepositoryRoot = '',
    [string]$EvidenceDirectory = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($PSVersionTable.PSVersion.Major -ne $ExpectedMajor -or [IntPtr]::Size -ne 8) { throw 'Unexpected diagnostic caller engine or bitness' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Diagnostic requires Windows x64' }
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
# 2026-10-09：冻结旧 PowerShell child 的完整源码字节，独立于主身份测试的原生 fixture。
$hostSourcePath = [IO.Path]::Combine($RepositoryRoot, 'tests', 'fixtures', 'host-process-startup-20261008.ps1')
$scannerSourcePath = [IO.Path]::Combine($RepositoryRoot, 'src', 'autoClicker.ps1')
$expectedHostHash = '776F1BBCD759D5DE3518CD44933FE0A1E1C7034A2F6DC13B4229846FF4FDB9D9'

<# 2026-10-08：哈希按明确字节计算；文件输入用 CreateNew，UTF-8 BOM 和正文回读必须完全一致。 #>
function Get-StartupHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Add-StartupEvent([string]$Name) {
    try {
        $startupLedger.Events += [pscustomobject]@{
            Name = $Name; Utc = [DateTime]::UtcNow.ToString('o'); ElapsedMs = $startupClock.ElapsedMilliseconds
        }
    } catch { $startupLedger.DiagnosticErrors += 'event:' + $_.Exception.GetType().FullName }
}

function Get-StartupArguments([ValidateSet('EncodedCommand', 'File')][string]$Mode, [string]$Body, [string]$OriginalArguments) {
    $bodyBytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $startupLedger.ActualBodySha256 = Get-StartupHash $bodyBytes
    $startupLedger.ActualBodyCharacters = $Body.Length
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Body))
    $expectedArguments = '-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    if ($OriginalArguments -cne $expectedArguments) { throw 'Frozen encoded arguments changed' }
    if ($Mode -ceq 'EncodedCommand') {
        $startupLedger.ArgumentsLength = $OriginalArguments.Length
        return $OriginalArguments
    }
    $scriptPath = [IO.Path]::GetFullPath([IO.Path]::Combine($EvidenceDirectory, 'input.ps1'))
    if (-not [String]::Equals([IO.Path]::GetDirectoryName($scriptPath), $EvidenceDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($scriptPath) -cne 'input.ps1') { throw 'Owned input script path changed' }
    $startupLedger.InputScriptPath = $scriptPath
    $bomBytes = [byte[]]([byte[]](239, 187, 191) + $bodyBytes)
    $file = [IO.File]::Open($scriptPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $startupLedger.InputScriptCreated = $true
    try { $file.Write($bomBytes, 0, $bomBytes.Length) }
    finally { $file.Dispose() }
    $actualBytes = [IO.File]::ReadAllBytes($scriptPath)
    $startupLedger.Utf8BomFileSha256 = Get-StartupHash $actualBytes
    if ($actualBytes.Length -ne $bomBytes.Length -or $actualBytes[0] -ne 239 -or $actualBytes[1] -ne 187 -or $actualBytes[2] -ne 191 -or
        $startupLedger.Utf8BomFileSha256 -cne (Get-StartupHash $bomBytes)) { throw 'Owned UTF8 BOM script bytes changed' }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    if ($strictUtf8.GetString($actualBytes, 3, $actualBytes.Length - 3) -cne $Body) { throw 'Owned UTF8 BOM script text changed' }
    $arguments = '-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
    $startupLedger.ArgumentsLength = $arguments.Length
    return $arguments
}

<# 2026-10-08：只提取唯一完整 AST 单元；冻结源、方法或插入边界变化时，在创建任何 child 前拒绝。 #>
function Get-StartupFragment([string]$HostText, [string]$HostPath) {
    $tokens = $null; $errors = $null
    $hostAst = [Management.Automation.Language.Parser]::ParseInput($HostText, $HostPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw 'Frozen host source parse errors' }
    $asserts = @($hostAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-Host' }, $true))
    $readers = @($hostAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Read-HostChildStage' }, $true))
    $loops = @($hostAst.FindAll({ param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -ceq 'fixture' }, $true))
    if ($asserts.Count -ne 1 -or $readers.Count -ne 1 -or $loops.Count -ne 1) { throw 'Frozen complete AST units are not unique' }
    $nativeUnits = @($hostAst.EndBlock.Statements | Where-Object { $_.Extent.StartLineNumber -ge 139 -and $_.Extent.EndLineNumber -le 153 })
    if ($nativeUnits.Count -ne 8 -or $nativeUnits[0].Extent.StartLineNumber -ne 139 -or $nativeUnits[7].Extent.EndLineNumber -ne 153 -or
        $nativeUnits[7] -isnot [Management.Automation.Language.ForEachStatementAst]) { throw 'Frozen native compilation unit changed' }
    $nativeText = $HostText.Substring($nativeUnits[0].Extent.StartOffset, $nativeUnits[7].Extent.EndOffset - $nativeUnits[0].Extent.StartOffset)
    $loop = $loops[0]
    if ($loop.Extent.StartLineNumber -ne 362 -or $loop.Extent.EndLineNumber -ne 532) { throw 'Frozen owned loop boundary changed' }
    $assignments = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] }, $true))
    $args = @($assignments | Where-Object { $_.Left.Extent.Text -ceq '$start.Arguments' })
    $ready = @($assignments | Where-Object { $_.Left.Extent.Text -ceq '$pendingReady' -and $_.Right.Extent.Text -ceq '$child.StandardOutput.ReadLineAsync()' })
    $exitWait = @($assignments | Where-Object { $_.Left.Extent.Text -ceq '$exitWaitCompleted' -and $_.Right.Extent.Text -ceq '$child.WaitForExit(10000)' })
    $templates = @($assignments | Where-Object { $_.Left.Extent.Text -ceq '$childCommand' -and $_.Right -is [Management.Automation.Language.CommandExpressionAst] -and $_.Right.Expression -is [Management.Automation.Language.StringConstantExpressionAst] })
    $timeouts = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '-not $pendingReady.Wait(10000)' }, $true))
    $starts = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -ceq "if (-not `$child.Start()) { throw 'Owned child did not start' }" }, $true))
    $exitChecks = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -ceq "if (-not `$exitWaitCompleted) { throw 'Owned child exit timeout' }" }, $true))
    $timeoutThrows = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.ThrowStatementAst] -and $n.Extent.Text.StartsWith('throw "Owned child ready timeout: engine=', [StringComparison]::Ordinal) }, $true))
    if ($args.Count -ne 1 -or $ready.Count -ne 1 -or $exitWait.Count -ne 1 -or $templates.Count -ne 1 -or
        $timeouts.Count -ne 1 -or $starts.Count -ne 1 -or $exitChecks.Count -ne 1 -or $timeoutThrows.Count -ne 1) { throw 'Frozen startup insertion boundary is not unique' }
    $template = $templates[0].Right.Expression.Value
    $body = $loop.Body.Extent.Text
    $baseOffset = $loop.Body.Extent.StartOffset
    $edits = @(
        @{ Start = $args[0].Extent.StartOffset; Length = $args[0].Extent.EndOffset - $args[0].Extent.StartOffset; Anchor = $args[0].Extent.Text; Text = '<# 2026-10-08：仅替换命令输入路径，原 EncodedCommand 参数仍精确校验。 #>' + "`r`n    " + '$start.Arguments = Get-StartupArguments $InputMode $childCommand (' + $args[0].Right.Extent.Text + ')' },
        @{ Start = $starts[0].Extent.StartOffset; Length = 0; Anchor = $starts[0].Extent.Text; Text = '<# 2026-10-08：启动前只记录墙钟和单调时间，不启动预热进程。 #>' + "`r`n        " + 'Add-StartupEvent ''start-before''' + "`r`n        " },
        @{ Start = $ready[0].Extent.StartOffset; Length = 0; Anchor = $ready[0].Extent.Text; Text = '<# 2026-10-08：原 childStarted/PID 已赋值后记录本次实际启动实例。 #>' + "`r`n        " + '$startupLedger.ChildPid = $ownedChildId; $startupLedger.StageNonce = $ownedStageNonce; $startupLedger.StageDirectory = $ownedStageDirectory; Add-StartupEvent ''start-returned''' + "`r`n        " },
        @{ Start = $timeouts[0].Clauses[0].Item2.Statements[0].Extent.StartOffset; Length = 0; Anchor = $timeouts[0].Clauses[0].Item2.Statements[0].Extent.Text; Text = '<# 2026-10-08：保留原 READY 超时分支，旁证不改变错误。 #>' + "`r`n            " + 'Add-StartupEvent ''ready-timeout''' + "`r`n            " },
        @{ Start = $exitWait[0].Extent.StartOffset; Length = 0; Anchor = $exitWait[0].Extent.Text; Text = '<# 2026-10-08：原十秒退出等待前记录时间。 #>' + "`r`n        " + 'Add-StartupEvent ''exit-wait-before''' + "`r`n        " },
        @{ Start = $exitChecks[0].Extent.StartOffset; Length = 0; Anchor = $exitChecks[0].Extent.Text; Text = '<# 2026-10-08：等待结果只记旁证，随后仍执行原退出断言。 #>' + "`r`n        " + '$startupLedger.NormalExitWaitCompleted = $exitWaitCompleted; Add-StartupEvent ''exit-wait-returned''' + "`r`n        " }
        @{ Start = $timeoutThrows[0].Extent.StartOffset; Length = 0; Anchor = $timeoutThrows[0].Extent.Text; Text = '<# 2026-10-08：原超时固定字段另存 artifact，仍由原 throw 返回失败。 #>' + "`r`n            " + '$startupLedger.ReadyTimeoutDiagnosticJson = $diagnosticJson' + "`r`n            " }
    )
    <# 2026-10-08：每个原始 anchor 先逐字确认；PS5 对 Hashtable key 排序必须显式读取，避免无序修改偏移。 #>
    foreach ($edit in $edits) {
        $relative = $edit.Start - $baseOffset
        if ($relative -lt 1 -or $relative + $edit.Anchor.Length -ge $body.Length -or
            $body.Substring($relative, $edit.Anchor.Length) -cne $edit.Anchor) { throw 'Startup insertion escaped complete AST anchor' }
    }
    foreach ($edit in @($edits | Sort-Object -Property @{ Expression = { [int]$_['Start'] }; Descending = $true })) {
        $relative = $edit.Start - $baseOffset
        $body = $body.Remove($relative, $edit.Length).Insert($relative, $edit.Text)
    }
    $originalAssertions = @($loop.Body.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Assert-Host' }, $true) | ForEach-Object { $_.Extent.Text })
    $candidateTokens = $null; $candidateErrors = $null
    $candidateAst = [Management.Automation.Language.Parser]::ParseInput('foreach ($fixture in @(@{ Engine = $native32; Expected = $native32; Bits = 4 })) ' + $body, [ref]$candidateTokens, [ref]$candidateErrors)
    if ($candidateErrors.Count -ne 0) { throw 'Extracted startup loop parse errors' }
    $actualAssertions = @($candidateAst.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Assert-Host' }, $true) | ForEach-Object { $_.Extent.Text })
    if (($originalAssertions -join "`n") -cne ($actualAssertions -join "`n")) { throw 'Original owned identity or stream assertions changed' }
    return [pscustomobject]@{
        AssertText = $asserts[0].Extent.Text; ReaderText = $readers[0].Extent.Text; NativeText = $nativeText
        Template = $template; OriginalBody = $loop.Body.Extent.Text; Body = $body; LoopText = $candidateAst.Extent.Text
        OriginalAssertionCommands = $originalAssertions.Count
    }
}

$hostBytes = [IO.File]::ReadAllBytes($hostSourcePath)
if ((Get-StartupHash $hostBytes) -cne $expectedHostHash) { throw 'Frozen host source hash changed; no child was started' }
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$hostText = $utf8.GetString($hostBytes)
$fragment = Get-StartupFragment $hostText $hostSourcePath
$source = [IO.File]::ReadAllText($scannerSourcePath, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) { $EvidenceDirectory = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'AntigravityAA-Startup-' + [Guid]::NewGuid().ToString('N')) }
if (-not [IO.Path]::IsPathRooted($EvidenceDirectory)) { throw 'Evidence directory must be absolute' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if ([IO.Directory]::Exists($EvidenceDirectory)) { throw 'Evidence directory already exists' }
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$startupClock = [Diagnostics.Stopwatch]::StartNew()
$startupFailure = $null
$startupLedger = [ordered]@{
    Mode = $InputMode; CallerVersion = $PSVersionTable.PSVersion.ToString(); CallerMajor = $ExpectedMajor; CallerBits = [IntPtr]::Size * 8; CallerPid = $PID
    HostSourceSha256 = $expectedHostHash; ScannerSourceSha256 = Get-StartupHash ([IO.File]::ReadAllBytes($scannerSourcePath))
    BodyTemplateSha256 = Get-StartupHash ([Text.Encoding]::UTF8.GetBytes($fragment.Template))
    ActualBodySha256 = $null; ActualBodyCharacters = $null; Utf8BomFileSha256 = $null; InputScriptPath = $null; InputScriptCreated = $false; ArgumentsLength = $null
    ChildPid = $null; StageNonce = $null; StageDirectory = $null; NormalExitWaitCompleted = $null; ReadyTimeoutDiagnosticJson = $null
    AssertionCommandsReused = $fragment.OriginalAssertionCommands; AssertionsPassed = 0; Passed = $false
    Events = @(); DiagnosticErrors = @(); OriginalFailureType = ''; OriginalFailureHResult = $null; OriginalCleanup = $null; InputCleanup = 'not-created'
}
$script:checks = 0
$childStarted = $false
$hasExitedAfterStop = $null
try {
    . ([scriptblock]::Create($fragment.AssertText))
    . ([scriptblock]::Create($fragment.ReaderText))
    . ([scriptblock]::Create($fragment.NativeText))
    $native32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    . ([scriptblock]::Create($fragment.LoopText))
    <# 2026-10-08：旁证作业不能把未回收资源记为成功；原 loop 失败仍由原异常优先返回。 #>
    if ($cleanup.HasExitedAfterStop -ne $true -or $cleanup.DirectoryState -cne 'removed' -or
        $cleanup.QueryError.Length -ne 0 -or $cleanup.StopError.Length -ne 0 -or $cleanup.DirectoryError.Length -ne 0 -or $cleanup.DisposeError.Length -ne 0 -or
        @($cleanup.StageFiles | Where-Object { $_.State -cne 'deleted' -or $_.Error.Length -ne 0 }).Count -ne 0) { throw 'Original owned loop cleanup was not confirmed' }
    $startupLedger.Passed = $true
} catch {
    $startupFailure = $_
    $startupLedger.OriginalFailureType = $_.Exception.GetType().FullName
    $startupLedger.OriginalFailureHResult = $_.Exception.HResult
    throw
} finally {
    Add-StartupEvent 'original-loop-finished'
    $startupLedger.AssertionsPassed = $script:checks
    if ($null -ne $cleanup) { $startupLedger.OriginalCleanup = $cleanup }
    <# 2026-10-08：新增脚本独立清理，不侵入原三个阶段文件清理；确认 child 退出后只删除自有准确 input.ps1。 #>
    if ($startupLedger.InputScriptCreated) {
        if (-not $childStarted -or $hasExitedAfterStop -eq $true) {
            try {
                $inputPath = [IO.Path]::GetFullPath($startupLedger.InputScriptPath)
                if (-not [String]::Equals([IO.Path]::GetDirectoryName($inputPath), $EvidenceDirectory, [StringComparison]::OrdinalIgnoreCase) -or
                    [IO.Path]::GetFileName($inputPath) -cne 'input.ps1') { throw 'Input cleanup ownership changed' }
                [IO.File]::Delete($inputPath)
                $startupLedger.InputCleanup = 'deleted'
            } catch { $startupLedger.InputCleanup = 'delete-error'; $startupLedger.DiagnosticErrors += 'input-cleanup:' + $_.Exception.GetType().FullName }
        } else { $startupLedger.InputCleanup = 'kept-exit-unconfirmed'; $startupLedger.DiagnosticErrors += 'input-cleanup:exit-unconfirmed' }
    }
    if ($startupLedger.DiagnosticErrors.Count -ne 0) { $startupLedger.Passed = $false }
    try {
        $resultPath = [IO.Path]::Combine($EvidenceDirectory, 'result.json')
        $resultBytes = [Text.Encoding]::UTF8.GetBytes(($startupLedger | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
        $resultFile = [IO.File]::Open($resultPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { $resultFile.Write($resultBytes, 0, $resultBytes.Length) } finally { $resultFile.Dispose() }
        [Console]::WriteLine('___CHILD_STARTUP_DIAGNOSTIC___:' + ($startupLedger | ConvertTo-Json -Compress -Depth 8))
    } catch {
        if ($null -eq $startupFailure) { throw }
        <# 2026-10-08：输出通道也可能持续失败，二次日志不能覆盖已保留的原启动异常。 #>
        try { [Console]::WriteLine('___CHILD_STARTUP_LEDGER_ERROR___:' + $_.Exception.GetType().FullName) } catch { }
    }
    if ($null -eq $startupFailure -and $startupLedger.DiagnosticErrors.Count -ne 0) { throw 'Child startup diagnostic or input cleanup failed' }
}
