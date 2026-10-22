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
