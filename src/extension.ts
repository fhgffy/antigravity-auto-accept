import * as vscode from 'vscode';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';

let clickerProcess: ChildProcess | undefined;

export function activate(context: vscode.ExtensionContext) {
    console.log('Antigravity Auto Accept extension is now active!');

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

    // We launch PowerShell to run the UIAutomation script in the background
    clickerProcess = spawn('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-vscodePid', pid
    ]);

    clickerProcess.stdout?.on('data', (data) => {
        console.log(`AutoClicker: ${data.toString()}`);
    });

    clickerProcess.stderr?.on('data', (data) => {
        console.error(`AutoClicker Error: ${data.toString()}`);
    });

    clickerProcess.on('close', (code) => {
        console.log(`AutoClicker exited with code ${code}`);
        clickerProcess = undefined;
    });

    // Also start an internal VS Code interval to accept QuickPicks just in case
    // it's an internal VS Code prompt that isn't exposed to Windows UIAutomation.
    const interval = setInterval(() => {
        // Try to accept any open input or quick pick automatically
        vscode.commands.executeCommand('workbench.action.acceptSelectedQuickOpenItem').then(undefined, () => { });
    }, 1500);

    context.subscriptions.push({ dispose: () => clearInterval(interval) });
}

function stopClicker() {
    if (clickerProcess) {
        clickerProcess.kill();
        clickerProcess = undefined;
    }
}

export function deactivate() {
    stopClicker();
}
