import * as vscode from 'vscode';
import * as path from 'path';
import * as child_process from 'child_process';
import * as fs from 'fs';
import { selectPlatformBackend } from './platformBackend';

// 2026-03-29 v5.1.0 UIAutomation架构 — 从CDP回归UIAutomation直接按钮检测 //***
// UIAutomation能看到Antigravity的"Run"/"Accept"等按钮并支持InvokePattern，无需CDP端口

let isEnabled = false;
let statusBarItem: vscode.StatusBarItem;
let outputChannel: vscode.OutputChannel;
let psProcess: child_process.ChildProcess | undefined;
let extensionContext: vscode.ExtensionContext;
/* 2026-10-05：扫描会话拥有独立状态与可取消重启，避免旧进程事件污染新实例。 */
let isActive = false;
let restartTimer: ReturnType<typeof setTimeout> | undefined;
let scannerState: 'starting' | 'waiting' | 'ready' | 'retrying' | 'diagnostic' | 'stopping' | undefined;
let diagnosticTimer: ReturnType<typeof setTimeout> | undefined;
let diagnosticKillTimer: ReturnType<typeof setTimeout> | undefined;
let linuxDiagnosticStop: ((message: string) => void) | undefined;
let linuxRestartRequested = false;
let startAfterTrust = false; // 2026-10-07：用户停止时取消尚未授信的自动启动。

// 2026-07-28 运行参数集中读取，避免启动/重启/状态栏各自散落默认值 //***
interface AutoAcceptConfig {
    autoStart: boolean;
    pollMs: number;
    cooldownMs: number;
    restoreCursor: boolean;
    showNotifications: boolean;
}

function log(emoji: string, message: string) {
    const ts = new Date().toTimeString().slice(0, 8);
    outputChannel.appendLine(`[${ts}] ${emoji} ${message}`);
}

export function activate(context: vscode.ExtensionContext) {
    isActive = true; // 2026-10-05
    extensionContext = context;
    outputChannel = vscode.window.createOutputChannel('Antigravity Auto Accept');
    context.subscriptions.push(outputChannel); // 2026-10-05
    log('🚀', `Antigravity Auto Accept ${context.extension?.packageJSON.version ?? ''} (${process.platform === 'linux' ? 'Linux diagnostics' : 'UIAutomation'}) activating...`); // 2026-10-05

    // 状态栏按钮
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'antigravity-auto-accept.toggle';
    statusBarItem.tooltip = 'Antigravity Auto Accept — Click to toggle ON/OFF';
    statusBarItem.show();
    context.subscriptions.push(statusBarItem);

    // 注册命令
    const toggleCmd = vscode.commands.registerCommand('antigravity-auto-accept.toggle', () => {
        /* 2026-10-14：Linux 诊断期间点击状态栏仅停止诊断，不误报审批开启。 */
        if (linuxDiagnosticStop) { stopAutoClicker(); updateStatusBar(); return; }
        isEnabled = !isEnabled;
        updateStatusBar();
        if (isEnabled) {
            startAutoClicker();
            if (isEnabled) { notify('Antigravity Auto Accept: ON'); } // 2026-10-05
        } else {
            stopAutoClicker();
            notify('Antigravity Auto Accept: OFF');
        }
    });

    const startCmd = vscode.commands.registerCommand('antigravity-auto-accept.start', () => {
        if (!isEnabled) {
            isEnabled = true;
            updateStatusBar();
            startAutoClicker();
        }
        if (isEnabled) { notify('Antigravity Auto Accept started.'); } // 2026-10-05
    });

    const stopCmd = vscode.commands.registerCommand('antigravity-auto-accept.stop', () => {
        isEnabled = false;
        updateStatusBar();
        stopAutoClicker();
        updateStatusBar();
        notify('Antigravity Auto Accept stopped.');
    });

    const restartCmd = vscode.commands.registerCommand('antigravity-auto-accept.restart', () => {
        /* 2026-10-14：显式重启等待旧 Linux 子进程真正关闭，停止和卸载可取消等待。 */
        if (linuxDiagnosticStop) {
            linuxRestartRequested = true;
            linuxDiagnosticStop('Restart requested; stopping the current Linux diagnostic.');
            return;
        }
        if (!isEnabled) {
            isEnabled = true;
            updateStatusBar();
            startAutoClicker();
            if (isEnabled) { notify('Antigravity Auto Accept started.'); } // 2026-10-05
            return;
        }
        restartAutoClicker('manual restart');
        notify('Antigravity Auto Accept restarted.');
    });

    const showOutputCmd = vscode.commands.registerCommand('antigravity-auto-accept.showOutput', () => {
        outputChannel.show(true);
    });

    const configWatcher = vscode.workspace.onDidChangeConfiguration((event) => {
        if (!event.affectsConfiguration('antigravityAutoAccept')) { return; }
        updateStatusBar();
        /* 2026-10-07：展示和下次激活选项不影响当前扫描，只有运行参数变化才重启。 */
        if (isEnabled && ['pollMs', 'cooldownMs', 'restoreCursor'].some(key =>
            event.affectsConfiguration(`antigravityAutoAccept.${key}`))) {
            restartAutoClicker('settings changed');
        }
    });

    /* 2026-10-05：首次授予工作区信任后重新检查自动启动条件，受限模式中不运行扫描器。 */
    const trustWatcher = vscode.workspace.onDidGrantWorkspaceTrust(() => {
        if (isActive && startAfterTrust && !isEnabled && getConfig().autoStart) { // 2026-10-07
            isEnabled = true;
            startAutoClicker();
        }
    });

    context.subscriptions.push(toggleCmd, startCmd, stopCmd, restartCmd, showOutputCmd, configWatcher, trustWatcher);

    // 自动启动
    /* 2026-10-14：Linux 仍未实现审批，启动插件不自动连接辅助功能或运行探针。 */
    isEnabled = process.platform !== 'linux' && getConfig().autoStart;
    updateStatusBar();
    if (isEnabled) {
        startAutoClicker();
    } else {
        log('ℹ️', process.platform === 'linux'
            ? 'Linux automatic approvals are unavailable. Use Start to run a read-only diagnostic.'
            : 'Auto start disabled by setting.');
    }
}

function startAutoClicker() {
    /* 2026-10-05：仅在 Windows Antigravity 的可信工作区启动，卸载后的遗留命令不再创建进程。 */
    if (!isActive) { isEnabled = false; return; }
    if (!isEnabled) { return; }
    if (psProcess) { if (process.platform === 'linux') { isEnabled = false; } return; }
    const backend = selectPlatformBackend(process.platform, process.execPath, vscode.workspace.isTrusted);
    if (backend.kind === 'unsupported') {
        startAfterTrust = process.platform === 'win32' && !vscode.workspace.isTrusted;
        log('ℹ️', backend.reason);
        isEnabled = false;
        scannerState = undefined;
        updateStatusBar();
        return;
    }
    startAfterTrust = false; // 2026-10-07：已通过宿主边界，无须等待后续信任事件。
    if (restartTimer !== undefined) { clearTimeout(restartTimer); restartTimer = undefined; }

    if (backend.kind === 'linux-atspi-diagnostic') { startLinuxDiagnostic(backend.script); return; }

    const config = getConfig();
    const scriptPath = extensionContext.asAbsolutePath(path.join('src', 'autoClicker.ps1'));
    if (!fs.existsSync(scriptPath)) {
        log('❌', `PowerShell scanner not found: ${scriptPath}`);
        vscode.window.showErrorMessage('Antigravity Auto Accept: autoClicker.ps1 is missing from the extension package.');
        isEnabled = false;
        updateStatusBar();
        return;
    }

    log('🔄', `Starting UIAutomation scanner: ${scriptPath}`);
    log('⚙️', `Settings: poll=${config.pollMs}ms, cooldown=${config.cooldownMs}ms, restoreCursor=${config.restoreCursor}`);

    /* 2026-10-05：Windows PowerShell 5 显式按 UTF-8 加载中文规则，并把安装路径作为字面量传递。 */
    const scannerCommand = `$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); `
        + `& ([scriptblock]::Create([IO.File]::ReadAllText('${scriptPath.replace(/'/g, "''")}', [Text.Encoding]::UTF8))) `
        + `-PollMs ${config.pollMs} -CooldownMs ${config.cooldownMs} -RestoreCursor '${config.restoreCursor}' `
        + `-ParentProcessId ${process.pid} -HostExecutablePath '${process.execPath.replace(/'/g, "''")}'`;
    let scannerProcess: child_process.ChildProcess;
    try {
        scannerProcess = child_process.spawn('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-OutputFormat', 'Text',
            '-ExecutionPolicy', 'Bypass',
            '-EncodedCommand', Buffer.from(scannerCommand, 'utf16le').toString('base64'),
        ], {
            stdio: ['ignore', 'pipe', 'pipe'],
            windowsHide: true,
        });
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        log('❌', `Failed to start PowerShell scanner: ${message}`);
        isEnabled = false;
        scannerState = undefined;
        updateStatusBar();
        vscode.window.showErrorMessage(`Antigravity Auto Accept failed to start: ${message}`);
        return;
    }
    psProcess = scannerProcess;
    scannerState = 'starting';
    updateStatusBar();
    let stdoutBuffer = '';
    let hasExited = false; // 2026-10-07：进程退出后只接收管道尾部诊断，直到 close。
    scannerProcess.stdout?.setEncoding('utf8');
    scannerProcess.stderr?.setEncoding('utf8');

    /* 2026-10-05：只接收当前扫描器的协议，分段输出由当前进程自己的缓冲区拼接。 */
    scannerProcess.stdout?.on('data', (data: Buffer | string) => {
        if ((psProcess !== scannerProcess && !hasExited) || !isActive || !isEnabled) { return; } // 2026-10-07
        stdoutBuffer += data.toString();
        const parts = stdoutBuffer.split(/\r?\n/);
        stdoutBuffer = parts.pop() ?? '';
        const lines = parts.filter(l => l.trim());
        for (const line of lines) {
            /* 2026-10-07：死亡实例输出明确标识为收尾诊断，READY/WAITING 等旧协议不能更新当前状态。 */
            if (hasExited) {
                log('📡', `Exited scanner: ${line.trim()}`);
                continue;
            }
            if (line.includes('___CLICK_INVOKE___:')) {
                const btnName = line.split('___CLICK_INVOKE___:')[1];
                log('✅', `Auto-accepted (Invoke): "${btnName}"`);
            } else if (line.includes('___CLICK_PHYSICAL___:')) {
                const info = line.split('___CLICK_PHYSICAL___:')[1];
                log('✅', `Auto-accepted (Physical): "${info}"`);
            } else if (line.includes('___AUTOCLICK_READY___')) {
                log('✅', 'UIAutomation scanner ready');
                scannerState = 'ready';
                updateStatusBar();
            } else if (line.includes('___SCANNER_WAITING___') || line.includes('___ALREADY_RUNNING___')) {
                scannerState = 'waiting';
                updateStatusBar();
                log('ℹ️', 'Another scanner owns the desktop session; waiting to take over when it stops.');
            } else if (line.includes('___ERROR___:')) {
                const err = line.split('___ERROR___:')[1];
                // UIAutomation错误通常是暂时性的，只在debug时显示
                if (err && !err.includes('Operation is not valid')) {
                    log('⚠️', `Scanner: ${err}`);
                }
            } else if (line.trim()) {
                log('📡', line.trim());
            }
        }
    });

    scannerProcess.stderr?.on('data', (data: Buffer | string) => {
        if ((psProcess !== scannerProcess && !hasExited) || !isActive || !isEnabled) { return; } // 2026-10-07
        const msg = data.toString().trim();
        if (msg) {
            log('❌', `${hasExited ? 'Exited scanner error' : 'PowerShell error'}: ${msg}`); // 2026-10-07
        }
    });

    /* 2026-10-07：close 后停止收尾，保留退出前后没有换行的最后一条诊断。 */
    scannerProcess.on('close', () => {
        if (hasExited && isActive && isEnabled && stdoutBuffer.trim()) {
            log('📡', `Exited scanner: ${stdoutBuffer.trim()}`);
        }
        hasExited = false;
        stdoutBuffer = '';
    });

    /* 2026-10-07：管道错误由当前扫描器接管，避免未处理事件中断宿主，旧实例错误不影响新会话。 */
    const handleStreamError = (error: Error) => {
        if (psProcess !== scannerProcess || !isActive) { return; }
        log('❌', `Scanner output failed: ${error.message}`);
        restartAutoClicker('scanner output failed');
    };
    scannerProcess.stdout?.on('error', handleStreamError);
    scannerProcess.stderr?.on('error', handleStreamError);

    /* 2026-10-05：退出只释放所属实例，异常重启可由停止、配置重启或卸载取消。 */
    scannerProcess.on('exit', (code) => {
        if (psProcess !== scannerProcess || !isActive) { return; }
        hasExited = true; // 2026-10-07：exit 不代表 stdout/stderr 已全部关闭。
        log('⏹️', `Scanner process exited (code: ${code})`);
        psProcess = undefined;
        // 如果仍启用则自动重启
        if (isEnabled) {
            scannerState = 'retrying';
            updateStatusBar();
            log('🔄', 'Restarting scanner in 3s...');
            restartTimer = setTimeout(() => {
                restartTimer = undefined;
                if (isActive && isEnabled && !psProcess) { startAutoClicker(); }
            }, 3000);
        }
    });

    scannerProcess.on('error', (error) => {
        if (psProcess !== scannerProcess || !isActive) { return; } // 2026-10-05
        log('❌', `Failed to start PowerShell scanner: ${error.message}`);
        psProcess = undefined;
        scannerState = undefined; // 2026-10-05
        isEnabled = false;
        updateStatusBar();
        vscode.window.showErrorMessage(`Antigravity Auto Accept failed to start: ${error.message}`);
    });
}

/* 2026-10-14：Linux 只运行可取消的单次只读探针，绝不复用 Windows READY 或重启协议。 */
function startLinuxDiagnostic(relativeScript: string) {
    isEnabled = false;
    const scriptPath = extensionContext.asAbsolutePath(relativeScript);
    if (!fs.existsSync(scriptPath)) {
        log('❌', 'Linux diagnostic script is missing from the extension package.');
        updateStatusBar();
        return;
    }
    let child: child_process.ChildProcess;
    try {
        /* 2026-10-14：固定系统解释器和参数数组，避免工作区 PATH、Python 环境或 shell 注入。 */
        child = child_process.spawn('/usr/bin/python3', [
            '-I', '-B', scriptPath, '--probe', '--parent-pid', String(process.pid),
            '--host-executable', process.execPath,
        ], { stdio: ['ignore', 'pipe', 'pipe'], shell: false });
    } catch {
        log('❌', 'Linux diagnostics could not start. System Python 3 is required.');
        updateStatusBar();
        return;
    }
    psProcess = child;
    scannerState = 'diagnostic';
    updateStatusBar();
    outputChannel.show(true);
    log('ℹ️', 'Running a read-only Linux capability diagnostic. Automatic approvals remain disabled.');
    let stdout = '';
    let stopping = false;
    const current = () => psProcess === child;
    const stop = (message: string) => {
        if (!current() || stopping) { return; }
        stopping = true;
        if (diagnosticTimer !== undefined) { clearTimeout(diagnosticTimer); diagnosticTimer = undefined; }
        scannerState = 'stopping';
        isEnabled = false;
        if (isActive) { log('ℹ️', message); updateStatusBar(); }
        /* 2026-10-14：先请求退出，宽限后只强制结束该子进程；close 前绝不释放所有权。 */
        try { child.kill('SIGTERM'); } catch { /* 2026-10-14：继续执行有界的强制结束。 */ }
        if (!current()) { return; }
        diagnosticKillTimer = setTimeout(() => {
            diagnosticKillTimer = undefined;
            if (!current()) { return; }
            try { child.kill('SIGKILL'); } catch { /* 2026-10-14：失败仍保持 STOPPING，不允许重叠启动。 */ }
            if (isActive) { log('ℹ️', 'Linux diagnostic termination requested; waiting for the child to close.'); }
        }, 1000);
    };
    linuxDiagnosticStop = stop;
    child.stdout?.setEncoding('utf8');
    child.stderr?.setEncoding('utf8');
    child.stdout?.on('data', (data: Buffer | string) => {
        if (!current() || !isActive || stopping) { return; }
        stdout += data.toString();
        if (stdout.length > 65536) { stop('Linux diagnostic output exceeded its limit; stopping the diagnostic.'); }
    });
    /* 2026-10-14：不打印可能含界面隐私的底层 stderr；关闭时只解释已校验的固定 JSON 协议。 */
    child.stderr?.on('data', () => {});
    for (const stream of [child.stdout, child.stderr]) {
        stream?.on('error', () => stop('Linux diagnostic pipe failed; stopping the diagnostic.'));
    }
    child.on('error', () => stop('Linux diagnostics could not start. Check system Python 3; waiting for cleanup.'));
    child.on('close', (code: number | null) => {
        if (!current()) { return; }
        if (diagnosticTimer !== undefined) { clearTimeout(diagnosticTimer); diagnosticTimer = undefined; }
        if (diagnosticKillTimer !== undefined) { clearTimeout(diagnosticKillTimer); diagnosticKillTimer = undefined; }
        psProcess = undefined;
        linuxDiagnosticStop = undefined;
        scannerState = undefined;
        isEnabled = false;
        const restartRequested = linuxRestartRequested && isActive;
        linuxRestartRequested = false;
        if (!isActive) { return; }
        let message = 'Linux diagnostic stopped. Automatic approvals remain disabled.';
        if (!stopping) {
            try {
                const report: unknown = JSON.parse(stdout.trim());
                if (typeof report !== 'object' || report === null) { throw new Error('invalid protocol'); }
                const result = report as Record<string, unknown>;
                if (result.schemaVersion !== 1 || result.backend !== 'linux-atspi' || result.actionsEnabled !== false
                    || typeof result.message !== 'string' || result.message.length > 2000
                    || !((code === 0 && result.status === 'diagnostic-only') || (code === 2 && result.status === 'unavailable'))) {
                    throw new Error('invalid protocol');
                }
                message = `Linux diagnostic: ${result.message}`;
            } catch {
                message = 'Linux diagnostics did not return a valid read-only result. Automatic approvals remain disabled.';
            }
        }
        log('ℹ️', message);
        updateStatusBar();
        if (restartRequested) { isEnabled = true; startAutoClicker(); }
    });
    diagnosticTimer = setTimeout(() => stop('Linux diagnostics timed out; stopping the diagnostic.'), 15000);
}

function stopAutoClicker() {
    /* 2026-10-14：Linux close 之前保留所有权，卸载后也必须执行强制结束计时器。 */
    linuxRestartRequested = false;
    if (linuxDiagnosticStop) { linuxDiagnosticStop('Stopping the Linux diagnostic.'); return; }
    startAfterTrust = false; // 2026-10-07：停止同时撤销尚未授信的启动意图。
    /* 2026-10-05：先撤销计时器和实例所有权，再结束进程，异步 exit 不再修改后续实例。 */
    if (restartTimer !== undefined) { clearTimeout(restartTimer); restartTimer = undefined; }
    if (diagnosticTimer !== undefined) { clearTimeout(diagnosticTimer); diagnosticTimer = undefined; }
    scannerState = undefined;
    if (psProcess) {
        log('⏹️', 'Stopping scanner...');
        const stoppedProcess = psProcess;
        psProcess = undefined;
        stoppedProcess.kill();
    }
}

function restartAutoClicker(reason: string) {
    log('🔄', `Restarting scanner (${reason})...`);
    stopAutoClicker();
    if (isEnabled) {
        /* 2026-10-05：配置变化与手动重启共用可取消计时器，连续变化只启动最后一次配置。 */
        scannerState = 'retrying';
        updateStatusBar();
        restartTimer = setTimeout(() => {
            restartTimer = undefined;
            if (isActive && isEnabled && !psProcess) { startAutoClicker(); }
        }, 300);
    }
}

// 2026-07-28 状态栏直接展示当前扫描节奏，减少必须打开日志排查的成本 //***
function updateStatusBar() {
    const config = getConfig();
    if (scannerState === 'diagnostic' || scannerState === 'stopping') {
        statusBarItem.text = scannerState === 'stopping' ? '◌ AutoAccept: STOPPING' : '◌ AutoAccept: DIAGNOSTIC';
        statusBarItem.tooltip = 'Linux read-only diagnostic. Automatic approvals are disabled.\nClick to stop.';
        statusBarItem.backgroundColor = undefined;
    } else if (isEnabled) {
        /* 2026-10-05：只有收到 READY 才显示 ON，等待接管与重启期间显示实际状态。 */
        const state = scannerState === 'ready' ? 'ON' : (scannerState ?? 'starting').toUpperCase();
        statusBarItem.text = `${scannerState === 'waiting' ? '⏳' : '⚡'} AutoAccept: ${state}`;
        statusBarItem.tooltip = `Antigravity Auto Accept: ${state}\nPoll: ${config.pollMs}ms · Cooldown: ${config.cooldownMs}ms\nClick to toggle OFF`;
        statusBarItem.backgroundColor = undefined;
    } else {
        statusBarItem.text = '✕ AutoAccept: OFF';
        statusBarItem.tooltip = process.platform === 'linux'
            ? 'Linux automatic approvals are unavailable.\nClick to run a read-only diagnostic.'
            : 'Antigravity Auto Accept: OFF\nClick to toggle ON';
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    }
}

// 2026-07-28 配置入口统一做范围钳制，防止错误设置把后台扫描拖死 //***
function getConfig(): AutoAcceptConfig {
    const config = vscode.workspace.getConfiguration('antigravityAutoAccept');
    return {
        /* 2026-10-14：布尔配置必须在运行时收窄，错误类型不自动启动、不通知并保持光标恢复。 */
        autoStart: config.get<unknown>('autoStart', true) === true,
        pollMs: clamp(config.get<number>('pollMs', 500), 100, 5000),
        cooldownMs: clamp(config.get<number>('cooldownMs', 1500), 300, 10000),
        restoreCursor: config.get<unknown>('restoreCursor', true) !== false,
        showNotifications: config.get<unknown>('showNotifications', false) === true,
    };
}

function clamp(value: number | undefined, min: number, max: number): number {
    if (typeof value !== 'number' || Number.isNaN(value)) { return min; }
    return Math.min(Math.max(Math.round(value), min), max);
}

function notify(message: string) {
    if (getConfig().showNotifications) {
        vscode.window.showInformationMessage(message);
    }
}

export function deactivate() {
    isActive = false; // 2026-10-05
    isEnabled = false;
    const linuxChild = linuxDiagnosticStop ? psProcess : undefined;
    stopAutoClicker();
    /* 2026-10-14：卸载后扩展宿主可能立即退出，不能依靠将来的计时器回收只读 Linux 子进程。 */
    if (linuxChild) {
        if (diagnosticKillTimer !== undefined) { clearTimeout(diagnosticKillTimer); diagnosticKillTimer = undefined; }
        try { linuxChild.kill('SIGKILL'); } catch { /* 2026-10-14：仅针对已拥有的 Linux 子进程。 */ }
    }
}
