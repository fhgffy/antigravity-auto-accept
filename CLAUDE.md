# Antigravity Auto Accept

## 项目概况
VSCode/Antigravity 插件，自动点击 Antigravity IDE 的权限弹窗（Run/Accept/Allow 等按钮）。
- 发布者：fhgffy
- 仓库：https://github.com/fhgffy/antigravity-auto-accept
- 双平台累计 2,400+ 安装量，评分 5.0/5

## 当前版本：v5.0.0（CDP 架构，2026-03-29）

### 架构变更
v4.0.0 及之前使用 PowerShell + UIAutomation + user32.dll 物理鼠标点击方案。
2026年2-3月 Antigravity 连续更新（v1.18.4 → v1.20.x），内部 Chromium webview UI 结构变化，
UIAutomation 无法穿透 Electron webview 看到内部按钮，导致插件完全失效。

v5.0.0 全面迁移到 Chrome DevTools Protocol (CDP)：
- `cdpClient.ts` — CDP WebSocket 客户端，HTTP 获取 targets，WebSocket 执行 JS + Input.dispatchMouseEvent 模拟点击
- `buttonDetector.ts` — 注入 webview 的 JS 脚本，DOM TreeWalker 扫描 25+ 种按钮文本
- `shortcutPatcher.ts` — 自动修补 Windows 快捷方式添加 `--remote-debugging-port=9222`
- `extension.ts` — 500ms 轮询 + 800ms cooldown，状态栏 toggle 按钮

### 使用前提
Antigravity 必须以 `--remote-debugging-port=9222` 启动。插件首次检测到端口未开放会弹窗提示一键修补。

### 待验证/待完成
- [ ] 实际安装到 Antigravity 中测试 CDP 连通性
- [ ] 验证按钮文本匹配是否覆盖最新版 Antigravity 的所有弹窗类型
- [ ] 测试 shortcutPatcher 是否正确修补快捷方式
- [ ] 考虑是否需要 MutationObserver 替代轮询（性能优化）
- [ ] 更新 README.md 说明新架构和安装步骤
- [ ] 发布到 VS Code Marketplace

### 竞品参考
- knarfy/antigravity-autoaccept — 已 clone 到 C:/Temp/knarfy-aa，架构参考来源
- pesoszpesosz/antigravity-auto-accept — CDP + 控制面板方案
- yazanbaker94/AntiGravity-AutoAccept — WebSocket 持久连接 + MutationObserver

## 编译命令
```bash
npm install
npx tsc -p ./
npx vsce package --no-dependencies
```

## 语言要求
- 代码注释用中文
- 用户面向的 UI 文本用英文（国际用户为主）
- printf/日志用英文
