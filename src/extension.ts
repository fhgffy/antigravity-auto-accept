import * as vscode from 'vscode';
import * as path from 'path';
import * as child_process from 'child_process';

// 2026-03-29 v5.1.0 UIAutomation架构 — 从CDP回归UIAutomation直接按钮检测 //***
// UIAutomation能看到Antigravity的"Run"/"Accept"等按钮并支持InvokePattern，无需CDP端口

let isEnabled = false;
let statusBarItem: vscode.StatusBarItem;
let outputChannel: vscode.OutputChannel;
let psProcess: child_process.ChildProcess | undefined;

function log(emoji: string, message: string) {
    const ts = new Date().toTimeString().slice(0, 8);
    outputChannel.appendLine(`[${ts}] ${emoji} ${message}`);
}

export function activate(context: vscode.ExtensionContext) {
    outputChannel = vscode.window.createOutputChannel('Antigravity Auto Accept');
    log('🚀', 'Antigravity Auto Accept v5.1.0 (UIAutomation) activating...');

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
            vscode.window.showInformationMessage('Antigravity Auto Accept: ON');
        } else {
            stopAutoClicker();
            vscode.window.showInformationMessage('Antigravity Auto Accept: OFF');
        }
    });

    const startCmd = vscode.commands.registerCommand('antigravity-auto-accept.start', () => {
        if (!isEnabled) {
            isEnabled = true;
            updateStatusBar();
            startAutoClicker();
        }
        vscode.window.showInformationMessage('Antigravity Auto Accept started.');
    });

    const stopCmd = vscode.commands.registerCommand('antigravity-auto-accept.stop', () => {
        isEnabled = false;
        updateStatusBar();
        stopAutoClicker();
        vscode.window.showInformationMessage('Antigravity Auto Accept stopped.');
    });

    context.subscriptions.push(toggleCmd, startCmd, stopCmd);

    // 自动启动
    isEnabled = true;
    updateStatusBar();
    startAutoClicker();
}

function startAutoClicker() {
    if (psProcess) { return; }

    const scriptPath = path.join(__dirname, '..', 'src', 'autoClicker.ps1');
    log('🔄', `Starting UIAutomation scanner: ${scriptPath}`);

    psProcess = child_process.spawn('powershell', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-PollMs', '500',
        '-CooldownMs', '1500'
    ], {
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
    });

    psProcess.stdout?.on('data', (data: Buffer) => {
        const lines = data.toString().split(/\r?\n/).filter(l => l.trim());
        for (const line of lines) {
            if (line.includes('___CLICK_INVOKE___:')) {
                const btnName = line.split('___CLICK_INVOKE___:')[1];
                log('✅', `Auto-accepted (Invoke): "${btnName}"`);
            } else if (line.includes('___CLICK_PHYSICAL___:')) {
                const info = line.split('___CLICK_PHYSICAL___:')[1];
                log('✅', `Auto-accepted (Physical): "${info}"`);
            } else if (line.includes('___AUTOCLICK_READY___')) {
                log('✅', 'UIAutomation scanner ready');
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

    psProcess.stderr?.on('data', (data: Buffer) => {
        const msg = data.toString().trim();
        if (msg) {
            log('❌', `PowerShell error: ${msg}`);
        }
    });

    psProcess.on('exit', (code) => {
        log('⏹️', `Scanner process exited (code: ${code})`);
        psProcess = undefined;
        // 如果仍启用则自动重启
        if (isEnabled) {
            log('🔄', 'Restarting scanner in 3s...');
            setTimeout(() => {
                if (isEnabled && !psProcess) { startAutoClicker(); }
            }, 3000);
        }
    });
}

function stopAutoClicker() {
    if (psProcess) {
        log('⏹️', 'Stopping scanner...');
        psProcess.kill();
        psProcess = undefined;
    }
}

function updateStatusBar() {
    if (isEnabled) {
        statusBarItem.text = '⚡ AutoAccept: ON';
        statusBarItem.backgroundColor = undefined;
    } else {
        statusBarItem.text = '✕ AutoAccept: OFF';
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    }
}

export function deactivate() {
    stopAutoClicker();
}
