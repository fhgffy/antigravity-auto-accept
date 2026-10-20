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
const selfTestFiles = []; // 2026-10-21：登记自测管道夹具与身份回执，保持白名单非递归清理。
const selfTestDirectories = []; // 2026-10-21：失败回执的目录替身单独登记，不能用文件删除误清目录。
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
    for (const file of [...pidFiles, ...selfTestFiles, fixture]) { if (fs.existsSync(file)) fs.unlinkSync(file); }
    for (const directory of selfTestDirectories) fs.rmdirSync(directory); // 2026-10-21：只移除本文件创建的空目录。
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

// 2026-10-21：只回收本用例登记的真实子进程；创建时间、路径及独立父 PID 均匹配后才能停止。
function stopOwnedSelfTest(pidFile, parentPid) {
    if (!fs.existsSync(pidFile)) return;
    assert.ok(Number.isSafeInteger(parentPid) && parentPid > 0, 'owned parent PID');
    const command = "$ErrorActionPreference='Stop'; $record=Get-Content -LiteralPath $env:AAA_SELFTEST_PIDFILE -Raw|ConvertFrom-Json; "
        + "$child=Get-Process -Id ([int]$record.Pid) -ErrorAction SilentlyContinue; if($null -eq $child){exit 0}; try { "
        + "if($child.StartTime.ToUniversalTime().Ticks.ToString() -cne $record.StartTicks -or "
        + "-not [String]::Equals($child.MainModule.FileName,$record.Path,[StringComparison]::OrdinalIgnoreCase) -or "
        + "(Get-CimInstance Win32_Process -Filter ('ProcessId='+$record.Pid)).ParentProcessId -ne [int]$env:AAA_SELFTEST_PARENT_PID){throw 'Owned SelfTest identity mismatch'}; "
        + "$child.Kill(); if(-not $child.WaitForExit(5000)){throw 'Owned SelfTest exit unconfirmed'} "
        + "} finally {$child.Dispose()}";
    const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text',
        '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
        encoding: 'utf8', windowsHide: true, timeout: 10000,
        env: { ...process.env, AAA_SELFTEST_PIDFILE: pidFile, AAA_SELFTEST_PARENT_PID: String(parentPid) }
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
}

for (const [index, engine] of engines.entries()) {
    for (const mode of ['stdout', 'stderr', 'exit', 'missing-done', 'timeout', 'ledger-failure']) {
        test(`${engine}: scanner SelfTest wrapper ${mode}`, () => {
            const pidFile = path.join(owned, `selftest-${index}-${mode}.json`);
            const scriptFile = path.join(owned, `selftest-${index}-${mode}.ps1`);
            const fallbackPidFile = path.join(owned, `selftest-${index}-${mode}-fallback.pid`);
            selfTestFiles.push(scriptFile);
            if (mode === 'ledger-failure') {
                fs.mkdirSync(pidFile);
                selfTestDirectories.push(pidFile);
                pidFiles.push(fallbackPidFile);
            } else { selfTestFiles.push(pidFile); }
            const bodies = {
                stdout: "[Console]::Out.WriteLine(('x'*131072)); [Console]::Out.WriteLine('___SELFTEST_DONE___:passed=95')",
                stderr: "[Console]::Error.WriteLine(('e'*131072)); [Console]::Error.WriteLine('SCANNER_WRAPPER_STDERR:tail'); [Console]::Out.WriteLine('___SELFTEST_DONE___:passed=95')",
                exit: "[Console]::Out.WriteLine('___SELFTEST_DONE___:passed=95'); exit 7",
                'missing-done': "[Console]::Out.WriteLine(('x'*131072))",
                timeout: "[Console]::Out.WriteLine('SCANNER_WRAPPER_STDOUT:before-stall'); [Console]::Out.WriteLine('___SELFTEST_DONE___:passed=95'); [Console]::Error.WriteLine('SCANNER_WRAPPER_STDERR:before-stall'); Start-Sleep -Seconds 60",
                'ledger-failure': "Start-Sleep -Seconds 60"
            };
            fs.writeFileSync(scriptFile, '# 2026-10-21：只控制子自测输出，不调用扫描器或桌面输入。\r\nparam([switch]$SelfTest)\r\n' + bodies[mode] + '\r\n', 'utf8');
            const quote = value => "'" + value.replace(/'/g, "''") + "'";
            // 2026-10-21：抽取真实包装循环；启动函数仅增加身份旁证，等待、读取及判定均使用仓库原实现。
            const command = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); "
                + "$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText("
                + quote(path.join(__dirname, 'scanner.test.ps1')) + ",[Text.Encoding]::UTF8),[ref]$tokens,[ref]$errors); if($errors.Count){throw 'Scanner wrapper parse failed'}; "
                + "$definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Start-TestProcess'},$true)); "
                + "$loop=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.ForEachStatementAst] -and $_.Extent.Text.Contains('SelfTest failed:')}); "
                + "if($definition.Count -ne 1 -or $loop.Count -ne 1){throw 'Exact SelfTest wrapper missing'}; "
                + ". ([scriptblock]::Create($definition[0].Extent.Text.Replace('function Start-TestProcess(', 'function Start-ObservedChild('))); "
                + "function Start-TestProcess($Executable,$Command){$child=Start-ObservedChild $Executable $Command; "
                // 2026-10-21：回执读取/写入失败时调用者尚未取得 Process，观察函数用本地对象有限回收并保留原异常。
                + "try {[IO.File]::WriteAllText($env:AAA_SELFTEST_PIDFILE,([ordered]@{Pid=$child.Id;StartTicks=$child.StartTime.ToUniversalTime().Ticks.ToString();Path=$child.MainModule.FileName}|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); return $child} "
                + "catch {$failure=$_;$cleanup=[ordered]@{Pid=$child.Id;ExitConfirmed=$false;StopError='';DisposeError=''}; "
                + "try {if(-not $child.HasExited){$child.Kill()};$cleanup.ExitConfirmed=$child.WaitForExit(5000)} catch {$cleanup.StopError=$_.Exception.GetType().FullName}; "
                + "try {$child.Dispose()} catch {$cleanup.DisposeError=$_.Exception.GetType().FullName}; "
                + "try {[Console]::WriteLine('___SCANNER_SELFTEST_OBSERVER_CLEANUP___:'+($cleanup|ConvertTo-Json -Compress))} catch {};throw $failure}}; "
                + "$engines=@((Get-Command " + quote(mode === 'ledger-failure' ? fixture : engine) + ").Source); $escapedScannerPath=" + quote(scriptFile.replace(/'/g, "''")) + "; "
                + "$ExpectedSelfTestCount=95; $checks=0; $bootstrapEncoding='$ProgressPreference=''SilentlyContinue'';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);'; "
                + "try {. ([scriptblock]::Create($loop[0].Extent.Text))} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 1}";
            const started = Date.now();
            const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass',
                '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
                cwd: root, encoding: 'utf8', windowsHide: true, timeout: 35000, maxBuffer: 2 * 1024 * 1024,
                env: { ...process.env, AAA_SELFTEST_PIDFILE: pidFile, AAA_HOST_WRAPPER_CASE: 'timeout', AAA_HOST_WRAPPER_PIDFILE: fallbackPidFile }
            });
            const elapsed = Date.now() - started;
            // 2026-10-21：回执写入失败发生在调用者取得 Process 之前，观察包装器必须自行确认 child 退出。
            if (mode === 'ledger-failure') {
                try {
                    assert.ifError(result.error);
                    assert.notEqual(result.status, 0, 'ledger failure must remain a failure');
                    assert.ok(result.stderr.includes(pidFile), 'original ledger write error retained');
                    const line = result.stdout.split(/\r?\n/).find(value => value.startsWith('___SCANNER_SELFTEST_OBSERVER_CLEANUP___:'));
                    assert.ok(line, 'failed observer must report owned child cleanup');
                    const detail = JSON.parse(line.slice('___SCANNER_SELFTEST_OBSERVER_CLEANUP___:'.length));
                    assert.equal(detail.ExitConfirmed, true);
                    assert.equal(detail.StopError, '');
                    assert.equal(detail.DisposeError, '');
                    assert.throws(() => process.kill(detail.Pid, 0), { code: 'ESRCH' }, 'observer child exited');
                } catch (error) {
                    // 2026-10-21：旧实现红例缺少回执时，使用独占 EXE 自写 PID 及路径确认回收，不能遗留注入子进程。
                    const deadline = Date.now() + 3000;
                    while (!fs.existsSync(fallbackPidFile) && Date.now() < deadline) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20);
                    try { assert.ok(fs.existsSync(fallbackPidFile), 'owned fallback PID required'); stopOwnedFixture(fallbackPidFile); }
                    catch (cleanupError) { keepArtifacts = true; console.error('Owned observer cleanup failed: ' + cleanupError.message); }
                    throw error;
                }
                return;
            }
            let record;
            try {
                assert.ifError(result.error);
                record = JSON.parse(fs.readFileSync(pidFile, 'utf8'));
                assert.ok(Number.isSafeInteger(record.Pid) && record.Pid > 0);
                assert.throws(() => process.kill(record.Pid, 0), { code: 'ESRCH' }, 'owned SelfTest child exited');
            } catch (error) {
                try { stopOwnedSelfTest(pidFile, result.pid); }
                catch (cleanupError) { keepArtifacts = true; console.error('Owned SelfTest cleanup failed: ' + cleanupError.message); }
                throw error;
            }
            if (mode === 'stdout') {
                assert.equal(result.status, 0, result.stderr);
                assert.match(result.stdout, /PASS SelfTest 95 cases:/);
                return;
            }
            assert.notEqual(result.status, 0, 'invalid or stalled SelfTest must fail');
            assert.doesNotMatch(result.stdout, /PASS SelfTest 95 cases:/);
            if (mode === 'timeout') {
                assert.match(result.stderr, /SelfTest timeout/);
                assert.ok(elapsed >= 14000 && elapsed < 35000, `original 15 second deadline retained: ${elapsed}ms`);
                const line = result.stdout.split(/\r?\n/).find(value => value.startsWith('___SCANNER_SELFTEST_TIMEOUT___:'));
                assert.ok(line, 'timeout must retain both output streams and confirmed exit');
                const detail = JSON.parse(line.slice('___SCANNER_SELFTEST_TIMEOUT___:'.length));
                assert.equal(detail.Pid, record.Pid);
                assert.equal(detail.ExitConfirmed, true);
                assert.equal(detail.StdoutComplete, true);
                assert.equal(detail.StderrComplete, true);
                assert.match(detail.Stdout, /SCANNER_WRAPPER_STDOUT:before-stall/);
                assert.match(detail.Stdout, /___SELFTEST_DONE___:passed=95/);
                assert.match(detail.Stderr, /SCANNER_WRAPPER_STDERR:before-stall/);
                assert.equal(detail.StopError, '');
                assert.equal(detail.ReadError, '');
                assert.equal(detail.DisposeError, '');
            } else {
                assert.match(result.stderr, /SelfTest failed:/);
                if (mode === 'stderr') assert.match(result.stderr, /SCANNER_WRAPPER_STDERR:tail/);
                if (mode === 'exit') assert.match(result.stderr, /exit=7/);
            }
        });
    }
}
