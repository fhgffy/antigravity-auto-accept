// 2026-10-22：保留原Node同步启动边界，控制源只等待，不能当作生产SelfTest通过证据。
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
test('owned lifecycle observer exact-source control', () => {
  const source = path.join(__dirname, 'lifecycle-observer-wait.ps1').replace(/'/g, "''");
  const command = "$ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); & ([scriptblock]::Create([IO.File]::ReadAllText('"+source+"',[Text.Encoding]::UTF8))) -SelfTest";
  const args = ['-NoProfile','-NonInteractive','-OutputFormat','Text','-ExecutionPolicy','Bypass','-EncodedCommand',Buffer.from(command,'utf16le').toString('base64')];
  const result = spawnSync('powershell.exe', args, {windowsHide:true,encoding:'utf8',timeout:25000});
  assert.ifError(result.error);
  assert.equal(result.status,0,result.stderr);
  assert.equal(result.stderr,'');
  assert.match(result.stdout,/OWNED_LIFECYCLE_CONTROL_DONE/);
});
