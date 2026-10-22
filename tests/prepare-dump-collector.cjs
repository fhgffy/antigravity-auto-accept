/* 2026-10-22：在被测进程启动前编译独立x64取证器，失败路径不再依赖另一轮PowerShell启动和现场编译。 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
// 2026-10-22：仅明确x86参数选择同位数工具，仍由64位编译器准备，目标开始前不运行32位进程。
if (process.argv.length > 3 || (process.argv[2] && process.argv[2] !== '--x86')) throw new Error('Unexpected owned collector architecture argument');
const platform = process.argv[2] === '--x86' ? 'x86' : 'x64';
const directory = path.join(fs.realpathSync.native(os.tmpdir()), 'AntigravityAA-DumpCollector-' + crypto.randomUUID().replace(/-/g, ''));
fs.mkdirSync(directory);
const executable = path.join(directory, 'host-dump-collector.exe');
const compiler = path.join(process.env.WINDIR, 'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
const sources = ['host-child-diagnostics.cs', 'host-dump-collector.cs'].map(name => path.join(__dirname, 'fixtures', name));
const sourceHashes = Object.fromEntries(sources.map(file => [path.basename(file), crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
const result = spawnSync(compiler, ['/nologo', '/target:exe', '/codepage:65001', '/platform:' + platform, ...(platform === 'x86' ? ['/define:OWNED_X86_COLLECTOR'] : []), '/out:' + executable, ...sources],
    { encoding: 'utf8', windowsHide: true, timeout: 15000 });
const record = { compiler, sources: sourceHashes, platform, path: executable, status: result.status, signal: result.signal,
    error: result.error ? { code: result.error.code, message: result.error.message } : null, stdout: result.stdout, stderr: result.stderr };
if (!result.error && result.status === 0 && result.stderr.length === 0) {
    record.sha256 = crypto.createHash('sha256').update(fs.readFileSync(executable)).digest('hex');
} else { process.exitCode = 1; }
fs.writeFileSync(path.join(directory, 'build.json'), JSON.stringify(record, null, 2) + '\r\n', 'utf8');
if (process.exitCode) { console.error(JSON.stringify(record)); }
else { console.log(JSON.stringify({ path: executable, sha256: record.sha256 })); }
