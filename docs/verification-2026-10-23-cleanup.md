# 2026-10-23 测试清理路径的模块依赖

证据等级：已读源码、已跑本地控制；最终 CI 和发布另记原运行回执。

## 原始失败

发布候选 `229ccc1d12fc8c93901cf76a445fcf5eac70a8c2` 的首次 push 运行 `39953443761`、PS7 作业 `120413328410`，在 host-wrapper case 32 失败。该检查预期错误创建身份被拒绝，实际 `stopOwnedFixture` 启动的独立 `powershell.exe` 在原 10000 ms 上限返回 ETIMEDOUT；用例耗时 10092.4448 ms。同提交 PR 对应检查成功不能抵消该失败。

原失败包 artifact `12502095737` 的 SHA-256 为 `c6842a0c43d56a7ac84c134c5ac35b52f5f3fe35a40968d54bf1219b516e8924`，978389 字节、CRC 正常、87 个唯一安全成员。本例仅留下独占控制 EXE 与 PID，没有该清理调用的阶段日志或转储，不能判定耗时发生于进程启动、模块加载或属性读取。首次失败回执明确 `AcceptancePassed=false`。

## 有界修改与验证

- 清理入口以核心 `Diagnostics.Process.GetProcessById` 代替 `Get-Process`，并禁止此子进程自动加载命令模块。只有查找本身的 `ArgumentException` 按 PID 已消失处理；其他异常继续失败。
- 保留同一 Process 的句柄、路径、创建时间、Kill、WaitForExit、Dispose，以及原 10 秒外层和 5 秒退出期限。没有修改扫描器或扩展运行代码。
- 启动/超时返回错误时先保留 PID、返回字段及 UTF-8 解码两流，再抛原错误；取证写入失败不替换原错误。这些字符串不是原始输出字节。
- 关闭模块自动加载的原入口红例失败于 Get-Process 不可用；换为核心查找后，同一错误身份拒绝和目标存活检查通过。该对照证明消除了额外模块依赖，不能证明云端原十秒超时已定因。
- 两个尾部控制覆盖真实已退出的自有 PID、非 ArgumentException 传播，以及模拟启动错误时诊断写入成功/失败两条路径。尾部放置避免预热原有冷启动案例。

私有证据根：`F:\CodexTests\AntigravityAA\resource-stability-20261021\work\cleanup-module-boundary-20261023`。原云端失败归档位于 `evidence/ci-release-5-3-14-229ccc1/strict-original/first-attempt-failure-readback.json`。补充控制最初的 VM 缺少 Buffer、私有路径未规范化失败均保留，修正仅涉及私有控制环境。接入测试时的尾部空行被原 whitespace 检查拦住，该次失败同样保留，删除多余空行后才继续验证。

本修改属于测试维护，不单独发布新版本；5.3.14 的运行优化来自已合并的 PR #52。原等待者内存及首小时增长阈值失败不受本修改影响。
