# 🚀 Antigravity Auto Accept (The Ultimate Permission Bypass)

**Tired of Gemini Antigravity violently interrupting your workflow to ask for "Run" or "Allow" permissions?**  
Say no more. This extension is the **absolute ultimate, nuclear-grade** solution to completely bypass and automate every single permission prompt thrown your way by the IDE or other extensions.

## ✨ Why is it so powerful?
VS Code and the Electron framework are notoriously difficult to automate due to their locked-down UI, shadow DOMs, and non-standard security layers. This extension doesn't just passively click; it employs a **4-Tiered Defense-in-Depth Matrix** to ensure that NO prompt survives longer than 1.5 seconds.

### 🛡️ The 4-Tier Annihilation Protocol:

1. **The Phantom (VS Code Native Toast Poller):**
   *(Newest Weapon)* Electron Notification Toasts are essentially invisible to Windows OS-level tools. For this, we bypass the OS entirely and inject a constant Poller into VS Code's extension host. Every `500ms`, it blindly executes `vscode.commands.executeCommand('notifications.acceptPrimaryAction')`. If a toast exists, its primary button ("Run Alt+↵") is destroyed from the inside out.

2. **The Diplomat (UI Automation API):** 
   A lightweight, invisible PowerShell background process tirelessly scans the Windows OS UI tree for explicit confirmation semantics (`Allow`, `Approve`, `Run`, `许可`, `确认`, etc.) on standard windows and invokes them using standard .NET Event Triggers.
   
3. **The Hacker (user32.dll Keyboard Injection + RuntimeId Cache):**
   If Electron attempts to swallow or ignore the API trigger, the script instantly drops to the native Windows C++ API (`user32.dll`), focuses the target, and violently injects a physical `Alt + Enter` keystroke directly into the operating system's event queue. 
   ***v1.2.0 Upgrade:*** To prevent the script from aggressively scrolling your window and stealing your focus whenever it detects an older, already-clicked button remaining in your chat history, we implemented a strict `RuntimeId` HashSet cache. The script extracts the memory fingerprint of every button it kills and permanently blacklists it. Perfect silence, zero scroll-stealing.
   
4. **The Encoder (Base64 UTF-16LE Execution):**
   *(Crucial Fix)* Native Windows `CreateProcess` calls from Node.js notoriously mangle strings on non-English locales (e.g., Chinese usernames). To ensure the background script ALWAYS launches, the extension strictly compiles the launch parameters into a raw Base64 UTF-16LE binary payload and invokes PowerShell via `-EncodedCommand`. Path corruption is mathematically impossible.

### 🔁 Bonus: Never Stop Generating
If Antigravity gets interrupted due to network timeouts and throws the dreaded red/blue **"Retry / 重试"** button, this extension's UIAutomation scanner will violently click it the exact millisecond it appears. Your AI agent essentially becomes immortal.

## ⚡ Installation & Usage

**1. Download the Extension:**
   - Head over to the [Releases page](../../releases) of this repository.
   - Download the latest `antigravity-auto-accept-X.X.X.vsix` file to your computer.

**2. Install in Antigravity / VS Code:**
   - Open your IDE and go to the **Extensions** view (`Ctrl+Shift+X` or `Cmd+Shift+X`).
   - Click the `...` (Views and More Actions) icon at the top right of the Extensions panel.
   - Select **"Install from VSIX..."** from the dropdown menu.
   - Locate and select the `.vsix` file you just downloaded.
   - **Important:** Restart your IDE after installation.

**3. How to Use:**
   - **Zero Configuration:** The extension is fully automatic. It activates entirely on its own the moment your IDE breathes. You don't need to do anything.
   - **Manual Toggle:** If you ever need to pause the auto-clicker, press `F1` (or `Ctrl+Shift+P`) to open the Command Palette, and type:
     - `Antigravity Auto Accept: Start Auto-Clicker`
     - `Antigravity Auto Accept: Stop Auto-Clicker`ccept`

---
*Built with pure rage against permission popups.*
