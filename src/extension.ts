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
