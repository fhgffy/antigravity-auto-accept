# 🚀 Antigravity Auto Accept v5.3.14

**Automatically accept supported agent approval buttons in Antigravity IDE on Windows.**
**Windows 上自动接受 Antigravity IDE 支持的 Agent 审批按钮，无需调试端口或命令白名单配置。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![VS Code](https://img.shields.io/badge/VS%20Code-%3E%3D1.80.0-blueviolet.svg)](https://code.visualstudio.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6.svg)](#)
[![Remote](https://img.shields.io/badge/Remote-WSL%20%7C%20SSH%20%7C%20Container-success.svg)](#-remote-development-support--远程开发支持)

> **Tired of permission popups interrupting your AI workflow?**
> This extension starts automatically in a trusted Antigravity workspace and uses Windows UIAutomation to accept supported `Run`, `Accept`, and `Allow` buttons. No CDP port or executable patching is required.
>
> **受够了权限弹窗打断你的 AI 工作流？**
> 插件在可信的 Antigravity 工作区自动启动，通过 Windows UIAutomation 接受支持的 `Run`、`Accept`、`Allow` 等审批按钮。无需 CDP 端口，也不修改 IDE 程序。

## Native permissions and scope | 原生权限与适用范围

Antigravity's [IDE settings documentation](https://antigravity.google/docs/settings?tab=ide) describes terminal **Always Proceed**, with denylist exceptions. Native permission features differ by product and platform: [Antigravity 2.0 and Antigravity IDE have separate release tracks](https://antigravity.google/docs/changelog). If your installed version's native controls meet your needs, they may be sufficient.

官方 IDE 设置文档提供终端 **Always Proceed**；原生权限能力因产品、版本和平台而异，不能把 Antigravity 2.0 / CLI 的 Turbo 说明直接当成本机 IDE 2.5.5 已验证的设置。如果当前版本的原生设置已经满足需求，可以直接使用。这个扩展保留的价值是兼容仍显示审批按钮的工作流和旧版 IDE；本次实测的是 IDE 2.5.5 的一次允许审批卡片。

- Installation enables scanning by default; a **trusted workspace, local Windows host, and accessible IDE window** are required. The extension does not change the IDE's permission settings.
- **Strict Mode, explicit denials, enterprise policies, sandbox restrictions, and browser denylist entries remain enforced by Antigravity.** This is not a guarantee that every command can execute.
- Workspace trust prompts and generic `Save`, `OK`, `Yes`, or `Retry` buttons are not agent approvals and are excluded. English and Chinese approval labels are supported.
- Command permission cards select **Yes, allow this time** and submit the same card. Browser domain cards select **Allow Once**, including the menu inside **More actions** in a narrow sidebar. Command cards in the conversation or input area keep the same strict form checks; long cards scroll only the verified action control into view. The scanner does not select **Always Allow** or expand historical command records.
- Narrow browser menus wait until the target IDE window is foreground and user input has been idle for 500ms; scanning resumes automatically when these conditions return. Direct **Allow Once** buttons and other supported approvals retain their background action path.
- 浏览器窄菜单在对应 IDE 窗口处于前台、输入空闲 500ms 后自动处理；切走或正在输入时暂缓，无需手动点批准。宽栏 **Allow Once** 和其它支持的审批继续使用后台动作路径。
- `InvokePattern` can work without moving the cursor. Physical fallback yields to user input and only acts on a revalidated button in the foreground Antigravity window; covered or changed targets are skipped.
- One scanner covers the desktop session's Antigravity windows from the same installation path. Other enabled windows wait to take over. Stop disables this window's scanner; another enabled window may continue scanning, including buttons in the stopped window. Workspace trust gates the scanner's host; scanning is not isolated per workspace.

默认安装即启动扫描，但前提是可信工作区、本地 Windows 和可访问的 IDE 窗口。“零配置”指无需额外扫描器配置，不代表绕过所有权限。未针对每个 IDE 版本、远程环境和审批类型进行实机验证。

Current maintenance: **fhgffy**, with **Codex** assisting fixes and tests. See [CONTRIBUTING.md](CONTRIBUTING.md) to help maintain the project. Historical Git commit authorship is preserved.

Window process and cross-architecture verification: [docs/verification-2026-10-07-process.md](docs/verification-2026-10-07-process.md). Latest user-input interference verification: [docs/verification-2026-10-07-input.md](docs/verification-2026-10-07-input.md). Multi-window and CI verification: [docs/verification-2026-10-07.md](docs/verification-2026-10-07.md). Earlier runtime notes remain in [docs/verification-2026-10-05.md](docs/verification-2026-10-05.md). A result on one IDE version does not establish compatibility with every permission type or future release.

---

## ✨ How It Works | 工作原理

```
┌─────────────────────────────────────────────────┐
│  Extension Host (TypeScript)                    │
│  ┌───────────────────────────────────────┐      │
│  │ Spawns PowerShell background process  │      │
│  │ 500ms polling · 1500ms cooldown       │      │
│  └───────────────┬───────────────────────┘      │
│                  │ stdout                        │
│                  ▼                               │
│  Parse ___CLICK_INVOKE___ / ___CLICK_PHYSICAL___│
│  → Log to Output Channel                       │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  PowerShell (autoClicker.ps1)                   │
│                                                 │
│  1. Scan Chrome_WidgetWin_1 windows             │
│     → Verify the owning Antigravity executable │
│                                                 │
│  2. Find all Button controls (UIAutomation)     │
│     → Match supported agent approval labels    │
│       in English and Chinese                   │
│     → Exclude: Run and Debug, Run Task,         │
│       Always run, Run Extension, ...            │
│                                                 │
│  3. Click via InvokePattern (API-level)         │
│     → Fallback: user32.dll physical mouse click │
└─────────────────────────────────────────────────┘
```

### Two-Layer Click | 双层点击

| Layer | Mechanism |
|-------|-----------|
| **InvokePattern** (preferred) | UIAutomation API-level invocation without explicit cursor or focus changes. Provider behavior is checked in runtime verification. |
| **Physical Click** (fallback) | Requires an idle foreground target, released input keys, and a revalidated button. Sends target movement, press/release and optional cursor restoration in one input batch, after checking screen and clip bounds. |

---

## 🌐 Remote Development Support | 远程开发支持

The extension declares `extensionKind: ["ui"]`, forcing it to **always run on your local Windows machine** — even in remote environments.

本插件声明 `extensionKind: ["ui"]`，**始终在本地 Windows 侧运行**。

| Environment | Status |
|-------------|--------|
| 🖥️ Local Windows | Supported scanner host; see verification notes for tested IDE versions |
| 🐧 Remote - WSL | Local UI extension design; remote end-to-end verification pending |
| 🔗 Remote - SSH | Local UI extension design; remote end-to-end verification pending |
| 📦 Remote - Container | Local UI extension design; remote end-to-end verification pending |

---

## ⚡ Installation | 安装

### Prerequisites | 前置需求

- **Windows 10/11** — Uses native `powershell.exe` and UIAutomation
- No CDP port, no additional setup | 无需 CDP 端口，无需额外配置

### Steps | 安装步骤

**方式一：插件商店搜索安装（推荐）**

在 VS Code / Antigravity 的扩展面板 (`Ctrl+Shift+X`) 中搜索 **`Antigravity Auto Accept`**（开发者: **fhgffy**），点击安装即可。

浏览器审批修复位于 **v5.3.1**，会话外终端审批与长表单滚动修复位于 **v5.3.2**，请核对商店显示的版本。若商店仍显示旧版本，请使用 GitHub Release 中对应版本的 VSIX。

- [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=fhgffy.antigravity-auto-accept)
- [Open VSX Registry](https://open-vsx.org/extension/fhgffy/antigravity-auto-accept)

**方式二：下载 VSIX | 手动安装步骤**

1. **Download** the latest `.vsix` from the [Releases page](https://github.com/fhgffy/antigravity-auto-accept/releases)
   从 [Releases 页面](https://github.com/fhgffy/antigravity-auto-accept/releases) 下载最新 `.vsix` 文件

2. **Install** via `Ctrl+Shift+X` → `...` → **Install from VSIX...**
   通过扩展面板 → `...` → **从 VSIX 安装...**

3. Run **Developer: Reload Window** or restart the IDE | 执行 **Developer: Reload Window** 或**重启** IDE

> 💡 **Automatic startup** — Scanning starts automatically in a trusted Antigravity workspace. Windows permission and workspace trust choices remain yours.
> **自动启动** — 在可信 Antigravity 工作区自动扫描，系统权限与工作区信任仍由用户决定。

### Manual Toggle | 手动启停

Press `Ctrl+Shift+P` and type:
- `Start Antigravity Auto Accept` — 开启
- `Stop Antigravity Auto Accept` — 关闭
- `Toggle Antigravity Auto Accept ON/OFF` — 切换
- `Restart Antigravity Auto Accept Scanner` — 重启后台扫描器
- `Show Antigravity Auto Accept Logs` — 打开输出日志

### Optional Settings | 可选设置

The defaults still work with zero configuration. Advanced users can tune these in Settings:

默认仍然是零配置即用。需要微调时，可以在设置里修改：

| Setting | Default | Purpose |
|---------|---------|---------|
| `antigravityAutoAccept.autoStart` | `true` | Start scanning automatically when the extension activates |
| `antigravityAutoAccept.pollMs` | `500` | UIAutomation scan interval |
| `antigravityAutoAccept.cooldownMs` | `1500` | Minimum delay after an approval action attempt |
| `antigravityAutoAccept.restoreCursor` | `true` | Include cursor restoration in the verified fallback input batch |
| `antigravityAutoAccept.showNotifications` | `false` | Show start/stop/restart notifications |

---

## 📋 Changelog | 更新日志

这里仅列用户可感知的运行变化；构建、自测和完整历史见[维护记录](docs/verification-2026-10-21-maintenance-archive.md)。

### v5.3.14 — 减少扫描中的无用读取

- 没有待处理浏览器菜单时，省去每轮额外的窗口属性读取。
- 减少终端审批诊断的重复查询，保留一次允许、实时复核和输入保护。
- Skip redundant window reads when no browser menu is pending, and avoid repeated terminal diagnostic queries.

### v5.3.13 — 多窗口扫描资源优化

- 降低多个 IDE 窗口同时开启时的扫描开销。
- 等待接管的窗口减少后台内存占用，保留原有一次允许和输入保护。

### v5.3.11 — 并发审批与长时运行

- 并发批准日志可对应具体窗口、卡片和目标，方便定位漏批或重复问题。
- 长时扫描通过自动交接/重试控制已观察到的资源增长；待续办菜单保留原归属。刷新可能延期，不保证硬内存上限。

### v5.3.10–v5.3.9 — 状态与启动恢复

- 状态栏按完整扫描器握手更新；启动一分钟未就绪时自动重试，正常等待接管不受影响。
- 停止、重启和卸载会取消旧扫描器的恢复任务。

### v5.3.8–v5.3.7 — 输入干扰保护

- 媒体键残留不会永久阻止空闲窗口审批；普通键、鼠标和修饰键仍受保护。
- 按键长按、输入期间及目标被遮挡时暂缓物理点击，恢复空闲后继续。

### v5.3.6–v5.3.3 — 兼容性与多窗口

- 减少无关按钮查询，兼容跨位数宿主；忙碌窗口不再长期阻挡其他窗口的审批。
- 按钮失效或单窗关闭不会中断其他窗口；调用报错后不再盲目追加物理点击。
- 物理回退保留前台、输入、目标和光标复核。

### v5.3.2–v5.3.0 — 一次允许审批

- 支持会话外终端表单、长卡片滚动和浏览器宽/窄布局的本次允许。
- 修复停止/启动、窗口接管与隐藏窗口处理；通用保存、确认、拒绝和始终允许不作为批准目标。

---

## ⚠️ Pro Tip | 使用技巧

> **Don't minimize the IDE!** Chromium suspends the accessibility tree when minimized.
> Keep the IDE window available. API invocation may work in the background; physical fallback skips points covered by another app.
>
> **不要最小化 IDE！** Chromium 最小化后会断开无障碍树。
> 保持 IDE 窗口可访问。API 调用可能支持后台审批；物理点击回退会跳过被其它应用遮挡的目标。

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
