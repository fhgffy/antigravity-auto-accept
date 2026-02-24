# Antigravity Auto Accept

Automatically grants IDE permissions for Gemini Antigravity (clicks "Allow", "Approve", "Yes", etc.).

## How it works

When activated, the extension runs a small background PowerShell script using `UIAutomationClient` to periodically scan for VS Code dialogs with authorization buttons and clicks them automatically.

## Activation

The extension activates automatically on VS Code startup (`*` event). 
You can manually start or stop it using the Command Palette:
- `Start Antigravity Auto Accept`
- `Stop Antigravity Auto Accept`
