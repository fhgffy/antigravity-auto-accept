/* 2026-10-05：在隔离宿主中复现子进程异步事件，验证真实扩展入口的生命周期与执行边界。 */
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { PassThrough } = require('node:stream');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');

const sourcePath = process.env.EXTENSION_SOURCE_PATH || path.join(__dirname, '..', 'src', 'extension.ts');
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;

/* 2026-10-05：仅替代不可在 Node 中加载的 IDE 与进程依赖，命令、事件和状态变更均由生产源码执行。 */
function createHarness(options = {}) {
    const commands = new Map();
    const timers = new Map();
    const children = [];
    const logs = [];
    const errors = [];
    const info = [];
    let nextTimer = 1;
    let configListener;
    let trustListener;
    const config = { autoStart: true, ...(options.config || {}) };
    const status = { show() {}, dispose() {} };
    const output = { appendLine: line => logs.push(line), show() {}, dispose() {} };
    const workspace = {
        isTrusted: options.trusted ?? true,
        getConfiguration: () => ({ get: (key, fallback) => config[key] ?? fallback }),
        onDidChangeConfiguration: listener => {
            configListener = listener;
            return { dispose() {} };
        },
        onDidGrantWorkspaceTrust: listener => {
            trustListener = listener;
            return { dispose() {} };
        },
    };
    const vscode = {
        workspace,
        env: { appName: options.appName || 'Antigravity' },
        StatusBarAlignment: { Right: 2 },
        ThemeColor: class { constructor(id) { this.id = id; } },
        window: {
            createOutputChannel: () => output,
            createStatusBarItem: () => status,
            showErrorMessage: message => errors.push(message),
            showInformationMessage: message => info.push(message),
        },
        commands: {
            registerCommand: (name, callback) => {
                commands.set(name, callback);
                return { dispose() {} };
            },
        },
    };
    const fakeProcess = {
        platform: options.platform || 'win32',
        execPath: options.execPath || 'F:\\Antigravity IDE\\Antigravity IDE.exe',
        pid: 4321,
    };
    const childProcess = {
        spawn: (command, args, spawnOptions) => {
            if (options.spawnThrows) { throw new Error('spawn rejected'); }
            const child = new EventEmitter();
            child.stdout = new PassThrough();
            child.stderr = new PassThrough();
            child.killCalls = 0;
            child.kill = () => { child.killCalls++; return true; };
            children.push({ child, command, args, options: spawnOptions });
            return child;
        },
    };
    const exports = {};
    const sandbox = {
        exports,
        process: fakeProcess,
        Buffer,
        setTimeout: (callback, delay) => {
            const id = nextTimer++;
            timers.set(id, { callback, delay });
            return id;
        },
        clearTimeout: id => timers.delete(id),
        require: name => {
            if (name === 'vscode') { return vscode; }
            if (name === 'child_process') { return childProcess; }
            if (name === 'fs') { return { existsSync: () => options.scriptExists ?? true }; }
            return require(name);
        },
    };
    vm.runInNewContext(compiled, sandbox, { filename: sourcePath });
    exports.activate({ subscriptions: [], asAbsolutePath: relative => path.join(__dirname, '..', relative) });
    return {
        children, logs, errors, info, status, timers, exports, fakeProcess,
        command: name => commands.get(`antigravity-auto-accept.${name}`)(),
        flushTimers: () => {
            const pending = Array.from(timers.entries());
            for (const [id, timer] of pending) {
                if (!timers.has(id)) { continue; }
                timers.delete(id);
                timer.callback();
            }
        },
        changeConfig: (changes, relevant = true) => {
            Object.assign(config, changes);
            configListener({ affectsConfiguration: () => relevant });
        },
        grantTrust: () => { workspace.isTrusted = true; trustListener?.(); },
    };
}

/* 2026-10-05：解码真实 PowerShell 启动命令，以验证 UTF-8 脚本加载与参数传递而不依赖命令行形式。 */
function getScannerCommand(spawned) {
    const encodedIndex = spawned.args.indexOf('-EncodedCommand');
    if (encodedIndex !== -1) {
        return Buffer.from(spawned.args[encodedIndex + 1], 'base64').toString('utf16le');
    }
    return spawned.args.join(' ');
}

/* 2026-10-05：宿主名称只用于展示，启动必须服从真实可执行文件、平台与工作区信任边界。 */
test('支持两代 Antigravity 可执行文件并传递父进程身份', () => {
    for (const executable of ['Antigravity.exe', 'Antigravity IDE.exe', 'ANTIGRAVITY.EXE']) {
        const harness = createHarness({ execPath: `F:\\IDE\\${executable}` });
        assert.equal(harness.children.length, 1);
        const spawned = harness.children[0];
        const scannerCommand = getScannerCommand(spawned);
        assert.match(scannerCommand, /-ParentProcessId 4321\b/);
        assert.equal(scannerCommand.includes(`-HostExecutablePath 'F:\\IDE\\${executable}'`), true);
        assert.match(scannerCommand, /ReadAllText\(.*\[Text.Encoding\]::UTF8/);
        assert.equal(spawned.options.windowsHide, true);
    }
});

test('包含单引号和美元符号的安装路径保持为字面量参数', () => {
    const harness = createHarness({ execPath: "F:\\O'Brien $IDE\\Antigravity.exe" });
    assert.equal(getScannerCommand(harness.children[0]).includes("-HostExecutablePath 'F:\\O''Brien $IDE\\Antigravity.exe'"), true);
});

test('其他 IDE 与非 Windows 平台不会启动扫描器', () => {
    for (const options of [
        { execPath: 'F:\\VSCode\\Code.exe' },
        { execPath: 'F:\\VSCode\\Code - Insiders.exe', appName: 'Antigravity' },
        { execPath: 'F:\\IDE\\FakeAntigravity.exe' },
        { platform: 'linux' },
        { platform: 'darwin' },
    ]) {
        const harness = createHarness(options);
        harness.command('start');
        harness.command('restart');
        harness.command('toggle');
        harness.flushTimers();
        assert.equal(harness.children.length, 0);
        assert.match(harness.status.text, /OFF/);
    }
});

test('未信任工作区阻止所有启动入口，授予信任后自动启动', () => {
    const harness = createHarness({ trusted: false });
    for (const command of ['start', 'restart', 'toggle']) { harness.command(command); }
    harness.changeConfig({ pollMs: 800 });
    harness.flushTimers();
    assert.equal(harness.children.length, 0);
    assert.match(harness.status.text, /OFF/);
    harness.grantTrust();
    assert.equal(harness.children.length, 1);
});

/* 2026-10-05：模拟旧进程在新进程启动后才结束，验证退出、错误与输出均不能污染新会话。 */
test('停止再启动后，旧 exit 不会丢失新 child', () => {
    const harness = createHarness();
    const first = harness.children[0].child;
    harness.command('stop');
    harness.command('start');
    const second = harness.children[1].child;
    first.emit('exit', 0);
    harness.command('stop');
    assert.equal(first.killCalls, 1);
    assert.equal(second.killCalls, 1);
    assert.equal(harness.timers.size, 0);
});

test('旧 error 不会关闭新扫描器或显示过期错误', () => {
    const harness = createHarness();
    const first = harness.children[0].child;
    harness.command('stop');
    harness.command('start');
    first.emit('error', new Error('stale failure'));
    harness.children[1].child.stdout.emit('data', Buffer.from('___AUTOCLICK_READY___\n'));
    assert.equal(harness.errors.length, 0);
    assert.match(harness.status.text, /ON/);
    harness.command('stop');
    assert.equal(harness.children[1].child.killCalls, 1);
});

test('新进程独享 stdout 缓冲区，旧 stdout 与 stderr 被忽略', () => {
    const harness = createHarness();
    const first = harness.children[0].child;
    first.stdout.emit('data', Buffer.from('___CLICK_INVOKE___:OLD'));
    harness.command('stop');
    harness.command('start');
    first.stdout.emit('data', Buffer.from('___CLICK_PHYSICAL___:STALE\n'));
    first.stderr.emit('data', Buffer.from('stale stderr'));
    const second = harness.children[1].child;
    second.stdout.emit('data', Buffer.from('___AUTOCLICK_READY___\n'));
    assert.equal(harness.logs.some(line => /OLD|STALE|stale stderr/.test(line)), false);
    assert.match(harness.status.text, /ON/);
});

test('中文按钮名跨 UTF-8 字节边界传输仍保持完整', () => {
    const harness = createHarness();
    const bytes = Buffer.from('___CLICK_INVOKE___:允许执行\n');
    const split = Buffer.from('___CLICK_INVOKE___:').length + 1;
    harness.children[0].child.stdout.write(bytes.subarray(0, split));
    harness.children[0].child.stdout.write(bytes.subarray(split));
    assert.equal(harness.logs.some(line => line.includes('允许执行')), true);
    assert.equal(harness.logs.some(line => line.includes('�')), false);
});

/* 2026-10-05：重启计时器必须只有一个所有者，用户停止或扩展卸载后不得残留后台重试。 */
test('异常退出会延迟重启并在 READY 前显示重启状态', () => {
    const harness = createHarness();
    harness.children[0].child.stdout.emit('data', Buffer.from('___AUTOCLICK_READY___\n'));
    harness.children[0].child.emit('exit', 1);
    assert.equal(harness.timers.size, 1);
    assert.match(harness.status.text, /RETRYING/);
    harness.flushTimers();
    assert.equal(harness.children.length, 2);
    assert.match(harness.status.text, /STARTING/);
});

test('停止命令取消异常退出后的重启计时器', () => {
    const harness = createHarness();
    harness.children[0].child.emit('exit', 1);
    harness.command('stop');
    assert.equal(harness.timers.size, 0);
    harness.flushTimers();
    assert.equal(harness.children.length, 1);
    assert.match(harness.status.text, /OFF/);
});

test('连续配置修改合并为一次重启，旧 exit 不追加计时器', () => {
    const harness = createHarness();
    const first = harness.children[0].child;
    harness.changeConfig({ pollMs: 700 });
    harness.changeConfig({ pollMs: 900 });
    first.emit('exit', 0);
    assert.equal(harness.timers.size, 1);
    harness.flushTimers();
    assert.equal(harness.children.length, 2);
    assert.match(getScannerCommand(harness.children[1]), /-PollMs 900\b/);
});

test('卸载取消重启并忽略随后到达的退出和命令', () => {
    const harness = createHarness();
    const first = harness.children[0].child;
    harness.command('restart');
    harness.exports.deactivate();
    first.emit('exit', 0);
    assert.equal(harness.timers.size, 0);
    harness.command('start');
    harness.flushTimers();
    assert.equal(harness.children.length, 1);
});

/* 2026-10-05：状态栏展示扫描器实际就绪状态；旧协议竞争退出仍须重试接管。 */
test('分段 READY、WAITING 与点击协议正确更新状态和日志', () => {
    const harness = createHarness();
    const child = harness.children[0].child;
    assert.match(harness.status.text, /STARTING/);
    child.stdout.emit('data', Buffer.from('___SCANNER_WAITING___\n'));
    assert.match(harness.status.text, /WAITING/);
    child.stdout.emit('data', Buffer.from('___AUTOCLICK_'));
    assert.match(harness.status.text, /WAITING/);
    child.stdout.emit('data', Buffer.from('READY___\r\n___CLICK_INVOKE___:Run\n___CLICK_PHYSICAL___:Accept\n'));
    assert.match(harness.status.text, /ON/);
    assert.equal(harness.logs.some(line => /Auto-accepted \(Invoke\).*Run/.test(line)), true);
    assert.equal(harness.logs.some(line => /Auto-accepted \(Physical\).*Accept/.test(line)), true);
});

test('旧 ALREADY_RUNNING 协议不会永久放弃接管', () => {
    const harness = createHarness();
    const child = harness.children[0].child;
    child.stdout.emit('data', Buffer.from('___ALREADY_RUNNING___\n'));
    assert.match(harness.status.text, /WAITING/);
    child.emit('exit', 0);
    assert.equal(harness.timers.size, 1);
    harness.flushTimers();
    assert.equal(harness.children.length, 2);
});

test('异步 spawn error 关闭状态且不自动无限重试', () => {
    const harness = createHarness();
    const child = harness.children[0].child;
    child.emit('error', new Error('ENOENT'));
    child.emit('exit', -1);
    assert.equal(harness.errors.length, 1);
    assert.match(harness.status.text, /OFF/);
    assert.equal(harness.timers.size, 0);
    harness.command('start');
    assert.equal(harness.children.length, 2);
});

test('同步 spawn 异常能报告失败且不会逃逸激活入口', () => {
    const harness = createHarness({ spawnThrows: true });
    assert.equal(harness.errors.length, 1);
    assert.match(harness.status.text, /OFF/);
    assert.equal(harness.timers.size, 0);
});

test('启动被边界检查拒绝时不会发送成功通知', () => {
    const harness = createHarness({ trusted: false, config: { showNotifications: true } });
    harness.command('start');
    harness.command('toggle');
    harness.command('restart');
    assert.equal(harness.info.length, 0);
    assert.equal(harness.children.length, 0);
});

test('扫描脚本缺失时关闭状态并说明包装错误', () => {
    const harness = createHarness({ scriptExists: false });
    assert.equal(harness.children.length, 0);
    assert.equal(harness.errors.length, 1);
    assert.match(harness.status.text, /OFF/);
});

test('禁用自动启动仍可手动启动，无关配置不会重启', () => {
    const harness = createHarness({ config: { autoStart: false } });
    assert.equal(harness.children.length, 0);
    harness.command('start');
    assert.equal(harness.children.length, 1);
    harness.changeConfig({}, false);
    assert.equal(harness.timers.size, 0);
    assert.equal(harness.children[0].child.killCalls, 0);
});

/* 2026-10-05：执行扩展实际生成的启动命令，仅增加无点击自测开关，验证 Windows PowerShell 的编码与完整参数协议。 */
test('真实 PowerShell 启动协议通过扫描器自测且 stderr 为空', { skip: process.platform !== 'win32' }, () => {
    const harness = createHarness();
    const spawned = harness.children[0];
    const args = spawned.args.slice();
    const encodedIndex = args.indexOf('-EncodedCommand');
    assert.notEqual(encodedIndex, -1);
    args[encodedIndex + 1] = Buffer.from(`${getScannerCommand(spawned)} -SelfTest`, 'utf16le').toString('base64');
    const result = require('node:child_process').spawnSync(spawned.command, args, {
        windowsHide: true,
        encoding: 'utf8',
        timeout: 20000,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /___SELFTEST_DONE___:passed=[1-9][0-9]*/);
    assert.equal(result.stderr, '');
});
