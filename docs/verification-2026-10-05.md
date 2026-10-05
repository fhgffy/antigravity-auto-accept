# v5.3.0 验证记录

工作开始于 2026-10-05；最终实机验收于 2026-10-06，时区 Asia/Shanghai。

## 结论与证据范围

**证据等级：已读源码、已跑编译/回归、已跑实机验证。** 在本地 Windows、Antigravity IDE 2.5.5 中，v5.3.0 自动启动，并能把一个真实待审批的终端任务从等待状态推进到执行完成。审批选择为“仅允许本次”，未选择永久允许。

这验证了下述终端审批卡片，不能证明所有工具、远程环境、旧版 IDE 或未来版本都兼容。Strict Mode、拒绝名单、企业策略和底层沙箱限制仍由 IDE 执行。

## 实机对照

1. 在空的临时工作区安装生成的 VSIX，执行 **Developer: Reload Window**。扩展输出版本 5.3.0，扫描器自动进入 READY，使用默认 500ms 扫描和 1500ms 冷却。
2. 点击扩展状态栏关闭扫描器。通过 Computer Use 给 Agent 发送一次任务，只运行 `Write-Output ANTIGRAVITY_AA_FINAL_V53`。
3. 扫描 OFF 时，IDE 显示 `Waiting for user input`，同一个审批卡片一直等待。控件包括 `Edit permission target`、`Yes, allow this time`、两个永久允许选项、拒绝选项，以及 `Submit ↵`。
4. 只点击扩展状态栏开启扫描器；未人工选择或点击审批控件。插件自动选择一次允许并提交同一卡片。
5. Agent 报告原始输出 `ANTIGRAVITY_AA_FINAL_V53`，退出码 **0**。任务完成后继续观察扩展日志，没有历史 Run 记录点击。

脱敏日志：

```text
[00:01:14] Antigravity Auto Accept 5.3.0 (UIAutomation) activating...
[00:01:17] UIAutomation scanner ready
[00:01:33] Stopping scanner...
[00:03:33] Starting UIAutomation scanner
[00:03:35] UIAutomation scanner ready
[00:03:36] Auto-accepted (Invoke): "Submit (one-time permission)"
```

本次测试没有修改 IDE 的终端自动执行、永久允许或拒绝名单配置。可信工作区由测试者选择；插件不批准工作区信任弹窗。

## 回归与编译

| 验证 | 结果 | 证据含义 |
| --- | --- | --- |
| TypeScript 编译与 `--noEmit` | 退出码 0 | 类型和产物构建通过 |
| 匹配规则 SelfTest | 每个引擎 93 项通过 | 中英文、快捷键、历史标题和通用按钮匹配规则 |
| 扩展生命周期 | 20/20 通过 | 旧 child 退出、重启取消、UTF-8 分段、宿主/信任门控、真实 PowerShell 引导 |
| 扫描器回归，PS5 + PS7 | 28/28 通过 | 审批卡片作用域、一次选择、父退出、互斥接管和点击边界 |
| 仅系统 PowerShell 5.1 | 27/27 通过 | 不依赖额外安装 PowerShell 7 |
| 最终独立代码审查 | 无未解决 P1/P2 | 查询期间父退出的最后一次 Invoke 为 0 |
| UTF-8、CRLF、AST、diff | 通过 | UTF-8 无 BOM；无孤立换行；PowerShell 解析和 diff 无错误 |
| `npm audit` | 0 漏洞 | 当前锁文件的 npm 审计结果 |

回归在无点击桩或隔离子进程中运行；只有上面的固定输出任务使用了真实 IDE 审批。

## 修复前后

- 旧扩展在 stop/start 后收到旧子进程 exit，会丢失新扫描器状态；生命周期回归验证新实例保持有效。
- 实机控件树表明 `Run Write-Output ANTIGRAVITY_AA_FINAL_V53?` 是记录展开按钮，新版真正审批是单选项加 Submit。新的扫描器定位同一卡片并提交一次允许。
- 初版修复完成审批后还点击 `Run Write-Output ANTIGRAVITY_AA_SMOKE_V53` 历史记录；最终匹配规则将任意命令正文标题排除，实机日志不再出现该点击。旧版静态审批标签 `Run command` 仍可匹配。
- 初检后选中状态丢失或查询期间父进程退出，早期检查仍可能 Invoke；最终回归要求提交次数为 0。

## 安装包与复现

```powershell
npm ci
npm test
npm run package
```

VSIX 包含 8 项：两个清单、LICENSE、图标、package.json、README、`out/extension.js` 和 `src/autoClicker.ps1`。测试、旧 CDP 产物、本地日志和协作记录不进入安装包。

工作区、VSIX 与实际安装的运行文件 SHA-256：

```text
src/autoClicker.ps1 = 50A247E28D4D16F66F01C23298B7BFF31C592E95F8F918F8255CA95FA5B59C79
out/extension.js   = 03F1B2785D613E52A9C81BF14AE1D10D687B2D9A69260BE2C41F1A0A40B38414
```

打包工具会将说明书相对链接改为仓库链接，因此 README 源文的字节哈希不同；VSIX 与已安装 README 一致。Release 提供对应 VSIX 的 SHA-256 校验文件。

## 尚未实机验证

旧版 Antigravity、中文界面、WSL/SSH/Container、遮挡窗口的物理点击回退、多窗口真实接管和其它工具审批类型，尚未完成逐项端到端验收。macOS/Linux 不支持此 Windows UIAutomation 扫描器。v5.3.0 尚未发布到 Marketplace/Open VSX，当前修复通过 GitHub Release 的 VSIX 提供。
