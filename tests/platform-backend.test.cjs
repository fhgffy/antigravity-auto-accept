/* 2026-10-14：纯平台分派测试不启动 PowerShell、Python 或桌面应用。 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');
const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'platformBackend.ts'), 'utf8');
const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const exportsObject = {};
vm.runInNewContext(compiled, { exports: exportsObject, require });
const select = exportsObject.selectPlatformBackend;

test('Windows host routing preserves both existing executable names and scanner', () => {
    for (const executable of ['Antigravity.exe', 'Antigravity IDE.exe', 'ANTIGRAVITY.EXE']) {
        const result = select('win32', `C:\\Apps\\${executable}`, true);
        assert.equal(result.kind, 'windows-uia');
        assert.equal(result.script, 'src/autoClicker.ps1');
        assert.equal(result.actionsEnabled, true);
    }
});

test('Linux routing is diagnostic-only and uses exact case-sensitive host names', () => {
    for (const executable of ['/opt/antigravity/antigravity', '/opt/Antigravity IDE/antigravity-ide']) {
        const result = select('linux', executable, true);
        assert.equal(result.kind, 'linux-atspi-diagnostic');
        assert.equal(result.script, 'src/linux/atspi_probe.py');
        assert.equal(result.actionsEnabled, false);
    }
    for (const executable of ['antigravity-ide', '/opt/Antigravity-IDE', '/opt/fake-antigravity', '/opt/code']) {
        assert.equal(select('linux', executable, true).kind, 'unsupported');
    }
});

test('Untrusted, unrelated and unsupported hosts never enable actions', () => {
    for (const [platform, executable, trusted] of [
        ['linux', '/opt/antigravity-ide', false],
        ['win32', 'C:\\Apps\\Antigravity.exe', false],
        ['win32', 'C:\\Apps\\Code.exe', true],
        ['darwin', '/Applications/Antigravity', true],
        ['freebsd', '/opt/antigravity', true],
    ]) {
        const result = select(platform, executable, trusted);
        assert.equal(result.kind, 'unsupported');
        assert.equal(result.actionsEnabled, false);
    }
});
