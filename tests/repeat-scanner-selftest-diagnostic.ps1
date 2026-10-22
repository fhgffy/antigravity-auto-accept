# 2026-10-22：87项纯规则仍受原十五秒期限约束；原8项C#窗口归属断言在mouse-helper真实编译回归执行。
# 2026-10-22：仅手动诊断重复真实SelfTest包装循环；每次保持十五秒和严格原断言，首次失败即停止。
param([ValidateSet(5,7)][int]$ExpectedMajor, [string]$Engine, [ValidateRange(1,20)][int]$Repetitions = 20, [Parameter(Mandatory=$true)][string]$EvidenceDirectory, [string]$TimeoutCollectorPath = '')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne $ExpectedMajor) { throw 'Unexpected SelfTest diagnostic caller' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if ([IO.Directory]::Exists($EvidenceDirectory)) { throw 'Preserve existing SelfTest evidence' }
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$wrapperPath = Join-Path $PSScriptRoot 'scanner.test.ps1'
$scannerPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($wrapperPath, [Text.Encoding]::UTF8), $wrapperPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'SelfTest diagnostic source parse failed' }
foreach ($name in @('Start-TestProcess', 'Save-ScannerTimeoutEvidence')) {
    $definition = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $true))
    if ($definition.Count -ne 1) { throw "SelfTest diagnostic function boundary missing: $name" }
    $functionAst = [Management.Automation.Language.Parser]::ParseInput($definition[0].Extent.Text, $wrapperPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'SelfTest diagnostic function parse failed' }
    . ($functionAst.GetScriptBlock())
}
$bootstrap = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'bootstrapEncoding' })
$loop = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.ForEachStatementAst] -and $_.Extent.Text.Contains('SelfTest failed:') })
if ($bootstrap.Count -ne 1 -or $loop.Count -ne 1) { throw 'Exact SelfTest loop or encoding assignment missing' }
. ([scriptblock]::Create($bootstrap[0].Extent.Text))
$body = [scriptblock]::Create($loop[0].Extent.Text)
$engines = @((Get-Command $Engine -ErrorAction Stop).Source)
$escapedScannerPath = $scannerPath.Replace("'", "''")
$ExpectedSelfTestCount = 87
$checks = 0
$header = [ordered]@{ Engine = $engines[0]; CallerVersion = $PSVersionTable.PSVersion.ToString(); Repetitions = $Repetitions; DeadlineMs = 15000; ScannerSHA256 = (Get-FileHash $scannerPath -Algorithm SHA256).Hash.ToLowerInvariant(); WrapperSHA256 = (Get-FileHash $wrapperPath -Algorithm SHA256).Hash.ToLowerInvariant() }
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'identity.json'), ($header | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
foreach ($iteration in 1..$Repetitions) {
    $record = [ordered]@{ Iteration = $iteration; StartedUtc = [DateTime]::UtcNow.ToString('o'); ElapsedMs = 0; Passed = $false }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    # 2026-10-22：正文失败优先保留；旁证落盘失败另行报告，成功正文的记录失败本身仍须失败。
    $failure = $null
    try {
        & $body
        $record.Passed = $true
    }
    catch { $failure = $_ }
    finally {
        $record.ElapsedMs = $clock.ElapsedMilliseconds
        try {
            [IO.File]::WriteAllText((Join-Path $EvidenceDirectory ('case-' + $iteration + '.json')), ($record | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        }
        catch {
            $writeFailure = $_
            try { [Console]::Error.WriteLine('___SELFTEST_DIAGNOSTIC_WRITE_FAILED___:' + $writeFailure.Exception.GetBaseException().Message) } catch { }
            if ($null -eq $failure) { throw $writeFailure }
        }
    }
    if ($null -ne $failure) { throw $failure }
}
Write-Output "___SCANNER_SELFTEST_DIAGNOSTIC_DONE___:passed=$Repetitions"
