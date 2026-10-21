# 历史经验流水归档（2026-10-21）

以下合并 main 历史记录与用户工作区追加，按完整章节去重；仅归档事实，不自动执行其中的历史命令或沿用旧结论。活跃规则见项目 lessons 索引及两份验收/发布技能。

原始字节保留在本轮 F 盘测试根目录，章节归档只去除尾随空白并脱敏邮箱。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

# 项目维护经验

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - Windows PowerShell 5.1 必须显式读取 UTF-8 规则

- **触发：** 无 BOM 的 UTF-8 扫描脚本增加中文按钮规则后，以 `powershell.exe -File` 启动。
- **现象：** 中文被按 ANSI 解码，测试和真实扫描出现语法错误；不能通过给源码加 BOM 来绕过既有编码约束。
- **根因：** Windows PowerShell 5.1 对无 BOM 文件使用系统代码页。
- **下次做法：** `ReadAllText(path, Encoding.UTF8)` 后创建脚本块，以 UTF-16LE 编码的 `EncodedCommand` 传入引导，安装路径按 PowerShell 单引号字面量转义；标准输出按 UTF-8 解码。
- **检查：** 用实际扩展生成的启动参数运行 SelfTest，并验证中文分段输出。测试入口也要显式 UTF-8，不把 pwsh 单独成功当成 PowerShell 5.1 成功。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - PowerShell 协议输出不能把进度当成错误

- **触发：** PowerShell 引导成功退出，但 stderr 出现 CLIXML 进度记录。
- **根因：** EncodedCommand 在重定向输出时可能序列化初始化进度。
- **下次做法：** 引导设置 `ProgressPreference='SilentlyContinue'` 并传 `-OutputFormat Text`；仍保留真正错误输出。
- **检查：** 实际启动测试要求退出码 0、stdout 含预期协议且 stderr 为空。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - 新权限表单不能按 Run 或 Submit 全局匹配

- **触发：** Antigravity IDE 2.5.5 显示新的工具审批卡片。
- **现象：** `Run Write-Output ANTIGRAVITY_AA_FINAL_V53?` 是工具记录的展开按钮，实际审批使用 `Yes, allow this time` 单选项和 `Submit ↵`。
- **下次做法：** 先读取实际控件树，在 `conversation` 内核对同一卡片的 permission target、一次允许、永久允许和拒绝选项；只选择一次允许，再提交对应卡片。禁止全局匹配 Submit，禁止选择永久允许。
- **检查：** 扫描关闭时审批保持等待；新 VSIX 安装重载后日志明确记录一次审批，终端输出目标标记。普通问答表单不能被提交。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - Computer Use 必须从筛选结果选择窗口

- **触发：** `list_windows` 返回多个应用，输出只展示筛选后的 IDE 窗口。
- **根因：** 显示筛选结果后误用原始数组第一个窗口，会绑定其它应用。
- **下次做法：** 保存筛选结果，要求恰好一个候选，再使用该候选返回的 id/app。发生用户输入、最小化或句柄变化后重新观察，不重用旧控件索引。
- **检查：** 首次状态显示临时测试目录标题和 Antigravity IDE 进程；每次输入后立即刷新核对。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - 单个 PowerShell 管道结果需要显式数组收集

- **触发：** 开发机仅安装系统 PowerShell 5.1，筛选引擎列表后按 `[0]` 选择执行程序。
- **现象：** 单个结果退化为字符串，`[0]` 得到盘符首字符，测试无法启动。
- **下次做法：** 用 `@(...)` 收集完整管道结果；不要使用 OutputEncoding、HOME 等系统变量作为普通任务字符串。
- **检查：** 除默认多引擎测试，还运行仅传 `powershell.exe` 的单引擎回归。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-05 Asia/Shanghai - 完成后的工具记录也不是审批按钮

- **触发：** 真实审批通过后，工具记录标题从 `Run Write-Output ANTIGRAVITY_AA_SMOKE_V53?` 变成 `Run Write-Output ANTIGRAVITY_AA_SMOKE_V53`。
- **现象：** 仅排除问号无法阻止扫描器继续展开历史记录。
- **下次做法：** 执行类按钮限定实际审批静态标签和快捷键后缀，禁止将任意命令正文按 Run 前缀匹配；字面量 `Run command` 仍是旧版静态审批标签，不要误写成已禁用。
- **检查：** 用最终安装包完成固定标记任务后，日志只有对应一次审批提交，没有 Run 工具记录点击。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 最后一次 UIA 查询后仍需检查宿主存活

- **触发：** 初始父进程检查通过，但后续获取按钮或宿主窗口时父进程退出。
- **现象：** 早期存活检查无法阻止最后一次 Invoke；两名审查者用实际函数桩独立复现。
- **下次做法：** 在现有点击路径中，把父进程存活复核放在选中状态、同卡片和 UIA 查询之后，紧邻 Invoke。保留独立的旧版按钮检查。
- **检查：** 模拟查询期间父退出，旧版和新版 Invoke 都必须为 0；不把这种无点击桩验证写成实机退出测试。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - VSCE 会重写说明书相对链接

- **触发：** 对比工作区 README、VSIX 和已安装文件的原始 SHA-256。
- **现象：** 运行脚本全部一致，但 README 源文与安装包不同。
- **根因：** 打包器把 Markdown 相对链接和图片地址改写为仓库 URL。
- **下次做法：** 运行文件要求三方字节一致；README 检查改写差异并要求 VSIX 与安装文件一致，不把合法链接改写当成旧包。
- **检查：** 显示实际链接差异，并分别记录运行文件和说明书的验证结果。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 浏览器审批需要核对窄布局折叠菜单

- **触发：** 插件 ON，但 `Agent needs permission to act on github.com` 卡片一直等待。
- **根因：** 命令审批的 Edit/Radio/Submit 结构不适用于浏览器；IDE 源码在窄布局把 `Allow Once` 放入 `More actions` 菜单，菜单项通过 Portal 出现在卡片之外。
- **下次做法：** 先读真实控件树及宿主 UI 定义，按同一浏览器卡片选择本次允许；不能将 `Always Allow` 加入全局字符串规则，也不能从全窗随意选择 MenuItem。
- **检查：** 回归分别覆盖宽布局与窄菜单，并安装新 VSIX 在原待审批任务验证。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - BOM 检查使用字节或 Ordinal 比较

- **触发：** 用默认文化比较的 `StartsWith([char]0xFEFF)` 检查 UTF-8 文件。
- **现象：** 无 BOM 文件也可能被误判；实际首字节为 `23 20 F0`，不是 `EF BB BF`。
- **下次做法：** 检查前三个原始字节，或显式使用 `StringComparison.Ordinal`；严格解码并单独统计 CRLF 和孤立 LF，避免误判后转码。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - IDE 状态命令按字段筛选输出

- **触发：** 用 IDE CLI 的 `--status` 查询进程存活。
- **现象：** 完整输出可能包含子进程参数中的会话凭据及 CSRF 字段，超出了版本和扫描器验证所需信息。
- **下次做法：** 优先查询 `--list-extensions --show-versions` 和插件日志；若确需状态输出，先在内存中按字段白名单或脱敏，再输出，完整原文不进入公开验证资料。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 新审批作用域必须覆盖旧回退路径

- **触发：** 为浏览器卡片加入精确本次允许分支，但旧全窗口匹配仍接受 `Allow Once`。
- **现象：** 宽栏的普通卡片被新函数拒绝后，旧扫描循环仍可能批准。
- **下次做法：** 让浏览器专用标签仅进入同卡片分支，并用实际扫描尾段覆盖宽栏无上下文、会话外和窄栏菜单；不能只测新增函数。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - AST 回归需要加载真实匹配全局表

- **触发：** 回归从 AST 加载实际匹配函数和扫描尾段，但没有同时读取源码中的目标前缀及排除表。
- **现象：** 空全局表掩盖宽栏 `Allow Once` 的旧回退误批，第一次预期红色的运行实际通过。
- **下次做法：** 从同一份被测源码 AST 加载匹配配置，再执行实际尾段；用隔离旧版副本验证它确实失败，不能将测试文件名称或预期当作证据。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 安装器会追加清单元数据

- **触发：** 对比 VSIX package.json 与 IDE 已安装 package.json 的字节哈希。
- **现象：** 安装器新增 `__metadata`，清单字节哈希不同；原始清单字段及两个运行文件完全相同。
- **下次做法：** 运行代码按字节 SHA-256 核对；安装清单逐项核对原字段及版本，单独列出安装器追加字段，不把合法安装元数据当成运行文件损坏。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 结构日志不能抢占错误诊断的节流

- **触发：** 扫描器记录候选卡片形状正确，但后续模式异常或菜单失败没有日志。
- **根因：** 结构日志先消耗共用的十秒节流，随后动作结果日志每次都被压掉；有结构日志不等于执行到 Invoke。
- **下次做法：** 结构和动作结果分别节流，或合并一次输出固定阶段和结果；不输出域名、消息或可能包含用户内容的异常全文。
- **检查：** 模拟连续轮询中的模式异常，结构日志与固定原因诊断都必须可见。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 离屏保护需要配套当前审批控件滚动

- **触发：** 窄侧栏的 More actions 在横向滚动区之外；同卡片结构正确但 IsOffscreen=True。
- **实机对照：** 仅横向滚动使 IsOffscreen=False，窄菜单仍未完成；仅扩大侧栏后，插件自动调用 Allow Once，原浏览器任务继续。因此不能把一个布局对照当作窄菜单修复完成。
- **下次做法：** 在已核验当前审批卡片内尝试带出控件，重新检查可见性和卡片归属后再操作；继续诊断菜单路径，不能删除离屏保护。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 下拉按钮的 UIA 模式与普通按钮不同

- **触发：** 同卡片 More actions 可见后仍未展开，宽布局 Allow Once 直接调用却成功。
- **已跑诊断：** 窄按钮实际报告 invoke=False、scrollitem=True、expand=True；普通 InvokePattern 不适用于此下拉控件。
- **下次做法：** 读取实际支持模式，按当前控件使用 ScrollItemPattern 和 ExpandCollapsePattern；在每次副作用前后复核卡片、宿主和可见性，不能仅依赖按钮名称或测试桩默认支持所有模式。
- **检查：** 旧实现对不支持 Invoke 的真实形状必须失败；回归要模拟 Expand 和滚动支持，并最终安装到同一个待审批 IDE 任务实测。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 宿主查询后复核当前控件状态

- **触发：** 加入滚动和展开路径时，将最终卡片、菜单和菜单项检查放在 Get-TargetProcessIds 之前。
- **已跑复现：** 宿主查询内改变卡片文案或可见性，旧版四例仍调用本次允许；滚动前改变卡片也仍滚动。实机普通任务成功不能排除这些竞态。
- **下次做法：** 移动现有检查为宿主查询、最终卡片及控件状态、最终菜单关联、父存活、实际动作；不叠重复校验。
- **检查：** 四例均零批准；滚前改变卡片零滚动，滚后改变卡片零展开；正常宽窄路径继续通过。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 新终端审批也会替代聊天输入区

- **触发：** 浏览器已连续自动批准，但 Allow running verification tests? 终端审批一直等待；单选和 Submit 位于 Agent Conversation 之外。
- **已读源码及实机树：** IDE 的专用 ask_permission 组件既可在 conversation 内渲染，也可替代输入框。实际 Radio → radiogroup → Group 两层父链仍是单个表单；同组含 Edit permission target、同前缀本次/持久/拒绝选项、Skip、唯一 Submit。
- **下次做法：** 宿主窗口内发现精确一次选项后核对专用权限表单，不把 conversation 当唯一入口；普通 ask_question 复用 ask-opt ID 但没有 permission target，必须拒绝。
- **滚动边界：** 长命令使持久选项换行，Submit 可在视口外；动作控件需滚到可见并重新验证，最终只读选中项可能因提交按钮滚动离屏。不能删除动作可见性保护，也不能要求两个相距很远的控件始终同时可见。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 原 Agent 的候选也需要贡献政策和重复修复核查

- **触发：** Agent 选择 Rich #4229 并修改本地代码，但还没有核实仓库 AI_POLICY.md 和作者已有修复。
- **已查公开证据：** Rich 要求披露 AI/agent、完整模板及维护者事先批准；该 issue 没有批准，原作者有同方案 commit 等待回复。
- **下次做法：** 在提交前核查贡献政策、关联 PR 和已有修复；保留工作区，向原 Agent 说明并改选合适目标。没有独立 AI_POLICY 文件不代表没有 AI 要求，仍需查贡献指南和 PR 模板。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 请求文字不能证明使用了专用权限表单

- **触发：** 在 Agent 提示词中要求通过 ask_permission 执行无害标记，再观察自动审批。
- **已跑验证：** Agent 实际生成了普通 ask_question，只有 Allow and execute / Deny / Other，没有 Edit permission target；插件保持不回答，符合专用权限表单边界。人工选择 Other 解释正常命令流程后才继续，不能把这次标记执行算作自动批准证据。
- **下次做法：** 让 Agent 正常执行需要审批的命令，用实际 UIA 表单结构和插件动作日志验证自动化；提示词、Agent 自述及命令最终输出都不能独立证明审批来源。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 浏览器上传受阻时保留逐文件选择的人工交接

- **触发：** 浏览器文件上传要求扩展文件网址权限，访问扩展设置页被 URL 策略拒绝；原生浏览器操作也因无法可靠识别网址被停止。
- **下次做法：** 不改用其他接口执行被拒绝的权限设置操作。先打开现有扩展的 Update 入口，向用户交接已验证公开 VSIX 的逐文件选择，接着完成正常上传和页面验证；没有看到选中文件及发布结果时，不声称商店已上架。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 富文本消息输入区需核对实际子文本

- **触发：** 替换 Antigravity Message input 的提示词后，只校验组合框的 Value 字段。
- **已跑观察：** Value 仍是第一次输入的旧内容，但其文本子节点和当前截图已经显示替换后的正确内容；因此第一次发送前校验误判。该观察只覆盖富文本消息组合框，不能外推到专用权限 target 输入框。
- **下次做法：** 输入后刷新状态，用实际文本子节点和必要的截图核对；当前存在专用权限表单时不点击消息区控件，避免审批表单切换时复用旧索引。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - PR 正文写入后必须读回核对

- **触发：** 原 IDE Agent 内联传递带 Markdown 引号和反引号的 gh pr edit 正文。
- **已跑验证：** Arrow PR #1367 的正文实际只剩 273 字符，验证信息与 AI 披露被截断；改用 UTF-8 body-file 后，读回文本与文件逐字一致。
- **下次做法：** 多行正文始终保存为文件或使用结构化参数；写入后验证完整文本和关键披露，不用命令退出成功代替正文完整性证明。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 自动审批与代码质量必须分别验证

- **触发：** 原 IDE Agent 修复 Arrow 多粒度日期计算并声明完成，但没有充分覆盖舍入、时区和日历边界。
- **已跑验证：** 独立审查先后复现负亚秒环绕、DST 固定单位双计、月末锚点丢失、零个月运算清除 fold，以及跨时区月边界方向错误。终端自动批准只证明审批自动化，不能证明开源贡献正确。
- **CI 边界：** 原项目 99% 总覆盖率通过后，Codecov 仍可能要求 patch 100%；不可达兜底应按固定单位集合删除，不为其制造无效测试或降低阈值。依赖下载 IncompleteRead 发生在运行测试之前，应与源码测试失败分开诊断。
- **下次做法：** 对最终提交独立审查原行为、真实回归及全部项目门槛，并核对精确 SHA 的 CI；Agent 自述或降低覆盖率门槛的测试输出都不能作为完整交付证据。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - 有效日期转换仍可能超过 datetime 范围

- **已跑验证：** Arrow 的两个有效 year 9999 端点相差 26 小时，新增的无条件 astimezone 转换却需要构造 year 10000，因此连纯天/小时粒度也出现新 OverflowError。
- **下次做法：** 固定粒度跳过日历转换；日历转换溢出时保留原 aware 端点，消费可表示的原月份锚点，再分解精确秒余量。说明不可表示下一月的边界，不把该分解宣称为全日期范围的最大日历单位。补齐双方向固定/日历回归后再封板。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-06 Asia/Shanghai - PR 作者不一定有权限重跑上游 CI

- **已跑验证：** Arrow 最终提交的 27 项检查为 26 成功、1 依赖下载失败；完整 run 结束后执行 gh run rerun --failed，明确被拒绝：Must have admin rights to Repository。贡献者能推自己的 fork，不代表能重跑上游工作流。
- **下次做法：** 保留同一提交的成功测试及实际失败日志，在 PR 正文说明需要维护者重跑环境失败项；不要降低门槛、反复无权限重试或制造空提交。发布 CLI 没有现成发布者/token 时，应交接已验证 VSIX 的逐文件选择，不自动创建凭证。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 多窗口扫描必须隔离失效节点并轮换成功窗口

- **触发：** 首个 IDE 窗口持续出现审批，或者在枚举后关闭窗口。
- **已跑复现：** 固定顺序三轮扫描首窗获批三次、次窗零次；首窗 UIA 异常让次窗整个轮次得不到扫描。
- **下次做法：** 在窗口和控件边界隔离临时异常，每次成功后让后续窗口优先；用实际扫描尾段与固定计数断言复现，避免只测字符串匹配。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - IDE 产品版本和 CLI 名称分别核对

- **触发：** 假定安装目录中的 CLI 名称是 antigravity.cmd。
- **现象：** 当前 Antigravity IDE 安装实际使用 antigravity-ide.cmd；CLI --version 输出基础编辑器 1.107.0。
- **下次做法：** 先枚举 bin，IDE 兼容版本读取 product.json 的 ideVersion，记录两者，不把基础编辑器版本写成 IDE 产品版本。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 显式 UTF-8 加载还要保留脚本文件上下文

- **触发：** CI 为 PS5 通过 ScriptBlock.Create(ReadAllText()) 执行测试文件。
- **已跑复现：** 原始引导丢失 PSScriptRoot，测试定位相邻源文件时 Join-Path 失败。
- **下次做法：** Parser.ParseInput 传 UTF-8 正文及绝对文件名，再执行 AST.GetScriptBlock；精确 CI 命令须在 PS5/PS7 分别验证。插值变量后紧跟冒号时使用 ${变量}，避免 PowerShell 将它当作用域语法。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 动作已发生后抛错也必须消耗扫描冷却

- **已跑复现：** 第一按钮 Invoke 先产生副作用再抛错，后续按钮在同轮约 35ms 内又获调用，虽配置冷却为 1000ms。
- **下次做法：** 只读查询失败可跳过；开始动作后，不论结果是否已知，本轮必须进入冷却且不能物理重试。成功日志与动作尝试分别记录，不以未抛错作为唯一限速入口。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 进程 exit 与输出 close 分别验证

- **触发：** 子进程 exit 后 stdout/stderr 仍有尾部数据。
- **下次做法：** 保留带退出实例标识的诊断，不能解析旧 READY/WAITING 更新新状态；close 后拒绝旧输出。停止或卸载后不再追加诊断，卸载验证无 child/timer，不要求已释放状态栏刷新。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 富文本输入不能只信 set_value 成功

- **已跑观察：** Antigravity 消息组合框 set_value 返回后仍空、Send disabled；点击并 type_text 后实际子文本和 Send 状态才更新。
- **下次做法：** 重新观察实际文本子节点；UIA 点击缺少几何信息时先激活目标并重新观察，不复用旧索引。Value 与实际子文本不一致时，以截图及当前子文本核对，不能盲发重复消息。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - UI 点击还要有当前截图几何

- **已跑观察：** 当前 Computer Use 环境仅刷新文本后，索引点击反复报告 geometry unavailable；激活目标并刷新 include_screenshot=true 后，同一可见命令点击成功。同进程多窗口还可能让缓存索引过期。
- **下次做法：** 按目标窗口重新观察，必要时同时获取截图；操作失败后不重复旧索引。浏览器 URL 无法核实时结束该次电脑操作，不换接口执行被拒动作；独立授权的构建、测试及 GitHub CLI 工作继续使用专用工具。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - YAML 解析不等于 Actions 表达式校验

- **已跑复现：** 本地 YAML 和 PowerShell AST 都通过，但 GitHub run 37515131660 在启动 job 之前失败；六个 step.shell 中的 matrix.shell 被远端判为 Unrecognized named-value，未生成任何测试结果。
- **下次做法：** 按 GitHub Contexts reference 的具体键位置检查可用上下文；job.defaults.run 支持 matrix，不能把 workflow 根 defaults.run 或步骤 shell 当作同一规则。工作流变更使用 Actions 表达式校验器，并以新提交在远端实际创建和完成所有 job 作为最终证据。
- **检查：** 没有 runner/job 的配置失败与测试失败分开记录；本地解析成功或旧提交 CI 成功都不能替代这次精确 SHA 的远端结果。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - Actions 运行时与项目 Node 分开维护

- **已跑观察：** checkout/setup-node/upload-artifact v4 的远端 job 成功，但提示 Node 20 Action 运行时已弃用并强制 Node 24；项目实际测试的 Node 仍为 22。
- **下次做法：** 升级前通过官方 release 和 action.yml 核对稳定版本、runs.using 及输入兼容，独立审查并以新 SHA 重跑整个流程；不能只改 node-version 来消除 Action 自身运行时警告。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 用户输入干扰要执行生产点击方法

- **触发：** 插件审批时用户可能正在浏览、拖动、选择文字或切换窗口。
- **现象：** 仅窗口归属布尔测试和整 Click 计数桩全部通过，生产方法回放却会覆盖用户新指针、松开已按住鼠标键；强杀测试子进程时 finally 未发配对 Up。
- **根因：** 系统输入边界和真实 Click 时序被整体替换，测试没有覆盖移动、按键和进程退出发生的时间点。
- **下次做法：** 保留生产方法，仅将 native API 和等待边界换成确定性内存实现；分别验证按钮身份漂移、30ms 观察期间移动、按键已按住、输入返回数量和恢复时输入变化。Down/Up 同批提交，不依赖可被强杀跳过的托管 finally。
- **检查：** 记录旧方法的失败和新方法通过；CI 不操作桌面，实机 UIA 焦点和后台审批另行验收。PS7 内查系统 PowerShell 使用 Get-Command powershell.exe，不拼接当前 PSHOME。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 浏览器审批最终复核必须包含身份

- **触发：** UIA 卡片、宽栏按钮或 Portal 菜单在查询、滚动或展开期间改变。
- **现象：** card shape 仍合法，但域名更换、按钮转移父节点、旧菜单项替换后仍会调用旧 Allow Once。
- **根因：** 只检查语义形状，或复用最初父节点和菜单项引用，不能证明仍是原审批目标。
- **下次做法：** 保存原目标与运行身份；动作前重新核对父链、当前目标和当前菜单项归属。已展开菜单只在精确唯一关联及锚点成立时使用，未知预存菜单保持拒绝。
- **检查：** 在宿主、模式和最终 Card.FindAll 查询边界注入变化，旧按钮与旧菜单项调用数必须为零。最终菜单项身份检查之后再读卡片树，仍可造成旧项归属失效；先完成卡片关联查询，再枚举菜单项和父链，不能只测试宿主查询。没有显式 SetFocus 不等于 provider 不抢焦点，需真实输入观察。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 原生输入结构和验证委托必须分别执行

- **触发：** 新物理输入通过 C# SendInput 和 PowerShell Func<bool> 控件复核组合执行。
- **根因：** 只测试 C# 的真假委托会漏掉真实 PS 作用域及 FromPoint 父链；只测试 x64 会漏掉 x86 INPUT 指针对齐。PS5 的 Marshal.SizeOf(RuntimeType) 还可能选择 object 重载。
- **下次做法：** 从生产 AST 提取委托赋值体，仅替系统命中查询，实际让生产 Click 调用；分别覆盖 button、text 子节点、几何、原身份、宿主和异常。Marshal.SizeOf 在 PS 测试中使用 boxed struct 实例，C# 继续 typeof；至少实际查询 x64 40字节/偏移8与 x86 28字节/偏移4。
- **检查：** 慢 UIA 委托后重新查询 native 前台和遮挡，再最后查输入戳及指针。保留 native 部分插入、同时输入和查询间隙的限制，不把内存模型称为真实桌面点击证明。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 同批输入需要精确像素映射和最后状态复核

- **触发：** 为避免鼠标停留及强杀后的 Down/Up 分离，将移动、按下、松开、恢复放入同次 SendInput。
- **已跑复现：** 旧中间实现若自身移动更新输入时间戳，会返回 false 并停留在目标；归一化中心公式在宽度65535、offset1时回落到像素0。裁剪查询期间切走前台或遮挡，在较早校验后仍可能发出批次。
- **下次做法：** 按65536个输入坐标与每个物理像素的整数区间选点，纵横轴都断言；临时设置线程DPI上下文并在finally恢复，检查虚拟屏幕、裁剪边界及实际显示器命中，再最后核对前台、原按钮、输入戳和原指针。
- **检查：** PS5x64、PS7x64和PS5x86执行真实生产方法；输入返回0/1不重试，2仅尽力补Up，3只代表批准对已插入。模型通过不替代真实系统接收或混合DPI多屏证明，SendInput顺序插入不构成窗口/显示器原子事务。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 低提交内存与安装器元数据分别定位

- **触发：** 全量扫描回归启动互斥测试进程时OutOfMemoryException；安装VSIX后package.json逐字节比较失败。
- **已跑验证：** 系统可用提交内存约1.1GB/总34GB，旧扫描器运行9小时私有内存约1.09GB；正常Stop后可用提交内存增加，完整npm test重跑退出0。不能只凭单个快照给源码下泄漏结论。
- **下次做法：** 先保存失败日志及具体PID、启动时间、编码命令归属，用插件正常Stop释放自己的扫描器再重跑，不清理其它用户进程；长期资源需趋势证据。
- **安装检查：** IDE安装器添加__metadata；运行代码仍逐字节核对，manifest排除这一安装器专有字段后逐项语义比较。不能把元数据差异说成运行代码不同，也不能忽略其它manifest差异。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 资源基准的截止与输出必须一起保护

- **触发：** Process路径查询原函数与仅内存Dispose的单子进程基准，85秒硬限结束后没有完整对照数字。
- **根因：** 每250轮才查软截止过粗；外层等退出后才读stdout/stderr，硬截止时没有及时回收部分结果。
- **下次做法：** 从子进程启动就异步收集输出，每轮或少量轮检查截止，先用3轮热身和10轮样本测单次成本，再按墙钟调整循环数；超时先终止自己持有的子进程，再回收已产生的输出，不把测量失败当成实现缺陷。
- **单位：** 内存原始字节必须保留，展示明确MB或MiB；121331712 bytes为121.33MB或115.71MiB，不能与119.75MiB直接按数值大小比较。没有完整对照和长期趋势时，只报告观察，不据缺少Dispose认定泄漏。
- **计数：** for结束后的循环变量不是执行次数；本次热身输出标号曾显示4，真实轮次只有1/2/3，报告必须按实际记录计3次。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 进程查询先分开枚举和路径计时

- **已跑验证：** PS5x64把Path换为native后整轮仍约200ms；拆分三轮发现Get-Process枚举183–222ms，而读取14条既有Path及native路径均约5–13ms，不能把热点误归MainModule。
- **真实缺陷：** PS5x86旧Path对14个x64 IDE宿主全部为空，MainModule报299；原生查询能识别14个完整路径。
- **下次做法：** 先按当前窗口PID查询完整映像，不跨轮缓存PID或路径；动作前重新核对路径并保留后续控件和窗口身份检查。同句柄查询前后零时等待仅接受258，不能用退出码259证明存活。
- **检查：** 同用户实际宿主、x86到x64、已退出但仍保留句柄、中文长缓冲、失败和抛错的关闭次数分别验证。小样本的速度或GC结果不能证明整个扫描器泄漏已解决。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 嵌套PowerShell与诊断输出也要单独验证

- **现象：** 外层PowerShell调用另一个引擎的双引号Command时，内层变量先被展开成空值，得到ParserError而未执行测试；改为单引号正文生成EncodedCommand后，才复现有效宿主漏识别的预期红灯。
- **下次做法：** 子进程脚本正文使用不插值的文字块，编码后传入；明确区分解析错误与真实断言失败，保留输出。
- **基准输出：** PS5的ConvertTo-Json不能序列化UInt32键Dictionary；native查询已经成功也可能因诊断序列化退出1。先将键值转为记录数组，并保留失败日志，不把仪表错误归于生产方法。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 扫描入口改变后生命周期测试也要隔离窗口枚举

- **已跑失败：** 完整npm回归的并发子进程未在10秒内随父进程退出；旧common仅把宿主进程图替为空，没有automation对象，新入口枚举窗口后反复InvokeMethodOnNull。异步收集同一真实生命周期的输出时，父退出后76ms正常结束；原现场管道阻塞没有线程栈，只能据源码与差分支持推断。
- **下次做法：** 生命周期fixture直接提供空FindAll集合，不依赖生产入口中某个早退；假窗口不读取桌面。只加载UIAutomationClient不会保证TreeScope已加载，显式加载UIAutomationTypes；保留原错误日志。
- **输出：** 等待退出前先异步收集stdout/stderr；已经消费READY或当前Pending之后才能读同一流的尾部，避免重复读取。不能以延长退出超时掩盖错误洪泛。
- **检查：** 空窗口两引擎并发22项通过后，再重跑唯一完整npm test；输出出现ERROR仍判失败，不能仅看进程退出0。

- **同类审查：** 单实例退出断言曾仅看exit0，受控子进程输出ERROR与stderr后仍被判通过。owner与waiter均在协议读取完成后异步收尾并拒绝错误或CLICK协议；abandoned owner也核对诊断。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 多窗口内存失败需区分宿主与插件

- **触发：** 打开第二个公开插件 IDE 窗口后，截图和 PowerShell 全进程枚举均报内存不足。
- **已跑验证：** 新窗口语言服务器 13:24:57 报 runtime: cannot allocate memory，宿主随后记录无响应与 renderer crashed；13:30 事后提交量 34052124672 / 35307311104 bytes（96%）。原 5.3.5 scanner 仍唯一，最后 Private 为 119431168 bytes。
- **边界：** 事后资源读数不是出错瞬间读数；这些证据支持资源不足，但不能定位到插件泄漏，也不能把打开后立即崩溃算作稳定的双 IDE 验收。
- **下次做法：** 扩展窗口矩阵前先读系统提交余量；遇到不足先保留失败，只关闭本轮空白测试窗口，不清理用户其它进程。GUI 无响应退出是异步操作，要刷新窗口列表确认结果；同进程模态索引失效后用重新观察的截图核对。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - CLR 类别存在不保证可映射进程

- **已跑验证：** .NET CLR Memory 的 Exists 返回 true，但 ID Process 计数器构造报 Could not locate Performance Counter，无法可靠映射固定 scanner PID。
- **下次做法：** 区分类别存在、PID 映射和具体计数器可读三层；读取失败保留 unavailable 与原异常，不安装、不提权、不触发 GC。固定 PID 的 Private/WS/CPU 仍可记录，不能代替 CLR heap 或存活根证据。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 发布交付必须逐个确认 Release 和商店

- **用户纠正：** PR 合并与 CI 通过没有完成发布。检查时 GitHub Release、Marketplace、Open VSX 都仍为 5.3.2；不能把本机安装成功说成商店更新。
- **已跑验证：** 从已验证 5.3.5 VSIX 创建 GitHub Release，标签指向通过 main CI 的 0b3f21b；下载公开 Release 资产后 SHA256 与安装输入一致。双商店已登录并打开表单，但浏览器文件选择器均要求文件 URL 权限；vsce ls-publishers、仓库 secret list 和已知发布环境变量为空。
- **下次做法：** 合并后先核对实际 Release/商店版本；只发布已验包。缺凭据不能伪造完成或自动创建 PAT。上传前读 file-uploads 文档；受限后准备好表单和确切包路径，再让用户做必需的一次操作。
- **工具边界：** 用户请求打开 chrome://extensions 后，Browser Use 仍拒绝非 HTTP/HTTPS 地址，并明确禁止其它控制路径绕过。仅提供手动打开步骤，不通过菜单、原生窗口、CDP 或其它浏览器面重试同一结果。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - CLR 计数器命名与测量日期精度更正

- **更正：** 上项 ID Process 构造失败来自诊断脚本命名错误，不是类别存在却缺少该计数器。本机 GetCounters 元数据和微软定义均为 Process ID；24 个名称中存在 Process ID、不存在 ID Process。
- **已跑验证：** 固定 scanner PID 1005396 在 16:10:18 和 16:11:26 均已退出；本轮不能提供其 CLR heap/Gen 读数。系统有效配对间隔 20.46269 秒，与 scanner heap 证据分别报告。
- **下次做法：** 首先只取计数器元数据确认真实名称；以明确 PID 和启动时间映射实例，不猜测替代 PID。日期间隔从原始 ISO 字符串或 DateTimeOffset 计算；默认 JSON 日期往返再转字符串可能丢失小数秒，必须保留真实超时配对，不能强报小于 60 秒。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 用户修改扩展权限后重连与商店公开验证

- **已跑验证：** 用户开启文件 URL 权限后，Chrome 连接3失效，fresh getState显示同profile/原tabID的新连接6；按新清单重新连接原发布表单，文件选择成功，5.3.5双商店上线。
- **下次做法：** 连接失效先确认实际浏览器身份，不关闭或重建用户页面；不得把旧ID unavailable当作用户未授权。页面内部Settings显示latest5.3.5/Public仍可能在审，初期公开API为404；以PUBLISHED队列、公开版本控件/历史和可下载包验证完成，不能仅看通用It's live提示。
- **边界：** 新agent与idle代理followup均曾被thread limit拒绝，避免重复创建；复用已有运行的代理与root交叉审查，不伪称新独立reviewer已运行。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 大型发布脚本不能塞进 Windows 命令行

- **已跑验证：** 发布离线测试首次有13个用例被spawnSync ENAMETOOLONG阻止，生产发布代码尚未执行；不能把这次红灯描述为发布逻辑缺陷。
- **根因：** 把完整工作流内联脚本与fixture通过EncodedCommand传给Windows子进程，编码后超过命令行限制。
- **下次做法：** 小型UTF8启动引导继续使用EncodedCommand；大型PS7测试正文写入本轮独立临时目录的UTF8 ps1，以pwsh -File执行，保留实际退出码和断言日志。
- **检查：** 修正后26项发布回归全部通过；临时清理先核对绝对目录在系统Temp内且前缀属于本轮，再使用同一文件API删除。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 单元回归与scanner ready不能替代当前包实机焦点验证

- **用户纠正：** 5.3.6需要Computer Use本机测，不能沿用5.3.5实机结果或只报PR/CI。
- **已跑验证：** 安装字节一致、日志确认5.3.6后，真实终端/浏览器批准可执行，Note文字保留；200ms原生只读样本却在两个批准附近记录Note→IDE前台切换。OFF对照中单张终端原生卡持续等待，Note在后续采样中保持前台。
- **下次做法：** 合并前要求当前安装包的实机证据，批准返回、工具结果、文字保留、前台/鼠标和多窗口分别核验。秒级日志不足以给Select/Invoke/Expand/宿主调用定责；先补阶段毫秒观测，不盲加焦点恢复，不放宽身份/输入校验。
- **边界：** 200ms快照不能排除间隙内短暂切换；当前Chromium upstream默认点击可改变页面焦点，不能直接推出本机Windows前台变化。低提交余量时不重复开第二完整IDE造成用户环境崩溃。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 原生观测几何与异步插件状态需刷新确认

- **已跑验证：** 最小化的自有Note不能抓状态；AX-only后两次click报coordinate input geometry is unavailable，动作未确认。恢复自有窗口并用fresh screenshot后输入成功，不把工具几何错误当插件故障。
- **下次做法：** 实机输入使用当前截图与返回的窗口句柄；控件索引失效先观察，必要时一次截图坐标回退。插件启动异步，click回调仍显示旧OFF时先看fresh ready/日志，不能立刻判定点击无效或重复切换。
- **日志定位：** 最新Antigravity logs目录可能仅有CLI安装日志；按近期真实window/exthost输出的5.3.6激活与ready定位，不把rg无命中说成scanner不存在。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 阶段诊断本身、日期解析与恢复身份必须验证

- **已跑失败：** 诊断Console.WriteLine中的多参数-f表达式未整体括起，异常被日志自身catch吞掉；纯内存包装断言发现缺日志，修正后再安装。不能把静态解析通过当实际诊断输出通过。
- **日期：** ConvertFrom-Json后的时间字段可能已变为DateTime，再与ISO字符串比较会得到空筛选或丢失精度；先按原始JSONL的ISO文本或数值elapsedMs定位，再报告样本读取区间，不能把时间戳当原子前台读数。
- **恢复：** 同版本CLI安装只替换磁盘文件，旧scanner仍运行。先核对原包hash，再用本轮已记录PID、精确启动时间、父PID和解码启动路径证明所属实例，才停止该诊断进程，随后按原重启日志确认原包ready。Windows安装路径驱动器大小写不同，身份比较使用OrdinalIgnoreCase，不缩减为文件名匹配。
- **工具边界：** Computer Use因无法可靠确认浏览器URL停止后，本轮停止所有界面输入，不换CUA/CDP/原生路线重试。已运行的只读观测记录可以保存，但不能冒充被中止的完整交互验收；非UI官方CLI可恢复本轮诊断安装。
- **边界：** Note→IDE切换被缩小到Invoke调用后半段或返回后的极短区间，Chrome也出现对应前台切换；这仍不能区分provider与异步宿主激活，不能盲加焦点恢复或放宽最终批准校验。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 同SHA首次超时与重跑成功分别保留

- **已跑验证：** 17135bc的PR/push首轮PS7分别在owned-child READY10s、SelfTest20s超时；原失败日志保留，同SHA各重跑失败作业一次后成功，未改断言和超时。
- **下次做法：** 在不修改生产代码的证据提交上，先区分runner协议启动超时与功能断言失败，精确核对SHA/attempt；GET失败且未提交重跑请求时先查原run状态，再补发一次请求。不能把重跑成功说成根因已确定或CI无不稳定。
- **检查：** 独立8秒mutex协议重放通过也不能替代诊断包完整PS7最后一项超时记录；测试范围与证据等级分别写明。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 客户端标志通过不等于后台焦点修复

- **已跑验证：** 同一原生UIA客户端AutoSetFocus=false，真实窗口/RuntimeId绑定和Invoke正常返回，Submit仍令Note转到IDE。600个独立样本确认切换，45字符文本保留和工具exit0不能抵消这一体验失败；不合并未奏效候选。
- **原生契约：** GetTypedObjectForIUnknown的Type要求COM imported class，不是COM接口；预检只创建client不会覆盖pattern转换。改为GetObjectForIUnknown再QI到接口，并分别释放自己的RCW与原始pointer；清理不能遮盖动作原异常，也不使用FinalReleaseComObject清空共享引用。
- **生成ABI：** SDK SAL宏可含内部下划线，不能用过窄正则删注解后把BOOL*/接口输出误当IntPtr；完整SDK vtable顺序、GUID、out/SAFEARRAY独立校验。多个C#文件用Add-Type -Path数组；避免将第二文件顶层using拼到前一namespace之后。不要复用PowerShell内建PROFILE变量。
- **测试：** 无效参数测试必须核对异常类型与内容，catch任意异常可把真实桌面失败误算成早期拒绝。没有插值的双引号here-string可能被解析为StringConstantExpressionAst；校验应接受两种字符串AST并拒绝真实NestedExpressions。
- **界面：** launch_app超时先刷新窗口，不重复启动；AX-only click几何缺失时补fresh截图。离屏按钮的AX索引不能替代可见区域核验，先滚动到实际可见工具记录，再展开；不要将未展开的Agent总结当原始工具输出。
- **证据边界：** Chromium固定版本默认动作中的页面focus不是本机Windows前台定责；实际IDE内核尚未映射。认证必须用户手动恢复，第三方Panel的TFA告警也不能独自推出主Agent仍无法工作。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 标准pattern与真实触发范围必须分别核验

- **已跑验证：** GetCurrentPattern标准IUnknown路径在绑定后读回AutoSetFocus=false，真实一次Submit仍使Note转IDE；不能通过更换获取API宣称修复。Help > About确认Chromium 142.0.7444.175后，才能将固定upstream源码映射本机；页面焦点仍不是Windows前台的定责。
- **触发：** 自然任务可选择list_dir等无需审批工具；没有卡片/Invoke的观察记为未触发。实际只读系统测量产生一次审批后，再看原始工具输出、前台记录和文本保留，三类证据不能互相替代。
- **输入：** set_value返回成功但本轮草稿未变；必须检查实际可见内容。聚焦自有草稿后Ctrl+A，核对selected_text严格等于自有文本，再替换，不能把RootWebArea焦点直接当用户代码可编辑区。
- **生成：** Temp生成器原为LF，候选源为CRLF，应逐文件检测；PowerShell正则替换中的字面反斜杠r/n不会生成换行。使用明确CR/LF字符值并以唯一完整代码块、hash及AST为守卫；边界不匹配时不得写文件。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 真实provider、触发顺序与Legacy单例证据

- **已跑验证：** 实际Submit Framework=Chrome、LegacyAvailable=True；只支持取得另一已文档化接口，不独自定责代理/宿主。AutoSetFocus=false的标准Invoke失败后，仅替换客户端为Legacy默认动作、保留完整最终检查，真实一个后台Submit返回后仍Note，独立511个后续样本保持Note及鼠标/input tick。不能从一个静置案例宣称持续输入、多窗口、全部按钮已修复。
- **触发：** 前两次批准早于Note激活，仅记接口执行通过、后台未触发。缩短发送后切换延迟可用两次连续Computer Use调用，各自只输入一次并刷新，不能省略观测或重复已发送任务。get_window_state必须至少请求text或screenshot；两者false的拒绝是工具参数错误，不是插件bug。
- **接口：** SDK完整24成员顺序/已调用ABI和两引擎编译先核验；MSAA入口少disabled拒绝，不能去掉原最后enabled、身份/选择/几何校验，也不能凭Blink disabled表单保护推断全部ARIA控件安全。保留自己的COM清理风险，正式实现前处理。
- **恢复：** CLI先成功后V8崩溃exit134，不能按成功文字说exit0或盲重装；先独立验磁盘hash、主IDE身份，再正常重启scanner，核对新PID/start/parent/decoded path/ready且旧候选退出。此轮未确定CLI崩溃根因。
- **工具输出：** 实际命令只回报内存数值，未显示exit code且未测时间，不补写；Agent显示Explored files时，不把自然语言只读边界当全部行为已验证。200ms样本不覆盖间隙的短暂激活。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 浏览器本机测试中止与自有服务清理

- **已跑验证：** Browser Use能读取自有环回输入页，但Windows Computer Use看到Chrome最小化，恢复请求被URL可信识别规则停止。本轮未发送测试Agent任务、未重启Legacy候选、未开始输入，不把页面创建算焦点或输入验收，也不换UI路径继续。
- **清理：** 非UI官方CLI恢复原包exit0，磁盘hash与原版一致；原scanner PID63404/start/parent保持，候选只曾写磁盘而未替换运行态。自有node服务的PID、start与唯一绝对script命令行匹配后关闭，保留Temp文件。
- **新坑：** exec_command默认非TTY的长期服务会关闭stdin，write_stdin发送quit失败；后续若要以stdin关闭自己的测试服务，启动时明确tty=true，或准备只针对本轮已验证进程身份的正常关闭接口。不得因stdin关闭重启同一已运行服务或结束其它node进程。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 原生契约扩展后的测试类边界与清理异常

- **已跑验证：** 五个 Invoke 获取入口的六个离线分支在原源码均红灯，接入 Legacy 准备边界后转绿；不得把桩里的前台状态当真实 Windows 焦点验收。完整首轮 scanner=152 通过，但 host-process 影子 C# 编译失败，整套结果仍为失败。
- **边界：** 同一个内嵌 C# 文本新增命名空间后，LastIndexOf('}') 已不属于 MouseHelper。影子字段仅插入完整顶层 MouseHelper 类范围；生产完整 C# 仍先编译，全部 P/Invoke 必须替换，不能删断言或漏出实际桌面调用。两个夹具边界独立括号配对和21项原生声明审查吻合。
- **清理：** 真实 RCW 重复释放没有复现异常，不冒充实机复现。受控 Marshal 释放异常会遮盖原异常，分别覆盖 InvalidComObjectException、COMException、ArgumentException，保留原审批异常并继续释放后续引用；不使用 FinalReleaseComObject。
- **生成：** 两个候选循环都有同名阶段标签，唯一匹配守卫在写入前中止；先核实函数范围再替换。PowerShell 同分隔符 here-string 不能嵌套生成脚本，改用 Temp 文件补丁，避免生成器提前结束。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 正式 Legacy 窄菜单失败与观测覆盖

- **已跑验证：** 正式提交双CI首次绿灯并安装运行后，真实两个浏览器域名Allow Once执行；第二项原生采样记录Note→IDE，窄按钮invoke=False/expand=True。仅替换Invoke入口不能证明展开链无焦点变化，下一步先分开观测展开与最终允许，不发布该候选。
- **覆盖：** 自然任务比120秒观测更晚触发审批，首项没有动作时采样，只记未覆盖；180秒请求被既有ValidateRange拒绝，不修改界限掩盖。后续基于真实任务进度启动第二段，保留第一段N/T结果。
- **快照：** IDE输入/进度AX可滞后于截图，甚至完成仍报告Working；用fresh截图、真实输出文件和日志交叉核验，不重复发送。几何失败先看确切草稿，只有未发送才能一次最新截图重试。
- **日期：** 复用既有JSON日期经验，直接解析原始ISO文本得到319样本；六段输入只有第一段在首观察区间，不把全部输入写成连续审批期间验证。
- **预检：** 完整类声明含sealed，过窄文本断言会误报缺契约；在已有作用域调用&导入函数会在子作用域结束后消失，独立内存夹具使用dot-source并先确认唯一完整函数边界。编译和十条实际格式断言通过后才安装诊断包。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - 窄菜单展开定界与准备顺序

- **已跑本机验证：** 完整原动作诊断在 Expand 前为 Note、返回后为 IDE，最终 Legacy Allow Once 在前台已变后才开始，无滚动。该阶段窗口定位不等于确定 OS/provider 的具体激活调用。
- **已跑内存验证：** 默认动作可能切换菜单，先识别精确关联的已开菜单；只有确需触发时准备 Legacy。已开菜单的触发器不支持 Legacy 不应挡住本次菜单项。折叠状态 getter 与模式准备均在最终 PID/HWND、卡片身份/文案、enabled/offscreen 和父宿主检查前；getter 改名或改 HWND 的两项实际函数重放原候选触发一次、修正后拒绝。
- **夹具：** 经典托管 UIA 没有 LegacyIAccessiblePattern 类，纯内存边界使用已对照契约的模式 ID10018，不能把夹具类型缺失当产品红灯。
- **打包：** 根项目没有本地 vsce.cmd，使用 package.json 固定的 npx @vscode/vsce@4.0.0；调用不存在的命令时 LASTEXITCODE 不能证明成功。先确认命令路径，启用 Stop 并保留实际进程退出码。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-07 Asia/Shanghai - Legacy 窄触发器不打开真实菜单

- **已跑验证：** 第十项重放证明准备期间打开菜单会被默认动作关闭；准备后复读状态且保持最终身份检查在后，双引擎10绿、复审无新增发现。
- **已跑本机验证：** A5CF候选普通Submit后483个样本全Note；真正窄按钮Legacy默认动作虽返回且保持Note，却 visible/new/once-items 全0、没有批准，488个后续样本仍Note。界面卡住也是失败，不能只看不抢焦点或桩里的模拟菜单打开。候选经正常Stop停止、PID94204退出，保留同一待批准卡片继续差分。
- **下一步依据：** SDK完整展开接口四项、GUID及10005对照后，测试同一AutoSetFocus=false客户端原生Expand；契约参数预检不触碰真实桌面，焦点与审批仍须实机同时证明。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 原生客户端 Expand 仍会切前台

- **已跑验证：** AutoSetFocus=false 原生展开契约双引擎预检和窄菜单10项内存回归绿，真实 Expand 返回后却 Note→IDE，Allow Once 完成不抵消体验失败；正常Stop后核对具体PID退出。
- **下次做法：** 区分客户端标志、离线接口契约、真实菜单打开、最终审批和前台保持；不同层证据不互相替代。GetIAccessible 可返回 NULL，直接 provider 的可用性与对象身份需实机证明，不把源码没有显式 SetFocus 当 Windows 前台定责。
- **工具：** get_window_state 已自动展示截图，不再 emitImage 同一 payload 作重复观察；异步 Stop 返回旧ON时用日志和固定PID核验，不能立即重复切换。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - GetIAccessible 空指针与未执行动作的证据边界

- **触发：** UIA Legacy 属性可读，但直接服务端指针取不到；原生准备失败只有 MethodInvocationException 外壳。
- **已跑验证：** 根异常为 Native MSAA server missing，GetIAccessible 返回空；后台 Note 保持来自没有 Expand 或最终批准。两个候选具体 PID 正常 Stop 后退出，不能把观察器稳定说成审批成功。
- **下次做法：** 记录根异常类型/HResult和阶段，不丢原错误；只抑制连续重复而非声称全局按内容去重。先核对真正支持的原生服务及完整 RuntimeId 映射，失败拒绝操作。
- **检查：** 准备、展开、批准、工具结果、前台与输入分别给证据；观察器资源类型按实际 observed-process-resource 计数并与 end 对照。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 双引擎内存分配夹具不要压制过时 API 告警

- **触发：** 用完整生产 COM 准备方法做纯内存身份/清理测试，需绕开真实客户端构造。
- **现象：** Framework FormatterServices.GetUninitializedObject 在 PowerShell7 Add-Type 报 SYSLIB0050，PowerShell5.1 可编译。
- **下次做法：** 测试夹具用反射选择 RuntimeHelpers.GetUninitializedObject，旧 Framework 才选 FormatterServices；不压告警、不改生产构造、不调用桌面。修正后十项真实方法分支双引擎均通过。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 原生外层窗口与 Chromium 子窗口不能混为同一目标

- **已跑本机验证：** outer HWND133218 的 MSAA 对象 childCount=0，映射编号为42,133218,4,-18；真实按钮为42,198588,4,4,1,72691。沿绑定按钮 RawView 取得最近原生祖先后，映射进入198588，但命中仍返回窗口根42,198588,4,-115150，childCount=2。两轮均无展开或批准，正常Stop后具体106228/119436退出。
- **下次做法：** 从已绑定目标确认原生归属，再比较完整 RuntimeId；不从 RuntimeId 某一整数猜 HWND，不靠名字或坐标近似放行。背景稳定仅证明拒绝路径；UIA/Chromium公开 UniqueId 到原生 child 的映射须另行验证。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - HRESULT 诊断和观察窗口必须覆盖实际分支

- **已跑内存红绿：** ThrowExceptionForHR(E_NOTIMPL/E_INVALIDARG) 可变成 NotImplementedException/ArgumentException，只有COM catch会盖住原身份拒绝。仅诊断try捕获Exception，再统一抛原绑定错误；双引擎两例保留原错、零Expand、引用释放完整。
- **观测：** 90秒观察提前结束于scanner Start前，排除该记录；重新观察60011ms/300样本后才记录对应111368拒绝路径。新119436观察90013ms/450样本，348个交接后样本全Note；不要把结束前后覆盖或静置样本说成持续输入验收。
- **工具：** Node REPL 新变量先var/let声明，隐式赋值可能在动作前或动作后抛错；先刷新真实状态，不能盲重试。AX旧ON/OFF与截图异步时按日志/PID交叉核验。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - UniqueId 离线契约通过不证明本机属性可用

- **已跑验证：** Registrar ABI/CLSID、PropertyInfo两位数布局与45分支双引擎绿；本机仍为Native target UniqueId missing，原生child、展开和批准都没开始。该错误不能独自定为provider接口失败或属性不支持，须区分默认值、返回类型及不支持标志。
- **下次做法：** 不解析RuntimeId某个整数猜原生UniqueId/窗口，不以名字几何替代完整身份。Native UIA与MSAA转换可能给出不同编号，须从官方接口与本机返回建立同一对象证明，不能放宽比较来让候选通过。
- **夹具：** PowerShell7 Marshal.SizeOf(Type)重载绑定可能选object，把RuntimeType本身当结构；用GetMethod明确Type参数签名后Invoke验证尺寸。仅夹具错误，未改变生产ABI。
- **恢复：** 正常Stop121560核对退出，原包官方CLI恢复exit0，source/JS各自hash验证；scanner保持OFF，不让失败诊断留在用户日常运行态。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 同 SHA 一次重跑仍失败时保留失败并补充边界诊断

- **已跑 CI：** df29655 的 PR/push 首次 PS5 均在 owned-child READY10s 超时。各自仅重跑失败作业一次后，PR attempt2 成功、push attempt2 仍在同一处失败；PS7 均通过。不能只引用 PR 绿灯或把重跑成功当作不稳定已消除。
- **边界诊断：** 保留 10s READY、10s退出及原位数/路径/存活/退出259断言；超时记录持有的自有 child engine/PID、期望位数、退出前状态和两个读取任务状态，终止该 child 后有限等待读取READY/stderr。停止/读取异常只进诊断字段，仍抛原 ready timeout。
- **已跑本机：** 原正常双引擎125项通过；延迟15s READY的真实自有子进程重放，旧版缺少诊断而失败，新版PS5/PS7调用32/64位子进程四项均保留超时并通过诊断及退出验证。它证明诊断有效，未证明CI原超时根因。
- **工具坑：** JavaScript模板字面量内直接放PowerShell反引号会导致JS解析失败，尚未执行的工具不能说已创建文件；跨两层引号的精确替换先检查实际文本，匹配不唯一立即停止，再用单引号转义构造命令，不盲重跑替换。
- **下次做法：** 下一次CI超时按实际诊断区分子进程启动、stdout读取、stderr错误、退出状态；不得继续重复重跑、放大超时或改变断言来换绿灯。正式5.3.6仍须本机后台审批验收通过后才能合并发布。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - READY 前空输出只缩小范围，不等于已找到根因

- **已跑CI：** 51ca1a4首轮PR的PS5及push的PS7各失败一次，均是caller64的child32尚未退出、两个读取任务WaitingForActivation，终止后READY/stderr为空且stopError为空；child64已通过。未再次rerun。
- **诊断推进：** 自有child向捕获stderr写ENTERED、ENCODING_SET、READY_WRITTEN三个含PID阶段协议；成功路径要求完整内容精确等于三行，额外stderr仍失败，原10s及125项断言不变。空输出尚不能直接断言冷启动、AMSI或Console编码设置就是根因。
- **已跑本机：** 三阶段正常协议PS5/PS7各125项通过；真实child分别在编码设置前、READY写入前延迟15s，诊断只报告已到达阶段并保留超时，均验证进程退出；独立审查实际协议比较7项内存重放通过。
- **下次做法：** 从下一次CI真实阶段标记定位，不因当前推测改超时或增加自动重跑，不把纯测试协议修改当作插件后台审批修复。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 默认空值、ReservedNotSupported 与日志错误信息

- **已跑本机：** 完整绑定目标的默认 UniqueId 为 S_OK 空 string，而 Ex(ignoreDefault=true) 返回 S_OK COM ReservedNotSupported 且 CheckNotSupported=true；两查询合看才能确认当前目标不提供该注册属性。只读拒绝的 173 个 Note 稳定样本不等于审批通过。
- **下次做法：** 新增脱敏诊断用 ThrowExceptionForHR(hr, IntPtr(-1)) 忽略线程 IErrorInfo，否则调用方打印映射后的标准异常仍可能带出 provider 自定义消息；保留原身份校验的异常。PS5/7 完整方法及故障日志红绿验证不可省略。
- **工具：** 当前 Sky element_index 输入仍需 screenshot-backed geometry；geometry unavailable 后先刷新确认开关未动，再恢复一次。异步旧 OFF/ON 由日志与持有 PID 判定，不能盲重复切换。观察启动早于工具恢复不保证覆盖实际 scanner Start；明确排除过期捕获并为实际静置另开观察。
- **源码边界：** 新 C API/helper 完整单元放到既有 AOW 注释之前，不能插在注释与声明中间；归档后重新固定源码哈希。固定 Chromium 的页面 SetFocusedElement 不能独自证明 Windows SetForegroundWindow 或实际版本相同。
- **毫秒筛选：** PS7.6 ConvertFrom-Json 默认自动转日期再隐式转 string 可能丢毫秒，导致区间误收边界样本；用 -DateKind String 或保留原 ISO 字符串后显式解析。本轮独立原始观测复算 173，与 Node JSON.parse 字符串筛选相同。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 根节点 core 编号失败不能当全树无目标

- **已跑本机：** 绑定目标和native root路径推进到UiaGetRuntimeId，首节点返回E_NOINTERFACE、nodes1/core-fail，未继续后代遍历。不能称native树没有目标，也不能把客户端pattern QI某个provider IID当公开身份桥；官方控制模式契约区分client与provider接口。
- **观测边界：** 新90s观察虽覆盖scanner Start，仍在案例结束前约13秒到期；仅归纳实际216个静置样本，缺失段不得用末尾快照或日志填成连续保证。下一次在实际capture覆盖内结束案例，必要时提前检查observer结束时间。
- **恢复：** 正常Stop147588后CIM核对退出，官方CLI原包恢复并hash7F732F核验、UI OFF；只有只读拒绝证据，没有批准或焦点修复通过证据。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 空 stderr 与读取任务状态不能判定脚本未进入

- **已跑 CI：** f18ed6a 首次 push 双引擎与包校验通过，首次 PR 的 PS7 在 caller64→child32 PID764 READY10s 失败，PS5 通过；没有重跑。终止后空输出和 stopError 空仍不能代替真实 WaitForExit 返回值及 HasExited 核验。
- **已跑受控验证：** 真实自有 child 在脚本入口先 sleep、尚未取得 Console.Error getter 时，stderr 仍为空；写 marker 后 sleep 的 child 在 Kill 后则保留 marker，读取任务超时前同为 WaitingForActivation。不能由空 stderr 声称脚本未执行，也不能由该任务状态声称零字节已读；本轮不是 Console/AMSI/cold-start/ThreadPool 的根因证明。
- **下次做法：** 第一条旁证写在任何 Console getter 前，用独占 GUID 目录、nonce/PID 与三个精确 CreateNew+close 文件；成功仍要求原精确 stderr 协议。missing/partial/读失败只记未知，READY null EOF 与空行分开，终止返回值和最终存活分别记录；诊断及文件清理失败不得盖掉原超时。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 首根跳过不能放宽后代身份或填补观察尾段

- **已跑本机：** 精确首根runtime E_NOINTERFACE经三即时资源全清理成功后可进入FirstChild；本机186轮首后代仍runtime-core E_NOINTERFACE/nodes2。不能继续泛化跳过后代错误、手拼RuntimeId或将未比较的元素称目标；批准仍未发生。正常Stop161408后核对退出，原包CLI恢复和hash通过，OFF且Note197exact。
- **采样坑复现：** 120s仍在案例最终读取前到期，232个实际覆盖样本Note稳定，尾段8.581s明确排除。工具返回、分析及新调用都有墙钟成本，预设120s不保证覆盖收尾；下一次将短观察区间的起止与只读结束核验放在同一受限执行单元，按实际deadline中止并保留超时，不修改案例结束时间迁就捕获。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 阶段旁证的异常、清理与 UTF8 边界

- **已跑验证：** 冻结host源码776F1BBC双引擎各131项，实际故障边界各24及六个真实阶段延迟通过，原READY/退出10s、125项身份断言和严格stderr协议全部保留。文件missing/partial只是未证实阶段，明确区分null EOF和空READY；未定位CI原超时根因。
- **新坑与修正：** PowerShell点属性在异常getter夹具中可返回null而不进catch，改显式同一get_HasExited并真实验证。原typed catch在完整PS5故障夹具中将路径/读取错误误分为missing，机制未定；single catch只在路径已验证且实际base exception为File/DirectoryNotFound时记missing，其它保ownership/read-error。诊断helper或JSON失败必须保护原timeout。
- **清理：** 先确认最终绝对目录、恰好原三个basename与顺序，再做任何删除；确认自有child退出才删除三个文件及空目录。读/删/终止失败各保留状态，不能误删同目录foreign文件，不能把empty stopError当已退出。
- **Temp编码：** PS5直接-File读取无BOM中文夹具可能误解码；固定显式UTF8 AST与major验证launcher后重放，旧解析失败日志保留。项目原UTF8 AST入口不受此次临时launcher问题影响。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - raw 有返回仍不等于完整目标身份

- **已跑本机：** 0E2519隔离候选94对root/FirstChild均raw S_OK、VT_I4一维len4/append、cleanup成功，但core仍E_NOINTERFACE且first-child原拒绝；没有批准动作。不能由core错误推论全部公开provider不可用，也不能将relative array拼接为目标full RuntimeId。
- **观察修正：** 在同一受限单元记录10秒无输入起止与结束核验，本次52个样本完整在实际120s观察期限内，Note197逐字保留；600全记录与24 IDE资源类型由原JSON确认。零动作稳定仅限拒绝路径，不是审批体验通过。
- **恢复：** 正常Stop168704核对退出，官方CLI原包restore0/hash7F732F、UI OFF，再恢复Note前台；正式scanner未改。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 只读命令目录不能把省略当不存在

- **已跑本机：** getCommands(true)当前2984 ID，关键词匹配64但ASCII白名单只输出62，complete=false；另外2个未知，不能据此关闭一次审批命令假设。下一步用bounded ASCII转义JSON保留完整字符串，不执行返回ID。API仅当前已注册非下划线ID，名称不是公开target参数契约。
- **新坑与修正：** unknown异常可能是Proxy，instanceof本身会触发getPrototypeOf并再次抛提供者文本；errorKind自身catch为固定Other，原实际编译函数红灯与最终9组mock绿灯及peer复审保留。官方VSCE会正规化README/LICENSE文件名，包字节核对应实际6entries映射，不能猜文件名。
- **恢复：** 独立目录扩展执行后exactID官方卸载/确认不存在，原插件source/JS hash保持、OFF无child、Note197exact；只枚举目录不证明审批通过。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - PS5 Hashtable 的 AST offset 排序须显式取 key

- **已跑候选生成验证：** 新独立启动A/B候选在PS5的Sort-Object Start未按Hashtable键值排序，真实最小输入7/9/5返回5/9/7；原AST offset与Extent均正确，却因无序插入导致候选parse在任何child Start前拒绝。首失败日志保留，不能归因原CI启动问题。
- **复用修正：** 用显式Expression={ [int]$_['Start'] }排序，并对每个原始AST插入anchor逐字校验；最终候选及CI结果须另行验证，原宿主测试及超时未改。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 目录 complete 的范围须限定当前过滤集合

- **已跑本机：** 转义JSON补齐之前unsafe2，当前2986 registered ID里关键词64全部输出；原62全保留，额外仅Webhint浏览器检查和AutoAccept日志通道。complete=true是这一刻非下划线/关键词/长度数量集合完整，不证明隐藏或未来命令不存在，更不是审批公开参数契约。没有执行任何返回ID。
- **恢复：** 只读GUID扩展用exactID官方卸载/list absent，原source/JS hash保持、OFF无child/pending，Note197exact并主动恢复前台；运行中host缓存的旧命令不能用list absent反推立即清空。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 备用日志也必须保护原异常

- **已跑红绿：** 独立A/B脚本ledger写入/输出持续失败时，catch内备用Console.WriteLine再次失败会盖掉原owned-child timeout；仅已有startupFailure分支给备用输出try/catch{}，无原异常仍throw，peer用实际catch和持续stdout故障复验两边界。不能用输出恢复失败替换原启动错误。
- **引擎边界：** 工具请求shell路径仍可能以外层PS7运行；用准确System32 PS5 exe启动被测caller并验证major/bitness，守卫在child前拒绝保留，不能归因候选。正式CRLF归一须更新候选hash并核对除换行外文本相同，原frozenhost hash不变。
- **范围：** 独立fresh-runner A/B只提取21项，不能替代原131required回归或把一次绿灯称机制定位；不预热、不rerun、不延长原10秒。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - A/B 两输入同绿不能定位间歇机制

- **已跑远端：** de056a3 A/B四freshrunner与PR/push均首轮通过，四artifact各21/原host与scanner hash/确认退出和准确清理核对通过，无重跑。两输入均绿只能证明这轮执行结果，不隔离原f79 READY10s未知故障；CI通过也不替代pending后台审批/焦点/连续输入/多IDE实测，发布仍跳过。
- **正文比较：** 原模板hash相同，但自有GUID/nonce/路径不同使actualbody hash各异；只称语义模板同源，不称实际正文逐字相同。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 公开转换成功与捕获覆盖分别核验

- **已跑本机：** 188F候选root/first-child各341条公开IAccessible转换均六HR S_OK/fullSamefalse/cleanuptrue，零CLICK；证明两个非目标元素可转换，不证明整树无目标，也不能改用relative编号或名称坐标放行。原目标完整身份仍须实际命中。Stop183028/CIM退出、CLI原包hash7F/JS2F85、OFFpending、Note197exact均核对。
- **兼容坑：** 新QueryInterface完整方法在PS7 .NET10的CS9191与PS5未知pragma CS1691分别实跑失败；只在新增方法局部1691/9191成对disable/restore后完整双引擎编译通过，不能全局IgnoreWarnings或把早期候选hash当最终包。
- **观测：** 实际120秒捕获启动后509样本含183 IDE与326 Note，不能写全Note或无input handsoff；到Stop约3分16秒尾段未覆盖。后续在同一受限单元记录短区间、立即完成Stop/恢复再分析，避免收尾分析耗尽observer。实时目录Length显示0时实际文件读到234105字节，状态用真实读取/start-stop记录确认，不据元数据认定空观察。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 协作预算停止不是 provider HRESULT 失败

- **已跑本机：** ACF只读sweep START1/71node，前70完整len4均不同于targetlen6，第71在ElementFromIAccessible S_OK之后预算检查中断，RuntimeId/Compare未调用；readHr80131509是managed预算异常，END1583ms/wall-budget。不能把日志format element-convert-throw当原生转换HRESULT失败，不由局部长度差异称全tree无目标。73prepare不等于73遍历，client一次消费阻止重复query。
- **覆盖：** 手离10.448秒/52样本全Note且逐字197保留，但实际单轮查询更早在IDE前台；只证明后续拒绝路径静置稳定。Capture结束到Stop27.731秒排除，预算包含sweep内层清理但非outerbinding/finally、不取消COM。
- **交接：** 所有root台账字段定稿后再交peer固定hash；本次peer读取期间root追加handsoffAudit使ledger hash变化，原始log/observer保持，复算按新冻结hash完成。不得将此交接顺序问题归因候选。
- **工具：** Marketplace extensionquery必须带api-version，缺失请求被服务拒绝，3.0-preview.1实际核验成功；用Stop保留原API异常，不让后续null集合检查遮盖。Windows rg的通配文件名使用-g作用于目录，不把docs/verification-*.md当LiteralPath。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 可见性重读与实际宿主根分别验证

- **已跑动态红绿：** 前置IsOffscreen=false不能封住旧if第二读变true的ScrollIntoView。Temp5848在旧offscreen body首句continue，保留旧body；PS5/7各3例9项确认旧Scroll1/query1到新Scroll0/query0、稳定可见collapsed query1。CandidateDiagnostic也读属性，首fixture没有触发真实旧分支；需从实际模式取得后控制时序，不把恒定属性case当race覆盖。普通路线未禁，只有browser动作拒绝边界。
- **夹具与执行上下文：** failed Simple out不能把此前成功Fragment RCW包装混计；首次PS5日志异常后仍写PASS不算通过，最终外层catch/exit和具体pointer修正保留红绿。UTF8 ScriptBlock没有原文件PSScriptRoot，必须显式传目录；不能把这些夹具/loader错误归因native provider。
- **已跑本机：** 实际FragmentRoot标准QI/selfSame/options226/Host/UiaNodeFromProvider全S_OK，RuntimeId仍80004002/arrayNULL，type/Compare not-called、cleanuptrue、marker1而prepare100、0CLICK。只证明root core入口成功，完整目标身份未命中，不能拿root或Host作为原More授权。
- **UI恢复与边界：** 原history选择空白后只Reload一次，再正常history选择出现workspace picker，Open in current window恢复原审批；不是未验证的隐藏面板隔离或盲重试。Stop199752/原包hash7F/JS2F85/OFFpending/Note197exact与3repo8hash保持核对；本轮无observer，不补造后台焦点或持续输入证明。
- **SDK 枚举须查源：** ProviderOwnsSetFocus=0x10(16)，128是HasNativeIAccessible，实际root options226不含OwnsSetFocus；不能按记忆猜bit值或从根flag直接推More动作抢焦点的根因。公开UiaNavigate返回cache SAFEARRAY/BSTR，转换函数准确名为UiaHUiaNodeFromVariant，不是直接out HUIANODE。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-08 Asia/Shanghai - 窗口完整编号可读仍须匹配原目标

- **已跑本机：** 539唯一nativeHandle的core/runtime均S_OK/完整len6，原Compare S_OK/fullSamefalse，cleanuptrue、marker1/prepare44、0CLICK。预定终态throw80131509不是provider失败；相同len不能代替目标完整ID。真实query6采样均IDE前台，不把随后Note拒绝轮询93样本称后台审批。
- **有限夹具：** 原binding重试也会再Compare，不能用累计次数划分core阶段；只修自有fixture按acquisition状态区分，保留首两红exit1。verifier按真实完整函数字面变量名核对，不猜rootPid/nativePid。throw-out时HR占位表示未取得返回值，可能已尝试，不一概写not-called。
- **覆盖与恢复：** Note无ROOT输入实际21.767秒，最后3.055秒超出60s observer，距末样本3.240秒；只报覆盖93样本、资源仅IDE35596，observer进程exit由ROOT工具返回归属，不由JSONLstop推出。未抓live scannerPID只可报Stop后currentparent无child。
- **工具边界：** Sky元素输入仍须最新截图几何；首次无geometry后先fresh观察OFF再重试，AX一次刷新可滞后，不盲目二次toggle。安装JS路径从package.json.main读取，不猜包根；CIM命令行过滤须限定原extensionHost父PID，否则观测shell文本会自匹配。PowerShell foreach语句结果先赋值或用@()包裹，再接管道。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-09 Asia/Shanghai - None 缓存带模式的真实首槽与日志共享读取

- **已跑本机：** 541 唯一 UiaFind 与模式转换均 S_OK，缓存首槽非 null/DBNull而被拒绝；首槽类型和值未知，不能假定零或据此释放未知节点。零展开/批准；Stop30712确认退出、原包CLI/hash恢复、OFF/pending、Note197及用户3repo/8files逐字保持。
- **复用边界：** WPF None 不使用首节点槽，但带模式的真实返回不能由原无模式夹具推断。明确空值和整数零与完整目标身份校验分开；非零仍拒绝且记录类型/空标志，完整RuntimeId、child、回映和最终审批守卫不得放宽。下一次后台实测在消费前检查IDE前台，拒绝不消耗唯一查询。
- **本轮工具坑：** functions.exec 无 crypto 全局，需由宿主生成GUID；IDE日志仍打开时 ReadAllBytes 被共享模式拒绝。用显式 ReadWrite/Delete 共享的只读 FileStream、核对offset/长度并逐字读取；ErrorAction Stop 防止首次读取失败后继续产生无效切片和级联错误。Sky只输出accessibility/窗口元信息，不序列化含data URL的完整截图对象。
- **证据边界：** activation调用开始不等于已切换完成，采样区间含人为切窗过渡时不得说全程Note稳定；observer main-process资源不证明scanner资源或泄漏，内存夹具绿不代替本机动作/焦点/连续输入/多IDE。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-09 Asia/Shanghai - Full 身份成功不能补出 Legacy 服务端

- **已跑本机：** 542 None 首槽实际非零 Int64，零值兼容未奏效；543 显式 Full、官方节点转换、缓存及节点完整 RuntimeId 均 S_OK/匹配，Legacy accessible 仍 S_OK NULL，零展开/批准。Null 符合公开 proxy/bridge 契约，不继续放宽身份或释放未知原始槽。
- **调整方向：** 之前托管和 COM Expand 已实机抢前台，WPF 又使用同一 C API；再次换同一底层入口不构成新修复。产品先延后会聚焦的窄菜单动作，仅目标 IDE 前台且输入空闲时处理，普通后台审批保留；最后只读检查仍有不可原子化的外部调用竞态，不写绝对无焦点保证。
- **工具：** 临时 launcher 实参须先读签名，run-utf8.ps1 只有 TaskScript540；错误 Path/ExpectedMajor 导致测试未进入，保留红日志后用正确参数验证，不归因候选。读取临时测试文件先列真实文件名，Windows rg 文件过滤用目录加 -g，不把通配路径当 LiteralPath。
- **验证：** 543 三组合完整编译及各77例2227检查、独立审查与唯一 native 查询均归档；Stop11608/原包恢复、OFF/pending/Note197、3repo8files保持。查询采样只有1条、静置75条，不能称后台审批通过、scanner资源或多IDE验收。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-09 Asia/Shanghai - 暂缓动作的续办身份与按键状态

- **独立复现：** 展开后最终输入守卫暂缓会遗留无标签 portal 菜单，下一轮原“只用新菜单”过滤不能续办；原输入数组仅含鼠标与修饰键，Enter/字母长按且输入戳不变时被漏过。修复保存精确 PID/HWND 对应卡片、文本、触发器、菜单及菜单项身份，并重读全部虚拟键高位；任意用户旧菜单不借此接管。
- **再次红灯：** PowerShell -ceq 是区分大小写的文化比较，git+[U+00AD]+hub.com 与 github.com 可判等；真实生产函数跨轮批准一次。续办文案必须使用 String.Equals Ordinal，与旧卡片验证一致。仓库加入软连字符动态拒绝用例，保留旧实现红日志。
- **验证边界：** 三项均由独立动态夹具复现；全套及真实本机结果另行归档。前台查询与外部 UIA 动作不能原子化，不承诺任何切窗时序下绝对无焦点竞态。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-09 Asia/Shanghai - 浏览器 tab 前台与 Windows 前台不能混计

- **已跑本机：** Chrome 专用接口确认 MDN URL，并保留两段中英文输入；Page.bringToFront 改变选中 tab，但只读 Windows 采样实际仍是原前台应用，零 Chrome 样本。不能由浏览器焦点或页面输入成功写“Chrome 前台输入通过”。Windows 工具的 URL 识别保护两次终止当前 turn，立即停止；后续使用受支持的浏览器接口只证明其自身范围，不关闭保护。
- **双窗口：** 正常新建窗口后真实两个 extensionHost；两个方向 WAITING→同 PID ready、原 owner 退出均核验。窗口一扫描器在窗口二本机前台时批准其本次域名，5 个动作时间桶采样稳定；随后模型服务 503 是任务服务问题，不等同插件批准失败或任务完成。
- **工具坑：** CLI new-window exit0 不等于可见窗口，须核对 inventory；用实际菜单快捷键后才出现第二窗口。不要把 minified bundle 的整行 rg 匹配直接输出，先限定文件或返回文件名。JS 未创建的全局绑定不能裸赋值，统一显式 globalThis 初始化；只读失败不重复输入。gh HTTP EOF 后保留失败，再核对同一个 run id，而非重跑 CI。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-09 Asia/Shanghai - 原生身份测试与脚本引擎启动分层

- **已跑 CI：** 725aea2 首轮 PR 的 PS7、push 的 PS5 均在 caller64→PowerShell child32 READY10s 超时；三个独占 stage 均 missing，停止后 stdout null/stderr 空，child 确认退出且准确清理。未到失败 child 的生产路径查询，不能把它称为 GetProcessImagePath 错误，也未隔离 AMSI、冷启动或 OS 根因。
- **测试边界：** 原生路径/句柄/退出身份测试可用明确架构的最小 Framework C# child，保留真实 IntPtr.Size/PID/完整路径/259/严格流/三个 nonce stage、原 131 项与 10s/45s。原 PowerShell 启动覆盖另存字节冻结入口，不能直接改 host 源后让固定 SHA/AST 的诊断失效；其 workflow filter 同时登记冻结源。
- **清理红灯：** 独立注入 binary 目录额外 sentinel，删除空目录失败却仍 exit0/DONE131。清理旁证须在正常路径 finally 之后设失败门禁，不能在 finally 抛错覆盖先前编译或 READY 超时。编译器和 child 都须按本次 Process 对象确认退出；stage 三文件与二进制目录白名单分别校验，非递归删除，不吞外来文件。
- **已跑本机：** 原型及最终 gate 的三 caller 各 131 项、四冻结诊断各 21 项、全套 npm test 通过；编译错误/自有编译器替身超时/native READY 延迟均保留失败，进程与目录回收另行核验。它证明测试分层与资源路径，不证明远端原启动根因修复；仍须新提交首轮 CI。

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 并发批准日志必须单行绑定真实目标，观察工具也要核对当前文本

- **复现：** 多窗口及同窗多任务产生相同 Submit 成功文案，旧日志不能区分真实准备命令、指定目标或卡片。不能由请求文案反推实际批准目标，也不能据相同标签宣称发生重复点击。
- **修复验证：** 使用最终核验前的 PID、HWND、原卡片身份和精确 UTF-8 目标 SHA-256；动作后不再读取可能消失的 UIA 元素。通用 Run 加 CR/LF 快捷键可拆断单行协议，Invoke 与 physical 红例均保留，转义仅作用于日志标签，哈希仍对应原始内容。测试须检查单条协议行，不能只在全部 writer 输出中查找归属文字。
- **测试启动：** 真实生产尾段增长后超过 Windows 命令行长度，两个测试启动器均改用自删 UTF-8 载荷；临时目录显式指向本轮 F 盘。保留首次命令过长失败，不放宽批准、冷却、超时或清理断言。
- **观察边界：** Chromium Message input 的 ValuePattern 可保留已删除的旧值；本轮截图与 TextPattern 文本范围交叉证明当前输入为空。只清除与本轮已发送文案逐字相同的可见草稿；任何不同内容均保留。UIA 状态按钮要定位 Button，Group Invoke 可能无效果；运行时编号变化必须重新读取。
- **身份与时间：** PS7 JSON 日期回写会改变小数位字符串格式，身份应核对 UTC ticks、PID、路径、HWND。系统重启后旧窗口和浏览器身份全部退休，不能沿用旧 PID、旧会话句柄或拼接重启前后采样时长。主动关闭重开产生的 rootMissing 必须按阶段逐条报告。
- **前台与审批：** 最小化 UIA 树可能收缩，使用仅恢复不激活的原生展示取得真实待批截图。工具对状态按钮的 Invoke 也可能影响前台；须以实际成功日志核对何时审批结束，不能把已经批准后的关闭重开写成待批生命周期验证。
- **证据：** 本轮原始材料保存在 F:\CodexTests\AntigravityAA\concurrency-20261020-7d2c\evidence。恢复测试使用实际生产扫描尾段及内存查询/动作替身，不宣称注入了真实原生提供者故障；动作后禁用的桩也不能证明仍保持可用的卡片具有额外去重机制。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - UIA 资源寿命与待续办归属必须一起验证

- **现场失败：** 同一个扫描 owner 在约 36 分钟内私有内存从 81.8 MiB 增至 193.4 MiB；句柄和托管堆基本稳定不能否定私有内存增长。独立只读 UIA 查询即使周期性完整 GC 仍增长，不把观察结果直接归因到某一 Windows 模块或原生分配器。
- **修复边界：** 合作式到期刷新沿用现有 finally、等待者接管和自动重试；未完成的无标签菜单保存在 owner 内存，不能无条件退出后假定下个 owner 能重建授权。最小化、隐藏、查询异常时保留状态并推迟刷新，明确不是硬性内存上限。
- **红例：** 首次无保护版本会丢续办；仅保护菜单查询异常还漏掉窗口句柄读取异常。完整窗口身份快照不可读时，不能把缺 key 当作窗口已关闭；后续完整快照确认关闭后仍需清理，否则会永久延期。
- **夹具坑：** PowerShell ScriptProperty 抛错可能在调用表达式表现为 null；先转 long 会变为 0 而绕开 catch。读取一次、先拒绝 null/0，再生成窗口 key，保留两次失败及最终绿例。真实 CLR 属性异常与脚本属性替身的行为须分层核对。
- **输入观察：** 新会话 TextPattern 还可能只返回控件名 Message input。先留截图证明占位，只有该精确占位与空 Value 同时成立才视为空草稿；不据旧 Value 清除内容，不放宽任意非空草稿保护。
- **验证：** 184 项扫描器检查与独立 8 项句柄异常/恢复案例通过；本机 15 分钟自然刷新及至少 30 分钟资源走势另行验收，不能用替代时钟红绿冒充真实等待。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 自然刷新验收与观察缓存分层

- **已跑原生：** 最终扫描器 528b83b2 连续 35.56 分钟、312 个资源样本、8 次真实批准，实际 15 分钟时钟两次到期；一次由等待者接管，一次单窗口退出后 3 秒自动重试。两张待批卡前后 runtime/父卡片相同，恢复前台后对应目标各只批准一次。此证据不证明未解决菜单或原生调用阻塞时仍有硬内存上限。
- **状态观察：** 最小化或遮挡的 Chromium UIA 状态栏可返回缓存文字。恢复后新树与截图显示 WAITING，日志也为等待；不能用最初旧 ON 文本推断第二 owner。窗口状态采样、实际 READY/退出事件与 mutex 回归须联合判断。
- **时间归属：** 菜单 pattern 阶段在 00:07:24，成功事件实际在 00:07:25；不要猜同秒成功。审计按 PID/HWND/真实父卡片/精确目标哈希关联，再读实际成功时间，保留首次错误假设导致的断言失败。
- **进程观察：** Get-Process 的 StartTime 和 CIM CreationDate 精度可不同；以已登记 CIM 时间值核验身份。已不存在的已知 PID 是预期退出证据，不该合并成“身份已改变”的异常，更不能因观察失败重启产品。
- **收尾：** 原始采样、失败候选、红例及真实截图均保留；计划关闭的 rootMissing 和正常 3 秒重试零扫描器样本必须列出，不删掉后称全程无间隙。商店上传与实际公开包哈希校验仍分别完成。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 空白窗口捕获与模型自述不能冒充工具输出

- **独立审查：** 最小化窗口的 PrintWindow 可生成 276×45 空白 PNG；保留为观察失败，不能只因存在图片文件就列为成功截图。有效 UIA 中的标记还需读取父节点来源，本轮标记属于 Agent response，不能称为原始终端 stdout。
- **验收边界：** 精确命令指纹、窗口/卡片及唯一成功日志证明一次批准；模型报告输出单独标注，未捕获原始 stdout 明确说明，不扩大 M1 审批验收结论。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - CI 预期跳过与可恢复测试清理

- **合并门禁：** 分支 push 的 Release and extension stores 按 workflow 条件 skipped 是预期；核对同一精确 head 的两个测试引擎、VSIX 必须 success，整体 conclusion 必须 success；不能要求所有条件作业都成功，也不能据门禁误判去重跑 CI。
- **安全清理：** 五个独占测试目录的永久递归删除被自动审批拒绝，改为可恢复回收站成功；不清空回收站。先核对原始日志逐字归档及 manifest、PID/创建时间/命令行退出、真实白名单路径和无重解析点，保留全部失败样本与候选。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 商店缓存登录与审核中版本必须分层核验

- **Open VSX：** 前端保留 fhgffy 用户菜单不代表服务端会话仍可发布；首次 Forbidden 后刷新页面显示 Log In，经原有 OAuth 正常刷新再上传才接收。先核对精确版本尚未存在，避免重复上传；不创建新令牌或扩大权限。
- **公开证据：** 管理页可显示 Latest 5.3.11 和扩展 Public，而精确公开 API 仍404、用户页仍5.3.10；审核接收不等于公开可下载。随后原 CI 查询函数核验发布者、精确版本及实际下载SHA与GitHub原包相同才通过。窄浏览器截图要实际看到版本标题，不能把只有警告横幅的图当上架证明。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 自测子进程也必须并发排空重定向管道

- **实际失败与边界：** 文档提交86dc867的push PS7出现SelfTest timeout，同提交PR CI成功；首次作业未保留child输出，不能按猜测认定远端是管道、编译器或冷启动问题，也不直接重跑抹掉红灯。
- **独立复现：** 抽取真实Start-TestProcess与SelfTest循环，子自测输出131072字符及有效DONE仍在15.12秒超时；父进程先WaitForExit后ReadToEnd导致管道反压。先发issue #24，再写真实进程回归红例；修正为同时异步读取stdout/stderr，原15秒及exit/stderr/marker要求保留。
- **恢复与证据：** 真正停滞场景即使提前输出有效DONE仍必须失败；有限收集两条流和原Process退出旁证，finally不盖掉原超时。两引擎10例覆盖大输出、stderr、exit、缺marker和15秒停滞；包装器修复不等于已确定远端原超时原因。生产运行文件及5.3.11原包不变，不发空补丁。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 测试观察函数取得资源后也必须负责异常收尾

- **独立红例：** child已启动，读取StartTime/MainModule或写身份回执失败时，调用者的process赋值尚未完成，外层finally不能回收。把回执目标设为目录可复现退出失败与child仍存活；先保留红脚本、结果及按父PID/路径/唯一nonce核对的清理回执。
- **修正边界：** 观察函数用自己持有的Process对象有限Kill/Wait5000/Dispose，诊断不覆盖原写入ErrorRecord。永久回归借已有独占EXE及自写PID，在红例外层兜底清理；目录替身单独登记，按白名单非递归删除。两引擎12个定向用例通过后再重跑完整套件，旧全套只能记中间候选。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - CI 的临时路径短名不能直接与 .NET 异常文本比对

- **真实红例：** c1f0a2f 的两路 CI 共四个作业只在新增 ledger-failure 断言失败；8a03381 仅补原两流后确认，Node 的 TEMP 为 C:\Users\RUNNER~1，.NET WriteAllText 异常使用 C:\Users\runneradmin，原错误和 child 退出均保留。不要把布尔路径不匹配误称为原异常丢失，也不能猜成首轮 SelfTest 超时原因。
- **最小边界：** 创建独占目录后用 fs.realpathSync.native 得到真实路径，随后夹具、回执及清理身份统一使用它；保留原 stderr 路径严格断言、非零退出、退出确认和 PID 不存活要求。不得改为忽略路径、只检查非空 stderr 或跳过 CI 用例。
- **验证分层：** 同版 Node22 的本地长路径12项通过也未覆盖 CI 短名。F 盘 GetShortPathName 无短名别名时如实记录；C:\PROGRA~1 只读目录错误可证明 .NET 与 Node 的规范化，但不能冒充真实短名 TEMP 端到端绿例，后者必须由最终 CI 给出。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 本人完成验证码与商店实际公开下载是不同发布阶段

- **完成链路：** Marketplace 本人完成验证码后显示 Verifying 5.3.11；最初精确公开查询仍不通过。等待后使用原 CI 函数核验发布者、精确版本及实际下载 SHA，于 01:42:02+08:00 通过；Open VSX 再次公开下载同 SHA。三处原包一致才勾选发布完成，审核接收不是公开成功。
- **权限与失败样本：** 沿用用户既有登录，不代解验证码，不创建发布密钥、不扩大权限，也不重复上传审核中的版本。保留 CAPTCHA、Forbidden、审核中、空白截图、SelfTest 首次失败及 8.3 路径假红，成功结果不覆盖这些原证据。
- **维护提交：** 测试包装器最终两路 CI 和合并后 main CI 均通过；运行文件与原 Release 不变。已存在版本的不同提交触发原包保护，不覆盖标签、资产或商店，也不为测试与文档生成空版本。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 文档替换参数与表格也要逐行自审

- PowerShell 调用函数时，多个片段拼接的参数先赋给变量或整体加括号，不能把运算符当成多个位置实参传入。UTF-8、CRLF 和 diff --check 通过不代表 Markdown 内容正确；本轮完整 diff 发现渠道表格两行替换损坏，提交前修正并核对三行四分隔符，保留原运行源码不变。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 自测不能依赖无关桌面，空输出超时不能倒推根因

- **事实分层：** 5d32e09 的 push PS7 再次超时，两流均完整却为空、child 已退出；同 head PR CI 成功。保留首次失败并创建 Issue #26，不重跑抹掉红灯。没有阶段输出就不能断言卡在 RootElement。
- **独立缺陷：** 原完整脚本在 SelfTest 前读桌面根并创建 8 个条件，但 95 项判定不使用它们。独占副本将唯一 getter 替换为精确异常，PS5/PS7 首次均红；仅给这 9 个赋值加 -not $SelfTest guard 后均绿。C#、22 函数、匹配表、普通扫描作用域/顺序不变，不跳过断言。
- **后续可诊断：** 测试子引导立即 Flush 启动、读源和解析阶段，timeout 回归新增严格阶段断言先红。原 15 秒、exit/stderr/DONE、同 Process 退出及两流诊断保持。该独立修复不证明历史9016卡点；生产源变动必须新补丁5.3.12，不覆盖已上架5.3.11。
//***

<!-- 来源：main；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 非空补丁的正式原包与商店接收必须继续区分

- SelfTest生产源改动已用5.3.12新标签发布，精确head两路CI、合并后main及GitHub下载/摘要/校验文件/包内运行字节均通过；原5.3.11不回写。CI明确商店凭据未配置，即便发布作业success也不能勾选商店完成。
- Open VSX再次出现缓存头像仍在但发布Forbidden；正常刷新原OAuth后恢复，无新权限。OAuth返回首页的首帧可能仍显示Log In，稍后重新读DOM出现原用户菜单；不要在过渡帧上反复点击登录。接收Under review与公开API404必须分开记录。
- Marketplace新版本再次要求图片验证码时保留现场并向本人异步交接，同时做完其他发布/文档/清理；不能沿用上一版本的“已完成人工验证码”冒充新挑战已完成。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 18:55 +08:00 - 发布状态、当前认证与退出码的证据边界

- **Git 与 shell：** PowerShell 未加引号的 HEAD^{tree} 被当作脚本块参数，Git 收到编码字符串而失败。给完整 revision 字面值加单引号并检查原生命令退出码，才可比较 HEAD 与 origin/main 的完整 tree；失败请求保留，不能按空输出宣称树相同。
- **认证与界面：** Open VSX 上传 Forbidden 时，缓存头像及已签协议状态不能证明当前认证有效；刷新后出现 Log In，经正常既有认证刷新后，同一 Release 包上传由 Reviewing 到 Public。先检查实际登录状态和新鲜 DOM，不把 Forbidden 直接归因发布权限，也不为此新建凭证或扩大授权。旧 Close 节点 detached 后重读实际界面，不重复点击已关闭弹窗。
- **授权边界：** 两商店文件选择均可使用已授权的 filechooser.setFiles；本轮没有再要求用户选择 VSIX。Marketplace 上传触发 CAPTCHA 后，浏览器 Computer Use Confirmation Policy 的 Solving/completing CAPTCHAs 要求当次确认，发布预授权和重新登录确认不能替代；等待确认前不选择图片、不提交挑战。
- **验证命令：** 直接调用 PowerShell 脚本成功不会保证设置 LASTEXITCODE；null 或遗留值会让外层误报失败。本轮 VSIX 内容八文件检查已成功但外层 exit 检查失败；改为独立 PowerShell 进程、立即保存其原生退出码后验证 exit0。区分脚本异常与原生进程退出码，保留假失败记录。
- **公开发布核验：** PR 合并、main 首轮 CI 成功、GitHub Release 和两个商店分别核验；main 发布任务明确报告商店凭据缺失，不能把其 success 当商店上线。Open VSX 公开 5.3.6 元数据 downloadable=true，实际下载包 SHA256 与 GitHub Release 完整相同，独立包验证 exit0；Marketplace 尚待本次验证码授权，持续输入的本机 Chrome 前台场景仍未验收。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 19:29 +08:00 - 最小化测试、观测期限与服务失败边界

- **只读观测：** 原 120 秒窗口已终止，第一组重做落在其终点之外；不能补造全程覆盖。自有临时观测仅放宽 ValidateRange 到 900 秒，原采样和查询保留，按实际 scanner 进程退出结束。两 observer 均 exit0；只报告重新观测中 79.614 秒的 398 个稳定 Note 样本与实际覆盖动作。
- **最小化与输入：** Windows IsIconic 确认第二 IDE 最小化；扫描器正常 ready，Note 104→168 字逐字保持，撤销/重做分别 147→126→147 和 168→147→168。最小化窗口的 sky.get_window_state 不可读取内部界面，需正常激活、get_window 重绑定后再读；不能从不可见状态推测审批存在。
- **界面与服务：** Chromium Message input 的 set_value 返回成功但新鲜树与截图仍为空；按实际编辑区定位后一次 type_text 写入，读回完整 Value 和 enabled Send 才提交，未重复文本。新的浏览器任务最终显示 network issue，未生成可核验审批，不重试模型容量或认证假设来伪造审批通过。
- **文件共享：** 活跃 observer JSONL 的 ReadAllText 再次遇到共享模式拒绝；此前日志共享读取经验同样适用：活跃时显式只读 FileStream、Share ReadWrite/Delete、固定长度和完整行边界。最终两 observer 已退出，冻结文件读取及独立汇总通过；失败读取本身不算资源采样成功。
- **恢复与界限：** 正常 Stop 后本次 PID79920 不存在、两窗口 OFF，3repo/8dirty hashes 原样。短时 scanner CPU/内存/句柄数据另存，不推长期无泄漏；Chrome 前台输入和真实最小化审批仍缺证据。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 20:25 +08:00 - 原始证据检查器的假通过与纯文本服务对照

- **已跑红绿：** 旧临时检查器对11项故障均exit0：错误undo/parent、实际Invoke/Physical日志、第二窗口批准、计数/创建身份/CPU顺序/未知记录及raw OFF。生产成功前缀为 Auto-accepted (Invoke/Physical)，不是 Auto-accepted:；检查两窗口全部phase并从raw记录核验，不能把汇总中的常量当证明。
- **独立审查：** 第一严格版仍接受空哈希表、缺observer脚本及同数量换名；三项独立红例后补固定本轮38 basename完整集合，最终原12项加3项通过。自包含哈希表不等于外部签名，真实归档SHA由根另行冻结；默认只读并核对前后全部文件，旧检查器和原始材料保持。
- **本机对照：** 原会话只读浏览器任务及新会话纯文本无工具任务均1秒终态 Agent execution terminated due to error，两scanner OFF且本轮日志切片0。仅说明未进入可验证审批阶段且失败不要求浏览器工具；周期性CAIC project key not found没有与请求精确对应，不确定认证、配额、代理或服务根因，不盲点Retry/重复要求登录。
- **持续目标：** 单轮扫描器Stop是测试清理，不能将已获授权的持续测试、合并和发布改成每轮等待用户再推动。单点验证码待当次确认时继续独立工作，有限场景和检查器通过不缩小总体目标。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 20:43 +08:00 - 持久浏览器绑定与窗口替换分别恢复

- **工具恢复：** CUA 持久会话中已有 let 绑定时，即使 var 位于 typeof 条件内，仍会在整段解析时报重复声明，前置操作也未执行。确认现有绑定后直接复用，不再次声明同名变量；domSnapshot 返回值必须显式输出才能读取，不把末尾 markHandoff 的空返回当作页面状态。
- **现场边界：** 本轮 IDE 状态读取先报前台进程信息不可读，按技能重选旧 HWND 后发现两个旧窗口已不在，新 inventory 只有 HWND1640832。从真实新窗口重新观察成功，当前有 Open Folder 和 AutoAccept ON；不得把前面的读取失败归因插件或认定整个 helper 故障，不操作正在选择的目录。旧 PID79920 退出只证明旧测试清理，不能停止或吞并新窗口实例。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 21:35 +08:00 - 真实审批、观测缺口与异步退出分层

- **发布核查：** 待验证码期间先读新鲜公开 validated 元数据；本轮已由人工完成，实际 Marketplace 包与 Release/Open VSX 完整 SHA 相同。不重复上传、不再求相同确认、不冒充自动完成验证码。
- **服务与审批：** 新 Gemini 400 region unsupported、GPT 纯文本 OK、browser CDP 失败后 URL 一次审批 Invoke 成功、随后 TLS/429 终态分别记录。URL 读取表单不等于 Browser More actions；任务未完成不等于批准失败，模型 Panel 0% 不能推断每个模型均不可用，不无限遍历模型或改代理/订阅。
- **观测期限：** 本轮 120 秒 observer 结束至恢复有 135.675 秒缺口；只能报最小化后 294 个采样，不补造全程无干扰或审批生成时刻。同 PID84616 的两个 IDE 窗口须按实际 HWND 区分，不用 PID 判断谁在前台。
- **生命周期与依赖：** 关闭自有窗口后先确认原实例仍在，稍后外部退出导致 mandatory Get-Process 失败。当前缺失要正常记录，不能据此重启用户实例或归因插件/清理；依赖工具须检查 exit_code 成功后再读结果，避免级联 ENOENT 产生假结果。
- **CLI 与异步：** 此安装准确入口 antigravity-ide.cmd，PATH 的 antigravity.cmd 属另一安装。new-window exit0 仅证明请求发出，首次 inventory 未出现时等真实窗口出现再绑定，不能据此重复 launch。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-09 21:58 +08:00 - 由退出顺序区分插件停止与宿主关闭

- **退出证据：** Auto Accept 扫描器最后一次正常轮询在 21:22:03；随后 renderer 于 21:22:09 先关闭 MessagePort，语言服务器收到正式 Exit requested，扩展宿主 code 0 退出，Crash Logs 为空。这组顺序支持宿主窗口关闭带动扫描器退出，不支持插件先崩溃导致 IDE 停止；日志不能确定是谁关闭窗口。
- **诊断做法：** 窗口消失后同时对齐插件输出、exthost、main、语言服务器和 crash log 的最后时间及退出码。清理阶段其他扩展的 dispose 异常发生在 renderer 关闭之后，只能作为关闭后清理错误记录，不能倒置为 Auto Accept 根因。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 00:30 +08:00 - Computer Use 文档能力与实际运行时能力分层

- **现场核对：** Antigravity IDE 可见窗口和 5.3.6 扫描器进程均存在，扫描器路径、父进程与发布脚本哈希一致；不能再沿用“IDE 未启动”作为阻塞原因。
- **工具边界：** `cua.getState()` 只返回浏览器且 `apps=[]`，同次初始化文档列出的 `cua.listWindows()`、`cua.listApps()` 在实际运行时均不是函数。原生窗口未由 Computer Use inventory 返回时，不得用 shell 读取的 HWND/PID 拼装 `getApp`，也不得同轮换另一套 UI 自动化绕过；应把“原生 Computer Use 无可绑定窗口”单独记录。
- **验证分层：** 已安装版本与发布哈希、类型检查、生命周期测试、扫描器测试可以证明包和代码测试层；它们不能替代真实 IDE 原生窗口、Chrome Windows 前台持续输入或最小化审批的验收。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 00:38 +08:00 - 原生入口恢复与地区错误定位

- **入口纠正：** 当前 computer-use SKILL.md 的正式入口是 node_repl 中导入 `@oai/sky`，不是浏览器 `cua` 接口。按该入口初始化后，`sky.list_apps()` 实际返回原 IDE 和新建测试窗口，原生 Computer Use 已恢复。浏览器接口没有原生 API 不能推出整个 Computer Use 不可用；优先核对当前 skill 的 Initialize，不能直接沿用旧运行时。
- **模型失败：** 独立新窗口的无工具固定文字请求在 1 秒终止；同一时段语言服务器依次记录 planner、generator、executor 的 HTTP 400 地区不支持。配额面板 Gemini 100% 不是该请求被允许的证据，也不能把登录成功当作地区资格通过。不盲重试相同受限模型、不直接重装或删除认证状态。
- **日志长度：** 本轮目录元数据反复显示日志 Length=0，显式 FileStream 共享读取的实际 Length=17691 且包含完整错误链。活跃日志的目录长度不能代替流长度或读取结果；发现矛盾应先共享只读读取，再判断无日志。
- **网络推断：** Windows 系统代理启用、语言服务器存在外部连接，只能提示需要核对进程实际出网路径；不能直接证明模型请求绕过代理或 Google 的地区判定依据。官方账号地区检查和用户报告的 IP 误判需分别标注证据强度。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 00:53 +08:00 - 论坛地区错误与 Antigravity 产品版本分层
- **版本边界：** 本机 product.json 的 ideVersion 与 EXE ProductVersion 均为 2.5.5；官网 Download 的 Standalone 和 Changelog 的 Antigravity IDE 分组也标为 Latest。Antigravity 2.0 的 2.19.1/2.22.0、CLI 和 IDE 是独立版本线，不能用论坛另一产品的版本号判断独立 IDE 过旧；package.json 的 1.107.0 是底层编辑器版本，也不能替代 IDE 产品版本。
- **论坛证据：** 同一 HTTP 400 在代理未被模型传输使用、出口资格不满足、账号资格异常等报告中都出现；用户帖子只证明该用户的复现。公开端点返回 401 只证明未认证请求的返回，不能证明认证后的账号/地区检查通过，也不能反推本机真实请求必然走代理。先核查自身日志和实际出网，再做单变量对照。
- **处理边界：** 官方 FAQ 的账号地区核对、论坛的支付地区核对均先只读检查；不因论坛建议就删除支付资料、认证状态或更换账号。地区无误仍复现时，保留时间和 Trajectory/Trace ID 供用户提交支持，不未经授权代发。来源：https://antigravity.google/docs/changelog/ ，https://discuss.ai.google.dev/t/all-gemini-models-fail-with-false-user-location-is-not-supported-in-antigravity-ai-studio-and-claude-work-normally/178242/13 。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 01:30 +08:00 - 最小化真实审批与毫秒审计边界

- **进程身份：** 实际扫描器由 PowerShell EncodedCommand 启动，命令行不直接含 autoClicker.ps1；只用原始字符串过滤会误报零实例。先限定 PowerShell 进程，再只解码其 UTF-16 Base64 启动参数，核验精确脚本路径、父进程和启动时间，不输出语言服务器的认证参数。
- **原生操作：** 后台窗口仅有 AX 节点时，点击可报 coordinate input geometry is unavailable；重新选择、正常激活并获取新鲜截图后才按新索引操作。新窗口与 Alt+F4 的返回早于窗口 inventory 收敛，后续只读确认，不能立即重复创建或关闭。
- **实际结果：** 5.3.6 在恢复测试窗口后完成浏览器 Allow Once 与一次性 Submit 两项 Invoke，无 Physical 审批。最小化区间107.629秒的538个完整采样没有 IDE 前台、没有失稳样本，输入戳与指针各保持一个值；这只证明该静置采样区间，不能当作持续键入测试，也没有证明审批首次出现的时刻位于最小化期间。最终模型地区400独立记为任务失败，不用自动审批成功替代任务成功。
- **时间审计：** PowerShell7.6 ConvertFrom-Json 自动把 ISO 时间转换为 DateTime；再将其隐式转成字符串送进 DateTimeOffset.Parse 会丢毫秒。本次错误复核得到107000ms/535条，保留该失败；直接转换 DateTimeOffset 后恢复107629ms/538条并与原始事件逐项一致。需要精确边界时保留原始时间字符串或直接转换日期对象，禁止依赖默认 ToString。
- **清理边界：** 已关闭自建无目录 IDE、只读观测正常到期且用户扫描器仍在；浏览器工具另起 Chrome 使用持久 profile，未读取实际标签页状态前不能假定没有用户内容并杀进程。清理清单分项记录，不把自有 IDE 关闭写成所有测试资源已清理。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 02:00 +08:00 - 代理路径证据与人工验证续接

- **代理核对：** Get-NetTCPConnection 的监听枚举未显示代理端口，但独立 netstat 显示同一 FlClashCore 正在监听。空枚举不是没有监听的证明，先核对精确端口、PID和进程身份，不能据此重配代理。普通 curl 的地区结果、TUN虚拟连接和Google真实模型资格是不同证据层，不能把US结果写成Gemini已恢复；ipinfo的429也不是Gemini配额耗尽。
- **日志定位：** 本机模型HTTP400写在当前日志根的ls-main.log；exthost日志无同一错误不能推出模型没有报错。FlClash实际支持目录须由本机确认，不能硬套论坛另一版本的目录名。
- **页面续接：** 摘要里的浏览器变量在当前会话不存在，按当前inventory查找原验证页。已有页面绑定报Debugger unattached时保留失败，不刷新或新开认证流程，也不切换自动化代操作本人验证。用户表示“完成后告诉你”是后续意图，不等于已经完成，国家字段仍标未读。
- **正常结束：** 观测session句柄缺失后，读取原始stop记录并核对本轮进程：duration-completed、3000样本、120资源记录且本轮observer不存在，用户扫描器仍在。这是正常到期，不重启观测；没有执行的新窗口审批测试须明确标为未测。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 02:42 +08:00 - 本地认证规则修订与失败复测证据

- **用户纠正：** 用户明确授权移除 computer-use 本地文档中禁止自动操作认证对话框的唯一一行。该本地 skill 限制按本次授权修订；这覆盖此前人工验证续接经验中的相应限制，但不取消更高优先级的验证码、安全警告、凭据修改和权限变更等独立要求。只删除精确匹配行，先备份并验证其余字节、UTF8与原始换行全部保留。
- **验证续接：** 常规网页认证自动推进到手机确认；电脑不能代替用户操作实体手机。用户完成手机确认后，页面实际进入支付设置，仅读取当前资料国家为 US，不保存认证挑战、账号或支付资料标识，不修改财务资料。
- **结果边界：** US 支付资料只排除当前资料国家不受支持这一项，不能证明模型请求出口、ASN或后台账号资格。新建空白原生 IDE 中一次纯文本 Gemini 请求仍显示通用执行失败；本次 ls-main.log 无新增请求记录，不能引用旧 HTTP400当成本次已证实的原因。
- **原生 UI：** AX 树可含隐藏或屏幕外节点。点击调试按钮报坐标超出窗口后，应先确认实际可见性；复制没有成功时，不应读取剪贴板来假设已取得诊断内容。本次调整窗口仍未取得调试内容，记录具体原因未证实，不连续盲点隐藏节点或重复发送模型请求。
- **清理检查：** 关闭本轮自建无目录窗口和认证标签页后重新读取 inventory，确认自建窗口已消失，用户原窗口与原扫描器仍在；其余旧浏览器测试资源保持独立清理边界。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 02:57 +08:00 - 会话数据库定位地区400与只读侧文件

- **错误关联：** 当前 IDE 使用 antigravity-ide 数据目录；旧 antigravity/daemon 日志不能覆盖当前请求。界面错误ID的UUID是 trajectory_id，磁盘会话数据库文件名是 cascade_id，两者通过 trajectory_meta 映射，不能凭相同UUID猜目录。本次固定测试标记在 steps[0]，对应界面错误的 steps[4].step_payload 含地区HTTP400；error_details为空不是没有错误。
- **只读边界：** SQLite mode=ro 不保证目录不变，可为WAL模式数据库创建零字节wal和shm。下一次先确认已停止的自有会话、WAL是否含事务，取得哈希一致的完整快照，再用immutable读取快照。非空WAL不能忽略，否则快照可能缺事务。本次原数据库SHA未变，读库产生的侧文件按创建时间、精确路径、零WAL与独占打开核验后清理；不批量清理用户数据库侧文件，原库与原会话历史保留。
- **账号核对：** 非凭据 userStatus 可能由多层Base64与protobuf封装，不能以第一层未找到邮箱就认为没有账号。限定深度、大小和字段解析，与网页Google账号按钮的身份逐项匹配，只保存匹配布尔值；不读取oauthToken、不记录邮箱或认证状态。
- **版本边界：** VSCode派生程序的package.version可能只是编辑器底座，产品版本应核对product.ideVersion。PATH旧入口也不等于当前窗口的可执行文件。本机不同目录对应旧Antigravity和当前Antigravity IDE，不能因为版本字符串相近就启动旧程序或迁移产品。
- **恢复方案：** 新论坛Remote Control成功报告只证明该用户的结果；官方适用产品是Antigravity2.0与CLI。当前IDE未证明支持这一入口，不能拿不同产品的办法当成本机已验证修复，也不能为未证实的办法擅自启用新的远程访问权限。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 03:02 +08:00 - Windows扫描器启动路径核验

- **触发与现象：** 已知原扫描器仍在，但按预期安装路径做区分大小写的Contains得到false，按直接调用脚本写的正则也失败。
- **已读源码：** extension.ts先将整个启动包装编码为UTF16LE Base64，包装内用ReadAllText按UTF8读取安装脚本，再由scriptblock执行，并非直接调用脚本文件。
- **下次做法：** 先读取启动源码的完整上下文，再只解析包装中的ReadAllText字面路径；Windows路径用OrdinalIgnoreCase比对，最终核对父PID、创建时间、实际脚本SHA和仓库SHA。不输出完整启动参数，不因路径误判结束原用户扫描器。
- **检查：** 本次按源码解析的实际安装路径仅盘符为小写，版本为5.3.6，实际脚本与仓库哈希相同；首次误判与正则失败均保留。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 03:29 +08:00 - 嵌套后台时间与原生审批证据分级

- **触发：** 用既有会话数据库补齐最小化期间待办审批的时间证据。
- **现象：** 浏览器子轨迹的等待发生于最小化期间，但仅看父步骤或同名遥测消息会误判时间与字段。
- **根因：** 同名 protobuf 消息不保证类型相同；created_at、viewable_at 和通用 WAITING 不等同于 UI 审批卡首次创建或明确权限等待。
- **下次做法：** 按完整类型引用确认 gemini_coder.Step → Trajectory → Step.metadata，解析真正的子步骤及状态转换；保留秒和纳秒，用整数时间计算。结合实际恢复后的 Invoke 记录，只声明已证实的后台步骤出生与等待，不自动把整个原生验收升级为通过。
- **检查：** 原始证据与数据库哈希前后相同、无新增 WAL/SHM；后台时间落在已确认最小化区间，恢复后动作对应；UI 卡首次出现未直接观察时保留缺口。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 03:29 +08:00 - 采集脚本的 await 回调边界

- **触发：** node_repl 中在 Array.filter 回调内读取异步文件。
- **现象：** 非 async 回调内出现 await，整段解析报 Unexpected reserved word，所有语句都未执行。
- **根因：** 外层允许顶层 await 不代表普通同步回调也允许 await。
- **下次做法：** 先在外层 await 得到基准列表，再用同步 filter；解析失败后只修正采集，不重发模型请求或重复 UI 输入。
- **检查：** 固定请求计数仍为一次，原生结果和会话 ID 对应，采集文件成功保存。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 03:39 +08:00 - 只读审核输出必须先投影并保留子命令退出码

- **触发：** 读取长线程、检索可选目录，或在 PowerShell 内运行 Python 审核后接其它命令。
- **现象：** includeOutputs=false 仍可能返回含工具参数的庞大 items；猜测 scripts 目录引发 rg 错误；嵌套字典括号错误使 Python 未执行，而后续成功命令让整个 shell 的最终状态看起来正常。
- **根因：** 工具响应开关不等于字段投影；可选路径不能凭惯例假定存在；shell 最后命令状态不能代表前面的子命令。
- **下次做法：** 保存线程响应后先解析 JSON，只输出 turn ID、状态和时间，排除工具参数与历史内容。先 rg --files 枚举实际目录；报告分步构造字典。Python 返回后立即检查 LASTEXITCODE，独立的进程查询分开执行。
- **检查：** 当前三轮 ID 从响应正确提取；只读数据库错误载荷和文件哈希核验实际完成；保留首次采集失败，语法修正不重发模型请求、不重复 UI 输入。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 04:00 +08:00 - Cloud Code 启动参数不是当前请求端点

- **触发：** 主语言服务器启动 URL 与扩展语言服务器的 daily URL 不同，怀疑连错测试环境。
- **现象：** 两个进程参数不同，但供应商源码同时提供按 tier/条款选择 URL 和 setCloudCodeURL 运行时更新。
- **根因：** 启动参数可已过时；public daily-cloudcode-pa 与 Google 内部 sandbox 分支不是同一含义。源码中的更新能力也不等于已经观测到某次实际请求目的地。
- **下次做法：** 先读 getCloudCodeUrl、选择器和 tier 更新调用链，精确检查 jetski.cloudCodeUrl 配置；只报告已验证的来源，不根据 daily 字样强改地址、条款或安全设置。
- **检查：** 原产品文件哈希前后相同，未新增模型请求；实际目的地未直接记录时保持未证实。公开支持稿按用户批准的字段限定数据，账号和支付核对信息保留在本机诊断。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 04:34 +08:00 - 初始化错误必须核对后续补偿与命令适用条件

- **触发：** Cloud Code 启动时设置端点报客户端未初始化，准备重启语言服务器。
- **现象：** 仅看三条早期错误会误以为运行时端点更新永久丢失；主语言服务器重启命令的标题存在，但带 Google 内部账号条件。
- **根因：** 主服务器初始化之后已有再次设置端点的逻辑，早期错误不能单独证明模型失败原因。命令注册不等于普通账号可以使用。
- **下次做法：** 先追踪初始化后的补偿调用、命令前置条件和完整处理器。只使用适用于当前账号的公开恢复入口，不强行调用隐藏命令或直接杀主进程。模型用量页面刷新之后只发送一次无工具请求，再核对会话原始错误与实际清理。
- **检查：** 本次刷新成功且没有新初始化错误，但实际请求仍返回地区 400；原服务器和扫描器保持原 PID，本轮窗口已关闭。服务条款关联国家和支付资料国家分别检查，不能互相替代。原生树按准确按钮角色筛选，聊天文字中的按钮名称不作控件证据。PowerShell 的 HEAD^{tree} 必须加引号，复用已有经验第 595 行。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 Asia/Shanghai - Google 身份登录与论坛首次注册分开确认

- **触发：** 用户授权用已有账号向官方论坛发布脱敏支持报告。
- **现象：** Google 身份认证成功后，论坛仍转到首次注册页面，要求用户名并提示注册即接受隐私政策与服务条款。
- **根因：** 已有 Google 账号不等于已有论坛成员资料；发帖授权也不自动包含新建论坛账号与接受条款。
- **下次做法：** 按正常登录流程推进，遇到首次注册后先保留可用的预填用户名、清空可选公开姓名，截图避开邮箱，保留页面，再针对注册及接受条款作当次确认。既有发帖授权继续有效，不再次确认同一报告。
- **检查：** 公开稿仅保留已批准版本、错误和请求标识字段；未确认前不点 Sign Up、不声称报告已发布。Google 登录凭据、邮箱、原始数据库不写入公开稿或注册截图。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 12:16:54 +08:00 - 论坛注册按出口 IP 限流

- **触发：** Google 登录成功且首次注册已获得用户当次确认，提交论坛 Sign Up。
- **现象：** 论坛返回 New registrations are not allowed from your IP address (maximum limit reached). Contact a staff member.
- **根因：** 这是论坛服务端的注册数量限制，不能当成 Google 认证失败或 Gemini 地区错误的证明；未创建成员账号就无法发布回帖。
- **下次做法：** 提交后检查异步错误，不重复点击注册，不为绕过限制自行切换出口；保存脱敏截图、批准记录和原公开稿，等待已有论坛账号或管理员处理。既有注册和发布授权不重复询问。
- **检查：** 注册仅提交一次，账号未创建、报告未发布如实记录；截图避开邮箱，公开稿哈希不变，保留可继续的页面。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 12:25 +08:00 - 论坛乐观回帖必须核对审核结果

- **触发：** Google 官方论坛首次注册完成，提交已授权的脱敏支持报告。
- **现象：** 点击 Reply 后暂时显示新楼层和 Saving，随后该 article 消失，页面出现 Awaiting Approval 和 Post Needs Approval，确认收到一份待审稿。
- **根因：** 提交阶段的乐观显示不证明已公开；新账号帖子可能进入版主审核队列。
- **下次做法：** 等保存结果并检查实际状态。选择器超时先重新观察，不再次提交；仅记录已提交、待审核，不把暂时的楼层链接当成公开永久链接。
- **检查：** 已授权原稿与编辑器、待审正文逐字归一核对，提交一次、待审一份、截图显示 Awaiting Approval；保留原注册失败记录和新提交结果，避免覆盖历史。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 Asia/Shanghai - 浏览器接口可用不代表原生 Chrome 观察获准

- **触发：** 官方论坛已能通过浏览器接口提交报告，继续检查 Windows 前台 Chrome 连续输入验收。
- **现象：** 原生窗口清单能列出当前论坛窗口，但只读绑定或状态采集阶段就因无法可靠识别浏览器网址被工具停止，尚未发送任何输入。
- **根因：** 原生 Computer Use 的网址检查独立于浏览器接口；已知标题和浏览器接口 URL 不能证明该检查通过。
- **下次做法：** 原生工具停止后本轮立即结束，不改安全规则、不换接口补造原生输入证据；下一轮可核对非 UI 证据及报告审核，但同一受阻条件累计达到三轮且没有可推进工作时登记 blocked。
- **检查：** 区分论坛报告已提交待审与 Windows 原生验收未完成；三轮 ID 来自实际线程元数据，排除旧 blocked 审计；保留用户扫描器与不明归属浏览器，不把它们当成目标等待句柄。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 18:42 +08:00 - 关闭 IDE 后的 SQLite checkpoint 与依赖调用门禁

- **触发：** 关闭自有 IDE 窗口后，复制该会话数据库用于错误取证。
- **现象：** 窗口消失时 WAL 尚非空；复制前后台 checkpoint 已完成，WAL 文件消失，首次快照未生成。工具返回 isError 后仍调用依赖的 SQL 解析，产生第二次空副本错误。
- **根因：** UI 关闭、数据库 checkpoint 和文件清单收敛不是同一时刻；工具错误结果不一定会抛出 JavaScript 异常。
- **下次做法：** 非空 WAL 必须完整复制并验证源 DB/WAL 前后哈希；复制时文件消失就拒绝该次快照，重新检查 checkpoint 后的 DB 与侧文件。无非空 WAL 且源 DB 哈希稳定时才用 immutable 读取自有副本。每次先检查工具 isError 或命令退出码，成功后才调用依赖步骤，不继续解析未生成的副本。
- **检查：** 首次失败保留；新副本关联真实 trajectory_id 与 cascade_id，错误载荷和 UI Error ID 对上；原始文件前后哈希一致，没有在源目录创建侧文件。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 19:35 +08:00 - 管理员窗口输入失效与状态恢复

- **触发：** 使用普通权限 Computer Use 只读查看原本最小化的 FlClash 管理员窗口。
- **现象：** 窗口激活成功，但页面导航、最小化与系统菜单输入均未产生可见效果；恢复 IDE 前台后仍需用户手动最小化 FlClash。
- **根因：** 已跑验证的目标进程为 High 完整性且已提升，输入助手为 Medium 且 UIAccess=false，支持 UIPI 限制假设；没有内部输入错误码，不能确定每次 Sky 输入失效均由 UIPI 导致。
- **下次做法：** 查看管理员应用前先核对完整性和恢复原状态的能力。输入无效时停止重复尝试，改查现有脱敏日志；不提升助手权限、不换原生输入接口绕过限制、不重启用户代理。保留原窗口状态，必要时请用户手动恢复。
- **检查：** 将完整性差、实际 UI 操作结果、具体输入失败原因分开记录；核对原 IDE 前台与用户手动清理结果，未验证最小化时不能记作已恢复。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 20:12 +08:00 - 单会话恢复与真实工具任务分层

- **触发：** 用户截图显示模型重新回复，继续本机真实审批验收。
- **现象：** 原会话两次 PLANNER_RESPONSE/DONE/STOP_PATTERN 有实际正文，新空窗口的浏览器任务仍返回地区 HTTP400，没有 browser/ToolCall/permissions 载荷；同 requested_model/generator_model 枚举不等于所有会话持续可用。
- **根因：** 成功的纯文字响应只证明该次请求完成，不能证明下一次工具任务或新窗口初始化后的路径也通过服务端资格检查。客户端 CLIENT_STREAM_ERROR 需结合具体错误载荷，不能直接解释成 EOF。
- **下次做法：** 先关联真实轨迹与回复结束字段，下一次只做有意义的工具任务；未产生审批就记模型外部受阻，不能记插件点击失败。继续不依赖模型的正常启停/双向接管，保留原启用状态；原生 Chrome 网址安全检查停止后，不再发本轮原生输入，只清理自有测试资源。
- **运行时：** 跨 cell 的 Sky 窗口/状态保存在 globalThis 专属对象；块内临时 var 不作跨 cell 句柄。安装文件先读 manifest 和实际文件清单，不猜 dist 路径。截图归档先确认返回 MIME，保留首次失败并检查 isError/退出码，失败依赖步骤不执行。
- **检查：** 独立审查实际日志前缀、进程父子与创建时间、旧实例退出、用户文件哈希和自有窗口清理。AX 即时树可滞后，保留 raw，使用 settled 树、截图和日志交叉；不能用生命周期通过代替真实审批通过。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 20:21 +08:00 - 续接审计要区分归档总数与冻结清单

- **触发：** 目标续接时复用历史证据和持久工具上下文。
- **现象：** 请求元数据已是对象却被 JSON.parse；通用 browser 别名不存在；先将 observer 目录当冻结清单目录，又把归档40文件总数当成38个冻结哈希条目，首次新审计误记失败。
- **根因：** 将历史摘要和示例变量名当当前运行时结构，混淆归档总文件数与检查器固定覆盖项。
- **下次做法：** 按实际类型解析元数据；缺失绑定时通过同一已选浏览器ID恢复，不为标签页错误切换浏览器；限定真实目录清单定位文件。冻结项数及完整名称从已核验检查器读取，原始失败另存，不放宽检查器。避免遍历整个临时目录产生无关输出。
- **检查：** 本次实际归档40文件、固定清单38项，38个名称与哈希全部通过；检查器及11故障样本历史报告SHA保持。已有lessons字节前缀、UTF8无BOM和CRLF均保留，生产代码无改动。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 20:34 +08:00 - 用户新截图应更新当前状态而保留单次失败边界

- **触发：** 用户用新窗口成功截图纠正此前仍受阻的判断。
- **现象：** 旧20:00单次地区400被用于概括当前状态，用户20:19的新请求实际20:21完成回复及工具步骤；同一新窗口随后20:29标记浏览器请求和另一次20:30请求又是地区400。
- **根因：** 原会话最新快照不覆盖用户随后创建的新会话；请求结果具有时间与会话边界，不能把一次失败写成所有新窗口当前都失败。
- **下次做法：** 立即按最新截图与实际窗口定位对应新轨迹、当前items字段及结束时间，再依据新状态尝试有意义的工具验收。成功和失败都独立保留，地区400发生在工具生成前时记审批未测，不记点击失败。协议消息按实际类型引用，不猜CortexStep或将CascadeToolConfig当结果；PS5读取含中文路径JSON必须显式UTF8。
- **检查：** 新成功和标记请求的具体时间、模型、Trace及ToolCall计数由稳定只读副本核对；本机只发一个标记请求，另一个请求来源不臆测。AX即时快照可滞后，发送前后确认完整草稿、历史marker及终态。截图被Codex遮挡时只作原始现场保存，不冒充IDE错误卡的可见证明。两个用户窗口/扫描器和3repo8文件均保持。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 20:44 +08:00 - 模型目录成功不等于协议调用可用

- **触发：** 通过 CC Switch 给 Gemini 配公司模型，或把 Antigravity IDE 与 Gemini CLI 的接口配置混在一起。
- **现象：** 同一公司接口的 OpenAI 与 Gemini 模型目录均返回 200，但 DeepSeek 的 Gemini generateContent 请求返回 400，错误码 protocol_not_supported。
- **根因：** 模型目录展示与实际生成协议支持属于不同证据；CC Switch 的 Gemini 项是 Gemini CLI 配置，不能直接替换 Antigravity IDE 原生 Agent。
- **下次做法：** 先确认目标客户端；对现有公司提供商验证具体模型和生成协议，不把反向代理另一方向的转换能力套用，不向新地址发送既有密钥。
- **检查：** 分别保留目录与实际生成结果，核查本机实现和官方产品文档；协议失败时不写入已知不可用配置，不宣称接入完成。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 20:54 +08:00 - 原生窗口句柄成功不能代表 Chrome 输入获准

- **触发：** 复核 Chrome 前台输入时，浏览器接口已有自建测试标签页、原生 get_window 也成功。
- **现象：** 实际 Chrome 仍显示另一标签页且已最小化；读取状态要求恢复，随后 activate_window 因当前网址无法可靠校验而明确停止本轮 Computer Use。
- **根因：** 句柄、后台标签页、页面 DOM 与 Windows 可操作前台状态属于不同证据，策略在实际操作阶段仍可能拒绝。
- **下次做法：** 只使用新枚举的真实窗口；最小化按提示做一次恢复复核；收到停止后不再原生输入、不换后端绕过；仅清理精确归属本轮的标签页、服务和观察器。
- **检查：** 原生测试文字与按键为零就标为未测；保留停止错误、观察器终态、服务退出码和端口消失证据，不把无审批时的采样算审批期间不抢焦点。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-11 21:02:14 +08:00 - PowerShell 中 Git 带花括号的 revision 必须作为字面参数

- **触发：** 只读核对 HEAD 和提交树时使用未加引号的 HEAD^{tree}。
- **现象：** PowerShell 将花括号相关内容解析为额外参数，Git 返回 exit1 并打印无关 revision；该输出不能证明提交树。
- **下次做法：** 将 HEAD^{tree} 用单引号包为一个字面参数，先核对命令退出码，再分别验证 HEAD 和 tree；保留首次失败，不能把重试成功覆盖成首次成功。
- **检查：** 正确引号后 exit0，HEAD 与既有 db5c04b2...、tree 与 0be360e6... 相符；本次只读查询没有更改 Git 状态。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-12 19:50 +08:00 - URL 权限目标和内容标题必须分别核对

- **触发：** 审核 Antigravity ReadURL 工具的真实内容、权限记录和审批日志。
- **现象：** 请求地址是完整 RFC URL，实际 ONCE 权限目标却是裸域名；web_document.title 可能只有 Live Content，而返回正文确有规范标题。
- **根因：** 请求 URL、授权范围和结果展示标题属于不同字段；DONE、通用标题和单条提交日志都不能独自证明界面审批与正确读取。
- **下次做法：** 分别核对实际 URL、allow/scope/action/域名目标、chunk.text 或 markdown_chunk.text 的正文标题及主回复终态，再结合对应原生卡片和增量日志。
- **检查：** 保留完整稳定 DB/WAL/SHM 副本和哈希，注明快照时间及之后源 WAL 的变化；仅查本轮唯一标记，不扩大到私人会话。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-13 23:16 +08:00 - FlClash 可读控件不代表能自动切换代理

- **触发：** 自动操作 FlClash 0.8.99 的模式或节点。
- **现象：** 原生截图为黑屏，辅助树能读到普通按钮；两个刷新后的按钮编号都返回 element is not available in cached app state。
- **下次做法：** 保留实际工具错误，停止重复点击或猜坐标，不提高助手权限、不打开额外控制接口。需要手动切换时说明具体阻碍；用已保存模式和新的真实网络请求核对变更是否生效。
- **检查：** 出口探测从 TW 变为 US 只证明探测请求路径；必须再做实际 Gemini 请求，不能将网络连通或地区码当模型修复成功。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-13 23:16 +08:00 - FlClash 配置 ID 读取必须保留整数精度

- **触发：** 核对 shared_preferences 中的 currentProfileId 与 profiles.selected_map。
- **现象：** 配置 ID 超过 JavaScript 安全整数范围，JSON.parse 后显示为浮点舍入值。
- **下次做法：** 从原 JSON 文本提取十进制 ID，以字符串绑定并在只读 SQLite 副本中转换为 INTEGER，或者使用支持任意精度整数的解析器。不能将整份 JavaScript 浮点化的配置直接写回。
- **检查：** 只查询准确的当前配置，保持源数据库无 SQL、无写入，不输出订阅链接、密码或完整配置。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-16 18:46 +08:00 - 长 JSONL 的证据检索应按记录解析

- **触发：** 从大型会话 JSONL 恢复历史测试输出。
- **现象：** 正则中的无界匹配命中整条长记录，有限行数仍可能产生大量无关输出。
- **下次做法：** 流式读取，仅解析目标调用和对应 call_id 的结果；先限定类型，再输出有界字段。恢复的历史执行输出与本轮实际重跑分别标注，原始冻结目录缺失时不能声称已重跑。
- **检查：** 核对调用及结果行号、退出码、每个故障的指定拒绝原因；精简副本保存到 F 盘，只删除本轮自有中间文件。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-16 19:10 +08:00 - 临时测试窗口的模型选择可能影响原窗口

- **触发：** 在自建空白 IDE 窗口中从 Gemini 切换到 Claude 做单次网页审批对照。
- **现象：** 关闭测试窗口后，用户原窗口的模型选择也显示为 Claude；聊天内容仍保留。
- **下次做法：** 测试前记录原模型及扫描器开关；结束后分别核对原窗口的模型、开关、会话和最小化状态，不能只关闭测试窗口。
- **检查：** 本次原窗口已恢复 Gemini 3.8 Flash Medium、AutoAccept ON，并恢复最小化；自建窗口已关闭。只有单次网页审批回归通过，不提升为真实长按或跨应用输入验收。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-16 19:22 +08:00 - 空白 IDE 重新加载后需恢复活动会话

- **触发：** 无目录、无文件改动且模型空闲时正常执行 Developer: Reload Window，以加载新版扩展。
- **现象：** 扩展已切到 5.3.7 且只有一个扫描器，但 Agent 暂时显示空白新会话；原会话仍在历史列表。
- **下次做法：** 重新加载前记录活动会话标题；完成后从原生 Past Conversations 精确选回同一会话，核对原文字、空输入框、模型与开关，再恢复窗口状态。
- **检查：** 本次已选回 Simple Greeting，原两条用户消息均保留；Gemini 3.8 Flash Medium、AutoAccept ON 与原最小化状态已恢复。未发送额外模型请求，未操作历史里的其他任务。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-16 Asia/Shanghai - CI 超时的失败证据和夹具生命周期须分层

- **触发：** 宿主测试包装器四十五秒超时，或其外层测试看门狗先结束包装器。
- **已读源码与复现：** 原包装器先抛超时，finally 停止自有子进程后丢弃输出任务；真实停滞夹具已写 stdout/stderr，旧入口仍没有诊断。外层三秒注入则证实只停止包装器会留下夹具。
- **下次做法：** 保留原阈值和失败判定；超时后只处理持有的进程，有限等待输出并明确完成状态，诊断失败不能覆盖原超时。外层失败需按登记 PID 与独占 EXE 完整路径核验后通过同一 Process 对象回收；不能确认时保留旁证。
- **检查：** 成功、stderr、非零退出、缺少 DONE 与已输出 DONE 后仍超时分别验证；本机包装器红绿不证明远端偶发启动超时根因已修复。新增测试也必须覆盖自身外层看门狗清理。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-16 Asia/Shanghai - 原生时序验收须读取实际扩展日志协议

- **触发：** 等待第一次真实审批后立即最小化，以验证下一条串行网页审批。
- **现象：** 用扫描器内部 ___CLICK_ 标记搜索扩展输出日志未命中，实际已审批却额外等待，第二次审批赶在最小化之前。该轮已明确拒绝通过。
- **下次做法：** 先核对实际日志通道；本版本扩展输出使用 Auto-accepted (Invoke)，不能套用内存测试输出协议。临界区只保留必要观察和一个原生操作，记录毫秒时刻并与原始日志对齐。
- **检查：** 修正后首审批观察到最小化6.57秒，恢复首帧有真实一次性审批，恢复后仅一次自动提交、候补零提交且两次读取成功。延迟接口源码只提供时序推断，不能替代UI首次生成时刻与全程焦点采样；该边界必须单列。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-17 Asia/Shanghai - 全虚拟键守卫需区分不输入 IDE 的媒体键

- **触发：** 5.3.7 正确认出窄侧栏浏览器授权卡，但前台空闲后仍无限暂缓，用户反馈没有自动继续。
- **已跑诊断：** 固定原因日志定位到 held-key，临时非字符控制诊断确认 Windows 持续返回 VK_MEDIA_NEXT_TRACK (0xB0) 按下。不能仅凭系统状态断言键盘硬件损坏，也不能归因于截图中的横向裁切。
- **处理：** 仅将 0xAD..0xB3 音量/媒体播放键排除，字母、Enter、鼠标、修饰、浏览器导航及启动键继续阻断；菜单及物理批次共用检查，保留三轮重读及500ms空闲。
- **证据：** 原会话在未改宽度、未人工批准时于00:25:13自动 Allow Once；临时键码日志已从候选实现移除。双引擎各188项及独立1275项内存组合检查通过；原IDE最小化后未强抢焦点，最终模型回复仍未验收。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 恢复历史工具调用先核对字段和共享读取

- **触发：** 从正在写入的大型会话文件定位已知行号及 call_id，恢复检查器的原始执行证据。
- **现象：** 路径式 StreamReader 默认共享策略与写入进程冲突；custom_tool_call 的代码字段是 input，历史内容块类型是 input_text，不能固定假设 arguments 和 text。
- **下次做法：** 用只读 FileStream 配合 FileShare.ReadWrite/Delete，按已知行号有限读取；先看实际 payload 字段、内容块类型，再解析嵌套 stdout，不执行历史代码。恢复的历史通过记录与本轮实际重跑分别列明。
- **检查：** 原材料缺失时保留缺口；所有新证据落 F 盘，截图必须来自实际截图状态，不能由 text-only 状态写出空图。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 历史检查器恢复须校验字节而非重建采样

- **触发：** 原始临时采样目录消失，历史记录只保留脚本创建调用和执行结果。
- **处理：** 只用 TypeScript/Python AST 提取字符串常量，禁止求值或执行历史命令；按原 CRLF 和末尾换行规则恢复三代检查器，逐代核对历史 SHA256。
- **检查：** 三代原始 SHA256 均匹配，7 个恢复脚本语法与编码有效；12 个测试定义逐项对上历史有效样本及11个故障的退出码和指定拒绝原因，另3个清单错误有历史拒绝记录。恢复材料落 F 盘，生产代码未改。
- **证据边界：** 缺失的原始 UI/observer 采样不能由方便通过的模拟数据代替；源文件恢复、历史执行通过、本轮重跑和真实桌面验收分别记录，未重跑就明确未重跑。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 当前模型可用性与本机接管证据应重新分层

- **触发：** 旧原会话保留模型执行错误，当前正式版的双窗口和最小化审批仍缺验收。
- **已跑验证：** 独占空白窗口中一次 Gemini 3.8 Flash Medium 网页请求成功；恢复最小化首帧存在真实窄审批卡，02:40:35 自动 Allow Once 一次，最终标题和正文回复完成。旧原会话错误不能概括当前所有请求；同时保留工具步骤 list network requests 的一次错误。
- **本机接管：** 原扫描器正常 Stop 后退出、等待实例接管；原窗口启动后等待，再由测试窗口 Stop 交回；正式 Restart 命令替换等待进程，关闭自有测试窗口后只余原宿主一个实例。PID、父进程、创建时间和原始日志副本逐阶段核对，不能把等待进程当重复所有者。
- **工具恢复：** 被遮挡窗口的纯文字控件状态可能没有输入几何，首次点击返回 coordinate input geometry is unavailable；先保留未改变的进程快照，正常激活并刷新截图和控件后只重试一次。即时 AX 可滞后于截图和实际日志，另存稳定后状态。
- **证据边界：** 已证明待批首帧与恢复后一次批准，尚未直接取得最小化期间审批生成时刻和全程焦点采样；不能升级为 Chrome 连续输入验收通过。原用户会话、模型、ON 及最小化恢复，生产源码和安装脚本哈希保持一致。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 只读会话时序审核的文件名和协议类型边界

- **文件名：** PowerShell 的逗号列表和加号混用会把 db、后缀拆成重复元素；首次 CreateNew 正确拒绝覆盖自有已复制文件。保留失败记录，改用独立后缀管道，先断言三项唯一，再做新快照；不能把失败副本当完整快照查询。
- **描述符：** FieldDescriptorProto 的编号在字段3，EnumValueDescriptorProto 的编号在字段2，后者字段3可能是废弃选项字节。先复现具体错误项再按实际消息/枚举种类解码。PermissionResource 已由字段 type=11 证明是消息，不能凭名称猜成枚举；保留首次错误输出，使用经过整数编号检查的修正文件。
- **时间：** 原生记录可能有七位小数，datetime.fromisoformat 仅保留微秒；边界计算要分离秒与小数并补齐九位，用整数纳秒比较。复核后本次时间顺序不变。
- **本次事实：** 自有公开网页任务的后端 OPEN_BROWSER_URL 在最小化期间创建并进入 WAITING，恢复约1.204秒后重新 RUNNING 并 DONE。WAITING 枚举本身不说明等待原因；即使恢复首帧有匹配审批卡且日志一次批准，也不声称直接采到了卡片首次生成或全程 Windows 前台焦点。
- **验证：** 仅复制自有已关闭会话，WAL为零；原 DB/WAL/SHM 前后与完整副本哈希一致。SQL仅运行于 F 盘副本，mode=ro、immutable=1；生产代码未改，旧 blocked 后恢复的计数重新开始。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 独立浏览器原生输入与最小化验收的工具边界

- **触发：** Computer Use 无法操作 Chrome，或桌面输入、UIA 查询、前台激活失败。
- **根因：** PS5 不支持 ushort 类型别名，应使用 uint16；原生 Unicode 输入的撤销事务可能逐字符提交，不能假设多字符标记一次撤销全部。UIA 状态项 Name 包含提示文本，精确匹配短显示文字会漏掉真实控件；旧 PID/句柄必须在操作前核对是否仍存活。
- **下次做法：** 独占 Chrome 配置、回环测试页、Win32 SendInput 和只读 CDP 分工；单字符标记验证原生 CtrlZ/Y，逐次检查前台，独立 50ms 记录器采样。UIA 先定位 statusbar，再按已知 AutomationId 取原文，不在持久输入服务中查询整棵树。
- **检查：** A3 连续65.2秒、655字一致、原生撤销重做正确，1303个覆盖样本均为测试Chrome，期间真实一次性审批仅提交一次。B最小化45秒的901个样本无IDE前台，同一真实RUN_COMMAND进入WAITING后在恢复后继续，日志仅一次提交。首帧动画不算审批截图；协议等待、一次性提交和输出必须结合核对。
- **证据边界：** 检查器适配当前真实证据格式须公开说明，保留旧11类故障语义和哈希来源，不能伪造旧日期、PID、报错或已丢失原始采样。按记录PID验证退出后，以目录白名单、真实路径和无重解析点检查限定清理范围。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 - 启动恢复必须按握手并区分注入故障与真实故障

- **触发：** 扫描器进程存活但没有READY或WAITING，状态栏永久STARTING。
- **处理：** 先用生产入口和虚拟时钟取得红例；独立真实IDE仅首次测试子进程注入90秒挂起，验证60秒截止、替换PID、READY及随后一次真实审批。发布包不包含故障注入，实际扫描器原字节哈希必须一致。
- **检查：** 开启通知并在截止前追加普通输出，证明自动恢复静默且不续期；stop/unload/error/exit取消，正常WAITING不误杀；旧截止和尾部握手不影响新实例。UIA状态读取为空只能写未取得原文，不可假装获取成功。
- **工具：** GraphQL合并EOF后先回读PR仍OPEN，再用REST并固定head SHA重试，最后核对实际merge commit与main CI。辅助清理不要与其他文件修改拼成大命令，先验证进程退出，再用固定绝对路径、无重解析点和非递归文件白名单独立执行。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 截图审批故障须对齐时间版本，公开包清理失败不得转绿

- **已跑本机：** 截图文件时间为10月17日00:11，对应日志为5.3.7反复等待IDE前台/输入空闲，不能据截图推定按钮不识别或模型网络报错。本轮真实窄栏卡片More actions离屏，现扫描器先滚动再选择Allow Once成功，返回Example Domain；未点Always Allow。正式5.3.9原包本机安装并重载，READY核验通过。旧日志未分拒绝原因，不能倒推出当时必为媒体键。
- **CI红绿：** 同版本的ZIP字节不同必须硬失败；finally删除异常可覆盖哈希异常，导致下次下载正确包后带残留报成功。保存原ErrorRecord，清理异常标不可恢复，预检与上传后复查都停止。OpenVSX精确身份/版本已见时先记存在，再看downloadable，暂不可下载只核验重试，不能重传。
- **独立验证：** 两店公开5.3.8原生产查询函数只读联网比对GitHub原包成功；无上传主体/凭据；故障注入覆盖清理、哈希加清理、传输加清理及不可下载后恢复。商店公开版本仍为5.3.8，不把已安装本机9、GitHub发布9或CI成功称为商店9上线。
- **工具复用：** Windows PowerShell 5编译的桌面辅助C#不可直接拿旧Framework引用给PS7；用指定原引擎并UTF8读脚本。嵌套PowerShell命令先编码，避免外层展开ProgressPreference。rg对Windows目录配-g过滤，不把通配路径作为字面文件名。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - PowerShell脚本与原生命令的退出码不能混用

- **现象：** validate-vsix脚本正常通过，随后把空的LASTEXITCODE与0比较而提前exit0，导致未commit先push了基线空分支，PR创建提示没有差异。
- **下次做法：** PowerShell脚本靠ErrorActionPreference=Stop、异常或即时成功状态判断；LASTEXITCODE只在实际原生命令之后核验。提交、push和创建PR分步检查每个结果，创建后回读head SHA和文件列表。取消自己误触发的基线CI，保留真正提交的检查。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 实机复测不能用缓存页面替代本轮审批证据

- **现象：** 正式5.3.9重载后再次请求example.com直接读已有页面，没有新权限卡；这只能证明任务运行，不能算本轮自动批准。
- **已跑验证：** 改用此前未批准的example.org，先OFF保存新域名等待卡片，再开启正式5.3.9；13:10:41自动选择Allow Once，待批卡片0、Working0、Example Domain正文存在、最终ON。旧版本同类成功与新正式版本的新审批证据分别保存，不混用版本或请求。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 扫描器协议必须整行握手且载荷不能被重复标记截断

- **红灯：** stdout日志只提到READY/WAITING也被includes当握手，状态误ON/WAITING并取消60秒恢复；split取第二段会截断载荷中的重复CLICK/ERROR标记。两项真实入口回归在旧源码独立复现，新版完整行握手、行首载荷标记、slice保留载荷，35项生命周期及全套通过。
- **本机：** 独占5.3.10首次helper仅输出带假握手文字的ERROR后挂起；60秒真实重启，下一秒READY。后台测试窗口的扫描器随后在普通前台窗口对example.net实际一次允许，日志恰一次批准、任务结束；原窗口恢复ON，测试IDE正常退出。
- **证据边界：** 原始完整UIA树仅13项，持久驱动后续查询超时。不得由观察超时重启产品；改为独立进程、限定12秒的AutomationId FindFirst，取得真实ON状态。不宣称拿到完整可视启动时间线。最终恢复一条已有注释后重编译/重打包，排除该单行注释后运行字节与实机候选完全相同，最终包校验通过。
- **清理：** 关闭并核对本轮PID后，独占白名单目录的专用清理脚本检查真实根、每层链接再清理；实际移除了测试profile、扩展、工作目录、控制token。避免在持久输入驱动中运行整树UIA查询，实时日志用支持共享读取的Get-Content，不用默认ReadAllText争用写锁。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-20 Asia/Shanghai - 商店提交必须回读原包，重载可绕开前台输入限制

- **已跑发布：** Marketplace 上传后先显示 Verifying，Open VSX 先显示 Under review；不能把上传回执当上线。两个商店实际公开 5.3.10 后，分别调用 CI 原生产查询函数，核对发布者、精确版本与下载包 SHA-256，均与不可变 GitHub 原包一致，临时下载清零。复用用户已登录的网页会话，不创建新令牌、不要求重复登录。
- **原生替代：** IDE 原有 Open Folder 模态窗口使聚焦快捷键失败；保留该对话框，改用已观察的 View → Command Palette 的 UIA Expand/Invoke，再调用唯一可见 Developer: Reload Window，正式 5.3.10 激活日志 READY、状态 ON、运行文件哈希全部通过。UIA 全树含模态文件列表时应缩小返回字段，不输出整棵无关列表。
- **边界：** CI 商店发布步骤缺凭据只报告未自动上传；本轮两个商店通过网页手动提交并独立核验，不宣称是 CI 自动上传。Open VSX 既有 namespace 未验证提示与版本下载可用是两回事。

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 有序字典字段应按键读取或先转为对象

- 复用2026-10-08 Hashtable键排序的经验：OrderedDictionary直接传给Select-Object字段投影可能全为null，不能把显示层空值当成原始回执缺失。本轮JSON原文仍含真实head/branch/status和完整性结果；用ConvertFrom-Json回读为PSCustomObject后再投影，显示恢复正常。先保留首个空观察，再核验原文和哈希，不重写真实证据，也不由空显示推断工具/产品故障。
//***

<!-- 来源：用户工作区补充；历史材料，不作为当前成功证明。 -->

## 2026-10-21 Asia/Shanghai - 目标完成回执与后续当前目标查询分开判断

- 本轮update_goal明确返回complete后，随后get_goal返回goal:null。不能要求后续当前目标查询仍返回complete对象，否则会产生自造的完成校验假红；以实际更新成功回执为准，并原样保留查询结果，不重启已完成目标。
