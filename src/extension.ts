import * as vscode from 'vscode';
import * as path from 'path';
import * as child_process from 'child_process';
import * as fs from 'fs';

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
let scannerState: 'starting' | 'waiting' | 'ready' | 'retrying' | undefined;

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
    log('🚀', `Antigravity Auto Accept ${context.extension?.packageJSON.version ?? ''} (UIAutomation) activating...`); // 2026-10-05

    // 状态栏按钮
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'antigravity-auto-accept.toggle';
    statusBarItem.tooltip = 'Antigravity Auto Accept — Click to toggle ON/OFF';
    statusBarItem.show();
    context.subscriptions.push(statusBarItem);

    // 注册命令
    const toggleCmd = vscode.commands.registerCommand('antigravity-auto-accept.toggle', () => {
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
        notify('Antigravity Auto Accept stopped.');
    });

    const restartCmd = vscode.commands.registerCommand('antigravity-auto-accept.restart', () => {
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
        if (isEnabled) {
            restartAutoClicker('settings changed');
        }
    });

    /* 2026-10-05：首次授予工作区信任后重新检查自动启动条件，受限模式中不运行扫描器。 */
    const trustWatcher = vscode.workspace.onDidGrantWorkspaceTrust(() => {
        if (isActive && !isEnabled && getConfig().autoStart) {
            isEnabled = true;
            startAutoClicker();
        }
    });

    context.subscriptions.push(toggleCmd, startCmd, stopCmd, restartCmd, showOutputCmd, configWatcher, trustWatcher);

    // 自动启动
    isEnabled = getConfig().autoStart;
    updateStatusBar();
    if (isEnabled) {
        startAutoClicker();
    } else {
        log('ℹ️', 'Auto start disabled by setting.');
    }
}

function startAutoClicker() {
    /* 2026-10-05：仅在 Windows Antigravity 的可信工作区启动，卸载后的遗留命令不再创建进程。 */
    if (!isActive) { isEnabled = false; return; }
    if (!isEnabled) { return; }
    if (psProcess) { return; }
    const unavailableReason = process.platform !== 'win32'
        ? 'UIAutomation requires Windows.'
        : !/^antigravity(?: ide)?\.exe$/i.test(path.win32.basename(process.execPath))
            ? 'This extension only runs inside Antigravity IDE.'
            : !vscode.workspace.isTrusted ? 'Workspace trust is required before auto-accept can start.' : undefined;
    if (unavailableReason) {
        log('ℹ️', unavailableReason);
        isEnabled = false;
        scannerState = undefined;
        updateStatusBar();
        return;
    }
    if (restartTimer !== undefined) { clearTimeout(restartTimer); restartTimer = undefined; }

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
    scannerProcess.stdout?.setEncoding('utf8');
    scannerProcess.stderr?.setEncoding('utf8');

    /* 2026-10-05：只接收当前扫描器的协议，分段输出由当前进程自己的缓冲区拼接。 */
    scannerProcess.stdout?.on('data', (data: Buffer | string) => {
        if (psProcess !== scannerProcess || !isActive) { return; }
        stdoutBuffer += data.toString();
        const parts = stdoutBuffer.split(/\r?\n/);
        stdoutBuffer = parts.pop() ?? '';
        const lines = parts.filter(l => l.trim());
        for (const line of lines) {
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
        if (psProcess !== scannerProcess || !isActive) { return; } // 2026-10-05
        const msg = data.toString().trim();
        if (msg) {
            log('❌', `PowerShell error: ${msg}`);
        }
    });

    /* 2026-10-05：退出只释放所属实例，异常重启可由停止、配置重启或卸载取消。 */
    scannerProcess.on('exit', (code) => {
        if (psProcess !== scannerProcess || !isActive) { return; }
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

function stopAutoClicker() {
    /* 2026-10-05：先撤销计时器和实例所有权，再结束进程，异步 exit 不再修改后续实例。 */
    if (restartTimer !== undefined) { clearTimeout(restartTimer); restartTimer = undefined; }
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
    if (isEnabled) {
        /* 2026-10-05：只有收到 READY 才显示 ON，等待接管与重启期间显示实际状态。 */
        const state = scannerState === 'ready' ? 'ON' : (scannerState ?? 'starting').toUpperCase();
        statusBarItem.text = `${scannerState === 'waiting' ? '⏳' : '⚡'} AutoAccept: ${state}`;
        statusBarItem.tooltip = `Antigravity Auto Accept: ${state}\nPoll: ${config.pollMs}ms · Cooldown: ${config.cooldownMs}ms\nClick to toggle OFF`;
        statusBarItem.backgroundColor = undefined;
    } else {
        statusBarItem.text = '✕ AutoAccept: OFF';
        statusBarItem.tooltip = 'Antigravity Auto Accept: OFF\nClick to toggle ON';
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    }
}

// 2026-07-28 配置入口统一做范围钳制，防止错误设置把后台扫描拖死 //***
function getConfig(): AutoAcceptConfig {
    const config = vscode.workspace.getConfiguration('antigravityAutoAccept');
    return {
        autoStart: config.get<boolean>('autoStart', true),
        pollMs: clamp(config.get<number>('pollMs', 500), 100, 5000),
        cooldownMs: clamp(config.get<number>('cooldownMs', 1500), 300, 10000),
        restoreCursor: config.get<boolean>('restoreCursor', true),
        showNotifications: config.get<boolean>('showNotifications', false),
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
    stopAutoClicker();
}
