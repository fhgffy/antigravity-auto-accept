/* 2026-10-23：捕获当前宿主文件真实回调，替换进程与文件边界；不执行before/after、编译或系统信号。 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const { EventEmitter } = require('node:events');
const callbackName = 'cleanup rejects a mismatched creation identity before stopping a live target';
const flush = async () => { for (let index = 0; index < 24; index++) await Promise.resolve(); };

module.exports = async function verifyCleanupControl(sourcePath) {
    const source = fs.readFileSync(sourcePath, 'utf8');
    const specs = [
        { name: 'normal-close', kill: 'true-close', expected: 'fulfilled' },
        { name: 'false-with-close-race', kill: 'false-close', expected: 'fulfilled' },
        { name: 'false-no-close', kill: 'false-no-close', expected: 'close-timeout' },
        { name: 'true-no-close', kill: 'true-no-close', expected: 'close-timeout' },
        { name: 'original-failure-close', kill: 'true-close', original: true, expected: 'original' },
        { name: 'original-failure-no-close', kill: 'false-no-close', original: true, expected: 'original' },
        { name: 'kill-throw', kill: 'throw', expected: 'kill-error' },
        { name: 'kill-throw-original-first', kill: 'throw', original: true, expected: 'original' },
        { name: 'report-console-fail-original-first', kill: 'false-no-close', original: true, reportThrows: true, expected: 'original' },
        { name: 'report-console-fail-cleanup-fails', kill: 'false-no-close', reportThrows: true, expected: 'close-timeout' },
        { name: 'ready-timeout-original-first', kill: 'false-no-close', noReady: true, expected: 'ready-timeout' },
        { name: 'async-error-no-close', kill: 'async-no-close', expected: 'async-error' },
        { name: 'async-error-close', kill: 'async-close', expected: 'async-error' },
        { name: 'async-error-original-first', kill: 'async-no-close', original: true, expected: 'original' },
        { name: 'consumed-ready-error-late-error-guard', kill: 'async-no-close', readyError: true, expected: 'ready-error' },
    ];
    const results = [];
    const references = [];
    let completed = false;
    try {
        for (const spec of specs) {
            const record = { Name: spec.name, Events: [], TimerBudgets: [], Reports: [], EmissionErrors: [] };
            const child = new EventEmitter(); child.pid = 987654321; child.exitCode = null;
            const childReference = setInterval(() => {}, 1000), pipes = [];
            references.push(childReference);
            const emitError = error => { try { child.emit('error', error); } catch (emission) { record.EmissionErrors.push(emission.message); } };
            const readyError = new Error('CONTROL_READY_ERROR'), asyncError = new Error('CONTROL_CLEANUP_ASYNC_ERROR');
            child.unref = () => { record.Events.push('child-unref'); childReference.unref(); };
            for (const name of ['stdout', 'stderr']) {
                const stream = new EventEmitter(), reference = setInterval(() => {}, 1000);
                references.push(reference);
                pipes.push(reference); child[name] = stream;
                stream.destroy = () => { record.Events.push(name + '-destroy'); clearInterval(reference); stream.emit('error', new Error('CONTROL_STREAM_RELEASE_ERROR')); };
            }
            child.kill = () => {
                record.Events.push('same-child-kill');
                if (spec.kill === 'throw') throw new Error('CONTROL_KILL_THROW');
                if (spec.kill.startsWith('async')) queueMicrotask(() => emitError(asyncError));
                if (spec.kill.endsWith('-close') && !spec.kill.endsWith('-no-close')) queueMicrotask(() => {
                    record.Events.push('same-child-close'); clearInterval(childReference); pipes.forEach(clearInterval); child.emit('close', null, 'SIGTERM');
                });
                return spec.kill.startsWith('true') || spec.kill.startsWith('async');
            };
            let now = 0, serial = 0, originalFailure, actualError, state = 'unsettled';
            const timers = new Map(), callbacks = [];
            const trackedAssert = Object.create(assert);
            trackedAssert.doesNotThrow = (...args) => { try { return assert.doesNotThrow(...args); } catch (error) { originalFailure = error; throw error; } };
            const fakeOwned = path.join(path.dirname(sourcePath), 'virtual-cleanup-only');
            const context = {
                __dirname: path.dirname(sourcePath), __filename: sourcePath, Buffer, Promise, Error,
                process: { env: { WINDIR: 'C:\\Windows' }, platform: process.platform, execPath: process.execPath,
                    kill: (pid, signal) => { assert.equal(pid, child.pid); assert.equal(signal, 0); if (spec.original) throw new Error('CONTROL_ORIGINAL_FAILURE'); return true; } },
                console: { error: () => { if (spec.reportThrows) throw new Error('CONTROL_CONSOLE_FAILURE'); } },
                setTimeout: (fn, ms) => { assert.equal(ms, 5000); const id = ++serial; timers.set(id, { fn, due: now + ms }); record.TimerBudgets.push(ms); return id; },
                clearTimeout: id => timers.delete(id),
            };
            const fakeFs = {
                mkdtempSync: () => fakeOwned, realpathSync: { native: value => value }, copyFileSync: () => {},
                writeFileSync: (file, text) => { record.Events.push('report-attempt'); if (spec.reportThrows) throw new Error('CONTROL_REPORT_FAILURE'); assert.equal(file, path.join(fakeOwned, 'cleanup-identity-control.cleanup.json')); record.Reports.push(JSON.parse(text)); },
            };
            const childProcesses = {
                spawnSync: () => { throw new Error('Unexpected real-wrapper or compiler boundary in pure cleanup control'); },
                spawn: () => {
                    record.Events.push('spawn-stub');
                    queueMicrotask(() => { if (spec.readyError) emitError(readyError); else if (!spec.noReady) child.stdout.emit('data', Buffer.from('HOST_WRAPPER_STDOUT:control')); });
                    return child;
                },
            };
            const modules = { 'node:assert/strict': trackedAssert, 'node:child_process': childProcesses, 'node:fs': fakeFs,
                'node:os': { tmpdir: () => path.dirname(sourcePath) }, 'node:path': path,
                'node:test': { test: (name, ...args) => callbacks.push({ name, callback: args.at(-1) }), before: () => {}, after: () => {} } };
            context.require = name => { assert.ok(Object.hasOwn(modules, name), 'Unexpected captured source dependency: ' + name); return modules[name]; };
            const sandbox = vm.createContext(context);
            vm.runInContext(source, sandbox, { filename: sourcePath, timeout: 1000 });
            const selected = callbacks.filter(item => item.name === callbackName);
            assert.equal(selected.length, 1, 'Capture one actual cleanup callback');
            /* 2026-10-23：身份拒绝保持原三个断言；仅替代会启动外部进程的既有负例工具边界。 */
            context.stopOwnedFixture = (pid, image, ticks) => { if (ticks === undefined) throw new Error('Shared process creation identity required'); assert.equal(ticks, '1'); throw new Error('Owned fixture creation time mismatch'); };
            const advance = async delta => { now += delta; for (const [id, timer] of [...timers]) if (timer.due <= now) { timers.delete(id); timer.fn(); } await flush(); };
            const pending = selected[0].callback().then(() => { state = 'fulfilled'; }, error => { actualError = error; state = 'rejected'; });
            await flush();
            if (spec.noReady) {
                await advance(4999); assert.equal(state, 'unsettled'); assert.ok(!record.Events.includes('same-child-kill'));
                await advance(1); assert.ok(record.Events.includes('same-child-kill'));
            }
            const expectsClose = spec.kill.endsWith('-close') && !spec.kill.endsWith('-no-close');
            if (!expectsClose) {
                assert.equal(state, 'unsettled'); await advance(4999); assert.equal(state, 'unsettled');
                record.UnsettledAtCleanup4999 = true; await advance(1); assert.equal(state, 'rejected');
            }
            await pending;
            record.VirtualElapsedMs = now; record.KeepArtifacts = vm.runInContext('keepArtifacts', sandbox);
            record.ActualError = actualError ? actualError.message : null;
            record.OriginalErrorIdentityPreserved = originalFailure !== undefined && originalFailure === actualError;
            assert.deepEqual(record.TimerBudgets, [5000, 5000]); assert.equal(timers.size, 0);
            if (spec.expected === 'fulfilled') { assert.equal(state, 'fulfilled'); assert.equal(record.KeepArtifacts, false); assert.equal(record.Reports.length, 0); }
            else {
                assert.equal(state, 'rejected'); assert.equal(record.KeepArtifacts, true);
                if (spec.expected === 'original') assert.ok(record.OriginalErrorIdentityPreserved, 'Original assertion object must remain primary');
                else if (spec.expected === 'ready-error') assert.equal(actualError, readyError);
                else assert.equal(actualError.message, { 'close-timeout': 'Owned identity control close timeout', 'ready-timeout': 'Owned identity control readiness timeout', 'kill-error': 'CONTROL_KILL_THROW', 'async-error': 'CONTROL_CLEANUP_ASYNC_ERROR' }[spec.expected]);
                const cleanupFailed = !expectsClose || spec.kill.startsWith('async');
                if (cleanupFailed) {
                    assert.ok(record.Events.includes('stdout-destroy') && record.Events.includes('stderr-destroy') && record.Events.includes('child-unref'), 'Cleanup failure must release own refs');
                    if (!spec.reportThrows) { assert.equal(record.Reports.length, 1); assert.equal(record.Reports[0].ExitConfirmed, expectsClose); }
                } else { assert.ok(record.Events.includes('same-child-close')); assert.equal(record.Reports.length, 0); }
            }
            if (spec.kill.startsWith('async') && !spec.reportThrows) assert.equal(record.Reports[0].Error, 'CONTROL_CLEANUP_ASYNC_ERROR', 'Asynchronous child error must not be replaced by timeout');
            if (!expectsClose) emitError(new Error('CONTROL_LATE_ERROR'));
            assert.deepEqual(record.EmissionErrors, [], 'Late child errors must retain a safe listener');
            record.ExpectedOutcomeConfirmed = true;
            results.push(record);
        }
        completed = true;
        return { SourceSHA256: crypto.createHash('sha256').update(source).digest('hex'), Cases: results, NoOSChildTarget: true, ActualSourceCallbackCaptured: true };
    } finally {
        // 2026-10-23：断言已失败才释放测试替身自身引用，避免回归失败拖住Node；成功路径仍由真实回调释放。
        if (!completed) references.forEach(clearInterval);
    }
};

/* 2026-10-23：私有或focused入口直接跑同一聚合回归，避免执行宿主文件全局before的真实编译。 */
if (require.main === module) {
    module.exports(path.resolve(process.argv[2] || path.join(__dirname, '..', 'host-wrapper.test.cjs')))
        .then(result => console.log(JSON.stringify(result)))
        .catch(error => { console.error(error.stack); process.exitCode = 1; });
}
