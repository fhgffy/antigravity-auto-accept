# v5.3.1 浏览器审批修复验证记录

日期：2026-10-06，Asia/Shanghai。本地源码、安装包和最终安装版本已完成下述验证；商店发布状态单独记录。

## 问题和证据范围

**证据等级：已读源码、已跑编译/回归、已跑实机验证。** v5.3.0 在 Windows Antigravity IDE 2.5.5 的浏览器域名审批卡片等待，已有终端单选审批分支不能处理该结构。v5.3.1 已通过同一个真实任务的窄布局滚动、展开和连续本次批准。

本机 IDE 的审批组件在宽布局显示 `Allow Once`，在窄布局将它折叠进 `More actions` 的 Portal 菜单。`Always Allow` 会修改持久域名允许列表，本修复选择本次允许。

## 当前实机结果

1. 编译、打包、强制安装 v5.3.1 并执行 `Developer: Reload Window`；确认扫描器 READY 和状态栏 ON。
2. 恢复同一个原待审批会话，不手动点击批准按钮。
3. 窄布局诊断显示候选结构匹配，但 `More actions` 横向离屏。仅滚动该区域后，可见性恢复，窄菜单仍未完成审批。新增受限诊断显示该控件 `invoke=False scrollitem=True expand=True`，普通 Invoke 调用与控件实际接口不匹配。
4. 仅扩大侧栏，使 IDE 显示宽布局按钮。插件自动调用 `Allow Once`，原任务打开页面、提取 DOM，并继续请求下一页。
5. 连续三次本次批准后恢复原窄布局，下一审批仍等待。依据真实模式加入当前控件的 ScrollItem/ExpandCollapse 操作后，再安装并重载。原窄布局连续自动滚动、展开并批准，未人工调整布局或批准。
6. 独立审查复现宿主查询期间卡片或菜单变化后仍批准的问题，移动已有最终检查并补回归。最终版本重新安装、重载、恢复同一会话，再次连续自动批准浏览器请求，原任务继续读取目标开源项目源码。

脱敏日志：

```text
[07:31:12] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
[07:31:19] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
[07:31:28] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
[07:51:11] browser scroll returned=True visible=True
[07:51:11] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
[07:51:21] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
[07:51:31] browser scroll returned=True visible=True
[07:51:31] Auto-accepted (Invoke): "Allow Once (browser domain permission)"
```

操作中未人工选择 `Allow Once`、`Always Allow` 或拒绝；未修改终端或域名持久允许配置。实机截图保留在本地，不将用户会话内容上传仓库。

## 回归与安装包

| 验证 | 最终结果 |
| --- | --- |
| TypeScript 编译与类型检查 | 退出码 0 |
| 规则 SelfTest | 每个 PowerShell 引擎 95 项通过 |
| 扩展生命周期 | 20/20 通过 |
| 扫描器，PS5 + PS7 | 64/64 通过 |
| 仅系统 PowerShell 5.1 | 63/63 通过 |
| 独立复审 | 10 个针对性用例通过，无未解决 P1/P2 |
| UTF-8、CRLF、AST、diff | 通过 |

扫描回归使用真实生产函数、实际扫描尾段和无点击桩，不把它写成所有路径的实机验证。旧版副本分别验证窄卡片漏批、全窗回退越界、菜单改属、诊断被节流、模式不支持及宿主查询期间状态变更会失败。

最终运行文件在工作区、VSIX、已安装目录中 SHA-256 一致：

```text
src/autoClicker.ps1 = 55DFE5BCE1459546190A31E1B9D7032210370B41DA1DA875F120DA0D3F85461A
out/extension.js   = 03F1B2785D613E52A9C81BF14AE1D10D687B2D9A69260BE2C41F1A0A40B38414
VSIX               = 74EE652F0F3E8EAA84794774C0AC6187D59EC075DC12A29129DDB4DED942AA24
```

VSIX 仅包含 8 个运行和展示文件。VSCE 改写 README 相对链接，打包 README 与安装 README 一致。IDE 为已安装清单追加 `__metadata`，其余全部清单字段与源文件和 VSIX 语义一致，版本为 5.3.1。

复现：`npm ci`、`npm test`、`npm run package`，安装生成的 VSIX 后执行 `Developer: Reload Window`。

## 发布状态

- 本地 v5.3.1 已安装并完成上述验收。
- VS Code Marketplace 和 Open VSX 尚未上传新版。浏览器文件上传依赖 ChatGPT 扩展的文件网址访问权限；工具的 URL 策略禁止代改扩展管理设置，需要用户手动开启，上传后手动关闭。不能把管理页已登录当作已发布。

本记录不表示所有工具审批类型、中文界面、旧版 IDE、远程环境或物理点击回退均已实机验证。
