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
    catch {
        try {
            $legacy = $Option.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
            return ($legacy.Current.State -band 16) -ne 0
        }
        catch { return $false }
    }
}

# 2026-10-05：读取审批卡片的实时控件特征，普通问答表单和全局提交按钮不会命中。
function Test-LiveApprovalCard($Card) {
    $edits = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition)
    $radios = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    $buttons = $Card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
    return Test-ApprovalCardShape @($edits | ForEach-Object { $_.Current.Name }) @($radios | ForEach-Object { $_.Current.AutomationId }) @($radios | ForEach-Object { $_.Current.Name }) @($buttons | ForEach-Object { $_.Current.Name })
}

# 2026-10-05：审批卡片的诊断最多每五秒输出一次，便于排查宿主 UI 变化且避免刷屏。
$script:lastApprovalDiagnosticTime = [DateTime]::MinValue
function Write-ApprovalDiagnostic([string]$Message) {
    if (([DateTime]::Now - $script:lastApprovalDiagnosticTime).TotalSeconds -lt 5) { return }
    [Console]::WriteLine("___SCANNER_DIAGNOSTIC___:$Message")
    $script:lastApprovalDiagnosticTime = [DateTime]::Now
}

# 2026-10-05：新版卡片只选本次允许并提交同一卡片，不修改终端或权限的持久设置。
function Invoke-ApprovalCards($Window, [int]$WindowProcessId, [IntPtr]$WindowHandle) {
    $conversation = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $conversationCondition)
    if ($null -eq $conversation) { return $false }
    $options = $conversation.FindAll([System.Windows.Automation.TreeScope]::Descendants, $radioCondition)
    foreach ($option in $options) {
        try {
            if ($option.Current.AutomationId -notmatch '^ask-opt-.+-1$' -or -not (Test-OneTimeApprovalName $option.Current.Name)) { continue }
            if (-not $option.Current.IsEnabled -or $option.Current.IsOffscreen) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($option)
            if ($null -eq $card) { continue }
            $card = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($card)
            if ($null -eq $card -or -not (Test-LiveApprovalCard $card)) {
                Write-ApprovalDiagnostic 'permission-card shape mismatch'
                continue
            }
            if (-not (Test-ApprovalOptionSelected $option)) {
                try {
                    $selection = $option.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                    $selection.Select()
                }
                catch {
                    try {
                        $invoke = $option.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                        $invoke.Invoke()
                    }
                    catch {
                        $legacy = $option.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
                        $legacy.DoDefaultAction()
                    }
                }
            }
            if (-not (Test-ApprovalOptionSelected $option) -or -not (Test-LiveApprovalCard $card)) {
                Write-ApprovalDiagnostic 'permission-card one-time selection unavailable'
                continue
            }
            if (-not (Test-ParentAlive) -or -not (Get-TargetProcessIds).ContainsKey($WindowProcessId)) { continue }
            if ($Window.Current.NativeWindowHandle -ne $WindowHandle.ToInt64() -or $Window.Current.ProcessId -ne $WindowProcessId) { continue }
            $buttons = $card.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
            foreach ($submit in $buttons) {
                if ($submit.Current.Name -notmatch '^(Submit|提交)(\s*[↵⏎])?$') { continue }
                if (-not $submit.Current.IsEnabled -or $submit.Current.IsOffscreen) { continue }
                $invoke = $submit.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                # 2026-10-05：提交前最后复核本次允许，避免宿主检查期间选项变成始终允许或拒绝。
                if (-not $option.Current.IsEnabled -or $option.Current.IsOffscreen -or -not (Test-LiveApprovalCard $card) -or -not (Test-ApprovalOptionSelected $option)) { continue }
                # 2026-10-05：所有控件查询结束后最后检查父宿主，退出期间不提交权限卡片。
                if (-not (Test-ParentAlive)) { return $false }
                $invoke.Invoke()
                [Console]::WriteLine('___CLICK_INVOKE___:Submit (one-time permission)')
                return $true
            }
        }
        catch { Write-ApprovalDiagnostic "permission-card error: $($_.Exception.Message)" }
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
        @{ Name = 'Allow once'; Expected = $true },
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
        @{ Name = 'Run command (Alt+Enter)'; Expected = $true }
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

    while (Test-ParentAlive) {
        Start-Sleep -Milliseconds $PollMs
        if (-not (Test-ParentAlive)) { break }
        $elapsed = ([DateTime]::Now - $lastClickTime).TotalMilliseconds
        if ($elapsed -lt $CooldownMs) { continue }

        try {
            $targetIds = Get-TargetProcessIds
            if ($targetIds.Count -eq 0) { continue }
            $windows = $automation.FindAll([System.Windows.Automation.TreeScope]::Children, $winCondition)
            $didClick = $false

            foreach ($win in $windows) {
                if ($didClick) { break }
                # 2026-10-05：窗口仅按已验证路径的进程 ID 归属，窗口标题不影响识别。
                $windowProcessId = $win.Current.ProcessId
                if (-not $targetIds.ContainsKey($windowProcessId)) { continue }
                $windowHandle = [IntPtr]$win.Current.NativeWindowHandle
                if ($windowHandle -eq [IntPtr]::Zero) { continue }

                # 2026-10-05：新版本次审批卡片优先处理，完成后统一进入原点击冷却。
                if (Invoke-ApprovalCards $win $windowProcessId $windowHandle) {
                    $didClick = $true
                    $lastClickTime = [DateTime]::Now
                    break
                }

                $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)

                foreach ($btn in $buttons) {
                    if ($didClick) { break }
                    $btnName = $btn.Current.Name
                    if (-not $btn.Current.IsEnabled) { continue }
                    if ($btn.Current.IsOffscreen) { continue }
                    $rect = $btn.Current.BoundingRectangle
                    if ($null -eq (Get-ButtonCenter $rect)) { continue }
                    if (-not (Test-ButtonMatch $btnName)) { continue }

                    try {
                        $ip = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                        # 2026-10-05：调用前重读按钮并复核宿主归属，扫描期间父进程退出时不执行动作。
                        $btnName = $btn.Current.Name
                        if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen -or -not (Test-ButtonMatch $btnName)) { continue }
                        if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                        if (-not (Get-TargetProcessIds).ContainsKey($windowProcessId)) { continue }
                        if (-not (Test-ParentAlive)) { break }
                        $ip.Invoke()
                        [Console]::WriteLine("___CLICK_INVOKE___:$btnName")
                        $didClick = $true
                    }
                    catch {
                        # 2026-10-05：回退前重读按钮与窗口，坐标被遮挡、宿主退出或按钮失效均不点击。
                        if (-not (Test-ParentAlive)) { break }
                        if (-not $btn.Current.IsEnabled -or $btn.Current.IsOffscreen) { continue }
                        $btnName = $btn.Current.Name
                        if (-not (Test-ButtonMatch $btnName)) { continue }
                        if ($win.Current.NativeWindowHandle -ne $windowHandle.ToInt64() -or $win.Current.ProcessId -ne $windowProcessId) { continue }
                        if (-not (Get-TargetProcessIds).ContainsKey($windowProcessId)) { continue }
                        $center = Get-ButtonCenter $btn.Current.BoundingRectangle
                        if ($null -eq $center) { continue }
                        if ([MouseHelper]::Click($center.X, $center.Y, $restoreCursorEnabled, $windowHandle, [uint32]$windowProcessId)) {
                            [Console]::WriteLine("___CLICK_PHYSICAL___:$btnName at ($($center.X),$($center.Y))")
                            $didClick = $true
                        }
                    }

                    if ($didClick) {
                        $lastClickTime = [DateTime]::Now
                    }
                }
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
