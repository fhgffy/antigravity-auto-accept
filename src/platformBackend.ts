import * as path from 'path';

/* 2026-10-14：平台选择仅返回后端描述，Linux 诊断不代表已经支持自动审批。 */
export type PlatformBackend =
    | { kind: 'windows-uia'; script: string; actionsEnabled: true }
    | { kind: 'linux-atspi-diagnostic'; script: string; actionsEnabled: false }
    | { kind: 'unsupported'; reason: string; actionsEnabled: false };

export function selectPlatformBackend(platform: string, executable: string, trusted: boolean): PlatformBackend {
    if (!trusted) {
        return { kind: 'unsupported', reason: 'Workspace trust is required before auto-accept can start.', actionsEnabled: false };
    }
    if (platform === 'win32') {
        if (!/^antigravity(?: ide)?\.exe$/i.test(path.win32.basename(executable))) {
            return { kind: 'unsupported', reason: 'This extension only runs inside Antigravity IDE.', actionsEnabled: false };
        }
        return { kind: 'windows-uia', script: 'src/autoClicker.ps1', actionsEnabled: true };
    }
    if (platform === 'linux') {
        /* 2026-10-14：Linux 名称大小写敏感，Python 探针还会核对实际进程路径和启动时间。 */
        if (!path.posix.isAbsolute(executable) || !['antigravity', 'antigravity-ide'].includes(path.posix.basename(executable))) {
            return { kind: 'unsupported', reason: 'A verified local Antigravity IDE Linux executable is required.', actionsEnabled: false };
        }
        return { kind: 'linux-atspi-diagnostic', script: 'src/linux/atspi_probe.py', actionsEnabled: false };
    }
    return { kind: 'unsupported', reason: 'This operating system has no supported backend.', actionsEnabled: false };
}
