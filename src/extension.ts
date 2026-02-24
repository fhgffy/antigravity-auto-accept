import * as vscode from 'vscode';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';

let clickerProcess: ChildProcess | undefined;
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

    // We launch PowerShell to run the UIAutomation script in the background
    // Using -Command and wrapping the path in single quotes prevents PowerShell from 
    // corrupting Chinese characters (like '药酱') or choking on spaces in the path.
    clickerProcess = spawn('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command', `& '${scriptPath}' -vscodePid ${pid}`
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

    // Intentionally omitted the QuickPick accept interval because it was auto-rejecting 
    // prompts that had "Reject" as their default focused item. We rely exclusively on the OS scraper.
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
