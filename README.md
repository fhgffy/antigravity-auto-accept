# 🚀 Antigravity Auto Accept (The Ultimate Permission Bypass)

**Tired of Gemini Antigravity violently interrupting your workflow to ask for "Run" or "Allow" permissions?**  
Say no more. This extension is the **absolute ultimate, nuclear-grade** solution to completely bypass and automate every single permission prompt thrown your way by the IDE or other extensions.

## ✨ Why is it so powerful?
VS Code and the Electron framework are notoriously difficult to automate due to their locked-down UI, shadow DOMs, and non-standard security layers. This extension doesn't just passively click; it employs a **4-Tiered Defense-in-Depth Matrix** to ensure that NO prompt survives longer than 1.5 seconds.

### 🛡️ The 4-Tier Annihilation Protocol:
1. **The Diplomat (UI Automation API):** 
   A lightweight, invisible PowerShell background process tirelessly scans the Windows UI tree for explicit confirmation semantics (`Allow`, `Approve`, `Run`, `许可`, `确认`, etc.) and invokes them using standard .NET Event Triggers.
   
2. **The Hacker (user32.dll Keyboard Injection):**
   If Electron attempts to swallow or ignore the API trigger (which it often does), the script instantly drops to the native Windows C++ API (`user32.dll`), focuses the target, and violently injects a physical `Alt + Enter` keystroke directly into the operating system's event queue. 
   
3. **The Sniper (Physical Mouse Teleportation):**
   If the prompt blocks keyboard events, the script calculates the exact X/Y coordinate bounding box of the button on your 4K monitor. It then uses native API `SetCursorPos` and `mouse_event` to literally teleport your mouse cursor and perform a sub-millisecond physical left-click on the target. Unblockable.

4. **The Insider (VS Code Native QuickPick Bypass):**
   Some prompts are actually VS Code native QuickPicks drop-downs that remain perfectly untraceable by external Windows tools. For these, the extension runs a sleeper cell *inside* the Node.js Main Process, constantly polling `workbench.action.acceptSelectedQuickOpenItem` every 1.5 seconds to quietly hit `Enter` on any active drop-downs on your behalf.

## ⚡ Setup & Activation
- **Zero Configuration:** Just install the `.vsix` file.
- **Always On:** It activates on the `*` startup event. The moment VS Code breathes, this extension is already hunting.
- **Manual Overrides:** Use the Command Palette to pause its wrath if needed:
  - `> Start Antigravity Auto Accept`
  - `> Stop Antigravity Auto Accept`

---
*Built with pure rage against permission popups.*
