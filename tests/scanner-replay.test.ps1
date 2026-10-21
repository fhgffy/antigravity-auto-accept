# 2026-10-21：回放脱敏原生卡片及明确标注的结构变体，原实时形状判定必须与缓存预筛后的候选逐项一致；不执行桌面动作。
param([string]$ScannerSourcePath='')
$ErrorActionPreference='Stop'
$scannerPath=if($ScannerSourcePath){[IO.Path]::GetFullPath($ScannerSourcePath)}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\src\autoClicker.ps1'))}
$source=[IO.File]::ReadAllText($scannerPath,[Text.Encoding]::UTF8)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Replay scanner parse failed'}
foreach($name in @('targetPrefixes','excludeExact','exactOnly')){
    $assignment=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst]-and$n.Left -is [Management.Automation.Language.VariableExpressionAst]-and$n.Left.VariablePath.UserPath-ceq$name},$true))
    if($assignment.Count-ne1){throw 'Replay matching table missing'}
    . ([scriptblock]::Create($assignment[0].Extent.Text))
}
foreach($name in @('Test-PrefixBoundary','Test-ButtonMatch','Get-DiscoveryFlags','Test-OneTimeApprovalName','Test-ApprovalCardShape','Test-LiveApprovalCard','Test-BrowserPermissionText','Test-BrowserPermissionCardShape','Test-LiveBrowserPermissionCard')){
    $function=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
    if($function.Count-ne1){throw ('Replay function missing: '+$name)}
    . ([scriptblock]::Create($function[0].Extent.Text))
}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$editCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Edit)
$radioCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::RadioButton)
$btnCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Button)
$textCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Text)
# 2026-10-21：仅替换 UIA 查询边界；父链、控件类型和原审批函数均由已落盘图驱动。
function Get-ReplayDescendants($Key,$Scope,$Condition){
    foreach($entry in $script:replayNodes.Values){
        if($entry.Current.ControlType.Id-ne$Condition.Value){continue}
        $parent=$entry.ParentKey
        while($parent){
            if($parent-ceq$Key){$entry;break}
            if($Scope-eq[Windows.Automation.TreeScope]::Children){break}
            $parent=$script:replayNodes[$parent].ParentKey
        }
    }
}
function Test-ReplayConversation($Node){
    while($null-ne$Node){
        if($Node.Current.AutomationId-ceq'conversation'){return $true}
        $Node=if($Node.ParentKey){$script:replayNodes[$Node.ParentKey]}else{$null}
    }
    return $false
}
$checks=0
foreach($fixturePath in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'fixtures\uia') -Filter '*.json' | Sort-Object Name)){
    $fixture=Get-Content -LiteralPath $fixturePath.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if($fixture.provenance-notin@('native-sanitized','derived-regression')){throw 'Replay provenance missing'}
    $script:replayNodes=@{}
    foreach($row in $fixture.nodes){
        if($script:replayNodes.ContainsKey($row.key)){throw 'Duplicate replay node'}
        $node=[pscustomobject]@{Key=[string]$row.key;ParentKey=[string]$row.parent;Current=[pscustomobject]@{Name=$row.name;AutomationId=$row.automationId;ControlType=[Windows.Automation.ControlType]::($row.type);IsEnabled=$row.enabled;IsOffscreen=$row.offscreen}}
        $node|Add-Member ScriptMethod FindAll {param($scope,$condition) return @(Get-ReplayDescendants $this.Key $scope $condition)}
        $script:replayNodes[$row.key]=$node
    }
    foreach($node in $script:replayNodes.Values){if($node.ParentKey-and-not$script:replayNodes.ContainsKey($node.ParentKey)){throw 'Missing replay parent'}}
    $card=if($fixture.card){$script:replayNodes[[string]$fixture.card]}else{$null}
    $terminal=$null-ne$card-and(Test-LiveApprovalCard $card)
    $browser=($null-ne$card)-and(Test-ReplayConversation $card)-and(Test-LiveBrowserPermissionCard $card)
    $generic=@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::Button-and$_.Current.IsEnabled-and-not$_.Current.IsOffscreen-and(Test-ButtonMatch $_.Current.Name)}|ForEach-Object{$_.Key}|Sort-Object)
    if($terminal-ne$fixture.expected.terminal-or$browser-ne$fixture.expected.browser-or($generic-join',')-cne(@($fixture.expected.generic|Sort-Object)-join',')){throw ('Original live decision differs from literal fixture expectation: '+$fixturePath.Name+' terminal='+$terminal+' browser='+$browser+' generic='+($generic-join','))}
    $snapshot=[pscustomobject]@{ButtonNames=[string[]]@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::Button}|ForEach-Object{$_.Current.Name});HasRadio=@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::RadioButton}).Count-gt0}
    $flags=Get-DiscoveryFlags $snapshot
    if(($terminal-and-not$flags.Terminal)-or($browser-and-not$flags.Browser)-or($generic.Count-gt0-and-not$flags.Generic)){throw ('Discovery dropped a live candidate: '+$fixturePath.Name)}
    $checks++;Write-Output ('PASS UIA decision replay: '+$fixturePath.BaseName+' provenance='+$fixture.provenance)
}
if($checks-ne6){throw 'Incomplete six-layout replay set'}
Write-Output "___SCANNER_REPLAY_TEST_DONE___:passed=$checks"
