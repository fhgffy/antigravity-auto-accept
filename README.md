# 🚀 Antigravity Auto Accept (The Ultimate Permission Bypass)
*(English / 中文双语版)*

**Tired of Gemini Antigravity violently interrupting your workflow to ask for "Run" or "Allow" permissions?**  
Say no more. This extension is the **absolute ultimate, nuclear-grade** solution to completely bypass and automate every single permission prompt thrown your way by the IDE or other extensions.

**受够了 Gemini Antigravity 动不动就弹窗打断您写代码，非要您手动点击「运行」或「允许」才能继续？**  
别再忍了。这个扩展是**最究极的、核武级别**的终极杀手锏，专门用来彻底绕过并全自动灭杀 IDE 或插件抛向您的任何权限确认弹窗。

---

## ✨ Why is it so powerful? / 为什么它如此强大？

VS Code and the Electron framework are notoriously difficult to automate due to their locked-down UI, shadow DOMs, and non-standard security layers. This extension doesn't just passively click; it employs a **4-Tiered Defense-in-Depth Matrix** to ensure that NO prompt survives longer than 1.5 seconds.

VS Code 和底层的 Electron 框架因为对 UI 施加了严格锁定、使用了 Shadow DOM 以及非标准安全层，导致它们出了名的难以被外部自动化控制。但这个扩展绝不是简单的“模拟点击”——它部署了一套**四重深度防御矩阵 (4-Tiered Defense-in-Depth Matrix)**，确保没有任何一个弹窗能活过 1.5 秒。

### 🛡️ The 4-Tier Annihilation Protocol / 四重终极毁灭协议：

1. **The Phantom (VS Code Native Toast Poller) / 幻影 (原生 VS Code 轮询监听):**
   *(Newest Weapon)* Electron Notification Toasts are essentially invisible to Windows OS-level tools. For this, we bypass the OS entirely and inject a constant Poller into VS Code's extension host. Every `500ms`, it blindly executes `vscode.commands.executeCommand('notifications.acceptPrimaryAction')`. If a toast exists, its primary button ("Run Alt+↵") is destroyed from the inside out.
   *(最新武器)* Electron 的吐司通知气泡在 Windows 系统级自动化工具眼里几乎是隐形的。为此，我们直接绕过了操作系统，在 VS Code 的扩展宿主内注入了一个不间断的轮询器。每隔 `500毫秒`，它就会盲发一条原生指令 `notifications.acceptPrimaryAction`。如果当时正好有个弹窗，它的主按钮（“Run Alt+↵”）会直接被从内部瓦解摧毁。

2. **The Diplomat (UI Automation API) / 外交官 (UI 自动化 API):** 
   A lightweight, invisible PowerShell background process tirelessly scans the Windows OS UI tree for explicit confirmation semantics (`Allow`, `Approve`, `Run`, `许可`, `确认`, etc.) on standard windows and invokes them using standard .NET Event Triggers.
   一个极轻量、隐形的 PowerShell 后台进程会无休止地扫描 Windows 操作系统的 UI 树，寻找标准的权限确认语义（如 `Allow`, `Approve`, `Run`, `许可`, `确认` 等），并使用标准的 .NET 事件触发器将其默默点掉。
   
3. **The Hacker (user32.dll Keyboard Injection + RuntimeId Cache) / 黑客 (底层键盘注入 + 内存指纹缓存):**
   If Electron attempts to swallow or ignore the API trigger, the script instantly drops to the native Windows C++ API (`user32.dll`), focuses the target, and violently injects a physical `Alt + Enter` keystroke directly into the operating system's event queue. 
   ***v1.2.0 Upgrade:*** To prevent the script from aggressively scrolling your window and stealing your focus whenever it detects an older, already-clicked button remaining in your chat history, we implemented a strict `RuntimeId` HashSet cache. The script extracts the memory fingerprint of every button it kills and permanently blacklists it. Perfect silence, zero scroll-stealing.
   如果 Electron 试图吞掉或无视上面那步的 API 触发信号，脚本会瞬间降维打击，调用 Windows 最底层的 C++ API (`user32.dll`)，强制命中目标，并极其暴力地直接向操作系统的事件队列中物理注入一个 `Alt + Enter` 键盘敲击。
   ***v1.2.0 史诗升级：*** 为了防止脚本扫描到您聊天记录里残留的老旧弹窗按钮，从而导致疯狂拉拉扯您的滚动条或抢走您的窗口焦点，我们引入了极其严格的 `RuntimeId` 哈希缓存池机制。脚本会提取每一个被它杀掉的按钮的内存指纹，并将其永久拉黑。绝对静默，绝不抢焦点。
   
4. **The Encoder (Base64 UTF-16LE Execution) / 编码者 (Base64 UTF-16LE 执行防护):**
   *(Crucial Fix)* Native Windows `CreateProcess` calls from Node.js notoriously mangle strings on non-English locales (e.g., Chinese usernames). To ensure the background script ALWAYS launches, the extension strictly compiles the launch parameters into a raw Base64 UTF-16LE binary payload and invokes PowerShell via `-EncodedCommand`. Path corruption is mathematically impossible.
   *(关键修复)* Node.js 在非纯英文系统的 Windows 上调配本地进程时，极易发生路径中文乱码报错（比如用户名带中文）。为了确保咱们的后台杀手脚本 100% 能够被唤醒，扩展会强制把所有启动参数编译成最原始的 Base64 UTF-16LE 二进制载荷，并通过 `-EncodedCommand` 交给 PowerShell 执行。彻底从数学层面上断绝了路径乱码崩溃的可能。

### 🔁 Bonus: Never Stop Generating / 附赠神技：永不断连
If Antigravity gets interrupted due to network timeouts and throws the dreaded red/blue **"Retry / 重试"** button, this extension's UIAutomation scanner will violently click it the exact millisecond it appears. Your AI agent essentially becomes immortal.
如果 Antigravity 因为网络波动突然中断生成，并抛出了那个让人崩溃的红蓝相间的 **“Retry / 重试”** 按钮……不用怕！本扩展的底层扫描器会在它露头的第一毫秒极其暴力地帮您把它点掉。您的 AI 助手此刻真正化身唯心不朽的存在。

---

## ⚡ Installation & Usage / 安装与使用指南

**1. Download the Extension / 下载扩展:**
   - Head over to the [Releases page](../../releases) of this repository.
   - Download the latest `antigravity-auto-accept-X.X.X.vsix` file to your computer.
   - 前往本仓库的 [Releases (发布页)](../../releases)。
   - 下载最新版本的 `antigravity-auto-accept-X.X.X.vsix` 扩展安装包到您的电脑上。

**2. Install in Antigravity / VS Code / 在 IDE 中安装:**
   - Open your IDE and go to the **Extensions** view (`Ctrl+Shift+X` or `Cmd+Shift+X`).
   - Click the `...` (Views and More Actions) icon at the top right of the Extensions panel.
   - Select **"Install from VSIX..."** from the dropdown menu.
   - Locate and select the `.vsix` file you just downloaded.
   - **Important:** Restart your IDE after installation.
   - 打开您的 IDE (如 Cursor, VS Code, Antigravity)，进入左侧的 **扩展 (Extensions)** 面板 (`Ctrl+Shift+X`)。
   - 点击扩展面板右上角的 `...` (视图和更多操作) 小图标。
   - 在弹出的下拉菜单中选择 **“从 VSIX 安装... (Install from VSIX...)”**。
   - 找到并选中您刚才下载的 `.vsix` 文件。
   - **⚠️ 极其重要：安装完成后，请务必完全重启您的 IDE。**

**3. How to Use / 如何使用:**
   - **Zero Configuration / 零配置全自动:** The extension is fully automatic. It activates entirely on its own the moment your IDE breathes. You don't need to do anything.
   - 本扩展是**完全免配置**的。只要您的 IDE 启动，它就会像影子一样自动潜伏在后台并启动猎杀，您无需进行任何配置或点击开启。
   
   - **Manual Toggle / 手动启停开关:** If you ever need to pause the auto-clicker, press `F1` (or `Ctrl+Shift+P`) to open the Command Palette, and type:
   - 如果您有特殊需求需要暂停这个自动狂点的杀手，请按 `F1` (或 `Ctrl+Shift+P`) 呼出命令面板，然后输入：
     - `Antigravity Auto Accept: Start Auto-Clicker` (开启)
     - `Antigravity Auto Accept: Stop Auto-Clicker` (关闭)

---
*Built with pure rage against permission popups.* / *出于对权限弹窗的纯粹愤怒而开发。*
