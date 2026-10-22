# 2026-10-21：仅替换创建 UIA 根的原生边界，验证真实窗口缓存的身份复核、重新绑定、完整快照和失败回退。
param([string]$ScannerSourcePath='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes # 2026-10-21：只加载枚举类型，不查询真实桌面。
$path=if($ScannerSourcePath){[IO.Path]::GetFullPath($ScannerSourcePath)}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))}
$source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8);$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Source parse failed'}
$definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Get-ScannerWindows'},$true))
if($definition.Count-ne1){throw 'Required window snapshot behavior missing'}
$function=$definition[0].Extent.Text
$boundary='[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)'
if(($function.Split(@($boundary),[StringSplitOptions]::None).Count-1)-ne1){throw 'Exact UIA root creation boundary missing'}
. ([scriptblock]::Create($function.Replace($boundary,'(New-TestWindowRoot $handle)')))
function Write-ApprovalDiagnostic{}
function New-TestWindowRoot([long]$Handle){$script:bindings++;if(-not$script:factory.ContainsKey($Handle)){throw 'Expected binding failure'};return $script:factory[$Handle]}
function New-WindowValue([long]$Handle,[int]$ProcessId){return [pscustomobject]@{Handle=$Handle;ProcessId=$ProcessId}}
function New-LiveRoot([long]$Handle,[int]$ProcessId){return [pscustomobject]@{Current=[pscustomobject]@{NativeWindowHandle=$Handle;ProcessId=$ProcessId}}}
$script:bindings=0;$script:factory=@{};$script:windowRoots=@{}
$script:discoveryClient=[pscustomobject]@{Values=@();Failure=$false}
$script:discoveryClient|Add-Member ScriptMethod Windows {if($this.Failure){throw 'Expected incomplete snapshot'};return $this.Values}
$fallback=New-LiveRoot 999 999
$automation=[pscustomobject]@{Fallback=$fallback;Calls=0}
$automation|Add-Member ScriptMethod FindAll {param($scope,$condition)$this.Calls++;return @($this.Fallback)}
$checks=0
$first=New-LiveRoot 42 123;$script:factory[[long]42]=$first;$script:discoveryClient.Values=@(New-WindowValue 42 123)
$a=@(Get-ScannerWindows);$b=@(Get-ScannerWindows)
if($a.Count-ne1-or$b.Count-ne1-or-not[object]::ReferenceEquals($a[0],$first)-or-not[object]::ReferenceEquals($b[0],$first)-or$script:bindings-ne1){throw 'Stable root not reused'}
$checks++
$replacement=New-LiveRoot 42 456;$script:factory[[long]42]=$replacement;$script:discoveryClient.Values=@(New-WindowValue 42 456)
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$replacement)-or$script:bindings-ne2){throw 'Reused HWND retained old process root'}
$checks++
$replacement.Current=$null;$fresh=New-LiveRoot 42 456;$script:factory[[long]42]=$fresh
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$fresh)-or$script:bindings-ne3){throw 'Unavailable root was not rebound'}
$checks++
$preserved=$script:windowRoots;$script:discoveryClient.Failure=$true
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$fallback)-or-not[object]::ReferenceEquals($preserved,$script:windowRoots)){throw 'Incomplete snapshot lost prior roots or skipped original lookup'}
$checks++
$script:discoveryClient.Failure=$false;$script:discoveryClient.Values=@(New-WindowValue 0 123)
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$fallback)){throw 'Incomplete identity accepted'}
$checks++
$script:discoveryClient.Values=@((New-WindowValue 42 456),(New-WindowValue 42 456))
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$fallback)-or-not[object]::ReferenceEquals($preserved,$script:windowRoots)){throw 'Duplicate partial snapshot committed'}
$checks++
$script:discoveryClient.Values=@(New-WindowValue 43 456)
$a=@(Get-ScannerWindows)
if($a.Count-ne1-or-not[object]::ReferenceEquals($a[0],$fallback)){throw 'Failed new root binding did not fall back'}
$checks++
$script:discoveryClient.Values=@();$a=@(Get-ScannerWindows)
if($a.Count-ne0-or$script:windowRoots.Count-ne0){throw 'Complete closed snapshot retained stale roots'}
$checks++
Write-Output "___SCANNER_WINDOWS_TEST_DONE___:passed=$checks"
