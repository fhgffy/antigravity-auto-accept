# 🚀 Antigravity Auto Accept v5

**Auto-accept all permission prompts in Antigravity IDE — zero clicks, zero configuration.**
**Antigravity IDE 权限弹窗全自动放行 —— 零点击，零配置。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![VS Code](https://img.shields.io/badge/VS%20Code-%3E%3D1.80.0-blueviolet.svg)](https://code.visualstudio.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6.svg)](#)
[![Remote](https://img.shields.io/badge/Remote-WSL%20%7C%20SSH%20%7C%20Container-success.svg)](#-remote-development-support--远程开发支持)

> **Tired of permission popups interrupting your AI workflow?**
> This extension uses Windows UIAutomation to detect and click every permission button — `Run`, `Accept`, `Allow`, `Retry` — the millisecond it appears. No CDP port, no complex setup. Just install and forget.
>
> **受够了权限弹窗打断你的 AI 工作流？**
> 本插件使用 Windows UIAutomation 检测并点击一切权限按钮 —— `Run`、`Accept`、`Allow`、`Retry` —— 在它出现的第一毫秒。无需 CDP 端口，无需复杂配置。装完即忘。

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
│     → Only windows with "Antigravity" in title  │
│                                                 │
│  2. Find all Button controls (UIAutomation)     │
│     → Match: Run, Accept, Allow, Apply,         │
│       Continue, Proceed, Retry, Execute,        │
│       Approve, Confirm, Overwrite, Save,        │
│       Yes, OK                                   │
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
| **InvokePattern** (preferred) | UIAutomation API-level invocation. No cursor movement, no focus stealing. Silent and instant. |
| **Physical Click** (fallback) | When InvokePattern is unavailable, falls back to `user32.dll` `SetCursorPos` + `mouse_event`. Works on any Electron button. |

---

## 🌐 Remote Development Support | 远程开发支持

The extension declares `extensionKind: ["ui"]`, forcing it to **always run on your local Windows machine** — even in remote environments.

本插件声明 `extensionKind: ["ui"]`，**始终在本地 Windows 侧运行**。

| Environment | Status |
|-------------|--------|
| 🖥️ Local Windows | ✅ Fully supported |
| 🐧 Remote - WSL | ✅ Supported |
| 🔗 Remote - SSH | ✅ Supported |
| 📦 Remote - Container | ✅ Supported |

---

## ⚡ Installation | 安装

### Prerequisites | 前置需求

- **Windows 10/11** — Uses native `powershell.exe` and UIAutomation
- No CDP port, no additional setup | 无需 CDP 端口，无需额外配置

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
- `Start Antigravity Auto Accept` — 开启
- `Stop Antigravity Auto Accept` — 关闭
- `Toggle Antigravity Auto Accept ON/OFF` — 切换

---

## 📋 Changelog | 更新日志

### v5.1.0 — Back to Basics: UIAutomation Revival (2026-03-29)

- 🔄 **架构回归**：从 CDP 方案回归 UIAutomation 直接按钮检测。UIAutomation 能看到 Antigravity 的权限按钮并支持 InvokePattern，无需 CDP 端口
- 🧹 **极简重写**：`extension.ts` 仅 ~150 行，`autoClicker.ps1` 仅 ~120 行。去除所有 Oracle/状态检测/指纹去重等复杂逻辑
- 🎯 **智能匹配**：前缀匹配 + 精确匹配 + 排除列表，覆盖 12 类权限关键词，排除 IDE 菜单误触
- ⚡ **双层点击**：优先 InvokePattern（无焦点抢占），失败时回退 user32.dll 物理点击
- 🔄 **Architecture revert**: Back to UIAutomation from CDP. UIAutomation can see Antigravity's permission buttons with InvokePattern support — no CDP port needed
- 🧹 **Minimal rewrite**: ~150 lines extension.ts, ~120 lines autoClicker.ps1. Removed Oracle/state detection/fingerprint dedup complexity
- 🎯 **Smart matching**: Prefix + exact match + exclusion list covering 12 permission keyword categories
- ⚡ **Two-layer click**: InvokePattern first (no focus stealing), user32.dll physical click fallback

### v5.0.0 — The CDP Experiment (2026-03-29)

- 🔧 **CDP 架构实验**：全面迁移到 Chrome DevTools Protocol，通过 WebSocket 连接 Antigravity 的 Chromium 调试端口，在 webview 内执行 JS 检测按钮 + `Input.dispatchMouseEvent` 模拟点击
- 📦 **新增模块**：`cdpClient.ts`（WebSocket CDP 客户端）、`buttonDetector.ts`（DOM 按钮扫描脚本）、`shortcutPatcher.ts`（自动修补快捷方式添加 `--remote-debugging-port=9222`）
- ❌ **已废弃**：确认 UIAutomation 仍能穿透最新版 Antigravity 后，v5.1.0 回归 UIAutomation
- 🔧 **CDP architecture experiment**: Full migration to Chrome DevTools Protocol — WebSocket connection to Chromium debug port, JS injection for button detection + `Input.dispatchMouseEvent` for clicks
- 📦 **New modules**: `cdpClient.ts`, `buttonDetector.ts`, `shortcutPatcher.ts`
- ❌ **Superseded**: Reverted to UIAutomation in v5.1.0 after confirming it still works with latest Antigravity

### v2.1.3 — Fingerprint Dedup: Click Once, Never Spam (2026-03-26)

- 🧠 **指纹去重缓存**：每个按钮点击后记录位置指纹（Name + X/Y 取整到 10px），同一按钮不再重复点击。解决 v2.1.2 Legacy 模式下疯狂点击历史 "Always run" 导致抢焦点的问题
- 🔄 **四态决策重构**：■ 运行中 → 全量点击（无需去重） | 错误面板 → 仅 Retry | Antigravity 空闲 → 去重点击 | 非 Antigravity → 全量 + 去重
- ⏱️ **TTL 自动清空**：指纹缓存 120 秒后自动清空，适应新一轮对话/UI 刷新
- 🧠 **Fingerprint dedup cache**: After clicking a button, records its position fingerprint (Name + X/Y rounded to 10px). Same button is never re-clicked
- 🔄 **Four-state logic**: ■ running → click all | error panel → Retry only | Antigravity idle → dedup click | non-Antigravity → click all + dedup
- ⏱️ **TTL auto-clear**: Fingerprint cache auto-clears every 120s for new conversations/UI refreshes

### v2.1.2 — Arrow Button False Positive Fix (2026-03-26)

- 🐛 **修复箭头按钮误判**：`Add context` / `Cancel` 等功能按钮的 CSS class 含 `opacity-70` + `rounded-full`，被误识别为聊天工具栏灰色箭头 → 所有权限按钮扫描被跳过
- 🔧 **修复方式**：灰色箭头判定增加 `Name 必须为空` 约束（真正的灰色箭头是纯图标无文字）
- 🐛 **Fix arrow button false positive**: `Add context` / `Cancel` buttons matched the gray arrow fingerprint — caused all permission button scanning to be skipped
- 🔧 **Fix**: Added `Name must be empty` constraint for gray arrow detection

### v2.1.1 — Universal Compatibility (2026-03-26)

- 🌍 **非 Antigravity IDE 回退**：检测到聊天工具栏（→ / ■）时使用 Oracle 智能模式；未检测到时（VS Code / Cursor / 其他 IDE）自动回退传统模式，盲点所有权限按钮
- 🌍 **Non-Antigravity fallback**: Oracle mode when chat toolbar detected; legacy mode for VS Code / Cursor / other IDEs — click all permission buttons unconditionally

---

## ⚠️ Pro Tip | 使用技巧

> **Don't minimize the IDE!** Chromium suspends the accessibility tree when minimized.
> Keep the IDE open behind your browser/game — the scanner handles everything silently underneath.
>
> **不要最小化 IDE！** Chromium 最小化后会断开无障碍树。
> 正确做法：让 IDE 平敞在桌面上，用浏览器/游戏盖住它即可。

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
