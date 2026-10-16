/* 2026-10-16：让真实宿主包装器管理可控 EXE，验证超时证据、严格失败和自有进程回收。 */
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test, before, after } = require('node:test');

const root = path.resolve(__dirname, '..');
const owned = fs.mkdtempSync(path.join(os.tmpdir(), 'AntigravityAA-HostWrapper-'));
const fixture = path.join(owned, 'host-wrapper-output.exe');
const pidFiles = [];
let keepArtifacts = false; // 2026-10-16：退出无法确认时保留独占夹具与 PID 旁证。
const engines = process.env.HOST_WRAPPER_ENGINE ? [process.env.HOST_WRAPPER_ENGINE] : ['powershell.exe', 'pwsh.exe'];

before(() => {
    const compiler = path.join(process.env.WINDIR, 'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
    const result = spawnSync(compiler, ['/nologo', '/target:exe', '/codepage:65001', '/platform:anycpu', '/out:' + fixture,
        path.join(__dirname, 'fixtures/host-wrapper-output.cs')], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
});

after(() => {
    // 2026-10-16：目录由本文件独占创建，只删除登记文件，外来文件使非递归清理显式失败。
    if (keepArtifacts) { console.error('Owned fixture cleanup unconfirmed; retained: ' + owned); return; }
    for (const file of [...pidFiles, fixture]) { if (fs.existsSync(file)) fs.unlinkSync(file); }
    fs.rmdirSync(owned);
});

// 2026-10-16：外层看门狗失败后，先核对登记 PID 的独占 EXE 路径，再通过同一 Process 对象回收。
function stopOwnedFixture(pidFile) {
    if (!fs.existsSync(pidFile)) return;
    const pid = Number(fs.readFileSync(pidFile, 'utf8'));
    assert.ok(Number.isSafeInteger(pid) && pid > 0, 'valid owned fixture PID');
    const command = "$ErrorActionPreference='Stop'; $ownedProcess=Get-Process -Id ([int]$env:AAA_HOST_WRAPPER_CLEANUP_PID) -ErrorAction SilentlyContinue; "
        + "if($null -eq $ownedProcess){exit 0}; try { if(-not $ownedProcess.HasExited) { "
        + "if(-not [String]::Equals($ownedProcess.MainModule.FileName,$env:AAA_HOST_WRAPPER_CLEANUP_EXE,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned fixture path mismatch'}; "
        + "$ownedProcess.Kill(); if(-not $ownedProcess.WaitForExit(5000)){throw 'Owned fixture exit unconfirmed'} "
        + "} } finally { $ownedProcess.Dispose() }";
    const cleanup = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text',
        '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
        encoding: 'utf8', windowsHide: true, timeout: 10000,
        env: { ...process.env, AAA_HOST_WRAPPER_CLEANUP_PID: String(pid), AAA_HOST_WRAPPER_CLEANUP_EXE: fixture }
    });
    assert.ifError(cleanup.error);
    assert.equal(cleanup.status, 0, cleanup.stderr);
    assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' }, 'failed test fixture exited');
}

for (const [index, engine] of engines.entries()) {
    for (const mode of ['timeout', 'success', 'stderr', 'exit', 'missing-done']) {
        test(`${engine}: host wrapper ${mode}`, () => {
            const pidFile = path.join(owned, `${index}-${mode}.pid`);
            pidFiles.push(pidFile);
            const quote = value => "'" + value.replace(/'/g, "''") + "'";
            const script = path.join(__dirname, 'host-process.test.ps1');
            const command = "$ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); "
                + "$p=" + quote(script) + "; $tokens=$null; $errors=$null; "
                + "$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8),$p,[ref]$tokens,[ref]$errors); "
                + "if($errors.Count){throw 'Host wrapper parse errors'}; & $ast.GetScriptBlock() -PowerShellEngines " + quote(fixture);
            const start = Date.now();
            const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass',
                '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
                cwd: root, encoding: 'utf8', windowsHide: true, timeout: 65000,
                env: { ...process.env, AAA_HOST_WRAPPER_CASE: mode, AAA_HOST_WRAPPER_PIDFILE: pidFile }
            });
            const elapsed = Date.now() - start;
            // 2026-10-16：失败仍按原异常上报；夹具回收另记诊断，不能用清理错误遮盖看门狗失败。
            let pid;
            try {
                assert.ifError(result.error);
                pid = Number(fs.readFileSync(pidFile, 'utf8'));
                assert.ok(Number.isSafeInteger(pid) && pid > 0);
                assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' }, 'owned fixture exited');
            } catch (error) {
                try { stopOwnedFixture(pidFile); }
                catch (cleanupError) { keepArtifacts = true; console.error('Owned fixture cleanup failed: ' + cleanupError.message); }
                throw error;
            }
            if (mode === 'success') {
                assert.equal(result.status, 0, result.stderr);
                assert.match(result.stdout, /PASS host process engine:/);
                assert.match(result.stdout, /HOST_WRAPPER_STDOUT:中文诊断/);
                return;
            }
            assert.notEqual(result.status, 0, 'failed child must fail the wrapper');
            assert.doesNotMatch(result.stdout, /PASS host process engine:/);
            if (mode === 'timeout') {
                assert.match(result.stderr, /Host test timeout:/);
                assert.ok(elapsed >= 44000 && elapsed < 65000, `original timeout preserved: ${elapsed}ms`);
                const diagnosticLine = result.stdout.split(/\r?\n/).find(line => line.startsWith('___HOST_WRAPPER_TIMEOUT___:'));
                assert.ok(diagnosticLine, 'timeout must retain child stdout and stderr diagnostics');
                const diagnostic = JSON.parse(diagnosticLine.slice('___HOST_WRAPPER_TIMEOUT___:'.length));
                assert.equal(diagnostic.Pid, pid);
                assert.equal(diagnostic.ExitConfirmed, true);
                assert.equal(diagnostic.StdoutComplete, true);
                assert.equal(diagnostic.StderrComplete, true);
                assert.match(diagnostic.Stdout, /HOST_WRAPPER_STDOUT:中文诊断/);
                assert.match(diagnostic.Stderr, /HOST_WRAPPER_STDERR:partial-error/);
                assert.equal(diagnostic.StopError, '');
                assert.equal(diagnostic.ReadError, '');
            } else {
                assert.match(result.stderr, /Host test failed:/);
                if (mode === 'stderr') assert.match(result.stderr, /HOST_WRAPPER_STDERR:partial-error/);
                if (mode === 'exit') assert.match(result.stderr, /exit=7/);
            }
        });
    }
}
