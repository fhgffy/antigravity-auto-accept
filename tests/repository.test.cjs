/* 2026-10-07：检查工作区和 CI 检出的真实文件，避免无 BOM 脚本被转码或发布清单与锁文件漂移。 */
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os'); // 2026-10-22：编译依赖控制只使用本例独占临时目录。
const path = require('node:path');
const test = require('node:test');
const { TextDecoder } = require('node:util');

const root = path.join(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root })
    .toString('utf8').split('\0').filter(Boolean);
const textFiles = files.filter(file => /\.(?:ts|ps1|cs|cjs|json|ya?ml|md)$/i.test(file) // 2026-10-09：新增原生测试夹具的编码检查。
    || ['.gitattributes', '.gitignore', '.vscodeignore', 'LICENSE'].includes(file));

test('tracked source and maintenance files preserve strict UTF-8 without BOM and CRLF', () => {
    assert.ok(textFiles.length > 0);
    const decoder = new TextDecoder('utf-8', { fatal: true });
    for (const file of textFiles) {
        const bytes = fs.readFileSync(path.join(root, file));
        assert.notDeepEqual(bytes.subarray(0, 3), Buffer.from([0xef, 0xbb, 0xbf]), `${file}: UTF-8 BOM`);
        const text = decoder.decode(bytes);
        assert.doesNotMatch(text, /(?<!\r)\n|\r(?!\n)/, `${file}: non-CRLF newline`);
        assert.doesNotMatch(text, /\u0000/, `${file}: NUL byte in text file`);
    }
});

test('package and lockfile identify the same release and dependency graph', () => {
    assert.equal(lock.name, manifest.name);
    assert.equal(lock.version, manifest.version);
    assert.equal(lock.packages[''].name, manifest.name);
    assert.equal(lock.packages[''].version, manifest.version);
    assert.deepEqual(lock.packages[''].devDependencies, manifest.devDependencies);
    assert.deepEqual(lock.packages[''].engines, manifest.engines);
    assert.equal(manifest.main, './out/extension.js');
    assert.equal(manifest.extensionKind.includes('ui'), true);
    assert.equal(manifest.capabilities.untrustedWorkspaces.supported, false);
    assert.equal(manifest.capabilities.virtualWorkspaces.supported, false);
});

test('working diff has no whitespace errors', () => {
    execFileSync('git', ['diff', '--check'], { cwd: root, stdio: 'pipe' });
    execFileSync('git', ['diff', '--cached', '--check'], { cwd: root, stdio: 'pipe' });
});

/* 2026-10-23：执行真实生命周期自测回调，只替代同步返回与文件边界，不启动CLR或提前读取目标模块。 */
function captureLifecycleFailure(result, variables = {}, writeFailure) {
    const callbacks = [], writes = [], directories = [], errors = [], calls = [], assertionErrors = [], cleanups = [];
    const environment = Object.freeze({ AAA_LIFECYCLE_SENTINEL: 'unchanged', ...variables });
    const environmentBefore = JSON.stringify(environment), realEnvironmentBefore = Object.entries(process.env);
    const recordedAssert = new Proxy(assert, { get: (target, name) => {
        const original = target[name];
        return ['ifError', 'equal', 'match'].includes(name) ? (...args) => {
            try { return original(...args); } catch (error) { assertionErrors.push(error); throw error; }
        } : original;
    } });
    let ticks = 0n, thrown;
    const modules = {
        'node:assert/strict': recordedAssert,
        'node:fs': { ...fs,
            mkdtempSync: prefix => {
                directories.push(prefix);
                if (writeFailure === 'directory') throw new Error('diagnostic directory rejected');
                return prefix + 'owned';
            },
            writeFileSync: (file, data, encoding) => {
                if (writeFailure === 'write' || (writeFailure === 'write-second' && writes.length === 1)
                    || (writeFailure === 'write-third' && writes.length === 2)) throw new Error('diagnostic write rejected');
                writes.push({ file, data, encoding });
            },
            unlinkSync: file => cleanups.push(file), rmdirSync: file => cleanups.push(file), rmSync: file => cleanups.push(file),
        },
        'node:test': (name, options, callback) => callbacks.push({ name, callback: callback || options }),
        'node:child_process': { spawnSync: (command, args, options) => { calls.push({ command, args, options }); return result; } },
    };
    require('node:vm').runInNewContext(fs.readFileSync(path.join(__dirname, 'extension.test.cjs'), 'utf8'), {
        require: name => Object.hasOwn(modules, name) ? modules[name] : require(name),
        __dirname, Buffer,
        process: { platform: 'win32', env: environment, hrtime: { bigint: () => { ticks += 1250000000n; return ticks; } } },
        console: { error: (...args) => errors.push(args) },
    }, { filename: 'extension.test.cjs', timeout: 5000 });
    const selected = callbacks.filter(item => item.name === '真实 PowerShell 启动协议通过扫描器自测且 stderr 为空');
    assert.equal(selected.length, 1);
    try { selected[0].callback(); } catch (error) { thrown = error; }
    assert.equal(calls.length, 1, 'one unchanged synchronous launcher invocation');
    assert.equal(calls[0].command, 'powershell.exe');
    assert.deepEqual(JSON.parse(JSON.stringify(calls[0].options)), { windowsHide: true, encoding: 'utf8', timeout: 20000 });
    assert.deepEqual(Array.from(calls[0].args).slice(0, 7), ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass', '-EncodedCommand']);
    assert.equal(calls[0].args.length, 8);
    const command = Buffer.from(calls[0].args[7], 'base64').toString('utf16le');
    assert.match(command, / -SelfTest$/);
    assert.equal(JSON.stringify(environment), environmentBefore);
    assert.deepEqual(Object.entries(process.env), realEnvironmentBefore);
    return { directories, writes, errors, calls, thrown, assertionErrors, cleanups };
}

/* 2026-10-23：成功路径零落盘；原超时、启动失败及原四项断言失败都保留同步返回原件与同一个断言异常。 */
test('real lifecycle failures retain the original synchronous result without changing launcher defaults', () => {
    const success = { pid: 4516, status: 0, signal: null, stdout: '___SELFTEST_DONE___:passed=87\r\n', stderr: '' };
    const passed = captureLifecycleFailure(success);
    assert.equal(passed.thrown, undefined);
    assert.equal(passed.assertionErrors.length, 0);
    assert.deepEqual(passed.directories, []);
    assert.deepEqual(passed.writes, []);
    assert.deepEqual(passed.errors, []);
    assert.deepEqual(passed.cleanups, []);
    const timeout = Object.assign(new Error('spawnSync powershell.exe ETIMEDOUT'), {
        code: 'ETIMEDOUT', errno: -4039, syscall: 'spawnSync powershell.exe', path: 'powershell.exe',
    });
    const missing = Object.assign(new Error('spawnSync powershell.exe ENOENT'), { code: 'ENOENT', errno: -4058, syscall: 'spawnSync powershell.exe', path: 'powershell.exe' });
    for (const result of [
        { ...success, error: timeout, status: null, signal: 'SIGTERM', stdout: '部分输出🙂\r\n', stderr: '部分错误🚩\n' },
        { error: missing, pid: 0, status: null, signal: null, stdout: null, stderr: null },
        { ...success, status: 3 }, { ...success, stderr: 'unexpected error\n' }, { ...success, stdout: 'missing done\n' },
    ]) {
        for (const variables of [{}, { RUNNER_TEMP: path.join(root, 'runner-temp-control') }]) {
            const actual = captureLifecycleFailure(result, variables);
            assert.equal(actual.thrown, actual.assertionErrors[0], 'diagnostics must rethrow the identical original assertion error');
            assert.ok(actual.thrown);
            assert.deepEqual(actual.errors, []);
            assert.deepEqual(actual.cleanups, []);
            assert.deepEqual(actual.directories, [path.join(variables.RUNNER_TEMP || os.tmpdir(), 'AntigravityAA-LifecycleTimeout-')]);
            assert.equal(actual.writes.length, 3);
            const byName = Object.fromEntries(actual.writes.map(item => [path.basename(item.file), item]));
            const receipt = JSON.parse(byName['receipt.json'].data);
            assert.equal(receipt.SpawnSyncReturned, true);
            assert.equal(receipt.PreKillCapture, false);
            assert.equal(receipt.StreamsAreNodeDecodedUtf8, true);
            assert.equal(receipt.DurationMs, 1250);
            assert.ok(Number.isFinite(Date.parse(receipt.StartedUtc)) && Date.parse(receipt.ReturnedUtc) >= Date.parse(receipt.StartedUtc));
            assert.equal(receipt.Command, actual.calls[0].command);
            assert.deepEqual(receipt.Args, Array.from(actual.calls[0].args));
            for (const field of ['pid', 'status', 'signal', 'stdout', 'stderr']) {
                assert.equal(receipt[field[0].toUpperCase() + field.slice(1)], result[field] ?? null);
            }
            assert.deepEqual(receipt.Error, result.error ? Object.fromEntries(
                ['name', 'message', 'stack', 'code', 'errno', 'syscall', 'path'].map(name => [name, result.error[name] ?? null])) : null);
            for (const stream of ['stdout', 'stderr']) assert.equal(byName[stream + '.log'].data, result[stream] ?? '');
            for (const item of actual.writes) {
                assert.equal(item.encoding, 'utf8');
                assert.equal(path.dirname(item.file), actual.directories[0] + 'owned');
            }
        }
    }
});

/* 2026-10-23：取证目录或两流写入失败只能额外报告，不能掩盖原测试失败或改变退出语义。 */
test('lifecycle diagnostic write failures preserve the original assertion exception', () => {
    for (const [failure, retained] of [['directory', 0], ['write', 0], ['write-second', 1], ['write-third', 2]]) {
        const actual = captureLifecycleFailure({ pid: 42, status: 1, signal: null, stdout: '', stderr: 'original failure' }, {}, failure);
        assert.equal(actual.thrown, actual.assertionErrors[0]);
        assert.ok(actual.thrown);
        assert.equal(actual.errors.length, 1);
        assert.match(actual.errors[0].join(' '), /Lifecycle failure evidence could not be written/);
        assert.equal(actual.directories.length, 1);
        assert.deepEqual(actual.cleanups, []);
        assert.deepEqual(actual.writes.map(item => path.basename(item.file)), ['receipt.json', 'stdout.log'].slice(0, retained));
        if (retained) assert.equal(JSON.parse(actual.writes[0].data).Stderr, 'original failure');
    }
});

/* 2026-10-23：这里只读暂存契约与调用顺序，真实PowerShell控制放原生命周期序列末尾，避免提前暖读Framework。 */
test('normal failure upload stages owned diagnostics after original tests', () => {
    const stageScript = path.join(__dirname, 'stage-owned-timeout-diagnostics.ps1');
    assert.ok(fs.existsSync(stageScript), 'Failure diagnostics need a real single-root staging script');
    const controlFile = path.join(__dirname, 'timeout-diagnostics.test.cjs');
    assert.ok(fs.existsSync(controlFile), 'Real staging controls must use a separate post-lifecycle entry');
    const workflow = fs.readFileSync(path.join(root, '.github/workflows/windows-validation.yml'), 'utf8');
    const stages = workflow.slice(workflow.indexOf('      - name: Stage owned host child timeout diagnostics'),
        workflow.indexOf('      - name: Preserve native startup trace'));
    assert.match(stages, /id: timeout_diagnostics/);
    assert.match(stages, /stage-owned-timeout-diagnostics\.ps1/);
    const upload = stages.slice(stages.indexOf('      - name: Preserve owned host child timeout diagnostics'));
    assert.match(upload, /if: failure\(\)/);
    assert.ok(upload.includes('path: ${{ steps.timeout_diagnostics.outputs.path }}'));
    assert.equal((upload.match(/^\s+path:/gm) || []).length, 1);
    assert.doesNotMatch(upload, /AppData|LifecycleTimeout-\*|HostBinary-\*/);
    assert.ok(upload.includes('name: host-child-timeout-${{ github.run_id }}-${{ matrix.major }}${{ inputs.artifact_suffix }}'));
    assert.match(upload, /retention-days: 14/); assert.match(upload, /if-no-files-found: warn/);
    assert.equal(manifest.scripts['test:timeout-diagnostics'], 'node --test tests/timeout-diagnostics.test.cjs');
    const originalTestOrder = ['compile', 'typecheck', 'test:repository', 'test:publication', 'selftest', 'test:lifecycle',
        'test:scanner', 'test:host', 'test:host-wrapper', 'test:mouse', 'test:concurrency'];
    /* 2026-10-23：原测试前缀及暂存控制保持严格顺序，托管子环境纯Node控制只追加在末尾。 */
    assert.equal(manifest.scripts['test:lifecycle-env'], 'node --test tests/lifecycle-hosted-env.test.cjs');
    assert.equal(manifest.scripts.test, [...originalTestOrder, 'test:timeout-diagnostics', 'test:lifecycle-env'].map(name => 'npm run ' + name).join(' && '));
    const controlStep = workflow.indexOf('      - name: Owned timeout diagnostics staging regression');
    assert.ok(controlStep > workflow.indexOf('      - name: Concurrent scanner handoff without desktop clicks'));
    assert.ok(controlStep < workflow.indexOf('      - name: Save native startup trace'));
    /* 2026-10-24：只检查原控制步骤自身，后续追加的架构条件不能被误归到这个无条件步骤。 */
    const controlBlock = workflow.slice(controlStep, workflow.indexOf('      - name:', controlStep + 1));
    assert.match(controlBlock, /run: npm run test:timeout-diagnostics/);
    assert.doesNotMatch(controlBlock, /if:|continue-on-error:/);
    const environmentStep = workflow.indexOf('      - name: Hosted lifecycle child environment boundaries');
    assert.ok(environmentStep > controlStep);
    assert.ok(environmentStep < workflow.indexOf('      - name: Save native startup trace'));
    const environmentBlock = workflow.slice(environmentStep, workflow.indexOf('      - name:', environmentStep + 1));
    assert.match(environmentBlock, /run: npm run test:lifecycle-env/);
    assert.doesNotMatch(environmentBlock, /if:|continue-on-error:/);
});

/* 2026-10-24：x86扫描与并发只追加在原测试之后，复用原入口及期限，不提前暖读生命周期首个WinPS。 */
test('x86 scanner and concurrency CI coverage follows every original test step', () => {
    const workflow = fs.readFileSync(path.join(root, '.github/workflows/windows-validation.yml'), 'utf8');
    const environmentStep = workflow.indexOf('      - name: Hosted lifecycle child environment boundaries');
    const traceStep = workflow.indexOf('      - name: Save native startup trace');
    let previousStep = environmentStep;
    for (const [name, file] of [
        ['X86 scanner regression on the default host', 'scanner.test.ps1'],
        ['X86 concurrent scanner handoff without desktop clicks', 'scanner-concurrency.test.ps1']
    ]) {
        const marker = '      - name: ' + name;
        const step = workflow.indexOf(marker);
        assert.ok(step > previousStep && step < traceStep, name + ' must follow the original tests');
        assert.equal(workflow.indexOf(marker, step + marker.length), -1, name + ' must run once');
        const block = workflow.slice(step, workflow.indexOf('      - name:', step + 1));
        assert.match(block, /^        if: matrix\.major == 5\r?$/m);
        assert.equal((block.match(/^        if:/gm) || []).length, 1);
        assert.ok(block.includes("$x86Engine = Join-Path $env:SystemRoot 'SysWOW64/WindowsPowerShell/v1.0/powershell.exe'"));
        assert.ok(block.includes("Join-Path $PWD 'tests/" + file + "'"));
        assert.ok(block.includes('[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)'));
        assert.match(block, /if \(\$parseErrors\.Count -gt 0\) \{ throw /);
        assert.ok(block.includes('& ($testAst.GetScriptBlock()) -PowerShellEngines @($x86Engine)'));
        if (file === 'scanner.test.ps1') {
            // 2026-10-24：完整回归必须在真实x86父宿主运行，不能只把x86路径传给内部子测试。
            const child = block.match(/^          \$testCommand = @'\r?\n([\s\S]*?)^          '@\r?$/m);
            assert.ok(child, 'scanner regression requires an explicit child command');
            assert.ok(child[1].includes("$ErrorActionPreference = 'Stop'"));
            assert.ok(child[1].includes("if ([IntPtr]::Size -ne 4) { throw 'Scanner regression requires a 32-bit host' }"));
            assert.ok(child[1].includes("$x86Engine = Join-Path $env:SystemRoot 'SysWOW64/WindowsPowerShell/v1.0/powershell.exe'"));
            assert.ok(child[1].includes("Join-Path $PWD 'tests/scanner.test.ps1'"));
            assert.ok(child[1].includes('[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)'));
            assert.match(child[1], /if \(\$parseErrors\.Count -gt 0\) \{ throw /);
            assert.match(child[1], /& \(\$testAst\.GetScriptBlock\(\)\) -PowerShellEngines @\(\$x86Engine\) -TimeoutCollectorPath \$env:AAA_TEST_DUMP_COLLECTOR\r?\n          if \(-not \$\?\) \{ throw 'Scanner regression failed' \}\r?\n          exit 0\r?\n$/);
            assert.match(block.slice(child.index + child[0].length), /^\r?\n          & \$x86Engine -NoLogo -NoProfile -NonInteractive -Command \$testCommand\r?\n          exit \$LASTEXITCODE\r?\n/);
        }
        assert.doesNotMatch(block, /continue-on-error:|timeout-minutes:|-Rounds\b|-ExpectedSelfTestCount\b|-ScannerSourcePath\b/);
        previousStep = step;
    }
    for (const name of ['Scanner regression on one engine', 'Concurrent scanner handoff without desktop clicks']) {
        const step = workflow.indexOf('      - name: ' + name);
        assert.ok(step > 0 && step < environmentStep);
        const block = workflow.slice(step, workflow.indexOf('      - name:', step + 1));
        assert.ok(block.includes("-PowerShellEngines @('${{ matrix.executable }}')"));
        assert.doesNotMatch(block, /SysWOW64|x86Engine|continue-on-error:|^        if:/m);
    }
});

/* 2026-10-23：执行真实诊断回调到进程边界即停止，不运行编译、PowerShell或清理钩子，避免提前暖读Framework。 */
function captureDiagnosticEnvironment(engine, variables = {}) {
    const parentEnvironment = Object.freeze({ WINDIR: process.env.WINDIR, SystemRoot: process.env.SystemRoot,
        HOST_WRAPPER_ENGINE: engine, AAA_ENV_BOUNDARY_SENTINEL: 'keep', ...variables });
    const parentBefore = JSON.stringify(parentEnvironment), realBefore = Object.entries(process.env);
    const owned = path.join(root, 'tests', 'environment-capture-only');
    const callbacks = [], stopped = new Error('diagnostic spawn captured');
    let captured;
    const modules = {
        'node:assert/strict': assert, 'node:path': path, 'node:os': os,
        'node:fs': { mkdtempSync: () => owned, realpathSync: { native: value => value } },
        'node:test': { test: (name, callback) => callbacks.push({ name, callback }), before: () => {}, after: () => {} },
        'node:child_process': { spawnSync: (image, args, options) => { captured = { image, args, options }; throw stopped; } }
    };
    require('node:vm').runInNewContext(fs.readFileSync(path.join(__dirname, 'host-wrapper.test.cjs'), 'utf8'), {
        require: name => { assert.ok(Object.hasOwn(modules, name), 'unexpected diagnostic dependency: ' + name); return modules[name]; },
        __dirname, Buffer, process: { env: parentEnvironment, execPath: process.execPath, platform: process.platform }
    }, { filename: 'host-wrapper.test.cjs', timeout: 5000 });
    const selected = callbacks.filter(item => item.name === engine + ': bounded x64 minidump success retains target');
    assert.equal(selected.length, 1, 'capture exactly one real bounded diagnostic callback');
    assert.throws(selected[0].callback, error => error === stopped);
    assert.equal(JSON.stringify(parentEnvironment), parentBefore, 'simulated parent environment must remain unchanged');
    assert.deepEqual(Object.entries(process.env), realBefore, 'real parent environment must remain unchanged');
    assert.equal(captured.image, engine);
    assert.deepEqual(Array.from(captured.args).slice(0, 5), ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand']);
    assert.equal(captured.options.cwd, path.resolve(root));
    assert.equal(captured.options.encoding, 'utf8');
    assert.equal(captured.options.windowsHide, true);
    assert.equal(captured.options.timeout, 25000);
    return { environment: JSON.parse(JSON.stringify(captured.options.env)), parentEnvironment, owned };
}

/* 2026-10-23：缺少局部开关、遗留大小写冲突或误改父环境都会使实际启动参数失败。 */
test('x86 diagnostic spawn selects one local Desktop CLR setting', { skip: process.platform !== 'win32' }, () => {
    const image = path.win32.join(process.env.WINDIR, 'SysWOW64', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    for (const engine of [image, image.toUpperCase().replace(/\\/g, '/')]) {
        for (const variables of [{}, { COMPLUS_ZAPDISABLE: '0' },
            { COMPLUS_ZAPDISABLE: '0', COMPlus_ZapDisable: '0', complus_zapdisable: '0' }]) {
            const actual = captureDiagnosticEnvironment(engine, variables);
            const settings = Object.entries(actual.environment).filter(([name]) => /^complus_zapdisable$/i.test(name));
            assert.deepEqual(settings, [['COMPlus_ZapDisable', '1']], 'x86 diagnostic must receive exactly one enabled CLR setting');
            assert.equal(actual.environment.AAA_ENV_BOUNDARY_SENTINEL, 'keep');
            assert.equal(actual.environment.AAA_HOST_WRAPPER_CASE, 'timeout');
            assert.equal(actual.environment.AAA_HOST_WRAPPER_PIDFILE, path.join(actual.owned, 'diagnostic-0-success.pid'));
        }
    }
});

/* 2026-10-23：精确映像边界不能把同名程序、x64或pwsh的原环境也改成候选模式。 */
test('other diagnostic images retain their original environment', { skip: process.platform !== 'win32' }, () => {
    for (const engine of ['powershell.exe', 'pwsh.exe',
        path.win32.join(process.env.WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
        path.win32.join(root, 'lookalike', 'SysWOW64', 'WindowsPowerShell', 'v1.0', 'powershell.exe')]) {
        const actual = captureDiagnosticEnvironment(engine, { COMPLUS_ZAPDISABLE: '0', COMPlus_ZapDisable: '2', complus_zapdisable: '3' });
        assert.deepEqual(actual.environment, { ...actual.parentEnvironment, AAA_HOST_WRAPPER_CASE: 'timeout',
            AAA_HOST_WRAPPER_PIDFILE: path.join(actual.owned, 'diagnostic-0-success.pid') });
    }
});

/* 2026-10-23：把真实调用点给出的环境传入普通Node子进程及其后代，覆盖Windows重复键排序；不启动CLR。 */
test('x86 diagnostic setting reaches a Windows Node child and descendant', { skip: process.platform !== 'win32' }, () => {
    const image = path.win32.join(process.env.WINDIR, 'SysWOW64', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    const actual = captureDiagnosticEnvironment(image, { COMPLUS_ZAPDISABLE: '0', COMPlus_ZapDisable: '0', complus_zapdisable: '0' });
    const readSettings = '() => Object.entries(process.env).filter(([name]) => /^complus_zapdisable$/i.test(name)).map(([, value]) => value)';
    const grandchild = 'process.stdout.write(JSON.stringify((' + readSettings + ')()));';
    const child = "const { execFileSync } = require('node:child_process');const own=(" + readSettings + ")();"
        + 'const grand=JSON.parse(execFileSync(process.execPath,[\'-e\',' + JSON.stringify(grandchild)
        + '],{encoding:\'utf8\',windowsHide:true,timeout:5000}));process.stdout.write(JSON.stringify({own,grand}));';
    const observed = JSON.parse(execFileSync(process.execPath, ['-e', child], {
        encoding: 'utf8', windowsHide: true, timeout: 10000, env: actual.environment
    }));
    assert.deepEqual(observed, { own: ['1'], grand: ['1'] });
});

/* 2026-10-23：执行真实scanner回调直到启动边界即截获，不启动CLR，也不运行编译/清理钩子。 */
function captureScannerWrapperSpawn(engine, mode) {
    const parentEnvironment = Object.freeze({ WINDIR: process.env.WINDIR, SystemRoot: process.env.SystemRoot,
        HOST_WRAPPER_ENGINE: engine, COMPLUS_ZAPDISABLE: '0', AAA_ENV_BOUNDARY_SENTINEL: 'keep' });
    const parentBefore = JSON.stringify(parentEnvironment), realBefore = Object.entries(process.env);
    const owned = path.join(root, 'tests', 'scanner-environment-capture-only');
    const callbacks = [], scripts = [], stopped = new Error('scanner spawn captured');
    let captured;
    const modules = {
        'node:assert/strict': assert, 'node:path': path, 'node:os': os,
        'node:fs': { mkdtempSync: () => owned, realpathSync: { native: value => value }, mkdirSync: () => {},
            writeFileSync: (file, text) => scripts.push({ file, text }), readFileSync: fs.readFileSync.bind(fs) },
        'node:test': { test: (name, callback) => callbacks.push({ name, callback }), before: () => {}, after: () => {} },
        'node:child_process': { spawnSync: (image, args, options) => { captured = { image, args, options }; throw stopped; } }
    };
    require('node:vm').runInNewContext(fs.readFileSync(path.join(__dirname, 'host-wrapper.test.cjs'), 'utf8'), {
        require: name => { assert.ok(Object.hasOwn(modules, name), 'unexpected scanner dependency: ' + name); return modules[name]; },
        __dirname, Buffer, process: { env: parentEnvironment, execPath: process.execPath, platform: process.platform }
    }, { filename: 'host-wrapper.test.cjs', timeout: 5000 });
    const selected = callbacks.filter(item => item.name === engine + ': scanner SelfTest wrapper ' + mode);
    assert.equal(selected.length, 1, 'capture exactly one real scanner callback');
    assert.throws(selected[0].callback, error => error === stopped);
    assert.equal(JSON.stringify(parentEnvironment), parentBefore);
    assert.deepEqual(Object.entries(process.env), realBefore);
    assert.equal(captured.image, engine); assert.equal(captured.options.timeout, 35000);
    assert.deepEqual(JSON.parse(JSON.stringify(captured.options.env)), { ...parentEnvironment,
        AAA_SELFTEST_PIDFILE: path.join(owned, `selftest-0-${mode}.json`), AAA_HOST_WRAPPER_CASE: 'timeout',
        AAA_HOST_WRAPPER_PIDFILE: path.join(owned, `selftest-0-${mode}-fallback.pid`),
        AAA_SCANNER_STARTUP_IMAGE_UNAVAILABLE: mode === 'stdout' ? '1' : '0' });
    return { command: Buffer.from(captured.args.at(-1), 'base64').toString('utf16le'), scripts };
}

/* 2026-10-23：仅人工stall的抽取目标设置JIT；父环境及其它模式不变，实际NI机制另由真实目标守卫确认。 */
test('scanner artificial timeout JIT stays inside owned target launch', { skip: process.platform !== 'win32' }, () => {
    for (const engine of ['powershell.exe', 'pwsh.exe']) {
        const actual = captureScannerWrapperSpawn(engine, 'timeout');
        assert.match(actual.command.replace(/''/g, "'"), /\$start\.EnvironmentVariables\['COMPlus_ZapDisable'\]='1'/,
            'artificial stall must set JIT on its target ProcessStartInfo');
        assert.ok(actual.command.includes('___SCANNER_STALL_TARGET_JIT_VERIFIED___'));
        assert.equal(actual.scripts.length, 1);
        assert.equal(Buffer.byteLength(actual.scripts[0].text, 'utf8'), 322, 'original fake stall source unchanged');
    }
});

test('other scanner wrapper modes retain their original CLR settings', { skip: process.platform !== 'win32' }, () => {
    for (const engine of ['powershell.exe', 'pwsh.exe']) {
        for (const mode of ['stdout', 'stderr', 'exit', 'missing-done', 'ledger-failure', 'selftest-no-desktop', 'selftest-no-compiler']) {
            const actual = captureScannerWrapperSpawn(engine, mode);
            assert.doesNotMatch(actual.command, /COMPlus_ZapDisable|___SCANNER_STALL_TARGET_JIT_VERIFIED___/);
        }
    }
});

/* 2026-10-22：真实构建须忽略默认响应文件中的无关引用，保持原源文件和输出位数；不执行x86目标。 */
test('diagnostic compiler ignores unrelated default response references', { skip: process.platform !== 'win32' }, () => {
    const actualCompiler = path.join(process.env.WINDIR, 'Microsoft.NET/Framework64/v4.0.30319');
    const owned = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'AntigravityAA-CompilerReferences-')));
    const fakeWindows = path.join(owned, 'windows');
    const compiler = path.join(fakeWindows, 'Microsoft.NET/Framework64/v4.0.30319');
    const files = [], directories = [], outputs = [];
    let passed = false;
    try {
        fs.mkdirSync(compiler, { recursive: true });
        for (const name of ['csc.exe', 'csc.exe.config', 'System.dll', '1033/cscui.dll', '2052/cscui.dll']) {
            const source = path.join(actualCompiler, name);
            if (!fs.existsSync(source) && name.endsWith('/cscui.dll')) continue;
            const destination = path.join(compiler, name);
            if (name.includes('/')) { fs.mkdirSync(path.dirname(destination)); directories.push(path.dirname(destination)); }
            fs.copyFileSync(source, destination);
            files.push(destination);
        }
        const response = path.join(compiler, 'csc.rsp');
        fs.writeFileSync(response, '/r:AAA_UNRELATED_DEFAULT_REFERENCE_MUST_NOT_BE_READ.dll\r\n');
        files.push(response);
        for (const platform of ['x64', 'x86']) {
            const result = require('node:child_process').spawnSync(process.execPath,
                [path.join(root, 'tests/prepare-dump-collector.cjs'), ...(platform === 'x86' ? ['--x86'] : [])], {
                    cwd: root, encoding: 'utf8', windowsHide: true, timeout: 20000,
                    env: { ...process.env, WINDIR: fakeWindows, TEMP: owned, TMP: owned }
                });
            assert.ifError(result.error);
            assert.equal(result.status, 0, JSON.stringify({ stdout: result.stdout, stderr: result.stderr, owned }));
            assert.equal(result.stderr, '');
            const built = JSON.parse(result.stdout);
            const relative = path.relative(owned, built.path);
            assert.ok(relative && !relative.startsWith('..') && !path.isAbsolute(relative));
            outputs.push(path.dirname(built.path));
            const record = JSON.parse(fs.readFileSync(path.join(path.dirname(built.path), 'build.json'), 'utf8'));
            assert.equal(record.platform, platform);
            assert.equal(record.status, 0);
            assert.equal(record.stdout, '');
            assert.equal(record.stderr, '');
            assert.equal(record.sha256, built.sha256);
            const binary = fs.readFileSync(built.path);
            assert.equal(binary.readUInt16LE(binary.readUInt32LE(0x3c) + 4), platform === 'x64' ? 0x8664 : 0x14c);
            assert.equal(fs.readFileSync(response, 'utf8'), '/r:AAA_UNRELATED_DEFAULT_REFERENCE_MUST_NOT_BE_READ.dll\r\n');
        }
        passed = true;
    } finally {
        // 2026-10-22：失败保留控制根和构建回执；成功只清理登记文件和空目录，禁止递归兜底。
        if (passed) {
            for (const directory of outputs) {
                fs.unlinkSync(path.join(directory, 'host-dump-collector.exe'));
                fs.unlinkSync(path.join(directory, 'build.json'));
                fs.rmdirSync(directory);
            }
            for (const file of files) fs.unlinkSync(file);
            for (const directory of directories) fs.rmdirSync(directory);
            for (let directory = compiler; directory !== owned; directory = path.dirname(directory)) fs.rmdirSync(directory);
            fs.rmdirSync(owned);
        } else { console.error('Compiler reference control retained: ' + owned); }
    }
});
