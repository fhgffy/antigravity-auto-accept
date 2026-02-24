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

while ($true) {
    Start-Sleep -Seconds 1
    
    $codePids = Get-Process -Name "Code", "Code - Insiders" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id

    # Try to find target buttons across all descendants
    $btnCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $buttons = $automation::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
    
    foreach ($btn in $buttons) {
        if ($null -ne $btn -and $null -ne $btn.Current) {
            # Strictly ensure this button belongs to VS Code process to prevent clicking web browsers
            if ($null -ne $codePids -and -not ($codePids -contains $btn.Current.ProcessId)) { continue }
            
            $name = $btn.Current.Name
            $class = $btn.Current.ClassName
            $id = $btn.Current.AutomationId
            
            # Strict check: Button text must explicitly match permission words.
            # Avoid broadly catching ANY 'primary' class button, which causes random extension reloads to be clicked.
            if ($name -match "(?i)^(allow|approve|yes|always allow|run|许可|允许|批准|确认|确定|总是允许|同意)$") {
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
