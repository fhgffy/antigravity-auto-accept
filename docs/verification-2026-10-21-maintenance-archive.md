# 旧维护状态与更新日志归档（2026-10-21）

历史说明可能已过时；当前运行语义以 README 与对应 verification 为准。原始字节另存本轮测试根目录。

## 原 CODEX 状态

# Antigravity Auto Accept

当前维护者：fhgffy；当前 AI 协作：Codex。历史提交保留原始作者信息。

## 项目概况
VSCode/Antigravity 插件，自动点击 Antigravity IDE 的权限弹窗（Run/Accept/Allow 等按钮）。
- 发布者：fhgffy
- 仓库：https://github.com/fhgffy/antigravity-auto-accept
- 安装量与评分以两个扩展商店的实时页面为准。

## 当前代码版本：v5.3.12（自测去除桌面依赖，2026-10-21）

`-SelfTest` 跳过桌面根与扫描条件初始化，保留实际 C#、全部 95 项判定和原 15 秒上限。两种 PowerShell 的完整源码探针红绿验证均通过；22 个函数、内嵌 C# 及正常初始化内容未变。测试引导增加即时刷出的阶段旁证。此修复不能证明历史 CI PID9016 超时卡在桌面；具体卡点仍未确认。详见 [自测调查记录](docs/verification-2026-10-21-selftest-desktop.md)。Node22.23.3 完整 npm test、24项包装器及VSIX字节校验通过。最终head c264b5c的push/PR CI39472559033/39472569252全绿，PR #25合并后main39473575714四作业成功；Issue #26关闭。5.3.12 正式原包已由 main 39473575714 四作业成功后生成，标签固定3f5155521e53edeecf013d83d371da69970c3796，资产660118710、82204字节。下载包、GitHub digest、校验文件及8项VSIX/运行字节校验通过，SHA-256为a62d7cc64dc4079b86d597f9182cc6465a601e3b3b26c90ff47c41cadaf06a4d。已上架5.3.11原包保持不可变。

发布快照时间（UTC）：2026-10-20T18:29:37.3454587Z。Open VSX于2026-10-21 02:29:37+08:00通过原CI函数的精确版本及实际公开下载SHA核验，与GitHub原包一致，public-final12-openvsx.json；首次审核中404及会话Forbidden仍保留；Marketplace已选正式原包、需本人完成新图片验证码。该快照不计三处完成，不创建新凭据或绕过验证码。最新公开下载核验与完整收尾状态以 [Release记录](https://github.com/fhgffy/antigravity-auto-accept/releases/tag/v5.3.12) 及本轮 final-report.md 为准。

### v5.3.11 并发批准归属与扫描器资源寿命（2026-10-20）

成功日志增加已核验窗口 PID、HWND、卡片身份与精确目标 SHA-256；专用命令和域名正文不写入日志。通用按钮标签中的 CR/LF 转义为单行，目标哈希仍基于原始 UTF-8 字节。审批匹配、最终宿主及卡片复核、输入保护和冷却规则保留。

扫描所有者在 15 分钟到期且无待续办菜单时通过原 finally 释放，沿用既有等待者接管与 3 秒自动重试。菜单续办、最小化、隐藏或查询异常会推迟刷新；这限制可安全交接时的寿命，不保证绝对内存上限。该改动针对真实采样观察到的私有内存增长，不声称已确定 Windows 原生分配根因。

当前扫描器定向回归包含 184 项检查，完整回归与两种 PowerShell 引擎 CI 状态分别记录。实机多窗口、同窗多任务、生命周期和长时资源证据见 [本轮验收报告](docs/verification-2026-10-20-concurrency.md)。代码版本、已安装版本和商店公开版本须分别核验；发布完成以三处原包校验回执为准。

2026-10-21 本机资源候选完成 35.56 分钟、312 个样本、8 次真实批准和两次自然刷新；单窗口 3 秒自动重试、跨刷新待批卡片保留及一次批准均通过。M1–M8 已有结论，文件工具未产生权限卡的子项明确不适用；限制和逐项版本哈希见验收报告。PR #22 已合并至 d1a1532782d968a724044f2158846c09eaec7d1c，main CI 39457516301 全绿。GitHub v5.3.11 原包与 Open VSX 公开下载 SHA-256 均为 2da1df5fcea17e3792aeffa15bb5d9f644bee14e9e690bc3d1b4254b87a9252e；Marketplace 于 2026-10-21 01:42:02+08:00 实际公开下载核验通过，三处正式原包 SHA-256 一致；公开核验回执见验收报告。

维护测试另按 Issue #24 修正 SelfTest 子进程的管道反压及超时旁证；15 秒上限和所有失败条件保留。远端新增用例另暴露 RUNNER~1 短名被 .NET 展开造成严格路径断言假红，现统一夹具真实路径，保留原断言。Node 22.23.3 下两个引擎共 12 个新增真实进程用例、修正后的完整 npm test 及独立复核均通过；PR #23 已合并为 81db66af1f02a4188b4cc3ac0f9b2241b05b3d19；最终 push/PR CI 39466344735/39466354898 与 main CI 39467406873 均通过。成功作业未打印规范化前 TEMP，短名差异由先前原始 CI 红例及只读探针证明。该测试工具修复不改变插件运行文件或已发布原包；首轮远端 SelfTest 超时的具体原因仍未确认。

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
- [x] 5.3.10 已在 GitHub Release、VS Code Marketplace、Open VSX 发布，三处原包哈希一致；作为本轮起点事实沿用。
- [x] 5.3.11 GitHub Release、VS Code Marketplace、Open VSX 三处实际原包下载 SHA-256 一致。
- [x] 本轮 M1–M8 均有结论及版本证据；终端/浏览器真实批准通过，文件工具未产生权限卡的子项记不适用，不泛化为全部审批类型已验证。

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


## 原 README 更新日志

## 📋 Changelog | 更新日志

### v5.3.12 — Desktop-independent SelfTest (2026-10-21)

- Skip desktop root and scan-condition initialization during `-SelfTest`; normal scanning keeps its existing initialization and approval paths.
- Add both-engine regression coverage that makes desktop access fail while requiring all 95 SelfTest cases, exit code 0 and empty stderr. Keep the original 15-second deadline and retain bootstrap-stage diagnostics on timeout.
- 自测不再访问不需要的桌面节点；正常扫描初始化与审批路径保持原逻辑。CI 原始偶发超时的具体卡点尚未确认，保留首次失败证据。

### v5.3.11 — Approval Attribution and Scanner Resource Lifetime (2026-10-20)

- Include the target window PID/handle, approval element identity and exact target SHA-256 in successful approval events, so concurrent tasks can be correlated with their recorded cards.
- Hash permission targets instead of adding command or domain text to the log; compute context before the existing final approval checks and do not query a disappeared card after the action.
- 并发批准日志补齐窗口、卡片和目标指纹，便于核对每张审批卡的实际提交；一次允许、单实例及输入保护规则保持原行为。
- Refresh a scanning owner after 15 minutes through the existing handoff/retry path, limiting observed private-memory growth during repeated UIAutomation queries. An expanded browser menu awaiting continuation delays refresh until it completes or is confirmed gone; this is a cooperative refresh rather than a hard memory cap. A sole enabled window may briefly show RETRYING during automatic restart.
- 长时扫描到期后自动交接或重试，无需手动重启；已展开的待续办菜单保留原所有者，最小化、隐藏或无法确认菜单状态时继续等待，避免刷新丢失审批归属。

### v5.3.10 — Accurate Scanner Status (2026-10-20)

- Only complete READY/WAITING protocol lines acknowledge scanner startup; diagnostic text mentioning those markers no longer cancels recovery or falsely changes the status bar.
- Approval and error events must start a protocol line, and their complete payload is retained even when it contains another marker.
- 修复普通日志提及握手标记时误报 ON/WAITING、导致启动恢复失效的问题；保留分段输出、空白边界及旧版等待握手兼容。

### v5.3.9 — Startup Recovery (2026-10-20)

- Restart a scanner that has not acknowledged startup within 60 seconds, instead of leaving the status bar at STARTING indefinitely.
- Keep normal WAITING handoffs alive; stop, unload, errors and replacement sessions cancel the old deadline.
- Recover without another setting or permission prompt; approval matching and input protection remain unchanged.
- 扫描器启动挂起一分钟后自动重试，正常等待接管不受影响，停止和卸载会取消恢复。
- See [verification](docs/verification-2026-10-20-startup.md) for regression and native IDE test evidence.

### v5.3.8 — Media-key Approval Recovery (2026-10-17)

- Prevent a stuck volume or playback key from indefinitely blocking approval in an otherwise idle foreground IDE.
- Keep typing, mouse, modifier, browser-navigation and application-launch keys protected, including rechecks immediately before an action.
- Report fixed reasons when browser menus are deferred, without logging typed text or key codes.
- 修复媒体键残留按下状态导致窄侧栏浏览器授权一直等待；本机原卡片已自动选择 Allow Once，无需扩大侧栏或设置 Always Allow。
- See [verification](docs/verification-2026-10-17-media-keys.md) for the reproduced cause and test scope.

### v5.3.7 — Held-key Input Protection (2026-10-16)

- Pause physical approval clicks while any keyboard or mouse button is held, including ordinary keys whose repeat has not yet updated the input timestamp.
- Recheck held keys immediately before the input batch; retain cursor, foreground, host and approval-identity guards.
- Add 28 production-path regressions covering held keys and keys pressed during final validation, with cursor restoration enabled and disabled.
- 物理回退补齐普通键长按保护；按住 Enter、字母、方向键等时暂缓点击，松开并恢复空闲后自动继续，无需新增配置。

### v5.3.6 — Button Filtering and Release Delivery (2026-10-07)

- Skip unrelated button state and geometry queries after the existing name filter; preserve action-time host, input and approval checks.
- Add production-loop regressions for ordinary buttons with throwing getters and disabled, offscreen, invalid-geometry and valid approval candidates.
- Publish verified main CI packages to GitHub Releases after tests pass. Marketplace and Open VSX publishing use configured credentials and report missing credentials explicitly.
- See [publishing instructions](docs/publishing.md) for release retry and store verification.

### v5.3.5 — Window Process Queries (2026-10-07)

- Query the current window's process image directly, avoiding repeated system-wide process enumeration.
- Recognize 64-bit IDE hosts from a 32-bit scanner and recheck the full installation path before each approval action.
- Reject exited processes on the same native handle; close query handles after success, failure or exceptions.
- Add real process-path and controlled failure regressions to PS5 x64/x86 and PS7 x64 CI.

### v5.3.4 — User Input and Approval Identity (2026-10-07)

- Yield physical fallback to active typing, dragging, held keys, covered targets and changed approval controls.
- Submit movement, press/release and optional restoration in one verified input batch; validate pixel normalization, screen/clip bounds and x86/x64 input layouts.
- Recheck browser permission target identity and menu ownership; support precisely linked menus already opened by the user.
- Add production-method input regressions to Windows CI for PS5 x64/x86 and PS7 x64.

### v5.3.3 — Multi-window Reliability (2026-10-07)

- Rotate approval attempts across IDE windows so a busy first window does not delay others indefinitely.
- Isolate stale window/control failures, recheck action state after host lookups, and avoid a second physical click after an Invoke error.
- Keep the scanner running when notification preferences change; preserve a deliberate OFF during a workspace-trust transition.
- Validate both PowerShell engines, concurrent scanner ownership and handoff, source encoding, and VSIX contents in GitHub CI.
- Permission forms require a readable SelectionItem selection; unsupported legacy-only controls are skipped.

### v5.3.2 — Terminal Approval Form Placement (2026-10-06)

- Recognize dedicated command permission forms rendered outside the conversation.
- Scroll the verified one-time option and same-form Submit into view for long commands.
- Recheck the permission target, selection, form identity and owning host before acting; keep ordinary questions excluded.

### v5.3.1 — Browser Approval Cards (2026-10-06)

- Recognize the browser domain permission card and choose Allow Once.
- Handle the narrow sidebar where Allow Once is folded into More actions.
- Keep browser approval scoped to the active card and preserve command one-time approvals.

### v5.3.0 — Compatibility and Lifecycle Repair (2026-10-05)

- Support the current one-time permission card and its scoped Submit button; exclude completed Run tool records.
- Support the current `Antigravity IDE.exe` and legacy Antigravity host names; verify window process ownership.
- Repair stop/start races, cancel delayed restarts, and let waiting windows take over scanner ownership.
- Support Chinese approval labels; exclude generic dialog actions and allow negative multi-monitor coordinates.
- Verify the physical click target, handle hidden windows conservatively, and stop when the owning extension host exits.
- Add lifecycle and scanner regression tests, Windows CI, and public contributor instructions.
- Explain native Always Proceed and the limits of automatic approval.

### v5.2.0 — Safer Matching + Cleaner Controls (2026-07-28)

- 🛡️ **误点修复**：收紧前缀匹配边界，`Application Settings`、`Continuous Integration` 这类普通按钮不再被 `Apply` / `Continue` 误判
- 🖱️ **鼠标体验优化**：物理点击回退后默认恢复鼠标原位置，减少抢鼠标感
- ⚙️ **新增设置**：支持配置自动启动、扫描间隔、点击冷却、鼠标恢复和通知开关
- 🧭 **新增命令**：支持命令面板重启扫描器、打开扩展日志
- 🧪 **测试链修复**：`npm run lint` 不再依赖缺失的 ESLint，新增 PowerShell 匹配规则自测
- 🔒 **依赖清理**：移除 v5.0 CDP 实验遗留的 `ws` 依赖，`npm audit` 回到 0 漏洞

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
