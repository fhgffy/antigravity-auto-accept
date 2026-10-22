# 资源稳定性与发布验收记录（进行中）

日期：2026-10-21 至 2026-10-22。证据等级分别为：已读源码、已跑验证；尚未确认的原因明确标作推测。

本轮运行版本合并为 5.3.13。当前公开版本仍为 5.3.12；5.3.13 尚未满足完整 CI 连续验证和发布闭环，不能据本报告当作已上线。

## 固定身份与证据位置

- 正式基线 5.3.12 VSIX SHA-256：a62d7cc64dc4079b86d597f9182cc6465a601e3b3b26c90ff47c41cadaf06a4d。
- 基线扫描器 SHA-256：b947655c5e16c21b16ba55c6712c710568539519ca7904c79400226902b163bf。
- 最终运行扫描器 SHA-256：d21ec58ba044540cff6991ec94950d2770038ff515ca178c35efe230f47695ee。
- 最终 TypeScript SHA-256：dc77196594441790fe2d719bdc8ed91bd5022eb9a7af0476cb4ce47040d01696；编译 JavaScript SHA-256：3328cb9898599e212a19460acddfa1036c0fc4266f7c09797c618f455a1fa9b1。
- 原生验收副本只替换独占互斥、关闭 15 分钟回收并在动作完成后记 QPC；扫描器 SHA-256：8fd943e689cbbe324914a48e9733f45e9494c89bb3ca16f85191e4d48b87c0b7。推导和逆向恢复见 native-final-test-package-derivation.json。此测试包不发布。
- IDE 2.5.5 完整测试副本的 EXE SHA-256：231d90772d0e26d4376e85bc35fb349c2341926cba84d800828791b33e1103ef。
- 主证据根：F:\CodexTests\AntigravityAA\resource-stability-20261021。
- 可信 12 后台复现根：F:\CodexTests\AntigravityAA\background-repro-20261022。
- 原始扫描日志另按字节归档；native-runtime-log-archive-manifest.json 保存原路径、归档路径和 SHA，不能因旧目录之后清理而丢失对应关系。

## A：基线、匹配对照及根因实验

已跑验证：三个独立测试配置，A 长会话 400 个 ListItem、563 个有效 UIA 节点；B 空闲对照 132 个节点；C 最小化。进程、创建时间、路径和 HWND 分组，已退出的代次单独退休，没有拼接曲线。

| 指标 | 基线 5.3.12 | 最终运行候选 | 结论与边界 |
| --- | --- | --- | --- |
| 匹配静态单核 CPU | 8.0805% | 约 2.791% | 降低 65.456%，超过 50%；使用无并行 UIA 观察器的 30–180 秒匹配窗口 |
| 单轮扫描 P50 / P95 | 264.98 / 317.51ms | 112.17 / 132.33ms | 基线为动态十分钟 760 轮，最终为匹配静态 150 秒 239 轮；不能把轮次分位直接当 CPU 改善 |
| 扫描器进程创建至 READY | 约 900ms | 869.777ms | 不是整个 IDE 启动时间 |
| 等待者私有内存 | 约 84.8MiB | 约 63.9MiB | 降低约 24.5%，未达到 40% |
| 真实终端审批 P95 | 出现区间下界 664.54ms，上界 755.07ms | 30 张卡合并上界 802.21ms | 最终上界仍小于基线下界加 200ms，即 864.54ms，按保守比较通过 |
| 第一小时句柄 | 基线短动态 695–729 | 517–656 | 基线与候选时段不同；不作精确降低比例 |
| 第二小时句柄 | 无同长度基线 | 517–528 | 同一 owner 的后续稳定区间 |

数据分别见 baseline-matched-summary.json、candidate-native-matched-summary.json、baseline-native-summary.json、final-native-timing-summary.json、final-native-first-61min-summary.json 和 final-native-second-61min-summary.json。

已跑验证：独立只读探针对齐 ControlView、名称、类型和完整 RuntimeId 集合后，比较托管查询、合并条件、COM 缓存与释放。第二版空探针自身 CPU 约 0.235%；托管现状 P50/P95 为 115.77/135.85ms，合并条件 55.74/71.41ms，COM 缓存 43.91/53.84ms。第一版探针反复 Process.Refresh 产生的 7.17% 观测开销已作为失败样本保留，没有用于归因。详见 probe-v2-summary.json 及对应原始探针记录。

已跑验证：COM 只读探针连续约一小时 7138 轮，私有内存约 72.45→74.38MiB。托管和 COM 对照说明查询方式、属性读取与缓存层的开销不同；它不能单独证明所有产品私有内存增长的内部根因。

## B：运行优化与长测

已读源码、已跑验证：批量缓存用于候选发现，减少重复全树查找；等待者在取得互斥之前不加载重型组件。动作前继续核对 live 元素、窗口/进程身份、完整卡片、精确目标和输入。初始化延后同时补充宿主接管初始化看门狗，避免 WAITING 免超时扩散到实际初始化。

回放夹具共六类。其中终端与窄栏浏览器来自脱敏原生快照；宽栏浏览器、通用、排除项和会话外终端为派生回归，不能称六类均为真实抓取。完整回归包含缓存失效/live 变化和提供者失败等边界。

### 两个独立的一小时时段

同一最终 owner PID 188216，没有刷新或重启：

| 时段 | 完整样本与时长 | 预热后私有内存 | OLS 斜率 | 判定 |
| --- | --- | --- | --- | --- |
| 第一小时 | 539 样本，3696.42 秒 | 87.309→96.066MiB | 11.781MiB/小时 | 失败，超过 10 |
| 第二小时 | 541 样本，3698.82 秒 | 96.066→96.418MiB | 0.443MiB/小时 | 该续测区间通过 |

第一小时第一次窄栏浏览器路径附近出现两次较大的私有分配阶跃；其关联不足以确认具体原生分配原因。第二小时的稳定不能抹掉第一小时失败，也不能外推为任意未来界面变化都不增长。

等待者的空 PS5 引擎、仅解析和实际等待分别做过对照；空引擎约 54.2MiB，仅解析约 59.4MiB。这是本机观测，不能宣称理论极限。GC 原型未达到 40% 目标，没有合并。正式包保留 15 分钟回收；没有用新的宽限值使验收变绿。

### 最终 M1–M5

native-final-M1-M5-summary.json 累计 47 次真实成功，43 次终端、4 次浏览器。按 PID/HWND/完整卡片/精确目标 SHA 联合去重，重复为零；都是单次允许，没有 Always Allow。

| 项目 | 结论 | 证据与边界 |
| --- | --- | --- |
| M1 单窗 | 通过 | A/B 及 72 个旧进程正常退出后只留 C；04:20:11 终端、04:25:20 浏览器各一次。M1-single-root-ready.json 与 C-m1-* 树、截图和日志 |
| M2 同窗多任务 | 通过；文件审批不适用 | B 有浏览器、终端待批和文件任务的历史证据。终端 04:07:18 一次 Submit；实际展开 Ran 工具后取得原始 stdout；指定文件内容按字节核对，文件工具没有产生权限卡 |
| M3 双窗及接管 | 通过 | A/B 两张不同精确目标同时待批，C 批准各一次。正常 Stop C 后 A 接管，再 Stop A 后 B 接管 |
| M4 三窗含最小化 | 通过 | C owner 最小化时处理 A/B，A/B 的新状态为 WAITING，结合 READY 和原生日志核对 |
| M5 待批生命周期 | 通过 owner 生命周期；补充宿主关闭边界单列 | 卡在 B，A owner Restart、Stop/Start 后完整卡身份保持；A 根 21528 正常退出、234756 重开，03:59:23 READY、03:59:25 对原卡 3260 一次 Allow Once。另测关闭承载浏览器任务的 B：历史保留但待批组件不恢复，不能把这个补充场景称为通过或归因为插件缺陷 |

初轮 M5 还使用实际 F24 长按验证菜单延期，日志明确 held-key；测试 finally 确认释放。两次测试工具失败与最终成功均保留，未更改产品输入保护。

最终 C、可信 12 的 D 和自有前台哨兵均正常关闭，74 个登记进程按创建身份确认退出，见 final-native-normal-close.json。19 份插件日志完成哈希归档。隔离配置和 IDE 副本的递归清理被自动审批拒绝，只返回 blocked by policy；没有执行删除或改用其他删除方法，目录保留。

## C：完整 CI 连续验证（未完成）

- e1cc04f 运行代码候选连续十次完整成功，第十一次 39642553316 在自有跨位数子进程十秒 READY 期限失败；尚未进入主程序阶段，原两流及阶段文件状态保留。不能将其归为 UIA 卡住。
- 随后的 070e6cf 和 2e67eae 各保留一次原 Framework64 csc.exe 编译启动超时。独立专用诊断未复现实际停滞，没有真实挂起转储。
- 933133d 的新增诊断暴露短命 worker PID 复用误报及跨磁盘 artifact 根路径问题，已分别修正；仍核对原 Node 退出和结果，证据先汇入同一独占根。
- bdc01bd 出现新增诊断元测试的 x86 外层超时；三个有界收集场景拆成独立测试，每例原 25 秒上限和全部断言保留。
- b371e47 完整序列两次成功，第三次 39670427448 在两个引擎的首次五秒转储收集失败；目标已 READY，收集器已正常回收且目标存活。失败 JSON 和 artifact 已下载，没有隐藏失败或计为成功。
- 程序集加载原型触发本机安全软件拦截，已整体撤回，失败源码和日志保留。此前宿主实现重新验证通过。新增普通、预编译的 x64 取证 EXE 供元测试显式调用，重复核对 PID、同一 .NET 创建时间和绝对路径，固定五秒等待并由原持有者回收目标；负例覆盖错误身份、已有文件和收集器停滞。实际超时的默认路径仍为独立 pwsh + Add-Type 最佳努力，不能把元测试优化说成默认路径已经优化。

a57b6ae 完成本地完整 npm test（host-wrapper 36/36）及新增 EXE 的独立审查；八项直接对照包括默认路径成功、身份拒绝和有界停滞。该提交连续十一轮完整绿色后，第十二轮 39687666275 在 PS7 7.6.6 的原十五秒 SelfTest 截止失败，PS5 通过，包作业未运行。原始日志仅到 bootstrap / source-read / scriptblock-created，不能据此判定具体系统或编译原因。

随后仅补超时取证：在已成立的十五秒失败后保存同一持有进程身份、源码、转储及两流，再由原持有者确认退出；取证失败不得覆盖原失败。新增红例在两引擎均复现缺少转储目录，补齐后两边真实 MDMP、身份、原失败与退出确认通过。手动诊断逐次复用同一包装循环，首次失败即停止，并上传本例独占目录。追加取证后的本地完整 npm test、仓库编码检查和正式 VSIX 八文件校验均通过；两个引擎各二十次原 SelfTest 通过。实际默认入口的受控停滞也保留有效转储、两流和原失败，SOS 能读出已知注入的 StartSleepCommand 栈，证明取证可用于定位；这不是云端故障的根因证明。8ba6193 的 PR 完整 CI 通过；push 39702126343 的 PS5 在新受控转储元测试中生成零字节文件而失败，目标已输出完成标记并处于人为停滞，身份、两流与退出确认正常；这与真实 SelfTest 停滞分开记录，尚不足以判定具体 API 阶段。

该提交的新代码首次独立窄审发现循环 finally 落盘异常覆盖原错误；两引擎新红例复现，修正后正文失败、记录失败和两者同时失败六项均通过，均在第一轮停止，记录异常另行报告。修正后的本地完整 npm test 通过（host-wrapper 42/42）；8ba6193 手动运行 39705375838 的 Windows 2022/latest × PS5/PS7 四组诊断均成功，其中原 SelfTest 共八十次通过；同次正常 PS5 作业却在 x86 宿主元测试原二十五秒外限失败，两流为空，故整个运行仍失败。证据见 manual-8ba6193-39705375838；不能把四组成功计为完整 CI 或根因证明。

补充本机定向回归捕获夹具启动模块列表暂时不可用，初始 MainModule.FileName 为 null；新红例在两引擎强制该边界，夹具改为明确保存 ExpectedImage（预期启动路径），实际映像仍由超时采集器在动作时读取并严格比对。异常优先级和启动预期元数据共十项定向通过；最终完整 npm test 亦通过（host-wrapper 42/42）；失败转储头断言也保留原外层两流，避免只剩空头断言。新连续序列尚未完成，正式运行 PS/TS 未改变。仍需新序列连续二十次完整两引擎和包验证。每个序列的 series.json、完整日志和首次失败都保留。历史专用二十轮宿主诊断不能冒充二十次完整 CI，最初编译器/CLR 启动偶发原因仍未确认。

f41ee74 的 push 39706528061 再现真实 PS7 SelfTest 十五秒超时，且失败后启动的 pwsh 取证器也在原五秒期限到达，无转储文件；目标退出和两流完成仍确认。同头 PR 39706532480 完整成功，两次完整日志保存在 ci-f41ee74。这说明当前诊断冷启动也可能失去现场，不能据此认定自测的具体停滞阶段。

本次将 CI 的取证器在被测子进程启动前编译为普通 x64 EXE，保留原编译十五秒、SelfTest 十五秒、取证五秒及全部失败断言；每次构建记录源码和工具 SHA。正常与手动作业都显式传入已准备路径，本地未传参数时仍为原 pwsh 最佳努力路径。两引擎实际入口参数转发先红后绿，受控停滞的实际入口保留有效 MDMP、原失败、完整两流及目标/收集器退出；完整 npm test 通过（host-wrapper 42/42），新功能首次独立窄审无 P0/P1/P2。证据为 prepared-collector-forward-red.log、prepared-collector-forward-green.log、prepared-collector-real-wrapper-controlled.log、prepared-collector-full-test.log；这是增强取证，不是云端根因修复。

另外在私有测试根验证外部观察原 Node 子进程的方法，保持原 spawnSync 命令及二十五秒期限；仅对已核对 PID、创建时间、映像和父进程的本例目标采集。正常两个原案例通过；人为二十秒停滞在约 10.103 秒保存有效 mini dump，原测试仍于原期限内返回，观察者不停止目标。这一私有原型尚未加入 CI，没有真实云端故障栈，不能作为根因结论或二十次完整 CI 验收。

3a58c11 的 PR 39708251565 完整成功；push 39708247468 的真实扫描器自测通过，但 PS7 人为停滞的取证元测试仍在五秒到期，生成零字节转储。原目标已写入完成及注入前标记，收集器也退出确认；原始两 run 与 artifact 在 ci-3a58c11。提前准备 EXE 没有消除这一独立诊断失败，不能据零字节文件断言卡在具体原生 API 内部。

下一层仅补取证阶段旁证：工具进入、身份核验、文件创建、句柄准备、原生返回及文件关闭完成，原生错误码在任何旁证 IO 前立即保存。阶段缺失仍为未观测，原 0x1124 参数、五秒上限和严格 MDMP/退出/两流断言均保留。三调用者新增断言先因缺少阶段文件失败，补齐后十二个定向案例通过，完整 npm test 亦通过（host-wrapper 42/42）。默认 pwsh 路径的同次有效 1.60MB 转储和五阶段文件另外核对；首次私有门脚本误把 Console 直接输出当作 PowerShell 管道值而报错，原文件及退出确认独立检查通过，没有重跑目标来抹掉该门错误。当前仍没有真实云端挂起栈或根因结论。

0b587c2 的 push 39709840452 完整成功，PR 39709845990 在 x86 外层原二十五秒期限失败。该次已经输出 ENTERED/CHILD_READY，转储 310,097 字节且阶段完整、原生返回 0，外层未输出收尾结果；范围缩小到外层执行/收尾，仍无具体根因。该头手动 39710700869 的两引擎和 VSIX 成功，但三组既有启动诊断在五分钟内取消，整个 run 为 cancelled；Windows 2022/PS5 的二十次原 SelfTest 全通过。一个取消组记录 npm ci 约四分钟，包作业的安装与打包也分别耗时约五、七分钟；另两组只有步骤标题，不能据此断言 npm 已启动或判定具体网络请求。原日志和摘要在 manual-0b587c2-39710700869，不计为二十次完整 CI。

新手动观察作业保留实际验证前缀和完整原 Node 测试，超过八秒才对本例父链、PID、创建时间与映像核对后的 PowerShell 进行旁路取证。独立读栈进程固定五秒，使用本机命名管道只读 GetCallStack，未发送断点或暂停命令，目标仍由原测试收尾；原有转储也保留。观察器自身另有一百八十秒总预算、作业五分钟预算，触发时是诊断失败，不能计作原流程成功或完整 CI。新增入口标记及本作业 npm verbose/timing 日志用于区分脚本入口与安装等待；没有关闭审计、改重试或增加原时限。

新功能首次窄审发现一个 P2：观察异常会提前中断原 Node，落盘失败会遮盖其原错误。真实 Node/文件 IO 红例分别复现；修正后查询故障时原测试继续二十秒并退出 0，原失败与落盘失败同时出现时优先保留原测试失败，诊断失败仍单列。修后两次固定 x86 目标的受控案例实际读出目标 Start-Sleep 语句、原 Node 均在原二十五秒内完成；读栈器错误创建时间、错误映像及错误父 PID 三个负例均拒绝、目标存活并由原持有者收尾。完整 npm test 再次通过（host-wrapper 42/42），文件与阶段回执在 host-callstack-repo-control-final-*、host-observer-fault-green-final.json、host-observer-reader-identity-negatives 和 host-observer-fixed-full-test.log。未做同范围修复复审。新云端观察仍待验证，原始 SelfTest 和宿主偶发超时根因未确认。

afa92d0 的 push 39714135354 在创建任何作业前失败，GitHub 注释明确为新增 job 级 env 使用了该层不允许的 runner.temp；不是原测试超时，原失败与 jobs=[] 已保留。将该 env 移到允许 runner 上下文的实际步骤，本地固定版本 actionlint 复现一个语义错误后检查通过。另加独立 Workflow lint 工作流，在主 CI 文件无法创建作业时仍可检查全部工作流；工具固定官方版本及 SHA-256，权限只读，作业五分钟。此补充没有改动运行或测试脚本，已有完整 npm test 的功能源码字节未变；配置专项语义、YAML、Bash 语法及仓库检查另行执行。Ubuntu 新检查和修正后云端观察尚待通过，不能把本地 YAML 可解析称为 GitHub 配置可执行。

e718587 的 push 39714938769、PR 39714943896 两次完整 Windows CI，以及独立 actionlint 的 push/PR 均成功；Ubuntu 侧实际下载、SHA 核验和 Bash 执行已完成。原日志和元数据在 ci-e718587。

同头手动 39717129869 全部成功：四组原 Node 全文测试、四组固定 x86 控制读栈以及四组各二十次原 SelfTest/编译启动均通过。SelfTest 共 80/80，四组最大值分别为 670、1421、554、1396ms；这些重复仍不是二十次完整 CI。完整日志、八份 artifact 与 summary.json 在 manual-e718587-39717129869。

该次真实 x86 包装器在启动超过八秒后，被读到停在 Save-HostTimeoutDump 最后回执的 ConvertTo-Json 语句；该例最终成功。此前 0b587c2 的失败已证明原生转储成功、外层未收尾，这次栈将一个实际慢点缩到报告路径；没有把成功例的栈冒充原失败那次的栈，也不能据此归因为 #34 的原 SelfTest 故障。该诊断边界单独登记 #35。

回执仅有固定字段，现以无命令模块的编码保留同一 JSON、null、整数和布尔契约。禁止 JSON 模块自动加载的三个实际引擎各两例先因缺回执失败，修后六例通过，含引号、反斜杠、控制字符、中文和非 BMP 错误原文；原 25 秒外限、五秒收集、身份/退出/失败断言未变。完整 npm test 通过（host-wrapper 48/48），证据为 dump-json-autoload-red.log、dump-json-autoload-green.log、dump-json-full-test.log。

旁路本身原先也会加载 Utility：禁自动加载的控制首先暴露 Get-Runspace 命令不可用，保留 red 与首次 green 失败。读栈改用核心运行时的只读 RunspaceList 属性和 CLI XML；没有设置断点、暂停或修改目标状态，不在目标加载 Utility。该内部只读属性已在实际 PS5/PS7 核对，缺失会明确失败，不作生产依赖。私有控制样本只替换原夹具的 executable 一行，分别对 PS7、PS5、x86 PS5 真实目标读到 Start-Sleep 语句，原 Node 及持有者正常退出；这与原固定 x86 控制的调用者标签分开。证据 dump-json-reader-final-PS7/PS5/PS5-x86，新的云端版本仍待验证。

原受控 x86 DMP 的系统/线程上下文为 x64 收集器生成的 WOW64 形式；dotnet-dump 两种位数及 CDB 逐行命令都未得到可用的托管栈，不能凭工具退出 0 称成功。官方签名工具改用包范围提取，原整包下载超时保留；没有安装或改全局 SDK。另从原 0b587c2 的 inner x64 DMP 读到预期 HostWrapperOutput.Main/Thread.Sleep，只证明内层在等待，不是外层根因。相关原日志、签名清单和 wow64-dump-architecture-audit.json 在本轮根目录。

8604179 的独立 lint 两次通过，PR 39720788867 完整成功；push 39720783516 的真实扫描器通过，却在 PS5 人为停滞的取证元测试失败。原 5 秒收集器退出已确认，零字节 DMP 最后阶段为 handles-ready，没有 native-returned；该界限还包含首次原生库加载，不能径直称为 MiniDumpWriteDump 内部死锁，更不能说 JSON 修复消除了此独立故障。完整日志与原 artifact 在 ci-8604179；故障源仅 322 字节，不是生产 SelfTest。

针对 #34 的原 SelfTest 停顿，在原 15 秒失败成立后、原持有者停止目标之前，复用有界只读栈工具，再执行原转储。其独立读栈进程至多等待 5 秒并单独收尾，原 SelfTest 循环及 15 秒判定逐字未变；取证失败仍不能遮盖原失败。两个引擎的新增断言先因缺少 selftest.callstack.json 失败，接入后均读到受控 Start-Sleep 60，原失败、MDMP、身份、两流和退出断言都通过，耗时约 18 秒，原 35 秒元测试外限保留。读栈启动失败与退出 1 的两项真实进程故障对照也保留有效 MDMP、活目标及最后原持有者退出确认，见 selftest-callstack-reader-faults；这是提高现场信息，并非原 SelfTest 根因已定位。 修后完整 npm test 通过（host-wrapper 48/48），7 个功能/运行文件起点哈希一致，正式测试 VSIX 八项、编码及函数边界检查通过；最终本地回执为 selftest-callstack-final-local-validation.json。

5fa51f6 的 push 39722205571、PR 39722212147 均完整成功，两个独立 lint 也成功，原日志和元数据在 ci-5fa51f6。它们验证最新读栈接线在云端正常执行，未触发原 SelfTest 停滞，不作为根因修复证据。

针对独立的 #36，在同一短命收集器中显式从 System32 加载 dbghelp.dll，再解析 MiniDumpWriteDump 导出，并分别记录进入/返回阶段；原 P/Invoke、0x1124 标志和五秒期限未变。六个正例先因缺少阶段失败，修后十一阶段全部符合；私有真实目标的缺库 126、缺导出 127 两例保留立即取得的原错误码、目标存活及最终原持有者退出。完整 npm test 再次通过（host-wrapper 48/48），测试前后九个功能/运行文件哈希一致。原日志为 dump-native-load-phases-red/green.log、dump-native-load-full-test.log，故障旁证为 work/dump-native-load-errors/summary.json。此改动用于缩小后续停顿边界，尚无原云端故障的加载/导出阶段，不能称为其修复。

另一方法 WCT 已在自有互斥等待进程做实际控制：三种原样查询均只返回目标阻塞线程，没有识别已知互斥和所有者，故标记未验证、不接入 CI；没有调整权限。首次私有断言失败前未保存原返回节点，第二次已先保存原始 JSON 再判断，保留 KnownChain=false 和目标正常退出，见 wait-chain-controlled-proof-follow.json。不能将 API 返回成功当作已定位等待链。

这批六文件新诊断做了一次独立首次窄审：未发现有依据的 P0–P3 新缺陷；另独立检查三个实际引擎的语法、六文件编码/换行、JSON 转义以及差异边界。该结论不覆盖旧运行优化、WCT、云端根因或整个分支的合并门槛，未追加修复复审。记录在 work/diagnostic-module-boundary-first-review.md。

b2876f4 的 push/PR 与两个 lint 均通过，手动 39724780097 亦完整成功：四原 Node 全文及四固定 x86 控制通过，四组 SelfTest 各 20 次，最大 725/1379/754/1272ms；各二十次编译最大 156/182/163/193ms。八 artifact、原日志和逐 JSON summary 在 manual-b2876f4-39724780097。实际 2022/7 的 slow7816 只得到空 Runspace1 帧，原例约 9692ms 最终成功；不能将其当作定位栈。固定头串行控制器已有四次完整绿，随后为共享完整矩阵主动停止新派发；退出 1 的原因是自设 stop flag，不是测试失败，全部结果在 ci-series-b2876f4 保留。

新增 #37 的完整矩阵将原 test/package job 移入唯一只读 reusable workflow；结构深比较确认除两 artifact 名称加可选后缀之外，所有 job/step 期限、步骤正文和断言保持原样。普通 ci 调用同提交该流程，publish 仍在外层，仅 needs 改为整体 validation；全部发布步骤相同。现有 CI 手动 complete_stability 选项的二十组分别通过两引擎后打包，独立 artifact 后缀、fail-fast=false，不传凭据、不进入发布。两个门检查先红后绿，当前四份 workflow 的 actionlint 通过；最终固定源码完整 npm test 已通过（publication 56/56、host-wrapper 48/48），十二个功能/配置文件起点哈希一致，正式测试 VSIX 八项通过。新配置首次窄审无具体 P0–P3；后续默认分支入口修正按官方说明由作者自审，矩阵对象只多显式手动条件，未追加复审。原本新建独立手动 workflow 在默认分支注册前无法分支派发，现改用原有 ci.yml 的默认 false 选项，入口一红两绿、最终四 workflow 语义检查通过。该段记录矩阵派发前的本地状态；实际云端结果见下面的完整矩阵失败记录。最终本地回执见 complete-ci-matrix-final-local-validation.json。


### 2026-10-22：首个完整矩阵真实失败与下一步取证

【已跑验证】de1735c 的 push/PR 与两 lint 通过；手动完整矩阵 39728103877 已完成，二十组各按两引擎及打包联合判断，17 组全绿，3/6/14 失败，无取消、重跑或隐藏失败，不能验收为二十连绿。批量 gh 日志命令因六十 job 超过客户端请求上限，改逐 job REST 取得全部六十份执行日志；这是归档方法失败，与 CI 失败分开。原 metadata、完整分类、日志 SHA 清单在 complete-matrix-de1735c-39728103877。

- 样本 3 / PS5：原 25 秒 x86 诊断在 CHILD_READY 后超时，未观测到收集器进入，不能套用后面的原生调用原因。新禁止命令模块自动加载对照，三个调用者都在 Join-Path 红；仅两个路径改 IO.Path.Combine 后绿，Management/Utility 始终未加载。修复的是已复现的多余冷加载依赖，不冒充原 25 秒失败根因。
- 样本 6 / PS7 调用者：真实启动协议的 Windows PowerShell 子进程撞原 20 秒 spawnSync 截止（#38），原测试提前断言，没有两流/栈。新精确源码过滤的只读观察器保持原命令、源码及期限；旧过滤器控制缺栈红、新控制可读 Start-Sleep 20 且原 Node 0、两流完整、清理空；错误来源路径不会捕获。手动诊断二十个新 VM 保留原前置步骤、控制后置，不能算完整 CI。
- 样本 14 / PS5：原人为等待夹具的收集器 5 秒失败，DMP0；最新阶段已明确系统库和导出均成功返回 0，随后没有 native-returned。边界缩到 P/Invoke/原生写入，但没有具体等待栈，#36 仍开。失败后以同一预编译 EXE 对该收集器自身另写最小栈，额外工具有独立 1.5 秒预算，原目标完整 0x1124、5 秒、JSON 契约及原失败不变。

新增收集器栈三个调用者先因缺 sidecar 红，首次实现保留两种新失败：系统自动加 AVX 上下文位，原断言错误地把文件头当原请求标志；32 位调用者读取 64 位 MainModule 为 null。已改为核对禁止完整数据/句柄流、仅允许系统 AVX 位，并用已知可执行路径让 64 位工具再次严格核验真实身份。原来小于 8 秒的阈值没有改；三绿耗时约 6.14/5.87/6.48 秒。证据 collector-self-stack-red/green/green2.log。仓库源过滤控制原 Node 21.094 秒正常结束，明确 Start-Sleep 20、读栈退出、无 DMP 和空清理错误，lifecycle-observer-repo-control。以上属于诊断能力和已复现依赖修复，原 #33/#34/#36/#38 根因仍需云端证据。

PSModulePath 另作单变量 Node 桥接对照：继承 PS7 环境的 WinPS 选择 PS7 模块清单，移除仅子进程 PSModulePath 后选择系统 WinPS 清单；两者真实 Add-Type/Join-Path 均成功（562/610ms），未复现超时。官方路径规则支持环境差异，但不能由清单路径差异推断当前超时因果；未改运行代码或全局环境，原始回执 psmodulepath-node-bridge-control.json。

【已跑验证】本批最终完整 npm test 通过（publication 56、lifecycle 38、host-wrapper 51、mouse 两引擎各188、concurrency 22），16个功能/配置起点哈希完全相同，测试 VSIX 八项通过。旧 host 观察默认模式控制仍取得明确 Start-Sleep 20/有效DMP/原Node0，生命周期模式不产生DMP。附加工具不存在与自身停滞两个真实故障均保留原五秒超时、活目标、原所有者退出，耗时5119/6051ms；自身停滞的附加工具约1033ms确认回收。首个私有故障对照因遗漏夹具必需PIDFILE环境而无效，保留原记录，补齐后才计两项通过。CDB从最小控制DMP读到预期clr!Thread::UserSleep，只证明取证可读，不是云端根因。九个新源码/配置首次独立窄审无具体P0-P3，仅静态检查；服务在输出阶段容量错误后同一审查者只整理原报告，无修复复审。最终回执 collector-lifecycle-final-local-validation.json，报告 work/collector-lifecycle-first-review.md。

### 第二个完整矩阵与原生 x86 取证

【已跑验证】d2f3cd5 的四次普通 push/PR/lint 原始运行均成功，八份实际作业日志与 SHA 清单在 ci-d2f3cd5。唯一手动运行 39738725656 最终结论为 cancelled：二十组完整两引擎/包中十九组成功，样本18的PS7调用者失败；另有三个诊断作业撞五分钟上限取消。完整原始82份执行日志、原始ZIP及核验清单在 diagnostic-matrix-d2f3cd5-39738725656；没有重跑失败或把十九组计作二十组。

样本18的原 x86 wrapper 在25024.9ms触发spawnSync原二十五秒截止，stdout/stderr均空，第一个DUMP_DIAGNOSTIC_ENTERED也未出现。只能界定为首次标记前或标记初始编码操作内的启动边界，不能归因尚未观测到的转储函数。生命周期诊断为17个作业成功、3个取消；取消中2个实际套件未启动，1个实际套件与后置控制均通过但总时限已到。一个实际慢进程的只读栈记录在目标退出后返回not running，原套件9564ms成功，此空栈不算根因现场。#33/#34/#36/#38仍未定位完整根因。

【已读源码、已跑验证】旧x64工具取得WOW64转储不等于x86上下文可分析。新可选--x86仅用原64位csc准备同位数工具，不在原目标前运行32位进程；默认x64和原0x1124写入参数、五秒限时、身份保护不变。真实控制先因SystemInfo architecture9红，修复后原生Intel0绿；x86 CDB从独占Sleep控制读到StartSleepCommand.Sleep/ProcessRecord和托管管道，部分非托管线程的clrstack错误如实保留。真实观察器控制原Node0、两流完整、空清理错误且DMP为Intel0。证据 native-x86-collector-red/green.log、native-x86-observer-red/green、x86-native-stack-cdb-control.log和x86-native-managed-cdb-control.log；这些只证明取证能力。下一轮先取启动现场，不盲重开完整二十组。

三个手动诊断作业的npm请求默认等待五分钟，与整个作业五分钟上限冲突（#39）；普通push打包的npm ci也曾约五分五秒后成功，原上游请求身份仍未知。使用云端同版npm10.9.9/Node22.23.3的回环控制：审计延迟使原1800ms外层失败，单请求400ms后同一安装1248ms成功且Bulk/Quick都仍尝试；必需tarball返回503仍844ms退出1。首次两个Python原型因配置路径重复及未建立预期请求而无效，全部保留。候选仅收紧三个手动作业到单请求10秒/不内部重试/记录timing，保留审计、必需下载失败、原五分钟和普通CI；静态配置先红后绿，实际云端门仍待验。证据 npm-audit-node-loopback-required-boundary.log、manual-network-budget-red/green.log。

首次五文件窄审发现P1：新测试对共享系统映像的收尾不能仅凭PID/路径。已用独占复制夹具先复现，再要求创建时间字符串并持有Process句柄后同时核对身份；缺失/错误创建时间必须拒绝且目标仍活，由原ChildProcess所有者最终回收。cleanup-creation-identity-red/green.log保留红绿；此前完整测试因修复后源码变化已作废。修复后重新完整npm通过：publication56/lifecycle38/host-wrapper53、mouse两引擎各188、concurrency22，17个源码/配置哈希全程相同；测试VSIX八项通过，actionlint及diff检查通过。最终回执 native-x86-budget-final-local-validation.json；观察器实际控制DMP也经x86 CDB读到Sleep/ProcessRecord（native-x86-observer-green-cdb.log）。正常CI、共享完整核心、运行字节、原测试主体及全部截止与d2相同。无修复复审循环，首审报告 work/native-x86-budget-first-review.md。

### 原生 x86 观察原结果及独立寄存器旁证

【已跑验证】2b22aaf 的四次普通CI原运行全绿、8份执行日志归档ci-2b22aaf；随后唯一手动39747161643未开完整矩阵/生命周期选项，20个host观察18成功/2失败，4个启动诊断和3个普通验证作业成功，无取消，共27份执行日志。三个失败后步骤也没有把作业改绿。原ZIP SHA/CRC及成员路径均核验；首次长路径归档在Windows MAX_PATH失败后，同次ZIP改用 F:\CodexTests\AntigravityAA\cloud-x86-39747161643\数字产物ID 提取，映射在short-artifact-locations.json。恢复只读归档，不是重跑CI；旧不完整目录/错误也保留。

两个真实失败都未放宽：windows-latest/7/5新增native32 positive的原5秒DMP为0，库及导出成功后无native-returned；windows-latest/7/2原scanner强制timeout案例的目标DMP与备用收集器自身最小DMP均0，备用工具1309ms超时且退出已确认。后一现场使只换另一个DbgHelp进程仍不够这一限制可见，#36具体等待位置仍未知。另一个实际x86启动slow5528最终14.25秒成功；原生Intel上下文经微软x86 CDB和匹配4.8.9363 DAC可读，线程0位于GlobalConfigReadInt、ServicePointManager配置、Runspace及ConsoleHost创建链。它是慢但成功现场，不能外推成二十五秒失败的根因；完整日志cloud-x86-slow-5528-cdb.log保留非托管线程错误。

【已读源码、已跑验证】新增候选只在已判原5秒失败后的自有收集器最小栈工具中，先用kernel32保存同位数CONTEXT、至多一页栈和模块表，再尝试原最小转储；不依赖DbgHelp，既有1.5秒附加预算不变。对每条线程先核对归属、暂停一层，在finally恰好恢复这一层后才写旁证；至多16条/400ms循环，不声称覆盖全部线程。原目标完整Write函数字节、0x1124、原截止、JSON及失败断言未改。布局和暂停要求对照[微软CONTEXT](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-context)、[x86布局](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-context-r2)和[GetThreadContext](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getthreadcontext)。

原collector-stall三个调用者先因缺.tsv旁证红，再3/3绿，仍要求有效最小MDMP及原耗时小于8秒。独立真实x64/x86工具控制分别515/547ms，在原1.5秒预算内返回；16条上下文分别1232/716字节，寄存器IP可对应ntdll模块，目标仍活并由原Popen句柄持有者最后退出。证据 collector-raw-context-red/green.log、collector-raw-context-bitness-controls/summary.json。原native32案例也转发同一x86工具，失败时采它自身旁证，不延长原期限。首次窄审未确认P0-P2；P3为线程自然退出可能截断旁证的源码假设，未作故障注入，明确保留为非阻塞限制（无END不得接受为完整控制）。首审报告work/collector-raw-context-first-review.md，无修复复审。新完整npm通过publication56/lifecycle38/host-wrapper53、两引擎mouse各188、concurrency22；17份源码/配置未变，VSIX八项通过，编码/diff/原期限和Write字节检查通过，回执collector-raw-context-final-local-validation.json。这些控制仍非云端根因修复。另24个原云端手动前缀均成功、最长100秒、无取消，生命周期scope本head未派发；manual-network-prefix-original-39747161643.json保留边界。

### 自然退出观察竞态与前置失败后的校准

【已跑验证】c90813b的四次普通push/PR/lint原始运行全绿，八份日志在ci-c90813b。唯一手动39752711623未开完整样本选项：生命周期20/20成功，host观察16/20成功，四个启动诊断和三个普通验证作业成功；47份执行日志及全部ZIP/SHA/CRC保留在diagnostic-matrix-c90813b-39752711623。四个失败逐项保留：119736971339在原前置lifecycle20秒截止，host实际套件未运行；119736971453/1557原Node均0但观察器GetProcessById遭遇正常退出竞争；119736971678实际Node0，后置x86 Sleep20控制撞原25秒，DMP为有效Intel0。这不计二十次完整全绿。

【已读源码、已跑验证】#40的候选只对GetProcessById的ArgumentException再次用一秒CIM确认PID消失；仍存在或查询失败继续抛错。确认退出时保留原PID/创建时间/reason，后续目标仍须原父PID/创建时间/映像检查；原Node失败优先、全部截止和原用例主体不变。真实自有已退出进程旧调用两红，新helper两绿；新增用例同时要求活进程正常返回。工作流另仅在原前置步骤之后加!cancelled()，让前置失败后的校准仍能编译同位数工具，不提前预热原测试。条件检查红绿日志保留。首次独立审查无确认P0–P3，另实跑两引擎各四种lookup/查询错误边界，无修复复审；work/observer-confirmed-exit-first-review.md。

【已跑验证】本轮完整npm通过publication56/lifecycle38/host-wrapper55、两引擎mouse各188、concurrency22；17份源码/配置哈希全程未变，VSIX八项通过。红绿、编码/CRLF、diff、原生primary Write/期限/运行字节不变的汇总为observer-confirmed-exit-final-local-validation.json。原前置lifecycle缺栈和真实原生收集器停滞仍未定位；不因诊断器修复宣称#33/#34/#36/#38消失。

### 不连接目标远程会话的原生轨迹方法

【已跑验证】d557fa8的四次普通push/PR/lint原运行全部成功，八份执行日志在ci-d557fa8；#40修复仍不表示未知启动根因解决。失败的后置5572控制原生转储已由x86 CDB/匹配4.8.9345 DAC读到线程0在WaitOne、ExecuteCommandAsyncHelper、ConsoleHost.DoRunspaceInitialization；另有AnalysisCacheData.Cleanup和PSRP协商线程。读栈进程在五秒截止，原实际Node已0；这只是校准初始化阶段旁证，且连接目标远程会话可能引入额外协商工作，不能反推原生命周期或collector等待原因。cloud-x86-failed-control-5572-analysis.json保留此边界。

【已读源码、已跑验证】下一候选增加默认关闭native_startup_trace，仅显式手动运行传入共享核心，在GitHub临时WindowsVM记录GeneralProfile ETW，覆盖原前置和后续真实宿主；不连接目标PSRP，普通步骤主体/顺序/预算、稳定性样本和发布门保持不变。记录唯一实例意图后再启动，失败也按同一实例save/cancel，不作全局取消；原生工具使用[微软实例参数与skipPdbGen语义](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options#instancename)。本机非管理员，不提升权限、不录用户系统。已本机只读导出配置，确认CSwitch/ReadyThread/DiskIO及相应栈；实际ETL解析和丢事件核对须以云端原件为准，仪器样本不计C完整连绿。

两引擎假WPR依赖回放各七项、共14项成功，覆盖start/save/cancel错误、无意图、坏身份及拒绝非hosted；这些是假工具边界，不是原生ETW能力通过。首次独立审查发现P2：可选大ETL上传无独立预算且挡住原失败产物。边界检查先红后绿，修复为先上传原失败产物，再以一分钟上限上传ETL；新增四步均一分钟，原job十五分钟不变。原审查与一次修复保留在work/native-etw-first-review.md，无修复复审。静态actionlint、两引擎AST和剥离新增项后整个YAML等值检查通过；原始控制在native-etw-workflow-controls/summary.json，来源不变量在native-etw-original-core-invariance.json。完整npm/VSIX以本候选最终回执为准，尚不宣称云端已记录成功。

【已跑验证】da62b56的四次普通push/PR/lint原始运行成功，八份执行日志归档ci-da62b56。新原生诊断唯一39767767716在两引擎及包三个原作业全绿，两边WPR起停/保存/上传都成功；这是带仪器样本，不计C。Go API读取ZIP首次HTTP2 EOF，换HTTP1取回第一包，但第二包仍EOF；保留全部不完整文件和错误，改原生curl用同一产物临时重定向URL续读，未读取账号令牌、未重派CI。两个原ZIP均与服务端SHA一致且CRC/成员安全检查通过；原ETL833617920/920649728字节，原日志/ZIP/映射在native-etw-cloud-39767767716。

官方TraceEvent4.0.0离线解析两份ETL均EventsLost=0，包含CSwitch/ReadyThread/DiskIO/StackWalk/CLR。自有原45秒夹具PID2648/创建身份与父PID核对：wall45023.7764ms、主线程CPU27.7664ms，ExecutionDelay44978.7964ms，唤醒后0.0199ms调度；4374条栈按FrameCount逐帧核对、最大127帧。native-wait-control.json只证明已知控制可读，不是未知启动根因。首个通用PayloadNames解码只列前四IP，短于四帧还产生额外槽；已用专用InstructionPointer逐帧读取，旧不完整解码保留，失败校验及修正均记ledger。第二个校验原先误用枚举名DelayExecution，已按实际TraceEvent值ExecutionDelay严格核对，43秒控制阈值未改。

【已读源码、已跑静态验证】下一轮将现有ETW开关透传到已有20组共享核心，仅显式开启时命名Native trace CI；关闭仍为Complete CI，所有原步骤、两引擎/包、产物隔离和期限不变。此轮只为覆盖实际偶发故障的前置和宿主现场，带仪器的全部样本不计无仪器二十连绿。透传检查先红后绿，首次窄审无确认P0–P3，105个可能产物名无冲突，无修复复审；work/native-etw-matrix-first-review.md。批量先解析进程/线程元数据和丢事件数，只对实际故障身份展开全量事件，避免复制数十份冗余JSON。新的完整本地测试/包以本候选最终回执为准。

### 2026-10-22：真实SelfTest冷编译现场与依赖拆分

【已跑验证】a5611a1唯一带仪器矩阵39773923275原attempt1有61个执行job成功、1个失败；sample18 PS7 SelfTest仍按原15秒失败，依赖的包被跳过。62份完整原job日志已核SHA；原失败ETL399507456字节、SHA5c127428221f85915795df143cf61a4f0875168d97c853f8d0c99f6ebbada5cc，报告EventsLost=0。PID6724、创建ticks639282672833761378，原生命周期15.5585374秒，最后95通过/退出0不能覆盖已成立超时。没有有效DMP。

官方TraceEvent4.0.0 ThreadTimeStackComputer重建后按严格进程栈根及pipeline TID1216筛选：硬缺页区间并集12.9328478秒，其中Microsoft.CodeAnalysis.dll为4.0811117秒、Microsoft.CodeAnalysis.CSharp.dll为6.9909093秒；CPU样本约0.9007秒，等待CPU0.0141秒。该线程大部分时间被编译依赖的缺页IO占据，不是凭模型自述归因。所有线程指标不能累加为墙钟时间；早期手工聚合未截断已退出线程且Any-PID误选相关进程的结果已标为无效，不能引用。原ETW及严格分析在native-etw-matrix-cloud-39773923275，原生解析的实验性边界保留；不将本次证据外推到旧#33/#36/#38或所有历史SelfTest。

【已读源码、已跑验证】最小候选让纯规则SelfTest跳过不需要的Add-Type和UIA加载。原C#文本和正常扫描初始化顺序逐字不变；87项纯判定留原入口，原8项窗口归属输入和真实C#调用迁入已有mouse-helper测试，并增加零target及零expectedPID两例。没有虚报同进程执行95，也没有删除或放宽原断言；原十五秒、stderr/exit/完成协议仍严格保留。新禁止Add-Type的真实两引擎先2红，再与禁止桌面getter共4绿；八个原生守卫逐一改坏，两引擎16个变异均被新归属断言拒绝，2个未改动控制成功。私人变异脚本首次命令超过Windows长度、随后WinPS模块进度进入stderr，两次无效控制保留；改用F盘UTF8文件短引导及原测试相同静默进度后18结果成立，没有放宽stderr。

完整本地npm session42180 exit0，19份被测源在全程无变化；56publication/38lifecycle/57host-wrapper，mouse每引擎198，concurrency22，固定项目工具VSIX8项通过。首次窄审无确认P0–P3，没有修复复审循环。证据selftest-compiler-boundary-final-local-validation.json、selftest-no-compiler-red/green.log、selftest-native-ownership-mutations-v2/summary.json及work/selftest-compiler-boundary-first-review.md。带仪器矩阵不计C连绿；新普通CI及修复后二十次无仪器完整两引擎/包验收仍待执行。此项只改变自测依赖，不单独发版，继续并入本轮5.3.13。

### 2026-10-22：x86真实启动与编译器默认引用的原生IO证据

【已跑验证】d2e46f2原push39783885342和两lint成功，原PR39783891700的WinPS x86取证success用例25秒失败，所有原纯规则SelfTest均成功；七份执行日志及原包12428960423已核SHA/CRC和路径。错误回执diagnostic-1-success-failure.json为25056ms、两流全空，无入口标记，不将其它成功DMP当本例现场。原失败保留，未开始无仪器C20。

唯一新原生诊断39785205874同源d2e46f2原attempt1失败。最终Jobs REST修正聚合视图尾部仍显示一个in_progress的延迟：53执行job为43成功/10失败，矩阵11/20完整成功；53原日志均核SHA。全部带仪器样本不计C，原63个可能执行核心中的依赖包正常跳过。各故障区分原生转储、PSRP读栈、共享映像清理、csc编译与x86启动，不能归为同一种插件逻辑错误。

sample12实际失败x86 PID5484/parent10036/UniqueProcessKey18446647368447771520从13:23:14.2682972Z运行24953.48ms，首个x86诊断命令前缀、父进程、次序及失败JSON联合核对；ETW命令后缀截断只解完整base64组，没有补造完整源码。原ETL761266176字节、SHA73aae86772164c63aa18ed22d4b1bbe64a79a623889264555c5f3087fe10c95d，EventsLost0。官方严格栈根/线程5264/原25秒窗口：CPU821.96ms、硬缺页13036.95ms、disk9959.72ms；CLR8.937秒、mscorlib3.608秒、SMA2.166秒文件等待，主要WofCompressedData。符号栈为CLR EEStartup/native-image binding→NTFS读取，尚未进入用户脚本；不是根据后置校准或PSRP线程推测。

sample8的实际collector5300在原5秒内，主线程7004 CPU171.08ms、硬缺页2850.40ms、disk1956.06ms。栈在原HostChildDiagnostics.Write→PInvoke→dbgcore读取目标模块，secondary暂停只发生在原5秒之后，分析窗口已裁剪，不混计后续暂停。该原因仍须单独处理，不能由改变转储标志或延长期限冒充修复。

sample13原编译进程748/parent9104/TID8364在14957.37ms被原owner结束，CPU250.64ms、disk9744.31ms、硬缺页4858.79ms；读取无关Forms/Data/Web等Framework程序集。原CSC.RSP默认引用整套程序集已由微软文档及实际本机文件核对，新增#41。最小候选只在五处实际/镜像编译调用增加/noconfig和/reference:System.dll，源、平台、10/15秒期限与输出断言不变；不预先运行x86、不修改Windows安装/配置。

【已读源码、已跑验证】回归在F独占目录复制未修改的微软编译器及所需资源，自己的csc.rsp注入缺失无关引用，调用真实prepare脚本。先红CS0006，再两架构真实编译成功并查PE机器类型，响应文件原样；只白名单清理文件/空目录。私人原型首次缺cscui.dll并非有效红例，补复制实际编译器语言资源后才建立控制，失败保留。完整npm session81623 exit0、21源全程不变，repository4/publication56/lifecycle38/host57、mouse每引擎198、concurrency22、VSIX8通过；首次窄审无确认P0–P3，无修复复审。compiler-references-final-local-validation.json及work/compiler-reference-first-review.md。本轮纯测试编译修复不单独发版。x86系统冷IO和其它独立诊断超时仍未修复，接下来须在同源/同期限下比较实际托管映像，不能未经对照就换runner或预热掩盖。

### 2026-10-22：默认关闭的同源托管映像对照入口

【已跑验证】99bd18f原push39795513208的WinPS x86同一25秒前置失败，原PR39795520020和两lint成功；七份原日志与12433522211原失败包（SHAddc7880486c8e2c6ed063d6ba6e228a73c5a99a3fc695085eb5e8bbea4f26068）已核对，全部未重跑。GitHub14:18官方Actions Results事故使状态/步骤结果延迟，14:35仍调查中；原运行保留到终态，不将延迟归因本地卡死或取消重派。此前39785205874的52诊断产物/42ETL现全部核SHA/CRC，三次下载尾部TLS EOF改原文件续读取回，仅恢复读取、不重跑CI，所有ETL报告0lost。

候选只新增windows_2022默认false布尔输入：手动入口/共享core对齐，validation仅手动事件透传，stability也透传；两个core作业只在固定windows-latest/windows-2022之间选择。false展开后的两个完整YAML语义等同99bd18f，所有原实际步骤正文/期限/发布和运行源码不变。不是直接将正常CI切到2022，也没有新增预热步骤。实际云端对照必须同时读回Operating System及Image版本，不能只信请求label。

静态门先红后绿、actionlint1.7.12成功、首次窄审无确认P0–P3。完整npm session46322 exit0、21源全程不变，repository4/publication56/lifecycle38/host57，mouse每引擎198、concurrency22、VSIX8；hosted-image-option-final-local-validation.json及work/hosted-image-option-first-review.md。云端2022对照尚未运行，不宣称该映像解决IO或C20。原99bd四CI均已终态才允许推送新候选，避免取消未完成结果；下一步仅显式单次原生诊断对照，不计完整连绿。

### 2026-10-22：动态runner的打包语言声明

【已跑验证】2020005的两份原lint失败，push39805867733/job119918783443在windows-validation.yml的PowerShell包校验正文报告SC1070/SC1133/SC2283。固定actionlint下载SHA通过；Windows原CI继续保留、不取消/重跑。此前本地关闭不可用ShellCheck的语义检查漏掉了实际语言派发，不能以该绿色结果外推全套云lint通过。Issue #42。

最小修复只在package作业声明defaults.run.shell=pwsh，保留Windows原实际语言、所有步骤正文/期限与完整ShellCheck。真实actionlint配只记录原始输入的语言旁证先红后绿：误派PowerShell正文1→0，原Bash lint仍派发；旁证不运行ShellCheck规则，云端原SC失败与后续真实lint仍分别保留。evidence/actionlint-shell-language-{red,green}.json/log；运行源码不变，纯配置修复不另发版。

【已跑验证】2020005原push/PR的两引擎及包均成功，两lint仍原失败，八份执行日志已核SHA归档ci-2020005/final-summary.json；没有取消/重跑。修复后完整本地session8229 exit0、21源全程不变，repository4/publication56/lifecycle38/host57，mouse每引擎198、concurrency22；session79171 VSIX8通过。explicit-package-shell-final-local-validation.json核对当前源/字节及只增加pwsh默认声明的完整YAML不变性；云端修复版真实ShellCheck仍待新原运行。

### 2026-10-23：同源冷IO对照与常规映像候选

【已跑验证】50b原四CI已终态：两lint成功，三份x86诊断25秒原失败、六日志及三个故障包SHA/CRC保留。两例空两流，另一例已写出成功转储和DUMP_TARGET_ALIVE但总期限超时，不能统称入口前卡住，最后一例确切慢阶段未证。下载Go EOF只恢复同一个原包读取，未重跑CI；ci-50b51fa/artifact-read-recovered-summary.json和three-original-x86-failure-readback.json。

同一50b源码，2022原39808588036和latest原39810120462各两引擎+包全成功，六日志/六包/四ETL均核SHA、CRC及0lost，均不计C。实际2022为20261012.333.1；latest实际2025-vs2026的PS5/PS7映像分别20261007.264.1/20261021.278.1。首次x86寿命2022为8.769/8.665秒，latest为5.990/14.536秒，不能宣称每个2022样本更快。证据在测试根evidence/hosted-image-comparison-50b51fa…-{windows-2022,windows-latest}-cloud-{39808588036,39810120462}/final-summary.json。

精确创建身份主线程对照：2022 PID2948/TID4468和PID8032/TID4036的IO并集6.634/6.938秒、WOF文件IO均0；同源2025 PID2700/TID5848 IO11.997秒、WOF7.293秒。原真实失败5484在24.953秒内IO22.997秒/WOF17.249秒。代表样本与官方2025-only程序集LZX策略相符，尚不能隔离全部OS/CLR/宿主磁盘差异或证明LZX唯一原因。各original-budget-thread-analysis.json、work/cold-io-next-mitigation-readonly.md；普通默认2022仍须无仪器完整20绿验收，不靠单次仪器成功宣告修复。

最小候选只把既有windows_2022两端默认改true，普通事件透传true、手动显式false仍选latest，stability透传不变；两runs-on、实际步骤正文、原期限/断言、发布、生产源均不改。无预热、系统解压、位数替换或防护变更。离线ETW工具另按PID/对象地址/创建时间及有限生命周期联合筛选，省略/错误创建时间的真实控制仍拒绝；2022内核512字符命令只匹配冻结源码唯一模板的实际前缀、Node创建身份和七原例顺序，绝不补造后缀。

【已跑验证】默认候选完整本地session52234 exit0，21源全程不变；repository4/publication56/lifecycle38/host57、mouse每引擎198、concurrency22。session34194 VSIX8通过；hosted-default-2022-final-local-validation.json核对当前源和完整YAML仅三处既有映像选择差异。actionlint及真实语言派发静态门通过，本机无ShellCheck不称完整规则通过；首次窄审无确认P0–P3，无修复复审，work/hosted-default-first-review.md。普通新默认云端OS核对及无仪器完整20组仍待提交后原运行，不计前述仪器控制。

## D：发布与文档（进行中）

README 更新日志只写运行体验变化，CODEX.md 保留一屏当前已发布状态。测试、CI 和证据文件按已有 .vscodeignore 排除。

现有发布作业已准备 VSCE_PAT、OVSX_PAT 仓库 Secrets 的一次性说明；没有创建或读取凭据。未配置时沿用网页上传。用户已授权 Computer Use 浏览器，本轮只新建任务标签并记录实际为已有 Chrome 配置，不能称独立 Chrome 实例；没有操作用户原有标签。

通过合并门槛后，按 main 同次绿色构建的不可变 GitHub 原包上传两个商店，核对发布者 fhgffy、精确版本和三处公开下载 SHA。当前尚未发布 5.3.13，不能将已有登录会话或绿色跳过商店的作业写成上架成功。验证码仅通知一次，必须本人完成。

## E：仓库与经验整理（部分完成）

已完成原生桌面验收、三渠道发布和经验维护技能，索引精简，旧流水归档，原 105 个主线及 53 个用户追加经验段全部保留。原工作区 lessons.md 未提交改动已备份并核对 SHA：285b8c0d546782441aa8855989b0de3270901a8e2112e8f06c083d26c098631b；本轮再次读取仍相同。

17 个已关闭/合并 PR 的远端 codex 分支已按读回结果清理；#28 已回复关闭。PR #5 的有用发布链接吸收并致谢，待本轮合并后礼貌关闭。原工作区仍保留 c697936 和唯一 lessons 改动，尚未切 main；须等自有 PR 合并后重新检查状态再按授权整合。

## F：外部 PR #30（已给出结论）

审查头 1f607c1a968ae81c0dece35f2f2e7f6991461c03 仍为 CHANGES_REQUESTED。未在宿主机运行或安装该 PR；只读累计 diff 后才批准其未改 workflow 的 fork CI，BOM 失败保留。

已读源码：默认 true 与 opt-in 描述不符；CanUseForegroundUi 提前 return true 绕过输入空闲、长按及输入变化等保护，影响窄栏菜单调用点。物理点击自身的最终保护没有在累计最终 diff 中被删除，不能用中间提交替代最终差异。

可信 5.3.12 的原生对照：

- 十张后台终端卡各批准一次，原证据与英文跟进已保留。
- 524px 窄栏浏览器卡在其他测试应用前台下等待 442.765 秒并记录 other-foreground；切回 IDE 后 04:41:07 对卡 821 一次 Allow Once。
- 1179px 宽栏直接 Allow Once 于 04:50:45 在其他测试应用前台完成一次，卡 2989；141.678 秒观测窗没有前台或鼠标变化。物理 250,225 与逻辑 143,129 经 Win32 转换核对，不能混比两套坐标。20ms 是配置采样间隔，不排除采样间瞬变。

原始证据及坐标审计在可信 12 根的 baseline12-browser-background-summary.json。窄栏待批截图已查看；宽栏批准发生在抓取前，没有把完成截图称为待批截图。

英文结论已[发布并逐字回读](https://github.com/fhgffy/antigravity-auto-accept/pull/30#issuecomment-6326464387)：纯模式后台路径已工作，剩余窄栏菜单路径不能为后台功能跳过输入/前台保护；要求默认 false、保留保护、去 BOM 并补回归。本轮不合并该外部 PR。

## 审查与最终待办

原整分支审查的重要接管初始化缺口已经修复，七项未采纳建议的理由和代价在本轮 ledger.md 保留。新增诊断事件的一次独立窄范围审查确认跨位数转储及同步诊断回收问题，已用 x64 有界收集器修复；没有反复派复审。C# 名称条件构造器的专用变异回归仍是已说明的次要覆盖缺口，不冒充已经加入 CI。

未完成：新修正后的二十次完整 CI、自有 PR 合并及 main CI、5.3.13 三渠道公开哈希核对、原工作区 main 整合、PR #5 关闭、最终发布回执。A/B 未达到的资源阈值与 CI 历史原因的不确定性必须保留到最终报告，不能因续测或发布省略。
