# 2026-10-05：解析实际扫描器并运行无点击回归，独立互斥名称不干扰真实 IDE。
param([string[]]$PowerShellEngines = @('powershell.exe', 'pwsh.exe'))

$ErrorActionPreference = 'Stop'
$scannerPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))
$source = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Scanner parse errors: $($parseErrors -join '; ')" }
$checks = 1

# 2026-10-05：通过 UTF-8 读取后创建脚本块，兼容 Windows PowerShell 5 的无 BOM 文件。
function Start-TestProcess([string]$Executable, [string]$Command) {
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

# 2026-10-05：读取协议使用有限超时，失败时保留错误输出并由外层清理测试进程。
function Read-ProtocolLine($Process, [string]$Expected) {
    $pending = $Process.StandardOutput.ReadLineAsync()
    if (-not $pending.Wait(8000)) { throw "Protocol timeout: $Expected" }
    $line = $pending.Result
    if ($line -ne $Expected) { throw "Protocol mismatch: expected=$Expected actual=$line" }
}

$engines = @($PowerShellEngines | ForEach-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -ExpandProperty Source -Unique)
if ($engines.Count -eq 0) { throw 'No PowerShell engine found' }
$escapedScannerPath = $scannerPath.Replace("'", "''")
$bootstrapEncoding = '$ProgressPreference = ''SilentlyContinue''; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false);'
foreach ($engine in $engines) {
    $process = Start-TestProcess $engine "$bootstrapEncoding & ([scriptblock]::Create([IO.File]::ReadAllText('$escapedScannerPath', [Text.Encoding]::UTF8))) -SelfTest"
    try {
        if (-not $process.WaitForExit(15000)) { throw 'SelfTest timeout' }
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0 -or $output -notmatch '___SELFTEST_DONE___:passed=93' -or $errorOutput.Length -gt 0) {
            throw "SelfTest failed: engine=$engine exit=$($process.ExitCode) output=$output stderr=$errorOutput"
        }
        Write-Output "PASS SelfTest 93 cases: $engine"
        $checks++
    }
    finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

# 2026-10-05：检查真实点击路径存在窗口命中复核，回归测试自身不调用任何鼠标函数。
$requiredFragments = @(
    'IntPtr hit = WindowFromPoint(point);',
    'IntPtr root = GetAncestor(hit, 2);',
    'if (!IsPointOwnedByWindow(x, y, target, expectedProcessId)) { return false; }',
    '!IsPointOwnedByWindow(x, y, target, expectedProcessId)',
    'currentPoint.X != x || currentPoint.Y != y',
    'if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen) { continue }',
    'if (-not (Get-TargetProcessIds).ContainsKey($windowProcessId)) { continue }'
)
foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) { throw "Missing click guard: $fragment" }
    $checks++
}
if ($source -match '\$rect\.[XY]\s+-lt\s+0|\$winName\s+-notlike|___ALREADY_RUNNING___') { throw 'Unsafe legacy scanner logic remains' }
$checks++

# 2026-10-05：执行实际卡片函数，只将外部 UIA 父节点查找替换成可控树，所有点击为计数桩。
Add-Type -AssemblyName UIAutomationClient
$testFunctions = @('Test-OneTimeApprovalName', 'Test-ApprovalCardShape', 'Test-ApprovalOptionSelected', 'Test-LiveApprovalCard', 'Write-ApprovalDiagnostic', 'Invoke-ApprovalCards', 'Get-ButtonCenter', 'Test-ButtonMatch', 'Test-PrefixBoundary')
foreach ($name in $testFunctions) {
    $definition = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($definition.Count -ne 1) { throw "Missing card function: $name" }
    $functionText = $definition[0].Extent.Text
    if ($name -eq 'Invoke-ApprovalCards') {
        $functionText = $functionText.Replace('[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)', '(Get-TestParent $option)')
        $functionText = $functionText.Replace('[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($card)', '(Get-TestParent $card)')
    }
    . ([scriptblock]::Create($functionText))
}
function Get-TestParent($Node) { return $Node.Parent }
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
$script:testParentAlive = $true
$script:exitParentDuringLookup = $false
function Test-ParentAlive { return $script:testParentAlive }
$script:optionToDeselect = $null
function Get-TargetProcessIds {
    if ($null -ne $script:optionToDeselect) { $script:optionToDeselect.Selection.Current.IsSelected = $false }
    if ($script:exitParentDuringLookup) { $script:testParentAlive = $false }
    return @{ 123 = $true }
}
$conversationCondition = 'conversation'
$editCondition = 'edit'
$radioCondition = 'radio'
$btnCondition = 'button'

# 2026-10-05：构造真实审批树的最小桩，选项和提交的动作仅改变测试对象。
function New-TestApprovalWindow([bool]$HasPermissionTarget, [bool]$InitiallySelected, [bool]$SelectionReadable) {
    $selection = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $InitiallySelected } }
    $selection | Add-Member ScriptMethod Select { $this.Current.IsSelected = $true }
    $option = [pscustomobject]@{
        Current = [pscustomobject]@{ Name = '1 Yes, allow this time'; AutomationId = 'ask-opt-P0-31-1'; IsEnabled = $true; IsOffscreen = $false }
        Selection = $selection
        SelectionReadable = $SelectionReadable
        Parent = $null
    }
    $option | Add-Member ScriptMethod GetCurrentPattern {
        param($pattern)
        if ($pattern.Id -eq [System.Windows.Automation.SelectionItemPattern]::Pattern.Id -and $this.SelectionReadable) { return $this.Selection }
        throw 'Pattern unavailable in test'
    }
    $submit = [pscustomobject]@{ Current = [pscustomobject]@{ Name = ('Submit ' + [char]0x21B5); IsEnabled = $true; IsOffscreen = $false }; Invocations = 0 }
    $submit | Add-Member ScriptMethod Invoke { $this.Invocations++ }
    $submit | Add-Member ScriptMethod GetCurrentPattern { param($pattern) return $this }
    $editName = if ($HasPermissionTarget) { 'Edit permission target' } else { 'Other question' }
    $card = [pscustomobject]@{
        Edits = @([pscustomobject]@{ Current = [pscustomobject]@{ Name = $editName } })
        Radios = @($option,
            [pscustomobject]@{ Current = [pscustomobject]@{ Name = '2 Yes, and always allow command'; AutomationId = 'ask-opt-P0-31-2' } },
            [pscustomobject]@{ Current = [pscustomobject]@{ Name = '4 No (tell the agent what to do instead)'; AutomationId = 'ask-opt-P0-31-__write_in__' } })
        Buttons = @($submit)
    }
    $card | Add-Member ScriptMethod FindAll {
        param($scope, $condition)
        switch ($condition) { 'edit' { return $this.Edits }; 'radio' { return $this.Radios }; 'button' { return $this.Buttons } }
    }
    $option.Parent = [pscustomobject]@{ Parent = $card }
    $window = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; NativeWindowHandle = 42 }; Card = $card }
    $window | Add-Member ScriptMethod FindFirst { param($scope, $condition) return $this.Card }
    return $window
}
foreach ($case in @(
    @{ Target = $true; Selected = $true; Readable = $true; Expected = 1 },
    @{ Target = $true; Selected = $false; Readable = $true; Expected = 1 },
    @{ Target = $false; Selected = $true; Readable = $true; Expected = 0 },
    @{ Target = $true; Selected = $false; Readable = $false; Expected = 0 }
)) {
    $window = New-TestApprovalWindow $case.Target $case.Selected $case.Readable
    $actual = Invoke-ApprovalCards $window 123 ([IntPtr]42)
    if ($window.Card.Buttons[0].Invocations -ne $case.Expected -or $actual -ne ($case.Expected -eq 1)) {
        throw "Card approval scope failed: target=$($case.Target) selected=$($case.Selected) readable=$($case.Readable)"
    }
    $checks++
}
Write-Output 'PASS permission-card scope, one-time selection, and unreadable selection skip'

# 2026-10-05：宿主归属检查期间取消本次允许，实际提交函数必须重新读取并跳过。
$window = New-TestApprovalWindow $true $true $true
$script:optionToDeselect = $window.Card.Radios[0]
try {
    $actual = Invoke-ApprovalCards $window 123 ([IntPtr]42)
    if ($actual -or $window.Card.Buttons[0].Invocations -ne 0) { throw 'Lost one-time selection was submitted' }
    $checks++
    Write-Output 'PASS one-time selection changed after initial check: skipped'
}
finally { $script:optionToDeselect = $null }

# 2026-10-05：宿主归属查询期间模拟父进程退出，现代卡片最终调用前必须停止提交。
$window = New-TestApprovalWindow $true $true $true
$script:exitParentDuringLookup = $true
try {
    $actual = Invoke-ApprovalCards $window 123 ([IntPtr]42)
    if ($actual -or $window.Card.Buttons[0].Invocations -ne 0) { throw 'Permission card submitted after parent exit during lookup' }
    $checks++
    Write-Output 'PASS parent exit during host lookup: permission Submit skipped'
}
finally {
    $script:exitParentDuringLookup = $false
    $script:testParentAlive = $true
}

# 2026-10-05：只提取实际父进程及互斥生命周期代码，目标进程返回空集合以阻止扫描和点击。
$parentFunction = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-ParentAlive' }, $true)
if ($parentFunction.Count -ne 1) { throw 'Parent lifecycle function not found' }
$tailIndex = $source.IndexOf('$script:parentProcess = $null', [StringComparison]::Ordinal)
if ($tailIndex -lt 0) { throw 'Mutex lifecycle entry not found' }
$mutexName = 'Local\AntigravityAutoAcceptScanner.Test.' + [Guid]::NewGuid().ToString('N')
$lifecycleSource = $source.Substring($tailIndex).Replace('Local\AntigravityAutoAcceptScanner', $mutexName)

# 2026-10-05：执行实际扫描尾段，控件查找期间模拟父宿主退出，旧版 Run 的调用桩必须保持零次。
$script:testParentAlive = $true
function Test-ParentAlive { return $script:testParentAlive }
function Invoke-ApprovalCards { return $false }
$legacyButton = [pscustomobject]@{
    Current = [pscustomobject]@{ Name = 'Run'; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 0; Y = 0; Width = 100; Height = 40 } }
    Invocations = 0
}
$legacyButton | Add-Member ScriptMethod Invoke { $this.Invocations++ }
$legacyButton | Add-Member ScriptMethod GetCurrentPattern { param($pattern) return $this }
$legacyWindow = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; NativeWindowHandle = 42 }; Buttons = @($legacyButton) }
$legacyWindow | Add-Member ScriptMethod FindAll {
    param($scope, $condition)
    $script:testParentAlive = $false
    return $this.Buttons
}
$automation = [pscustomobject]@{ Window = $legacyWindow }
$automation | Add-Member ScriptMethod FindAll { param($scope, $condition) return @($this.Window) }
$winCondition = 'window'
$PollMs = 50
$CooldownMs = 0
$ParentProcessId = 0
. ([scriptblock]::Create($lifecycleSource))
if ($legacyButton.Invocations -ne 0) { throw 'Legacy button invoked after parent exit during scan' }
$checks++
Write-Output 'PASS parent exit during button search: legacy Invoke skipped'

$stub = $parentFunction[0].Extent.Text + "`nfunction Get-TargetProcessIds { return @{} }`n"
$engine = $engines[0]
$processes = New-Object Collections.Generic.List[Diagnostics.Process]
try {
    foreach ($abandonOwner in @($false, $true)) {
        $ownerParent = Start-TestProcess $engine 'Start-Sleep -Seconds 60'
        $processes.Add($ownerParent)
        $waiterParent = Start-TestProcess $engine 'Start-Sleep -Seconds 60'
        $processes.Add($waiterParent)
        $common = "$bootstrapEncoding `$PollMs = 50; `$CooldownMs = 0; $stub"
        $owner = Start-TestProcess $engine "$common `$ParentProcessId = $($ownerParent.Id); $lifecycleSource"
        $processes.Add($owner)
        Read-ProtocolLine $owner '___AUTOCLICK_READY___'
        $checks++
        $waiter = Start-TestProcess $engine "$common `$ParentProcessId = $($waiterParent.Id); $lifecycleSource"
        $processes.Add($waiter)
        Read-ProtocolLine $waiter '___SCANNER_WAITING___'
        if ($waiter.HasExited) { throw 'Waiting scanner exited instead of waiting' }
        $checks++
        if ($abandonOwner) { $owner.Kill(); $owner.WaitForExit() }
        else {
            $ownerParent.Kill(); $ownerParent.WaitForExit()
            if (-not $owner.WaitForExit(5000) -or $owner.ExitCode -ne 0) { throw 'Owner did not exit after its parent' }
        }
        Read-ProtocolLine $waiter '___AUTOCLICK_READY___'
        $checks++
        $waiterParent.Kill(); $waiterParent.WaitForExit()
        if (-not $waiter.WaitForExit(5000) -or $waiter.ExitCode -ne 0) { throw 'Waiter did not exit after its parent' }
        $checks++
        Write-Output "PASS mutex handoff and parent exit: abandoned=$abandonOwner"
    }
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

# 2026-10-05：原扫描器与测试均保持 UTF-8 无 BOM、纯 CRLF，禁止隐式编码迁移。
foreach ($path in @($scannerPath, $PSCommandPath)) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    $body = $strictUtf8.GetString($bytes)
    if (($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) -or $body -match '(?<!\r)\n|\r(?!\n)') {
        throw "Encoding or newline changed: $path"
    }
    $checks++
}
Write-Output "___SCANNER_TEST_DONE___:passed=$checks"
