/* 2026-10-07：检查工作区和 CI 检出的真实文件，避免无 BOM 脚本被转码或发布清单与锁文件漂移。 */
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
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
