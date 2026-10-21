# 2026-10-21：回放真实扫描尾段，缓存只减少无关查询；命中或缓存失败仍进入原实时核验，不调用桌面动作。
param([string]$ScannerSourcePath='')
$ErrorActionPreference='Stop'
$scannerPath=if($ScannerSourcePath){[IO.Path]::GetFullPath($ScannerSourcePath)}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))}
$source=[IO.File]::ReadAllText($scannerPath,[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Scanner parse failed'}
foreach($name in @('targetPrefixes','excludeExact','exactOnly')){
    $a=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst]-and$n.Left -is [Management.Automation.Language.VariableExpressionAst]-and$n.Left.VariablePath.UserPath-ceq$name},$true))
    if($a.Count-ne1){throw 'Matching table missing'}
    . ([scriptblock]::Create($a[0].Extent.Text))
}
foreach($name in @('Test-PrefixBoundary','Test-ButtonMatch','Get-DiscoveryFlags','Get-ScannerWindows')){
    $f=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
    if($f.Count-ne1){throw ('Required discovery behavior missing: '+$name)}
    . ([scriptblock]::Create($f[0].Extent.Text))
}
$cases=@(
    @{Name='idle-exclusions';Buttons=@('Save','Run and Debug','Run Task','Always Allow');Radio=$false;Browser=0;Terminal=0;Generic=0},
    @{Name='terminal-outside-conversation';Buttons=@('Submit');Radio=$true;Browser=0;Terminal=1;Generic=0},
    @{Name='browser-wide';Buttons=@('Always Allow','Allow Once');Radio=$false;Browser=1;Terminal=0;Generic=0},
    @{Name='browser-narrow';Buttons=@('Always Allow','More actions');Radio=$false;Browser=1;Terminal=0;Generic=0},
    @{Name='generic-approval';Buttons=@('Accept changes');Radio=$false;Browser=0;Terminal=0;Generic=1},
    @{Name='mixed';Buttons=@('More actions','Run');Radio=$true;Browser=1;Terminal=1;Generic=1},
    @{Name='provider-failure';Buttons=@();Radio=$false;Failure=$true;Browser=1;Terminal=1;Generic=1}
)
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$tailIndex=$source.IndexOf('$script:parentProcess = $null',[StringComparison]::Ordinal)
if($tailIndex-lt0){throw 'Real lifecycle missing'}
$tail=$source.Substring($tailIndex).Replace('Local\AntigravityAutoAcceptScanner','Local\AntigravityAutoAcceptScanner.DiscoveryTest.'+[Guid]::NewGuid().ToString('N'))
$checks=0
foreach($case in $cases){
    $script:discoveryCounts=@{Browser=0;Terminal=0;Generic=0}
    $script:discoveryAlive=$true
    function Test-ParentAlive{return $script:discoveryAlive}
    function Get-TargetProcessIds([int]$ProcessId){return @{$ProcessId=$true}}
    function Invoke-BrowserPermissionCards{$script:discoveryCounts.Browser++;return $false}
    function Invoke-ApprovalCards{$script:discoveryCounts.Terminal++;return $false}
    function Write-ApprovalDiagnostic{}
    $script:discoveryClient=[pscustomobject]@{Snapshot=[pscustomobject]@{ButtonNames=[string[]]$case.Buttons;HasRadio=$case.Radio};Failure=[bool]$case.Failure;Reads=0;Disposed=$false}
    $script:discoveryClient|Add-Member ScriptMethod Read {param($hwnd) if($hwnd.ToInt64()-ne42){throw 'Wrong window snapshot'};$this.Reads++;if($this.Failure){throw 'Expected provider failure'};return $this.Snapshot}
    $script:discoveryClient|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    $testWindow=[pscustomobject]@{Current=[pscustomobject]@{ProcessId=123;NativeWindowHandle=42}}
    $testWindow|Add-Member ScriptMethod FindAll {param($scope,$condition)$script:discoveryCounts.Generic++;return @()}
    $automation=[pscustomobject]@{Window=$testWindow;Rounds=0}
    $automation|Add-Member ScriptMethod FindAll {param($scope,$condition)$this.Rounds++;if($this.Rounds-gt1){$script:discoveryAlive=$false;return @()};return @($this.Window)}
    $initializeAutomation={};$ParentProcessId=0;$PollMs=1;$CooldownMs=0;$winCondition='window';$btnCondition='button'
    $ownedDiscovery=$script:discoveryClient
    . ([scriptblock]::Create($tail))
    foreach($kind in @('Browser','Terminal','Generic')){if($script:discoveryCounts[$kind]-ne$case[$kind]){throw "Discovery changed live path: case=$($case.Name) kind=$kind expected=$($case[$kind]) actual=$($script:discoveryCounts[$kind])"}}
    if($ownedDiscovery.Reads-ne1-or-not$ownedDiscovery.Disposed){throw 'Discovery lifecycle skipped read or cleanup'}
    $checks++;Write-Output ('PASS cached discovery live path: '+$case.Name)
}
Write-Output "___SCANNER_DISCOVERY_TEST_DONE___:passed=$checks"
