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
    public const byte VK_MENU = 0x12; // Alt key
    public const byte VK_RETURN = 0x0D; // Enter key
    public const uint KEYEVENTF_KEYUP = 0x0002;
    
    public static void SendAltEnter() {
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero); // Alt Down
        keybd_event(VK_RETURN, 0, 0, UIntPtr.Zero); // Enter Down
        keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Enter Up
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); // Alt Up
    }
}
"@

Write-Host "Starting AutoClicker for VS Code (PID $vscodePid)..."

while ($true) {
    Start-Sleep -Seconds 1
    
    # Try to find target buttons across all descendants
    $btnCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $buttons = $automation::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
    
    foreach ($btn in $buttons) {
        if ($null -ne $btn -and $null -ne $btn.Current) {
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
                
                # Fallback: Try setting focus and issuing Alt+Enter natively
                try {
                    $btn.SetFocus()
                    Start-Sleep -Milliseconds 100
                    [Keyboard]::SendAltEnter()
                    Write-Host "Sent native Alt+Enter focus event to $($name)"
                }
                catch {
                    Write-Host "Failed to send keys to $($name): $_"
                }
                
                # Sleep a bit longer after an attempt to let UI process the click
                Start-Sleep -Seconds 2
            }
        }
    }
}
