# 2026-10-08：后台浏览器审批的属性与原生编号诊断

证据等级：已跑本机验证、已跑离线验证、已读源码。5.3.6 尚未通过后台浏览器审批验收，PR12 保持草稿；未合并发布。

## 当前 CI 与发布边界

提交 f18ed6a9efaa058d139399f7fcb61dea6194c1e0 的首次 push run 37678092637 通过双引擎与 Verified VSIX；首次 PR run 37678101006 的 PS5 通过、PS7 在宿主身份步骤失败，Verified VSIX 和发布均跳过。失败为 caller64 → child32 PID764 的 READY10s 超时；超时前 child 存活，READY/stderr 两任务 WaitingForActivation，终止后捕获输出为空、stopError 为空。没有再次重跑。源码随后审计确认 WaitForExit(5000) 返回值被丢弃，stopError 为空不能独自证明已退出；ReadLine 的 null EOF 与空行也曾被同一空字符串格式合并。

独立受控真实 child 重放表明：脚本可以在第一条 Console.Error 写入前已经执行，仍留下空 stderr；ReadToEndAsync 的 WaitingForActivation 也不代表没有读取任何字节。这是观测边界，不是 Console、冷启动、AMSI 或 ThreadPool 根因定责。本次新增独占 GUID/nonce 的三个 CreateNew+close 阶段文件，ENTERED 在任何 Console getter 前写入。保留原10s、精确三行 stderr 与125项身份断言，双引擎正常执行新增6项共131项。冻结测试源码776F1BBCD759D5DE3518CD44933FE0A1E1C7034A2F6DC13B4229846FF4FDB9D9，PS5/PS7各24个实际 reader/timeout/finally 边界和六个真实延迟子进程全部通过；独立审查各131及24也通过。只对验证完成且已确认退出的精确三个绝对文件路径清理，诊断异常保留原超时，EOF null与空行分开。ROOT随后在同一冻结测试源码运行 npm test，exit0：compile/typecheck、repository3、publication26、selftest95、lifecycle28、scanner152、host双引擎各131、mouse双引擎各81、concurrency22全通过。完整日志位于C:/Temp/AntigravityAA-ci-stage-files-536-71042d8b1bac469d8cbb1db868459c3e/root-full-suite.log。随后f79d73b9cdf985a881b3496f27759e22bf6d08fa首轮PR37685982927通过双引擎与Verified VSIX；首轮push37685975422的PS7通过、PS5 caller64→child32 PID7372 READY10s失败，包与发布跳过。实际CLIXML解码确认ExitWaitCompleted/HasExitedAfterStop均true，READY为null EOF/length-1，stderr length0，三个stage均missing；exact文件清理及空dir删除成功。首次ENTERED之前仍有赋值/ASCII编码/文件IO，不能由missing声称脚本从未进入。没有rerun，原间歇超时根因未修复。

提交 3d557feea4a0d88ca4bfd09996eb4d5c243f4e9f 的 PR run 37668572394、push run 37668565299 均首次通过，包含双 PowerShell 引擎和 Verified VSIX。未重跑。新增 READY 阶段 stderr 协议仍要求精确三行与 PID，原 10s 超时和 125 项宿主身份断言不变；前两提交的 READY 超时失败与一次重跑记录保留在 verification-2026-10-07-release.md。本次绿灯不能证明间歇超时根因已修复。发布作业在当前分支跳过，不能把 VSIX 校验称为已上线。

## UniqueId 的本机返回

隔离候选仅对已完整绑定的当前 More actions 目标读取默认属性、GetCurrentPropertyValueEx(ignoreDefault=true) 和 ProviderDescription。原完整 RuntimeId、root HWND/PID、RawView 原生祖先校验及全部 PowerShell 最后检查保持；所有新路径均抛诊断拒绝，不返回动作包装，不取得 native child，不展开或批准。原包其它审批分支仍在，因此只读结论仅限本次无已有菜单的窄栏卡片，不是全局只读模式。

- 默认 UniqueId：HRESULT S_OK，System.String，长度 0；CheckNotSupported 为 false。
- 忽略默认值：HRESULT S_OK，System.__ComObject；CheckNotSupported 为 true。
- ProviderDescription：HRESULT S_OK，字符串长度 98；MSAA、Proxy、Bridge、Chromium、Chrome、Microsoft、UIAutomationCore 七个固定分类均 false。没有打印提供者原文。

默认空字符串不能独自证明属性不支持；第二查询及 CheckNotSupported 才补齐这项本机证据。当前已绑定目标不提供可用的注册 UniqueId，不能放宽 RuntimeId 比较或猜某一整数来进入原生动作。新的查询错误按 HRESULT 映射并显式忽略线程 IErrorInfo，防止调用方日志重新带出提供者文本；原绑定拒绝仍保留。

## 包、生命周期与独立前台观测

官方 CLI 安装退出 0；安装源码 SHA256=A14C4A66E0A5196485EDB71C9715F381C24F30A78D73B72A8F2C8D6899CF43A7，VSIX=894F7C8A3BCD7A0B3767A93C601ADFB83887A85A1EA14F8ACA89B0EDCA15387A。归档 8 个条目，除 scanner 外其余 7 个 payload 与基线逐字节相同。双 PowerShell 引擎各通过完整方法 65 个模式、缓存 1 项、真实 PS 拒绝链 6 项、窄菜单回归 10 项和完整 C# 预检；独立审查复跑核心夹具通过。UTF-8 无 BOM、CRLF 与 PS 层字节不变检查通过。

主 IDE PID35596 / HWND133218 和 extensionHost PID36856 保持原启动身份。Scanner PID144356 于 03:17:47 启动，03:20:01 正常 Stop 后 CIM 确认退出。第一次开关动作因 geometry unavailable 没有执行，重新观察仍 OFF 后恢复一次；第二次正常请求后的旧 OFF 快照没有作为重试依据，实际日志及 PID 证明启动。Stop 返回旧 ON 同样仅按日志/PID确认，未重复切换。

初始 60s 观察结束在恢复后的 scanner Start 之前，明确排除其启动/静置证明。第二观察为 19:18:36.609Z—19:19:36.612Z；无输入区间为 19:19:01.857Z—19:19:36.435Z。173 个完整落在该区间的采样均为 Note HWND329822，读取前后稳定，cursor1322,865 和 lastInput tick30829546 各仅一个值。资源采样固定为 IDE PID35596，不能称为 scanner 资源或泄漏证明；前台、指针、输入查询也不构成原子快照或输入来源识别。

记事本原 197 字符逐字保留；未追加输入，TypeScript 审批仍 pending，未出现 Allow Once 或 CLICK 动作。稳定只证明拒绝路径，不是实际批准通过。候选随后官方 CLI 还原原包退出 0，安装 scanner SHA256=7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A，扫描器 OFF。原 IDE 的 8 项未提交内容未修改。

证据目录 C:/Temp/AntigravityAA-browser-property-536-d29d032b60ba4bd1a8443ca4e6880f53，含 native-runtime-ledger.json、native-plugin-excerpt.log、verification-ledger.json、package-byte-check.json 和红绿日志。原始观察位于 production-legacy Temp 目录，具体文件在 runtime ledger 中。

## 原生身份接口的验证边界

公开 CompareElements 契约也依赖完整 RuntimeId 相等，不能跨不同编号证明对象相同。随后进行了原生 provider → core 完整编号的零动作诊断，结果见下文，只允许公共接口生成 opaque 完整 ID；不手工拼接，不执行展开/批准。相关 C API 已弃用，仅是隔离实验，不能先称稳定生产桥或焦点修复。

固定 Chromium 142 源码中普通菜单 Expand 可走 RequestClickAction → SetFocusedElement。该页面焦点链不等于 Windows 前台激活，且本机实际 Chromium 版本未核实；同一 native provider 无公开“跳过内部聚焦”的 Expand 参数。因此即便身份映射可用，仍须真实审批、前台、持续输入和多 IDE 一起验收后才能合并或发布。

## 公开契约与命令检索范围

证据等级：已读官方契约与本机源码，未调用隐藏服务。Microsoft [CompareElements](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation-compareelements) 明确以相同 RuntimeId 判定；[GetIAccessible](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationlegacyiaccessiblepattern-getiaccessible) 在特定 proxy/bridge 下允许 NULL。[AutoSetFocus](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation2-put_autosetfocus) 控制客户端 pattern 前聚焦，不能当 provider 内部不聚焦承诺。固定 [Chromium142 Expand](https://github.com/chromium/chromium/blob/142.0.7444.175/third_party/blink/renderer/modules/accessibility/ax_object.cc#L7771) 对普通菜单可进入 [点击焦点链](https://github.com/chromium/chromium/blob/142.0.7444.175/third_party/blink/renderer/modules/accessibility/ax_object.cc#L7656)。

本机 workbench JS（SHA256 F4BD347D94BE4634D2ADEEC8B3EF65E4D65D7DD0D72281B0E1982FE9C71FE6A7）、builtin extension.js（7E46AC546C790FF8F9F249C3F2D3A236CB8489917C961A58A12D9C22D108B4B8）和 package.json 的已检范围，未找到带 cascadeId/trajectoryId/stepIndex 参数契约的公开一次性 browserAction confirm 命令。acceptAgentStep 的注册 handler 不转发参数，不能用猜测参数绑定特定会话；快捷键 label 也不证明 browser 组件注册了回调。62 项命令枚举及 builtin 固定注册入口不覆盖服务端动态 LSP 命令，所以不能推论所有运行时命令绝对不存在。未读认证值、调用 RPC、执行未知命令、注入 DOM 或修改域允许列表。

## 公开版本复核

已跑 API 验证，2026-10-07T19:32:29.0666347Z（本地 2026-10-08 03:32）：GitHub 最新 release v5.3.5，发布时间 2026-10-07T08:15:51Z；Marketplace 精确扩展查询 flags33 与 OpenVSX latest 均为 5.3.5，Marketplace 返回版本列表不含 5.3.6。PR12 仍 OPEN/DRAFT，head=3d557fe。具体 JSON 位于本轮 property Temp 目录；未把本机诊断包上传到商店。

## 原生 provider/core 编号的本机结果

证据等级：已跑本机验证、已跑离线验证。隔离源码 SHA256=5C89B2F986BD25C3F9439FAA0A4B67C7D1D273841EA330C2EA053E4C0A3EC13A，VSIX=838D5815D79B9E40120CBEED73843607DE45A48DF0354C1EE5555FD37FAE2CC0。官方 CLI 安装退出0、安装源码hash一致。双 PS5/7 加 x86 各79个完整方法分支及真实Windows SAFEARRAY/IErrorInfo接口验证通过，双引擎实际PS拒绝10例和完整预检10records通过；独立审查复跑并核对8entries/other7 payload、编码及原完整binding/PS层字节一致。此前夹具错误和native ErrorInfo失败日志保留在Temp，未通过压测试来清除失败。

Scanner PID147588、parent36856、启动03:41:40.017201+08:00。实际推进到runtime-core后，UiaGetRuntimeId返回80004002（E_NOINTERFACE），nodes=1、match=false、terminal=core-fail；所有重放相同。没有拿到可与原目标比较的完整core编号，未进入后代遍历。这不是“整棵树没有目标”或“命中另一对象”的证据，也不是展开/批准失败；诊断零动作分支已经拒绝。后续只可提出可证伪的只读子树观察，不放宽原完整身份。

90s观察覆盖19:41:07.086Z—19:42:37.097Z，无输入交接19:41:53.696Z，实际案例结束19:42:50.182Z。交接后216个完整样本（53.894Z—42:36.891Z）均Note329822、读取前后稳定、cursor1322,865、lastInput tick32262390均未变；该观察提前结束，不能把缺失的末尾约13秒纳入连续前台保证。结束时单次快照Note仍197字符逐字保留；其后主动切回IDE操作Stop不归因插件。资源固定IDE35596，不是scanner指标。

03:43:37正常Stop，CIM147588已退出，CLI原包恢复exit0且安装scanner重新为7F732F...8ADC0A，UI OFF，原卡片仍Waiting for user input；原工作区8项未提交内容保持。证据目录C:/Temp/AntigravityAA-browser-provider-id-536-60136a904305411ba14fa1bbd732f880，包含native-runtime-ledger.json、native-plugin-excerpt.log、完整79分支与native ABI红绿记录。弃用C API仍只用于隔离诊断，未进正式源码。

Microsoft [Control Patterns Overview](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-controlpatternsoverview) 明确provider接口由core使用，client拿到另一套接口；[GetCurrentPatternAs](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationelement-getcurrentpatternas)的通用IID参数不能推出能还原稳定native provider、同一目标身份或无焦点动作。本轮未试任意provider IID、更未据此执行动作。

## 首根失败后的后代只读诊断

证据等级：已跑本机验证、已跑隔离验证。2026-10-08 的隔离候选仅允许首节点 nodes1、深度1、同一 fragmentRoot 在 UiaGetRuntimeId 返回 E_NOINTERFACE 时，经失败 out SAFEARRAY、coreNode、providerPointer 三项即时清理全部成功后继续 FirstChild。任一清理失败、S_FALSE 或异常仍保留原80004002且零Navigate；后代及其它阶段/错误不跳过，完整 opaque 编号、绑定守卫及原遍历界限保持。所有路径仍抛诊断拒绝，未返回动作包装。

源码42607C96EC0AF49A9BC8A3E3BCD709519A063E638A3EAD7DB35A1EB2F8F7D13D，VSIX2FA703E6B58CBE68D36F589F4915A750DE31AD6B516E521B5748E11848E20632。完整111方法模式PS5/PS7/x86通过，实际PS拒绝链20项、真实本进程ABI及预检通过；独立审查复跑双引擎111、PS7拒绝20/预检10与x86 ABI，并核对原PS尾及8entries中other7字节完全不变。UTF8无BOM/全CRLF/解析通过；仅支持诊断候选，不能证明实机命中或动作无干扰。

官方CLI安装exit0、安装源码hash一致；scanner PID161408、parent36856，04:25:28.761703+08启动，04:28:00正常Stop后CIM确认退出。实际186轮均先记录 root-core-interface-unsupported/80004002/nodes1/rootSkipped=true，随即首个后代 runtime-core/80004002/nodes2/match=false/core-fail。此次进入了一个后代，仍未取得可比较完整编号，不能推论其余后代或整树缺目标；无CLICK或expand-after/allow-after/trigger-after，原TypeScript卡片仍pending。

120s观察实际为20:24:50.866Z—20:26:50.873Z，共600样本和24条IDE35596资源记录。无输入交接20:26:04.290Z，案例结束20:26:59.454Z；覆盖内232完整样本（20:26:04.464Z—20:26:50.668Z）均Note329822、读取前后稳定，cursor1322,865及lastInput34891093不变。案例收尾晚于观察约8.581s，明确排除未覆盖尾段，不声称全程保持。结束及恢复后的Note197字符逐字保留。

原包CLI恢复exit0、source重新为7F732F...8ADC0A，UI OFF且无scanner child，随后主动恢复Note前台；正式scanner源码CDB3AB...2EAEC1未改。证据目录C:/Temp/AntigravityAA-browser-provider-root-skip-536-be6bd64b618e4cb8bd8ca6ba031cbeb6，含handoff、native-runtime-ledger.json、native-plugin-excerpt.log、package-byte-check.json、111分支/ABI/预检与CLI安装恢复日志。

## 公开 Fragment 原始编号的本机对比

证据等级：已跑本机验证、已跑隔离验证、已读公开契约。2026-10-08 隔离候选0E2519A41EE6406A79F8A2514FB7DCBE6496902DC9A6D9D2B27C0A19712385BB，VSIX02068C1195BAA4B8D03B6BE80477DC8394CAE8A262A90CB87D8E0C76840DD648。仅在前两次已证明失败的 exact root/实际 FirstChild 上，经原 core 三即时资源全部清理后，借用既有 Fragment.GetRuntimeId 做只读对比。失败 out 不读取；成功 SAFEARRAY 只读类型、维度、长度及 SDK append 分类，不输出编号内容，不拼完整 RuntimeId，不取得动作包装。首后代无论结果仍抛原 E_NOINTERFACE；其它后代与原完整绑定/PS尾不变。

完整方法172项、实际PS拒绝链36项、完整C#预检以及真实本进程SAFEARRAY20项在PS5/PS7/x86通过；独立审查复跑双引擎172、最终拒绝36、完整编译及x86 ABI/真实数组20，并核对最终源码/包哈希、8entries仅scanner改变、UTF8无BOM/CRLF及原PS尾字节不变。隔离包只供本机诊断，不是正式发布产物。

官方CLI安装exit0且安装源码hash一致。scanner PID168704、parent36856，04:51:39.312832+08启动，04:52:58正常Stop后CIM确认退出。实际94轮根与首子 raw均 S_OK、readHr=S_OK、VT_I4/dim1/len4/append=true/cleanup=true；对应core仍80004002，首子terminal=core-fail、match=false。它证明这两个provider的公开raw接口有返回，不能归结为整条provider接口不可用，也不证明相对数组可与目标完整编号直接比较。审批卡仍Waiting for user input、More actions折叠；实际CLICK_INVOKE/CLICK_PHYSICAL标记为0。

观察20:52:00.671Z—20:54:00.679Z共600样本、24条observed-process-resource（固定IDE35596）。本次将短无输入区间起止放在同一执行单元：20:52:33.728Z—20:52:44.133Z完整在deadline内，52个完整样本（33.880Z—44.083Z）均Note329822/读取前后稳定，cursor1322,865与lastInput36461609各仅一个值、读取无错误。顺序查询不是原子快照或输入来源识别；零动作拒绝中的稳定不能称真实审批、持续输入或scanner资源验收通过。Note原197字符逐字保留。

原包官方CLI恢复exit0、source7F732F...8ADC0A、UI OFF且无scanner child；随后主动恢复Note前台，正式scanner CDB3AB...2EAEC1和IDE原8项未提交内容未改。证据目录C:/Temp/AntigravityAA-browser-provider-raw-536-279300aafa8f4e6b8b3867278abef69d，含handoff、native-runtime-ledger.json、native-plugin-excerpt.log、native-restore-result.json、包/编码/红绿记录和实际observer绝对路径。

本机IDE resources/app/package.json声明Electron39.2.3，[官方发行映射](https://releases.electronjs.org/release/v39.2.3)为Chromium142.0.7444.175；这是本地声明和官方映射，未读取实际运行process.versions。相对编号与窗口宿主NULL的[公开接口契约](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-irawelementproviderfragment-getruntimeid)不提供本轮手拼完整编号的授权或证据。

## 当前注册命令目录的本机只读盘点

证据等级：已跑本机验证、已跑编译及有限mock、已读源码。使用独立GUID扩展D20609BC462724C3B460DBB38C02FA0F63042275D380510C63B37BF625F45ED0，TS E7F768116C63D27E348509CDA398DBB3F803A1BFBAEDD4726B5E077A0C08E341、JS89BF916E1F87F8414E298EFCF7D55F6361BE391BFBE9CB2DEB4EC74B0878AE52。原5.3.6插件未被替换，独立扩展仅onCommand激活，用Sky在原IDE命令面板执行自己的 AA 5.3.6 Command Directory (1a24e71ddd62)，回调只调用官方getCommands(true)并写自有输出通道。没有执行返回目录中的其它命令，没有读认证、改配置或启动scanner。

真实目录total2984/unique2984，关键词匹配64，输出62；两个匹配ID被ASCII白名单省略，unsafe2/complete=false。结果包含antigravity.acceptAgentStep/getBrowserOnboardingPort/showBrowserAllowlist等，但目录本身不证明公开的一次性批准目标参数契约；尤其不能排除未输出两个ID。后续将以有限ASCII转义JSON补齐，不把格式过滤的缺失当不存在。getCommands(true)只返回当前已注册且过滤下划线内部ID，不能声称覆盖所有隐藏或未来注册命令。

9组有限mock、TS/JS解析、API白名单与独立审查通过；VSIX6唯一entries/4payload同字节、UTF8无BOM/LF。官方CLI安装exit0、installed JS一致，执行后日志正常BEGIN/END；官方CLI卸载exact独立ID exit0并list确认不存在，原scanner7F732F...8ADC0A/JS2F85...2EA1AD保持、无scanner child、UI OFF、卡片pending、Note197字符exact并恢复前台。证据目录C:/Temp/AntigravityAA-command-directory-536-1a24e71ddd6245a190db18979c824d91，含native-runtime-ledger.json/native-command-directory.log和CLI安装卸载记录。

2026-10-07T21:05:26.1003561Z重新查三个公开API，GitHub最新v5.3.5，Marketplace及OpenVSX均5.3.5，Marketplace exact列表不含5.3.6；快照在CI-stage Temp/public-versions-f79.json。没有上传诊断包或发布5.3.6。

## 转义完整目录的本机补齐

证据等级：已跑本机验证、已跑有限编译/mock、已读源码。2026-10-07T21:32Z 使用独立GUID诊断包A6280C2DF920946138099406075B199F86F023F6532D8C3B81216180179D50BB，TS A421E6547F46039B1D710C0A7D9DFED9772C6531F8F14F2E2E65ED1FA9100735、JS3DD9AF04A7D1FD8DE08E396B73FDAFA74E8630AA9B5BB0020F8D895DA88F5B46。Sky命令面板只执行一次自有 AA 5.3.6 Escaped Command Directory (d4c2dce3e4f1)，回调只getCommands(true)，以ASCII转义JSON保留匹配ID完整字符串；无其它命令执行或scanner。目录total2986/unique2986、matched64/emitted64、nonString0/tooLong0/truncatedfalse/complete=true；先前62个ID全数保留，补齐两个：vscode-webhint/ignore-browsers-project（Webhint检查）和workbench.action.output.show.extension-output-fhgffy.antigravity-auto-accept-#1-Antigravity Auto Accept（插件日志通道）。两个新增ID名称不提供一次审批的目标参数契约。complete只指当前已注册非下划线关键词集合且通过本轮长度/数量边界，不能声称所有动态、内部或未来服务入口不存在。

有限9组mock、TS/JS解析、API静态白名单、独立peer审查及6唯一ZIPentries/4payload同字节均通过，未扩大回归或调用未知命令。官方CLIexact独立ID卸载exit0且list确认不存在；原插件source7F732F...8ADC0A/JS2F85...2EA1AD保持、无scanner child。随后Sky核对OFF/卡片pending并恢复Note329822前台，197字符逐字一致。证据目录C:/Temp/AntigravityAA-command-directory-escaped-536-d4c2dce3e4f1456f8f77c03eb2348d15，含native-runtime-ledger.json、native-command-directory.log、native-cleanup.json及安装/卸载日志。

## 独立 child 输入 A/B 诊断

证据等级：已读源码、已跑有限本机验证、已跑独立审查；远端四个fresh runner结果待验证。新增tests/child-startup-diagnostic.ps1与.github/workflows/child-startup-diagnostic.yml，只在当前codex/scanner-idle-audit分支的这两个path push时启动major5/7 × EncodedCommand/File四个独立job，每个只启动一次自有child32，无预热、自动重跑或continue-on-error。原required ci.yml和host-process.test.ps1 SHA776F1BBC...F4FDB9D9保持。脚本按冻结AST提取完整Assert-Host、Read-HostChildStage、原native编译/ABI与完整owned-loop，只改child命令输入路径并加时间/hash/失败旁证；原READY/exit10s、PID/path/native handle/退出259、精确stderr及PID+nonce三个stage条件/原三文件清理保留。每组为21项提取断言，不称原131项全量回归。File用CreateNew、UTF8 BOM及正文/字节回读，确认child退出后独立删除准确input.ps1；未知源或anchor先于child创建被拒绝。

作者本机四组各21通过，四组受控15秒延迟保留原10秒timeout/exit1并回收自有child；12项有限边界通过。独立review四组各21/exit0/stderr空、三stage删除/空目录删除、File输入删除通过，自有四PID均退出。独立正常首个PS5 Encoded用旧SHA32262B、其余三用日志保护修后0708107，没有重跑填绿；另外单独以持续stdout故障验证旧异常覆盖红→修后保留原异常绿，无原异常仍抛输出失败。修正仅增加一条2026-10-08中文说明及备用Console.WriteLine的try/catch{}，原函数/reader/assert/cleanup逐字保持；peer最终无P1/P2。Temp候选UTF8无BOM/LF，正式新文件依项目归一CRLF、内容除此一致：脚本D435CFF806983319BF6FBCF682E0C8AA4B9D3033BAF99246536EEE7B65D4670F，workflow DF932632E514EC3CCFF27D67DB2BA0C7CAEC25861AC31A21B1EF1A2961B88679。ROOT准确PS5/7解析均0，repository三项（strictUTF8/noBOM/CRLF、manifest、diff）通过；正式scanner CDB3AB...2EAEC1保持。

证据目录C:/Temp/AntigravityAA-ci-startup-ab-536-ecb8c35e2059461eade13b33c47e2d9f（作者handoff、每例result/stdout/stderr、root-formal-copy.json），独立审查C:/Temp/AntigravityAA-ci-ab-readonly-review-536-23ee03b3298d4a468f694570495a7750。原f79 PR首轮绿/push首轮PS5失败均保留，尚未定位原CI根因；A/B本机绿灯或未来单次runner差异都不能直接证明AMSI/base64/冷启动机制。此次不改变发布门禁，不合并或发布5.3.6。
