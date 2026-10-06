# Antigravity Auto Accept

当前维护者：fhgffy；当前 AI 协作：Codex。历史提交保留原始作者信息。

## 项目概况
VSCode/Antigravity 插件，自动点击 Antigravity IDE 的权限弹窗（Run/Accept/Allow 等按钮）。
- 发布者：fhgffy
- 仓库：https://github.com/fhgffy/antigravity-auto-accept
- 安装量与评分以两个扩展商店的实时页面为准。

## 当前版本：v5.3.2（会话外终端审批兼容修复，2026-10-06）

### 架构变更
v4.0.0 及之前使用 PowerShell + UIAutomation + user32.dll 物理鼠标点击方案。
2026年2-3月 Antigravity 连续更新（v1.18.4 → v1.20.x），内部 Chromium webview UI 结构变化，
UIAutomation 无法穿透 Electron webview 看到内部按钮，导致插件完全失效。

v5.0.0 曾迁移到 Chrome DevTools Protocol (CDP)，v5.1.0 回归 UIAutomation。
v5.3.0 保持 UIAutomation 架构，在既有 v5.2.0 改动上修复宿主兼容、点击边界、进程生命周期和多窗口接管：
- `extension.ts` — 启动 PowerShell 后台扫描器、状态栏 toggle、配置变更自动重启、日志命令
- `autoClicker.ps1` — UIAutomation 扫描 Antigravity 窗口按钮，优先 InvokePattern，失败时物理点击并恢复鼠标位置
- `package.json` — 配置项、测试脚本、命令面板入口

v5.3.1 增加浏览器域名审批：宽布局直接选择 `Allow Once`，窄布局通过当前按钮的 ScrollItem/ExpandCollapse 模式滚入并展开菜单，再核对菜单归属并选择本次允许。浏览器专用批准标签不会进入全窗通用匹配。

v5.3.2 兼容替代输入框的会话外终端审批，按专用 permission target、同前缀单选项和唯一 Submit 核对表单；长命令仅滚动已核验的动作控件，重新验证目标值、表单归属和已选一次允许。普通问答不进入审批路径。

### 使用前提
Windows 10/11，本地可运行 `powershell.exe` 和 UIAutomation。无需 CDP 端口。

### 待验证/待完成
- [x] 已安装并重载 5.3.0，在 Antigravity IDE 2.5.5 验证同一个无害终端命令：扫描 OFF 时等待，ON 后自动批准一次并返回退出码 0
- [x] VSIX、工作区和已安装的扫描器/扩展运行文件 SHA-256 一致；说明书的相对链接由 VSCE 转为仓库链接，打包说明书与已安装说明书一致
- [x] 已安装并重载 5.3.1，在同一个真实浏览器任务验证宽布局和原窄布局连续本次批准；窄布局未人工滚动或批准。记录见 `docs/verification-2026-10-06.md`。
- [x] 安装重载 5.3.2，真实终端连续自动本次批准；会话外及长表单红绿回归通过，相同布局进一步实机验证待完成。记录见 `docs/verification-2026-10-06-terminal.md`。
- [ ] 按审批类型逐项实机验证；不能把字符串自测写成所有权限弹窗已验证
- [ ] 发布到 VS Code Marketplace
- [ ] 发布到 Open VSX

### 竞品参考
- knarfy/antigravity-autoaccept — 已 clone 到 C:/Temp/knarfy-aa，架构参考来源
- pesoszpesosz/antigravity-auto-accept — CDP + 控制面板方案
- yazanbaker94/AntiGravity-AutoAccept — WebSocket 持久连接 + MutationObserver

## 编译命令
```bash
npm install
npx tsc -p ./
npm test
npm run package
```

## 语言要求
- 代码注释用中文
- 用户面向的 UI 文本用英文（国际用户为主）
- printf/日志用英文

## 验证边界

- 代码和新测试使用中文注释，并带实际修改日期。保持 UTF-8 无 BOM 与 CRLF。
- 修改前检查 git 状态，保留维护者的未提交改动。
- 仅在可信 Windows Antigravity 宿主运行；不可点工作区信任或通用保存/确认按钮。
- 原生 Always Proceed、Strict Mode、拒绝名单和企业策略以官方文档为准，不承诺任何命令都能执行。
- Windows PowerShell 5.1 对 UTF-8 无 BOM 的 `-File` 读取需要显式 UTF-8 引导；修改后同时验证实际启动参数和中文匹配。
- 提交前执行 `npm test`、`git diff --check` 与 VSIX 内容检查；实机证据单独记录。
