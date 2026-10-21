# 2026-10-22：复现原Node同步编译的15秒边界；只观察本例Node的精确编译子进程，慢于8秒先抓现场，失败仍保留原返回码。
param([ValidateSet(5,7)][int]$ExpectedMajor,[ValidateRange(1,20)][int]$Repetitions=20,[Parameter(Mandatory=$true)][string]$EvidenceDirectory,[string]$CompilerPath='')
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne $ExpectedMajor -or [IntPtr]::Size -ne 8){throw 'Unexpected Node compiler diagnostic caller'}
if([string]::IsNullOrWhiteSpace($CompilerPath)){$CompilerPath=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'}
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
if([IO.Directory]::Exists($EvidenceDirectory)){throw 'Preserve existing compiler evidence'}
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$hostPath=Join-Path $PSScriptRoot 'host-process.test.ps1';$t=$null;$e=$null
$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($hostPath,[Text.Encoding]::UTF8),$hostPath,[ref]$t,[ref]$e)
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-HostTimeoutDump'},$true))
if($e.Count -or $f.Count -ne 1){throw 'Owned dump function boundary missing'}
$a=[Management.Automation.Language.Parser]::ParseInput($f[0].Extent.Text,$hostPath,[ref]$t,[ref]$e)
if($e.Count){throw 'Owned dump function parse failed'}
. ($a.GetScriptBlock())
$nodeScript=Join-Path $EvidenceDirectory 'compiler-probe.cjs'
[IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures\node-compiler-startup-probe.cjs'),$nodeScript,$false)
$nodePath=(Get-Command node.exe -ErrorAction Stop).Source
foreach($iteration in 1..$Repetitions){
    $directory=Join-Path $EvidenceDirectory ('case-'+$iteration+'-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $argsFile=Join-Path $directory 'arguments.json';$resultFile=Join-Path $directory 'result.json';$identityFile=Join-Path $directory 'identity.json'
    $argsRecord=[ordered]@{compiler=$CompilerPath;source=(Join-Path $PSScriptRoot 'fixtures\host-wrapper-output.cs');nodePath=$nodePath;nodeVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($nodePath).ProductVersion}
    [IO.File]::WriteAllText($argsFile,($argsRecord|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$nodePath;$start.Arguments='--test "'+$nodeScript+'"'
    $start.EnvironmentVariables['AAA_COMPILER_ARGUMENTS']=$argsFile;$start.EnvironmentVariables['AAA_COMPILER_RESULT']=$resultFile;$start.EnvironmentVariables['AAA_COMPILER_IDENTITY']=$identityFile
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $node=[Diagnostics.Process]::new();$node.StartInfo=$start;$compiler=$null;$started=$false;$observed=$false;$cleanupErrors=@()
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        if(-not $node.Start()){throw 'Owned Node did not start'}
        $started=$true;$out=$node.StandardOutput.ReadToEndAsync();$err=$node.StandardError.ReadToEndAsync()
        while(-not $node.get_HasExited()){
            if($clock.ElapsedMilliseconds -gt 23000){throw 'Owned Node exit deadline expired after original compiler timeout'}
            if(-not $observed -and [IO.File]::Exists($identityFile)){
                $identity=[IO.File]::ReadAllText($identityFile,[Text.Encoding]::UTF8)|ConvertFrom-Json
                $worker=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$identity.workerPid)
                if($null -eq $worker){[Threading.Thread]::Sleep(100);continue}
                if($worker.ParentProcessId -ne $node.Id -or $identity.parentPid -ne $node.Id -or $worker.ExecutablePath -ine $nodePath){throw 'Owned test worker identity changed'}
                $outputExe=[string]$identity.fixture
                $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+[int]$identity.workerPid))
                $matches=@($children|Where-Object{$_.ExecutablePath -ieq $CompilerPath -and ([string]$_.CommandLine).IndexOf($outputExe,[StringComparison]::OrdinalIgnoreCase) -ge 0})
                if($matches.Count -gt 1){throw 'Owned compiler identity ambiguous'}
                if($matches.Count -eq 1 -and ([DateTime]::UtcNow-$matches[0].CreationDate.ToUniversalTime()).TotalMilliseconds -ge 8000){
                    $compiler=[Diagnostics.Process]::GetProcessById([int]$matches[0].ProcessId)
                    [void]$compiler.Handle
                    $fresh=Get-CimInstance Win32_Process -Filter ('ProcessId='+$compiler.Id)
                    if($null -eq $fresh -or $fresh.ParentProcessId -ne $identity.workerPid -or $fresh.ExecutablePath -ine $CompilerPath -or $fresh.CreationDate -ne $matches[0].CreationDate){throw 'Owned compiler identity changed'}
                    $observed=$true
                    [IO.File]::WriteAllText((Join-Path $directory 'slow-compiler.json'),([ordered]@{Pid=$compiler.Id;ParentPid=$identity.workerPid;NodeRootPid=$node.Id;Image=$CompilerPath;CreationDate=$fresh.CreationDate.ToUniversalTime().ToString('o');StartTicks=$compiler.StartTime.ToUniversalTime().Ticks;ElapsedBeforeDumpMs=$clock.ElapsedMilliseconds}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
                    Save-HostTimeoutDump $compiler $CompilerPath (Join-Path $directory 'slow-compiler.dmp')
                }
            }
            [Threading.Thread]::Sleep(100)
        }
        if(-not $node.WaitForExit(1000) -or -not $out.Wait(1000) -or -not $err.Wait(1000)){throw 'Owned Node streams incomplete'}
        [IO.File]::WriteAllText((Join-Path $directory 'node.stdout'),$out.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $directory 'node.stderr'),$err.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        if(-not [IO.File]::Exists($resultFile)){throw 'Owned Node result missing'}
        $result=[IO.File]::ReadAllText($resultFile,[Text.Encoding]::UTF8)|ConvertFrom-Json
        Write-Output ('NODE_COMPILER_DIAGNOSTIC:'+($result|ConvertTo-Json -Compress))
        if($node.ExitCode -ne 0 -or $null -ne $result.error -or $result.status -ne 0){throw ('Original compiler invocation failed: '+$resultFile)}
    }finally{
        # 2026-10-22：回收旁证不覆盖原编译失败；正常路径仍须将无法确认退出作为失败。
        $cleanup=[ordered]@{NodePid=$(if($started){$node.Id}else{$null});NodeExited=$false;CompilerPid=$null;CompilerExited=$null;Errors=@()}
        if($null -ne $compiler){
            $cleanup.CompilerPid=$compiler.Id
            try{if(-not $compiler.get_HasExited()){$compiler.Kill()};$cleanup.CompilerExited=$compiler.WaitForExit(2000);if(-not $cleanup.CompilerExited){throw 'Owned compiler exit unconfirmed'}}catch{$cleanupErrors+='compiler:'+ $_.Exception.GetType().FullName}
            try{$compiler.Dispose()}catch{$cleanupErrors+='compiler-dispose:'+ $_.Exception.GetType().FullName}
        }
        if($started){try{if(-not $node.get_HasExited()){$node.Kill()};$cleanup.NodeExited=$node.WaitForExit(2000);if(-not $cleanup.NodeExited){throw 'Owned Node exit unconfirmed'}}catch{$cleanupErrors+='node:'+ $_.Exception.GetType().FullName}}
        try{$node.Dispose()}catch{$cleanupErrors+='node-dispose:'+ $_.Exception.GetType().FullName}
        $cleanup.Errors=$cleanupErrors
        try{[IO.File]::WriteAllText((Join-Path $directory 'cleanup.json'),($cleanup|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))}catch{[Console]::WriteLine('NODE_COMPILER_CLEANUP_DIAGNOSTIC_FAILED:'+ $_.Exception.GetType().FullName);$cleanupErrors+='receipt:'+ $_.Exception.GetType().FullName}
    }
    if($cleanupErrors.Count){throw 'Owned compiler diagnostic cleanup failed'}
}
