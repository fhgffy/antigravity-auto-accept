param (
    [string]$vscodePid
)

# 2026-03-24T22:30:00+08:00: 修复控制台输出中文乱码——强制设置输出编码为 UTF-8 //***
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 2026-03-24T22:40:00+08:00: 抑制 PowerShell 进度条和模块加载的 CLIXML 噪音 //***
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$automation = [System.Windows.Automation.AutomationElement]

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Keyboard {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    public static uint GetWindowProcId(IntPtr hwnd) {
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        return pid;
    }

    public const byte VK_MENU = 0x12; 
    public const byte VK_RETURN = 0x0D; 
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const int SW_RESTORE = 9;
    public const int SW_MINIMIZE = 6;

    public static void StealthAltEnter(IntPtr targetHwnd, IntPtr fallbackHwnd, bool forceRestoreFallback) {
        IntPtr currentForeground = GetForegroundWindow();
        bool wasMinimized = IsIconic(targetHwnd);
        bool requiresFocusSwitch = (currentForeground != targetHwnd && currentForeground != IntPtr.Zero);

        if (!requiresFocusSwitch && forceRestoreFallback && fallbackHwnd != IntPtr.Zero) {
            requiresFocusSwitch = true;
            currentForeground = fallbackHwnd; // Pretend the user never left the browser!
        }

        if (requiresFocusSwitch) {
             uint dummy1;
             uint foregroundThreadId = GetWindowThreadProcessId(currentForeground, out dummy1);
             uint myThreadId = GetCurrentThreadId();
             
             if (foregroundThreadId != myThreadId) {
                 AttachThreadInput(myThreadId, foregroundThreadId, true);
                 if (wasMinimized) ShowWindow(targetHwnd, SW_RESTORE);
                 SetForegroundWindow(targetHwnd);
                 AttachThreadInput(myThreadId, foregroundThreadId, false);
             } else {
                 if (wasMinimized) ShowWindow(targetHwnd, SW_RESTORE);
                 SetForegroundWindow(targetHwnd);
             }

             // Give Electron 150ms to wake up from background/minimized state and hook the keyboard
             System.Threading.Thread.Sleep(150); 
        }

        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
        keybd_event(VK_RETURN, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);

        if (requiresFocusSwitch) {
             uint dummy2;
             uint foregroundThreadId = GetWindowThreadProcessId(targetHwnd, out dummy2);
             uint myThreadId = GetCurrentThreadId();
             
             if (foregroundThreadId != myThreadId) {
                 AttachThreadInput(myThreadId, foregroundThreadId, true);
                 SetForegroundWindow(currentForeground);
                 AttachThreadInput(myThreadId, foregroundThreadId, false);
             } else {
                 SetForegroundWindow(currentForeground);
             }

             // Re-minimize if it was minimized originally
             if (wasMinimized) {
                  ShowWindow(targetHwnd, SW_MINIMIZE);
             }
        }
    }
}
"@

# 2026-03-24T22:59:00+08:00: PS1 只输出纯文本标签，TS 侧统一添加 emoji（避免 stdout 管道乱码）//***
$ts = Get-Date -Format 'HH:mm:ss'
Write-Host "[AA:INIT] [$ts] AutoClicker started (PID $vscodePid)"

# Dynamically resolve the IDE's process name from the given PID (handles VS Code, Cursor, VSCodium, Antigravity etc.)
$ideProcessName = "Code"
$parentProc = Get-Process -Id $vscodePid -ErrorAction SilentlyContinue
if ($parentProc) {
    # e.g., "Code", "Cursor", "VSCodium", "Antigravity"
    $ideProcessName = $parentProc.Name
    if ($ideProcessName -match "electron") {
        $ideProcessName = "Antigravity"
    }
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[AA:IDE] [$ts] IDE: $ideProcessName | Watching for permission dialogs..."
}

# 2026-03-25T23:20:00+08:00: v2.1.0 — 双态检测：■ 停止按钮 + 错误面板文本 //***
# ■ 停止按钮：ControlType=Group, ClassName 含 'bg-gray-500'+'rounded-full', 30~50px
# 错误面板：FindFirst 精确搜索 Name="Agent terminated due to error" 文本
#   比 CSS class 匹配更稳定——直接命中语义文本，不依赖可变的样式类名
# 返回 hashtable: @{ Running=$bool; HasError=$bool }
function Get-AgentState($win) {
    $state = @{ Running = $false; HasError = $false }

    # 检测 ■ 停止按钮（Group 遍历）
    $groupCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Group
    )
    $groups = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $groupCondition)
    foreach ($g in $groups) {
        try {
            if ($null -eq $g -or $null -eq $g.Current) { continue }
            $cls = $g.Current.ClassName
            if ($null -eq $cls) { continue }
            # 匹配 ■ 停止按钮的 CSS 指纹（agent 运行中）
            if ($cls -match 'bg-gray-500' -and $cls -match 'rounded-full' -and $cls -match 'cursor-pointer') {
                $r = $g.Current.BoundingRectangle
                if (-not $r.IsEmpty -and $r.Width -ge 30 -and $r.Width -le 50 -and $r.Height -ge 30 -and $r.Height -le 50) {
                    $state.Running = $true
                    break
                }
            }
        } catch {}
    }

    # 检测错误面板：精确搜索 "Agent terminated due to error" 文本（FindFirst 一旦命中立即返回）
    if (-not $state.Running) {
        try {
            $errorNameCondition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty,
                "Agent terminated due to error"
            )
            $errorText = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $errorNameCondition)
            if ($null -ne $errorText) {
                $state.HasError = $true
            }
        } catch {}
    }

    return $state
}
#***

# Track the last window the user was actively using outside the IDE
$global:lastNonIdeWindow = [IntPtr]::Zero
$global:lastNonIdeTime = [DateTime]::MinValue

while ($true) {
    Start-Sleep -Seconds 1

    $codePids = @()
    if ($ideProcessName) {
        $codePids = Get-Process -Name $ideProcessName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id
    }

    if ($null -eq $codePids -or $codePids.Count -eq 0) {
        continue
    }

    # Constantly background-track what the user is currently looking at
    $currentHwnd = [Keyboard]::GetForegroundWindow()
    if ($currentHwnd -ne [IntPtr]::Zero) {
        $cProcId = [Keyboard]::GetWindowProcId($currentHwnd)
        if ($codePids -notcontains $cProcId) {
            $global:lastNonIdeWindow = $currentHwnd
            $global:lastNonIdeTime = [DateTime]::Now
        }
    }

    # Find ONLY top-level windows belonging to the IDE process to prevent global OS UI tree traversal freezes
    $targetWindows = @()
    $windowCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1")
    $windows = $automation::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $windowCondition)
    foreach ($win in $windows) {
        if ($null -ne $win.Current -and $codePids -contains $win.Current.ProcessId) {
            $targetWindows += $win
        }
    }

    # 2026-03-25T23:10:00+08:00: v2.1.0 — 双态检测：■ 运行中 / 错误面板 / 完全空闲 //***
    # Running=true → 全量匹配权限按钮
    # HasError=true → 仅匹配 Retry/重试（错误面板恢复）
    # 两者都 false → 完全空闲，跳过本轮
    $agentRunning = $false
    $hasError = $false
    foreach ($win in $targetWindows) {
        $s = Get-AgentState $win
        if ($s.Running) { $agentRunning = $true }
        if ($s.HasError) { $hasError = $true }
    }

    if (-not $agentRunning -and -not $hasError) {
        # agent 完全空闲且无错误面板，跳过本轮扫描
        continue
    }


    # 2026-03-25T23:10:00+08:00: 根据状态选择按钮匹配范围 //***
    if ($agentRunning) {
        # agent 运行中：全量匹配所有权限/重试按钮
        $btnRegex = "(?i)^(allow|allow once|allow this conversation|allow all|approve|yes|proceed|always allow.*|always run.*|always proceed.*|retry|许可|允许|允许本次|允许此对话|全部允许|批准|确认|确定|继续|总是允许|总是运行|总是继续|同意|重试|执行)$"
    } else {
        # agent 空闲但有错误面板：仅点击 Retry/重试（网络错误恢复）
        $btnRegex = "(?i)^(retry|重试)$"
    }
    #***

    $btnCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)

    foreach ($win in $targetWindows) {
        $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)

        foreach ($btn in $buttons) {
            if ($null -ne $btn -and $null -ne $btn.Current) {

                $name = $btn.Current.Name
                # 2026-03-24T22:30:00+08:00: 修复 $name 为 null 时 .Trim() 抛出 InvokeMethodOnNull //***
                if ($null -eq $name) { continue }
                $cleanName = $name.Trim()

                # 严格匹配：按钮文本必须命中当前状态的关键词范围
                # v1.3.9 (2026-03-21): 新增 'proceed'/'execute'/'继续'/'执行' //***
                # v1.4.0 (2026-03-21): 新增 'allow once'/'allow this conversation'/'allow all' //***
                # v2.1.0 (2026-03-25): $btnRegex 由上方双态检测动态决定 //***
                if ($cleanName -match $btnRegex) {

                    if ($btn.Current.IsEnabled -eq $false) { continue }
                    if ($btn.Current.BoundingRectangle.IsEmpty) { continue }

                    # 2026-03-24T22:59:00+08:00: 纯文本点击日志，emoji 由 TS 侧添加 //***
                    $ts = Get-Date -Format 'HH:mm:ss'
                    Write-Host "[AA:CLICK] [$ts] Clicked: '$cleanName'"

                    try {
                        $currentHwnd = [Keyboard]::GetForegroundWindow()
                        if ($codePids -contains [Keyboard]::GetWindowProcId($currentHwnd)) {
                            $btn.SetFocus()
                        }
                        $scrollPattern = $btn.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern) -as [System.Windows.Automation.ScrollItemPattern]
                        if ($scrollPattern) { $scrollPattern.ScrollIntoView() }
                    }
                    catch { }

                    $invokedSoftly = $false

                    # 2026-03-24T22:40:00+08:00: InvokePattern 点击 //***
                    try {
                        $invokePattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) -as [System.Windows.Automation.InvokePattern]
                        if ($invokePattern) {
                            $invokePattern.Invoke()
                            $invokedSoftly = $true
                        }
                    }
                    catch { }

                    # 2026-03-24T22:40:00+08:00: LegacyPattern 回退 //***
                    if (-not $invokedSoftly) {
                        try {
                            $legacyPattern = $btn.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern) -as [System.Windows.Automation.LegacyIAccessiblePattern]
                            if ($legacyPattern) {
                                $legacyPattern.DoDefaultAction()
                                $invokedSoftly = $true
                            }
                        }
                        catch { }
                    }

                    # Stealth Focus 回退 (Ghost Protocol)
                    if (-not $invokedSoftly) {
                        try {
                            $hwnd = [IntPtr]($win.Current.NativeWindowHandle)
                            if ($hwnd -ne [IntPtr]::Zero) {
                                $forceRestore = $false
                                if (($global:lastNonIdeWindow -ne [IntPtr]::Zero) -and (([DateTime]::Now - $global:lastNonIdeTime).TotalSeconds -lt 5)) {
                                    $forceRestore = $true
                                }
                                [Keyboard]::StealthAltEnter($hwnd, $global:lastNonIdeWindow, $forceRestore)
                            }
                        }
                        catch { }
                    }

                    Start-Sleep -Milliseconds 200
                    break  # 每周期只点击一个按钮
                }
            }
        }
    }
}
