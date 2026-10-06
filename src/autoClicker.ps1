param(
    # 2026-10-05：扫描间隔限定为有效范围，宿主信息由扩展传入以锁定进程归属。
    [ValidateRange(50, 60000)][int]$PollMs = 500,
    [ValidateRange(0, 60000)][int]$CooldownMs = 1500,
    [string]$RestoreCursor = 'true',
    [string]$HostExecutablePath = '',
    [ValidateRange(0, 2147483647)][int]$ParentProcessId = 0,
    [switch]$SelfTest
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    // 2026-07-28 物理点击前记录鼠标位置，回退点击后尽量不打断用户操作
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    // 2026-10-05：物理回退只接受目标顶层窗口内的坐标，遮挡或失效时跳过。
    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public static bool IsHitTargetWindow(IntPtr target, IntPtr root, bool exists, bool visible,
                                        bool enabled, bool iconic, uint actualProcessId, uint expectedProcessId) {
        return target != IntPtr.Zero && root == target && exists && visible && enabled && !iconic &&
               expectedProcessId != 0 && actualProcessId == expectedProcessId;
    }
    public static bool IsPointOwnedByWindow(int x, int y, IntPtr target, uint expectedProcessId) {
        POINT point = new POINT { X = x, Y = y };
        IntPtr hit = WindowFromPoint(point);
        IntPtr root = GetAncestor(hit, 2);
        uint actualProcessId;
        GetWindowThreadProcessId(target, out actualProcessId);
        return IsHitTargetWindow(target, root, IsWindow(target), IsWindowVisible(target),
                                 IsWindowEnabled(target), IsIconic(target), actualProcessId, expectedProcessId);
    }
    public static bool Click(int x, int y, bool restoreCursor, IntPtr target, uint expectedProcessId) {
        if (!IsPointOwnedByWindow(x, y, target, expectedProcessId)) { return false; }
        POINT oldPoint;
        bool hasOldPoint = GetCursorPos(out oldPoint);
        if (!SetCursorPos(x, y)) { return false; }
        System.Threading.Thread.Sleep(30);
        POINT currentPoint;
        if (!GetCursorPos(out currentPoint) || currentPoint.X != x || currentPoint.Y != y ||
            !IsPointOwnedByWindow(x, y, target, expectedProcessId)) {
            if (restoreCursor && hasOldPoint) { SetCursorPos(oldPoint.X, oldPoint.Y); }
            return false;
        }
        try {
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(50);
        }
        finally {
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            if (restoreCursor && hasOldPoint) {
                System.Threading.Thread.Sleep(20);
                SetCursorPos(oldPoint.X, oldPoint.Y);
            }
        }
        return true;
    }
}
"@

Add-Type -AssemblyName UIAutomationClient

$automation = [System.Windows.Automation.AutomationElement]::RootElement
$winCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$btnCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button
)
# 2026-10-05：新版权限卡片位于会话区域，审批单选项与权限目标需成组识别。
$conversationCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'conversation'
)
$radioCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::RadioButton
)
$editCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit
)
# 2026-10-06：浏览器权限在宽栏是按钮、窄栏是弹出菜单项，分别读取实际控件类型。
$textCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text
)
$menuCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Menu
)
$menuItemCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem
)

# 2026-10-05：只匹配审批动作及其中文标签，普通保存、确认、重试按钮不参与自动同意。
$targetPrefixes = @('Run', 'Accept', 'Allow', 'Execute', 'Approve', '运行', '接受', '允许', '同意', '批准', '执行')
$excludeExact = @('Run and Debug', 'Run Task', 'Run Build Task', 'Run File', 'Always run', 'Run Extension', 'Run Selection')
$exactOnly = @('全部接受', '全部同意', '全部允许', '全部批准')

# 2026-07-28 前缀匹配必须有边界，避免 Application/Continuous 这类普通按钮被误点
function Test-PrefixBoundary([string]$Rest) {
    if ($Rest.Length -eq 0) { return $true }
    if ($Rest[0] -eq ' ' -or $Rest[0] -eq '(' -or $Rest[0] -eq '[' -or $Rest[0] -eq '+' -or $Rest[0] -eq ':' -or $Rest[0] -eq '-') { return $true }
    if ($Rest -match '^(Alt|Ctrl|Shift|Enter|Cmd|Win)\b') { return $true }
    return $false
}

function Test-ButtonMatch([string]$Name) {
    # 2026-10-05：拒绝、取消和停止动作优先排除，中文审批仅允许常见审批后缀。
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim()
    if ($n -match '\b(Reject|Deny|Denied|Cancel|Stop|Abort)\b|拒绝|取消|停止|中止') { return $false }
    # 2026-10-06：本次允许专属于已核验的浏览器卡片，不能由全窗普通按钮回退绕过作用域。
    if ($n -eq 'Allow Once') { return $false }
    # 2026-10-05：执行后的工具标题也会以 Run 开头，仅静态审批标签和快捷键后缀可点击。
    if ($n -match '^(Run|Execute|Approve|运行|执行|批准)') {
        return $n -match '^(Run|Execute|Approve|Run command|Execute command|Approve command|运行|执行|批准|运行命令|执行命令|批准命令)(\s*[\(\[]?(Alt|Ctrl|Shift|Enter|Cmd|Win)(\s*\+\s*(Alt|Ctrl|Shift|Enter|Cmd|Win|[A-Za-z0-9]))*[\)\]]?)?$'
    }

    foreach ($ex in $excludeExact) {
        if ($n -eq $ex) { return $false }
        if ($n -like "$ex *") { return $false }
    }

    foreach ($em in $exactOnly) {
        if ($n -eq $em) { return $true }
    }

    foreach ($p in $targetPrefixes) {
        if ($n -eq $p) { return $true }
        if ($n.Length -gt $p.Length) {
            $start = $n.Substring(0, $p.Length)
            if ($start -eq $p) {
                $rest = $n.Substring($p.Length)
                if (Test-PrefixBoundary $rest) { return $true }
                if ($p -match '[\u4e00-\u9fff]' -and $rest -match '^(全部|所有|一次|本次|此次|此|该|运行|执行|命令|更改|修改|编辑|操作|会话|终端|文件|访问|网络|目录)') { return $true }
            }
        }
    }
    return $false
}

# 2026-10-05：按完整可执行文件路径锁定窗口，独立运行兼容新旧 Antigravity 进程名。
function Test-HostProcessPath([string]$ExecutablePath, [string]$ExpectedPath) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($ExecutablePath)
        if ([IO.Path]::GetFileName($fullPath) -notin @('Antigravity.exe', 'Antigravity IDE.exe')) { return $false }
        if ([string]::IsNullOrWhiteSpace($ExpectedPath)) { return $true }
        return [string]::Equals($fullPath, [IO.Path]::GetFullPath($ExpectedPath), [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

# 2026-10-05：进程路径不可读取时跳过，不使用可能被其他应用仿造的窗口标题。
function Get-TargetProcessIds {
    $targetIds = @{}
    foreach ($process in @(Get-Process -Name 'Antigravity', 'Antigravity IDE' -ErrorAction SilentlyContinue)) {
        try {
            if (Test-HostProcessPath $process.Path $HostExecutablePath) { $targetIds[$process.Id] = $true }
        }
        catch { }
    }
    return $targetIds
}

# 2026-10-05：按按钮最新矩形计算坐标，负坐标保留以支持主屏左侧或上方的副屏。
function Get-ButtonCenter($Rectangle) {
    if ($null -eq $Rectangle -or $Rectangle.Width -le 0 -or $Rectangle.Height -le 0) { return $null }
    $x = $Rectangle.X + $Rectangle.Width / 2
    $y = $Rectangle.Y + $Rectangle.Height / 2
    if ([double]::IsNaN($x) -or [double]::IsInfinity($x) -or [double]::IsNaN($y) -or [double]::IsInfinity($y)) { return $null }
    if ($x -lt [int]::MinValue -or $x -gt [int]::MaxValue -or $y -lt [int]::MinValue -or $y -gt [int]::MaxValue) { return $null }
    return @{ X = [int]$x; Y = [int]$y }
}

# 2026-10-05：保留启动时的父进程对象，宿主退出后等待者及扫描者均退出。
function Test-ParentAlive {
    if ($ParentProcessId -eq 0) { return $true }
    if ($null -eq $script:parentProcess) { return $false }
    try {
        $script:parentProcess.Refresh()
        return -not $script:parentProcess.HasExited
    }
    catch { return $false }
}

# 2026-10-05：仅允许明确的本次审批，始终允许和拒绝选项不参与自动选择。
function Test-OneTimeApprovalName([string]$Name) {
    return $Name.Trim() -in @('1 Yes, allow this time', 'Yes, allow this time', '1 是，仅本次允许', '是，仅本次允许', '1 是，允许本次', '是，允许本次', '1 仅允许本次', '仅允许本次')
}

# 2026-10-05：权限目标编辑框与同问题的本次、始终、拒绝选项必须在同一卡片内。
function Test-ApprovalCardShape($EditNames, $OptionIds, $OptionNames, $SubmitNames) {
    if (@($EditNames | Where-Object { $_ -eq 'Edit permission target' }).Count -ne 1) { return $false }
    if ($OptionIds.Count -lt 3 -or $OptionIds.Count -ne $OptionNames.Count) { return $false }
    $oneTimeIndex = -1
    for ($i = 0; $i -lt $OptionIds.Count; $i++) {
        if ($OptionIds[$i] -match '^ask-opt-(.+)-1$' -and (Test-OneTimeApprovalName $OptionNames[$i])) {
            if ($oneTimeIndex -ge 0) { return $false }
            $oneTimeIndex = $i
        }
    }
    if ($oneTimeIndex -lt 0) { return $false }
    $questionPrefix = $OptionIds[$oneTimeIndex].Substring(0, $OptionIds[$oneTimeIndex].Length - 1)
    foreach ($id in $OptionIds) {
        if (-not $id.StartsWith($questionPrefix, [StringComparison]::Ordinal)) { return $false }
    }
    if (@($OptionNames | Where-Object { $_ -match '\balways allow\b|始终允许|总是允许|始终同意|总是同意' }).Count -eq 0) { return $false }
    if (@($OptionNames | Where-Object { $_ -match '^(\d+\s+)?No\b|拒绝|不同意|不允许' }).Count -eq 0) { return $false }
    return @($SubmitNames | Where-Object { $_ -match '^(Submit|提交)(\s*[↵⏎])?$' }).Count -eq 1
}

# 2026-10-05：用实际选中状态确认本次允许，无法读取选中状态时不提交表单。
function Test-ApprovalOptionSelected($Option) {
    try {
        $selection = $Option.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        return $selection.Current.IsSelected
    }
    # 2026-10-07：托管 UIA 不提供 LegacyIAccessiblePattern，读不到真实选中状态时保持不提交。
    catch { return $false }
}

# 2026-10-05：读取审批卡片的实时控件特征，普通问答表单和全局提交按钮不会命中。
function Test-LiveApprovalCard($Card, $ExpectedTarget = $null) {
    $edits = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition)
    $radios = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    $buttons = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
    # 2026-10-06：滚动和宿主查询后同时验证目标控件身份与原始值，命令变化时不能沿用旧批准。
    if (-not (Test-ApprovalCardShape @($edits | ForEach-Object { $_.Current.Name }) @($radios | ForEach-Object { $_.Current.AutomationId }) @($radios | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name }))) { return $false }
    if ($null -ne $ExpectedTarget) {
        $target = @($edits | Where-Object { $_.Current.Name -eq 'Edit permission target' })[0]
        if (($target.GetRuntimeId() -join '.') -ne $ExpectedTarget.Id) { return $false }
        $value = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
        if (-not [string]::Equals($value, $ExpectedTarget.Value, [StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

# 2026-10-06：审批卡片的诊断最多每十秒输出一次，便于排查宿主 UI 变化且避免刷屏。
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
$script:approvalDiagnosticTimes = @{}
# 2026-10-06：候选、控件模式和动作结果分别节流，候选结构不能永久压住后续失败证据。
function Write-ApprovalDiagnostic([string]$Message, [string]$Category = 'approval') {
    $now = [DateTime]::Now
    if ($Category -eq 'browser-candidate') {
        if (($now - $script:lastApprovalDiagnosticTime).TotalSeconds -lt 10) { return }
        $script:lastApprovalDiagnosticTime = $now
    }
    else {
        if ($script:approvalDiagnosticTimes.ContainsKey($Category) -and ($now - $script:approvalDiagnosticTimes[$Category]).TotalSeconds -lt 10) { return }
        $script:approvalDiagnosticTimes[$Category] = $now
    }
    [Console]::WriteLine("___SCANNER_DIAGNOSTIC___:$Message")
}

# 2026-10-06：浏览器权限文案必须包含真实主机名，不把普通消息或网址正文当作审批。
function Test-BrowserPermissionText([string]$Name) {
    if ($Name -notmatch '^Agent needs permission to act on (\S+)$') { return $false }
    return [Uri]::CheckHostName($Matches[1]) -ne [UriHostNameType]::Unknown
}

# 2026-10-06：同一卡片必须同时有权限文案、配置、拒绝和始终允许，批准仍只选择本次。
function Test-BrowserPermissionCardShape($TextNames, $ButtonNames) {
    if (@($TextNames | Where-Object { Test-BrowserPermissionText $_ }).Count -ne 1) { return $false }
    foreach ($required in @('Configure', 'Deny', 'Always Allow')) {
        if (@($ButtonNames | Where-Object { $_ -eq $required }).Count -ne 1) { return $false }
    }
    $onceCount = @($ButtonNames | Where-Object { $_ -eq 'Allow Once' }).Count
    if ($onceCount -eq 1) { return $true }
    return $onceCount -eq 0 -and @($ButtonNames | Where-Object { $_ -eq 'More actions' }).Count -eq 1
}

# 2026-10-06：只检查当前卡片的直属控件，不能从整段会话拼凑不相关按钮。
function Test-LiveBrowserPermissionCard($Card) {
    $texts = $Card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition)
    $buttons = $Card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition)
    return Test-BrowserPermissionCardShape @($texts | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name })
}

# 2026-10-06：门户菜单必须靠近此次触发按钮，负坐标副屏沿用同一几何判断。
function Test-BrowserMenuAnchor($MenuRectangle, $ButtonRectangle) {
    if ($null -eq (Get-ButtonCenter $MenuRectangle) -or $null -eq (Get-ButtonCenter $ButtonRectangle)) { return $false }
    $horizontal = $MenuRectangle.X -le ($ButtonRectangle.X + $ButtonRectangle.Width + 16) -and ($MenuRectangle.X + $MenuRectangle.Width) -ge ($ButtonRectangle.X - 16)
    $below = [Math]::Abs($MenuRectangle.Y - ($ButtonRectangle.Y + $ButtonRectangle.Height))
    $above = [Math]::Abs(($MenuRectangle.Y + $MenuRectangle.Height) - $ButtonRectangle.Y)
    return $horizontal -and [Math]::Min($below, $above) -le 32
}

# 2026-10-06：菜单限定为目标宿主窗口内可见的菜单，隐藏或其他进程的菜单不参与差分。
function Get-VisibleBrowserMenus($Window, [int]$WindowProcessId) {
    foreach ($menu in $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuCondition)) {
        if ($menu.Current.ProcessId -eq $WindowProcessId -and -not $menu.Current.IsOffscreen -and $menu.Current.IsEnabled -and $null -ne (Get-ButtonCenter $menu.Current.BoundingRectangle)) { $menu }
    }
}

# 2026-10-06：仅输出候选控件结构和固定批准标签，不记录域名、消息或窗口标题。
function Write-BrowserCandidateDiagnostic($CandidateButtons, [int]$WindowProcessId) {
    if (([DateTime]::Now - $script:lastApprovalDiagnosticTime).TotalSeconds -lt 10) { return }
    $candidates = @($CandidateButtons | Where-Object { $_.Current.Name -in @('Allow Once', 'More actions') })
    $structures = @()
    foreach ($allow in $candidates) {
        try {
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($allow)
            $parentType = 'none'
            $texts = @()
            $buttons = @()
            if ($null -ne $card) {
                $parentType = $card.Current.ControlType.ProgrammaticName
                $texts = @($card.FindAll([System.Windows.Automation.TreeScope]::Children, $textCondition))
                $buttons = @($card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition))
            }
            $fixedLabels = @($buttons | ForEach-Object { $_.Current.Name } | Where-Object { $_ -in @('Configure', 'Deny', 'Always Allow', 'Allow Once', 'More actions') }) -join ','
            $shape = Test-BrowserPermissionCardShape @($texts | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name })
            # 2026-10-06：离屏控件也只读报告支持模式，为后续受控滚动提供实际证据。
            $patternSummary = 'patterns=unavailable'
            try {
                $supportsInvoke = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
                $supportsScrollItem = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                $supportsExpand = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsExpandCollapsePatternAvailableProperty)
                $patternSummary = "invoke=$supportsInvoke scrollitem=$supportsScrollItem expand=$supportsExpand"
            }
            catch { }
            $structures += "[$($allow.Current.Name) enabled=$($allow.Current.IsEnabled) offscreen=$($allow.Current.IsOffscreen) parent=$parentType texts=$($texts.Count) buttons=$($buttons.Count) labels=$fixedLabels shape=$shape $patternSummary]"
        }
        catch { $structures += '[candidate structure unavailable]' }
    }
    $summary = @($structures | Sort-Object -Unique) -join ' '
    Write-ApprovalDiagnostic "browser candidates pid=$WindowProcessId buttons=$($CandidateButtons.Count) candidates=$($candidates.Count) $summary" 'browser-candidate'
}

# 2026-10-06：宽栏直接允许本次，窄栏展开已核验卡片的菜单，只允许此次新出现的本次菜单项。
function Invoke-BrowserPermissionCards($Window, [int]$WindowProcessId, [IntPtr]$WindowHandle) {
    $conversation = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $conversationCondition)
    if ($null -eq $conversation) {
        Write-ApprovalDiagnostic "browser conversation missing pid=$WindowProcessId" 'browser-candidate'
        return $false
    }
    $conversationButtons = @($conversation.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition))
    Write-BrowserCandidateDiagnostic $conversationButtons $WindowProcessId
    foreach ($allow in $conversationButtons) {
        $stage = 'candidate'
        try {
            $actionName = $allow.Current.Name
            if ($actionName -notin @('Allow Once', 'More actions') -or -not $allow.Current.IsEnabled) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($allow)
            if ($null -eq $card -or -not (Test-LiveBrowserPermissionCard $card)) { continue }
            if ($actionName -eq 'More actions') {
                $cardButtons = $card.FindAll([System.Windows.Automation.TreeScope]::Children, $btnCondition)
                if (@($cardButtons | Where-Object { $_.Current.Name -eq 'Allow Once' }).Count -gt 0) { continue }
            }
            # 2026-10-06：只记录固定模式布尔值，区分控件不支持调用与调用后菜单没有出现。
            $stage = 'pattern'
            $invokeAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
            $scrollItemAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
            $expandAvailable = $allow.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsExpandCollapsePatternAvailableProperty)
            Write-ApprovalDiagnostic "browser pattern action=$actionName invoke=$invokeAvailable scrollitem=$scrollItemAvailable expand=$expandAvailable" 'browser-pattern'
            # 2026-10-06：离屏的已核验窄卡片仅通过自身滚动模式带出，滚动前后复核宿主和当前卡片。
            if ($allow.Current.IsOffscreen) {
                if ($actionName -ne 'More actions' -or -not $scrollItemAvailable) { continue }
                $stage = 'scroll-pattern'
                $scrollItem = $allow.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                # 2026-10-06：宿主查询可能改变卡片状态，滚动前后的界面复核统一放在查询之后。
                if (-not (Test-LiveBrowserPermissionCard $card) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'scroll'
                $scrollItem.ScrollIntoView()
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                if (-not (Test-LiveBrowserPermissionCard $card) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                Write-ApprovalDiagnostic 'browser scroll returned=True visible=True' 'browser-scroll'
            }
            # 2026-10-06：实机窄按钮没有 Invoke，优先使用展开模式避免切换菜单；宽栏本次按钮继续 Invoke。
            $stage = 'action-pattern'
            $method = 'invoke'
            if ($actionName -eq 'More actions' -and $expandAvailable) {
                $actionPattern = $allow.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                $method = 'expand'
            }
            elseif ($invokeAvailable) { $actionPattern = $allow.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) }
            else { continue }
            $stage = 'before-menus'
            $beforeMenus = @{}
            if ($actionName -eq 'More actions') {
                foreach ($menu in @(Get-VisibleBrowserMenus $Window $WindowProcessId)) { $beforeMenus[($menu.GetRuntimeId() -join '.')] = $true }
            }
            $stage = 'host'
            if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
            if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
            # 2026-10-06：最后一次宿主查询后重读卡片和动作按钮，不沿用查询前的批准状态。
            $stage = 'final-card'
            if (-not (Test-LiveBrowserPermissionCard $card) -or $allow.Current.Name -ne $actionName -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
            if (-not (Test-ParentAlive)) { return $false }
            $stage = $method
            if ($method -eq 'expand') { $actionPattern.Expand() }
            else { $actionPattern.Invoke() }
            if ($actionName -eq 'Allow Once') {
                [Console]::WriteLine('___CLICK_INVOKE___:Allow Once (browser domain permission)')
                return $true
            }
            $stage = 'menu-query'
            $menuCount = 0
            $newMenuCount = 0
            $itemCount = 0
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                Start-Sleep -Milliseconds 100
                if (-not (Test-ParentAlive)) { return $false }
                $visibleMenus = @(Get-VisibleBrowserMenus $Window $WindowProcessId)
                $menuCount = $visibleMenus.Count
                $newMenus = @($visibleMenus | Where-Object { -not $beforeMenus.ContainsKey(($_.GetRuntimeId() -join '.')) })
                $newMenuCount = $newMenus.Count
                if ($newMenus.Count -ne 1) { continue }
                $menu = $newMenus[0]
                if (-not (Test-BrowserMenuAnchor $menu.Current.BoundingRectangle $allow.Current.BoundingRectangle)) { continue }
                $label = $menu.Current.LabeledBy
                if ($null -ne $label -and ($label.GetRuntimeId() -join '.') -ne ($allow.GetRuntimeId() -join '.')) { continue }
                $items = @($menu.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menuItemCondition) | Where-Object { $_.Current.Name -eq 'Allow Once' })
                $itemCount = $items.Count
                if ($items.Count -ne 1) { continue }
                $item = $items[0]
                $stage = 'item-pattern' # 2026-10-06：菜单项模式异常单独标明阶段，便于实机定位。
                $itemInvoke = $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                # 2026-10-06：宿主查询完成后复核卡片、菜单和本次菜单项，关联触发器仍保持最后复核。
                $stage = 'item-final'
                if (-not (Test-LiveBrowserPermissionCard $card) -or $allow.Current.Name -ne 'More actions' -or -not $allow.Current.IsEnabled -or $allow.Current.IsOffscreen) { continue }
                if ($menu.Current.ProcessId -ne $WindowProcessId -or $menu.Current.IsOffscreen -or -not $menu.Current.IsEnabled -or -not (Test-BrowserMenuAnchor $menu.Current.BoundingRectangle $allow.Current.BoundingRectangle)) { continue }
                if ($item.Current.Name -ne 'Allow Once' -or -not $item.Current.IsEnabled -or $item.Current.IsOffscreen) { continue }
                # 2026-10-06：菜单项取模式和宿主查询后复核关联触发器，菜单改属其他卡片时不批准。
                $label = $menu.Current.LabeledBy
                if ($null -ne $label -and ($label.GetRuntimeId() -join '.') -ne ($allow.GetRuntimeId() -join '.')) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'item-invoke' # 2026-10-06：明确唯一新菜单本次批准的实际调用阶段。
                $itemInvoke.Invoke()
                [Console]::WriteLine('___CLICK_INVOKE___:Allow Once (browser domain permission)')
                return $true
            }
            Write-ApprovalDiagnostic "browser menu method=$method action-returned=True before=$($beforeMenus.Count) visible=$menuCount new=$newMenuCount once-items=$itemCount" 'browser-menu'
        }
        catch {
            Write-ApprovalDiagnostic "browser error stage=$stage type=$($_.Exception.GetType().Name)" 'browser-error'
            # 2026-10-07：最终批准已尝试但结果未知时占用本轮，展开或滚动失败仍可继续其它候选。
            if (($stage -eq 'invoke' -and $actionName -eq 'Allow Once') -or $stage -eq 'item-invoke') { return $true }
        }
    }
    return $false
}

# 2026-10-05：新版卡片只选本次允许并提交同一卡片，不修改终端或权限的持久设置。
function Invoke-ApprovalCards($Window, [int]$WindowProcessId, [IntPtr]$WindowHandle) {
    # 2026-10-06：专用权限表单也会位于会话兄弟输入区，候选来自宿主窗口，批准仍限定同一个真实表单。
    $options = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    foreach ($option in $options) {
        $stage = 'candidate'
        try {
            if ($option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
            if (-not $option.Current.IsEnabled) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
            if ($null -eq $card) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($card)
            if ($null -eq $card -or -not (Test-LiveApprovalCard $card)) {
                Write-ApprovalDiagnostic 'permission-card shape mismatch'
                continue
            }
            # 2026-10-06：保存当前表单归属，滚动导致控件移到其他表单时不能继续选择或提交。
            $cardId = $card.GetRuntimeId() -join '.'
            $stage = 'target-pattern'
            $target = @($card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition) | Where-Object { $_.Current.Name -eq 'Edit permission target' })[0]
            try {
                $valueAvailable = $target.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty)
                Write-ApprovalDiagnostic "permission target value-pattern=$valueAvailable" 'permission-target-pattern'
            }
            catch { }
            $expectedTarget = @{ Id = ($target.GetRuntimeId() -join '.'); Value = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
            # 2026-10-06：仅对已核验表单报告固定模式布尔值，候选日志不抢占滚动和错误诊断。
            try {
                $selectionAvailable = $option.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsSelectionItemPatternAvailableProperty)
                $scrollAvailable = $option.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                Write-ApprovalDiagnostic "permission option enabled=$($option.Current.IsEnabled) offscreen=$($option.Current.IsOffscreen) selection=$selectionAvailable scrollitem=$scrollAvailable" 'permission-candidate'
            }
            catch { }
            if ($option.Current.IsOffscreen) {
                $stage = 'option-scroll-pattern'
                $scroll = $option.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                if ($null -eq $optionCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $option.Current.IsEnabled -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'option-scroll'
                $scroll.ScrollIntoView()
                Write-ApprovalDiagnostic "permission option-scroll returned=True visible=$(-not $option.Current.IsOffscreen)" 'permission-option-scroll'
            }
            if ($option.Current.IsOffscreen) { continue }
            if (-not (Test-ApprovalOptionSelected $option)) {
                # 2026-10-06：只在取得模式后再次核验同表单、可见性和宿主，模式降级不重复执行选择动作。
                $stage = 'selection-pattern'
                $selectionMethod = 'select'
                try { $selection = $option.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern) }
                # 2026-10-07：仅降级到托管 UIA 实际支持的调用模式，选中状态仍由 SelectionItem 复核。
                catch {
                    $selection = $option.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    $selectionMethod = 'invoke'
                }
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                if ($null -eq $optionCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $option.Current.IsEnabled -or $option.Current.IsOffscreen -or $option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'selection'
                if ($selectionMethod -eq 'select') { $selection.Select() }
                else { $selection.Invoke() } # 2026-10-07：已取得调用模式后只执行一次选择动作。
            }
            if (-not (Test-ApprovalOptionSelected $option) -or -not (Test-LiveApprovalCard $card $expectedTarget)) {
                Write-ApprovalDiagnostic 'permission-card one-time selection unavailable'
                continue
            }
            if (-not (Test-ParentAlive) -or -not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
            if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
            $buttons = $card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
            foreach ($submit in $buttons) {
                if ($submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$') { continue }
                if (-not $submit.Current.IsEnabled) { continue }
                try {
                    $invokeAvailable = $submit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty)
                    $scrollAvailable = $submit.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsScrollItemPatternAvailableProperty)
                    Write-ApprovalDiagnostic "permission submit enabled=$($submit.Current.IsEnabled) offscreen=$($submit.Current.IsOffscreen) invoke=$invokeAvailable scrollitem=$scrollAvailable" 'permission-submit-pattern'
                }
                catch { }
                # 2026-10-06：长表单只滚动同表单 Submit；顶部一次允许因本次滚动离屏时仍读取选中状态。
                $submitScrolled = $false
                if ($submit.Current.IsOffscreen) {
                    $stage = 'submit-scroll-pattern'
                    $scroll = $submit.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
                    if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                    if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                    $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                    $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                    $submitCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($submit)
                    if ($null -eq $optionCard -or $null -eq $submitCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or ($submitCard.GetRuntimeId() -join '.') -ne $cardId -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not $submit.Current.IsEnabled -or $submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$' -or -not $option.Current.IsEnabled -or $option.Current.IsOffscreen -or -not (Test-ApprovalOptionSelected $option)) { continue }
                    if (-not (Test-ParentAlive)) { return $false }
                    $stage = 'submit-scroll'
                    $scroll.ScrollIntoView()
                    $submitScrolled = $true
                    Write-ApprovalDiagnostic "permission submit-scroll returned=True visible=$(-not $submit.Current.IsOffscreen)" 'permission-submit-scroll'
                }
                $stage = 'submit-pattern'
                $invoke = $submit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                # 2026-10-06：模式和宿主查询完成后，再核验最终按钮状态及两端控件仍归属原权限表单。
                if (-not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
                if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
                $optionGroup = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
                $optionCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($optionGroup)
                $submitCard = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($submit)
                if ($null -eq $optionCard -or $null -eq $submitCard -or ($optionCard.GetRuntimeId() -join '.') -ne $cardId -or ($submitCard.GetRuntimeId() -join '.') -ne $cardId) { continue }
                if (-not $submit.Current.IsEnabled -or $submit.Current.IsOffscreen -or $submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$') { continue }
                # 2026-10-05：提交前最后复核本次允许，避免宿主检查期间选项变成始终允许或拒绝。
                if (-not $option.Current.IsEnabled -or ($option.Current.IsOffscreen -and -not $submitScrolled) -or $option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name) -or -not (Test-LiveApprovalCard $card $expectedTarget) -or -not (Test-ApprovalOptionSelected $option)) { continue }
                # 2026-10-05：所有控件查询结束后最后检查父宿主，退出期间不提交权限卡片。
                if (-not (Test-ParentAlive)) { return $false }
                $stage = 'submit-invoke' # 2026-10-07：最终批准阶段紧邻调用，选中、模式及只读查询失败不能误计为批准尝试。
                $invoke.Invoke()
                [Console]::WriteLine('___CLICK_INVOKE___:Submit (one-time permission)')
                return $true
            }
        }
        catch {
            Write-ApprovalDiagnostic "permission-card error stage=$stage type=$($_.Exception.GetType().Name)" 'permission-error'
            # 2026-10-07：提交调用已开始即消耗本轮，异常不能导致同轮继续批准其它窗口。
            if ($stage -eq 'submit-invoke') { return $true }
        } # 2026-10-06：错误日志只含固定阶段和类型，不输出命令正文。
    }
    return $false
}

# 2026-07-28 自测只验证匹配规则，不进入无限扫描循环，方便打包前快速回归
function Invoke-SelfTest {
    # 2026-10-05：同时覆盖中文审批、普通按钮排除、窗口归属及负坐标，所有分支均不点击。
    $cases = @(
        @{ Name = 'Run'; Expected = $true },
        @{ Name = 'RunAlt+Enter'; Expected = $true },
        @{ Name = 'Run and Debug'; Expected = $false },
        @{ Name = 'Accept (1)'; Expected = $true },
        @{ Name = 'Accept All'; Expected = $true },
        @{ Name = 'Allow this conversation'; Expected = $true },
        @{ Name = 'Apply Changes'; Expected = $false },
        @{ Name = 'Application Settings'; Expected = $false },
        @{ Name = 'Continue'; Expected = $false },
        @{ Name = 'Continuous Integration'; Expected = $false },
        @{ Name = 'Yes'; Expected = $false },
        @{ Name = 'Ok'; Expected = $false },
        @{ Name = 'Always run'; Expected = $false },
        @{ Name = 'Run (Alt+Enter)'; Expected = $true },
        @{ Name = 'Run command'; Expected = $true },
        @{ Name = 'Run Task (Ctrl+Shift+P)'; Expected = $false },
        @{ Name = 'Runnable'; Expected = $false },
        @{ Name = 'Allow once'; Expected = $false },
        @{ Name = 'Allow this workspace'; Expected = $true },
        @{ Name = 'Accept all'; Expected = $true },
        @{ Name = 'Accept All Changes'; Expected = $true },
        @{ Name = 'Acceptance criteria'; Expected = $false },
        @{ Name = 'Approve'; Expected = $true },
        @{ Name = 'Execute'; Expected = $true },
        @{ Name = 'Retry'; Expected = $false },
        @{ Name = 'Save'; Expected = $false },
        @{ Name = 'Save All'; Expected = $false },
        @{ Name = 'Confirm'; Expected = $false },
        @{ Name = 'Overwrite'; Expected = $false },
        @{ Name = 'OK'; Expected = $false },
        @{ Name = 'Reject'; Expected = $false },
        @{ Name = 'Accept or Reject'; Expected = $false },
        @{ Name = 'Run / Stop'; Expected = $false },
        @{ Name = 'Allow - Cancel'; Expected = $false },
        @{ Name = '运行'; Expected = $true },
        @{ Name = '运行命令'; Expected = $true },
        @{ Name = '运行 (Alt+Enter)'; Expected = $true },
        @{ Name = '执行'; Expected = $true },
        @{ Name = '接受'; Expected = $true },
        @{ Name = '接受全部'; Expected = $true },
        @{ Name = '接受所有更改'; Expected = $true },
        @{ Name = '全部接受'; Expected = $true },
        @{ Name = '允许'; Expected = $true },
        @{ Name = '允许运行一次'; Expected = $true },
        @{ Name = '允许本次会话'; Expected = $true },
        @{ Name = '同意'; Expected = $true },
        @{ Name = '同意全部'; Expected = $true },
        @{ Name = '全部同意'; Expected = $true },
        @{ Name = '批准'; Expected = $true },
        @{ Name = '允许 / 拒绝'; Expected = $false },
        @{ Name = '运行 / 停止'; Expected = $false },
        @{ Name = '允许取消'; Expected = $false },
        @{ Name = '接受度设置'; Expected = $false },
        @{ Name = '运行状态'; Expected = $false },
        @{ Name = '保存'; Expected = $false },
        @{ Name = '确定'; Expected = $false },
        @{ Name = '是'; Expected = $false },
        @{ Name = '继续'; Expected = $false },
        @{ Name = ''; Expected = $false },
        @{ Name = '   '; Expected = $false }
        @{ Name = 'Run Write-Output test?'; Expected = $false },
        @{ Name = 'Run command？'; Expected = $false },
        @{ Name = 'Submit'; Expected = $false },
        @{ Name = 'Submit ↵'; Expected = $false },
        @{ Name = 'Run Write-Output ANTIGRAVITY_AA_SMOKE_V53'; Expected = $false },
        @{ Name = 'Run npm test'; Expected = $false },
        @{ Name = 'Run git status'; Expected = $false },
        @{ Name = 'Execute npm test'; Expected = $false },
        @{ Name = 'Approve npm test'; Expected = $false },
        @{ Name = 'Run (1)'; Expected = $false },
        @{ Name = 'Run command (Alt+Enter)'; Expected = $true },
        # 2026-10-06：浏览器专用批准由卡片分支处理，普通按钮匹配不得放行。
        @{ Name = 'Allow Once'; Expected = $false },
        @{ Name = 'Always Allow'; Expected = $false }
    )

    $failed = 0
    foreach ($case in $cases) {
        $actual = Test-ButtonMatch $case.Name
        if ($actual -ne $case.Expected) {
            [Console]::WriteLine("___SELFTEST_FAIL___:$($case.Name): expected=$($case.Expected), actual=$actual")
            $failed++
        }
    }

    $stateCases = @(
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $true },
        @{ Root = 43; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 0; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $false; Visible = $true; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $false; Enabled = $true; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $false; Iconic = $false; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $true; Process = 10; Expected = $false },
        @{ Root = 42; Exists = $true; Visible = $true; Enabled = $true; Iconic = $false; Process = 11; Expected = $false }
    )
    foreach ($case in $stateCases) {
        $actual = [MouseHelper]::IsHitTargetWindow([IntPtr]42, [IntPtr]$case.Root, $case.Exists, $case.Visible, $case.Enabled, $case.Iconic, [uint32]$case.Process, [uint32]10)
        if ($actual -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:window ownership')
            $failed++
        }
    }

    $pathCases = @(
        @{ Path = 'C:\Apps\Antigravity IDE.exe'; Host = 'c:\apps\ANTIGRAVITY IDE.EXE'; Expected = $true },
        @{ Path = 'C:\Apps\Antigravity.exe'; Host = ''; Expected = $true },
        @{ Path = 'C:\Other\Antigravity IDE.exe'; Host = 'C:\Apps\Antigravity IDE.exe'; Expected = $false },
        @{ Path = 'C:\Apps\Code.exe'; Host = ''; Expected = $false },
        @{ Path = ''; Host = ''; Expected = $false }
    )
    foreach ($case in $pathCases) {
        if ((Test-HostProcessPath $case.Path $case.Host) -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:host executable path')
            $failed++
        }
    }

    $center = Get-ButtonCenter @{ X = -1920; Y = -1000; Width = 100; Height = 40 }
    if ($null -eq $center -or $center.X -ne -1870 -or $center.Y -ne -980) {
        [Console]::WriteLine('___SELFTEST_FAIL___:negative monitor coordinates')
        $failed++
    }
    if ($null -ne (Get-ButtonCenter @{ X = 0; Y = 0; Width = 0; Height = 40 })) {
        [Console]::WriteLine('___SELFTEST_FAIL___:invalid rectangle')
        $failed++
    }

    $cardCases = @(
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No (tell the agent what to do instead)'); Submit = @('Skip', 'Submit ↵'); Expected = $true },
        @{ Edits = @('Other question'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Submit ↵'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-32-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, and always allow command', '2 Yes, and always allow command', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-3'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '3 Other'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Other', '4 No'); Submit = @('Submit'); Expected = $false },
        @{ Edits = @('Edit permission target'); Ids = @('ask-opt-P0-31-1', 'ask-opt-P0-31-2', 'ask-opt-P0-31-__write_in__'); Names = @('1 Yes, allow this time', '2 Yes, and always allow command', '4 No'); Submit = @('Save'); Expected = $false }
    )
    foreach ($case in $cardCases) {
        if ((Test-ApprovalCardShape $case.Edits $case.Ids $case.Names $case.Submit) -ne $case.Expected) {
            [Console]::WriteLine('___SELFTEST_FAIL___:permission card scope')
            $failed++
        }
    }

    if ($failed -gt 0) {
        [Console]::WriteLine("___SELFTEST_DONE___:failed=$failed")
        exit 1
    }

    [Console]::WriteLine("___SELFTEST_DONE___:passed=$($cases.Count + $stateCases.Count + $pathCases.Count + $cardCases.Count + 2)")
    exit 0
}

if ($SelfTest) {
    Invoke-SelfTest
}

# 2026-07-28 扩展进程传入的是字符串，这里统一转成布尔值，避免 PowerShell 参数绑定失败
$restoreCursorEnabled = $RestoreCursor -notmatch '^(false|0|no)$'

# 2026-07-28 多个 Antigravity 窗口只允许一个全局扫描器，避免重复点击同一权限按钮
# 2026-10-05：等待现有扫描器释放后接管，父宿主退出时释放互斥并结束子进程。
$script:parentProcess = $null
if ($ParentProcessId -gt 0) {
    try { $script:parentProcess = Get-Process -Id $ParentProcessId -ErrorAction Stop }
    catch { exit 0 }
}
$scannerMutex = New-Object System.Threading.Mutex($false, 'Local\AntigravityAutoAcceptScanner')
$mutexOwned = $false
$waitingReported = $false
try {
    while (-not $mutexOwned -and (Test-ParentAlive)) {
        try { $mutexOwned = $scannerMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $mutexOwned = $true }
        if (-not $mutexOwned) {
            if (-not $waitingReported) {
                [Console]::WriteLine('___SCANNER_WAITING___')
                $waitingReported = $true
            }
            Start-Sleep -Milliseconds $PollMs
        }
    }
    if (-not $mutexOwned -or -not (Test-ParentAlive)) { exit 0 }
    [Console]::WriteLine('___AUTOCLICK_READY___')
    $lastClickTime = [DateTime]::MinValue
    $lastServedWindowHandle = [IntPtr]::Zero # 2026-10-07：最终批准尝试后从下一窗口开始，持续审批的首窗不能饿死其余窗口。

    while (Test-ParentAlive) {
        Start-Sleep -Milliseconds $PollMs
        if (-not (Test-ParentAlive)) { break }
        $elapsed = ([DateTime]::Now - $lastClickTime).TotalMilliseconds
        if ($elapsed -lt $CooldownMs) { continue }

        try {
            $targetIds = Get-TargetProcessIds
            if ($targetIds.Count -eq 0) { continue }
            $windows = @($automation.FindAll([System.Windows.Automation.TreeScope]::Children, $winCondition))
            $didClick = $false
            # 2026-10-07：每轮保留窗口快照并按上次动作窗口轮转，失效句柄只跳过自身。
            $windowStart = 0
            for ($index = 0; $index -lt $windows.Count; $index++) {
                try {
                    if ([IntPtr]$windows[$index].Current.NativeWindowHandle -eq $lastServedWindowHandle) {
                        $windowStart = ($index + 1) % $windows.Count
                        break
                    }
                }
                catch { }
            }

            for ($offset = 0; $offset -lt $windows.Count; $offset++) {
                if ($didClick) { break }
                $win = $windows[($windowStart + $offset) % $windows.Count]
                # 2026-10-07：单窗控件树在扫描时关闭或失效，不阻断同轮其它窗口。
                try {
                    # 2026-10-05：窗口仅按已验证路径的进程 ID 归属，窗口标题不影响识别。
                    $windowProcessId = $win.Current.ProcessId
                    if (-not $targetIds.ContainsKey($windowProcessId)) { continue }
                    $windowHandle = [IntPtr]$win.Current.NativeWindowHandle
                    if ($windowHandle -eq [IntPtr]::Zero) { continue }

                    # 2026-10-05：新版本次审批卡片优先处理，完成后统一进入原点击冷却。
                    # 2026-10-06：浏览器域名卡片使用同卡片本次允许，窄栏菜单不能交给普通按钮匹配。
                    if (Invoke-BrowserPermissionCards $win $windowProcessId $windowHandle) {
                        $didClick = $true
                        $lastClickTime = [DateTime]::Now
                        $lastServedWindowHandle = $windowHandle # 2026-10-07：两类卡片均参与窗口轮转。
                        break
                    }
                    if (Invoke-ApprovalCards $win $windowProcessId $windowHandle) {
                        $didClick = $true
                        $lastClickTime = [DateTime]::Now
                        $lastServedWindowHandle = $windowHandle # 2026-10-07：终端提交尝试后优先服务其它窗口。
                        break
                    }

                    $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
                    foreach ($btn in $buttons) {
                        if ($didClick) { break }
                        # 2026-10-07：单个按钮失效或调用报错仅跳过该按钮，调用后报错不能再物理重试。
                        try {
                            $btnName = $btn.Current.Name
                            if (-not $btn.Current.IsEnabled) { continue }
                            if ($btn.Current.IsOffscreen) { continue }
                            $rect = $btn.Current.BoundingRectangle
                            if ($null -eq (Get-ButtonCenter $rect)) { continue }
                            if (-not (Test-ButtonMatch $btnName)) { continue }
                            $ip = $null
                            try { $ip = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) }
                            catch { }
                            if ($null -ne $ip) {
                                # 2026-10-05：调用前重读按钮并复核宿主归属，扫描期间父进程退出时不执行动作。
                                # 2026-10-07：宿主查询放在最终按钮复核前，查询期间变化的名称及可见性不会沿用。
                                if (-not (Get-TargetProcessIds).ContainsKey($windowProcessId)) { continue }
                                if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                                $btnName = $btn.Current.Name
                                if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or -not (Test-ButtonMatch $btnName)) { continue }
                                if (-not (Test-ParentAlive)) { break }
                                # 2026-10-07：提供者可能在动作后抛错，先占用本轮和窗口轮换；慢调用的冷却从结束时计时。
                                $didClick = $true
                                $lastServedWindowHandle = $windowHandle
                                try {
                                    $ip.Invoke()
                                    [Console]::WriteLine("___CLICK_INVOKE___:$btnName")
                                }
                                finally { $lastClickTime = [DateTime]::Now }
                            }
                            else {
                                # 2026-10-05：回退前重读按钮与窗口，坐标被遮挡、宿主退出或按钮失效均不点击。
                                # 2026-10-07：只有未取得调用模式才物理回退，最后坐标及状态查询后再检查父宿主。
                                if (-not (Get-TargetProcessIds).ContainsKey($windowProcessId)) { continue }
                                if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                                $center = Get-ButtonCenter $btn.Current.BoundingRectangle
                                if ($null -eq $center) { continue }
                                $btnName = $btn.Current.Name
                                if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or -not (Test-ButtonMatch $btnName)) { continue }
                                if (-not (Test-ParentAlive)) { break }
                                # 2026-10-07：物理回退同样只尝试一次，失败或动作后抛错都从动作结束时开始冷却。
                                $didClick = $true
                                $lastServedWindowHandle = $windowHandle
                                try {
                                    if ([MouseHelper]::Click($center.X, $center.Y, $restoreCursorEnabled, $windowHandle, [uint32]$windowProcessId)) {
                                        [Console]::WriteLine("___CLICK_PHYSICAL___:$btnName at ($($center.X),$($center.Y))")
                                    }
                                }
                                finally { $lastClickTime = [DateTime]::Now }
                            }
                        }
                        catch { Write-ApprovalDiagnostic "button scan failed type=$($_.Exception.GetType().Name)" 'button-error' }
                    }
                }
                catch { Write-ApprovalDiagnostic "window scan failed type=$($_.Exception.GetType().Name)" 'window-error' }
            }
        }
        catch {
            if ($_.Exception.Message -notlike '*Operation is not valid*') {
                [Console]::WriteLine("___ERROR___:$($_.Exception.Message)")
            }
        }
    }
}
# 2026-10-05：正常退出和异常退出均释放已持有的单实例锁，等待者可继续接管。
finally {
    if ($mutexOwned) { $scannerMutex.ReleaseMutex() }
    $scannerMutex.Dispose()
    if ($null -ne $script:parentProcess) { $script:parentProcess.Dispose() }
}
