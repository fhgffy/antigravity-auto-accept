# v5.3.2 终端审批位置与滚动修复验证记录

日期：2026-10-06，Asia/Shanghai。

## 问题及实现

**证据等级：已读源码、已跑回归、已跑安装和部分实机验证。** 在 IDE 2.5.5 的原任务中，v5.3.1 无法发现聊天区域之外的专用终端审批表单。真实控件父链是 Radio → radiogroup → 同一个 Group，包含 Edit permission target、同前缀一次/持久/拒绝选项和唯一 Submit；长命令使下方 Submit 离屏。

本机 IDE 源码确认专用 ask_permission 组件既可出现在 conversation 内，也会替代输入区域。v5.3.2 在已锁定宿主窗口发现精确的一次允许选项，保留同表单严格结构检查。滚动只针对已经核验的动作控件；每次选择或提交前重新检查目标 Edit 的 runtimeID 与 Value、表单归属、选中状态、宿主身份和父宿主存活。命令正文只用于内存比较，不进入日志。

普通问答虽然也使用 ask-opt ID，但没有专用 permission target，因此不会批准。最终动作控件必须可见；已选的一次允许可因提交按钮滚动而离屏，只读核对其选中状态后才提交。

## 回归与独立审查

| 验证 | 结果 |
| --- | --- |
| 编译及类型检查 | 退出码 0 |
| SelfTest | PS5/PS7 各 95 项通过 |
| 扩展生命周期 | 20/20 通过 |
| 扫描器 PS5 + PS7 | 90/90 通过 |
| 仅系统 PS5 | 89/89 通过 |
| 独立补充无桌面桩 | 133 项通过，无剩余 P1/P2 |
| UTF-8 无 BOM、纯 CRLF、AST、diff | 通过 |

隔离旧 5.3.1 扫描器副本运行同一套新增用例，五个会话外及滚动阳性场景实际失败，退出码 1；新扫描器通过。阴性覆盖普通问答、重复 Submit、选项前缀不一致、目标值改变、同值目标替换、滚动失败或仍离屏、表单换属、选中丢失、宿主改变及父退出，均不提交；滚动后场景还断言滚动确实发生，避免提前异常产生假绿。

这些回归执行生产函数并用无点击桩替代桌面控件，不能写成会话外长表单已完成全部实机验证。独立审查还发现 main 已有 LegacyIAccessiblePattern 降级类型在 PS5/PS7 不可用；无法读取 selected 时会安全跳过。本版本没有修复或声称验证该旧降级路径。

## 安装与真实任务

已强制安装生成的 5.3.2 VSIX，执行 Developer: Reload Window，并恢复原会话。日志显示 5.3.2 激活、已安装目录中的扫描器启动和 READY，状态栏 ON。

该真实任务连续执行 GitHub 只读检索命令。插件在 08:22:34、08:22:45、08:22:55、08:23:04 自动提交本次允许。另暂停扫描，捕获正在等待的真实终端表单；恢复 ON 后 08:23:59 自动提交并继续任务，全程未手动选择一次允许或 Submit。

脱敏日志：

```text
[08:19:49] Antigravity Auto Accept 5.3.2 (UIAutomation) activating...
[08:19:53] UIAutomation scanner ready
[08:22:34] permission option enabled=True offscreen=False selection=True scrollitem=True
[08:22:34] permission submit enabled=True offscreen=False invoke=True scrollitem=True
[08:22:34] Auto-accepted (Invoke): "Submit (one-time permission)"
[08:23:12] Stopping scanner...
[08:23:46] Starting UIAutomation scanner...
[08:23:59] Auto-accepted (Invoke): "Submit (one-time permission)"
```

暂停时捕获的表单实际位于 conversation 内；不能将这张截图写成会话外表单验收。会话外与长表单目前由已读 IDE 组件、原故障控件树及红绿回归支撑，仍需相同布局的进一步实机验证。原 Claude 模型达到额度限制，切换 Gemini 后任务可以继续；原开源修复 PR 尚未完成，不能把自动批准等同于 PR 已提交。

## 安装包一致性

工作区、VSIX 和安装目录的两个运行文件 SHA-256 相同：

```text
src/autoClicker.ps1 = 9AAB23176B0E81CC206400769D5587FF4782F8493DC4D561F9BC78BEE9B0F4B8
out/extension.js   = 03F1B2785D613E52A9C81BF14AE1D10D687B2D9A69260BE2C41F1A0A40B38414
VSIX               = A9F798BFAC2D82C673575A0B4586902DBD435E10BFF19250283FA534749FEDA3
```

安装清单版本为 5.3.2。VSIX 包含 8 个运行及展示文件，不含本地截图、用户会话或测试证据目录。浏览器审批实现保持 5.3.1 已验证路径。

复现命令：npm ci、npm test、npm run package；安装 VSIX 后重载窗口。商店发布状态必须以管理页结果为准，不以登录、文件选择或 GitHub Release 代替。

## 2026-10-06 后续真实任务验证

**证据等级：已跑实机观察、已读 GitHub PR 状态。** 原 IDE Agent 在相同会话继续执行开源检索、测试脚本生成、pytest、pre-commit、提交及推送。5.3.2 持续保持 ON；实际输出在 08:47:32、08:53:28、08:56:26、08:58:06、09:18:14 和 09:18:34 记录本次允许的自动提交，命令随后继续执行。测试人员只向 Agent 提供审查反馈，没有手动选择审批选项或 Submit。

原任务已创建 [Arrow PR #1367](https://github.com/arrow-py/arrow/pull/1367)，并根据独立审查补充多粒度日期回归；PR 为 OPEN，尚未被上游维护者合并。自动审批验证与代码审查、项目 CI、维护者验收分别记录，不用插件成功点击代替贡献质量结论。

本轮捕获的终端审批仍在 conversation 内，包括较长命令与 pre-commit 阶段。后续真实任务证明已安装插件可以持续完成正常终端审批，但没有补齐会话外布局的实机验收，前文关于源码和桩回归的证据边界继续适用。

5.3.2 已发布为 [GitHub Release](https://github.com/fhgffy/antigravity-auto-accept/releases/tag/v5.3.2)。插件商店须以独立上传和验证结果为准；GitHub 发布不代表商店已更新。
