# 5.3.5 窗口进程查询验证（2026-10-07）

证据等级：已读源码、已跑验证。基线为5.3.4提交7f7f912e3f6a691fecbaea4cbf58583d8f1d0fd9；本轮保持审批匹配、一次允许、控件身份及输入复核，修改宿主进程查询。

## 已复现的问题

PS5 x86实际查询本机14个x64 IDE进程时，旧Process.Path全部为空；MainModule读取均报Win32错误299，原Get-TargetProcessIds返回0。相同PID通过完整映像路径查询后，14/14符合原宿主路径匹配。另有实际旧函数的控制依赖红灯：有效PID123的Path读取失败时被遗漏，native路径替身提供合法完整路径仍无法使用。

## 性能定位

将Path直接换成native而保留Get-Process枚举，两种整轮耗时仍约200ms，没有证明整体提速。PS5 x64同一快照三轮分解：

| 边界 | 三轮耗时范围 |
|---|---:|
| Get-Process按名称枚举 | 183–222ms |
| 读取已有14个Process.Path | 5–12ms |
| 查询相同14个PID的native路径 | 5–13ms |

最终方案从本轮顶层窗口取得PID，只查询该进程，每次动作前重新查询完整路径，没有跨轮PID缓存。原生方法在同一个句柄查询前后检查非退出状态，并在finally关闭句柄；普通路径使用512字符缓冲，只有错误122时扩到32768再试一次。接口采用Unicode和Win32路径格式，完整ExpectedPath匹配不变。[路径查询合同](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew)、[等待合同](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject)、[句柄关闭合同](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle)。

有限native对照中，相同14个PID三轮为30.918、6.623、6.814ms，打开42次、关闭42次，84次零时等待均为258，失败0。该对照说明可以避开全系统枚举开销，不能替代完整扫描器CPU测量。

## 落盘生产与回归

实际生产源码SHA256：E9EDCF0720CE3DF80466EDA06808D60B830333DAE316A760A287A79F111BC30C。

独立PS5 x64/x86子进程只抽取未修改的生产C#块及两个PS函数，未加载桌面扫描：每个引擎三轮均识别固定14/14个真实IDE PID，测试子进程自身被拒绝，exit0、stderr空；没有显式GC或停止已安装扫描器。x64三轮62.849/16.940/36.900ms，x86为52.235/14.192/10.666ms；这些是函数查询总耗时，不能与另一原生方法层的小样本当作相同工作量。

新增host-process.test.ps1在PS5 x64、PS7 x64、PS5 x86各125项通过：执行生产PS/C#方法，只替最底层native依赖，覆盖精确PID、路径变化、同名不同目录、异常隔离、Unicode、权限拒绝、前后等待、122扩容和finally释放。还实际启动自有32/64位子进程，核对真实位数及路径；退出259并保留句柄后必须拒绝。CI增加同样的三引擎验证。

独立变异测试得到行为红灯：删除查询后的等待，会返回刚退出进程路径；浏览器最终宿主查询漏传PID，会遗漏应批准的narrow卡片。两个案例均解析成功，失败来自行为断言。

## 全量测试中的失败与处理

首轮完整npm回归在并发父进程退出测试失败。旧生命周期fixture通过空进程图跳过窗口枚举；新入口开始按窗口查PID后，缺少automation对象而反复产生InvokeMethodOnNull。独立持续收集输出的相同生命周期，在父进程退出后76ms正常退出0。未消费的输出可能阻塞退出检查，原现场没有线程栈，不能声称直接证明WriteLine卡点。

现有两个生命周期fixture改为显式空窗口树，并加载UIAutomationClient和UIAutomationTypes；仅Client的中间fixture曾产生TreeScope缺失，失败日志保留。并发退出检查先异步收集输出再等待退出，错误诊断仍判失败。修复后的并发22项、两轮、两引擎退出0。独立审查还复现单实例测试忽略exit0尾部ERROR/stderr，现owner与waiter均严格校验尾部输出。最终完整npm test退出0：编译与类型检查、仓库3项、生命周期28项、自测95项、扫描器127项、宿主查询每引擎125项、鼠标每引擎81项、并发22项；PS5x86的宿主查询125项另外通过。

## 实机边界

同用户真实IDE进程已验证新增查询与等待权限；真实IDE安装、合并后的CI和长期资源趋势另行记录。5.3.4的多应用输入记录见[输入验收](verification-2026-10-07-input.md)。本轮短程路径查询没有证明长期内存增长已解决，也没有新增审批发生时保持焦点、混合DPI多屏或真实物理输入的证明。

本地npm package退出0，validate-vsix实际检查8项及运行文件字节一致，版本5.3.5。安装包SHA256：DCA7D7F07B752E437467E416ED4AF08894CA7CD42FBD4668F66F1437531EFF1A。独立源码审查无剩余可复现P1/P2；编码、AST、diff检查和actionlint通过。
