# 5.3.12 自测桌面依赖修复（2026-10-21）

证据等级：**已读源码、已跑定向验证**。本记录区分可确定复现的桌面依赖与尚未定位的远端偶发超时。

## 触发与边界

5.3.11 已在 GitHub、Marketplace、Open VSX 三处实际下载核验，SHA-256 均为 `2da1df5fcea17e3792aeffa15bb5d9f644bee14e9e690bc3d1b4254b87a9252e`。随后仅改文档的 `5d32e09` 在 push CI [39468882798](https://github.com/fhgffy/antigravity-auto-accept/actions/runs/39468882798) 的 PS7 SelfTest 超时；同提交 PR CI 39468971066 成功。没有重跑失败作业。

首次失败 PID9016 在原 15 秒后被确认退出；stdout/stderr 的异步读取均完成但内容为空。正常 SelfTest 原先也只在结束时输出，不能据空输出判断卡在 PowerShell 启动、C# 编译、程序集加载、桌面读取或具体断言。原日志 `ci-job-118787379266-5d32e09-first-failure.log` 保留；[Issue #26](https://github.com/fhgffy/antigravity-auto-accept/issues/26) 跟踪本次调查。

## 确定性红绿与最小修复

实际源码在 `-SelfTest` 入口前读取 `AutomationElement.RootElement` 并创建 8 个扫描条件，而 95 项自测只依赖标签、路径、卡片、矩形等纯判定。回归在独占临时副本中把唯一桌面 getter 替换为 `SELFTEST_DESKTOP_ACCESS_PROBE` 异常；其余完整脚本、C# 编译、程序集加载和真实 SelfTest 都保留，不查询真实桌面。

- 红例：原源码在 PS5/PS7 均因该精确探针异常失败，`selftest-desktop-dependency-first-red.log`；不是把编译错误或超时当成成功复现。
- 绿例：只将桌面根和 8 个条件放进 `if (-not $SelfTest)`，两引擎全部 95 项、零 stderr、退出码 0 通过，`selftest-desktop-dependency-first-green.log`。原 15 秒未放宽。
- 正常扫描和显式 `-SelfTest:$false` 仍按原顺序初始化；PowerShell `if` 不新增作用域。22 个函数和内嵌 C# 字节未改，匹配表留在分支外。逐字边界回执为 `selftest-desktop-source-boundary.json`。

包装器另增加立即 Flush 的 bootstrap、source-read、scriptblock-created 三阶段旁证，位于测试代码中，不改生产输出协议。原 timeout 回归仍要求真实停滞失败、同一 Process 退出、两条流完整、有效 DONE 也不能掩盖停滞；新增阶段断言首次在两引擎均红，`selftest-bootstrap-phases-first-red.log`。阶段信息用于以后定位，不能倒推 PID9016 的历史卡点。

## 版本与验证记录

- 原生产扫描器 SHA-256：`528b83b22e77cc6e7d3e3408e407aa41ea14d834d26723aec68f209ee702f3db`。
- 修正扫描器 SHA-256：`b947655c5e16c21b16ba55c6712c710568539519ca7904c79400226902b163bf`。
- 5.3.11 的 M1–M8 原生证据见 [并发验收](verification-2026-10-20-concurrency.md)；这里只按正常扫描路径字节/控制流等价复用，不声称对 5.3.12 重新运行 35.56 分钟实机测试。
- 完整 Node 22.23.3 `npm test` 退出 0：扫描器184、进程检查每引擎131、包装器24、鼠标判定每引擎188、并发22；`full-test-selftest-desktop-5312-node22.log`。本地 VSIX 8项/运行字节校验通过，`vsix-5312-local-validation.log`。
- 普通启动及显式 `-SelfTest:$false` 两引擎4项均进入原初始化分支；使用同一 getter 异常探针而不访问真实桌面，`normal-initialization-5312-results.json`。独立审查者另在 Node22 下运行完整源码探针及15秒超时共4项，全部通过，`review-5312-selftest-independent.log`。
- 最终head `c264b5cb1c778fd33b25dc6735c71f08b744f1ab` 的 push39472559033、PR39472569252均success，两个测试引擎及VSIX成功，非main发布按条件skip。独立最终head审查无阻塞；精确门禁通过后PR #25合并至 `3f5155521e53edeecf013d83d371da69970c3796`，Issue #26关闭。main39473575714四作业均success，原日志 `main-ci-39473575714.log` 保留。

证据根目录：`F:\CodexTests\AntigravityAA\concurrency-20261020-7d2c\evidence`。最终发布结果及用户待办收录于上级目录的 `final-report.md`。

## 发布快照

5.3.12 正式原包已由 main 39473575714 四作业成功后生成，标签固定3f5155521e53edeecf013d83d371da69970c3796，资产660118710、82204字节。下载包、GitHub digest、校验文件及8项VSIX/运行字节校验通过，SHA-256为a62d7cc64dc4079b86d597f9182cc6465a601e3b3b26c90ff47c41cadaf06a4d。

发布快照时间（UTC）：2026-10-20T18:29:37.3454587Z。Open VSX于2026-10-21 02:29:37+08:00通过原CI函数的精确版本及实际公开下载SHA核验，与GitHub原包一致，public-final12-openvsx.json；首次审核中404及会话Forbidden仍保留；Marketplace已选正式原包、需本人完成新图片验证码。该快照不计三处完成，不创建新凭据或绕过验证码。最新公开下载核验与完整收尾状态以 [Release记录](https://github.com/fhgffy/antigravity-auto-accept/releases/tag/v5.3.12) 及本轮 final-report.md 为准。

GitHub核验回执：`github-original-final12-verification.json`。Open VSX首次Forbidden、刷新后接收审核、首次公开404及Marketplace人工验证码现场均保留；无重复上传审核中的版本。CI未配置商店凭据，日志明确not-configured；后续沿用已有网页账号发布，不将CI作业success当作两个商店发布成功。
