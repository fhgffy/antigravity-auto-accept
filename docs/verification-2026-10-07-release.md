# 5.3.6 按钮初筛与发布验证（2026-10-07）

证据等级：已读源码、已跑验证。基线为已合并、已发布的5.3.5提交0b3f21b380009450308e2055e35cbf207dbfb7dd。本轮没有改变审批名称、卡片作用域、一次允许选择、宿主身份、动作前复核或物理输入规则。

## 已复现与修改

原generic主循环在名称匹配前读取IsEnabled、IsOffscreen、BoundingRectangle并计算中心。普通Save按钮不产生批准动作，但仍触及这些无关提供者属性。新增内存fixture执行实际生产主循环，统计每个getter、几何函数、模式和动作调用；只有系统窗口、宿主查询及控件提供者为替身，实际Get-ButtonCenter保持执行。

旧5.3.5在PS7得到4个普通按钮用例的明确断言红灯，退出1、解析成功；普通计数用例读Name/Enabled/Offscreen/Rectangle各1次、中心1次，其他三个用例分别令状态或矩形getter抛错。合法Run的禁用、离屏、无效几何和有效用例仍通过。

最小修复将原Test-ButtonMatch移到Current.Name之后，不匹配立即跳过。新8个用例在PS5、PS7分别通过：普通4例仅Name=1，其余getter、中心、模式、Invoke、Physical均0；有效Run仍Invoke=1，禁用、离屏和无效几何保持无动作。最后宿主查询后名称、状态、PID变化及物理父进程退出用例继续通过。生产源SHA256为7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A。

这些计数证明避免无关查询，未测量整轮CPU、长期heap或实际UIA provider成本，不能据此宣称内存泄漏已修复。真实多应用、后台审批和低内存失败的既有证据分别见此前验证记录。

## 本地回归与打包

完整npm test退出0，包含compile/typecheck、仓库3项、扩展生命周期28项、SelfTest95项、扫描母脚本汇总135项（其SelfTest子进程覆盖PS5和PS7）、两引擎宿主查询各125项、输入各81项、并发22项。另行完整执行扫描回归的独立PS5、PS7日志各134项通过；这两份日志同时覆盖各自母脚本内的主循环fixture。单引擎CI应显示scanner134，不能把默认链的135项汇总或双引擎SelfTest当成两个母脚本的完整回放。

新增test:publication接入默认npm test链后，独立执行26项发布回归全部通过、仓库3项通过、actionlint退出0。发布用例执行实际工作流内联PowerShell，替换网络/CLI边界，生成8文件夹具归档并调用真实validate-vsix；覆盖精确SHA、既有原资产保留、缺失资产、标签缺失/冲突、损坏输入、草稿、缺商店凭据、公开状态和有限等待。完整npm test原日志先于这个脚本入口变更，新增发布链验证另存C:\Temp\antigravity-536-publication-test-20261007.txt。

npm run package退出0；validate-vsix读取实际归档，核对8文件、完整package manifest/VSIX identity、生产扫描器、extension.js、icon和LICENSE字节一致。版本5.3.6，本地包SHA256为DA0A9CEB841F553E24D840F67687E1CD13D02ED42B01D1CB30E6B3BD6D53F9B2。CI重新生成ZIP的元数据可不同，最终以同一次main构建的原归档及其校验文件为发布输入。

本地完整日志为C:\Temp\antigravity-536-npm-test-20261007.txt，打包日志为C:\Temp\antigravity-536-package-final-20261007.txt；独立红绿日志位于C:\Temp\antigravity-scanner-namefilter-7e78222ee9454951b4f62c3a792332c7。源码和测试严格UTF-8无BOM、CRLF、PS AST无错，diff检查通过。

## 发布证据的范围

5.3.5已补齐GitHub Release、Marketplace、Open VSX三个渠道，双商店公开版本均为5.3.5；Open VSX公开VSIX下载后SHA256与原上传包DCA7D7F07B752E437467E416ED4AF08894CA7CD42FBD4668F66F1437531EFF1A一致。

5.3.6自动发布规则和重试边界见[publishing.md](publishing.md)。本文件的本地通过不证明5.3.6远端CI、合并、自动Release或商店上架已完成；这些步骤需在本轮精确提交进入GitHub后分别核对。没有配置商店凭据时，CI会明确报告未发布，后续从已验原包在已登录表单完成上传。

## 5.3.6 Computer Use 实机回合（2026-10-07 16:54–17:16 Asia/Shanghai）

使用computer-use的Sky API启动真实Antigravity IDE、重载窗口、输入普通Agent任务，并在自有记事本测试页输入文字；没有手动点击审批的Allow/Submit，没有改变IDE权限设置。通过CLI安装本轮已验5.3.6包后，已安装manifest版本和scanner/extension.js字节与本地生产文件一致。实际输出显示16:56:13的5.3.6 activating、对应安装目录及16:56:17 scanner ready，固定scanner PID1025924、启动时间16:56:13.3428483。

本轮日志累计5次Submit(one-time permission)与1次Allow Once(browser domain permission)：最初三个无害终端标记、浏览器域名批准、Agent后续终端工具调用以及关闭插件对照后恢复的一次命令。Agent UI显示三个D536_STEP标记及Example Domain结果；其对HTML主标题的解释没有被独立核对，不能作为页面内容准确性的证明。审批日志明确Invoke返回，未出现物理批准标记；工具最终结果与该请求返回是不同证据。

在真实IDE、已打开Chrome及Notepad并存时，记事本新增D536_BACKGROUND_INPUT_001及中文/英文/数字文本均保留。120秒只读观测产生575个前台/指针/输入tick样本与24次固定scanner资源样本。17:03:44.721前台为Notepad；17:04:00.521至.723之间切到IDE，终端Submit日志为17:04:00。17:04:18.120再次处于Notepad；17:04:26.731至.920之间切到IDE，浏览器More actions日志17:04:26、Allow Once日志17:04:27。相关采样指针始终729,434。此结果证明前台切换，不能宣称后台批准全程不抢焦点，也不能用下一次type_text重新激活Note掩盖切换。

停止插件后，固定scanner退出，AutoAccept显示OFF。随后发送单个D536_OFF_CONTROL_002任务，将Note置前台。第二次120秒观测570个样本：17:10:42.174以后前台保持Note直至17:12:16.587停止；17:11:32–34的只读UI截图同时看到原生权限target与Submit等待。批准前这个卡片没有在采样中把IDE切前台。17:13:32恢复scanner、17:13:36 ready、17:13:37自动批准。恢复动作由Computer Use主动激活IDE，不能把这次控制回合误算为后台焦点验证。

已读生产源码没有直接SetFocus/SetForegroundWindow调用。本次终端控件可见，未记录滚动；仍需区分SelectionItem.Select、Submit.Invoke与批准后宿主行为。浏览器经过ScrollIntoView、Expand和菜单Invoke，秒级日志不足以区分阶段。Chromium官方固定源码表明部分默认点击路径可改变页面元素焦点，但页面焦点不等于Windows前台，且未映射当前IDE内核build；归因仍为推测。

固定scanner前后资源样本privateBytes为108032000与112304128、handle为649与608；这是短时资源记录，不证明长期无泄漏或GC存活根。单IDE启动后系统提交余量约1.58GiB，本轮未打开第二个完整IDE，避免重复此前低内存失败；未做Chrome人在浏览时审批、第二IDE或远程环境的完整验收。

原始本机证据保存在C:\Temp\AntigravityAA-runtime-536-ddc64f6a9d1d4557ad97b6b8fb5ce32a，含安装验证、scanner-events-536.txt、两个只读观察脚本、三份JSONL及actual-ide-536-approval.png。scanner事件归档SHA256为2A4CE3649D47EFA3B03BAFB3088E9546247C83521F6AF835F23BD9709B57D9B9；保留截图SHA256为9B3EA433B9D81D5509AE0E2F4525CF25AFA28BEBA8FC06C5CFFD93BBE367723A。

精确7ffae95b5a66b3246f2b4ec0462eb896cee5a6b3的push run37596617849和PR run37596629241均已success，PS5/PS7及Verified VSIX通过，发布作业在分支/PR按设计skipped。PR12暂不合并，先定位真实前台切换；5.3.6尚未发布，5.3.5仍为已核三个渠道的公开版本。这一回合真实实测不等于整体体验验收完成。

## 阶段诊断与原包恢复（2026-10-07 17:50–18:13 Asia/Shanghai）

为区分动作阶段，在系统Temp目录构建了同版本、明确标记LOCAL DIAGNOSTIC的独立安装包；它不是发布5.3.6的验收输入。10处既有Select/Invoke/Scroll/Expand动作保留原最终校验、顺序、冷却和异常传播，只在校验前与动作后读取前台，并以内存时刻记录call begin/return。诊断scanner SHA256为0088F6385A46B41BC62A1904AC565AD5F08407CADF33D1788224B6E2D3506827、VSIX为8912F50ADF39605BD5B5CF17D738AA9E945FA53CDD071E4A8284874D12675F57，extension.js保持原包字节。

诊断预检的PS5完整160项包装断言、95项SelfTest、134项scanner通过。PS7包装断言与相关动作回归通过，但完整scanner最后的abandoned mutex READY在原8秒界限超时；后续同界限的单独协议复现通过，不替代完整PS7成功证据。大型诊断fixture只在Temp副本改为UTF8文件与短启动引导，生产及仓库测试未因此改动。

17:53:36的单次终端审批中，before-validation在.371读取Note HWND32639358，Invoke begin=.413、return=.449，after在.450读取IDE HWND331346。独立只读观察在.414–.415区间仍读取Note，之后.617已IDE；前台切换因而被缩小到约35–36ms的观测包络，覆盖Invoke后半段或刚返回的极短区间。本次没有Select、Scroll、Expand或物理批准动作。pointer保持1427,618，lastInput tick变化不能识别输入来源；这些记录不能独自证明provider或审批后宿主哪一个发起了激活。

18:10提交下一张D536_DIAG_CHROME_001自然终端任务并尝试切至自有Example Domain窗口。Computer Use随后因无法可靠确认当前浏览器URL停止；没有继续原生/浏览器界面操作，完整Chrome交互验收未完成。已在运行的只读观测仍记录到实际Chrome前台：18:10:56.301的before-validation为Chrome HWND328922，Invoke begin=.363、return=.389，after=.389为IDE；独立样本.305为Chrome、.474为IDE，pointer1434,825保持。该记录证明第二个前台来源的切换，不能将被中止的界面测试说成通过，也未测持续浏览器输入。

官方CLI恢复已归档原始5.3.6包后，核对scanner为7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A、extension.js为2F85FBE50F0DF4EF35CC7C688602EA2B5D822951777B0159040057AE392EA1AD。仅在PID1041608、精确启动时间17:50:50.5100200、父进程1039888及解码启动脚本安装路径全部匹配后停止本轮诊断scanner；扩展按原3秒策略启动原包scanner PID832324，18:13:52 ready。没有结束用户IDE或其它应用，也没有残留运行中的诊断scanner。

新增日志scanner-events-diagnostic-and-restore-536.txt SHA256为C013DAD0517CB95171F7480D9B87FDE74AE14979342A83A2084598E2082E8B4D；Chrome观测observe-foreground-1023228-20261007T101028106-354805c0cf054eb4a6b3ca1f8d7041cb.jsonl SHA256为0AC981C938BF60D0E2C8C8FE1AE922B00A60CFB4474798C9EE53BD61CFD89AA3，120030ms、548样本、24次固定IDE资源记录、无观测错误。全部保存在前述独立Temp证据目录，diagnostic-restoration-20261007.json记录恢复身份与时间。

精确17135bca550e13fc8da1e5d746c5bf5462f1439a的PR run37600826061与push run37600822037最终均success：第一次分别在PS7的32bit owned-child READY10s与生命周期SelfTest20s处超时，失败日志保留；同SHA失败作业各仅重跑一次，未改界限或断言。重跑成功不能证明首次超时根因或长期CI稳定性。PR12仍为draft且未合并，5.3.6仍未发布；本轮没有修复前台切换。

## 自动设焦点的官方客户端契约（2026-10-07）

证据等级：已读官方文档，尚未验证修复。微软[IUIAutomation2::put_AutoSetFocus文档](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation2-put_autosetfocus)说明，默认多数执行动作的UIA方法会在Invoke、SetValue等动作前设焦点；原生COM客户端实例可设AutoSetFocus=false阻止这一自动步骤。该属性从Windows8支持，符合项目Windows10/11前提。现有托管InvokePattern未暴露这个实例选项，创建另一COM实例并设false也不能假定会改变原托管调用。后续受控差分必须从同一个已配置COM客户端取得动作pattern，在原最终校验完成后调用，并分别验证一次批准、前台保持、浏览器窄菜单、用户输入及原错误/冷却语义。本文记录官方契约提供的可测假设，不把它写成此次实机切换已经定责或修复。

## 原生无焦点客户端候选实测失败（2026-10-07 20:00–20:22 Asia/Shanghai）

证据等级：已跑验证，候选未修复前台切换。基于原诊断scanner，只将Submit pattern获取改为同一CUIAutomation8/IUIAutomation2客户端的AutoSetFocus=false路径：窗口句柄定位、RuntimeId条件查找、再次比较、GetCurrentPatternAs取得Invoke，保留原最终表单、一次允许、宿主退出校验及冷却；本轮没有替换选择、滚动、展开或普通按钮动作。候选源码SHA256为C206DD9199D19E0FD2BCC3F51A6D290EA469E501877EC79A0F333823ED70E954、VSIX为676A8255887FC92243CC5F250955A63CBB75EA1B829C1AD62E9DEB9A96FFE8C6，extension.js与原包相同。

预检在PS5和PS7编译候选内嵌C#、创建自己的COM客户端、读回AutoSetFocus=false，严格核对三种无效参数的异常类型及内容；均exit0，没有桌面查询或控件动作。纯内存测试真实生产Submit函数经过外部pattern边界，原版默认焦点副作用模型失败、候选通过；这是路由验证，不能替代前台验收。审查发现GetTypedObjectForIUnknown要求COM class，候选在安装前已改为GetObjectForIUnknown后接口转换；转换失败释放自己的RCW，raw pointer独立释放一次。顺序清理异常遮盖原异常的风险仍需在任何正式实现前处理。

启动时真实Agent提示认证失效，本轮没有自动操作登录；用户手动恢复后，正常发送单个D536_NOFOCUS_APPROVAL_001本地只读检查任务，并将新建自有Note页置前台。候选于20:09:00 ready，20:12:22实际创建无焦点客户端并完成原生绑定。before-validation=.110读取Note HWND329822，Invoke begin=.151、return=.196、after=.197读取IDE HWND133218，调用正常返回且一次性Submit被批准。本次只有Submit，无Select、Scroll、Expand或物理批准。

独立只读观察120006ms、600个200ms前台样本、24次固定IDE资源记录，无观察错误；20:12:22.150–.151仍Note，.372已IDE，pointer1429,546保持。观察文件observe-foreground-35596-20261007T121042225-2cfb0555b072471781d5efedfa18e1e5.jsonl SHA256为41389498F5B4C28F6E87C6DAD33E29818D48FF0A89CC526F6557785DF129E23A。关闭UIA客户端默认设焦点未消除这次切换，不能因此认定真实宿主或provider已经定责。

Computer Use随后展开已完成工具记录，读到task-8结果“command exited with code 0”；Agent回报当前工作目录，系统时间属于Agent环境元数据，不能说成终端独立测时。审批后自有Note的D536_NOFOCUS_TEXT_001中文/英文/数字基准文本保持原45字符，仅为单次输入保留，未验证持续键入。UI返回记录保存在独立Temp目录的native-task-result-and-note.json；用户工作区仍显示原8项待提交改动，未编辑这些文件。

本轮证据与候选保存在C:\Temp\AntigravityAA-focus-client-536-413788f4d5a44e63abdf7a7bc8256173。测试后官方CLI恢复原5.3.6源码7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A，并仅在PID28744、启动时间20:08:56.157476、父PID36856及解码安装路径匹配后停止候选scanner，保持用户IDE与应用。原包scanner PID43736于20:22:02.245849启动，原输出20:22:02 ready，恢复后的日志归档SHA256为FA248E7A8A2EEDF777A42664FA4820C8CBE68B9D18F1C1CAC841E812EAE9E6BA。该实验未修改生产源码、未合并PR12、未发布5.3.6。多IDE和完整浏览器持续输入矩阵仍未完成，不能从短时样本宣称体验验收完成。

## 标准pattern路径复测与内核版本核实（2026-10-07 20:35–20:50 Asia/Shanghai）

证据等级：已跑验证，标准路径候选仍失败。Computer Use通过Help > About读取真实运行版本：Antigravity IDE 2.5.5、Electron 39.2.3、Chromium 142.0.7444.175、Node 22.21.1；因此此前固定Chromium源码已能映射本机版本，但页面焦点机制仍不能独自确定Windows前台变化的调用者。

只在Temp生成第三个候选，将同一已配置COM客户端的GetCurrentPatternAs/raw pointer转换换为GetCurrentPattern标准IUnknown输出；保持原窗口、RuntimeId和最终审批校验，在绑定后、最终校验前重新读取AutoSetFocus。源码SHA256为15C8956BDC19FC7055732C5DF9A8C58A4195612B9A2260309ACECEF21300EFDB，VSIX为321CD461B7DEC6C079F5F46B60A2EA2199383DB3ACBFAD8850620DFBCA6153D4，extension.js仍与原版相同。PS5/PS7内嵌C#编译、客户端false标志、三种无效参数的提前拒绝、纯内存实际审批路由和VSIX字节身份校验均exit0；这些不替代原生focus验收。

第一项目录任务D536_STANDARD_APPROVAL_001使用list_dir完成，没有产生审批或Invoke，只记录为未触发。第二项自然任务D536_STANDARD_APPROVAL_002要求实际测量可用物理内存和测量时间；用户未手动点击审批，正常Agent生成只读系统检查，产品自身提交一次许可。20:46:59日志在绑定后再次显示AutoSetFocus=False；before-validation=.322读取Note HWND329822，Invoke begin=.337、return=.364、after=.364已IDE HWND133218，无Select、Scroll、Expand或物理审批。因而标准pattern获取路径没有修复焦点变化，且排除了此次绑定过程中标志恢复为true的解释；尚不能独自区分provider或宿主的激活行为。

独立观察120007ms、600个200ms前台样本、24次固定IDE资源记录、无观测错误：20:46:59.165–.166为Note，.369为IDE；pointer1429,570保持，lastInput变化不识别输入来源。observe-foreground-35596-20261007T124631304-b9a45abd697e46be95c5da9d92b25313.jsonl SHA256为A7E35862EEAFC8651DC2D9485063411AEFDFEBEED38B83B91F984F9AA1285B6A。Computer Use展开工具输出，实际读到Available Memory (KB): 3734588和Current Time: 2026-10-07 20:47:01；该界面未显示退出码，不补写exit0。自有Note的D536_STANDARD_TEXT_001中文/英文/数字44字符基准保持；未验证持续键入、第二IDE或完整浏览器矩阵。

官方CLI恢复原始5.3.6包，再通过正常Restart Scanner命令重启产品；磁盘scanner恢复7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A，候选PID48472已退出，原包PID48236、父PID36856、启动20:49:59.2795700，20:49:59 ready。证据保存在上述focus-client Temp目录：candidate3-native-task-and-note.json、actual-ide-about-20261007.json、candidate3-runtime-ledger.json；日志candidate3-native-failure-and-restore.log SHA256为2554A01C67AAE23F48AC5BAE1A9033E0D56970CB726368298D3857C8346F1BA7。生产源码、IDE安装文件与用户原8项工作区改动均未编辑，PR12仍draft，不合并或发布未通过本机体验验收的候选。

## 实际provider诊断与Legacy单例正向结果（2026-10-07 21:10–21:27 Asia/Shanghai）

证据等级：已跑本机验证；仅一个后台静置案例通过，尚未完成候选验收。本轮仍只在独立Temp目录制作同版本诊断包，未修改生产源码。第四个包只在原最终检查前增加FrameworkId、ProviderDescription和IsLegacyIAccessiblePatternAvailable查询，PS5/PS7内嵌COM编译、客户端标志和归档身份均通过。真实Submit于21:12:12读到Framework=Chrome、LegacyAvailable=True、Provider=[pid:35596,providerId:0x0 Main(parent link):Unidentified Provider (unmanaged:Antigravity IDE.exe)]。它不证明MSAA代理或宿主已被定责。该动作早于Note置前台的21:12:13.531，不计为后台焦点案例。

据此第五个临时包只替换Submit的客户端动作接口：同一AutoSetFocus=false客户端、同一窗口/RuntimeId绑定，GetCurrentPattern(10018)取得IUIAutomationLegacyIAccessiblePattern后调用DoDefaultAction；选择、滚动、展开和其它按钮仍为原实现。原最终宿主、表单归属、权限目标、一次允许选择、enabled/offscreen/rect等1797字符检查块与第四包逐字相同，不增加动作失败后的物理回退。微软SDK头文件的完整24成员vtable顺序、GUID和已调用方法签名已对照，PS5/PS7编译、三种无效参数提前拒绝、UTF8无BOM/CRLF、归档源与extension.js身份检查均exit0。临时scanner SHA256为A7C07697A052203AB2B79EAA1602A6530ADF1F1678CD97035DCEE618934264CA，VSIX为56DA0DD72F6F051B2961AA96C811513D39F927A38D3C8DF18EB75CF148EC3427，extension.js仍保持原包字节。

已读[微软默认动作契约](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationlegacyiaccessiblepattern-dodefaultaction)与固定142.0.7444.175的[Chromium Windows接口源码](https://github.com/chromium/chromium/blob/142.0.7444.175/ui/accessibility/platform/ax_platform_node_win.cc)：Invoke和MSAA默认动作最终均请求kDoDefault，但MSAA入口没有Invoke中的disabled拒绝，因此原最终检查不能删除。Blink的[DispatchSimulatedClick](https://github.com/chromium/chromium/blob/142.0.7444.175/third_party/blink/renderer/core/dom/events/event_dispatcher.cc)在disabled表单控件处返回；这不覆盖全部ARIA自定义控件，也不是本机Windows前台归因。此轮正向结果仅支持进一步测试另一客户端路径。

第一个Legacy任务D536_LEGACY_APPROVAL_001于21:20:00正常完成默认动作，但Note直到21:20:12才置前台，仍仅为接口能执行的证据。发送后刷新曾错误地同时关闭text与screenshot，Computer Use拒绝该调用；已重新观察并确认任务已发，没有重复发送。界面观察工具错误不算插件失败。

第二任务D536_LEGACY_APPROVAL_002通过正常Agent输入要求实际只读内存测量，用户未手动审批。将正常发送与独立Note激活安排为两次连续Computer Use调用，每个输入后刷新；21:22:24.129起停止界面输入。21:22:37.126的before-validation为Note HWND329822；Legacy动作begin=.141、return=.142，after=.142仍Note，而目标IDE HWND133218。只记录一项Submit，没有Select、Scroll、Expand或物理审批。这与此前Invoke候选动作后转IDE的案例不同，但尚不能证明UIA内核或宿主的确切激活调用链。

独立原生只读观察120011ms、600个200ms样本、24次固定IDE资源记录、无错误。停止输入后的511个样本全部为Note，foregroundHwnd与foregroundHwndAfter相同且稳定；pointer1433,593、lastInputTick32=9505828保持不变。文件observe-foreground-35596-20261007T132206439-6789cbdaef894640a6e40d9315d08849.jsonl SHA256为AA9EA7CE3EB31AAF6152C75A30CB3546A2229C620CAF27AFB879F1E5B20092FA。200ms采样不能排除采样间隙内的短暂激活，不将一个静置样本扩展为持续输入或全部应用通过。

Computer Use展开原始工具记录，实际输出FreePhysicalMemory=1954848、TotalVisibleMemorySize=16624952（KB）。界面未显示exit code，测量命令也未独立输出时间，均不补写。Note自有中文/英文/数字基准仍为44字符且逐字一致；本轮未持续键入，未做浏览器或第二完整IDE验收。Agent另显示Explored 3 files及技能加载总结，本文不将自然语言限制视为其全部行为合规证据，也未修改用户工作区的8项既有待提交内容。

恢复官方原包CLI先报告安装成功，随后V8::ToLocalChecked Empty MaybeLocal崩溃，实际exit134；没有当成exit0，也没有盲目重复安装。独立核对磁盘scanner=7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A、extension.js=2F85FBE50F0DF4EF35CC7C688602EA2B5D822951777B0159040057AE392EA1AD；通过正常Restart Scanner命令后，第四/第五包PID8780/61808均退出，原包PID63404、父PID36856、启动21:26:26.3752551，21:26:27 ready，解码launcher完整安装路径匹配。主IDE PID35596及原启动时间不变。CLI崩溃原因未定责，不归为插件bug。

证据保存在此前focus-client Temp目录：candidate5-native-observation.json、candidate5-native-task-and-note.json、candidate5-runtime-ledger.json及candidate4-provider-candidate5-legacy-and-restore.log，日志SHA256为330E7F0D3DFE1986B4B1927EBCF8582245EDC6C3242BE3428064CC99C279659E。PR12保持draft，未合并或发布5.3.6；生产实现、清理异常风险、连续输入、浏览器窄菜单及多IDE矩阵仍需后续验证。

## 正式 Legacy 动作接入与完整离线验证（2026-10-07 Asia/Shanghai）

证据等级：已读源码、已跑验证。正式 src/autoClicker.ps1 将五个 Invoke 模式获取入口改为同一个 AutoSetFocus=false 原生客户端准备 Legacy DoDefaultAction：浏览器直接允许/触发器、菜单项、一次选项降级、Submit、旧式匹配按钮。准备阶段绑定窗口和 RuntimeId，取得模式后仍执行原宿主、控件归属、目标内容、一次允许、enabled/offscreen/几何及父进程最终检查；最终动作只调用默认动作。Select、ScrollIntoView、Expand 保持原实现，其本机焦点影响仍在待验收范围。

客户端仅在实际准备动作时创建；模式在返回、继续、最终检查拒绝和动作异常路径释放，扫描器退出释放客户端。清理分别处理已断开引用、COM 释放和参数异常，不遮盖原审批异常、不跳过后续引用、不使用 FinalReleaseComObject。真实 RCW 重复释放预检未复现异常；异常传播问题只由受控 Marshal 边界红灯证明，不表述为实机复现。独立只读审查对照 SDK 头文件 SHA256 66B00453430CC6884482352EBC0DDF6DB3916E38BF5684CABA79D6E86AA1F038，确认展平客户端61项、元素82项、Legacy24项、元素数组2项完整顺序与已调用 ABI。

六个真实审批分支离线重放在旧源码全部红灯，接入后转绿；覆盖终端 Submit、选项降级、宽浏览器卡片、窄触发器、窄菜单和普通 Run。最终父进程退出、菜单重新关联、动作后抛错另核实零/单次动作与对应模式释放。原生八项预检只创建客户端与提前拒绝无效参数，不枚举或操作真实桌面；PS7 单独预检通过，完整套件中的 PS5 预检也通过。桩里的前台状态不证明 Windows 实机焦点。

首轮完整 npm test 实际失败：扫描器152项通过后，host-process 的内存影子把字段注入整个 C# 最后括号；新增命名空间使该处不再属于 MouseHelper。宿主和鼠标夹具改为提取完整顶层 MouseHelper 类，完整生产 C# 仍先编译，21个 P/Invoke 均在替换边界，全部原断言保留。独立类边界审查通过。修正后第二轮 npm test exit0：编译/typecheck、仓库3、发布26、自测95、生命周期28、扫描器152、宿主每引擎125、鼠标每引擎81、并发22全部通过。UTF-8无BOM/CRLF和 git diff --check 通过。

独立正式候选归档八条目及源/JS/资源字节核验通过；scanner SHA256=CDB3AB3C3B247B4B37A3C5A81D6D9128A729509A25E6E01EC2DF5A6E4F2EAEC1，extension.js=2F85FBE50F0DF4EF35CC7C688602EA2B5D822951777B0159040057AE392EA1AD，VSIX=A99EE3965E6542F258E7C324308BDC8E2CA1D6A7C2F6B461951B0C96597B4F7B。证据目录 C:\Temp\AntigravityAA-production-legacy-a4da725875e54ebfbe6429aebbfca186，保留旧源码、六路红灯、受控清理红灯、首次失败、完整第二次通过和归档日志。

本节只证明正式源码接入及离线验证。正式包尚未替换本机运行态，先前单个临时 Submit 静置结果不能提升为正式包验收。新提交 CI、持续输入、浏览器、窄菜单、多 IDE、公平接管仍需继续验证；PR12保持 draft，未合并或发布。

## 正式包安装、真实输入与浏览器窄菜单失败（2026-10-07 22:25–23:12 Asia/Shanghai）

证据等级：已跑本机验证，正式候选尚未通过体验验收。精确提交678e741baea93d336c526e6a02bf733d50fde6b2的PR run37635788908与push run37635780593首次均success。官方CLI安装正式包exit0，经正常Restart Scanner后原PID63404退出，新scanner PID72940、父PID36856、启动22:25:09.1135330、22:25:14 ready；源码与前节CDB3AB...正式hash、JS与原包hash逐字节匹配，解码launcher绑定真实安装脚本及IDE完整路径。

文件任务D536_FORMAL_NOTE_INPUT_001使用真实内置文件工具读取独立Temp输入并写出native-task-output-001.txt：marker、version5.3.6、numbers总和10和中文text一致，实际输出SHA256=7671AF83BABE70A385624D9D2A8BB23CE3920F68859DD3940F0D70DF4C0F7766。本轮六段中英文输入后Note为146字符、逐字一致。原始JSON日期解析后，14:40:32.586Z切至Note后的319个样本全部Note HWND329822、读取前后稳定；此观察仅覆盖第一段输入，且没有产生审批，所以只记文件工作流与输入保留，审批为NOT_TRIGGERED。截图显示任务结束时AX曾仍返回Working，不能凭一层快照判断是否完成。

浏览任务D536_FORMAL_BROWSER_001由正常Agent访问MDN和W3C文档，23:02:30和23:05:45各有一项实际Allow Once，均使用More actions窄菜单，invoke=False、scrollitem=True、expand=True；未手动审批或更改持久许可。首个动作晚于第一段独立观察结束，不计其前台结果。第二段观察在23:04:41.984切至Note，第三段追加中英文于23:04:56.906结束，之后没有界面输入；23:05:44.967样本初读Note、23:05:45.454读完时已IDE HWND133218（该样本foregroundStableDuringRead=false），23:05:45.934稳定读到IDE。cursor1423,686不变，lastInput tick变化不能识别输入来源。该案例明确未通过后台焦点验收，但秒级审批日志仍不能给展开或最终Legacy允许精确归因。

第二段文件observe-foreground-72940-20261007T150434576-a1e6dbdf0c884c4abd5ed5459f978dcb.jsonl为120386ms、366个样本、24次固定scanner资源记录、无观察错误；采样间隔受调度影响，不表述为连续每200ms保证。SHA256=2F319B06C0826287AE55009D580E38F769A563EBF33A90865FBAA57EBB2E7A06。Note累积197字符，三段浏览阶段输入此前均逐字保留；这不能抵消后来焦点切换，也没有在切换后追加输入来掩盖问题。

新增证据均保存在上述production-legacy Temp目录，包括三份输入/观察汇总、native-narrow-menu-focus-failure.json、更新的运行态台账和formal-native-first-browser.log（SHA256=B72380FD6A7FA42B713CE6CFDF0E74ACD3DBAE7C54D5347C214FA357902D683F）。真实浏览器任务结束后，Agent报告MDN示例提取失败与上游模型503；它不是此处插件焦点根因证据。用户原工作区仍显示8项待提交内容。

仅在独立Temp准备完整原动作的阶段诊断包，分开观测准备、滚动、展开、触发与最终允许，不加入焦点恢复、物理回退或放宽校验。PS5/PS7完整C#与固定内存10条日志预检通过；初次预检的sealed声明及函数导入作用域错误已修正，它们是诊断夹具错误。后续必须实际定位与复测；PR12继续draft，不能因正式源码CI绿灯而合并或发布5.3.6。

## 窄菜单展开阶段定界及临时候选回归（2026-10-07 23:16–23:40 Asia/Shanghai）

证据等级：已跑本机验证、已跑纯内存验证；修正候选尚未安装验收。原动作诊断包 CLI 安装 exit0，旧 scanner72940退出，新 scanner84424/父36856、启动23:16:19.142797、23:16:24 ready；解码入口绑定真实安装目录，source=72D60C0CBFF3909DDF0390EDA5AB6A86AA6D31E4E1750C309113EC2747AD3775，JS仍与原包相同。

正常浏览任务 D536_BROWSER_STAGE_001 发出15:18:21.897Z、Note静置起15:18:29.638Z。23:19:06诊断精确记录 prepare-before .2052369、prepare-after .2327389均为Note HWND329822；expand-before .3670248为Note、expand-after .3958230已IDE HWND133218；allow-before .9359939及after .9390020均IDE。本次没有 Scroll，最终 Legacy Allow Once 在前台已变后才执行。独立585样本/24资源记录/120017ms观察同样记 Note→IDE，无观测错误，SHA256=BC7546A468210990722D88A48B3D624292C1E6BE7A9856F64296A5A2E5666370。此结果将变化定界到观测的托管 Expand 调用窗口，尚未确定 OS/provider 的具体激活调用。证据在 C:\Temp\AntigravityAA-browser-stage-536-99745bd134dc44e49caac31f38a365fd/native-expand-isolation.json，完整原动作与最终检查保留。

独立 Temp 候选仅把 More actions 实际触发改为已绑定 Legacy 默认动作，精确已开菜单直接接管，未关联已有菜单或非折叠状态拒绝。首个候选 A777022C…C88501 的六个用例通过，但只读审查另复现两项：状态 getter 在最后检查后改名仍触发，以及精确已开菜单的 trigger Legacy 不支持导致漏批。补 getter 改名、getter 改 HWND、已开菜单缺 trigger Legacy 三项，旧候选三红，修正后 PS5/PS7 九项均绿；模式状态读取及准备全部放在原最终宿主/卡片/父宿主检查前。

修正临时 source=25430E2AD8C8044F478E05BE3144619CA0604CBF21F62075BF88EEA953CC7B38，完整 C# 编译和10条日志预检双引擎通过，UTF8无BOM/CRLF；VSIX=05B7A5CB78441C0B9BC9F4909C3E2E4F18B25EA729D3933AF5E46838246282C2、8条目且源/JS字节身份一致。证据目录 C:\Temp\AntigravityAA-browser-legacy-536-7ff4c935acd74182a49ad35d3595ac2f，review-red.log 和 review-green-ps5/ps7.log 保留红绿结果。打包首试用了不存在的本地vsce路径，未生成新包；改为项目固定 npx @vscode/vsce@4.0.0 后实际 exit0。未将夹具绿灯提升为本机验收，生产源码仍678e741，PR保持draft。

## Legacy 窄触发器本机失败（2026-10-07 23:44–23:51 Asia/Shanghai）

证据等级：已跑纯内存验证、已跑本机验证；该候选验收失败。独立审查又复现准备期间菜单被打开后默认动作将它关闭，补第十例并在原最终身份检查前增加准备后折叠状态复读。双引擎10绿、复审无新增发现；最终临时source=A5CF4BBEB4CB30C79ABE0139DD43C428316B87E91811A7D983B170F277CFF37D、VSIX=87D35B6E59700BB1B39EFE03342A279EAF6CE0BA8AE62622DB60CDC4DFE6FC8E、8条目源与JS字节匹配，官方CLI exit0。正常Restart后旧84424退出，94204/父36856、启动23:44:23.683375、23:44:24 ready，解码入口绑定真实安装路径和IDE；主IDE35596与原启动不变。

D536_BROWSER_LEGACY_001被Agent选择为read_url_content，23:46:01实际走普通Submit；Note静置后483个样本全部Note、197字符保留，窄菜单NOT_TRIGGERED。另一次明确要求browser_subagent的D536_BROWSER_LEGACY_002，真实nodejs.org卡片 More actions invoke=False/expand=True。15:49:52.1048320/.2094231准备前后Note，.2805590/.2825600触发前后也Note；却visible=0/new=0/once-items=0，反复调用仍未打开菜单，实际Allow Once=0、页面仍Waiting for user input。因此不算通过。

第二观察599样本/24资源/120011ms、无错误，静置起15:49:01.558Z后488个样本全部Note，SHA256=302F28C0A0D7D3D455ADE37F5D6E3C6A1C90381717E4E01F3E18D05954EEF226。普通Submit观察SHA256=B10C0F559926359FB3F8E7F839E75A0407434603C8FC314686A681E8CA7D5F85。23:51:05.142Z停止该观察案例，随后正常Stop Scanner于23:51:33停止，94204已退出；停止操作主动将IDE置前台，不归因插件。完整记录native-no-menu-failure.json/native-no-menu.log和native-submit-observer-summary.json在前节browser-legacy Temp目录。

根据[微软AutoSetFocus契约](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomation2-put_autosetfocus)与本地SDK完整四项ExpandCollapse接口、GUID619be086-1f4e-4ee4-bafa-210128738730及ID10005，在新Temp目录准备同一客户端的原生Expand实验，最终Allow Once仍Legacy。未改生产源码，未将上述失败候选合并或发布。

## 2026-10-08 本机原生客户端 Expand 候选失败

- 临时候选 F6AC6C6AB59753408BB0AA22F80D62BA51F1839BD203FA5116A9BC7594382AE2 在 PowerShell 5.1/7 完整 C# 编译、参数提前拒绝（桌面查询 0）和实际窄菜单函数 10 项内存回归通过后，使用官方 CLI 安装并正常启动 PID97176。未修改正式生产代码。
- 已跑本机验证：同一 AutoSetFocus=false 客户端的原生 Expand，00:02:45.2673414 前台为 Note329822，00:02:45.2938640 返回后为 IDE133218；随后的 Legacy Allow Once 执行一次并完成 Node.js 页面任务。独立 600 个样本、24 项资源记录、120016ms 观测中，对应相邻样本也记录 Note→IDE，鼠标和最后输入 tick 未变。观察文件 SHA256 AEB53A67B1101D9839793BDAB4C62F4002044F6EBC24AA6586DCF1F471C360C6。
- 结论：接口能展开和批准，但后台体验失败，不能发布。正常 Stop 于 00:12:25 停止，CIM 确认 PID97176 已退出，主 IDE35596 启动身份保持。完整记录位于 C:/Temp/AntigravityAA-browser-expand-536-53b2b79570a7427ead160962675fd817/native-expand-focus-failure.json。
- 下一步仅为假设：通过已绑定 Legacy 的 GetIAccessible 取得原生 MSAA 服务端，再查询 IExpandCollapseProvider；SDK 三方法契约与指针/RCW 所有权须先验证，接口不可用或原生焦点失败仍拒绝验收。

## 2026-10-08：原生 provider 取得失败与另一条只读原生路径

- 证据等级：已跑本机验证。GetIAccessible 直接取得方案两轮正常 Start/Stop；11544、101928 均已核对退出。初轮没有 prepare-after、Expand 或 Allow Once；错误诊断轮明确为 InvalidOperationException，HResult 80131509，Native MSAA server missing，即 GetIAccessible 返回空指针。不是最终展开失败或审批通过。
- 首轮只读观测600样本/24资源，321个交接后、主动结束前样本全为 Note；诊断轮300样本/12资源，206个交接后样本全为 Note。鼠标和输入状态稳定，保持前台来自没有执行动作，不能当体验验收通过。证据：C:\Temp\AntigravityAA-browser-provider-536-8590a6c027b4284683331eeac90e159d 下 native-provider-preparation-failure.json 与 native-provider-null-server.json。
- 已跑离线验证：完整 PrepareProviderExpand 方法的10项内存身份/所有权/异常测试在 PowerShell5.1、7均通过；根异常诊断只抑制连续重复，保留原异常，日志失败不遮盖动作错误。
- 证据等级：已读安装源码。工作台 F4BD347D... 的 acceptAgentStep 仅处理 runCommand、captureBrowserScreenshot、executeBrowserJavascript、openBrowserUrl，没有 browserAction；浏览器 Allow Once 回调绑定 cascadeId/trajectoryId/stepIndex。recordConversationInteraction 为复制/反馈遥测，不能作为批准入口。未找到精确、公开可供此扩展调用的 browserAction 提交 API；不盲调当前会话命令，不读取实际凭据或改变权限设置。
- 证据等级：已读官方源码。.NET WPF ExpandCollapsePattern.Expand 已调用 UiaCoreApi.ExpandCollapsePattern_Expand，单换同一个底层 C API 没有新的验证价值。Chromium固定142.0.7444.175 的 QueryService 允许 IID_IAccessible 服务后 QueryInterface；据此建立另一个 Temp 诊断路径：AccessibleObjectFromWindow(绑定HWND)→只读命中→映射完整 RuntimeId→原生展开服务。该新路径尚未本机验证，未并入生产、未发布。

## 2026-10-08：原生窗口和祖先窗口候选仍未匹配按钮

证据等级：已跑本机验证、已跑纯内存验证。第一原生窗口候选source1864002C...启动111368，在正常Stop后退出；最近60011ms/300样本、12资源记录全Note，SHA256 A75832E9D326C67CC2BBCB9B468109B90C0A1ACF20EA1A5E20224AC6AAC274E5。此前90秒观察在候选启动前已结束，明确排除，不作为候选验收。

D2272FEE...诊断候选PID106228启动01:12:21.716767、父36856。01:12:26明确原生外层childCount=0、target NativeHandle=0，期望42,198588,4,4,1,72691映射为42,133218,4,-18，零prepare-after/Expand/Allow Once。未启动独立观察器；01:17:30正常Stop后CIM核对退出。完整记录 native-binding-diagnostic-failure.json/log 位于 C:/Temp/AntigravityAA-browser-native-window-536-429fa59c0bb44640b0b81e209f0ffd1d。

审查另以HRESULT E_NOTIMPL/E_INVALIDARG复现诊断getter盖住原拒绝，局部catch(Exception)后两引擎红绿通过。新Temp原生祖先候选F8CD4BC053D7D544ED78A31D3931970DBF364189A531F5D5895CA77C144DB84C使用SDK完整13项TreeWalker，从绑定按钮向上取得最近原生窗口，外层root、深度32、顶层窗口或Win32PID不符均拒绝。所有原PS函数逐字不变。32项完整准备方法和10项窄函数回归双引擎绿，独立审查无新增发现，编码和8条目归档字节检查通过。VSIX D29304895E3FAE1891543469A8BC27509162AEC4C4180F9D55E3DB15322B0088，官方CLI exit0。

本机119436/父36856启动01:26:16.220147、01:26:17 ready，launcher和安装源码hash匹配。01:26:18只读命中进入正确原生窗口198588，却得到根对象42,198588,4,-115150（childCount=2），仍不等于完整目标RuntimeId。因此没有展开或批准，待批准卡片保留；01:28:04正常Stop后具体PID退出。独立观察90013ms、450样本/18资源、无错误，交接后348样本全Note、cursor1322,865/inputTick24138593稳定，SHA256 888CC5C1E6ACA5F225D845ADBBC2719E00147BFEA6284F1FA5AFCA307AE0D796；这仍是拒绝路径，不是审批通过。记录 native-parent-mapping-failure.json/log 位于 C:/Temp/AntigravityAA-browser-native-parent-536-44dd11f82d7a4be9b31288837eeef193。

正式生产代码仍678e741，PR12保持draft，未合并或发布5.3.6。下一步依据Chromium固定版UniqueId自定义属性和负childId映射做独立候选；先验证身份和接口，不放宽一次允许或最终宿主检查。

## 2026-10-08：UniqueId 候选本机拒绝与原包恢复

证据等级：已读官方源码、已跑纯内存及本机验证。Temp候选3AD657AE892EE8A224FC10FCA23A50803F987C14D876198883F82456908040DD根据固定Chromium UniqueId GUID，用公开Registrar三项完整SDK接口注册String属性；从已绑定target取得负编号，再查询原生后代、映射完整RuntimeId。移除坐标命中路径，所有PS最终审批函数逐字不变。45项完整方法回归双引擎均绿；独立审查补核PropertyInfo x64 size32/offset0,16,24、x86 size24/offset0,16,20，未发现新增可执行问题。缓存仅propertyId，两次准备重新取得target并逐项释放；拒绝路径零动作。

VSIX D69E67000BECFA612D2CC23708223015362262B9076898DF0FE8F2AB022ED0A3，官方CLI exit0、安装source/JS匹配。正常Start后121560/父36856，01:47:43 ready；01:47:44根异常Native target UniqueId missing（80131509），没有prepare-after、原生child查询、Expand或Allow Once。该错误只证明未取得可用负UniqueId，尚未区分属性不支持、默认空值或其它取值；不能将其概括为Native provider已测试失败。

独立60011ms/300样本/12资源记录、无错误，交接后157样本全Note，cursor1322,865/inputTick25424734稳定；SHA256 C3EE36E1F6B0684A133874134A7CC1834FECF4349E191485F348ECEE3AA4363E。观察在01:48:14结束，后续静置不补写为连续观测。01:54:30正常Stop后CIM核对121560退出。记录 native-unique-failure.json/log、离线日志与ABI布局在 C:/Temp/AntigravityAA-browser-unique-536-4c517afb2e664042a4154363a0ce7c98。

原包7ffae95通过官方CLI恢复exit0，磁盘source=7F732F0CAB9FEA2A9F8A3FCB029820A4BC36FE6D98A3F6C8EA6CBF89D18ADC0A、JS=2F85FBE50F0DF4EF35CC7C688602EA2B5D822951777B0159040057AE392EA1AD均一致。scanner保持OFF，未重启未通过候选，原待批准卡片与Note197字符保留。正式源码仍678e741，5.3.6不合并发布；下一步先查UniqueId取值/映射的实际语义，及MSAA代理与Native UIA对象是否可按公开接口保留同一身份。
