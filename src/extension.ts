import * as vscode from 'vscode';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';

let clickerProcess: ChildProcess | undefined;
let notificationPoller: NodeJS.Timeout | undefined;
let outputChannel: vscode.OutputChannel;

export function activate(context: vscode.ExtensionContext) {
    outputChannel = vscode.window.createOutputChannel('Antigravity Auto Accept');
    outputChannel.appendLine('Antigravity Auto Accept extension is now active!');

    const startCommand = vscode.commands.registerCommand('antigravity-auto-accept.start', () => {
        startClicker(context);
        vscode.window.showInformationMessage('Antigravity Auto Accept started.');
    });

    const stopCommand = vscode.commands.registerCommand('antigravity-auto-accept.stop', () => {
        stopClicker();
        vscode.window.showInformationMessage('Antigravity Auto Accept stopped.');
    });

    context.subscriptions.push(startCommand, stopCommand);

    // 2026-03-22T12:11:20+08:00: 注册兜底命令，消除 IDE 幽灵命令报错 (Issue #3)
    // Antigravity IDE 的 package.json 声明了 antigravity.agent.acceptAgentStep 的 keybinding，
    // 但 dist/extension.js 从未注册过该命令。当 notificationPoller 或 StealthAltEnter
    // 触发 Alt+Enter 时，会命中这条 keybinding 并报 command not found。
    // 解决方案：检查该命令是否存在，不存在则注册一个空操作兜底版本。
    registerFallbackCommands(context);
    //***

    // Auto-start on load
    startClicker(context);
}

function startClicker(context: vscode.ExtensionContext) {
    if (clickerProcess) {
        return;
    }

    const scriptPath = path.join(context.extensionPath, 'src', 'autoClicker.ps1');
    const pid = process.pid.toString(); // VS Code main/extension process PID

    // We launch PowerShell to run the UIAutomation script in the background.
    // To completely avoid Node.js and PowerShell garbling the Chinese characters ('药酱') 
    // in the path during process spawn, we must encode the command as a UTF-16LE Base64 string.
    const commandToRun = `& '${scriptPath}' -vscodePid ${pid}`;
    const encodedCommand = Buffer.from(commandToRun, 'utf16le').toString('base64');

    clickerProcess = spawn('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-EncodedCommand', encodedCommand
    ]);

    clickerProcess.stdout?.on('data', (data) => {
        const msg = data.toString().trim();
        if (msg) { outputChannel.appendLine(`[PS] ${msg}`); }
    });

    clickerProcess.stderr?.on('data', (data) => {
        const msg = data.toString().trim();
        if (msg) { outputChannel.appendLine(`[ERR] ${msg}`); }
    });

    clickerProcess.on('close', (code) => {
        outputChannel.appendLine(`AutoClicker exited with code ${code}`);
        clickerProcess = undefined;
    });

    // Strategy 2: VS Code Native Notification Poller
    // UIAutomation cannot see inside VS Code's custom Toast Notifications. 
    // We must use the internal command API to accept the primary action of any active toast.
    if (!notificationPoller) {
        notificationPoller = setInterval(() => {
            vscode.commands.executeCommand('notifications.acceptPrimaryAction').then(undefined, () => { });
        }, 500);
        outputChannel.appendLine('[Extension] Started Internal Toast Notification Poller');
    }
}

function stopClicker() {
    if (clickerProcess) {
        clickerProcess.kill();
        clickerProcess = undefined;
    }

    if (notificationPoller) {
        clearInterval(notificationPoller);
        notificationPoller = undefined;
    }
}

export function deactivate() {
    stopClicker();
}

// 2026-03-22T12:11:20+08:00: 兜底命令注册 — 消除 IDE 幽灵命令报错 (Issue #3)
// Antigravity IDE 内置扩展的 package.json 声明了 keybinding 但从未在代码中注册的命令。
// 当 Alt+Enter 或 notificationPoller 触发这些命令时，VS Code 会报 command not found。
// 此函数在命令不存在时预注册空操作版本，从根源消除报错。
async function registerFallbackCommands(context: vscode.ExtensionContext) {
    // Antigravity IDE 声明了 keybinding 但从未注册的幽灵命令列表
    const phantomCommands = [
        'antigravity.agent.acceptAgentStep',
    ];

    try {
        const existingCommands = await vscode.commands.getCommands(true);
        const existingSet = new Set(existingCommands);

        for (const cmdId of phantomCommands) {
            if (!existingSet.has(cmdId)) {
                // 注册空操作兜底命令：静默拦截，不做任何实际操作
                const fallback = vscode.commands.registerCommand(cmdId, () => {
                    // 静默拦截，不输出日志（每 500ms 触发一次会刷屏）
                });
                context.subscriptions.push(fallback);
                outputChannel.appendLine(`[Fallback] 已注册兜底命令: ${cmdId}`);
            } else {
                outputChannel.appendLine(`[Fallback] 命令已存在，跳过: ${cmdId}`);
            }
        }
    } catch (err) {
        outputChannel.appendLine(`[Fallback] 兜底命令注册失败: ${err}`);
    }
}
//***
