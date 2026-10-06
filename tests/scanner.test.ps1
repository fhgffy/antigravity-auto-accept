# 2026-10-05：解析实际扫描器并运行无点击回归，独立互斥名称不干扰真实 IDE。
# 2026-10-06：旧源码副本可指定原自测数量，使红灯证据落在行为缺陷而非数量变化。
param([string[]]$PowerShellEngines = @('powershell.exe', 'pwsh.exe'), [string]$ScannerSourcePath = '', [int]$ExpectedSelfTestCount = 95)

$ErrorActionPreference = 'Stop'
# 2026-10-06：允许只读旧源码副本复现红灯，避免回滚共享工作区中的修复。
$scannerPath = if ([string]::IsNullOrWhiteSpace($ScannerSourcePath)) { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1')) } else { [IO.Path]::GetFullPath($ScannerSourcePath) }
$source = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Scanner parse errors: $($parseErrors -join '; ')" }
$checks = 1

# 2026-10-06：实际按钮函数依赖源码匹配表，测试也加载原表，避免空变量把误批掩盖成未命中。
foreach ($name in @('targetPrefixes', 'excludeExact', 'exactOnly')) {
    $assignment = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq $name }, $true)
    if ($assignment.Count -ne 1) { throw "Missing button matching table: $name" }
    . ([scriptblock]::Create($assignment[0].Extent.Text))
}

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
        if ($process.ExitCode -ne 0 -or $output -notmatch ("___SELFTEST_DONE___:passed=$ExpectedSelfTestCount\b") -or $errorOutput.Length -gt 0) {
            throw "SelfTest failed: engine=$engine exit=$($process.ExitCode) output=$output stderr=$errorOutput"
        }
        Write-Output "PASS SelfTest $ExpectedSelfTestCount cases: $engine"
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
        # 2026-10-06：新增归属复核也使用同一可控父链，不在回归中访问真实桌面控件。
        $functionText = $functionText.Replace('[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)', '(Get-TestParent $optionGroup)')
        $functionText = $functionText.Replace('[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($submit)', '(Get-TestParent $submit)')
    }
    . ([scriptblock]::Create($functionText))
}
# 2026-10-06：浏览器卡片函数存在时执行实际实现，旧版没有该入口时由扫描尾段复现漏批。
foreach ($name in @('Test-BrowserPermissionText', 'Test-BrowserPermissionCardShape', 'Test-LiveBrowserPermissionCard', 'Test-BrowserMenuAnchor', 'Get-VisibleBrowserMenus', 'Write-BrowserCandidateDiagnostic', 'Invoke-BrowserPermissionCards')) {
    $definition = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($definition.Count -eq 0) { continue }
    $functionText = $definition[0].Extent.Text.Replace('[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($allow)', '(Get-TestParent $allow)')
    . ([scriptblock]::Create($functionText))
}
function Get-TestParent($Node) { return $Node.Parent }
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
$script:approvalDiagnosticTimes = @{}
$script:testParentAlive = $true
$script:exitParentDuringLookup = $false
function Test-ParentAlive { return $script:testParentAlive }
$script:optionToDeselect = $null
# 2026-10-06：宿主归属查询期间只在测试内改变卡片状态，复现最后查询与动作之间的竞态。
$script:browserHostLookupWindow = $null
$script:browserHostLookupCount = 0
function Get-TargetProcessIds {
    if ($null -ne $script:optionToDeselect) { $script:optionToDeselect.Selection.Current.IsSelected = $false }
    if ($script:exitParentDuringLookup) { $script:testParentAlive = $false }
    if ($null -ne $script:browserHostLookupWindow) {
        $script:browserHostLookupCount++
        $mutation = $script:browserHostLookupWindow
        if ($script:browserHostLookupCount -eq $mutation.Lookup) {
            if ($mutation.State -eq 'card') { $mutation.Window.Card.Texts[0].Current.Name = 'Ordinary card' }
            elseif ($mutation.State -eq 'once-offscreen') { $mutation.Window.Once.Current.IsOffscreen = $true }
            elseif ($mutation.State -eq 'menu-offscreen') { $mutation.Window.Menu.Current.IsOffscreen = $true }
        }
    }
    return @{ 123 = $true }
}
$conversationCondition = 'conversation'
$editCondition = 'edit'
$radioCondition = 'radio'
$btnCondition = 'button'

# 2026-10-05：构造真实审批树的最小桩，选项和提交的动作仅改变测试对象。
function New-TestApprovalWindow([bool]$HasPermissionTarget, [bool]$InitiallySelected, [bool]$SelectionReadable, [string]$Mode = '') {
    # 2026-10-06：会话兄弟区域和长权限表单均使用真实两层父链，滚动只改变内存控件状态。
    $selection = [pscustomobject]@{ Current = [pscustomobject]@{ IsSelected = $InitiallySelected }; Selects = 0 }
    $selection | Add-Member ScriptMethod Select { $this.Selects++; $this.Current.IsSelected = $true }
    $option = [pscustomobject]@{
        Current = [pscustomobject]@{ Name = '1 Yes, allow this time'; AutomationId = 'ask-opt-P0-31-1'; IsEnabled = $true; IsOffscreen = ($Mode -like 'option-*') }
        Selection = $selection
        SelectionReadable = $SelectionReadable
        Parent = $null
        Window = $null
        Scrolls = 0
    }
    $option | Add-Member ScriptMethod GetCurrentPattern {
        param($pattern)
        if ($pattern.Id -eq [System.Windows.Automation.ScrollItemPattern]::Pattern.Id -and $this.Window.Mode -ne 'option-scroll-unsupported') { return $this }
        if ($pattern.Id -eq [System.Windows.Automation.SelectionItemPattern]::Pattern.Id -and $this.SelectionReadable) { return $this.Selection }
        throw 'Pattern unavailable in test'
    }
    $option | Add-Member ScriptMethod GetCurrentPropertyValue { param($property) if ($property.Id -eq [System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty.Id -and $this.Window.Mode -eq 'option-scroll-unsupported') { return $false }; return $true } # 2026-10-06：固定模式只读诊断不访问真实桌面。
    $option | Add-Member ScriptMethod ScrollIntoView {
        $this.Scrolls++
        if ($this.Window.Mode -eq 'option-scroll-throws') { throw 'ScrollIntoView failed in test' } # 2026-10-06：滚动本身失败也不得继续选择或提交。
        if ($this.Window.Mode -ne 'option-scroll-still-offscreen') { $this.Current.IsOffscreen = $false }
        if ($this.Window.Mode -eq 'option-scroll-parent-exit') { $script:testParentAlive = $false }
        if ($this.Window.Mode -eq 'option-scroll-host-changed') { $this.Window.Current.ProcessId = 999 }
        if ($this.Window.Mode -eq 'option-scroll-target-changed') { $this.Window.Card.Edits[0].Current.Value = 'Write-Output CHANGED_TARGET' }
        if ($this.Window.Mode -eq 'option-scroll-target-replaced') { $this.Window.Card.Edits[0].Key = 9825 } # 2026-10-06：同值目标被替换也不能沿用旧控件批准。
        if ($this.Window.Mode -eq 'option-scroll-form-changed') {
            $otherCard = [pscustomobject]@{ Key = 999 }
            $otherCard | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
            $this.Parent = [pscustomobject]@{ Parent = $otherCard }
        }
    }
    $submit = [pscustomobject]@{ Current = [pscustomobject]@{ Name = ('Submit ' + [char]0x21B5); IsEnabled = $true; IsOffscreen = ($Mode -like 'submit-*') }; Invocations = 0; Scrolls = 0; Window = $null; Parent = $null }
    $submit | Add-Member ScriptMethod Invoke { $this.Invocations++ }
    $submit | Add-Member ScriptMethod GetCurrentPattern { param($pattern) if ($pattern.Id -eq [System.Windows.Automation.ScrollItemPattern]::Pattern.Id -and $this.Window.Mode -eq 'submit-scroll-unsupported') { throw 'ScrollItem unavailable in test' }; return $this }
    $submit | Add-Member ScriptMethod GetCurrentPropertyValue { param($property) if ($property.Id -eq [System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty.Id -and $this.Window.Mode -eq 'submit-scroll-unsupported') { return $false }; return $true } # 2026-10-06：提交按钮诊断仅返回桩内支持布尔值。
    $submit | Add-Member ScriptMethod ScrollIntoView {
        $this.Scrolls++
        if ($this.Window.Mode -eq 'submit-scroll-throws') { throw 'ScrollIntoView failed in test' } # 2026-10-06：提交按钮滚动失败只计数，不产生真实点击。
        if ($this.Window.Mode -ne 'submit-scroll-still-offscreen') { $this.Current.IsOffscreen = $false }
        if ($this.Window.Mode -eq 'submit-scroll-parent-exit') { $script:testParentAlive = $false }
        if ($this.Window.Mode -eq 'submit-scroll-host-changed') { $this.Window.Current.ProcessId = 999 }
        if ($this.Window.Mode -eq 'submit-scroll-target-changed') { $this.Window.Card.Edits[0].Current.Value = 'Write-Output CHANGED_TARGET' }
        if ($this.Window.Mode -eq 'submit-scroll-target-replaced') { $this.Window.Card.Edits[0].Key = 9825 } # 2026-10-06：提交滚动期间更换目标控件时必须停止。
        if ($this.Window.Mode -eq 'submit-scroll-lost-selection') { $this.Window.Card.Radios[0].Selection.Current.IsSelected = $false }
        if ($this.Window.Mode -eq 'submit-scroll-hides-option') { $this.Window.Card.Radios[0].Current.IsOffscreen = $true }
        if ($this.Window.Mode -eq 'submit-scroll-renamed') { $this.Current.Name = 'Save' }
        if ($this.Window.Mode -eq 'submit-scroll-form-changed') {
            $this.Parent = [pscustomobject]@{ Key = 999 }
            $this.Parent | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
        }
    }
    $editName = if ($HasPermissionTarget) { 'Edit permission target' } else { 'Other question' }
    # 2026-10-06：目标值与控件身份按真实 ValuePattern 提供，改变命令正文而保留标签才能验证目标竞态。
    $target = [pscustomobject]@{ Current = [pscustomobject]@{ Name = $editName; Value = 'Write-Output AA_TEST' }; Key = 9824 }
    $target | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
    $target | Add-Member ScriptMethod GetCurrentPattern { param($pattern) if ($pattern.Id -eq [System.Windows.Automation.ValuePattern]::Pattern.Id) { return $this }; throw 'Target pattern unavailable' }
    $target | Add-Member ScriptMethod GetCurrentPropertyValue { param($property) return $true } # 2026-10-06：目标模式支持诊断不输出命令值。
    $card = [pscustomobject]@{
        Key = 824
        Edits = @($target)
        Radios = @($option,
            [pscustomobject]@{ Current = [pscustomobject]@{ Name = '2 Yes, and always allow command'; AutomationId = 'ask-opt-P0-31-2' } },
            [pscustomobject]@{ Current = [pscustomobject]@{ Name = '4 No (tell the agent what to do instead)'; AutomationId = 'ask-opt-P0-31-__write_in__' } })
        Buttons = @($submit)
    }
    $card | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
    $card | Add-Member ScriptMethod FindAll {
        param($scope, $condition)
        switch ($condition) { 'edit' { return $this.Edits }; 'radio' { return $this.Radios }; 'button' { return $this.Buttons } }
    }
    $option.Parent = [pscustomobject]@{ Parent = $card }
    $submit.Parent = $card
    if ($Mode -eq 'external-mixed-prefix') { $card.Radios[1].Current.AutomationId = 'ask-opt-P0-999-2' }
    if ($Mode -eq 'external-duplicate-submit') { $card.Buttons += [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Submit' } } }
    $emptyConversation = [pscustomobject]@{}
    $emptyConversation | Add-Member ScriptMethod FindAll { param($scope, $condition) return @() }
    $window = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; NativeWindowHandle = 42 }; Card = $card; Mode = $Mode; EmptyConversation = $emptyConversation }
    $option.Window = $window
    $submit.Window = $window
    $window | Add-Member ScriptMethod FindFirst { param($scope, $condition) if ($this.Mode -ne '') { return $this.EmptyConversation }; return $this.Card }
    $window | Add-Member ScriptMethod FindAll { param($scope, $condition) if ($condition -eq 'radio') { return $this.Card.Radios }; return @() }
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

# 2026-10-06：真实窗口候选中包含会话外专用表单，普通问答及滚动后失效仍必须保持零提交。
$externalFailures = @()
foreach ($case in @(
    @{ Mode = 'external-selected'; Target = $true; Selected = $true; Expected = 1 },
    @{ Mode = 'external-select-once'; Target = $true; Selected = $false; Expected = 1 },
    @{ Mode = 'external-question'; Target = $false; Selected = $true; Expected = 0 },
    @{ Mode = 'external-mixed-prefix'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'external-duplicate-submit'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'option-scroll'; Target = $true; Selected = $false; Expected = 1 },
    @{ Mode = 'option-scroll-unsupported'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-throws'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-still-offscreen'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-parent-exit'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-host-changed'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-target-changed'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-target-replaced'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'option-scroll-form-changed'; Target = $true; Selected = $false; Expected = 0 },
    @{ Mode = 'submit-scroll'; Target = $true; Selected = $true; Expected = 1 },
    @{ Mode = 'submit-scroll-hides-option'; Target = $true; Selected = $true; Expected = 1 },
    @{ Mode = 'submit-scroll-unsupported'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-throws'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-still-offscreen'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-parent-exit'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-host-changed'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-target-changed'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-target-replaced'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-lost-selection'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-renamed'; Target = $true; Selected = $true; Expected = 0 },
    @{ Mode = 'submit-scroll-form-changed'; Target = $true; Selected = $true; Expected = 0 }
)) {
    $script:testParentAlive = $true
    $window = New-TestApprovalWindow $case.Target $case.Selected $true $case.Mode
    $actual = Invoke-ApprovalCards $window 123 ([IntPtr]42)
    # 2026-10-06：阴性滚动案例必须到达对应真实动作，不能因树桩缺失而提前异常形成假通过。
    $expectedOptionScrolls = if ($case.Mode -like 'option-*' -and $case.Mode -ne 'option-scroll-unsupported') { 1 } else { 0 }
    $expectedSubmitScrolls = if ($case.Mode -like 'submit-*' -and $case.Mode -ne 'submit-scroll-unsupported') { 1 } else { 0 }
    $description = "$($case.Mode) expected=$($case.Expected) result=$actual submit=$($window.Card.Buttons[0].Invocations) option-scrolls=$($window.Card.Radios[0].Scrolls) submit-scrolls=$($window.Card.Buttons[0].Scrolls)"
    if ($actual -ne ($case.Expected -eq 1) -or $window.Card.Buttons[0].Invocations -ne $case.Expected -or $window.Card.Radios[0].Scrolls -ne $expectedOptionScrolls -or $window.Card.Buttons[0].Scrolls -ne $expectedSubmitScrolls) { $externalFailures += $description; Write-Output "FAIL external permission: $description" }
    else { $checks++; Write-Output "PASS external permission: $description" }
}
if ($externalFailures.Count -gt 0) { throw "External permission regressions: $($externalFailures -join '; ')" }
$script:testParentAlive = $true

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
$legacyWindow | Add-Member ScriptMethod FindFirst { param($scope, $condition) return $null }
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

# 2026-10-06：实际扫描尾段复现窄浏览器卡片，菜单和所有点击仅为内存桩。
$textCondition = 'text'
$menuCondition = 'menu'
$menuItemCondition = 'menuitem'
function New-TestBrowserWindow([string]$Mode) {
    $once = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Allow Once'; IsEnabled = $true; IsOffscreen = $false; ProcessId = 123 }; Invocations = 0; Menu = $null; Relabel = $false; OtherTrigger = $null }
    $once | Add-Member ScriptMethod Invoke { $this.Invocations++ }
    $once | Add-Member ScriptMethod GetCurrentPattern { param($pattern) if ($this.Relabel) { $this.Menu.Current.LabeledBy = $this.OtherTrigger }; return $this }
    $once | Add-Member ScriptMethod GetCurrentPropertyValue { param($property) return $true }
    $menu = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 100; Y = 234; Width = 160; Height = 40 } }; Once = $once; Key = 1001 }
    $menu | Add-Member ScriptMethod GetRuntimeId { return @($this.Key) }
    $menu | Add-Member ScriptMethod FindAll { param($scope, $condition) if ($condition -eq 'menuitem') { return @($this.Once) }; return @() }
    $always = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Always Allow'; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 100; Y = 200; Width = 130; Height = 30 } }; Invocations = 0 }
    $always | Add-Member ScriptMethod Invoke { $this.Invocations++ }
    $always | Add-Member ScriptMethod GetCurrentPattern { param($pattern) return $this }
    # 2026-10-06：按实机不支持 Invoke、支持滚动与展开的窄按钮模拟模式，动作只累计内存计数。
    $more = [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'More actions'; IsEnabled = $true; IsOffscreen = ($Mode -like 'scroll-*'); BoundingRectangle = @{ X = 240; Y = 200; Width = 20; Height = 30 }; ExpandCollapseState = [System.Windows.Automation.ExpandCollapseState]::Collapsed }; Window = $null; Parent = $null; Scrolls = 0; Expansions = 0; Invocations = 0 }
    $more | Add-Member ScriptMethod Invoke { $this.Window.Opened = $true }
    $more | Add-Member ScriptMethod ScrollIntoView {
        $this.Scrolls++
        if ($this.Window.Mode -ne 'scroll-still-offscreen') { $this.Current.IsOffscreen = $false }
        if ($this.Window.Mode -eq 'scroll-card-changed') { $this.Parent.Texts[0].Current.Name = 'Ordinary card' }
        if ($this.Window.Mode -eq 'scroll-parent-exit') { $script:testParentAlive = $false }
        if ($this.Window.Mode -eq 'scroll-host-changed') { $this.Window.Current.ProcessId = 999 }
    }
    $more | Add-Member ScriptMethod Expand { $this.Expansions++; $this.Current.ExpandCollapseState = [System.Windows.Automation.ExpandCollapseState]::Expanded; $this.Window.Opened = $true }
    $more | Add-Member ScriptMethod GetCurrentPattern {
        param($pattern)
        if ($this.Window.Mode -in @('parent-exit', 'scroll-pattern-parent-exit')) { $script:testParentAlive = $false }
        if (($this.Window.Mode -like 'scroll-*' -or $this.Window.Mode -eq 'expand-only') -and $pattern.Id -eq [System.Windows.Automation.InvokePattern]::Pattern.Id) { throw 'Invoke not supported by real narrow trigger' }
        return $this
    }
    $more | Add-Member ScriptMethod GetCurrentPropertyValue {
        param($property)
        if ($property.Id -eq [System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty.Id -and ($this.Window.Mode -like 'scroll-*' -or $this.Window.Mode -eq 'expand-only')) { return $false }
        return $true
    }
    $more | Add-Member ScriptMethod GetRuntimeId { return @(2001) }
    if ($Mode -in @('labeled-menu', 'relabel-menu')) { $menu.Current | Add-Member NoteProperty LabeledBy $more }
    if ($Mode -in @('mislabeled-menu', 'relabel-menu')) {
        $otherTrigger = [pscustomobject]@{}
        $otherTrigger | Add-Member ScriptMethod GetRuntimeId { return @(2002) }
        if ($Mode -eq 'mislabeled-menu') { $menu.Current | Add-Member NoteProperty LabeledBy $otherTrigger }
        else { $once.Menu = $menu; $once.Relabel = $true; $once.OtherTrigger = $otherTrigger }
    }
    $permissionText = if ($Mode -in @('unrelated', 'wide-unrelated')) { 'Ordinary card on github.com' } else { 'Agent needs permission to act on github.com' }
    $buttons = @(
        [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Configure'; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 0; Y = 200; Width = 40; Height = 30 } } },
        [pscustomobject]@{ Current = [pscustomobject]@{ Name = 'Deny'; IsEnabled = $true; IsOffscreen = $false; BoundingRectangle = @{ X = 50; Y = 200; Width = 40; Height = 30 } } }, $always, $more)
    if ($Mode -like 'wide*') { $once.Current | Add-Member NoteProperty BoundingRectangle @{ X = 100; Y = 200; Width = 80; Height = 30 }; $buttons += $once }
    $card = [pscustomobject]@{ Current = [pscustomobject]@{ ControlType = [System.Windows.Automation.ControlType]::Group }; Texts = @([pscustomobject]@{ Current = [pscustomobject]@{ Name = $permissionText } }); Buttons = $buttons }
    $card | Add-Member ScriptMethod FindAll { param($scope, $condition) if ($condition -eq 'text') { return $this.Texts }; if ($condition -eq 'button') { return $this.Buttons }; return @() }
    $once | Add-Member NoteProperty Parent $card
    $more.Parent = $card
    $conversation = [pscustomobject]@{ Card = $card }
    $conversation | Add-Member ScriptMethod FindAll { param($scope, $condition) if ($condition -eq 'button') { return $this.Card.Buttons }; return @() }
    $secondMenu = [pscustomobject]@{ Current = $menu.Current }
    $secondMenu | Add-Member ScriptMethod GetRuntimeId { return @(1002) }
    $window = [pscustomobject]@{ Current = [pscustomobject]@{ ProcessId = 123; NativeWindowHandle = 42 }; Conversation = $conversation; Card = $card; Menu = $menu; SecondMenu = $secondMenu; Always = $always; Once = $once; More = $more; Opened = $false; Mode = $Mode }
    $more.Window = $window
    $window | Add-Member ScriptMethod FindFirst { param($scope, $condition) if ($this.Mode -notin @('outside-conversation', 'wide-outside-conversation')) { return $this.Conversation }; return $null }
    $window | Add-Member ScriptMethod FindAll {
        param($scope, $condition)
        if ($condition -eq 'button') { return $this.Card.Buttons }
        if ($condition -eq 'menu' -and ($this.Opened -or $this.Mode -eq 'preexisting-menu')) {
            if ($this.Mode -eq 'ambiguous-menu') { return @($this.Menu, $this.SecondMenu) }
            return @($this.Menu)
        }
        return @()
    }
    return $window
}

# 2026-10-06：诊断仅观察结构，验证总数、离屏状态和日志中没有域名或用户消息。
if (Get-Command Write-BrowserCandidateDiagnostic -ErrorAction SilentlyContinue) {
    $diagnosticWindow = New-TestBrowserWindow 'wide'
    $diagnosticWindow.More.Current.IsOffscreen = $true
    $script:lastApprovalDiagnosticTime = [DateTime]::MinValue
    $originalConsoleWriter = [Console]::Out
    $diagnosticWriter = New-Object IO.StringWriter
    try {
        [Console]::SetOut($diagnosticWriter)
        Write-BrowserCandidateDiagnostic $diagnosticWindow.Card.Buttons 123
    }
    finally { [Console]::SetOut($originalConsoleWriter) }
    $diagnosticOutput = $diagnosticWriter.ToString()
    $diagnosticWriter.Dispose()
    if ($diagnosticOutput -notmatch 'pid=123 buttons=5 candidates=2' -or $diagnosticOutput -notmatch 'offscreen=True parent=ControlType.Group texts=1 buttons=5' -or $diagnosticOutput -match 'github\.com|Agent needs permission') { throw 'Browser structural diagnostic leaked content or reported wrong structure' }
    if ($diagnosticWindow.Once.Invocations -ne 0 -or $diagnosticWindow.Always.Invocations -ne 0) { throw 'Browser structural diagnostic invoked an action' }
    $checks++
    Write-Output 'PASS browser diagnostic counts, offscreen state, content privacy, and no actions'
}

# 2026-10-06：候选诊断和错误结果各自节流，结构日志之后的关键结果仍必须能够输出。
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
$script:approvalDiagnosticTimes = @{}
$originalConsoleWriter = [Console]::Out
$throttleWriter = New-Object IO.StringWriter
try {
    [Console]::SetOut($throttleWriter)
    Write-ApprovalDiagnostic 'candidate structure' 'browser-candidate'
    Write-ApprovalDiagnostic 'pattern support' 'browser-pattern'
    Write-ApprovalDiagnostic 'menu result' 'browser-menu'
    Write-ApprovalDiagnostic 'candidate repeated' 'browser-candidate'
    Write-ApprovalDiagnostic 'pattern repeated' 'browser-pattern'
}
finally { [Console]::SetOut($originalConsoleWriter) }
$throttleOutput = $throttleWriter.ToString()
$throttleWriter.Dispose()
if ($throttleOutput -notmatch 'candidate structure' -or $throttleOutput -notmatch 'pattern support' -or $throttleOutput -notmatch 'menu result' -or $throttleOutput -match 'repeated') { throw 'Diagnostic categories starved each other or did not throttle duplicates' }
$checks++
Write-Output 'PASS diagnostic categories preserve action evidence and throttle repeats'

foreach ($case in @(
    @{ Mode = 'narrow'; Expected = 1 }, @{ Mode = 'wide'; Expected = 1 },
    @{ Mode = 'scroll-expand'; Expected = 1; Scrolls = 1; Expansions = 1 },
    @{ Mode = 'expand-only'; Expected = 1; Scrolls = 0; Expansions = 1 },
    @{ Mode = 'scroll-still-offscreen'; Expected = 0; Scrolls = 1; Expansions = 0 },
    @{ Mode = 'scroll-card-changed'; Expected = 0; Scrolls = 1; Expansions = 0 },
    @{ Mode = 'scroll-parent-exit'; Expected = 0; Scrolls = 1; Expansions = 0 },
    @{ Mode = 'scroll-host-changed'; Expected = 0; Scrolls = 1; Expansions = 0 },
    @{ Mode = 'scroll-pattern-parent-exit'; Expected = 0; Scrolls = 0; Expansions = 0 },
    @{ Mode = 'unrelated'; Expected = 0 }, @{ Mode = 'outside-conversation'; Expected = 0 },
    @{ Mode = 'preexisting-menu'; Expected = 0 }, @{ Mode = 'ambiguous-menu'; Expected = 0 },
    @{ Mode = 'parent-exit'; Expected = 0 },
    @{ Mode = 'labeled-menu'; Expected = 1 }, @{ Mode = 'mislabeled-menu'; Expected = 0 },
    @{ Mode = 'wide-unrelated'; Expected = 0 }, @{ Mode = 'wide-outside-conversation'; Expected = 0 },
    @{ Mode = 'relabel-menu'; Expected = 0 }
)) {
    $script:testParentAlive = $true
    $browserWindow = New-TestBrowserWindow $case.Mode
    $automation = [pscustomobject]@{ Window = $browserWindow; Scans = 0 }
    $automation | Add-Member ScriptMethod FindAll {
        param($scope, $condition)
        $this.Scans++
        if ($this.Scans -gt 1) { $script:testParentAlive = $false; return @() }
        return @($this.Window)
    }
    . ([scriptblock]::Create($lifecycleSource))
    if ($browserWindow.Once.Invocations -ne $case.Expected -or $browserWindow.Always.Invocations -ne 0) {
        throw "Browser permission regression: mode=$($case.Mode) expected=$($case.Expected) once=$($browserWindow.Once.Invocations) permanent=$($browserWindow.Always.Invocations)"
    }
    # 2026-10-06：无点击桩同时验证失效卡片只滚动而不展开，宿主退出前不能开始滚动。
    if ($case.ContainsKey('Scrolls') -and ($browserWindow.More.Scrolls -ne $case.Scrolls -or $browserWindow.More.Expansions -ne $case.Expansions)) { throw "Browser pattern regression: mode=$($case.Mode) scrolls=$($browserWindow.More.Scrolls) expands=$($browserWindow.More.Expansions)" }
    $checks++
    Write-Output "PASS browser permission actual scanner: $($case.Mode)"
}

# 2026-10-06：调用实际浏览器函数，在宿主查询后变更卡片和可见性，所有案例应保持零批准。
$hostMutationFailures = @()
foreach ($case in @(
    @{ Mode = 'wide'; State = 'card'; Lookup = 1; Scrolls = 0; Expansions = 0 },
    @{ Mode = 'labeled-menu'; State = 'card'; Lookup = 2; Scrolls = 0; Expansions = 1 },
    @{ Mode = 'labeled-menu'; State = 'once-offscreen'; Lookup = 2; Scrolls = 0; Expansions = 1 },
    @{ Mode = 'labeled-menu'; State = 'menu-offscreen'; Lookup = 2; Scrolls = 0; Expansions = 1 },
    @{ Mode = 'scroll-expand'; State = 'card'; Lookup = 1; Scrolls = 0; Expansions = 0 },
    @{ Mode = 'scroll-expand'; State = 'card'; Lookup = 2; Scrolls = 1; Expansions = 0 }
)) {
    $script:testParentAlive = $true
    $browserWindow = New-TestBrowserWindow $case.Mode
    $script:browserHostLookupCount = 0
    $script:browserHostLookupWindow = @{ Window = $browserWindow; Lookup = $case.Lookup; State = $case.State }
    try { $actual = Invoke-BrowserPermissionCards $browserWindow 123 ([IntPtr]42) }
    finally { $script:browserHostLookupWindow = $null }
    $description = "$($case.Mode) $($case.State) lookup=$($case.Lookup) result=$actual once=$($browserWindow.Once.Invocations) permanent=$($browserWindow.Always.Invocations) scrolls=$($browserWindow.More.Scrolls) expands=$($browserWindow.More.Expansions)"
    if ($actual -or $browserWindow.Once.Invocations -ne 0 -or $browserWindow.Always.Invocations -ne 0 -or $browserWindow.More.Scrolls -ne $case.Scrolls -or $browserWindow.More.Expansions -ne $case.Expansions) {
        $hostMutationFailures += $description
        Write-Output "FAIL browser host lookup state: $description"
    }
    else { $checks++; Write-Output "PASS browser host lookup state: $description" }
}
if ($hostMutationFailures.Count -gt 0) { throw "Browser host lookup state regressions: $($hostMutationFailures -join '; ')" }

# 2026-10-06：调用真实卡片规则验证文案和同卡片按钮，不用复制的匹配逻辑作断言。
foreach ($case in @(
    @{ Text = 'Agent needs permission to act on github.com'; Buttons = @('Configure', 'Deny', 'Always Allow', 'More actions'); Expected = $true },
    @{ Text = 'Agent needs permission to act on github.com'; Buttons = @('Configure', 'Deny', 'Always Allow', 'Allow Once'); Expected = $true },
    @{ Text = 'Ordinary message on github.com'; Buttons = @('Configure', 'Deny', 'Always Allow', 'More actions'); Expected = $false },
    @{ Text = 'Agent needs permission to act on github.com'; Buttons = @('Deny', 'Always Allow', 'More actions'); Expected = $false },
    @{ Text = 'Agent needs permission to act on github.com'; Buttons = @('Configure', 'Always Allow', 'More actions'); Expected = $false },
    @{ Text = 'Agent needs permission to act on https://github.com'; Buttons = @('Configure', 'Deny', 'Always Allow', 'More actions'); Expected = $false },
    @{ Text = 'Agent needs permission to act on github.com/other'; Buttons = @('Configure', 'Deny', 'Always Allow', 'More actions'); Expected = $false },
    @{ Text = 'Agent needs permission to act on github.com'; Buttons = @('Configure', 'Deny', 'Always Allow'); Expected = $false }
)) {
    if ((Test-BrowserPermissionCardShape @($case.Text) $case.Buttons) -ne $case.Expected) { throw 'Browser card shape mismatch' }
    $checks++
}
if (Test-ButtonMatch 'Always Allow') { throw 'Global Always Allow matcher must remain disabled' }
$checks++
Write-Output 'PASS browser permission shape and global Always Allow exclusion'

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
