param(
    [int]$PollMs = 500,
    [int]$CooldownMs = 1500
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(30);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
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

$targetPrefixes = @('Run', 'Accept', 'Allow', 'Apply', 'Continue', 'Proceed', 'Retry', 'Execute', 'Approve', 'Confirm', 'Overwrite', 'Save')
$excludeExact = @('Run and Debug', 'Run Task', 'Run Build Task', 'Run File', 'Always run', 'Run Extension', 'Run Selection')
$exactOnly = @('Yes', 'OK', 'Ok')

function Test-ButtonMatch([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim()

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
                if ($rest[0] -eq ' ' -or $rest[0] -eq '(' -or $rest[0] -eq '+') { return $true }
                if ($rest -like 'Alt*' -or $rest -like 'Ctrl*' -or $rest -like 'Shift*') { return $true }
                if ($p.Length -gt 3 -and $rest.Length -lt 30) { return $true }
            }
        }
    }
    return $false
}

Write-Host "___AUTOCLICK_READY___"
$lastClickTime = [DateTime]::MinValue

while ($true) {
    Start-Sleep -Milliseconds $PollMs
    $elapsed = ([DateTime]::Now - $lastClickTime).TotalMilliseconds
    if ($elapsed -lt $CooldownMs) { continue }

    try {
        $windows = $automation.FindAll([System.Windows.Automation.TreeScope]::Children, $winCondition)
        $didClick = $false

        foreach ($win in $windows) {
            if ($didClick) { break }
            $winName = $win.Current.Name
            if ($winName -notlike '*Antigravity*') { continue }

            $buttons = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCondition)

            foreach ($btn in $buttons) {
                if ($didClick) { break }
                $btnName = $btn.Current.Name
                $rect = $btn.Current.BoundingRectangle
                if ($rect.Width -le 0 -or $rect.Height -le 0) { continue }
                if ($rect.Y -lt 0 -or $rect.X -lt 0) { continue }
                if (-not (Test-ButtonMatch $btnName)) { continue }

                try {
                    $ip = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                    $ip.Invoke()
                    Write-Host "___CLICK_INVOKE___:$btnName"
                    $didClick = $true
                }
                catch {
                    $cx = [int]($rect.X + $rect.Width / 2)
                    $cy = [int]($rect.Y + $rect.Height / 2)
                    [MouseHelper]::Click($cx, $cy)
                    Write-Host "___CLICK_PHYSICAL___:$btnName at ($cx,$cy)"
                    $didClick = $true
                }

                if ($didClick) {
                    $lastClickTime = [DateTime]::Now
                }
            }
        }
    }
    catch {
        if ($_.Exception.Message -notlike '*Operation is not valid*') {
            Write-Host "___ERROR___:$($_.Exception.Message)"
        }
    }
}
