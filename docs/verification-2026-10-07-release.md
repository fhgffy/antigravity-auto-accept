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
