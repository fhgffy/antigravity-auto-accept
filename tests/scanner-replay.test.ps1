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
# 2026-10-27：保留原十份夹具并冻结新增原生通用批准子集，缺失、替换或增加文件都必须失败。
$fixturePaths=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'fixtures\uia') -Filter '*.json' | Sort-Object Name)
$expectedFixtureNames=@('agent-error-retry.json','browser-narrow.json','browser-wide.json','excluded.json','generic.json','mcp-one-time.json','persistent-allow-excluded.json','read-url-one-time.json','stdin-generic-approval.json','terminal-outside-conversation.json','terminal.json')
if((@($fixturePaths|ForEach-Object{$_.Name})-join',')-cne(@($expectedFixtureNames|Sort-Object)-join',')){throw 'Incomplete eleven-layout replay set'}
$checks=0
$targetChecks=0;$retryChecks=0;$scopeChecks=0;$nativeGenericChecks=0 # 2026-10-27：保留现有数量门，并冻结原生通用批准与权限范围覆盖。
foreach($fixturePath in $fixturePaths){
    $fixture=Get-Content -LiteralPath $fixturePath.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if($fixture.provenance-notin@('native-sanitized','derived-regression')){throw 'Replay provenance missing'}
    # 2026-10-27：此夹具只演示名称规则；冻结正负例数与来源，避免被误记为原生布局或漏测持久项。
    if($fixturePath.Name-ceq'persistent-allow-excluded.json'){
        if($fixture.provenance-cne'derived-regression'-or$null-ne$fixture.card-or$fixture.nodes.Count-ne75-or@($fixture.expected.generic).Count-ne11){throw 'Incomplete persistent permission scope fixture'}
        $scopeChecks=$fixture.nodes.Count
    }
    $script:replayNodes=@{}
    foreach($row in $fixture.nodes){
        if($script:replayNodes.ContainsKey($row.key)){throw 'Duplicate replay node'}
        # 2026-10-26：补齐真实目标复验需要的两个 UIA 查询接口，值与身份都来自脱敏图。
        $node=[pscustomobject]@{Key=[string]$row.key;ParentKey=[string]$row.parent;RuntimeId=[int[]]@($row.runtimeId);Value=$row.value;Current=[pscustomobject]@{Name=$row.name;AutomationId=$row.automationId;ControlType=[Windows.Automation.ControlType]::($row.type);IsEnabled=$row.enabled;IsOffscreen=$row.offscreen}}
        $node|Add-Member ScriptMethod FindAll {param($scope,$condition) return @(Get-ReplayDescendants $this.Key $scope $condition)}
        $node|Add-Member ScriptMethod GetRuntimeId {return $this.RuntimeId}
        $node|Add-Member ScriptMethod GetCurrentPattern {param($pattern) if($pattern-ne[Windows.Automation.ValuePattern]::Pattern){throw 'Unsupported replay pattern'};return [pscustomobject]@{Current=[pscustomobject]@{Value=$this.Value}}}
        $script:replayNodes[$row.key]=$node
    }
    foreach($node in $script:replayNodes.Values){if($node.ParentKey-and-not$script:replayNodes.ContainsKey($node.ParentKey)){throw 'Missing replay parent'}}
    $card=if($fixture.card){$script:replayNodes[[string]$fixture.card]}else{$null}
    $terminal=$null-ne$card-and(Test-LiveApprovalCard $card)
    $browser=($null-ne$card)-and(Test-ReplayConversation $card)-and(Test-LiveBrowserPermissionCard $card)
    $generic=@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::Button-and$_.Current.IsEnabled-and-not$_.Current.IsOffscreen-and(Test-ButtonMatch $_.Current.Name)}|ForEach-Object{$_.Key}|Sort-Object)
    if($terminal-ne$fixture.expected.terminal-or$browser-ne$fixture.expected.browser-or($generic-join',')-cne(@($fixture.expected.generic|Sort-Object)-join',')){throw ('Original live decision differs from literal fixture expectation: '+$fixturePath.Name+' terminal='+$terminal+' browser='+$browser+' generic='+($generic-join','))}
    # 2026-10-27：真实 Sending input to 卡片走通用 Accept；保留 Reject，并明确不能当作旧 stdin 专用形状。
    if($fixturePath.Name-ceq'stdin-generic-approval.json'){
        if($fixture.provenance-cne'native-sanitized'-or$fixture.approvalPath-cne'generic-accept'-or$fixture.nodes.Count-ne22-or$terminal-or$browser-or$generic.Count-ne1-or$script:replayNodes[$generic[0]].Current.Name-cne'Accept'){throw 'Native stdin generic approval changed'}
        foreach($name in @('Sending input to','Task: Bounded stdin test','Approve?','Reject','Accept','Waiting for user input')){
            if(@($fixture.nodes|Where-Object{$_.name-ceq$name}).Count-ne1){throw ('Native stdin approval label changed: '+$name)}
        }
        $nativeGenericChecks++;Write-Output 'PASS native stdin generic Accept approval and Reject exclusion'
    }
    # 2026-10-26：复用生产动作前复验；完整卡片不变时，目标值或控件身份变化都应拒绝旧批准。
    if($fixturePath.Name-in@('mcp-one-time.json','read-url-one-time.json')){
        $targetKind=if($fixturePath.Name-ceq'mcp-one-time.json'){'MCP'}else{'Read URL'}
        $expectedTarget=@{Id=[string]$fixture.expectedTarget.id;Value=[string]$fixture.expectedTarget.value}
        $target=$script:replayNodes[[string]$fixture.expectedTarget.key]
        if(-not(Test-LiveApprovalCard $card $expectedTarget)){throw ($targetKind+' approval rejected original target')}
        $targetChecks++
        $originalValue=$target.Value
        try{$target.Value=if($targetKind-ceq'MCP'){'compiler-fs/other_tool'}else{'127.0.0.2'};if(Test-LiveApprovalCard $card $expectedTarget){throw ($targetKind+' approval accepted changed target value')}}finally{$target.Value=$originalValue}
        $targetChecks++
        $originalRuntimeId=$target.RuntimeId
        try{$target.RuntimeId=[int[]]@(42,2147483647);if(Test-LiveApprovalCard $card $expectedTarget){throw ($targetKind+' approval accepted changed target RuntimeId')}}finally{$target.RuntimeId=$originalRuntimeId}
        $targetChecks++
        Write-Output ('PASS '+$targetKind+' target revalidation: original, changed value, changed RuntimeId')
    }
    # 2026-10-26：保留原生 Retry 的屏外状态，另直接调用名称判定，避免靠不可见性掩盖误匹配。
    if($fixturePath.Name-ceq'agent-error-retry.json'){
        $retry=@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::Button-and$_.Current.Name-ceq'Retry'})
        if($retry.Count-ne1-or-not$retry[0].Current.IsOffscreen){throw 'Native Retry fixture visibility changed'}
        if(Test-ButtonMatch $retry[0].Current.Name){throw 'Native Retry name matched an approval'}
        $retryChecks++;Write-Output 'PASS native Retry name exclusion independent of visibility'
    }
    $snapshot=[pscustomobject]@{ButtonNames=[string[]]@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::Button}|ForEach-Object{$_.Current.Name});HasRadio=@($script:replayNodes.Values|Where-Object{$_.Current.ControlType-eq[Windows.Automation.ControlType]::RadioButton}).Count-gt0}
    $flags=Get-DiscoveryFlags $snapshot
    if(($terminal-and-not$flags.Terminal)-or($browser-and-not$flags.Browser)-or($generic.Count-gt0-and-not$flags.Generic)){throw ('Discovery dropped a live candidate: '+$fixturePath.Name)}
    $checks++;Write-Output ('PASS UIA decision replay: '+$fixturePath.BaseName+' provenance='+$fixture.provenance)
}
if($checks-ne11){throw 'Incomplete eleven-layout replay set'}
if($targetChecks-ne6-or$retryChecks-ne1){throw 'Incomplete target and Retry replay checks'} # 2026-10-26：新增行为断言不能因夹具分支遗漏而静默跳过。
# 2026-10-27：单独数量门保证新增的正负名称断言确实执行。
if($scopeChecks-ne75){throw 'Incomplete persistent permission scope replay checks'}
Write-Output ('PASS persistent permission scope names: '+$scopeChecks+' (11 positive, 64 negative)')
# 2026-10-27：新增原生子集必须实际执行通用批准断言，不能只增加夹具文件数。
if($nativeGenericChecks-ne1){throw 'Incomplete native generic approval replay checks'}
Write-Output "___SCANNER_REPLAY_TEST_DONE___:passed=$checks"
