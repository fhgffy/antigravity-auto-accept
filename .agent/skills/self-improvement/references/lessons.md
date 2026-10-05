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
