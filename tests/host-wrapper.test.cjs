/* 2026-10-16：让真实宿主包装器管理可控 EXE，验证超时证据、严格失败和自有进程回收。 */
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test, before, after } = require('node:test');

const root = path.resolve(__dirname, '..');
// 2026-10-21：将 CI 的 RUNNER~1 短名展开为真实路径，使异常与 Process 路径可严格核对。
const owned = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'AntigravityAA-HostWrapper-')));
const fixture = path.join(owned, 'host-wrapper-output.exe');
const diagnosticCollector = path.join(owned, 'host-dump-collector.exe'); // 2026-10-22：取证工具事先按普通EXE编译，不在五秒窗口内加载或编译脚本程序集。
const pidFiles = [];
const selfTestFiles = []; // 2026-10-21：登记自测管道夹具与身份回执，保持白名单非递归清理。
const selfTestDirectories = []; // 2026-10-21：失败回执的目录替身单独登记，不能用文件删除误清目录。
let keepArtifacts = false; // 2026-10-16：退出无法确认时保留独占夹具与 PID 旁证。
const engines = process.env.HOST_WRAPPER_ENGINE ? [process.env.HOST_WRAPPER_ENGINE] : ['powershell.exe', 'pwsh.exe'];

before(() => {
    const compiler = path.join(process.env.WINDIR, 'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
    const result = spawnSync(compiler, ['/nologo', '/target:exe', '/codepage:65001', '/platform:anycpu', '/out:' + fixture,
        path.join(__dirname, 'fixtures/host-wrapper-output.cs')], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
    let diagnosticBuild; // 2026-10-22：分别保留两次编译的原两流与返回字段。
    try {
        assert.ifError(result.error);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        diagnosticBuild = spawnSync(compiler, ['/nologo', '/target:exe', '/codepage:65001', '/platform:x64', '/out:' + diagnosticCollector,
            path.join(__dirname, 'fixtures/host-child-diagnostics.cs'), path.join(__dirname, 'fixtures/host-dump-collector.cs')],
            { encoding: 'utf8', windowsHide: true, timeout: 15000 });
        assert.ifError(diagnosticBuild.error);
        assert.equal(diagnosticBuild.status, 0, diagnosticBuild.stdout + diagnosticBuild.stderr);
    } catch (error) {
        // 2026-10-22：首次编译失败保留原两流与退出字段，不能被后续清理抹掉现场。
        keepArtifacts = true;
        fs.writeFileSync(path.join(owned, 'compiler-failure.json'), JSON.stringify({ status: result.status, signal: result.signal,
            error: result.error ? { code: result.error.code, message: result.error.message } : null, stdout: result.stdout, stderr: result.stderr,
            diagnosticBuild: diagnosticBuild ? { status: diagnosticBuild.status, signal: diagnosticBuild.signal,
                error: diagnosticBuild.error ? { code: diagnosticBuild.error.code, message: diagnosticBuild.error.message } : null,
                stdout: diagnosticBuild.stdout, stderr: diagnosticBuild.stderr } : null }));
        throw error;
    }
});

after(() => {
    // 2026-10-16：目录由本文件独占创建，只删除登记文件，外来文件使非递归清理显式失败。
    if (keepArtifacts) { console.error('Owned fixture cleanup unconfirmed; retained: ' + owned); return; }
    for (const file of [...pidFiles, ...selfTestFiles, fixture, diagnosticCollector]) { if (fs.existsSync(file)) fs.unlinkSync(file); }
    for (const directory of selfTestDirectories) fs.rmdirSync(directory); // 2026-10-21：只移除本文件创建的空目录。
    fs.rmdirSync(owned);
});

// 2026-10-16：外层看门狗失败后，先核对登记 PID 的独占 EXE 路径，再通过同一 Process 对象回收。
function stopOwnedFixture(pidFile, expectedImage = fixture, expectedStartTicks = null) { // 2026-10-22：共享映像必须同时持有创建身份。
    if (!fs.existsSync(pidFile)) return;
    if (expectedImage !== fixture) assert.match(String(expectedStartTicks), /^[1-9][0-9]{0,18}$/, 'Shared process creation identity required'); // 2026-10-22：缺少创建身份不得进入共享进程回收。
    const pid = Number(fs.readFileSync(pidFile, 'utf8'));
    assert.ok(Number.isSafeInteger(pid) && pid > 0, 'valid owned fixture PID');
    const command = "$ErrorActionPreference='Stop'; $ownedProcess=Get-Process -Id ([int]$env:AAA_HOST_WRAPPER_CLEANUP_PID) -ErrorAction SilentlyContinue; "
        + "if($null -eq $ownedProcess){exit 0}; try { [void]$ownedProcess.Handle; if(-not $ownedProcess.HasExited) { "
        + "if(-not [String]::Equals($ownedProcess.MainModule.FileName,$env:AAA_HOST_WRAPPER_CLEANUP_EXE,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned fixture path mismatch'}; "
        + "if($env:AAA_HOST_WRAPPER_CLEANUP_START_TICKS -and $ownedProcess.StartTime.ToUniversalTime().Ticks -ne [long]$env:AAA_HOST_WRAPPER_CLEANUP_START_TICKS){throw 'Owned fixture creation time mismatch'}; "
        + "$ownedProcess.Kill(); if(-not $ownedProcess.WaitForExit(5000)){throw 'Owned fixture exit unconfirmed'} "
        + "} } finally { $ownedProcess.Dispose() }";
    const cleanup = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text',
        '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
        encoding: 'utf8', windowsHide: true, timeout: 10000,
        env: { ...process.env, AAA_HOST_WRAPPER_CLEANUP_PID: String(pid), AAA_HOST_WRAPPER_CLEANUP_EXE: expectedImage, AAA_HOST_WRAPPER_CLEANUP_START_TICKS: expectedStartTicks === null ? '' : String(expectedStartTicks) }
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
        + "-not [String]::Equals($child.MainModule.FileName,$record.ExpectedImage,[StringComparison]::OrdinalIgnoreCase) -or "
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
    // 2026-10-22：回放真实手动循环，证据写入与正文同时失败时仍保留首个自测错误，并在第一轮停止。
    for (const mode of ['body-failure', 'write-failure', 'both-failure']) {
        test(`${engine}: SelfTest iteration evidence ${mode}`, () => {
            const evidencePath = path.join(owned, `iteration-${index}-${mode}`);
            const bodyFails = mode !== 'write-failure';
            const writeFails = mode !== 'body-failure';
            if (writeFails) {
                fs.writeFileSync(evidencePath, 'owned file blocks the directory', 'utf8');
                selfTestFiles.push(evidencePath);
            } else {
                fs.mkdirSync(evidencePath);
                selfTestDirectories.push(evidencePath);
                selfTestFiles.push(path.join(evidencePath, 'case-1.json'));
            }
            const quote = value => "'" + value.replace(/'/g, "''") + "'";
            const command = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $t=$null;$e=$null; "
                + "$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText("
                + quote(path.join(__dirname, 'repeat-scanner-selftest-diagnostic.ps1')) + ",[Text.Encoding]::UTF8),[ref]$t,[ref]$e); "
                + "$loops=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.ForEachStatementAst] -and $_.Extent.Text.Contains('$record.Passed')}); "
                + "if($e.Count -or $loops.Count -ne 1){throw 'Exact diagnostic iteration loop missing'}; $Repetitions=3; $script:bodyCount=0; $EvidenceDirectory="
                + quote(evidencePath) + "; $body={ $script:bodyCount++; "
                + (bodyFails ? "throw [InvalidOperationException]::new('ORIGINAL_SELFTEST_FAILURE')" : "[void]0")
                + " }; try {. ([scriptblock]::Create($loops[0].Extent.Text)); throw 'Iteration unexpectedly succeeded'} catch { "
                + "[Console]::WriteLine('___SELFTEST_ITERATION_RESULT___:'+([ordered]@{Error=$_.Exception.Message;Iterations=$script:bodyCount}|ConvertTo-Json -Compress)) }";
            const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand',
                Buffer.from(command, 'utf16le').toString('base64')], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
            assert.ifError(result.error);
            assert.equal(result.status, 0, result.stderr);
            const line = result.stdout.split(/\r?\n/).find(value => value.startsWith('___SELFTEST_ITERATION_RESULT___:'));
            assert.ok(line, 'diagnostic loop outcome retained');
            const outcome = JSON.parse(line.slice('___SELFTEST_ITERATION_RESULT___:'.length));
            assert.equal(outcome.Iterations, 1, 'first failure must stop repetitions');
            if (bodyFails) assert.equal(outcome.Error, 'ORIGINAL_SELFTEST_FAILURE');
            else assert.doesNotMatch(outcome.Error, /Iteration unexpectedly succeeded|ORIGINAL_SELFTEST_FAILURE/);
            if (writeFails) assert.match(result.stderr, /___SELFTEST_DIAGNOSTIC_WRITE_FAILED___:/);
            else assert.equal(result.stderr, '');
        });
    }
    for (const mode of ['stdout', 'stderr', 'exit', 'missing-done', 'timeout', 'ledger-failure', 'selftest-no-desktop']) {
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
            if (mode === 'selftest-no-desktop') {
                // 2026-10-21：仅替换真实源码的唯一桌面 getter 为失败探针，保留其余完整 SelfTest 路径及95项断言。
                const scanner = fs.readFileSync(path.join(root, 'src/autoClicker.ps1'), 'utf8');
                const desktopGetter = '[System.Windows.Automation.AutomationElement]::RootElement';
                assert.equal(scanner.split(desktopGetter).length, 2, 'exact desktop root getter');
                fs.writeFileSync(scriptFile, scanner.replace(desktopGetter, "$(throw 'SELFTEST_DESKTOP_ACCESS_PROBE')"), 'utf8');
            } else {
                fs.writeFileSync(scriptFile, '# 2026-10-21：只控制子自测输出，不调用扫描器或桌面输入。\r\nparam([switch]$SelfTest)\r\n' + bodies[mode] + '\r\n', 'utf8');
            }
            const quote = value => "'" + value.replace(/'/g, "''") + "'";
            // 2026-10-21：抽取真实包装循环；启动函数仅增加身份旁证，等待、读取及判定均使用仓库原实现。
            const command = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); "
                + "$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText("
                + quote(path.join(__dirname, 'scanner.test.ps1')) + ",[Text.Encoding]::UTF8),[ref]$tokens,[ref]$errors); if($errors.Count){throw 'Scanner wrapper parse failed'}; "
                + "$definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Start-TestProcess'},$true)); "
                + "$loop=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.ForEachStatementAst] -and $_.Extent.Text.Contains('SelfTest failed:')}); "
                + "if($definition.Count -ne 1 -or $loop.Count -ne 1){throw 'Exact SelfTest wrapper missing'}; "
                // 2026-10-22：调用真实超时旁证函数；旧版仍运行原包装循环，再由缺少现场回执产生红灯。
                + "$capture=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-ScannerTimeoutEvidence'},$true)); "
                + "if($capture.Count -eq 1){$captureAst=[Management.Automation.Language.Parser]::ParseInput($capture[0].Extent.Text,"
                + quote(path.join(__dirname, 'scanner.test.ps1')) + ",[ref]$tokens,[ref]$errors); . ([scriptblock]::Create($captureAst.Extent.Text.Replace('function Save-ScannerTimeoutEvidence {','function Save-ObservedTimeoutEvidence {'))); "
                + "$scannerDumpTestRoot=" + quote(__dirname) + "; function Save-ScannerTimeoutEvidence($Target,$ExpectedImage,$SourcePath,$CollectorEngine,[switch]$ExecutableCollector){[Console]::WriteLine('___PREPARED_COLLECTOR_FORWARD___:'+([ordered]@{Engine=$CollectorEngine;Native=$ExecutableCollector.IsPresent}|ConvertTo-Json -Compress)); Save-ObservedTimeoutEvidence $Target $ExpectedImage $SourcePath -UtilityPath (Join-Path $scannerDumpTestRoot 'host-process.test.ps1') -CollectorEngine "
                + quote(diagnosticCollector) + " -ExecutableCollector}}; "
                + ". ([scriptblock]::Create($definition[0].Extent.Text.Replace('function Start-TestProcess(', 'function Start-ObservedChild('))); "
                + "function Start-TestProcess($Executable,$Command){$child=Start-ObservedChild $Executable $Command; "
                // 2026-10-22：模拟进程刚创建时模块列表尚不可用，启动归属不能依赖暂时为空的MainModule。
                + "if($env:AAA_SCANNER_STARTUP_IMAGE_UNAVAILABLE -eq '1'){$child|Add-Member ScriptProperty MainModule {return $null} -Force}; "
                // 2026-10-21：回执读取/写入失败时调用者尚未取得 Process，观察函数用本地对象有限回收并保留原异常。
                + "try {[IO.File]::WriteAllText($env:AAA_SELFTEST_PIDFILE,([ordered]@{Pid=$child.Id;StartTicks=$child.StartTime.ToUniversalTime().Ticks.ToString();ExpectedImage=$Executable}|ConvertTo-Json),[Text.UTF8Encoding]::new($false)); return $child} "
                + "catch {$failure=$_;$cleanup=[ordered]@{Pid=$child.Id;ExitConfirmed=$false;StopError='';DisposeError=''}; "
                + "try {if(-not $child.HasExited){$child.Kill()};$cleanup.ExitConfirmed=$child.WaitForExit(5000)} catch {$cleanup.StopError=$_.Exception.GetType().FullName}; "
                + "try {$child.Dispose()} catch {$cleanup.DisposeError=$_.Exception.GetType().FullName}; "
                + "try {[Console]::WriteLine('___SCANNER_SELFTEST_OBSERVER_CLEANUP___:'+($cleanup|ConvertTo-Json -Compress))} catch {};throw $failure}}; "
                + "$engines=@((Get-Command " + quote(mode === 'ledger-failure' ? fixture : engine) + ").Source); $escapedScannerPath=" + quote(scriptFile.replace(/'/g, "''")) + "; "
                + "$TimeoutCollectorPath=" + quote(diagnosticCollector) + "; "
                + "$ExpectedSelfTestCount=95; $checks=0; $bootstrapEncoding='$ProgressPreference=''SilentlyContinue'';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);'; "
                + "try {. ([scriptblock]::Create($loop[0].Extent.Text))} catch {[Console]::Error.WriteLine($_.Exception.Message);exit 1}";
            const started = Date.now();
            const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass',
                '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
                cwd: root, encoding: 'utf8', windowsHide: true, timeout: 35000, maxBuffer: 2 * 1024 * 1024,
                env: { ...process.env, AAA_SELFTEST_PIDFILE: pidFile, AAA_HOST_WRAPPER_CASE: 'timeout', AAA_HOST_WRAPPER_PIDFILE: fallbackPidFile, AAA_SCANNER_STARTUP_IMAGE_UNAVAILABLE: mode === 'stdout' ? '1' : '0' }
            });
            const elapsed = Date.now() - started;
            // 2026-10-21：回执写入失败发生在调用者取得 Process 之前，观察包装器必须自行确认 child 退出。
            if (mode === 'ledger-failure') {
                try {
                    assert.ifError(result.error);
                    assert.notEqual(result.status, 0, 'ledger failure must remain a failure');
                    // 2026-10-21：远端断言失败必须保留真实子进程两条流，不能只报一个缺少路径的布尔结果。
                    assert.ok(result.stderr.includes(pidFile), 'original ledger write error retained: ' + JSON.stringify({ pidFile, status: result.status, stdout: result.stdout, stderr: result.stderr }));
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
            if (mode === 'stdout' || mode === 'selftest-no-desktop') {
                assert.ok(typeof record.ExpectedImage === 'string' && path.isAbsolute(record.ExpectedImage), 'launch expectation retained even before module enumeration');
                assert.equal(path.basename(record.ExpectedImage).toLowerCase(), path.basename(engine).toLowerCase());
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
                // 2026-10-22：CI事先准备的独立EXE须穿过实际超时入口，失败后不重新启动PowerShell和编译。
                const forwardedLine = result.stdout.split(/\r?\n/).find(value => value.startsWith('___PREPARED_COLLECTOR_FORWARD___:'));
                assert.ok(forwardedLine, 'prepared collector forwarding recorded');
                const forwarded = JSON.parse(forwardedLine.slice('___PREPARED_COLLECTOR_FORWARD___:'.length));
                assert.equal(forwarded.Engine, diagnosticCollector);
                assert.equal(forwarded.Native, true);
                assert.equal(detail.StdoutComplete, true);
                assert.equal(detail.StderrComplete, true);
                // 2026-10-21：真实超时必须保留子进程启动、源码读取与解析阶段，不能只剩空输出。
                for (const phase of ['bootstrap', 'source-read', 'scriptblock-created']) {
                    assert.ok(detail.Stdout.includes('___SCANNER_SELFTEST_PHASE___:' + phase), `missing SelfTest phase: ${phase}`);
                }
                assert.match(detail.Stdout, /SCANNER_WRAPPER_STDOUT:before-stall/);
                assert.match(detail.Stdout, /___SELFTEST_DONE___:passed=95/);
                assert.match(detail.Stderr, /SCANNER_WRAPPER_STDERR:before-stall/);
                assert.equal(detail.StopError, '');
                assert.equal(detail.ReadError, '');
                assert.equal(detail.DisposeError, '');
                // 2026-10-22：成功标记后停滞仍须失败；先保留真实MDMP和身份，再由原持有者确认退出。
                assert.ok(detail.DumpDirectory, 'SelfTest timeout must retain a dump evidence directory');
                const identity = JSON.parse(fs.readFileSync(path.join(detail.DumpDirectory, 'identity.json'), 'utf8'));
                assert.equal(identity.Pid, record.Pid);
                assert.equal(identity.StartTicks, record.StartTicks);
                assert.equal(identity.Image.toLowerCase(), record.ExpectedImage.toLowerCase());
                const dumpFile = path.join(detail.DumpDirectory, 'selftest.dmp');
                assert.equal(fs.readFileSync(dumpFile).subarray(0, 4).toString('ascii'), 'MDMP',
                    JSON.stringify({ status: result.status, stdout: result.stdout, stderr: result.stderr })); // 2026-10-22：真实采集失败保留收集器原两流，不能只剩空头断言。
                assert.equal(fs.readFileSync(path.join(detail.DumpDirectory, 'source.ps1'), 'utf8'), fs.readFileSync(scriptFile, 'utf8'));
                // 2026-10-22：原15秒失败后在停止目标前读出注入等待语句，保留同一PID/创建身份及有界读栈退出。
                const stack = JSON.parse(fs.readFileSync(path.join(detail.DumpDirectory, 'selftest.callstack.json'), 'utf8'));
                assert.equal(stack.Pid, record.Pid);
                assert.equal(stack.StartTicks, record.StartTicks);
                assert.equal(stack.Error, '');
                assert.ok(stack.Stacks.some(runspace => runspace.Name === 'Runspace1' && runspace.Frames.some(frame => frame.PositionText === 'Start-Sleep -Seconds 60')));
                const reader = JSON.parse(fs.readFileSync(path.join(detail.DumpDirectory, 'selftest.reader.json'), 'utf8'));
                assert.equal(reader.TimedOut, false);
                assert.equal(reader.ExitConfirmed, true);
                assert.equal(reader.ExitCode, 0);
                assert.equal(reader.Stderr, '');
                for (const name of ['identity.json', 'source.ps1', 'selftest.dmp', 'selftest.dmp.phases.log', 'streams.json', 'selftest.callstack.json', 'selftest.reader.json']) selfTestFiles.push(path.join(detail.DumpDirectory, name));
                selfTestDirectories.push(detail.DumpDirectory);
            } else {
                assert.match(result.stderr, /SelfTest failed:/);
                if (mode === 'stderr') assert.match(result.stderr, /SCANNER_WRAPPER_STDERR:tail/);
                if (mode === 'exit') assert.match(result.stderr, /exit=7/);
            }
        });
    }
}

// 2026-10-22：各项诊断使用独立目标和原25秒上限，避免三次5秒收集器叠加耗尽同一个外层截止时间。
const diagnosticEngines = [...new Set([...engines, path.join(process.env.WINDIR, 'SysWOW64/WindowsPowerShell/v1.0/powershell.exe')])];
for (const [index, engine] of diagnosticEngines.entries()) {
    for (const scenario of ['success', 'file-error', 'collector-stall', 'identity-error', 'json-unavailable', 'json-error-escaping', 'modules-unavailable']) {
        test(engine + ': bounded x64 minidump ' + scenario + ' retains target', () => {
            const quote = value => "'" + value.replace(/'/g, "''") + "'";
            const stem = 'diagnostic-' + index + '-' + scenario;
            const diagnostic = path.join(owned, stem + '.dmp');
            const pidFile = path.join(owned, stem + '.pid');
            const collectorPidFile = path.join(owned, stem + '-collector.pid');
            pidFiles.push(pidFile);
            if (scenario === 'collector-stall' || scenario === 'json-error-escaping') pidFiles.push(collectorPidFile);
            selfTestFiles.push(diagnostic, diagnostic + '.phases.log', diagnostic + '.collector.dmp', diagnostic + '.collector.dmp.phases.log', diagnostic + '.collector.dmp.context.tsv', diagnostic + '.collector.json'); // 2026-10-22：取证阶段旁证按本例明确文件收尾。
            const preserved = Buffer.from('existing-owned-dump-must-not-change');
            if (scenario === 'file-error') fs.writeFileSync(diagnostic, preserved, { flag: 'wx' });
            const hostPath = path.join(__dirname, 'host-process.test.ps1');
            // 2026-10-22：禁止JSON模块自动加载的真实子进程仍须完成取证回执，避免首次报告加载耗时突破原25秒。
            const noJsonModule = scenario.startsWith('json-');
            const noCommandModules = scenario === 'modules-unavailable'; // 2026-10-22：原生EXE路径不应先冷加载任何命令模块。
            const dumpError = 'DUMP_ERROR:quote=" slash=\\ tab=\t cr=\r lf=\n 中文😀';
            const command = "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::WriteLine('DUMP_DIAGNOSTIC_ENTERED'); "
                + "$hostPath=" + quote(hostPath) + ";$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($hostPath,[Text.Encoding]::UTF8),$hostPath,[ref]$t,[ref]$e);"
                + "$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-HostTimeoutDump'},$true));if($f.Count -ne 1){throw 'Dump function missing'};"
                + "$a=[Management.Automation.Language.Parser]::ParseInput($f[0].Extent.Text,$hostPath,[ref]$t,[ref]$e);if($e.Count){throw 'Dump function parse failed'};. ($a.GetScriptBlock());"
                + "$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=" + quote(fixture) + ";$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;"
                + "$child=[Diagnostics.Process]::new();$child.StartInfo=$start;try{[void]$child.Start();$out=$child.StandardOutput.ReadLineAsync();$err=$child.StandardError.ReadToEndAsync();if(-not $out.Wait(5000)){throw 'Owned diagnostic child start timeout'};"
                + "[Console]::WriteLine('DUMP_DIAGNOSTIC_CHILD_READY');$clock=[Diagnostics.Stopwatch]::StartNew();"
                + (noJsonModule ? "$null=Join-Path 'C:\\' 'module-probe';$PSModuleAutoLoadingPreference='None';if(Get-Module Microsoft.PowerShell.Utility){throw 'JSON module unexpectedly preloaded'};" : "")
                + (noCommandModules ? "$PSModuleAutoLoadingPreference='None';if(Get-Module Microsoft.PowerShell.Management,Microsoft.PowerShell.Utility){throw 'Command module unexpectedly preloaded'};" : "")
                + (scenario === 'collector-stall' || scenario === 'json-error-escaping' ? "$env:AAA_HOST_WRAPPER_PIDFILE=" + quote(collectorPidFile) + ";" : "")
                + (scenario === 'json-error-escaping' ? "$env:AAA_HOST_WRAPPER_CASE='dump-json-error';" : "")
                + "Save-HostTimeoutDump $child " + quote(scenario === 'identity-error' ? path.join(owned, 'unowned.exe') : fixture) + " " + quote(diagnostic)
                + " -ExecutableCollector -CollectorEngine " + quote(scenario === 'collector-stall' || scenario === 'json-error-escaping' ? fixture : diagnosticCollector) + " -CollectorStackTool " + quote(diagnosticCollector) + ";"
                + (noJsonModule ? "if($PSModuleAutoLoadingPreference -cne 'None' -or (Get-Module Microsoft.PowerShell.Utility)){throw 'JSON module autoload guard changed'};" : "")
                + (noCommandModules ? "if($PSModuleAutoLoadingPreference -cne 'None' -or (Get-Module Microsoft.PowerShell.Management,Microsoft.PowerShell.Utility)){throw 'Command module autoload guard changed'};" : "")
                + "$clock.Stop();[Console]::WriteLine('DUMP_ELAPSED:'+$clock.ElapsedMilliseconds);"
                + "if($child.HasExited){throw 'Diagnostic ended live target'};[Console]::WriteLine('DUMP_TARGET_ALIVE')"
                + "}finally{if(-not $child.HasExited){$child.Kill()};if(-not $child.WaitForExit(5000)){throw 'Owned diagnostic child exit unconfirmed'};$child.Dispose()}";
            const started = Date.now();
            const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], {
                cwd: root, encoding: 'utf8', windowsHide: true, timeout: 25000,
                env: { ...process.env, AAA_HOST_WRAPPER_CASE: 'timeout', AAA_HOST_WRAPPER_PIDFILE: pidFile }
            });
            try {
                assert.ifError(result.error);
                assert.equal(result.status, 0, result.stderr);
                assert.match(result.stdout, /DUMP_TARGET_ALIVE/);
                const records = result.stdout.split(/\r?\n/).filter(line => line.startsWith('___HOST_CHILD_DUMP___:')).map(line => JSON.parse(line.slice('___HOST_CHILD_DUMP___:'.length)));
                assert.equal(records.length, 1);
                assert.equal(records[0].CollectorExited, true);
                assert.equal(records[0].Path, diagnostic);
                assert.equal(records[0].Pid, Number(fs.readFileSync(pidFile, 'utf8')));
                if (scenario === 'success' || scenario === 'json-unavailable' || scenario === 'modules-unavailable') {
                    assert.equal(records[0].Written, true, records[0].Error);
                    const dump = fs.readFileSync(diagnostic);
                    assert.equal(dump.toString('ascii', 0, 4), 'MDMP');
                    assert.ok(dump.readUInt32LE(8) > 0);
                    // 2026-10-22：必须区分身份核验、文件/句柄准备、原生调用返回与关闭完成，零字节不再被猜作具体阶段。
                    const phases = fs.readFileSync(diagnostic + '.phases.log', 'utf8').trim().split(/\r?\n/).map(line => line.split(' ')[1]);
                    assert.deepEqual(phases, ['collector-entered', 'identity-verified', 'write-entered', 'file-opened', 'handles-ready', 'dbghelp-load-entered', 'dbghelp-load-returned:0', 'dbghelp-export-entered', 'dbghelp-export-returned:0', 'native-returned:0', 'complete']);
                } else {
                    assert.equal(records[0].Written, false);
                    assert.ok(records[0].Error.length > 0);
                    if (scenario === 'file-error') assert.deepEqual(fs.readFileSync(diagnostic), preserved);
                    if (scenario === 'json-error-escaping') assert.ok(records[0].Error.endsWith(dumpError), records[0].Error);
                    // 2026-10-22：错误绝对路径必须拒绝取证，且不能生成目标转储；原持有者仍负责目标退出。
                    if (scenario === 'identity-error') { assert.match(records[0].Error, /Owned dump target identity changed/); assert.equal(fs.existsSync(diagnostic), false); }
                    if (scenario === 'collector-stall') {
                        assert.equal(records[0].TimedOut, true);
                        const elapsed = Number(result.stdout.match(/DUMP_ELAPSED:(\d+)/)?.[1]);
                        assert.ok(elapsed >= 4900 && elapsed < 8000, 'fixed collector deadline and bounded stop: ' + elapsed);
                        // 2026-10-22：原五秒仍失败，额外最小栈仅针对超时收集器自身，不替换原目标完整转储。
                        const secondary = JSON.parse(fs.readFileSync(diagnostic + '.collector.json', 'utf8'));
                        assert.equal(secondary.Pid, records[0].CollectorPid);
                        assert.equal(secondary.Written, true, secondary.Error);
                        assert.equal(secondary.TimedOut, false);
                        assert.equal(secondary.ExitConfirmed, true);
                        // 2026-10-22：先有不依赖DbgHelp的原寄存器/栈旁证，最小转储自身超时也不能丢现场。
                        const context = fs.readFileSync(diagnostic + '.collector.dmp.context.tsv', 'utf8').trim().split(/\r?\n/).map(line => line.split('\t'));
                        assert.deepEqual(context[0].slice(0, 4), ['AAA_CONTEXT', '1', '8', String(secondary.Pid)]);
                        assert.equal(context[0][4], secondary.StartTicks);
                        assert.ok(context.some(row => row[0] === 'M' && Buffer.from(row[3], 'base64').toString('utf8').toLowerCase().endsWith('ntdll.dll')));
                        const threads = context.filter(row => row[0] === 'T');
                        assert.ok(threads.length > 0);
                        assert.ok(threads.every(row => BigInt('0x' + row[2]) > 0n && BigInt('0x' + row[3]) > 0n && Buffer.from(row[4], 'base64').length === 1232 && Buffer.from(row[5], 'base64').length > 0));
                        assert.equal(context.at(-1)[0], 'END');
                        const stack = fs.readFileSync(diagnostic + '.collector.dmp');
                        assert.equal(stack.toString('ascii', 0, 4), 'MDMP');
                        // 2026-10-22：系统会自动加入AVX上下文位0x200000；仍禁止完整目标转储的数据标志和句柄数据流。
                        assert.equal(stack.readBigUInt64LE(24) & ~0x200000n, 0n);
                        const streamCount = stack.readUInt32LE(8), streamDirectory = stack.readUInt32LE(12);
                        for (let stream = 0; stream < streamCount; stream++) assert.notEqual(stack.readUInt32LE(streamDirectory + stream * 12), 12);
                    }
                }
                for (const file of scenario === 'collector-stall' || scenario === 'json-error-escaping' ? [pidFile, collectorPidFile] : [pidFile]) {
                    assert.throws(() => process.kill(Number(fs.readFileSync(file, 'utf8')), 0), { code: 'ESRCH' });
                }
            } catch (error) {
                // 2026-10-22：保留本例原两流、失败及耗时，仍抛原断言；精确回收本例目标与模拟收集器。
                keepArtifacts = true;
                fs.writeFileSync(path.join(owned, stem + '-failure.json'), JSON.stringify({ elapsedMs: Date.now() - started,
                    status: result.status, signal: result.signal, error: result.error ? { code: result.error.code, message: result.error.message } : null,
                    stdout: result.stdout, stderr: result.stderr }));
                for (const file of [pidFile, collectorPidFile]) {
                    try { stopOwnedFixture(file); } catch (cleanupError) { console.error(cleanupError.message); }
                }
                throw error;
            }
        });
    }
}

// 2026-10-22：原跨位数案例之后再验同位数取证，原x86启动命令不预热；必须得到可读x86上下文而非WOW64头。
test('native x86 collector preserves x86 dump context and owned target', () => {
    const quote = value => "'" + value.replace(/'/g, "''") + "'";
    const pidFile = path.join(owned, 'native-x86-target.pid');
    const dump = path.join(owned, 'native-x86-target.dmp');
    const ticksFile = path.join(owned, 'native-x86-target.startticks'); // 2026-10-22：共享系统映像的fallback必须带目标创建身份。
    const image = path.join(process.env.WINDIR, 'SysWOW64/WindowsPowerShell/v1.0/powershell.exe');
    pidFiles.push(pidFile); selfTestFiles.push(dump, dump + '.phases.log', ticksFile, dump + '.collector.dmp', dump + '.collector.dmp.phases.log', dump + '.collector.dmp.context.tsv', dump + '.collector.json'); // 2026-10-22：原生x86失败也登记同位数收集器自身旁证。
    const build = spawnSync(process.execPath, [path.join(__dirname, 'prepare-dump-collector.cjs'), '--x86'], { encoding: 'utf8', windowsHide: true, timeout: 20000 });
    assert.ifError(build.error); assert.equal(build.status, 0, build.stderr);
    const prepared = JSON.parse(build.stdout);
    selfTestFiles.push(prepared.path, path.join(path.dirname(prepared.path), 'build.json'));
    selfTestDirectories.push(path.dirname(prepared.path));
    const host = path.join(__dirname, 'host-process.test.ps1');
    const targetCommand = "$ProgressPreference='SilentlyContinue';[IO.File]::WriteAllText(" + quote(pidFile) + ",$PID.ToString());$identity=[Diagnostics.Process]::GetCurrentProcess();try{[IO.File]::WriteAllText(" + quote(ticksFile) + ",$identity.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture))}finally{$identity.Dispose()};[Console]::WriteLine('OWNED_NATIVE_X86_READY');Start-Sleep -Seconds 60";
    const command = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$p=" + quote(host) + ";$t=$null;$e=$null;"
        + "$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8),$p,[ref]$t,[ref]$e);"
        + "$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-HostTimeoutDump'},$true));if($f.Count -ne 1){throw 'Exact helper missing'};"
        + "$a=[Management.Automation.Language.Parser]::ParseInput($f[0].Extent.Text,$p,[ref]$t,[ref]$e);. ($a.GetScriptBlock());"
        + "$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName=" + quote(image) + ";$s.Arguments='-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand " + Buffer.from(targetCommand, 'utf16le').toString('base64') + "';"
        + "$s.UseShellExecute=$false;$s.CreateNoWindow=$true;$s.RedirectStandardOutput=$true;$s.RedirectStandardError=$true;$child=[Diagnostics.Process]::new();$child.StartInfo=$s;"
        + "try{if(-not $child.Start()){throw 'Owned x86 target not started'};$ready=$child.StandardOutput.ReadLineAsync();$err=$child.StandardError.ReadToEndAsync();if(-not $ready.Wait(5000) -or $ready.Result -cne 'OWNED_NATIVE_X86_READY'){throw 'Owned x86 ready failed'};"
        + "Save-HostTimeoutDump $child " + quote(image) + " " + quote(dump) + " -ExecutableCollector -CollectorEngine " + quote(prepared.path) + " -CollectorStackTool " + quote(prepared.path) + ";if($child.HasExited){throw 'Dump ended owned target'};[Console]::WriteLine('OWNED_NATIVE_X86_ALIVE')}"
        + "finally{if(-not $child.HasExited){$child.Kill()};if(-not $child.WaitForExit(1000)){throw 'Owned x86 exit unconfirmed'};$child.Dispose()}";
    const result = spawnSync('pwsh.exe', ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 25000 });
    try {
        assert.ifError(result.error); assert.equal(result.status, 0, result.stderr); assert.equal(result.stderr, '');
        assert.match(result.stdout, /OWNED_NATIVE_X86_ALIVE/);
        const record = JSON.parse(result.stdout.split(/\r?\n/).find(line => line.startsWith('___HOST_CHILD_DUMP___:')).slice('___HOST_CHILD_DUMP___:'.length));
        assert.equal(record.Written, true, record.Error); assert.equal(record.CollectorExited, true);
        assert.equal(record.Pid, Number(fs.readFileSync(pidFile, 'utf8')));
        assert.throws(() => process.kill(record.Pid, 0), { code: 'ESRCH' });
        const bytes = fs.readFileSync(dump); assert.equal(bytes.toString('ascii', 0, 4), 'MDMP');
        let architecture = null;
        for (let n = 0; n < bytes.readUInt32LE(8); n++) {
            const entry = bytes.readUInt32LE(12) + n * 12;
            if (bytes.readUInt32LE(entry) === 7) architecture = bytes.readUInt16LE(bytes.readUInt32LE(entry + 8));
        }
        assert.equal(architecture, 0, 'same-bitness dump must use native Intel context');
        assert.equal(bytes.readBigUInt64LE(24) & 0x1124n, 0x1124n);
        assert.equal(JSON.parse(fs.readFileSync(path.join(path.dirname(prepared.path), 'build.json'), 'utf8')).platform, 'x86');
    } catch (error) {
        keepArtifacts = true; fs.writeFileSync(path.join(owned, 'native-x86-failure.json'), JSON.stringify({ status: result.status, stdout: result.stdout, stderr: result.stderr }));
        try { stopOwnedFixture(pidFile, image, fs.existsSync(ticksFile) ? fs.readFileSync(ticksFile, 'utf8') : null); }
        catch (cleanupError) { console.error('Owned native x86 cleanup refused: ' + cleanupError.message); }
        throw error;
    }
});

// 2026-10-22：用独占EXE安全模拟共享映像调用，错误创建身份不能回收仍由本测试持有的目标。
test('cleanup rejects a mismatched creation identity before stopping a live target', async () => {
    const { spawn } = require('node:child_process');
    const image = path.join(owned, 'cleanup-identity-control.exe');
    const pidFile = path.join(owned, 'cleanup-identity-control.pid');
    fs.copyFileSync(fixture, image); selfTestFiles.push(image); pidFiles.push(pidFile);
    const child = spawn(image, [], { windowsHide: true, stdio: ['ignore','pipe','pipe'], env: { ...process.env, AAA_HOST_WRAPPER_CASE: 'timeout', AAA_HOST_WRAPPER_PIDFILE: pidFile } });
    const closed = new Promise(resolve => child.once('close', resolve));
    child.stderr.on('data', () => {});
    let failure;
    try {
        await new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('Owned identity control readiness timeout')), 5000);
            child.once('error', error => { clearTimeout(timer); reject(error); });
            child.stdout.on('data', value => { if (value.toString().includes('HOST_WRAPPER_STDOUT:')) { clearTimeout(timer); resolve(); } });
        });
        assert.throws(() => stopOwnedFixture(pidFile, image), /Shared process creation identity required/);
        assert.throws(() => stopOwnedFixture(pidFile, image, '1'), /creation time mismatch/);
        assert.doesNotThrow(() => process.kill(child.pid, 0), 'mismatched creation identity must leave the owned target alive');
    } catch (error) { keepArtifacts = true; failure = error; }
    finally {
        // 2026-10-22：无论回归断言如何，最后只由原ChildProcess持有者停止自己的控制目标。
        if (child.exitCode === null) child.kill();
        await closed;
    }
    if (failure) throw failure;
});

// 2026-10-22：CIM快照之后正常退出的自有候选不是观察器故障；真实旧调用必须先复现ArgumentException。
for (const engine of engines) {
    test(engine + ': observer handles a confirmed exited candidate and retains live lookup', () => {
        const quote = value => "'" + value.replace(/'/g, "''") + "'";
        const observer = path.join(__dirname, 'observe-host-wrapper-diagnostic.ps1');
        const command = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$p=" + quote(observer) + ";$t=$null;$e=$null;"
            + "$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8),$p,[ref]$t,[ref]$e);"
            + "$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Open-ObserverCandidateProcess'},$true));"
            + "if($f.Count -eq 1){$a=[Management.Automation.Language.Parser]::ParseInput($f[0].Extent.Text,$p,[ref]$t,[ref]$e);. ($a.GetScriptBlock())}"
            + "else{function Open-ObserverCandidateProcess([int]$CandidatePid){return [Diagnostics.Process]::GetProcessById($CandidatePid)}};"
            + "$s=[Diagnostics.ProcessStartInfo]::new();$s.FileName=$env:ComSpec;$s.Arguments='/d /c exit 0';$s.UseShellExecute=$false;$s.CreateNoWindow=$true;"
            + "$child=[Diagnostics.Process]::new();$child.StartInfo=$s;$started=$false;"
            + "try{if(-not $child.Start()){throw 'Owned exit control start failed'};$started=$true;[void]$child.Handle;"
            + "if(-not $child.WaitForExit(5000) -or $child.ExitCode -ne 0){throw 'Owned exit control not complete'};"
            + "$live=Open-ObserverCandidateProcess $PID;try{if($null -eq $live -or $live.Id -ne $PID){throw 'Live lookup lost'}}finally{if($null -ne $live){$live.Dispose()}};"
            + "$gone=Open-ObserverCandidateProcess $child.Id;if($null -ne $gone){$gone.Dispose();throw 'Exited lookup retained an unavailable candidate'};"
            + "[Console]::WriteLine('OBSERVER_CONFIRMED_EXIT_RACE_HANDLED')}"
            + "finally{if($started){if(-not $child.HasExited){$child.Kill()};if(-not $child.WaitForExit(1000)){throw 'Owned exit control cleanup unconfirmed'}};$child.Dispose()}";
        const result = spawnSync(engine, ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')],
            { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 25000 });
        assert.ifError(result.error);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stderr, '');
        assert.match(result.stdout, /OBSERVER_CONFIRMED_EXIT_RACE_HANDLED/);
    });
}
