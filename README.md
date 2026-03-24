# 🚀 Antigravity Auto Accept

**The Ultimate Permission Bypass for Gemini Antigravity IDE**
**Gemini Antigravity IDE 终极权限自动放行插件**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![VS Code](https://img.shields.io/badge/VS%20Code-%3E%3D1.80.0-blueviolet.svg)](https://code.visualstudio.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6.svg)](#)
[![Remote](https://img.shields.io/badge/Remote-WSL%20%7C%20SSH%20%7C%20Container-success.svg)](#-remote-development-support--远程开发支持)

> **Tired of permission popups interrupting your AI workflow?**
> This extension deploys a 4-tiered annihilation protocol to automatically bypass every single permission prompt — `Allow`, `Run`, `Approve`, `Retry` — the millisecond it appears. Your AI agent becomes immortal.
>
> **受够了权限弹窗打断你的 AI 工作流？**
> 本插件部署四重毁灭协议，在弹窗露头的第一毫秒自动灭杀一切权限确认 —— `允许`、`运行`、`确认`、`重试` —— 让你的 AI 助手化身不朽机器。

---

## ✨ How It Works | 工作原理

### 🛡️ The 4-Tier Annihilation Protocol | 四重毁灭协议

<table>
<tr>
<th width="180">Tier</th>
<th>Mechanism</th>
</tr>
<tr>
<td>

**👻 Tier 1 — The Phantom**
幻影层

</td>
<td>

Injects a poller directly into VS Code's extension host. Every **500ms**, it blindly fires `notifications.acceptPrimaryAction` to destroy Toast notifications from the inside — completely invisible to Windows.

在 VS Code 扩展宿主内注入轮询器，每 **500ms** 盲发原生指令，从内部瓦解 Toast 通知。对 Windows 完全隐形。

</td>
</tr>
<tr>
<td>

**🤝 Tier 2 — The Diplomat**
外交官层

</td>
<td>

A PowerShell background process scans the Windows UI Automation tree for permission keywords (`Allow`, `Approve`, `Run`, `许可`, `确认`...) and invokes them via .NET `InvokePattern`.

后台 PowerShell 进程扫描 Windows UI 自动化树，匹配权限关键词并通过 .NET `InvokePattern` 静默触发。

</td>
</tr>
<tr>
<td>

**⚡ Tier 3 — The Hacker**
黑客层

</td>
<td>

When Electron swallows the API trigger, drops to `user32.dll` C++ API and physically injects `Alt+Enter` into the OS event queue. Uses a `RuntimeId` HashSet cache to permanently blacklist killed buttons.

当 Electron 吞掉 API 触发时，降维调用 `user32.dll` 物理注入 `Alt+Enter`。使用 `RuntimeId` 哈希缓存永久拉黑已击杀按钮。

</td>
</tr>
<tr>
<td>

**🔐 Tier 4 — The Encoder**
编码者层

</td>
<td>

Compiles the PowerShell payload into Base64 UTF-16LE binary and invokes via `-EncodedCommand`. Path corruption on CJK systems is mathematically impossible.

将 PowerShell 载荷编译为 Base64 UTF-16LE 二进制，从数学层面断绝中文路径乱码。

</td>
</tr>
</table>

### 🔁 Bonus: Immortal Agent | 附赠：不死 Agent

Network timeout? `Retry` button? The scanner clicks it the exact millisecond it appears. Your AI agent never stops generating.

网络超时？`重试` 按钮？扫描器在它露头的第一毫秒按掉。你的 AI 助手永不断连。

---

## 🌐 Remote Development Support | 远程开发支持

> **v1.5.0 — Full Remote Environment Support!**

The extension declares `extensionKind: ["ui"]`, which forces it to **always run on your local Windows machine** — even when connected to remote environments. This ensures the Win32 UIAutomation APIs remain available.

本插件声明 `extensionKind: ["ui"]`，**始终在本地 Windows 侧运行** —— 即使连接远程环境也不受影响。

| Environment | Status |
|-------------|--------|
| 🖥️ Local Windows | ✅ Fully supported |
| 🐧 Remote - WSL | ✅ Supported (v1.5.0+) |
| 🔗 Remote - SSH | ✅ Supported (v1.5.0+) |
| 📦 Remote - Container | ✅ Supported (v1.5.0+) |

---

## ⚡ Installation | 安装

### Prerequisites | 前置需求

- **Windows 10/11** — Uses the native `powershell.exe` shipped with Windows
- No additional extensions required | 无需安装任何额外扩展

### Steps | 安装步骤

**方式一：插件商店搜索安装（推荐）**

在 VS Code / Antigravity 的扩展面板 (`Ctrl+Shift+X`) 中搜索 **`Antigravity Auto Accept`**（开发者: **fhgffy**），点击安装即可。

- [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=fhgffy.antigravity-auto-accept)
- [Open VSX Registry](https://open-vsx.org/extension/fhgffy/antigravity-auto-accept)

**方式二：手动下载 VSIX 安装**

1. **Download** the latest `.vsix` from the [Releases page](../../releases)
   从 [Releases 页面](../../releases) 下载最新 `.vsix` 文件

2. **Install** via `Ctrl+Shift+X` → `...` → **Install from VSIX...**
   通过扩展面板 → `...` → **从 VSIX 安装...**

3. **Restart** your IDE | **重启** IDE

> 💡 **Zero Configuration** — The extension activates automatically on IDE startup. No setup needed.
> **零配置** — 插件随 IDE 启动自动激活，无需任何设置。

### Manual Toggle | 手动启停

Press `Ctrl+Shift+P` and type:
- `Antigravity Auto Accept: Start` — 开启
- `Antigravity Auto Accept: Stop` — 关闭

---

## 📋 Changelog | 更新日志

### v1.5.2 — Premium Console Output (2026-03-24)
- ✨ Toolkit-style output: every log line now shows `[HH:mm:ss] emoji message`
- 🔇 Eliminated CLIXML/XML noise from PowerShell stderr — no more `[ERR]` blocks
- 🛡️ Fixed `InvokeMethodOnNull` crash when scanning buttons with null names
- 🔧 Moved `GetCurrentPattern` calls inside try/catch — "不支持的模式" errors no longer leak to stderr
- 🎨 Tag-based emoji architecture: PS1 outputs `[AA:TAG]` plaintext, TypeScript renders emojis (avoids pipe encoding issues)
- ✨ Toolkit 风格输出：每行日志显示 `[HH:mm:ss] emoji 消息`
- 🔇 彻底过滤 PowerShell CLIXML/XML 噪音——不再出现 `[ERR]` XML 块
- 🛡️ 修复扫描无名称按钮时的 `InvokeMethodOnNull` 崩溃
- 🔧 `GetCurrentPattern` 调用移入 try/catch——"不支持的模式"错误不再泄漏到 stderr
- 🎨 标签化 emoji 架构：PS1 输出纯文本标签，TypeScript 侧渲染 emoji（避免管道编码乱码）

### v1.5.1 — Phantom Command Fix (2026-03-22)
- 🔇 Fixed `command 'antigravity.agent.acceptAgentStep' not found` error in status bar (Issue #3)
- 🔇 修复 Antigravity IDE 状态栏反复弹出"命令未找到"的报错 —— 原因是 IDE 内置扩展声明了 keybinding 但从未注册该命令（幽灵命令），本插件现在会自动注册兜底版本

### v1.5.0 — Remote Environment Support (2026-03-22)
- 🌐 Added `extensionKind: ["ui"]` — full support for WSL / SSH / Container remote environments
- 🌐 新增远程开发支持 — WSL / SSH / Container 环境下插件正常工作 (Issue #2)

### v1.4.0 — Directory Permission Auto-Accept (2026-03-21)
- 🔓 Fixed `Allow Once`, `Allow This Conversation`, `Allow All` buttons not being auto-clicked
- 🔓 修复目录权限弹窗中多词按钮无法自动点击的问题

### v1.3.9 — Browser JS Execution Fix (2026-03-21)
- 🌐 Added `Proceed`, `Execute`, `继续`, `执行` keywords for browser JS execution dialogs (Issue #1)
- 🌐 新增浏览器 JS 执行权限对话框的自动确认支持

### v1.3.8 — Ultimate Anti-Jitter (2026-03-21)
- 🔇 Eradicated scrollbar twitching from historical buttons
- 🔇 One-Click-Per-Cycle break mechanism

### v1.3.5 — Ghost Protocol (2026-03-20)
- 👻 `ScrollIntoView` for off-screen buttons
- 👻 Stealth focus switching — returns control to your browser/game in < 100ms

### v1.2.0 — RuntimeId Cache (2026-03-19)
- 🧠 Permanent RuntimeId blacklist prevents re-clicking historical buttons
- 🧠 Base64 UTF-16LE encoding for CJK path support

---

## ⚠️ Pro Tip | 使用技巧

> **Don't minimize the IDE!** Chromium suspends the accessibility tree when minimized.
> Instead, keep the IDE open behind your browser/game — the Ghost Protocol handles everything silently underneath.
>
> **不要最小化 IDE！** Chromium 最小化后会断开无障碍树。
> 正确做法：让 IDE 平敞在桌面上，用浏览器/游戏盖住它。幽灵协议会在底层静默猎杀一切弹窗。

---

## ☕ Support | 赞赏支持

If this extension saved your sanity and your mouse, consider buying me a coffee!
如果这个插件拯救了你的鼠标和精神状态，欢迎投喂一杯咖啡！

<p align="center">
  <img src="./sponsor.png" alt="赞赏码 / Sponsor QR Code" width="300" style="border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
</p>

---

<p align="center">
  <i>Built with pure rage against permission popups.</i><br>
  <i>出于对权限弹窗的纯粹愤怒而开发。</i>
</p>
