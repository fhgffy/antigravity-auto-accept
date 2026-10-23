/* 2026-10-23：执行原生命周期case30回调的纯Node VM控制，不启动WinPS、CLR或扫描器。 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const lifecycleSource = fs.readFileSync(path.join(__dirname, 'extension.test.cjs'), 'utf8');
const selectedKey = 'COMPLUS_DisableNativeImageLoadList';
const success = Object.freeze({ pid: 4516, status: 0, signal: null, stdout: '___SELFTEST_DONE___:passed=87\r\n', stderr: '' });

/* 2026-10-23：只替代系统调用和失败落盘；命令生成、环境选择、四项断言及原异常均来自现有真实回调。 */
function captureCase(variables, result = success, writeFailure) {
    const callbacks = [], calls = [], writes = [], errors = [], assertionErrors = [], assertions = [], directories = [];
    const env = Object.freeze({ SENTINEL: 'unchanged', ...variables });
    const before = JSON.stringify(env), realBefore = Object.entries(process.env);
    const checkedAssert = new Proxy(assert, { get(target, name) {
        const original = target[name];
        return ['ifError', 'equal', 'match'].includes(name) ? (...values) => {
            assertions.push(name);
            try { return original(...values); } catch (error) { assertionErrors.push(error); throw error; }
        } : original;
    } });
    let ticks = 0n, thrown;
    const modules = {
        'node:assert/strict': checkedAssert,
        'node:test': (name, options, callback) => callbacks.push({ name, callback: callback || options }),
        'node:child_process': { spawnSync: (command, args, options) => { calls.push({ command, args, options }); return result; } },
        'node:fs': { ...fs,
            mkdtempSync(prefix) { directories.push(prefix); if (writeFailure === 'directory') throw new Error('owned diagnostic directory rejected'); return prefix + 'owned'; },
            writeFileSync(file, data, encoding) { if (writeFailure === 'write-' + writes.length) throw new Error('owned diagnostic write rejected'); writes.push({ file, data, encoding }); },
        },
    };
    vm.runInNewContext(lifecycleSource, {
        require: name => Object.hasOwn(modules, name) ? modules[name] : require(name),
        __dirname, Buffer, process: { platform: 'win32', env, hrtime: { bigint: () => { ticks += 1250000000n; return ticks; } } },
        console: { error: (...values) => errors.push(values) },
    }, { filename: 'extension.test.cjs', timeout: 5000 });
    const original = callbacks.filter(item => item.name === '真实 PowerShell 启动协议通过扫描器自测且 stderr 为空');
    assert.equal(original.length, 1);
    try { original[0].callback(); } catch (error) { thrown = error; }
    assert.equal(calls.length, 1);
    assert.equal(calls[0].command, 'powershell.exe');
    assert.deepEqual(Array.from(calls[0].args).slice(0, 7), ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-ExecutionPolicy', 'Bypass', '-EncodedCommand']);
    assert.equal(calls[0].args.length, 8);
    assert.match(Buffer.from(calls[0].args[7], 'base64').toString('utf16le'), / -SelfTest$/);
    assert.equal(calls[0].options.timeout, 20000); assert.equal(calls[0].options.windowsHide, true); assert.equal(calls[0].options.encoding, 'utf8');
    assert.equal(JSON.stringify(env), before); assert.deepEqual(Object.entries(process.env), realBefore);
    return { env, calls, writes, errors, assertions, assertionErrors, directories, thrown };
}

test('exact GitHub-hosted case30 selects only the copied child SMA setting', () => {
    const parent = { GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'github-hosted', COMPLUS_DISABLENATIVEIMAGELOADLIST: 'old-a', COMPlus_DisableNativeImageLoadList: 'old-b', COMPLUS_ZapDisable: '0', COMPLUS_ReadyToRun: '1', UNRELATED: 'retained' };
    const actual = captureCase(parent), options = actual.calls[0].options;
    assert.equal(actual.thrown, undefined); assert.ok(Object.hasOwn(options, 'env'), 'hosted real callback needs one child-only environment');
    assert.notEqual(options.env, actual.env);
    assert.deepEqual(Object.entries(options.env).filter(([name]) => name.toLowerCase() === selectedKey.toLowerCase()), [[selectedKey, 'System.Management.Automation']]);
    const expected = { ...actual.env }; for (const name of Object.keys(expected)) if (name.toLowerCase() === selectedKey.toLowerCase()) delete expected[name]; expected[selectedKey] = 'System.Management.Automation';
    assert.deepEqual(JSON.parse(JSON.stringify(options.env)), expected);
    assert.deepEqual(Object.keys(options).sort(), ['encoding', 'env', 'timeout', 'windowsHide']);
    const ordinary = captureCase({}); assert.deepEqual(Array.from(actual.calls[0].args), Array.from(ordinary.calls[0].args));
    assert.deepEqual(actual.assertions, ['ifError', 'equal', 'match', 'equal']); assert.deepEqual(actual.writes, []); assert.deepEqual(actual.errors, []);
});

test('local self-hosted and non-exact values keep all original options without env', () => {
    for (const variables of [{}, { GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'self-hosted' }, { GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted' },
        { GITHUB_ACTIONS: 'TRUE', RUNNER_ENVIRONMENT: 'github-hosted' }, { GITHUB_ACTIONS: 'True', RUNNER_ENVIRONMENT: 'github-hosted' },
        { GITHUB_ACTIONS: 'true ', RUNNER_ENVIRONMENT: 'github-hosted' }, { GITHUB_ACTIONS: true, RUNNER_ENVIRONMENT: 'github-hosted' },
        { GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'GitHub-hosted' }, { GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'github-hosted ' },
        { GITHUB_ACTIONS: 'true' }, { RUNNER_ENVIRONMENT: 'github-hosted' }, { COMPLUS_DisableNativeImageLoadList: 'original-local-setting' }]) {
        const actual = captureCase(variables);
        assert.equal(actual.thrown, undefined); assert.equal(Object.hasOwn(actual.calls[0].options, 'env'), false);
        assert.deepEqual(JSON.parse(JSON.stringify(actual.calls[0].options)), { windowsHide: true, encoding: 'utf8', timeout: 20000 });
        assert.deepEqual(actual.writes, []); assert.deepEqual(actual.errors, []);
    }
});

test('hosted original error status marker and stderr assertions still fail and retain their result', () => {
    const timeout = Object.assign(new Error('spawnSync powershell.exe ETIMEDOUT'), { code: 'ETIMEDOUT', errno: -4039, syscall: 'spawnSync powershell.exe', path: 'powershell.exe' });
    for (const result of [{ ...success, error: timeout, status: null, signal: 'SIGTERM', stdout: '部分输出🙂\r\n', stderr: '原错误🚩\n' },
        { ...success, status: 3 }, { ...success, stdout: 'missing done\n' }, { ...success, stderr: 'original stderr\n' }]) {
        const actual = captureCase({ GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'github-hosted', RUNNER_TEMP: 'F:/owned-only' }, result);
        assert.ok(actual.thrown); assert.equal(actual.thrown, actual.assertionErrors[0]); assert.equal(actual.writes.length, 3);
        const byName = Object.fromEntries(actual.writes.map(item => [path.basename(item.file), item]));
        const receipt = JSON.parse(byName['receipt.json'].data);
        assert.equal(receipt.DurationMs, 1250); assert.equal(receipt.Pid, result.pid); assert.equal(receipt.Status, result.status); assert.equal(receipt.Signal, result.signal);
        assert.equal(receipt.Stdout, result.stdout); assert.equal(receipt.Stderr, result.stderr); assert.equal(receipt.PreKillCapture, false); assert.equal(receipt.StreamsAreNodeDecodedUtf8, true);
        assert.deepEqual(receipt.Args, Array.from(actual.calls[0].args));
        assert.equal(byName['stdout.log'].data, result.stdout); assert.equal(byName['stderr.log'].data, result.stderr);
        assert.deepEqual(receipt.Error, result.error ? Object.fromEntries(['name', 'message', 'stack', 'code', 'errno', 'syscall', 'path'].map(name => [name, result.error[name] ?? null])) : null);
        assert.deepEqual(actual.errors, []);
    }
});

test('hosted diagnostic directory or stream write failure preserves the identical original assertion', () => {
    for (const stage of ['directory', 'write-0', 'write-1', 'write-2']) {
        const actual = captureCase({ GITHUB_ACTIONS: 'true', RUNNER_ENVIRONMENT: 'github-hosted' }, { ...success, status: 1, stderr: 'original failure' }, stage);
        assert.ok(actual.thrown); assert.equal(actual.thrown, actual.assertionErrors[0]); assert.equal(actual.errors.length, 1);
        assert.match(actual.errors[0].join(' '), /Lifecycle failure evidence could not be written/);
        assert.equal(actual.writes.length, stage === 'directory' ? 0 : Number(stage.slice(-1)));
    }
});
