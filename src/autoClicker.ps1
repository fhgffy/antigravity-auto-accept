param (
    [string]$vscodePid
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$automation = [System.Windows.Automation.AutomationElement]
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1")

# Keywords to click
$targetNames = @("Allow", "Approve", "Yes", "OK", "Run", "Always Allow", "许可", "允许", "批准", "确认", "确定", "运行", "总是允许", "同意")

Write-Host "Starting AutoClicker for VS Code (PID $vscodePid)..."

while ($true) {
    Start-Sleep -Seconds 2
    
    # Try to find target buttons in any VS Code window
    $windows = $automation::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $condition)
    
    foreach ($win in $windows) {
        # Check if window name contains VS Code
        if ($win.Current.Name -match "Visual Studio Code") {
            # Search for buttons
            $btnCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
            $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)
            
            foreach ($btn in $buttons) {
                $name = $btn.Current.Name
                if ($name -in $targetNames -or $targetNames -contains $name) {
                    Write-Host "Found button: $name"
                    
                    # Ensure the button actually belongs to a dialog or notification related to Antigravity
                    # This is a bit generous, we will just click any "Approve" button
                    $invokePattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) -as [System.Windows.Automation.InvokePattern]
                    if ($invokePattern) {
                        try {
                            $invokePattern.Invoke()
                            Write-Host "Clicked $name"
                        }
                        catch {
                            Write-Host "Failed to click $($name): $_"
                        }
                    }
                }
            }
        }
    }
}
