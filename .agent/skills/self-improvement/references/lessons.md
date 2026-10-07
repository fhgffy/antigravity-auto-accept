# 项目维护经验

## 2026-10-05 Asia/Shanghai - Windows PowerShell 5.1 必须显式读取 UTF-8 规则

- **触发：** 无 BOM 的 UTF-8 扫描脚本增加中文按钮规则后，以 `powershell.exe -File` 启动。
- **现象：** 中文被按 ANSI 解码，测试和真实扫描出现语法错误；不能通过给源码加 BOM 来绕过既有编码约束。
- **根因：** Windows PowerShell 5.1 对无 BOM 文件使用系统代码页。
- **下次做法：** `ReadAllText(path, Encoding.UTF8)` 后创建脚本块，以 UTF-16LE 编码的 `EncodedCommand` 传入引导，安装路径按 PowerShell 单引号字面量转义；标准输出按 UTF-8 解码。
- **检查：** 用实际扩展生成的启动参数运行 SelfTest，并验证中文分段输出。测试入口也要显式 UTF-8，不把 pwsh 单独成功当成 PowerShell 5.1 成功。

## 2026-10-05 Asia/Shanghai - PowerShell 协议输出不能把进度当成错误

- **触发：** PowerShell 引导成功退出，但 stderr 出现 CLIXML 进度记录。
- **根因：** EncodedCommand 在重定向输出时可能序列化初始化进度。
- **下次做法：** 引导设置 `ProgressPreference='SilentlyContinue'` 并传 `-OutputFormat Text`；仍保留真正错误输出。
- **检查：** 实际启动测试要求退出码 0、stdout 含预期协议且 stderr 为空。

## 2026-10-05 Asia/Shanghai - 新权限表单不能按 Run 或 Submit 全局匹配

- **触发：** Antigravity IDE 2.5.5 显示新的工具审批卡片。
- **现象：** `Run Write-Output ANTIGRAVITY_AA_FINAL_V53?` 是工具记录的展开按钮，实际审批使用 `Yes, allow this time` 单选项和 `Submit ↵`。
- **下次做法：** 先读取实际控件树，在 `conversation` 内核对同一卡片的 permission target、一次允许、永久允许和拒绝选项；只选择一次允许，再提交对应卡片。禁止全局匹配 Submit，禁止选择永久允许。
- **检查：** 扫描关闭时审批保持等待；新 VSIX 安装重载后日志明确记录一次审批，终端输出目标标记。普通问答表单不能被提交。

## 2026-10-05 Asia/Shanghai - Computer Use 必须从筛选结果选择窗口

- **触发：** `list_windows` 返回多个应用，输出只展示筛选后的 IDE 窗口。
- **根因：** 显示筛选结果后误用原始数组第一个窗口，会绑定其它应用。
- **下次做法：** 保存筛选结果，要求恰好一个候选，再使用该候选返回的 id/app。发生用户输入、最小化或句柄变化后重新观察，不重用旧控件索引。
- **检查：** 首次状态显示临时测试目录标题和 Antigravity IDE 进程；每次输入后立即刷新核对。

## 2026-10-05 Asia/Shanghai - 单个 PowerShell 管道结果需要显式数组收集

- **触发：** 开发机仅安装系统 PowerShell 5.1，筛选引擎列表后按 `[0]` 选择执行程序。
- **现象：** 单个结果退化为字符串，`[0]` 得到盘符首字符，测试无法启动。
- **下次做法：** 用 `@(...)` 收集完整管道结果；不要使用 OutputEncoding、HOME 等系统变量作为普通任务字符串。
- **检查：** 除默认多引擎测试，还运行仅传 `powershell.exe` 的单引擎回归。

## 2026-10-05 Asia/Shanghai - 完成后的工具记录也不是审批按钮

- **触发：** 真实审批通过后，工具记录标题从 `Run Write-Output ANTIGRAVITY_AA_SMOKE_V53?` 变成 `Run Write-Output ANTIGRAVITY_AA_SMOKE_V53`。
- **现象：** 仅排除问号无法阻止扫描器继续展开历史记录。
- **下次做法：** 执行类按钮限定实际审批静态标签和快捷键后缀，禁止将任意命令正文按 Run 前缀匹配；字面量 `Run command` 仍是旧版静态审批标签，不要误写成已禁用。
- **检查：** 用最终安装包完成固定标记任务后，日志只有对应一次审批提交，没有 Run 工具记录点击。

## 2026-10-06 Asia/Shanghai - 最后一次 UIA 查询后仍需检查宿主存活

- **触发：** 初始父进程检查通过，但后续获取按钮或宿主窗口时父进程退出。
- **现象：** 早期存活检查无法阻止最后一次 Invoke；两名审查者用实际函数桩独立复现。
- **下次做法：** 在现有点击路径中，把父进程存活复核放在选中状态、同卡片和 UIA 查询之后，紧邻 Invoke。保留独立的旧版按钮检查。
- **检查：** 模拟查询期间父退出，旧版和新版 Invoke 都必须为 0；不把这种无点击桩验证写成实机退出测试。

## 2026-10-06 Asia/Shanghai - VSCE 会重写说明书相对链接

- **触发：** 对比工作区 README、VSIX 和已安装文件的原始 SHA-256。
- **现象：** 运行脚本全部一致，但 README 源文与安装包不同。
- **根因：** 打包器把 Markdown 相对链接和图片地址改写为仓库 URL。
- **下次做法：** 运行文件要求三方字节一致；README 检查改写差异并要求 VSIX 与安装文件一致，不把合法链接改写当成旧包。
- **检查：** 显示实际链接差异，并分别记录运行文件和说明书的验证结果。

## 2026-10-06 Asia/Shanghai - 浏览器审批需要核对窄布局折叠菜单

- **触发：** 插件 ON，但 `Agent needs permission to act on github.com` 卡片一直等待。
- **根因：** 命令审批的 Edit/Radio/Submit 结构不适用于浏览器；IDE 源码在窄布局把 `Allow Once` 放入 `More actions` 菜单，菜单项通过 Portal 出现在卡片之外。
- **下次做法：** 先读真实控件树及宿主 UI 定义，按同一浏览器卡片选择本次允许；不能将 `Always Allow` 加入全局字符串规则，也不能从全窗随意选择 MenuItem。
- **检查：** 回归分别覆盖宽布局与窄菜单，并安装新 VSIX 在原待审批任务验证。

## 2026-10-06 Asia/Shanghai - BOM 检查使用字节或 Ordinal 比较

- **触发：** 用默认文化比较的 `StartsWith([char]0xFEFF)` 检查 UTF-8 文件。
- **现象：** 无 BOM 文件也可能被误判；实际首字节为 `23 20 F0`，不是 `EF BB BF`。
- **下次做法：** 检查前三个原始字节，或显式使用 `StringComparison.Ordinal`；严格解码并单独统计 CRLF 和孤立 LF，避免误判后转码。

## 2026-10-06 Asia/Shanghai - IDE 状态命令按字段筛选输出

- **触发：** 用 IDE CLI 的 `--status` 查询进程存活。
- **现象：** 完整输出可能包含子进程参数中的会话凭据及 CSRF 字段，超出了版本和扫描器验证所需信息。
- **下次做法：** 优先查询 `--list-extensions --show-versions` 和插件日志；若确需状态输出，先在内存中按字段白名单或脱敏，再输出，完整原文不进入公开验证资料。

## 2026-10-06 Asia/Shanghai - 新审批作用域必须覆盖旧回退路径

- **触发：** 为浏览器卡片加入精确本次允许分支，但旧全窗口匹配仍接受 `Allow Once`。
- **现象：** 宽栏的普通卡片被新函数拒绝后，旧扫描循环仍可能批准。
- **下次做法：** 让浏览器专用标签仅进入同卡片分支，并用实际扫描尾段覆盖宽栏无上下文、会话外和窄栏菜单；不能只测新增函数。

## 2026-10-06 Asia/Shanghai - AST 回归需要加载真实匹配全局表

- **触发：** 回归从 AST 加载实际匹配函数和扫描尾段，但没有同时读取源码中的目标前缀及排除表。
- **现象：** 空全局表掩盖宽栏 `Allow Once` 的旧回退误批，第一次预期红色的运行实际通过。
- **下次做法：** 从同一份被测源码 AST 加载匹配配置，再执行实际尾段；用隔离旧版副本验证它确实失败，不能将测试文件名称或预期当作证据。

## 2026-10-06 Asia/Shanghai - 安装器会追加清单元数据

- **触发：** 对比 VSIX package.json 与 IDE 已安装 package.json 的字节哈希。
- **现象：** 安装器新增 `__metadata`，清单字节哈希不同；原始清单字段及两个运行文件完全相同。
- **下次做法：** 运行代码按字节 SHA-256 核对；安装清单逐项核对原字段及版本，单独列出安装器追加字段，不把合法安装元数据当成运行文件损坏。

## 2026-10-06 Asia/Shanghai - 结构日志不能抢占错误诊断的节流

- **触发：** 扫描器记录候选卡片形状正确，但后续模式异常或菜单失败没有日志。
- **根因：** 结构日志先消耗共用的十秒节流，随后动作结果日志每次都被压掉；有结构日志不等于执行到 Invoke。
- **下次做法：** 结构和动作结果分别节流，或合并一次输出固定阶段和结果；不输出域名、消息或可能包含用户内容的异常全文。
- **检查：** 模拟连续轮询中的模式异常，结构日志与固定原因诊断都必须可见。

## 2026-10-06 Asia/Shanghai - 离屏保护需要配套当前审批控件滚动

- **触发：** 窄侧栏的 More actions 在横向滚动区之外；同卡片结构正确但 IsOffscreen=True。
- **实机对照：** 仅横向滚动使 IsOffscreen=False，窄菜单仍未完成；仅扩大侧栏后，插件自动调用 Allow Once，原浏览器任务继续。因此不能把一个布局对照当作窄菜单修复完成。
- **下次做法：** 在已核验当前审批卡片内尝试带出控件，重新检查可见性和卡片归属后再操作；继续诊断菜单路径，不能删除离屏保护。

## 2026-10-06 Asia/Shanghai - 下拉按钮的 UIA 模式与普通按钮不同

- **触发：** 同卡片 More actions 可见后仍未展开，宽布局 Allow Once 直接调用却成功。
- **已跑诊断：** 窄按钮实际报告 invoke=False、scrollitem=True、expand=True；普通 InvokePattern 不适用于此下拉控件。
- **下次做法：** 读取实际支持模式，按当前控件使用 ScrollItemPattern 和 ExpandCollapsePattern；在每次副作用前后复核卡片、宿主和可见性，不能仅依赖按钮名称或测试桩默认支持所有模式。
- **检查：** 旧实现对不支持 Invoke 的真实形状必须失败；回归要模拟 Expand 和滚动支持，并最终安装到同一个待审批 IDE 任务实测。

## 2026-10-06 Asia/Shanghai - 宿主查询后复核当前控件状态

- **触发：** 加入滚动和展开路径时，将最终卡片、菜单和菜单项检查放在 Get-TargetProcessIds 之前。
- **已跑复现：** 宿主查询内改变卡片文案或可见性，旧版四例仍调用本次允许；滚动前改变卡片也仍滚动。实机普通任务成功不能排除这些竞态。
- **下次做法：** 移动现有检查为宿主查询、最终卡片及控件状态、最终菜单关联、父存活、实际动作；不叠重复校验。
- **检查：** 四例均零批准；滚前改变卡片零滚动，滚后改变卡片零展开；正常宽窄路径继续通过。

## 2026-10-06 Asia/Shanghai - 新终端审批也会替代聊天输入区

- **触发：** 浏览器已连续自动批准，但 Allow running verification tests? 终端审批一直等待；单选和 Submit 位于 Agent Conversation 之外。
- **已读源码及实机树：** IDE 的专用 ask_permission 组件既可在 conversation 内渲染，也可替代输入框。实际 Radio → radiogroup → Group 两层父链仍是单个表单；同组含 Edit permission target、同前缀本次/持久/拒绝选项、Skip、唯一 Submit。
- **下次做法：** 宿主窗口内发现精确一次选项后核对专用权限表单，不把 conversation 当唯一入口；普通 ask_question 复用 ask-opt ID 但没有 permission target，必须拒绝。
- **滚动边界：** 长命令使持久选项换行，Submit 可在视口外；动作控件需滚到可见并重新验证，最终只读选中项可能因提交按钮滚动离屏。不能删除动作可见性保护，也不能要求两个相距很远的控件始终同时可见。

## 2026-10-06 Asia/Shanghai - 原 Agent 的候选也需要贡献政策和重复修复核查

- **触发：** Agent 选择 Rich #4229 并修改本地代码，但还没有核实仓库 AI_POLICY.md 和作者已有修复。
- **已查公开证据：** Rich 要求披露 AI/agent、完整模板及维护者事先批准；该 issue 没有批准，原作者有同方案 commit 等待回复。
- **下次做法：** 在提交前核查贡献政策、关联 PR 和已有修复；保留工作区，向原 Agent 说明并改选合适目标。没有独立 AI_POLICY 文件不代表没有 AI 要求，仍需查贡献指南和 PR 模板。

## 2026-10-06 Asia/Shanghai - 请求文字不能证明使用了专用权限表单

- **触发：** 在 Agent 提示词中要求通过 ask_permission 执行无害标记，再观察自动审批。
- **已跑验证：** Agent 实际生成了普通 ask_question，只有 Allow and execute / Deny / Other，没有 Edit permission target；插件保持不回答，符合专用权限表单边界。人工选择 Other 解释正常命令流程后才继续，不能把这次标记执行算作自动批准证据。
- **下次做法：** 让 Agent 正常执行需要审批的命令，用实际 UIA 表单结构和插件动作日志验证自动化；提示词、Agent 自述及命令最终输出都不能独立证明审批来源。

## 2026-10-06 Asia/Shanghai - 浏览器上传受阻时保留逐文件选择的人工交接

- **触发：** 浏览器文件上传要求扩展文件网址权限，访问扩展设置页被 URL 策略拒绝；原生浏览器操作也因无法可靠识别网址被停止。
- **下次做法：** 不改用其他接口执行被拒绝的权限设置操作。先打开现有扩展的 Update 入口，向用户交接已验证公开 VSIX 的逐文件选择，接着完成正常上传和页面验证；没有看到选中文件及发布结果时，不声称商店已上架。

## 2026-10-06 Asia/Shanghai - 富文本消息输入区需核对实际子文本

- **触发：** 替换 Antigravity Message input 的提示词后，只校验组合框的 Value 字段。
- **已跑观察：** Value 仍是第一次输入的旧内容，但其文本子节点和当前截图已经显示替换后的正确内容；因此第一次发送前校验误判。该观察只覆盖富文本消息组合框，不能外推到专用权限 target 输入框。
- **下次做法：** 输入后刷新状态，用实际文本子节点和必要的截图核对；当前存在专用权限表单时不点击消息区控件，避免审批表单切换时复用旧索引。

## 2026-10-06 Asia/Shanghai - PR 正文写入后必须读回核对

- **触发：** 原 IDE Agent 内联传递带 Markdown 引号和反引号的 gh pr edit 正文。
- **已跑验证：** Arrow PR #1367 的正文实际只剩 273 字符，验证信息与 AI 披露被截断；改用 UTF-8 body-file 后，读回文本与文件逐字一致。
- **下次做法：** 多行正文始终保存为文件或使用结构化参数；写入后验证完整文本和关键披露，不用命令退出成功代替正文完整性证明。

## 2026-10-06 Asia/Shanghai - 自动审批与代码质量必须分别验证

- **触发：** 原 IDE Agent 修复 Arrow 多粒度日期计算并声明完成，但没有充分覆盖舍入、时区和日历边界。
- **已跑验证：** 独立审查先后复现负亚秒环绕、DST 固定单位双计、月末锚点丢失、零个月运算清除 fold，以及跨时区月边界方向错误。终端自动批准只证明审批自动化，不能证明开源贡献正确。
- **CI 边界：** 原项目 99% 总覆盖率通过后，Codecov 仍可能要求 patch 100%；不可达兜底应按固定单位集合删除，不为其制造无效测试或降低阈值。依赖下载 IncompleteRead 发生在运行测试之前，应与源码测试失败分开诊断。
- **下次做法：** 对最终提交独立审查原行为、真实回归及全部项目门槛，并核对精确 SHA 的 CI；Agent 自述或降低覆盖率门槛的测试输出都不能作为完整交付证据。

## 2026-10-06 Asia/Shanghai - 有效日期转换仍可能超过 datetime 范围

- **已跑验证：** Arrow 的两个有效 year 9999 端点相差 26 小时，新增的无条件 astimezone 转换却需要构造 year 10000，因此连纯天/小时粒度也出现新 OverflowError。
- **下次做法：** 固定粒度跳过日历转换；日历转换溢出时保留原 aware 端点，消费可表示的原月份锚点，再分解精确秒余量。说明不可表示下一月的边界，不把该分解宣称为全日期范围的最大日历单位。补齐双方向固定/日历回归后再封板。

## 2026-10-06 Asia/Shanghai - PR 作者不一定有权限重跑上游 CI

- **已跑验证：** Arrow 最终提交的 27 项检查为 26 成功、1 依赖下载失败；完整 run 结束后执行 gh run rerun --failed，明确被拒绝：Must have admin rights to Repository。贡献者能推自己的 fork，不代表能重跑上游工作流。
- **下次做法：** 保留同一提交的成功测试及实际失败日志，在 PR 正文说明需要维护者重跑环境失败项；不要降低门槛、反复无权限重试或制造空提交。发布 CLI 没有现成发布者/token 时，应交接已验证 VSIX 的逐文件选择，不自动创建凭证。

## 2026-10-07 Asia/Shanghai - 多窗口扫描必须隔离失效节点并轮换成功窗口

- **触发：** 首个 IDE 窗口持续出现审批，或者在枚举后关闭窗口。
- **已跑复现：** 固定顺序三轮扫描首窗获批三次、次窗零次；首窗 UIA 异常让次窗整个轮次得不到扫描。
- **下次做法：** 在窗口和控件边界隔离临时异常，每次成功后让后续窗口优先；用实际扫描尾段与固定计数断言复现，避免只测字符串匹配。

## 2026-10-07 Asia/Shanghai - IDE 产品版本和 CLI 名称分别核对

- **触发：** 假定安装目录中的 CLI 名称是 antigravity.cmd。
- **现象：** 当前 Antigravity IDE 安装实际使用 antigravity-ide.cmd；CLI --version 输出基础编辑器 1.107.0。
- **下次做法：** 先枚举 bin，IDE 兼容版本读取 product.json 的 ideVersion，记录两者，不把基础编辑器版本写成 IDE 产品版本。

## 2026-10-07 Asia/Shanghai - 显式 UTF-8 加载还要保留脚本文件上下文

- **触发：** CI 为 PS5 通过 ScriptBlock.Create(ReadAllText()) 执行测试文件。
- **已跑复现：** 原始引导丢失 PSScriptRoot，测试定位相邻源文件时 Join-Path 失败。
- **下次做法：** Parser.ParseInput 传 UTF-8 正文及绝对文件名，再执行 AST.GetScriptBlock；精确 CI 命令须在 PS5/PS7 分别验证。插值变量后紧跟冒号时使用 ${变量}，避免 PowerShell 将它当作用域语法。

## 2026-10-07 Asia/Shanghai - 动作已发生后抛错也必须消耗扫描冷却

- **已跑复现：** 第一按钮 Invoke 先产生副作用再抛错，后续按钮在同轮约 35ms 内又获调用，虽配置冷却为 1000ms。
- **下次做法：** 只读查询失败可跳过；开始动作后，不论结果是否已知，本轮必须进入冷却且不能物理重试。成功日志与动作尝试分别记录，不以未抛错作为唯一限速入口。

## 2026-10-07 Asia/Shanghai - 进程 exit 与输出 close 分别验证

- **触发：** 子进程 exit 后 stdout/stderr 仍有尾部数据。
- **下次做法：** 保留带退出实例标识的诊断，不能解析旧 READY/WAITING 更新新状态；close 后拒绝旧输出。停止或卸载后不再追加诊断，卸载验证无 child/timer，不要求已释放状态栏刷新。

## 2026-10-07 Asia/Shanghai - 富文本输入不能只信 set_value 成功

- **已跑观察：** Antigravity 消息组合框 set_value 返回后仍空、Send disabled；点击并 type_text 后实际子文本和 Send 状态才更新。
- **下次做法：** 重新观察实际文本子节点；UIA 点击缺少几何信息时先激活目标并重新观察，不复用旧索引。Value 与实际子文本不一致时，以截图及当前子文本核对，不能盲发重复消息。

## 2026-10-07 Asia/Shanghai - UI 点击还要有当前截图几何

- **已跑观察：** 当前 Computer Use 环境仅刷新文本后，索引点击反复报告 geometry unavailable；激活目标并刷新 include_screenshot=true 后，同一可见命令点击成功。同进程多窗口还可能让缓存索引过期。
- **下次做法：** 按目标窗口重新观察，必要时同时获取截图；操作失败后不重复旧索引。浏览器 URL 无法核实时结束该次电脑操作，不换接口执行被拒动作；独立授权的构建、测试及 GitHub CLI 工作继续使用专用工具。
## 2026-10-07 Asia/Shanghai - YAML 解析不等于 Actions 表达式校验

- **已跑复现：** 本地 YAML 和 PowerShell AST 都通过，但 GitHub run 37515131660 在启动 job 之前失败；六个 step.shell 中的 matrix.shell 被远端判为 Unrecognized named-value，未生成任何测试结果。
- **下次做法：** 按 GitHub Contexts reference 的具体键位置检查可用上下文；job.defaults.run 支持 matrix，不能把 workflow 根 defaults.run 或步骤 shell 当作同一规则。工作流变更使用 Actions 表达式校验器，并以新提交在远端实际创建和完成所有 job 作为最终证据。
- **检查：** 没有 runner/job 的配置失败与测试失败分开记录；本地解析成功或旧提交 CI 成功都不能替代这次精确 SHA 的远端结果。

## 2026-10-07 Asia/Shanghai - Actions 运行时与项目 Node 分开维护

- **已跑观察：** checkout/setup-node/upload-artifact v4 的远端 job 成功，但提示 Node 20 Action 运行时已弃用并强制 Node 24；项目实际测试的 Node 仍为 22。
- **下次做法：** 升级前通过官方 release 和 action.yml 核对稳定版本、runs.using 及输入兼容，独立审查并以新 SHA 重跑整个流程；不能只改 node-version 来消除 Action 自身运行时警告。

## 2026-10-07 Asia/Shanghai - 用户输入干扰要执行生产点击方法

- **触发：** 插件审批时用户可能正在浏览、拖动、选择文字或切换窗口。
- **现象：** 仅窗口归属布尔测试和整 Click 计数桩全部通过，生产方法回放却会覆盖用户新指针、松开已按住鼠标键；强杀测试子进程时 finally 未发配对 Up。
- **根因：** 系统输入边界和真实 Click 时序被整体替换，测试没有覆盖移动、按键和进程退出发生的时间点。
- **下次做法：** 保留生产方法，仅将 native API 和等待边界换成确定性内存实现；分别验证按钮身份漂移、30ms 观察期间移动、按键已按住、输入返回数量和恢复时输入变化。Down/Up 同批提交，不依赖可被强杀跳过的托管 finally。
- **检查：** 记录旧方法的失败和新方法通过；CI 不操作桌面，实机 UIA 焦点和后台审批另行验收。PS7 内查系统 PowerShell 使用 Get-Command powershell.exe，不拼接当前 PSHOME。

## 2026-10-07 Asia/Shanghai - 浏览器审批最终复核必须包含身份

- **触发：** UIA 卡片、宽栏按钮或 Portal 菜单在查询、滚动或展开期间改变。
- **现象：** card shape 仍合法，但域名更换、按钮转移父节点、旧菜单项替换后仍会调用旧 Allow Once。
- **根因：** 只检查语义形状，或复用最初父节点和菜单项引用，不能证明仍是原审批目标。
- **下次做法：** 保存原目标与运行身份；动作前重新核对父链、当前目标和当前菜单项归属。已展开菜单只在精确唯一关联及锚点成立时使用，未知预存菜单保持拒绝。
- **检查：** 在宿主、模式和最终 Card.FindAll 查询边界注入变化，旧按钮与旧菜单项调用数必须为零。最终菜单项身份检查之后再读卡片树，仍可造成旧项归属失效；先完成卡片关联查询，再枚举菜单项和父链，不能只测试宿主查询。没有显式 SetFocus 不等于 provider 不抢焦点，需真实输入观察。

## 2026-10-07 Asia/Shanghai - 原生输入结构和验证委托必须分别执行

- **触发：** 新物理输入通过 C# SendInput 和 PowerShell Func<bool> 控件复核组合执行。
- **根因：** 只测试 C# 的真假委托会漏掉真实 PS 作用域及 FromPoint 父链；只测试 x64 会漏掉 x86 INPUT 指针对齐。PS5 的 Marshal.SizeOf(RuntimeType) 还可能选择 object 重载。
- **下次做法：** 从生产 AST 提取委托赋值体，仅替系统命中查询，实际让生产 Click 调用；分别覆盖 button、text 子节点、几何、原身份、宿主和异常。Marshal.SizeOf 在 PS 测试中使用 boxed struct 实例，C# 继续 typeof；至少实际查询 x64 40字节/偏移8与 x86 28字节/偏移4。
- **检查：** 慢 UIA 委托后重新查询 native 前台和遮挡，再最后查输入戳及指针。保留 native 部分插入、同时输入和查询间隙的限制，不把内存模型称为真实桌面点击证明。

## 2026-10-07 Asia/Shanghai - 同批输入需要精确像素映射和最后状态复核

- **触发：** 为避免鼠标停留及强杀后的 Down/Up 分离，将移动、按下、松开、恢复放入同次 SendInput。
- **已跑复现：** 旧中间实现若自身移动更新输入时间戳，会返回 false 并停留在目标；归一化中心公式在宽度65535、offset1时回落到像素0。裁剪查询期间切走前台或遮挡，在较早校验后仍可能发出批次。
- **下次做法：** 按65536个输入坐标与每个物理像素的整数区间选点，纵横轴都断言；临时设置线程DPI上下文并在finally恢复，检查虚拟屏幕、裁剪边界及实际显示器命中，再最后核对前台、原按钮、输入戳和原指针。
- **检查：** PS5x64、PS7x64和PS5x86执行真实生产方法；输入返回0/1不重试，2仅尽力补Up，3只代表批准对已插入。模型通过不替代真实系统接收或混合DPI多屏证明，SendInput顺序插入不构成窗口/显示器原子事务。

## 2026-10-07 Asia/Shanghai - 低提交内存与安装器元数据分别定位

- **触发：** 全量扫描回归启动互斥测试进程时OutOfMemoryException；安装VSIX后package.json逐字节比较失败。
- **已跑验证：** 系统可用提交内存约1.1GB/总34GB，旧扫描器运行9小时私有内存约1.09GB；正常Stop后可用提交内存增加，完整npm test重跑退出0。不能只凭单个快照给源码下泄漏结论。
- **下次做法：** 先保存失败日志及具体PID、启动时间、编码命令归属，用插件正常Stop释放自己的扫描器再重跑，不清理其它用户进程；长期资源需趋势证据。
- **安装检查：** IDE安装器添加__metadata；运行代码仍逐字节核对，manifest排除这一安装器专有字段后逐项语义比较。不能把元数据差异说成运行代码不同，也不能忽略其它manifest差异。

## 2026-10-07 Asia/Shanghai - 资源基准的截止与输出必须一起保护

- **触发：** Process路径查询原函数与仅内存Dispose的单子进程基准，85秒硬限结束后没有完整对照数字。
- **根因：** 每250轮才查软截止过粗；外层等退出后才读stdout/stderr，硬截止时没有及时回收部分结果。
- **下次做法：** 从子进程启动就异步收集输出，每轮或少量轮检查截止，先用3轮热身和10轮样本测单次成本，再按墙钟调整循环数；超时先终止自己持有的子进程，再回收已产生的输出，不把测量失败当成实现缺陷。
- **单位：** 内存原始字节必须保留，展示明确MB或MiB；121331712 bytes为121.33MB或115.71MiB，不能与119.75MiB直接按数值大小比较。没有完整对照和长期趋势时，只报告观察，不据缺少Dispose认定泄漏。
- **计数：** for结束后的循环变量不是执行次数；本次热身输出标号曾显示4，真实轮次只有1/2/3，报告必须按实际记录计3次。

## 2026-10-07 Asia/Shanghai - 进程查询先分开枚举和路径计时

- **已跑验证：** PS5x64把Path换为native后整轮仍约200ms；拆分三轮发现Get-Process枚举183–222ms，而读取14条既有Path及native路径均约5–13ms，不能把热点误归MainModule。
- **真实缺陷：** PS5x86旧Path对14个x64 IDE宿主全部为空，MainModule报299；原生查询能识别14个完整路径。
- **下次做法：** 先按当前窗口PID查询完整映像，不跨轮缓存PID或路径；动作前重新核对路径并保留后续控件和窗口身份检查。同句柄查询前后零时等待仅接受258，不能用退出码259证明存活。
- **检查：** 同用户实际宿主、x86到x64、已退出但仍保留句柄、中文长缓冲、失败和抛错的关闭次数分别验证。小样本的速度或GC结果不能证明整个扫描器泄漏已解决。

## 2026-10-07 Asia/Shanghai - 嵌套PowerShell与诊断输出也要单独验证

- **现象：** 外层PowerShell调用另一个引擎的双引号Command时，内层变量先被展开成空值，得到ParserError而未执行测试；改为单引号正文生成EncodedCommand后，才复现有效宿主漏识别的预期红灯。
- **下次做法：** 子进程脚本正文使用不插值的文字块，编码后传入；明确区分解析错误与真实断言失败，保留输出。
- **基准输出：** PS5的ConvertTo-Json不能序列化UInt32键Dictionary；native查询已经成功也可能因诊断序列化退出1。先将键值转为记录数组，并保留失败日志，不把仪表错误归于生产方法。

## 2026-10-07 Asia/Shanghai - 扫描入口改变后生命周期测试也要隔离窗口枚举

- **已跑失败：** 完整npm回归的并发子进程未在10秒内随父进程退出；旧common仅把宿主进程图替为空，没有automation对象，新入口枚举窗口后反复InvokeMethodOnNull。异步收集同一真实生命周期的输出时，父退出后76ms正常结束；原现场管道阻塞没有线程栈，只能据源码与差分支持推断。
- **下次做法：** 生命周期fixture直接提供空FindAll集合，不依赖生产入口中某个早退；假窗口不读取桌面。只加载UIAutomationClient不会保证TreeScope已加载，显式加载UIAutomationTypes；保留原错误日志。
- **输出：** 等待退出前先异步收集stdout/stderr；已经消费READY或当前Pending之后才能读同一流的尾部，避免重复读取。不能以延长退出超时掩盖错误洪泛。
- **检查：** 空窗口两引擎并发22项通过后，再重跑唯一完整npm test；输出出现ERROR仍判失败，不能仅看进程退出0。

- **同类审查：** 单实例退出断言曾仅看exit0，受控子进程输出ERROR与stderr后仍被判通过。owner与waiter均在协议读取完成后异步收尾并拒绝错误或CLICK协议；abandoned owner也核对诊断。

## 2026-10-07 Asia/Shanghai - 多窗口内存失败需区分宿主与插件

- **触发：** 打开第二个公开插件 IDE 窗口后，截图和 PowerShell 全进程枚举均报内存不足。
- **已跑验证：** 新窗口语言服务器 13:24:57 报 runtime: cannot allocate memory，宿主随后记录无响应与 renderer crashed；13:30 事后提交量 34052124672 / 35307311104 bytes（96%）。原 5.3.5 scanner 仍唯一，最后 Private 为 119431168 bytes。
- **边界：** 事后资源读数不是出错瞬间读数；这些证据支持资源不足，但不能定位到插件泄漏，也不能把打开后立即崩溃算作稳定的双 IDE 验收。
- **下次做法：** 扩展窗口矩阵前先读系统提交余量；遇到不足先保留失败，只关闭本轮空白测试窗口，不清理用户其它进程。GUI 无响应退出是异步操作，要刷新窗口列表确认结果；同进程模态索引失效后用重新观察的截图核对。

## 2026-10-07 Asia/Shanghai - CLR 类别存在不保证可映射进程

- **已跑验证：** .NET CLR Memory 的 Exists 返回 true，但 ID Process 计数器构造报 Could not locate Performance Counter，无法可靠映射固定 scanner PID。
- **下次做法：** 区分类别存在、PID 映射和具体计数器可读三层；读取失败保留 unavailable 与原异常，不安装、不提权、不触发 GC。固定 PID 的 Private/WS/CPU 仍可记录，不能代替 CLR heap 或存活根证据。

## 2026-10-07 Asia/Shanghai - 发布交付必须逐个确认 Release 和商店

- **用户纠正：** PR 合并与 CI 通过没有完成发布。检查时 GitHub Release、Marketplace、Open VSX 都仍为 5.3.2；不能把本机安装成功说成商店更新。
- **已跑验证：** 从已验证 5.3.5 VSIX 创建 GitHub Release，标签指向通过 main CI 的 0b3f21b；下载公开 Release 资产后 SHA256 与安装输入一致。双商店已登录并打开表单，但浏览器文件选择器均要求文件 URL 权限；vsce ls-publishers、仓库 secret list 和已知发布环境变量为空。
- **下次做法：** 合并后先核对实际 Release/商店版本；只发布已验包。缺凭据不能伪造完成或自动创建 PAT。上传前读 file-uploads 文档；受限后准备好表单和确切包路径，再让用户做必需的一次操作。
- **工具边界：** 用户请求打开 chrome://extensions 后，Browser Use 仍拒绝非 HTTP/HTTPS 地址，并明确禁止其它控制路径绕过。仅提供手动打开步骤，不通过菜单、原生窗口、CDP 或其它浏览器面重试同一结果。

## 2026-10-07 Asia/Shanghai - CLR 计数器命名与测量日期精度更正

- **更正：** 上项 ID Process 构造失败来自诊断脚本命名错误，不是类别存在却缺少该计数器。本机 GetCounters 元数据和微软定义均为 Process ID；24 个名称中存在 Process ID、不存在 ID Process。
- **已跑验证：** 固定 scanner PID 1005396 在 16:10:18 和 16:11:26 均已退出；本轮不能提供其 CLR heap/Gen 读数。系统有效配对间隔 20.46269 秒，与 scanner heap 证据分别报告。
- **下次做法：** 首先只取计数器元数据确认真实名称；以明确 PID 和启动时间映射实例，不猜测替代 PID。日期间隔从原始 ISO 字符串或 DateTimeOffset 计算；默认 JSON 日期往返再转字符串可能丢失小数秒，必须保留真实超时配对，不能强报小于 60 秒。

## 2026-10-07 Asia/Shanghai - 用户修改扩展权限后重连与商店公开验证

- **已跑验证：** 用户开启文件 URL 权限后，Chrome 连接3失效，fresh getState显示同profile/原tabID的新连接6；按新清单重新连接原发布表单，文件选择成功，5.3.5双商店上线。
- **下次做法：** 连接失效先确认实际浏览器身份，不关闭或重建用户页面；不得把旧ID unavailable当作用户未授权。页面内部Settings显示latest5.3.5/Public仍可能在审，初期公开API为404；以PUBLISHED队列、公开版本控件/历史和可下载包验证完成，不能仅看通用It's live提示。
- **边界：** 新agent与idle代理followup均曾被thread limit拒绝，避免重复创建；复用已有运行的代理与root交叉审查，不伪称新独立reviewer已运行。

## 2026-10-07 Asia/Shanghai - 大型发布脚本不能塞进 Windows 命令行

- **已跑验证：** 发布离线测试首次有13个用例被spawnSync ENAMETOOLONG阻止，生产发布代码尚未执行；不能把这次红灯描述为发布逻辑缺陷。
- **根因：** 把完整工作流内联脚本与fixture通过EncodedCommand传给Windows子进程，编码后超过命令行限制。
- **下次做法：** 小型UTF8启动引导继续使用EncodedCommand；大型PS7测试正文写入本轮独立临时目录的UTF8 ps1，以pwsh -File执行，保留实际退出码和断言日志。
- **检查：** 修正后26项发布回归全部通过；临时清理先核对绝对目录在系统Temp内且前缀属于本轮，再使用同一文件API删除。

## 2026-10-07 Asia/Shanghai - 单元回归与scanner ready不能替代当前包实机焦点验证

- **用户纠正：** 5.3.6需要Computer Use本机测，不能沿用5.3.5实机结果或只报PR/CI。
- **已跑验证：** 安装字节一致、日志确认5.3.6后，真实终端/浏览器批准可执行，Note文字保留；200ms原生只读样本却在两个批准附近记录Note→IDE前台切换。OFF对照中单张终端原生卡持续等待，Note在后续采样中保持前台。
- **下次做法：** 合并前要求当前安装包的实机证据，批准返回、工具结果、文字保留、前台/鼠标和多窗口分别核验。秒级日志不足以给Select/Invoke/Expand/宿主调用定责；先补阶段毫秒观测，不盲加焦点恢复，不放宽身份/输入校验。
- **边界：** 200ms快照不能排除间隙内短暂切换；当前Chromium upstream默认点击可改变页面焦点，不能直接推出本机Windows前台变化。低提交余量时不重复开第二完整IDE造成用户环境崩溃。

## 2026-10-07 Asia/Shanghai - 原生观测几何与异步插件状态需刷新确认

- **已跑验证：** 最小化的自有Note不能抓状态；AX-only后两次click报coordinate input geometry is unavailable，动作未确认。恢复自有窗口并用fresh screenshot后输入成功，不把工具几何错误当插件故障。
- **下次做法：** 实机输入使用当前截图与返回的窗口句柄；控件索引失效先观察，必要时一次截图坐标回退。插件启动异步，click回调仍显示旧OFF时先看fresh ready/日志，不能立刻判定点击无效或重复切换。
- **日志定位：** 最新Antigravity logs目录可能仅有CLI安装日志；按近期真实window/exthost输出的5.3.6激活与ready定位，不把rg无命中说成scanner不存在。

## 2026-10-07 Asia/Shanghai - 阶段诊断本身、日期解析与恢复身份必须验证

- **已跑失败：** 诊断Console.WriteLine中的多参数-f表达式未整体括起，异常被日志自身catch吞掉；纯内存包装断言发现缺日志，修正后再安装。不能把静态解析通过当实际诊断输出通过。
- **日期：** ConvertFrom-Json后的时间字段可能已变为DateTime，再与ISO字符串比较会得到空筛选或丢失精度；先按原始JSONL的ISO文本或数值elapsedMs定位，再报告样本读取区间，不能把时间戳当原子前台读数。
- **恢复：** 同版本CLI安装只替换磁盘文件，旧scanner仍运行。先核对原包hash，再用本轮已记录PID、精确启动时间、父PID和解码启动路径证明所属实例，才停止该诊断进程，随后按原重启日志确认原包ready。Windows安装路径驱动器大小写不同，身份比较使用OrdinalIgnoreCase，不缩减为文件名匹配。
- **工具边界：** Computer Use因无法可靠确认浏览器URL停止后，本轮停止所有界面输入，不换CUA/CDP/原生路线重试。已运行的只读观测记录可以保存，但不能冒充被中止的完整交互验收；非UI官方CLI可恢复本轮诊断安装。
- **边界：** Note→IDE切换被缩小到Invoke调用后半段或返回后的极短区间，Chrome也出现对应前台切换；这仍不能区分provider与异步宿主激活，不能盲加焦点恢复或放宽最终批准校验。

## 2026-10-07 Asia/Shanghai - 同SHA首次超时与重跑成功分别保留

- **已跑验证：** 17135bc的PR/push首轮PS7分别在owned-child READY10s、SelfTest20s超时；原失败日志保留，同SHA各重跑失败作业一次后成功，未改断言和超时。
- **下次做法：** 在不修改生产代码的证据提交上，先区分runner协议启动超时与功能断言失败，精确核对SHA/attempt；GET失败且未提交重跑请求时先查原run状态，再补发一次请求。不能把重跑成功说成根因已确定或CI无不稳定。
- **检查：** 独立8秒mutex协议重放通过也不能替代诊断包完整PS7最后一项超时记录；测试范围与证据等级分别写明。

## 2026-10-07 Asia/Shanghai - 客户端标志通过不等于后台焦点修复

- **已跑验证：** 同一原生UIA客户端AutoSetFocus=false，真实窗口/RuntimeId绑定和Invoke正常返回，Submit仍令Note转到IDE。600个独立样本确认切换，45字符文本保留和工具exit0不能抵消这一体验失败；不合并未奏效候选。
- **原生契约：** GetTypedObjectForIUnknown的Type要求COM imported class，不是COM接口；预检只创建client不会覆盖pattern转换。改为GetObjectForIUnknown再QI到接口，并分别释放自己的RCW与原始pointer；清理不能遮盖动作原异常，也不使用FinalReleaseComObject清空共享引用。
- **生成ABI：** SDK SAL宏可含内部下划线，不能用过窄正则删注解后把BOOL*/接口输出误当IntPtr；完整SDK vtable顺序、GUID、out/SAFEARRAY独立校验。多个C#文件用Add-Type -Path数组；避免将第二文件顶层using拼到前一namespace之后。不要复用PowerShell内建PROFILE变量。
- **测试：** 无效参数测试必须核对异常类型与内容，catch任意异常可把真实桌面失败误算成早期拒绝。没有插值的双引号here-string可能被解析为StringConstantExpressionAst；校验应接受两种字符串AST并拒绝真实NestedExpressions。
- **界面：** launch_app超时先刷新窗口，不重复启动；AX-only click几何缺失时补fresh截图。离屏按钮的AX索引不能替代可见区域核验，先滚动到实际可见工具记录，再展开；不要将未展开的Agent总结当原始工具输出。
- **证据边界：** Chromium固定版本默认动作中的页面focus不是本机Windows前台定责；实际IDE内核尚未映射。认证必须用户手动恢复，第三方Panel的TFA告警也不能独自推出主Agent仍无法工作。

## 2026-10-07 Asia/Shanghai - 标准pattern与真实触发范围必须分别核验

- **已跑验证：** GetCurrentPattern标准IUnknown路径在绑定后读回AutoSetFocus=false，真实一次Submit仍使Note转IDE；不能通过更换获取API宣称修复。Help > About确认Chromium 142.0.7444.175后，才能将固定upstream源码映射本机；页面焦点仍不是Windows前台的定责。
- **触发：** 自然任务可选择list_dir等无需审批工具；没有卡片/Invoke的观察记为未触发。实际只读系统测量产生一次审批后，再看原始工具输出、前台记录和文本保留，三类证据不能互相替代。
- **输入：** set_value返回成功但本轮草稿未变；必须检查实际可见内容。聚焦自有草稿后Ctrl+A，核对selected_text严格等于自有文本，再替换，不能把RootWebArea焦点直接当用户代码可编辑区。
- **生成：** Temp生成器原为LF，候选源为CRLF，应逐文件检测；PowerShell正则替换中的字面反斜杠r/n不会生成换行。使用明确CR/LF字符值并以唯一完整代码块、hash及AST为守卫；边界不匹配时不得写文件。

## 2026-10-07 Asia/Shanghai - 真实provider、触发顺序与Legacy单例证据

- **已跑验证：** 实际Submit Framework=Chrome、LegacyAvailable=True；只支持取得另一已文档化接口，不独自定责代理/宿主。AutoSetFocus=false的标准Invoke失败后，仅替换客户端为Legacy默认动作、保留完整最终检查，真实一个后台Submit返回后仍Note，独立511个后续样本保持Note及鼠标/input tick。不能从一个静置案例宣称持续输入、多窗口、全部按钮已修复。
- **触发：** 前两次批准早于Note激活，仅记接口执行通过、后台未触发。缩短发送后切换延迟可用两次连续Computer Use调用，各自只输入一次并刷新，不能省略观测或重复已发送任务。get_window_state必须至少请求text或screenshot；两者false的拒绝是工具参数错误，不是插件bug。
- **接口：** SDK完整24成员顺序/已调用ABI和两引擎编译先核验；MSAA入口少disabled拒绝，不能去掉原最后enabled、身份/选择/几何校验，也不能凭Blink disabled表单保护推断全部ARIA控件安全。保留自己的COM清理风险，正式实现前处理。
- **恢复：** CLI先成功后V8崩溃exit134，不能按成功文字说exit0或盲重装；先独立验磁盘hash、主IDE身份，再正常重启scanner，核对新PID/start/parent/decoded path/ready且旧候选退出。此轮未确定CLI崩溃根因。
- **工具输出：** 实际命令只回报内存数值，未显示exit code且未测时间，不补写；Agent显示Explored files时，不把自然语言只读边界当全部行为已验证。200ms样本不覆盖间隙的短暂激活。

## 2026-10-07 Asia/Shanghai - 浏览器本机测试中止与自有服务清理

- **已跑验证：** Browser Use能读取自有环回输入页，但Windows Computer Use看到Chrome最小化，恢复请求被URL可信识别规则停止。本轮未发送测试Agent任务、未重启Legacy候选、未开始输入，不把页面创建算焦点或输入验收，也不换UI路径继续。
- **清理：** 非UI官方CLI恢复原包exit0，磁盘hash与原版一致；原scanner PID63404/start/parent保持，候选只曾写磁盘而未替换运行态。自有node服务的PID、start与唯一绝对script命令行匹配后关闭，保留Temp文件。
- **新坑：** exec_command默认非TTY的长期服务会关闭stdin，write_stdin发送quit失败；后续若要以stdin关闭自己的测试服务，启动时明确tty=true，或准备只针对本轮已验证进程身份的正常关闭接口。不得因stdin关闭重启同一已运行服务或结束其它node进程。

## 2026-10-07 Asia/Shanghai - 原生契约扩展后的测试类边界与清理异常

- **已跑验证：** 五个 Invoke 获取入口的六个离线分支在原源码均红灯，接入 Legacy 准备边界后转绿；不得把桩里的前台状态当真实 Windows 焦点验收。完整首轮 scanner=152 通过，但 host-process 影子 C# 编译失败，整套结果仍为失败。
- **边界：** 同一个内嵌 C# 文本新增命名空间后，LastIndexOf('}') 已不属于 MouseHelper。影子字段仅插入完整顶层 MouseHelper 类范围；生产完整 C# 仍先编译，全部 P/Invoke 必须替换，不能删断言或漏出实际桌面调用。两个夹具边界独立括号配对和21项原生声明审查吻合。
- **清理：** 真实 RCW 重复释放没有复现异常，不冒充实机复现。受控 Marshal 释放异常会遮盖原异常，分别覆盖 InvalidComObjectException、COMException、ArgumentException，保留原审批异常并继续释放后续引用；不使用 FinalReleaseComObject。
- **生成：** 两个候选循环都有同名阶段标签，唯一匹配守卫在写入前中止；先核实函数范围再替换。PowerShell 同分隔符 here-string 不能嵌套生成脚本，改用 Temp 文件补丁，避免生成器提前结束。

## 2026-10-07 Asia/Shanghai - 正式 Legacy 窄菜单失败与观测覆盖

- **已跑验证：** 正式提交双CI首次绿灯并安装运行后，真实两个浏览器域名Allow Once执行；第二项原生采样记录Note→IDE，窄按钮invoke=False/expand=True。仅替换Invoke入口不能证明展开链无焦点变化，下一步先分开观测展开与最终允许，不发布该候选。
- **覆盖：** 自然任务比120秒观测更晚触发审批，首项没有动作时采样，只记未覆盖；180秒请求被既有ValidateRange拒绝，不修改界限掩盖。后续基于真实任务进度启动第二段，保留第一段N/T结果。
- **快照：** IDE输入/进度AX可滞后于截图，甚至完成仍报告Working；用fresh截图、真实输出文件和日志交叉核验，不重复发送。几何失败先看确切草稿，只有未发送才能一次最新截图重试。
- **日期：** 复用既有JSON日期经验，直接解析原始ISO文本得到319样本；六段输入只有第一段在首观察区间，不把全部输入写成连续审批期间验证。
- **预检：** 完整类声明含sealed，过窄文本断言会误报缺契约；在已有作用域调用&导入函数会在子作用域结束后消失，独立内存夹具使用dot-source并先确认唯一完整函数边界。编译和十条实际格式断言通过后才安装诊断包。

## 2026-10-07 Asia/Shanghai - 窄菜单展开定界与准备顺序

- **已跑本机验证：** 完整原动作诊断在 Expand 前为 Note、返回后为 IDE，最终 Legacy Allow Once 在前台已变后才开始，无滚动。该阶段窗口定位不等于确定 OS/provider 的具体激活调用。
- **已跑内存验证：** 默认动作可能切换菜单，先识别精确关联的已开菜单；只有确需触发时准备 Legacy。已开菜单的触发器不支持 Legacy 不应挡住本次菜单项。折叠状态 getter 与模式准备均在最终 PID/HWND、卡片身份/文案、enabled/offscreen 和父宿主检查前；getter 改名或改 HWND 的两项实际函数重放原候选触发一次、修正后拒绝。
- **夹具：** 经典托管 UIA 没有 LegacyIAccessiblePattern 类，纯内存边界使用已对照契约的模式 ID10018，不能把夹具类型缺失当产品红灯。
- **打包：** 根项目没有本地 vsce.cmd，使用 package.json 固定的 npx @vscode/vsce@4.0.0；调用不存在的命令时 LASTEXITCODE 不能证明成功。先确认命令路径，启用 Stop 并保留实际进程退出码。

## 2026-10-07 Asia/Shanghai - Legacy 窄触发器不打开真实菜单

- **已跑验证：** 第十项重放证明准备期间打开菜单会被默认动作关闭；准备后复读状态且保持最终身份检查在后，双引擎10绿、复审无新增发现。
- **已跑本机验证：** A5CF候选普通Submit后483个样本全Note；真正窄按钮Legacy默认动作虽返回且保持Note，却 visible/new/once-items 全0、没有批准，488个后续样本仍Note。界面卡住也是失败，不能只看不抢焦点或桩里的模拟菜单打开。候选经正常Stop停止、PID94204退出，保留同一待批准卡片继续差分。
- **下一步依据：** SDK完整展开接口四项、GUID及10005对照后，测试同一AutoSetFocus=false客户端原生Expand；契约参数预检不触碰真实桌面，焦点与审批仍须实机同时证明。

## 2026-10-08 Asia/Shanghai - 原生客户端 Expand 仍会切前台

- **已跑验证：** AutoSetFocus=false 原生展开契约双引擎预检和窄菜单10项内存回归绿，真实 Expand 返回后却 Note→IDE，Allow Once 完成不抵消体验失败；正常Stop后核对具体PID退出。
- **下次做法：** 区分客户端标志、离线接口契约、真实菜单打开、最终审批和前台保持；不同层证据不互相替代。GetIAccessible 可返回 NULL，直接 provider 的可用性与对象身份需实机证明，不把源码没有显式 SetFocus 当 Windows 前台定责。
- **工具：** get_window_state 已自动展示截图，不再 emitImage 同一 payload 作重复观察；异步 Stop 返回旧ON时用日志和固定PID核验，不能立即重复切换。

## 2026-10-08 Asia/Shanghai - GetIAccessible 空指针与未执行动作的证据边界

- **触发：** UIA Legacy 属性可读，但直接服务端指针取不到；原生准备失败只有 MethodInvocationException 外壳。
- **已跑验证：** 根异常为 Native MSAA server missing，GetIAccessible 返回空；后台 Note 保持来自没有 Expand 或最终批准。两个候选具体 PID 正常 Stop 后退出，不能把观察器稳定说成审批成功。
- **下次做法：** 记录根异常类型/HResult和阶段，不丢原错误；只抑制连续重复而非声称全局按内容去重。先核对真正支持的原生服务及完整 RuntimeId 映射，失败拒绝操作。
- **检查：** 准备、展开、批准、工具结果、前台与输入分别给证据；观察器资源类型按实际 observed-process-resource 计数并与 end 对照。

## 2026-10-08 Asia/Shanghai - 双引擎内存分配夹具不要压制过时 API 告警

- **触发：** 用完整生产 COM 准备方法做纯内存身份/清理测试，需绕开真实客户端构造。
- **现象：** Framework FormatterServices.GetUninitializedObject 在 PowerShell7 Add-Type 报 SYSLIB0050，PowerShell5.1 可编译。
- **下次做法：** 测试夹具用反射选择 RuntimeHelpers.GetUninitializedObject，旧 Framework 才选 FormatterServices；不压告警、不改生产构造、不调用桌面。修正后十项真实方法分支双引擎均通过。

## 2026-10-08 Asia/Shanghai - 原生外层窗口与 Chromium 子窗口不能混为同一目标

- **已跑本机验证：** outer HWND133218 的 MSAA 对象 childCount=0，映射编号为42,133218,4,-18；真实按钮为42,198588,4,4,1,72691。沿绑定按钮 RawView 取得最近原生祖先后，映射进入198588，但命中仍返回窗口根42,198588,4,-115150，childCount=2。两轮均无展开或批准，正常Stop后具体106228/119436退出。
- **下次做法：** 从已绑定目标确认原生归属，再比较完整 RuntimeId；不从 RuntimeId 某一整数猜 HWND，不靠名字或坐标近似放行。背景稳定仅证明拒绝路径；UIA/Chromium公开 UniqueId 到原生 child 的映射须另行验证。

## 2026-10-08 Asia/Shanghai - HRESULT 诊断和观察窗口必须覆盖实际分支

- **已跑内存红绿：** ThrowExceptionForHR(E_NOTIMPL/E_INVALIDARG) 可变成 NotImplementedException/ArgumentException，只有COM catch会盖住原身份拒绝。仅诊断try捕获Exception，再统一抛原绑定错误；双引擎两例保留原错、零Expand、引用释放完整。
- **观测：** 90秒观察提前结束于scanner Start前，排除该记录；重新观察60011ms/300样本后才记录对应111368拒绝路径。新119436观察90013ms/450样本，348个交接后样本全Note；不要把结束前后覆盖或静置样本说成持续输入验收。
- **工具：** Node REPL 新变量先var/let声明，隐式赋值可能在动作前或动作后抛错；先刷新真实状态，不能盲重试。AX旧ON/OFF与截图异步时按日志/PID交叉核验。

## 2026-10-08 Asia/Shanghai - UniqueId 离线契约通过不证明本机属性可用

- **已跑验证：** Registrar ABI/CLSID、PropertyInfo两位数布局与45分支双引擎绿；本机仍为Native target UniqueId missing，原生child、展开和批准都没开始。该错误不能独自定为provider接口失败或属性不支持，须区分默认值、返回类型及不支持标志。
- **下次做法：** 不解析RuntimeId某个整数猜原生UniqueId/窗口，不以名字几何替代完整身份。Native UIA与MSAA转换可能给出不同编号，须从官方接口与本机返回建立同一对象证明，不能放宽比较来让候选通过。
- **夹具：** PowerShell7 Marshal.SizeOf(Type)重载绑定可能选object，把RuntimeType本身当结构；用GetMethod明确Type参数签名后Invoke验证尺寸。仅夹具错误，未改变生产ABI。
- **恢复：** 正常Stop121560核对退出，原包官方CLI恢复exit0，source/JS各自hash验证；scanner保持OFF，不让失败诊断留在用户日常运行态。

## 2026-10-08 Asia/Shanghai - 同 SHA 一次重跑仍失败时保留失败并补充边界诊断

- **已跑 CI：** df29655 的 PR/push 首次 PS5 均在 owned-child READY10s 超时。各自仅重跑失败作业一次后，PR attempt2 成功、push attempt2 仍在同一处失败；PS7 均通过。不能只引用 PR 绿灯或把重跑成功当作不稳定已消除。
- **边界诊断：** 保留 10s READY、10s退出及原位数/路径/存活/退出259断言；超时记录持有的自有 child engine/PID、期望位数、退出前状态和两个读取任务状态，终止该 child 后有限等待读取READY/stderr。停止/读取异常只进诊断字段，仍抛原 ready timeout。
- **已跑本机：** 原正常双引擎125项通过；延迟15s READY的真实自有子进程重放，旧版缺少诊断而失败，新版PS5/PS7调用32/64位子进程四项均保留超时并通过诊断及退出验证。它证明诊断有效，未证明CI原超时根因。
- **工具坑：** JavaScript模板字面量内直接放PowerShell反引号会导致JS解析失败，尚未执行的工具不能说已创建文件；跨两层引号的精确替换先检查实际文本，匹配不唯一立即停止，再用单引号转义构造命令，不盲重跑替换。
- **下次做法：** 下一次CI超时按实际诊断区分子进程启动、stdout读取、stderr错误、退出状态；不得继续重复重跑、放大超时或改变断言来换绿灯。正式5.3.6仍须本机后台审批验收通过后才能合并发布。
