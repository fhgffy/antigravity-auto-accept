import * as vscode from 'vscode';
import * as child_process from 'child_process';

// 2026-03-29 v5.0.0 自动修补Antigravity快捷方式，添加CDP调试端口 //***

export class ShortcutPatcher {
    private port: number;
    private log: (msg: string) => void;

    constructor(port: number, log: (msg: string) => void) {
        this.port = port;
        this.log = log;
    }

    async checkAndPrompt(): Promise<void> {
        const action = await vscode.window.showWarningMessage(
            `Antigravity Auto Accept: CDP port ${this.port} is not open. ` +
            `Antigravity needs to be launched with --remote-debugging-port=${this.port}. ` +
            `Auto-fix your shortcut?`,
            'Auto-Fix (Windows)',
            'Manual Instructions'
        );

        if (action === 'Auto-Fix (Windows)') {
            await this.patchShortcuts();
        } else if (action === 'Manual Instructions') {
            vscode.window.showInformationMessage(
                `Add --remote-debugging-port=${this.port} to your Antigravity shortcut target, then restart Antigravity.`
            );
        }
    }

    private async patchShortcuts(): Promise<void> {
        const flag = `--remote-debugging-port=${this.port}`;
        // PowerShell脚本：查找所有Antigravity快捷方式并添加CDP端口参数
        const psScript = `
$shell = New-Object -ComObject WScript.Shell;
$shortcuts = @();
$shortcuts += Get-ChildItem "$env:APPDATA\\Microsoft\\Windows\\Start Menu" -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue;
$shortcuts += Get-ChildItem "$env:USERPROFILE\\Desktop" -Filter "*.lnk" -ErrorAction SilentlyContinue;
$patched = 0;
foreach ($sc in $shortcuts) {
    $lnk = $shell.CreateShortcut($sc.FullName);
    if ($lnk.TargetPath -like '*antigravity*' -or $lnk.TargetPath -like '*Antigravity*') {
        if ($lnk.Arguments -notlike '*${flag}*') {
            $lnk.Arguments = $lnk.Arguments + ' ${flag}';
            $lnk.Save();
            $patched++;
            Write-Output "Patched: $($sc.FullName)";
        } else {
            Write-Output "Already patched: $($sc.FullName)";
        }
    }
}
if ($patched -eq 0) { Write-Output "No Antigravity shortcuts found or all already patched." }
else { Write-Output "Patched $patched shortcut(s). Please restart Antigravity." }
`.replace(/\n/g, ' ');

        return new Promise((resolve) => {
            child_process.exec(
                `powershell -NoProfile -ExecutionPolicy Bypass -Command "${psScript}"`,
                (err, stdout, stderr) => {
                    if (err) {
                        this.log(`[Patcher] Error: ${stderr}`);
                        vscode.window.showErrorMessage(`Failed to patch shortcut: ${stderr}`);
                    } else {
                        this.log(`[Patcher] ${stdout.trim()}`);
                        vscode.window.showInformationMessage(
                            `Shortcut patched! Please restart Antigravity completely.`
                        );
                    }
                    resolve();
                }
            );
        });
    }
}
