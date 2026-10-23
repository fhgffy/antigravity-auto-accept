# 2026-10-23：执行真实维护块和诊断入口，只用计数对象替换 UIA 属性，不访问桌面。
param([string]$ScannerSourcePath = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$path = if ($ScannerSourcePath) { [IO.Path]::GetFullPath($ScannerSourcePath) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1')) }
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Scanner source parse failed' }
$script:unusedReadChecks = 0
$script:unusedReadFailures = [Collections.Generic.List[string]]::new()
function Assert-UnusedRead($Condition, [string]$Message) {
    $script:unusedReadChecks++
    if (-not $Condition) { $script:unusedReadFailures.Add($Message) }
}

# 2026-10-23：按块内直接赋值定位完整 if，避免冻结条件而绕过被测的空表分支。
$maintenance = @($ast.FindAll({ param($node)
    if ($node -isnot [Management.Automation.Language.IfStatementAst]) { return $false }
    return @($node.Clauses[0].Item2.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'liveMenuWindowKeys'
    }).Count -eq 1
}, $true))
if ($maintenance.Count -ne 1) { throw 'Exact deferred menu maintenance boundary missing' }
$maintenanceBlock = [scriptblock]::Create($maintenance[0].Extent.Text)
$menuWindow = [pscustomobject]@{ Handle = 42; Fail = $false; Reads = 0 }
$menuWindow | Add-Member ScriptProperty Current {
    $this.Reads++
    if ($this.Fail) { throw 'Expected unavailable window identity' }
    return [pscustomobject]@{ NativeWindowHandle = $this.Handle }
}
$windows = @($menuWindow)
$recycleDue = $false
$script:deferredBrowserMenus = $null
& $maintenanceBlock
Assert-UnusedRead ($menuWindow.Reads -eq 0 -and $null -eq $script:deferredBrowserMenus) 'Null menu state read window properties'
$script:deferredBrowserMenus = @{}
& $maintenanceBlock
Assert-UnusedRead ($menuWindow.Reads -eq 0 -and $script:deferredBrowserMenus.Count -eq 0) 'Empty menu state read window properties'
$menuWindow.Reads = 0
$pendingMenu = [pscustomobject]@{ MenuId = 'pending'; ProcessId = 123 }
$script:deferredBrowserMenus = @{ '42' = $pendingMenu; '99' = $pendingMenu }
& $maintenanceBlock
Assert-UnusedRead ($menuWindow.Reads -eq 1 -and $script:deferredBrowserMenus.Count -eq 1 -and [object]::ReferenceEquals($script:deferredBrowserMenus['42'], $pendingMenu)) 'Live menu lost or closed window menu retained'
foreach ($identityFailure in @('throws', 'null', 'zero')) {
    $menuWindow.Reads = 0; $menuWindow.Fail = $identityFailure -eq 'throws'
    $menuWindow.Handle = if ($identityFailure -eq 'zero') { 0 } else { $null }
    $script:deferredBrowserMenus = @{ '42' = $pendingMenu; '99' = $pendingMenu }
    & $maintenanceBlock
    Assert-UnusedRead ($menuWindow.Reads -eq 1 -and $script:deferredBrowserMenus.Count -eq 2 -and [object]::ReferenceEquals($script:deferredBrowserMenus['42'], $pendingMenu) -and [object]::ReferenceEquals($script:deferredBrowserMenus['99'], $pendingMenu)) "Incomplete identity pruned menu state: $identityFailure"
}
$windows = @()
& $maintenanceBlock
Assert-UnusedRead ($script:deferredBrowserMenus.Count -eq 0) 'Complete empty window snapshot retained closed menus'

# 2026-10-23：提取三个原诊断 try 和真实日志函数；不复制诊断条件、消息工厂或异常处理。
$logger = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-ApprovalDiagnostic' }, $true))
$cards = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-ApprovalCards' }, $true))
if ($logger.Count -ne 1 -or $cards.Count -ne 1) { throw 'Exact approval diagnostic functions missing' }
. ([scriptblock]::Create($logger[0].Extent.Text))
$diagnosticElement = [pscustomobject]@{ Reads = 0; Fail = $false }
$diagnosticElement | Add-Member ScriptMethod GetCurrentPropertyValue {
    param($property)
    $this.Reads++
    if ($this.Fail) { throw 'Expected diagnostic provider failure' }
    return $property -ne [System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty
}
$diagnosticElement | Add-Member ScriptProperty Current {
    $this.Reads++
    return [pscustomobject]@{ IsEnabled = $true; IsOffscreen = $false }
}
$target = $diagnosticElement; $option = $diagnosticElement; $submit = $diagnosticElement
$cases = @(
    @{ Category = 'permission-target-pattern'; Reads = 1; Message = 'permission target value-pattern=True' },
    @{ Category = 'permission-candidate'; Reads = 4; Message = 'permission option enabled=True offscreen=False selection=True scrollitem=False' },
    @{ Category = 'permission-submit-pattern'; Reads = 4; Message = 'permission submit enabled=True offscreen=False invoke=True scrollitem=False' }
)
$savedWriter = [Console]::Out
$writer = [IO.StringWriter]::new()
try {
    [Console]::SetOut($writer)
    foreach ($case in $cases) {
        $commands = @($cards[0].FindAll({ param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Write-ApprovalDiagnostic' -and @($node.CommandElements | Where-Object { $_ -is [Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -ceq $case.Category }).Count -eq 1
        }, $true))
        if ($commands.Count -ne 1) { throw "Exact diagnostic call missing: $($case.Category)" }
        $diagnosticTry = $commands[0].Parent
        while ($null -ne $diagnosticTry -and $diagnosticTry -isnot [Management.Automation.Language.TryStatementAst]) { $diagnosticTry = $diagnosticTry.Parent }
        if ($null -eq $diagnosticTry -or $diagnosticTry.CatchClauses.Count -ne 1 -or $diagnosticTry.CatchClauses[0].Body.Statements.Count -ne 0) { throw 'Expected diagnostic-only try/catch boundary' }
        $diagnosticBlock = [scriptblock]::Create($diagnosticTry.Extent.Text)
        $recent = [DateTime]::Now.AddSeconds(2)
        $script:approvalDiagnosticTimes = @{}
        foreach ($other in $cases) { $script:approvalDiagnosticTimes[$other.Category] = $recent }
        $script:lastApprovalDiagnosticTime = $recent
        $diagnosticElement.Reads = 0; $diagnosticElement.Fail = $false
        $writer.GetStringBuilder().Length = 0
        & $diagnosticBlock
        Assert-UnusedRead ($diagnosticElement.Reads -eq 0 -and $writer.ToString() -eq '' -and $script:approvalDiagnosticTimes[$case.Category] -eq $recent) "Throttled diagnostic read properties: $($case.Category)"

        $due = [DateTime]::Now.AddSeconds(-20)
        $script:approvalDiagnosticTimes[$case.Category] = $due
        $diagnosticElement.Reads = 0; $diagnosticElement.Fail = $true
        $continued = $false
        & $diagnosticBlock
        $continued = $true
        Assert-UnusedRead ($continued -and $diagnosticElement.Reads -eq 1 -and $writer.ToString() -eq '' -and $script:approvalDiagnosticTimes[$case.Category] -eq $due) "Diagnostic failure consumed category or escaped caller: $($case.Category)"

        $diagnosticElement.Reads = 0; $diagnosticElement.Fail = $false
        $before = [DateTime]::Now
        & $diagnosticBlock
        $after = [DateTime]::Now
        Assert-UnusedRead ($diagnosticElement.Reads -eq $case.Reads -and $writer.ToString() -ceq ("___SCANNER_DIAGNOSTIC___:" + $case.Message + [Environment]::NewLine) -and $script:approvalDiagnosticTimes[$case.Category] -ge $before -and $script:approvalDiagnosticTimes[$case.Category] -le $after) "Due diagnostic changed original message or reads: $($case.Category)"
        Assert-UnusedRead (@($cases | Where-Object { $_.Category -ne $case.Category -and $script:approvalDiagnosticTimes[$_.Category] -ne $recent }).Count -eq 0 -and $script:lastApprovalDiagnosticTime -eq $recent) "Diagnostic categories interfered: $($case.Category)"
    }

    # 2026-10-23：保留旧字符串入口，并验证独立浏览器时钟及工厂读取调用者局部变量。
    $writer.GetStringBuilder().Length = 0
    $script:approvalDiagnosticTimes = @{}
    Write-ApprovalDiagnostic 'legacy first'
    $legacyTime = $script:approvalDiagnosticTimes['approval']
    Write-ApprovalDiagnostic 'legacy suppressed'
    Assert-UnusedRead ($writer.ToString() -ceq ("___SCANNER_DIAGNOSTIC___:legacy first" + [Environment]::NewLine) -and $script:approvalDiagnosticTimes['approval'] -eq $legacyTime) 'Legacy string diagnostics changed'
    $writer.GetStringBuilder().Length = 0
    $script:lastApprovalDiagnosticTime = [DateTime]::Now.AddSeconds(-20)
    $script:factoryCalls = 0
    & {
        $callerLocal = 'caller-local-value'
        Write-ApprovalDiagnostic -Category 'browser-candidate' -MessageFactory { $script:factoryCalls++; $callerLocal }
        Write-ApprovalDiagnostic -Category 'browser-candidate' -MessageFactory { $script:factoryCalls++; 'suppressed' }
    }
    Assert-UnusedRead ($script:factoryCalls -eq 1 -and $writer.ToString() -ceq ("___SCANNER_DIAGNOSTIC___:caller-local-value" + [Environment]::NewLine) -and -not $script:approvalDiagnosticTimes.ContainsKey('browser-candidate') -and $script:approvalDiagnosticTimes['approval'] -eq $legacyTime) 'Browser factory lost caller scope, independent clock, or throttling'
}
finally { [Console]::SetOut($savedWriter); $writer.Dispose() }
if ($script:unusedReadFailures.Count) { throw ('Unused read regression: ' + ($script:unusedReadFailures -join '; ')) }
Write-Output "PASS unused UIA reads: $script:unusedReadChecks checks"
