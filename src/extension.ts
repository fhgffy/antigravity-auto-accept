import * as vscode from 'vscode';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';

let clickerProcess: ChildProcess | undefined;
let notificationPoller: NodeJS.Timeout | undefined;
let outputChannel: vscode.OutputChannel;

// 2026-03-24T22:55:00+08:00: 统一时间戳 + emoji 日志格式，对齐 Toolkit 风格 //***
function log(emoji: string, message: string) {
    const now = new Date();
    const ts = now.toTimeString().slice(0, 8);
    outputChannel.appendLine(`[${ts}] ${emoji} ${message}`);
}

export function activate(context: vscode.ExtensionContext) {
    outputChannel = vscode.window.createOutputChannel('Antigravity Auto Accept');
    // 2026-03-24T22:55:00+08:00: Toolkit 风格启动日志 //***
    log('🚀', 'Auto Accept: Activating (v1.5.2)...');

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

    // 2026-03-24T22:59:00+08:00: 解析 PS1 的 [AA:TAG] 标签，在 TS 侧添加 emoji（避免管道乱码）//***
    const emojiMap: Record<string, string> = {
        'INIT': '🖥️ ',
        'IDE': '👁️ ',
        'CLICK': '✅',
    };
    clickerProcess.stdout?.on('data', (data) => {
        // 2026-03-24T23:04:00+08:00: 按行分割处理——stdout 可能一次性到达多行数据 //***
        const lines = data.toString().split(/\r?\n/);
        for (const line of lines) {
            const msg = line.trim();
            if (!msg) { continue; }
            // 解析 [AA:TAG] [HH:mm:ss] message 格式
            const tagMatch = msg.match(/^\[AA:(\w+)\]\s*\[(\d{2}:\d{2}:\d{2})\]\s*(.*)$/);
            if (tagMatch) {
                const emoji = emojiMap[tagMatch[1]] || 'ℹ️';
                outputChannel.appendLine(`[${tagMatch[2]}] ${emoji} ${tagMatch[3]}`);
            } else {
                outputChannel.appendLine(msg);
            }
        }
    });

    clickerProcess.stderr?.on('data', (data) => {
        const raw = data.toString();
        // 过滤 PowerShell CLIXML 序列化噪音（进度条、信息流、重复错误）
        if (raw.includes('CLIXML') || raw.includes('<Objs') || raw.includes('</Objs>') ||
            raw.includes('<S S="Error">') || raw.includes('<TNRef') || raw.includes('<Obj S=')) {
            return;
        }
        const msg = raw.trim();
        if (msg) { log('⚠️', msg); }
    });

    clickerProcess.on('close', (code) => {
        log('🛑', `AutoClicker exited (code ${code})`);
        clickerProcess = undefined;
    });

    // Strategy 2: VS Code Native Notification Poller
    // UIAutomation cannot see inside VS Code's custom Toast Notifications. 
    // We must use the internal command API to accept the primary action of any active toast.
    if (!notificationPoller) {
        notificationPoller = setInterval(() => {
            vscode.commands.executeCommand('notifications.acceptPrimaryAction').then(undefined, () => { });
        }, 500);
        log('🔔', 'Toast Poller: Active');
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
                log('🔗', `Fallback registered: ${cmdId}`);
            } else {
                log('✅', `Command exists: ${cmdId}`);
            }
        }
    } catch (err) {
        log('⚠️', `Fallback registration failed: ${err}`);
    }
}
//***
