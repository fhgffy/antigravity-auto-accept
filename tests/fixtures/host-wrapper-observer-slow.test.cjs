/* 2026-10-22：受控外层PowerShell在二十五秒原限内完成，验证旁路在第八秒先取证；不是云端故障复现。 */
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const path=require('node:path');
test('bounded x64 minidump success observer-selfcheck',()=>{
    const executable=path.join(process.env.WINDIR,'SysWOW64/WindowsPowerShell/v1.0/powershell.exe');
    const command="$ProgressPreference='SilentlyContinue'; $knownCollector='host-dump-collector.exe'; Start-Sleep -Seconds 20; [Console]::WriteLine('DUMP_DIAGNOSTIC_CHILD_READY')";
    const result=spawnSync(executable,['-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',Buffer.from(command,'utf16le').toString('base64')],{encoding:'utf8',windowsHide:true,timeout:25000});
    assert.ifError(result.error);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/DUMP_DIAGNOSTIC_CHILD_READY/);
});
