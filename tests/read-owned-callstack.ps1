# 2026-10-22：仅对观察者已核对父链的自有PowerShell读取脚本栈；本进程可被外层五秒回收，绝不停止目标。
param([int]$TargetPid,[string]$StartTicks,[string]$ExpectedImage,[int]$ExpectedParentId,[string]$OutputFile)
$ErrorActionPreference='Stop'
$target=$null;$rs=$null;$ps=$null
$record=[ordered]@{Pid=$TargetPid;StartTicks=$StartTicks;Image=$ExpectedImage;CapturedUtc=[DateTime]::UtcNow.ToString('o');Stacks=$null;Error=''}
try {
 if($TargetPid -le 0 -or $ExpectedParentId -le 0 -or -not [IO.Path]::IsPathRooted($ExpectedImage)){throw 'Invalid owned stack identity'}
 $target=[Diagnostics.Process]::GetProcessById($TargetPid);[void]$target.Handle
 $fresh=Get-CimInstance Win32_Process -Filter ('ProcessId='+$TargetPid)
 if($target.HasExited -or $target.StartTime.ToUniversalTime().Ticks.ToString() -cne $StartTicks -or $target.MainModule.FileName -ine $ExpectedImage -or $null -eq $fresh -or $fresh.ParentProcessId -ne $ExpectedParentId -or $fresh.ExecutablePath -ine $ExpectedImage){throw 'Owned stack target identity changed'}
 $connection=[Management.Automation.Runspaces.NamedPipeConnectionInfo]::new($TargetPid,'',1000)
 $connection.SetSessionOptions((New-PSSessionOption -OpenTimeout 1000 -OperationTimeout 1000 -CancelTimeout 1000))
 $rs=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($connection);$rs.Open()
 $ps=[PowerShell]::Create();$ps.Runspace=$rs
 # 2026-10-22：目标只用核心CLI XML传回快照，禁止为旁路读栈自动加载JSON模块干扰冷启动现场。
 [void]$ps.AddScript('$PSModuleAutoLoadingPreference=''None''; $list=[Management.Automation.Runspaces.Runspace].GetProperty(''RunspaceList'',[Reflection.BindingFlags]''Static,NonPublic''); if($null -eq $list){throw ''Owned runtime RunspaceList unavailable''}; $snapshot=@(foreach($runspace in $list.GetValue($null)){[pscustomobject]@{Id=$runspace.Id;Name=$runspace.Name;Frames=@(foreach($frame in $runspace.Debugger.GetCallStack()){[pscustomobject]@{FunctionName=$frame.FunctionName;ScriptName=$frame.ScriptName;ScriptLineNumber=$frame.ScriptLineNumber;PositionText=$frame.Position.Text;CommandName=$frame.InvocationInfo.MyCommand.Name}})}}); [Management.Automation.PSSerializer]::Serialize($snapshot,8)')
 $pending=$ps.BeginInvoke();if(-not $pending.AsyncWaitHandle.WaitOne(2000)){throw 'Owned script stack read deadline expired'}
 $result=$ps.EndInvoke($pending);if($ps.HadErrors){throw ($ps.Streams.Error|Out-String)}
 $record.Stacks=@([Management.Automation.PSSerializer]::Deserialize($result -join [Environment]::NewLine)) # 2026-10-22：本地重建同一快照结构。
} catch {$record.Error=$_.Exception.GetBaseException().GetType().FullName+':'+$_.Exception.GetBaseException().Message}
finally {
 if($null -ne $target){$target.Dispose()}
 try{[IO.File]::WriteAllText($OutputFile,($record|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}catch{[Console]::Error.WriteLine($_.Exception.GetBaseException().Message)}
 if($null -ne $ps){$ps.Dispose()};if($null -ne $rs){$rs.Dispose()}
}
if($record.Error){exit 1}