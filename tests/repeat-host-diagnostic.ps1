# 2026-10-22：独立手动诊断每次运行完整原宿主测试；首次失败保留现场并终止，不作完整CI连绿计数。
param([ValidateSet(5,7)][int]$ExpectedMajor,[ValidateSet('powershell.exe','pwsh.exe')][string]$Engine,[ValidateRange(1,20)][int]$Repetitions=20)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne $ExpectedMajor -or [IntPtr]::Size -ne 8){throw 'Unexpected diagnostic caller'}
$path=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'host-process.test.ps1'))
$literal=$path.Replace("'","''")
$command='$ErrorActionPreference=''Stop''; $p='''+$literal+'''; $t=$null; $e=$null; $a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8),$p,[ref]$t,[ref]$e); if($e.Count){throw ''Host diagnostic parse errors''}; & $a.GetScriptBlock() -PowerShellEngines @('''+$Engine+''')'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
foreach($iteration in 1..$Repetitions){
    Write-Output "HOST_STARTUP_DIAGNOSTIC:$iteration/$Repetitions"
    & $Engine -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encoded
    if($LASTEXITCODE -ne 0){throw "Host startup diagnostic failed: iteration=$iteration exit=$LASTEXITCODE"}
}
