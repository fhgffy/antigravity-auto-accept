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
$expectedFixtureNames=@('agent-error-retry.json','browser-narrow.json','browser-wide.json','excluded.json','generic.json','mcp-one-time.json','scoped-allow-names.json','read-url-one-time.json','stdin-generic-approval.json','terminal-outside-conversation.json','terminal.json')
if((@($fixturePaths|ForEach-Object{$_.Name})-join',')-cne(@($expectedFixtureNames|Sort-Object)-join',')){throw 'Incomplete eleven-layout replay set'}
$checks=0
$targetChecks=0;$retryChecks=0;$scopeChecks=0;$nativeGenericChecks=0 # 2026-10-27：保留现有数量门，并冻结原生通用批准与权限范围覆盖。
foreach($fixturePath in $fixturePaths){
    $fixture=Get-Content -LiteralPath $fixturePath.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if($fixture.provenance-notin@('native-sanitized','derived-regression')){throw 'Replay provenance missing'}
    # 2026-10-27：此夹具只演示名称规则；冻结正负例数与来源，避免被误记为原生布局，也防止范围类 Allow 再被改成人工决定。
    if($fixturePath.Name-ceq'scoped-allow-names.json'){
        if($fixture.provenance-cne'derived-regression'-or$null-ne$fixture.card-or$fixture.nodes.Count-ne75-or@($fixture.expected.generic).Count-ne65){throw 'Incomplete scoped Allow name fixture'}
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
if($scopeChecks-ne75){throw 'Incomplete scoped Allow name replay checks'}
Write-Output ('PASS scoped Allow names: '+$scopeChecks+' (65 positive, 10 negative)')
# 2026-10-27：新增原生子集必须实际执行通用批准断言，不能只增加夹具文件数。
if($nativeGenericChecks-ne1){throw 'Incomplete native generic approval replay checks'}
# 2026-10-31：IDE 2.6.0 的持久范围过滤可只留下本次和拒绝；以下为实际渲染源码导出的规则回归，不计作原生审批成功。
$filteredPermissionCases=@(
    @{Label='once and denial only';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 No (tell the agent what to do instead)');Submit=@('Skip','Submit ↵');Expected=$true},
    @{Label='unnumbered once and denial';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('Yes, allow this time','No');Submit=@('Submit');Expected=$true},
    @{Label='conversation URL scope only';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-2','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 Yes, allow http://localhost:52968 in this conversation','3 No');Submit=@('Submit ↵');Expected=$true},
    @{Label='Chinese once and denial';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 是，仅本次允许','2 不允许');Submit=@('提交');Expected=$true},
    @{Label='ordinary question';Edits=@('Other question');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 No');Submit=@('Submit');Expected=$false},
    @{Label='missing denial';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-2');Names=@('1 Yes, allow this time','2 Yes, and always allow');Submit=@('Submit');Expected=$false},
    @{Label='missing once';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, and always allow','2 No');Submit=@('Submit');Expected=$false},
    @{Label='mixed questions';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-R-__write_in__');Names=@('1 Yes, allow this time','2 No');Submit=@('Submit');Expected=$false},
    @{Label='unknown third option';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-2','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 Other','3 No');Submit=@('Submit');Expected=$false},
    @{Label='unrelated conversation choice';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-2','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 Discuss in this conversation','3 No');Submit=@('Submit');Expected=$false},
    @{Label='duplicate target';Edits=@('Edit permission target','Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 No');Submit=@('Submit');Expected=$false},
    @{Label='missing submit';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 No');Submit=@('Save');Expected=$false},
    @{Label='duplicate submit';Edits=@('Edit permission target');Ids=@('ask-opt-Q-1','ask-opt-Q-__write_in__');Names=@('1 Yes, allow this time','2 No');Submit=@('Submit','Submit ↵');Expected=$false}
)
if($filteredPermissionCases.Count-ne13){throw 'Incomplete filtered permission card coverage'} # 2026-10-31：冻结新增正负例数量。
foreach($case in $filteredPermissionCases){
    $actual=Test-ApprovalCardShape $case.Edits $case.Ids $case.Names $case.Submit
    if($actual-ne$case.Expected){throw ('Filtered permission card mismatch: '+$case.Label+' expected='+$case.Expected+' actual='+$actual)}
}
Write-Output ('PASS derived filtered permission cards: '+$filteredPermissionCases.Count)
# 2026-10-31：只替代 UIA 查询并运行真实浏览器入口；新版内置 Agent 文档可发现，普通预览及有歧义的根不能进入卡片扫描。
$browserFunction=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Invoke-BrowserPermissionCards'},$true))
if($browserFunction.Count-ne1){throw 'Browser approval entry missing'}
. ([scriptblock]::Create($browserFunction[0].Extent.Text))
function Write-ApprovalDiagnostic{}
function Write-BrowserCandidateDiagnostic{}
$conversationCondition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'conversation')
function New-ScopeTestRoot{
    $root=[pscustomobject]@{Scans=0}
    $root|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-ne[Windows.Automation.ControlType]::Button.Id){throw 'Unexpected candidate query'};$this.Scans++;return @()}
    return $root
}
function New-ScopeTestDocument([string]$Url,$Roots,[string]$FrameId='active-frame'){
    $document=[pscustomobject]@{Current=[pscustomobject]@{AutomationId='RootWebArea'};Url=$Url;Roots=@($Roots)}
    $document|Add-Member ScriptMethod GetCurrentPattern {param($pattern) if($pattern-ne[Windows.Automation.ValuePattern]::Pattern){throw 'Unexpected document pattern'};return [pscustomobject]@{Current=[pscustomobject]@{Value=$this.Url}}}
    $document|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-cne'root'){throw 'Unexpected root query'};return $this.Roots}
    $frame=[pscustomobject]@{Current=[pscustomobject]@{AutomationId=$FrameId};Documents=@($document)}
    $frame|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-ne[Windows.Automation.ControlType]::Document.Id){throw 'Unexpected frame query'};return $this.Documents}
    return $frame
}
$scopeCases=@('legacy','native-agent','localhost-agent','ordinary-root','other-frame','remote-host','https-host','missing-extension-view','wrong-extension','duplicate-root','duplicate-agent-document','unavailable-document','missing-root')
foreach($mode in $scopeCases){
    $root=New-ScopeTestRoot;$otherRoot=New-ScopeTestRoot
    $url='http://127.0.0.1:52968/?extensionView=true&extensionVariant=vs-code&platform=electron'
    if($mode-eq'localhost-agent'){$url='http://localhost:52968/?platform=electron&extensionVariant=vs-code&extensionView=true'}
    if($mode-eq'remote-host'){$url='http://example.com:52968/?extensionView=true&extensionVariant=vs-code'}
    if($mode-eq'https-host'){$url='https://127.0.0.1:52968/?extensionView=true&extensionVariant=vs-code'}
    if($mode-eq'missing-extension-view'){$url='http://127.0.0.1:52968/?extensionVariant=vs-code'}
    if($mode-eq'wrong-extension'){$url='http://127.0.0.1:52968/?extensionView=true&extensionVariant=other'}
    $frameId=if($mode-eq'other-frame'){'preview-frame'}else{'active-frame'}
    $roots=if($mode-eq'duplicate-root'){@($root,$otherRoot)}elseif($mode-eq'missing-root'){@()}else{@($root)}
    $frames=@(New-ScopeTestDocument $url $roots $frameId)
    if($mode-eq'duplicate-agent-document'){$frames+=New-ScopeTestDocument $url @($otherRoot)}
    if($mode-eq'ordinary-root'){$frames=@()}
    if($mode-eq'unavailable-document'){$frames[0].Documents[0]|Add-Member ScriptMethod GetCurrentPattern {throw 'Document value unavailable'} -Force}
    $window=[pscustomobject]@{Frames=$frames;Legacy=if($mode-eq'legacy'){$root}else{$null};Current=[pscustomobject]@{ProcessId=123;NativeWindowHandle=42}}
    $window|Add-Member ScriptMethod FindFirst {param($scope,$condition) if($condition.Value-cne'conversation'){throw 'Unexpected legacy scope query'};return $this.Legacy}
    $window|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-ne[Windows.Automation.ControlType]::Document.Id){throw 'Unexpected window query'};return $this.Frames}
    $actual=Invoke-BrowserPermissionCards $window 123 ([IntPtr]42)
    $expectedScans=if($mode-in@('legacy','native-agent','localhost-agent')){1}else{0}
    if($actual-or$root.Scans-ne$expectedScans-or$otherRoot.Scans-ne0){throw ('Browser scope discovery mismatch: '+$mode+' expected='+$expectedScans+' actual='+$root.Scans)}
}
if($scopeCases.Count-ne13){throw 'Incomplete browser scope discovery coverage'}
Write-Output ('PASS derived browser scope discovery: '+$scopeCases.Count)
# 2026-11-10：查询参数必须与内置后端的大小写及唯一性约束一致；冲突参数不能把其它页面带入 Agent 扫描。
$queryScopeCases=@(
    @{Label='conflicting extension view first false';Query='extensionView=false&extensionView=true&extensionVariant=vs-code';Scans=0},
    @{Label='conflicting extension variant first other';Query='extensionView=true&extensionVariant=other&extensionVariant=vs-code';Scans=0},
    @{Label='duplicate extension view first true';Query='extensionView=true&extensionView=false&extensionVariant=vs-code';Scans=0},
    @{Label='duplicate extension variant first native';Query='extensionView=true&extensionVariant=vs-code&extensionVariant=other';Scans=0},
    @{Label='case changed extension view value';Query='extensionView=TRUE&extensionVariant=vs-code';Scans=0},
    @{Label='case changed extension view key';Query='ExtensionView=true&extensionVariant=vs-code';Scans=0},
    @{Label='case changed extension variant value';Query='extensionView=true&extensionVariant=VS-CODE';Scans=0},
    @{Label='case changed extension variant key';Query='extensionView=true&ExtensionVariant=vs-code';Scans=0},
    @{Label='bare extension view before assigned value';Query='extensionView&extensionView=true&extensionVariant=vs-code';Scans=0},
    @{Label='bare extension variant before assigned value';Query='extensionView=true&extensionVariant&extensionVariant=vs-code';Scans=0},
    @{Label='canonical parameters with extra fields';Query='platform=electron&extensionVariant=vs-code&extensionView=true&hostTheme=dark';Scans=1}
)
foreach($case in $queryScopeCases){
    $root=New-ScopeTestRoot
    $window=[pscustomobject]@{Frames=@(New-ScopeTestDocument ('http://127.0.0.1:52968/?'+$case.Query) @($root));Legacy=$null;Current=[pscustomobject]@{ProcessId=123;NativeWindowHandle=42}}
    $window|Add-Member ScriptMethod FindFirst {param($scope,$condition) if($condition.Value-cne'conversation'){throw 'Unexpected legacy scope query'};return $this.Legacy}
    $window|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-ne[Windows.Automation.ControlType]::Document.Id){throw 'Unexpected window query'};return $this.Frames}
    $actual=Invoke-BrowserPermissionCards $window 123 ([IntPtr]42)
    if($actual-or$root.Scans-ne$case.Scans){throw ('Browser query scope mismatch: '+$case.Label+' expected='+$case.Scans+' actual='+$root.Scans)}
}
if($queryScopeCases.Count-ne11){throw 'Incomplete browser query scope coverage'}
Write-Output ('PASS derived browser query scope: '+$queryScopeCases.Count)
# 2026-11-11：恢复后的原生内置文档使用 /c/会话 UUID；只增加该精确路由，不放行设置或普通预览。
$pathScopeCases=@(
    @{Label='native restored conversation';Path='/c/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ac';Scans=1},
    @{Label='agent home';Path='/';Scans=1},
    @{Label='settings document';Path='/settings-standalone';Scans=0},
    @{Label='ordinary preview';Path='/preview';Scans=0},
    @{Label='unknown route';Path='/other/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ac';Scans=0},
    @{Label='wrong route case';Path='/C/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ac';Scans=0},
    @{Label='missing conversation';Path='/c/';Scans=0},
    @{Label='invalid UUID';Path='/c/not-a-conversation';Scans=0},
    @{Label='invalid UUID character';Path='/c/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ag';Scans=0},
    @{Label='conversation child route';Path='/c/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ac/preview';Scans=0}
)
foreach($case in $pathScopeCases){
    $root=New-ScopeTestRoot
    $window=[pscustomobject]@{Frames=@(New-ScopeTestDocument ('http://127.0.0.1:52968'+$case.Path+'?extensionView=true&extensionVariant=vs-code') @($root));Legacy=$null;Current=[pscustomobject]@{ProcessId=123;NativeWindowHandle=42}}
    $window|Add-Member ScriptMethod FindFirst {param($scope,$condition) if($condition.Value-cne'conversation'){throw 'Unexpected legacy scope query'};return $this.Legacy}
    $window|Add-Member ScriptMethod FindAll {param($scope,$condition) if($condition.Value-ne[Windows.Automation.ControlType]::Document.Id){throw 'Unexpected window query'};return $this.Frames}
    $actual=Invoke-BrowserPermissionCards $window 123 ([IntPtr]42)
    if($actual-or$root.Scans-ne$case.Scans){throw ('Browser path scope mismatch: '+$case.Label+' expected='+$case.Scans+' actual='+$root.Scans)}
}
if($pathScopeCases.Count-ne10){throw 'Incomplete browser path scope coverage'}
Write-Output ('PASS derived browser path scope: '+$pathScopeCases.Count)
Write-Output "___SCANNER_REPLAY_TEST_DONE___:passed=$checks"
