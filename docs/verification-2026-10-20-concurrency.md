# 并发审批验收：5.3.11

证据等级：已读源码、已跑验证。原生验收跨 2026-10-20/21；发布状态与本机运行结果分别核验。

## 版本与范围

- 基线：5.3.10，提交 `18af5e960b8a7e385620e6e33cdddc0a83241386`。
- 第一轮归属日志候选扫描器 SHA-256：`1ddf83e151db893a9300b454b6d93971ca9d26f5d3769940aaabf10f66208a8c`；下文已完成的并发原生证据对应此字节版本。
- 资源寿命修正扫描器 SHA-256：`528b83b22e77cc6e7d3e3408e407aa41ea14d834d26723aec68f209ee702f3db`，已完成下述 35.56 分钟原生复测。
- 扩展入口 SHA-256：`20677d86cced88f3f05d095d0d1d7a7a5364b77cb222c40ddd6752bd45d8d8d5`，入口未改动。
- Windows 本机 Antigravity IDE 2.5.5；真实任务使用 Gemini 3.8 Flash Medium。
- 独占测试根目录：`F:\CodexTests\AntigravityAA\concurrency-20261020-7d2c`。下文证据文件均相对于其 `evidence\`。
- 三个 IDE 使用独立配置和同一候选扩展目录；记录 PID、父 PID、创建时间、可执行路径及 HWND。Chrome 使用该测试根下的独立配置和回环 CDP 9222，只访问回环测试页。
- 未更改 IDE 信任、审批、拒绝列表、浏览器允许列表或系统安全设置。未对用户 Chrome 使用 Computer Use。

## 已确认的缺陷及修复

[Issue #19](https://github.com/fhgffy/antigravity-auto-accept/issues/19) 对应旧成功日志只有按钮标签的问题。5.3.10 的多个真实任务产生相同的 `Submit (one-time permission)` 文案，不能据此区分指定命令、模型额外准备命令或不同卡片。相同标签本身不是重复批准证据。

5.3.11 在原最终检查前保存窗口 PID、HWND、原元素身份与精确 UTF-8 目标 SHA-256，成功后只消费该快照。命令和域名正文不新增到日志；动作后不再查询已经可能消失的 UIA 元素。原审批匹配、宿主及卡片复核、输入保护、尝试次数和冷却保持原逻辑。

独立审查还复现合法通用标签 `Run\r\nAlt+Y` 将协议拆成两行的问题。日志标签现在转义 CR/LF，目标哈希仍使用原始字符串。两个动作路径均保留红例，并按单条成功协议行检查归属。

- 首次缺少归属红例：`approval-context-red.log`、`generic-context-red.log`。
- 换行红例与绿例：`generic-newline-red.log`、`generic-newline-green.log`。
- 最终资源修正版完整本地回归：`full-test-lifetime-final.log`，命令退出 0；扫描器 184 项、并发 22 项；编译、类型检查、仓库、发布、生命周期、宿主和物理输入回归均通过。早期 `full-test-M8-final.log` 的 175 项结果单独保留。
- 查询/UIA 恢复边界：`M8-recovery-loop.log`。
- 独立审查确认所有动作后日志不再新增 UIA 查询，启动载荷清理及精确 UTF-8 指纹正确；未发现剩余阻塞代码问题。

测试载荷增长曾触及 Windows 命令行上限，原失败保留在 `approval-context-green-all-routes.log` 和 `full-context-test.log`。两个测试启动器现通过自删 UTF-8 文件传递大载荷，不放宽任何动作、冷却或超时断言。

## 验收矩阵

| 项目 | 结论 | 实际证据与边界 |
| --- | --- | --- |
| M1 单窗单线程 | 通过 | 最终资源候选中，关闭 A/B 后仅 C5 运行；`C5-single-browser-complete.uia.json/.png` 对应实际访问 `/m7-c5-expiry-2348` 及准确页面标记，23:51:39 一次浏览器批准；`C5-single-m1-terminal-result.uia.json` 中的准确标记属于模型回复，并非原始 stdout；精确命令目标在 23:54:16 只有一次终端批准，原始 stdout 未独立捕获。`approval-events-final11.json` 按指纹及卡片核对。 |
| M2 同窗多任务 | 通过；文件审批子项不适用 | C2 中独立终端、浏览器和文件任务；终端与浏览器曾同时等待。`C2-m2-term-concurrent.png`、`C2-m2-browser-pending.png`、`C2-m2-three-history.uia.json`。终端/浏览器各一个成功事件且目标匹配；文件编辑工具直接写入指定文件，没有权限卡，不计批准。 |
| M3 双窗并发及接管 | 通过 | `A2-m4-pending.uia.json`、`B2-m4-pending.uia.json` 同时保留不同精确目标与卡片；C 扫描器随后各批准一次。Stop/关闭后的 C→A→B→C 接管由状态、进程退出回执和日志核对。 |
| M4 三窗含最小化 | 通过 | `A2-mixed-running.status.json`、`B2-mixed-running.status.json` 为 WAITING，`C2-mixed-running.status.json` 为 ON；C 最小化期间批准 A、B 的实际卡片。三个扫描器进程包含一个 owner 和两个等待者，不将等待者当重复 owner。 |
| M5 待批生命周期 | 通过 | `C2-m5-pending-background.png` 在 Restart/Stop 前保留待批；`M5-restart-after.json` 记录旧等待进程退出及新 PID，`M5-stop-owner.json` 记录旧 owner 退出。第二轮 `C2-m5-close-pending.png`、`M5-close-pending-A3.json`、`C2-m5-pending-after-second-reopen.png` 证明卡片跨关闭重开保留，A4 为 WAITING，恢复后一次允许。 |
| M6 输入与撤销重做 | 通过，沿用已验证原生输入基线 | 原生 65.202 秒、655 字精确、原生撤销/重做正确、1303 个前台样本无外来窗口；期间真实审批一次。`M6-native-block-equivalence.json` 确认 5.3.8、5.3.10 与候选内嵌 C# 输入实现完全相同（仅统一换行后比对）。 |
| M7 至少 30 分钟资源 | 通过；首轮失败后修复 | 最终 `resources-lifetime-final11.jsonl` 连续 2133.39 秒、312 个样本、8 次真实批准；两次 15 分钟自然刷新，含单窗口自动重试。`native-acceptance-final11.json`、`resource-statistics-final11.json`、`M7-refresh-card-attribution.json` 分别保存生命周期、完整资源统计和两张卡片跨刷新后的唯一批准。旧候选增长失败样本完整保留。 |
| M8 故障与恢复 | 通过，明确分层 | 沿用已验证的真实 60 秒无 READY 自动恢复；本轮实际生产扫描尾段对宿主查询失败和 UIA 失效各注入一次，恢复后一次动作，完成控件随后不再动作。查询/动作边界为内存替身，不称为真实原生提供者故障。 |

C2 并发任务身份来自原生历史列表：终端 `b8dd192b-76cc-47e4-a884-1849d951bd15`、浏览器 `5df3ffb0-50f5-445c-918e-442c4117d7f2`、文件 `3ec3d42e-b5aa-40ad-b430-6c7e5acb36a1`。切换历史会重新创建可见 UIA 元素，因此用任务身份、精确目标、实际输出及该次成功事件联合核对，不假设不同显示时刻的 runtime ID 永不变化。

候选第一轮 8 次真实成功事件已核对：五个终端命令目标各一次，三个独立浏览器卡片各 Allow Once 一次。相同域名文案产生相同目标哈希，卡片身份不同，不据哈希相同判重复。记录见 `approval-context-audit.json`，后续单窗收尾另行追加。

原生输入基线文件为 `F:\CodexTests\AntigravityAA\final538-20261020-8f91c2a7\evidence\A3-verification.json`；无 READY 基线见 [启动恢复报告](verification-2026-10-20-startup.md)。这些旧证据沿用，不标记为本轮重新执行。

## 资源与工具故障边界

[Issue #21](https://github.com/fhgffy/antigravity-auto-accept/issues/21)：同一 owner 的私有内存由约 84 MiB 持续增长到 150 MiB 以上，句柄基本稳定。独立只读 UIA 查询进程在每 600 次查询后强制 GC 仍增长，不能据 CLR 堆大小或 GC 推断原生分配根因。修复在原冷却与清理后检查 15 分钟单调计时，仅无待续办菜单时正常退出，沿用原自动接管/重试；原审批函数与 C# 输入实现不变。

独立审查发现初版无条件退出会丢失已展开无标签菜单的续办身份，该版本未安装。当前保护所有待续办记录；只有非最小化、非隐藏窗口成功查不到原 MenuId/PID 时才清理。`resource-deferred-green.log` 的 183 项检查覆盖继续办理、菜单消失、最小化、隐藏与菜单查询异常；故意移除保护的源副本在 `resource-deferred-injected-red.log` 失败（continued once=0、recycles=1、deferred=1），不把该注入红例冒充首次现场失败。

随后审查发现窗口句柄读取失败仍可误清记录。`resource-handle-red.log` 和第一次修正仍失败的 `resource-handle-green.log` 均保留；最终单次读取先拒绝 null/0，只有完整窗口身份快照才清理缺失 key。`resource-handle-green2.log` 为最终 184 项通过；审查者还独立执行 8 项实际尾段异常与后续恢复案例，通过后确认源码无剩余阻塞。该独立检查不冒充全套重跑或原生 UIA 故障注入。

`component-equivalence-final.json` 确认最终修正版与第一轮归属候选的 22 个 PowerShell 函数、内嵌 C# 输入实现及扩展 JavaScript 一致。此前 M2–M6 的审批与输入组件证据据此沿用；新增所有者寿命路径另由 `resources-lifetime-final11.jsonl` 重新连续实测，不能由组件等价推定 M7 通过。

最终候选第一轮自然刷新：C5 在 23:49:19 输出回收标记并以 0 正常退出，A5 的等待者取得所有权；C5 旧进程 30932 退出，新进程 64664 在 23:49:23 进入等待。`C5-natural-refresh-pending.uia.json/.png` 与 `C5-after-natural-refresh.uia.json/.png` 保存同一真实浏览器待批卡；`first-natural-refresh-window-audit.json` 的 651 个样本覆盖 23:48:54–23:50:06，C 全程最小化且没有 C 前台样本。正常关闭 A/B 后四个登记 PID 均退出，C 于 23:50:48 接管；其后恢复前台才批准该卡一次。

最小化窗口的首次 UIA 状态栏读取仍可返回旧文字，不能用其单次缓存值判定 owner。恢复后新 UIA 树和 `C5-after-natural-refresh.png` 均显示 WAITING，与该窗口日志一致；真实所有权结合 mutex 回归、进程与各窗口 READY/退出事件核对。第一张 C5 浏览器卡早在 23:43:39 批准，其旧待批截图未用于跨刷新结论；后续重建的卡片才具备上述前后证据。

单窗口第二轮自然刷新于 2026-10-21 00:05:48 正常退出，原进程 64664 消失；既有 3 秒重试启动进程 70724，00:05:52 收到 READY。`C5-second-refresh-pending.uia.json/.png` 与 `C5-second-refresh-retained.uia.json/.png` 的权限文本 runtime ID 同为 `42.263938.4.4.1.9842`，父卡片同为 `42.263938.4.4.1.9149`。00:07:25 只有一次对应批准；`C5-m7-final-result.uia.json/.png` 和回环请求记录证明新页面实际返回准确标记。`second-natural-refresh-window-audit.json` 的 941 个样本覆盖 00:05:26–00:07:10，C 一直最小化且隔离 Chrome 一直在前台。Win32 前台请求失败后改用刚观察到的隔离 Chrome 地址栏 UIA 焦点，没有输入文字或修改网址。

最终采样为 2026-10-20 23:34:28.509 至 2026-10-21 00:10:01.903，样本最大间隔 11.733 秒，中位间隔 5.732 秒。三个 C 扫描器进程的私有内存分别为 91.168→140.375、81.973→120.879、120.426→102.457 MiB；第三个进程的初始高值随后回落。所有扫描器的观测峰值为 A 接管初始化时的 158.637 MiB，未将该波峰隐藏；等待者约 83–85.5 MiB。扫描器句柄范围 559–700，没有跨刷新累积。原缺陷候选同一进程 36.58 分钟由 81.75→193.38 MiB 的失败见 `M7-first-candidate-failed.json`。

C 宿主整棵进程树的私有内存为 2326.98–3293.67 MiB，包含模型任务与渲染波动；末三个分钟时间桶（最后一个不足一分钟）的中位数为 3220.69、3231.04、3214.85 MiB，未呈持续单调增长。子进程数 296 个样本为 35，15 个样本为 34，自动重试间隙一个样本为 33；扫描器计数分别有 109 个三进程样本、202 个单进程样本、一个正常重试间隙零进程样本。计划关闭阶段明确保留 B 缺失 3 次、A 缺失 2 次；C 根进程未缺失。完整统计不以最小值或单个末值替代走势。

最终 8 条批准中，五个精确终端目标各一次、三个不同浏览器卡片各一次，同一窗口/卡片/目标组合无重复；两个跨刷新事件均与前后待批树的真实父卡片和目标哈希相符。原生日志没有 PowerShell、扫描器启动/输出或报告的 UIA 错误；正常退出和暂缓诊断单列。该通过结论限于已观察的桌面与任务条件，持续原生阻塞或未解决菜单可延期刷新，不宣称硬内存上限。

本轮开始阶段的系统重启见 `reboot-audit.json`。重启前进程已退出，重新登记 A2/B2/C2 后安装候选，不将该次系统重启归因插件崩溃，也不拼接两次系统启动的采样时长。

旧 `resources.jsonl` 使用日期字符串比较而错误报告根进程不存在，全部排除；`resources-valid.jsonl` 和 `resources-owner.jsonl` 只作为重启前的历史基线。最终候选采样通过 UTC ticks、PID、路径和当前登记关系识别进程，计划关闭重开的缺失根逐阶段报告。

观察工具曾遇到系统盘临时编译失败，现观察子进程 TEMP/TMP 固定在本轮 F 盘目录。Chromium 输入的 ValuePattern 可能保留已删除文本，截图及 TextPattern 用于交叉检查当前内容；仅清理与本轮已发送文案逐字相同的草稿。查询超时只结束自有观察进程，不重启被测产品。

独立审查确认 `C5-single-m1-terminal-result.png` 与 `A5-m7-mid-result.png` 是 276×45 的空白捕获，均保留为观察失败，不用于成功结论。M1 终端的批准归属由成功日志和精确目标指纹证明；模型回复中的输出标记不能替代原始终端 stdout。

## 发布与收尾

[PR #22](https://github.com/fhgffy/antigravity-auto-accept/pull/22) 合并前核对最后提交的完整 CI 及本矩阵；它包含归属和资源两个修复，原诊断草稿 #20 已关闭。合并后再核对 main CI。GitHub Release 原包发布后，两个商店上传同一原包，实际公开下载须通过 CI 现有原生产查询函数，逐项核对发布者、精确版本及 SHA-256。

发布回执及最终矩阵保存在测试根目录的 `final-report.md`；本机候选通过、PR 合并、商店上传回执和商店实际公开下载是不同证据，不互相替代。临时配置、浏览器及测试进程仅在记录身份核对退出后按固定目录白名单清理；证据目录保留。原工作区已有 lessons 改动完整保留，仅追加本轮经验。
