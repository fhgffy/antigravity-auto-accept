param (
    [string]$vscodePid
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$automation = [System.Windows.Automation.AutomationElement]

# Keywords to click
$targetNames = @("Allow", "Approve", "Yes", "OK", "Run", "Always Allow", "许可", "允许", "批准", "确认", "确定", "运行", "总是允许", "同意")

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
            if ($name -match "(?i)^(allow|approve|yes|always allow|许可|允许|批准|确认|确定|总是允许|同意)$") {
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
            }
        }
    }
}
