param (
    [string]$vscodePid
)

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

Write-Host "Starting AutoClicker for VS Code (PID $vscodePid)..."

# Dynamically resolve the IDE's process name from the given PID (handles VS Code, Cursor, VSCodium, Antigravity etc.)
$ideProcessName = "Code"
$parentProc = Get-Process -Id $vscodePid -ErrorAction SilentlyContinue
if ($parentProc) {
    # e.g., "Code", "Cursor", "VSCodium", "Antigravity"
    $ideProcessName = $parentProc.Name
    if ($ideProcessName -match "electron") {
        $ideProcessName = "Antigravity"
    }
    Write-Host "Resolved IDE Process Name: $ideProcessName"
}

# Cache to prevent infinitely re-clicking the same historical buttons in the chat view
$global:clickedIds = New-Object System.Collections.Generic.HashSet[string]

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

    # Then we only search for target buttons inside those specific Electron windows.

    $btnCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    
    # Only search for buttons inside actual VS Code windows!
    foreach ($win in $targetWindows) {
        $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
        
        foreach ($btn in $buttons) {
            if ($null -ne $btn -and $null -ne $btn.Current) {
            
                $name = $btn.Current.Name
                $class = $btn.Current.ClassName
                $id = $btn.Current.AutomationId
                $cleanName = $name.Trim()
                
                # DIAGNOSTIC: Print every button we scan in VS Code so the user can send me the log if it fails
                if ($cleanName.Length -gt 0 -and $cleanName.Length -lt 50) {
                    # Write-Host "SCANNING BTN: '$cleanName'"
                }
            
                # Check if we have already processed this specific button instance in the UI tree
                $runtimeIdArray = $btn.GetRuntimeId()
                if ($null -ne $runtimeIdArray) {
                    $runtimeId = $runtimeIdArray -join ','
                    if ($global:clickedIds.Contains($runtimeId)) {
                        continue
                    }
                }

                # 严格匹配：按钮文本必须命中权限/重试关键词
                # 注意：'run$' 和 'run\s+.*' 已移除，因为会误触代码块 "Run" 按钮和内联聊天动作按钮！
                # 那样会导致 StealthAltEnter 发射，Alt+Enter 注入意外提交聊天输入框。
                # v1.3.9 (2026-03-21): 新增 'proceed'/'execute'/'继续'/'执行' — 修复 Antigravity 浏览器 JS 执行权限弹窗 (Issue #1) //***
                # v1.4.0 (2026-03-21T17:16:02+08:00): 新增 'allow once'/'allow this conversation'/'allow all' — 修复目录权限弹窗不自动点击 //***
                if ($cleanName -match "(?i)^(allow|allow once|allow this conversation|allow all|approve|yes|proceed|always allow.*|always run.*|always proceed.*|retry|许可|允许|允许本次|允许此对话|全部允许|批准|确认|确定|继续|总是允许|总是运行|总是继续|同意|重试|执行)$") {
                    
                    # Ignore elements that are explicitly disabled (historical buttons often become disabled)
                    if ($btn.Current.IsEnabled -eq $false) {
                        continue
                    }

                    # We also want to skip buttons that are completely off-screen IF they are historical.
                    # BoundingRectangle.IsEmpty is true when the element is completely virtualized out of the viewport.
                    if ($btn.Current.BoundingRectangle.IsEmpty) {
                        continue
                    }

                    Write-Host ">>> TARGET MATCHED: '$cleanName' <<<"

                    # Attempt to bring the element into view explicitly. This is crucial for offscreen buttons in Electron.
                    try {
                        # Only steal focus if the IDE is already the active window. Otherwise scrolling might steal the user's typing focus!
                        $currentHwnd = [Keyboard]::GetForegroundWindow()
                        if ($codePids -contains [Keyboard]::GetWindowProcId($currentHwnd)) {
                            $btn.SetFocus()
                        }
                        
                        $scrollPattern = $btn.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern) -as [System.Windows.Automation.ScrollItemPattern]
                        if ($scrollPattern) {
                            $scrollPattern.ScrollIntoView()
                        }
                    }
                    catch { }

                    # Track whether we successfully clicked it without needing physical keyboard
                    $invokedSoftly = $false

                    # Attempt to invoke (Silently fails on Electron shadow DOM elements)
                    $invokePattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) -as [System.Windows.Automation.InvokePattern]
                    if ($invokePattern) {
                        try {
                            $invokePattern.Invoke()
                            Write-Host "Invoked $cleanName via InvokePattern"
                            $invokedSoftly = $true
                        }
                        catch { }
                    }
                
                    # Attempt LegacyIAccessiblePattern (Silently fails on some Electron apps, works on others)
                    if (-not $invokedSoftly) {
                        $legacyPattern = $btn.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern) -as [System.Windows.Automation.LegacyIAccessiblePattern]
                        if ($legacyPattern) {
                            try {
                                $legacyPattern.DoDefaultAction()
                                Write-Host "Invoked $cleanName via LegacyPattern"
                                $invokedSoftly = $true
                            }
                            catch { }
                        }
                    }
                
                    # Fallback: Stealth Focus (Ghost Protocol)
                    # Quickly steals focus, injects the physical Alt+Enter, and instantly bounces focus back to user's browser in <80ms.
                    if (-not $invokedSoftly) {
                        try {
                            $hwnd = [IntPtr]($win.Current.NativeWindowHandle)
                            if ($hwnd -ne [IntPtr]::Zero) {
                                $forceRestore = $false
                                if (($global:lastNonIdeWindow -ne [IntPtr]::Zero) -and (([DateTime]::Now - $global:lastNonIdeTime).TotalSeconds -lt 5)) {
                                    $forceRestore = $true
                                    Write-Host "IDE violently stole focus within last 5s! Un-stealing and returning focus back to Browser."
                                }

                                # Only do the keyboard simulation if we have to, and do it gently.
                                [Keyboard]::StealthAltEnter($hwnd, $global:lastNonIdeWindow, $forceRestore)
                                Write-Host "Sent Stealth Alt+Enter to window $hwnd for $($cleanName)"
                            }
                        }
                        catch { }
                    }

                    # Mark element as clicked so we NEVER process it again, even if it stays in the DOM history forever.
                    if ($null -ne $runtimeIdArray) {
                        $null = $global:clickedIds.Add($runtimeId)
                    }

                    # Sleep less so we can blaze through these faster without causing the script to lag and trigger multiple window bounds
                    Start-Sleep -Milliseconds 200

                    # BREAK out of the button processing loop!
                    # If there are multiple historical buttons on screen, processing them all in one pass 
                    # causes the ScrollIntoView to wildly jitter the scrollbar back and forth between them.
                    # By breaking, we only click ONE button per 1-second polling cycle.
                    break
                }
            }
        }
    }
}
