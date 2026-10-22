/* 2026-10-22：保留原Node测试runner、同步spawn、临时目录规范化和15秒截止时间；结果与本例身份先写独占旁证。 */
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { before, after, test } = require('node:test');

const args = JSON.parse(fs.readFileSync(process.env.AAA_COMPILER_ARGUMENTS, 'utf8'));
const owned = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'AntigravityAA-HostWrapper-')));
const fixture = path.join(owned, 'host-wrapper-output.exe');
fs.writeFileSync(process.env.AAA_COMPILER_IDENTITY + '.tmp', JSON.stringify({
    workerPid: process.pid, parentPid: process.ppid, fixture, owned,
    compiler: args.compiler, source: args.source
}), { encoding: 'utf8', flag: 'wx' });
fs.renameSync(process.env.AAA_COMPILER_IDENTITY + '.tmp', process.env.AAA_COMPILER_IDENTITY); // 2026-10-22：完整身份原子可见，避免观察器读半行JSON。
let result;
before(() => {
    const begin = Date.now();
    // 2026-10-22：诊断探针复用实际构建的精确引用边界，原十五秒期限不变。
    result = spawnSync(args.compiler, ['/nologo', '/noconfig', '/reference:System.dll', '/target:exe', '/codepage:65001', '/platform:anycpu',
        '/out:' + fixture, args.source], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
    fs.writeFileSync(process.env.AAA_COMPILER_RESULT, JSON.stringify({
        nodePid: process.pid, elapsedMs: Date.now() - begin, status: result.status, signal: result.signal,
        error: result.error ? { message: result.error.message, code: result.error.code } : null,
        stdout: result.stdout, stderr: result.stderr
    }), { encoding: 'utf8', flag: 'wx' });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
});
test('original Node compiler startup boundary', () => assert.ok(fs.existsSync(fixture)));
after(() => {
    // 2026-10-22：成功只清理本次登记EXE与空目录；失败保留现场，非递归清理拒绝外来文件。
    if (result && !result.error && result.status === 0) {
        fs.unlinkSync(fixture);
        fs.rmdirSync(owned);
    }
});
