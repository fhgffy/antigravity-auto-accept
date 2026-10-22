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
