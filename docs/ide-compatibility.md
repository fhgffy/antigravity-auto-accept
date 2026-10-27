# IDE 升级后的兼容性自检

2026-10-26：审批界面会随 IDE 版本、账号能力和权限设置变化。已有版本的回放或成功日志不能替代升级后的原生验收。

1. 在 F 盘建立本轮独立配置、扩展目录和测试工作区，记录实际 IDE/扩展版本、激活扩展路径与权限设置。不要更改日常使用配置、信任设置或已有持久允许规则。
2. 用自有无害目标分别触发终端命令、Read URL、浏览器域名访问、浏览器 JavaScript、工作区外文件读/编辑和 MCP 工具。每类分别记录是否真的出现审批；Read URL、浏览器域名与 JavaScript 分开计数。没有弹卡的成功工具调用不能证明该类审批已经覆盖。
3. 扫描器停止时保存原始 UIA 树和卡片：完整父链、卡片/目标 RuntimeId、精确目标值、一次允许选项及 Submit 或 Allow Once。开始扫描后，只接受同卡片的本次允许，核对精确目标及其 UTF-8 SHA-256、唯一成功日志和工具原始输出；模型复述、通用 Submit 文案或文件存在本身都不能代替这条证据链。
4. 升级后运行仓库回归、Windows PowerShell 5.1/PowerShell 7 对应脚本及打包校验。真实卡片发生变化时，先保留原始失败与快照，再加入注明来源的脱敏回放；结构推演样本必须继续标作 `derived-regression`。
5. 保留失败日志、原始工具输出及输入/前台影响记录。正常关闭本轮独立窗口，再按确切路径清理自建目录；不要据一次成功扩大到其他权限类型、远程环境或未来版本。

`Proceed` 计划审阅、问答翻页的 `Continue`、错误重发的 `Retry`、持久允许规则、登录认证和工作区信任属于需要人工判断的语义，默认排除。步数上限后的继续是另一种交互；本轮没有取得其真实卡片，不能把问答翻页的排除结论套用到它。不要为通过自检加入通用按钮白名单，也不要绕过拒绝规则、企业策略或沙箱限制。

本轮样本的解释边界：

- `mcp-one-time.json` 和 `read-url-one-time.json` 分别来自真实 MCP 与 Read URL 一次允许卡片。两者都使用统一权限表单，所以回放中的 `terminal=true` 表示该表单判定路径，不能据此把 MCP、Read URL 计成终端执行。
- MCP `compiler-fs/write_file` 卡片已有一次批准记录，但下游工具拒绝了测试路径，不能计作文件写入成功。已测配置下，原生工作区外读取和编辑确实成功，却没有触发文件审批；这与 MCP 卡片是不同证据。
- 本轮 JavaScript 尝试受到 `browser_subagent` 报告的官方 API 地区限制，未取得 JavaScript 审批卡及原始执行输出，不能记作验证通过。Read URL 回放也不能补足这一项。
- `agent-error-retry.json` 保留原始 `Retry` 的 `offscreen=true`。回归另直接调用生产名称判定验证其排除，不依赖不可见性冒充语义覆盖。
- 2026-10-27：`persistent-allow-excluded.json` 是明确标作 `derived-regression` 的权限范围负例。IDE 源码把 `Allow in Conversation` 用于会话范围，把 `Allow <hostname>` 用于保存浏览器名单；这些标签的生产匹配误判已在不点击桌面的条件下复现。5.3.15 收紧通用 `Allow`，保留精确标签和无歧义的完整快捷键，中文会话、工作区等持久范围也保持人工决定。它不是原生持久授权实测样本。
- 2026-10-27：`stdin-generic-approval.json` 来自正常终端 stdin 测试中的真实 `Approve? / Accept / Reject` 卡片。本机任务工具显示 `Sending input to Task`，所以只计作该通用工具许可，不能称为旧 `sendCommandInput` 专用卡。原始输入与工具输出要另外核对，通用日志中按钮名的哈希不能冒充 stdin 内容的指纹。

回放入口为 [scanner-replay.test.ps1](../tests/scanner-replay.test.ps1)，由现有扫描器回归调用；它验证生产判定函数，不执行桌面审批。
