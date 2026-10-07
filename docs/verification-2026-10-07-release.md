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
