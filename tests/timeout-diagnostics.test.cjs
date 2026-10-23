const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');

/* 2026-10-23：原生命周期与进程测试完成后执行真实暂存控制，跨根复制只读原件，不提前暖读原冷启动样本。 */
test('owned timeout diagnostics staging preserves bytes and boundaries', { skip: process.platform !== 'win32' }, () => {
    const stageScript = path.join(__dirname, 'stage-owned-timeout-diagnostics.ps1');
    assert.ok(fs.existsSync(stageScript), 'Failure diagnostics need a real single-root staging script');
    const owned = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'AntigravityAA-StageControl-')));
    const registeredFiles = [], registeredDirectories = [], links = [];
    let passed = false;
    const mkdir = directory => { if (!fs.existsSync(directory)) { fs.mkdirSync(directory); registeredDirectories.push(directory); } return directory; };
    const write = (file, bytes) => { fs.writeFileSync(file, bytes); registeredFiles.push(file); };
    const filesBelow = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(item => {
        const file = path.join(directory, item.name); assert.equal(fs.lstatSync(file).isSymbolicLink(), false, 'staged paths cannot be links');
        return item.isDirectory() ? filesBelow(file) : [file];
    });
    const quote = value => "'" + value.replace(/'/g, "''") + "'";
    try {
        for (const engine of ['powershell.exe', 'pwsh.exe']) {
            const base = mkdir(path.join(owned, engine.replace('.exe', '')));
            const runner = mkdir(path.join(base, 'runner')), actual = mkdir(path.join(base, 'default'));
            const profile = mkdir(path.join(base, 'profile')); mkdir(path.join(profile, 'AppData')); mkdir(path.join(profile, 'AppData', 'Local'));
            const profileTemp = mkdir(path.join(profile, 'AppData', 'Local', 'Temp'));
            const roots = [runner, actual, profileTemp], expected = new Map(), originals = new Map();
            for (const [index, directory] of roots.entries()) {
                for (const kind of ['HostBinary', 'HostWrapper', 'ScannerTimeout', 'DumpCollector', 'LifecycleTimeout']) {
                    const parent = mkdir(path.join(directory, 'AntigravityAA-' + kind + '-same'));
                    const nested = mkdir(path.join(parent, 'nested'));
                    for (const [name, bytes] of [['same.bin', Buffer.from([0, 255, index, 13, 10])],
                        ['nested/receipt.json', Buffer.from(JSON.stringify({ source: index, text: '原字节🙂' }) + '\r\n', 'utf8')]]) {
                        const file = path.join(parent, name); write(file, bytes); originals.set(file, bytes);
                        expected.set(path.join('source-' + index, path.basename(parent), name), bytes);
                    }
                }
            }
            const unrelated = mkdir(path.join(runner, 'unrelated')); const nestedOnly = mkdir(path.join(unrelated, 'AntigravityAA-LifecycleTimeout-hidden'));
            write(path.join(nestedOnly, 'excluded.bin'), Buffer.from('unrelated')); const noSuffix = mkdir(path.join(runner, 'AntigravityAA-LifecycleTimeout-'));
            write(path.join(noSuffix, 'excluded.bin'), Buffer.from('no owned suffix'));
            const invoke = (name, runnerRoot = runner, defaultRoot = actual, profileRoot = profile, lockFile) => {
                const output = path.join(base, name + '.outputs'); registeredFiles.push(output);
                // 2026-10-23：只在已启动的受控宿主内改变本例来源变量，不为host启动创建假profile缓存。
                const command = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);"
                    + '$env:USERPROFILE=' + quote(profileRoot) + ';'
                    + (lockFile ? '$held=[IO.File]::Open(' + quote(lockFile) + ',[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);try{' : '')
                    + '$p=' + quote(stageScript) + ";$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($p,[Text.Encoding]::UTF8),$p,[ref]$t,[ref]$e);if($e.Count){throw 'Staging parse failed'};& ($a.GetScriptBlock())" + (lockFile ? '}finally{$held.Dispose()}' : '');
                const result = require('node:child_process').spawnSync(engine,
                    ['-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')],
                    { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 15000,
                        env: { ...process.env, RUNNER_TEMP: runnerRoot, TEMP: defaultRoot, TMP: defaultRoot, GITHUB_OUTPUT: output } });
                assert.ifError(result.error); assert.notEqual(result.status, null, 'staging must finish without the outer timeout');
                const match = fs.readFileSync(output, 'utf8').trim().match(/^path=(.+)$/); assert.ok(match, 'single upload root must be known even on partial failure');
                const destination = fs.realpathSync.native(match[1]); const relative = path.relative(runnerRoot, destination);
                assert.ok(relative && !relative.startsWith('..') && !path.isAbsolute(relative), 'upload root must stay within the selected owned temporary parent');
                registeredDirectories.push(destination);
                const copied = filesBelow(destination); registeredFiles.push(...copied);
                const directories = [];
                const collect = directory => { for (const item of fs.readdirSync(directory, { withFileTypes: true })) if (item.isDirectory()) { const child = path.join(directory, item.name); collect(child); directories.push(child); } };
                collect(destination); registeredDirectories.push(...directories.reverse());
                return { result, destination, copied, receipt: copied.find(file => path.basename(file) === 'staging.json') };
            };
            const normal = invoke('normal'); assert.equal(normal.result.status, 0, normal.result.stderr);
            assert.ok(normal.receipt); const metadata = JSON.parse(fs.readFileSync(normal.receipt, 'utf8')); assert.deepEqual(metadata.Errors, []);
            assert.equal(metadata.FilesCopied, expected.size); assert.equal(metadata.Sources.length, 3);
            const actualFiles = normal.copied.filter(file => file !== normal.receipt);
            assert.equal(actualFiles.length, expected.size);
            for (const file of actualFiles) { const relative = path.relative(normal.destination, file); assert.ok(expected.has(relative), relative); assert.deepEqual(fs.readFileSync(file), expected.get(relative)); }
            for (const [file, bytes] of originals) assert.deepEqual(fs.readFileSync(file), bytes, 'original source files are unchanged');
            const outside = mkdir(path.join(base, 'outside')); const outsideFile = path.join(outside, 'must-not-copy.bin'); write(outsideFile, Buffer.from('outside boundary'));
            const topLink = path.join(runner, 'AntigravityAA-LifecycleTimeout-linked'); fs.symlinkSync(outside, topLink, 'junction'); links.push(topLink);
            const innerLink = path.join(runner, 'AntigravityAA-HostBinary-same', 'linked'); fs.symlinkSync(outside, innerLink, 'junction'); links.push(innerLink);
            const locked = path.join(runner, 'AntigravityAA-HostWrapper-same', 'same.bin');
            const partial = invoke('partial', runner, actual, profile, locked); assert.notEqual(partial.result.status, 0);
            assert.notEqual(partial.destination, normal.destination, 'each staging call owns a fresh root');
            assert.ok(partial.receipt); const partialMetadata = JSON.parse(fs.readFileSync(partial.receipt, 'utf8'));
            assert.ok(partialMetadata.Errors.some(error => /reparse/i.test(error))); assert.ok(partialMetadata.FilesCopied > 0);
            assert.ok(partialMetadata.Errors.some(error => error.includes(locked))); assert.ok(!partial.copied.some(file => file.endsWith('must-not-copy.bin')));
            for (const [file, bytes] of originals) assert.deepEqual(fs.readFileSync(file), bytes); assert.equal(fs.readFileSync(outsideFile, 'utf8'), 'outside boundary');
            const emptyRunner = mkdir(path.join(base, 'empty-runner')), emptyDefault = mkdir(path.join(base, 'empty-default')), emptyProfile = mkdir(path.join(base, 'empty-profile'));
            const empty = invoke('empty', emptyRunner, emptyDefault, emptyProfile); assert.equal(empty.result.status, 0, empty.result.stderr); assert.deepEqual(empty.copied, []);
        }
        passed = true;
    } finally {
        // 2026-10-23：只移除本例登记的链接、文件及空目录；失败保留现场，绝不递归兜底或删原诊断。
        if (passed) {
            for (const link of links) fs.rmdirSync(link);
            for (const file of [...new Set(registeredFiles)]) if (fs.existsSync(file)) fs.unlinkSync(file);
            for (const directory of [...new Set(registeredDirectories)].sort((a, b) => b.length - a.length)) if (fs.existsSync(directory)) fs.rmdirSync(directory);
            fs.rmdirSync(owned);
        } else { console.error('Owned staging control retained: ' + owned); }
    }
});

