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
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint cButtons, uint dwExtraInfo);

    public const byte VK_MENU = 0x12; // Alt key
    public const byte VK_RETURN = 0x0D; // Enter key
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    
    public static void SendAltEnter() {
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero); // Alt Down
        keybd_event(VK_RETURN, 0, 0, UIntPtr.Zero); // Enter Down
        keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Enter Up
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Alt Up
    }
    
    public static void ClickPosition(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
    }
}
"@

Write-Host "Starting AutoClicker for VS Code (PID $vscodePid)..."

# Dynamically resolve the IDE's process name from the given PID (handles VS Code, Cursor, VSCodium, etc.)
$ideProcessName = "Code"
$parentProc = Get-Process -Id $vscodePid -ErrorAction SilentlyContinue
if ($parentProc) {
    # e.g., "Code", "Cursor", "VSCodium"
    $ideProcessName = $parentProc.Name
    Write-Host "Resolved IDE Process Name: $ideProcessName"
}

while ($true) {
    Start-Sleep -Seconds 1

    $codePids = @()
    if ($ideProcessName) {
        $codePids = Get-Process -Name $ideProcessName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id
    }

    if ($null -eq $codePids -or $codePids.Count -eq 0) {
        continue
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
                
                # DIAGNOSTIC: Print every button we scan in VS Code so the user can send me the log if it fails
                if ($name.Length -gt 0 -and $name.Length -lt 50) {
                    Write-Host "SCANNING BTN: '$name'"
                }
            
                # Strict check: Button text must explicitly match permission words.
                # Avoid broadly catching ANY 'primary' class button, which causes random extension reloads to be clicked.
                if ($name -match "(?i)^(allow|approve|yes|always allow.*|run alt\+.*|always run.*|run$|许可|允许|批准|确认|确定|总是允许|同意)$") {
                    # Attempt to invoke
                    $invokePattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) -as [System.Windows.Automation.InvokePattern]
                    if ($invokePattern) {
                        try {
                            $invokePattern.Invoke()
                            Write-Host "Clicked $name (Class: $class, ID: $id)"
                        }
                        catch {
                            Write-Host "Failed to click $($name): $_"
                        }
                    }
                
                    # Fallback 1: Try setting focus and issuing Alt+Enter natively
                    try {
                        $btn.SetFocus()
                        Start-Sleep -Milliseconds 50
                        [Keyboard]::SendAltEnter()
                        Write-Host "Sent native Alt+Enter focus event to $($name)"
                    }
                    catch {
                        Write-Host "Failed to send keys to $($name): $_"
                    }

                    # Fallback 2: Physical Mouse Click Action
                    try {
                        $rect = $btn.Current.BoundingRectangle
                        if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
                            $x = [int]($rect.Left + ($rect.Width / 2))
                            $y = [int]($rect.Top + ($rect.Height / 2))
                            [Keyboard]::ClickPosition($x, $y)
                            Write-Host "Sent native Mouse Click to ($x, $y)"
                        }
                    }
                    catch {
                        Write-Host "Failed to send physical click to $($name): $_"
                    }
                
                    # Sleep a bit longer after an attempt to let UI process the click
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}
