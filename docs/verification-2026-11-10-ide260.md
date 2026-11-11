# IDE 2.6.0 兼容维护与原生验证

2026-11-10 至 2026-11-11。5.3.17 已合并并在 GitHub Release 公开；main CI 与匿名下载原包均已核对。Marketplace / Open VSX 因缺少发布身份尚未上线。

## 维护判断与范围

**已读源码、已跑验证**：项目仍有兼容维护价值。原生 Turbo 已覆盖本机普通终端与文件读取；但独立项目的 PreToolUse `force_ask` 仍能产生真实权限卡，5.3.16 会漏批。修复后已自动提交真实终端卡，工具原始 stdout 与退出码均已核对。它的适用范围是仍出现审批的工作流，而不是每个 Turbo 用户都必需。

官方更新按产品线区分：[IDE 更新记录](https://antigravity.google/docs/changelog) 当前列 IDE 2.6.0（2026-10-26），更新内置 Agent 界面和架构；App 2.31.0（2026-11-09）新增浏览器下载审批。后者不能当作 IDE 的实测结果。[权限页](https://antigravity.google/docs/permissions) 标明 App / CLI；[浏览器站点规则页](https://antigravity.google/docs/ide/allowlist-denylist) 同时列 App / IDE。普通任务已无审批时，直接使用原生设置即可。

- 起点为 5.3.16 的 `8bdddf5d68fef7d553bc158c852431ed50f6e4ae`。修改前冻结并备份工作区既有兼容修复、回放和历史验证文档；未清理已有改动。
- 正式 5.3.16 VSIX SHA-256：`0bed7f29903b4b59a05fe43925e30b250d095fefdaddc4fd332e8177e8dc5e02`。
- 本机 Windows IDE 2.6.0，F 盘独占用户数据、扩展及空白工作区；实际后端 1.4.10。没有修改日常安装、全局 Turbo / 计划 Always Proceed / 浏览器 JavaScript Disabled、账户、拒绝规则或代理。
- 项目产品原则保持：启用即代批，范围类 Allow 仍自动批准；登录、OAuth、验证码、付款、工作区信任、拒绝规则及企业策略不作为通用审批。

## 根因与运行改动

1. **已读源码、已跑规则验证**：权限范围过滤可只留下本次与拒绝，旧规则强制至少三项并必须存在 always allow；现在接受合法两选项表单，仍核对唯一目标、同一问题、本次允许、拒绝和唯一 Submit。额外 URL 会话选项也按实际文案识别。
2. **已读源码、已跑原生验证**：本轮真实单选项到完整权限卡有四层父节点，Submit 也在嵌套分组内。旧版及第一候选均出现 `permission-card shape mismatch`。现在最多沿六层父链取最近完整卡，遇 Document / Window 截断；发现和每个滚动、选择、提交前的归属复核同步改用该路径。原卡 RuntimeId、目标 RuntimeId、目标 Ordinal 值、宿主、可见性与选中状态门保留。
3. **已读源码、已跑离线发现验证**：新版 Agent 文档没有旧 conversation 容器。仅在旧路径不存在时查找 active-frame / RootWebArea、本地 HTTP loopback 首页或精确 /c/UUID 恢复路径、唯一 root，以及各只出现一次且大小写精确的 extensionView=true / extensionVariant=vs-code。普通预览、歧义根、冲突或裸重复键均排除。浏览器站点批准本轮尚未原生验证。

## 红绿与构建证据

- 正式 5.3.16 原扫描器在新增过滤表单首例失败：expected=True / actual=False。
- 第二窗口原生 active-frame / RootWebArea 实际保留 /c/4319b7ab-4d68-4d21-bfde-9bfc7e3a62ac，旧根路径限制漏掉该内置文档。生产发现入口新增 10 路径用例，修复前 restored conversation expected=1 / actual=0；只增加精确 /c/UUID 路由，设置、预览、未知及 UUID 后缀路由继续拒绝。
- 两轮查询边界最小红灯覆盖冲突首值、无等号同名键；修复后两引擎均通过原 11 布局、75 名称、13 过滤表单、13 范围及 11 查询边界。
- 真实嵌套布局先进入生产 Invoke-ApprovalCards，修复前 `native selected expected=1 actual=0`；修复后新增 10 项全部通过，原有回归保留。
- 恢复路径与两项边界回归合入后的完整 `npm test` 退出 0（扫描器 passed=196、路径 10 项）；路径回放也已在 PowerShell 7 通过。独立 WinPS 5.1 与 PowerShell 7 全扫描器均退出 0、passed=196。边界节点 FindAll 故意抛错，直接调用定位函数可防止入口吞异常产生假绿灯。
- 独立代码审查无必须修复 P0–P2；另外离线核对两种边界、同目标双卡与动作中改名，3 种 URL 编码重复键也均被真实发现入口拒绝。审查不操作桌面，不计原生批准。
- 首次 npm 打包 ECONNRESET 保留；使用已有固定 VSCE 4.0.0 离线缓存后打包和 VSIX 字节校验均退出 0。最终 routefix 包完成 8 文件校验并安装，源码、包内与实际安装扫描器 SHA-256 同为 `07c1e806b7b0c9aa6ec8e1c075a9b8b807f41f76308f8ac06a74139126b17877`；TypeScript 运行字节本轮没有变化。该本地 VSIX SHA-256 为 `40b37b624f1d53b749077c1bedee9a34e3349af5d0420205017b42d98f2c68a4`，不当作后续 main CI 原包。
- 修改文件严格 UTF-8 无 BOM、CRLF；产品及测试 AST、git diff --check 已通过。最终分发包与公开渠道另核，不将本地候选包当作商店发布。

## 原生场景

| 场景 | 本轮结果及证据边界 |
| --- | --- |
| Gemini 4 Argon | 工具产生前官方 HTTP 400 地区限制；不是插件漏批。按用户提示找到既有排障 skill，改选已有 Claude，未提取凭据或改代理。 |
| Claude 普通终端 | Turbo 下真实 Write-Output 返回原唯一标记，未出现审批，不计插件批准。 |
| 项目外专用文件 | Turbo 下读工具及标记已出现，没有审批；模型引用与完整原始读步骤分开，不计插件批准。 |
| MCP 正式版基线 | 项目本地 force_ask 产生 approval_echo 卡；正式 5.3.16 连续 shape mismatch，卡保留、工具无执行记录。 |
| MCP 第一候选 | 同样因四层分组漏批。父链修复后同一张卡自动提交，随后超时；全新请求约 1 秒内自动提交，仍在 3 分钟后超时。批准已验证，MCP 工具执行未成功，不以卡片消失或模型复述充数。 |
| 命令 CASE_G | 18:48:09 自动提交，随后展开实际 Ran 步骤：命令 Write-Output 'AA_NATIVE_APPROVED_COMMAND_20261111_G'、stdout 同标记、退出码 0。**已跑原生批准与执行验证。** 模型自述“没弹窗”不作为验收依据。 |
| 待批启停 CASE_K | 两窗都 OFF 时完整卡保留；另一原窗口启动扫描器取得 owner 后在 19:05:38 自动提交。已展开实际 Ran echo output，命令、原始 stdout AA_NATIVE_AFTER_STOP_20261111_K 和退出码 0 核对；不是模型摘要。 |
| 最终安装 CASE_M | 最终扫描器字节在原窗口 19:25:28 自动提交真实卡；已展开 Ran run PowerShell echo，核对实际命令与 stdout AA_NATIVE_FINAL_20261111_M / EXIT=。模型额外添加了输出 LASTEXITCODE 的无副作用命令，完整实际目标纳入哈希；空 EXIT= 不当作退出码证明。 |
| Read URL | 普通提示未发出该类工具调用，不能据单一模型自述断言 IDE 全局不提供该工具。 |
| 浏览器 /browser | 界面命令存在，但执行前出现 Remote Debugging Required，要求 Chrome 开启远程调试及连接授权。未代操作本人浏览器授权；本轮未到站点审批，不计成功，也不判浏览器规则失效。 |
| Retry / 计划 / 登录等 | 代码规则及回归继续排除；真实 Gemini 错误页 Retry 没有被点击。不是本轮已批准场景。 |

CASE_K 归属：原 IDE 根 PID 48904、HWND 6359514、创建时间 2026-11-10T23:13:45.350475+08:00；完整卡 `42.592530.4.25.7.2078`，目标 SHA-256 `25517c8968587f598a782d177ee56ea24cbb3c3e943d48f536aff7f95520879d`。待批 UIA 与展开的原始输出分文件保留。G / K 对应安装扫描器为父链修复后的 `54eb...`，恢复路径后续改动只涉及浏览器文档发现，不把它们称为新字节的重跑。

命令 CASE_G 归属：IDE 根 PID 43212、HWND 1769668、创建时间 2026-11-11T18:24:48.982345+08:00；完整卡 RuntimeId `42.2100434.4.13.7.3197`；精确命令 UTF-8 SHA-256 `12fa35cddb514c186d5d24859ab370e02a77a5c0b8af33e11fcb307cd3903afd`。实际命令文本独立计算相符，扫描器只有对应一次成功事件。没有将钩子执行时刻当成严格卡片出现时刻或正式延迟指标。

MCP 目标 aa-approval-probe/approval_echo 的 UTF-8 SHA-256 `34a30d9856c94d6fd4c8d59bb6384d42f617fa965f7bdc44109d75ccfc9f8984`；两次批准完整卡分别为 `42.2100434.4.13.7.2196`、`42.2100434.4.13.7.2821`。Python 独立协议校准能返回固定标记，校准目录与原生调用日志分开；它不证明 IDE 的实际工具执行。全新会话 CASE_J 也在约 2 秒内批准（卡 `42.2100434.4.13.7.5327`），随后同样超时；不再以更换提示反复重试。旧候选窗口未重载 MCP 配置，不能声称其协议已被追踪；原窗口新 MCP 进程 PID 47640 已启用方法级追踪。CASE_L 在两个扫描器 OFF 时人工选择本次并提交，同样于 19:17:01 超时；该进程只收到初始化、tools/list 和 notifications/cancelled，未收到 tools/call，原生工具调用日志未产生。此对照说明问题并非仅由自动点击产生，具体后端或协议原因仍未定位，MCP 执行不计成功。

CASE_M 仍为 PID 48904 / HWND 6359514，完整卡 `42.592530.4.25.7.3304`；实际目标 `Write-Output 'AA_NATIVE_FINAL_20261111_M'; Write-Output "EXIT=$LASTEXITCODE"` 的 UTF-8 SHA-256 为 `100823a196c5f78a3c10bef4f5dd606cc2f0fcd4d38707fcc839c604db6e73d7`，与唯一成功日志相符。最终运行字节同时将该 /c/UUID 文档由 conversation missing 转为 browser candidates；这只证明容器发现，不证明浏览器站点批准。

## 环境与失败原件

- 独立 user-data 不隔离共享后端设置。原窗口重载触发后端 1.5.5 更新，三次 socket 下载失败后回退缓存 1.4.10；第二窗口使用同一有效缓存版本。原请求随重载中断，不跨实例拼为同一张卡；没有宣称已验证 1.5.5。
- 项目钩子第一次因 Windows 后端保留脚本路径引号而失败，原配置与错误保留；修正本轮无空格路径引号后才产生审批卡。只记录工具方法与步骤，不记录参数、凭据或业务文件。
- HTTP 辅助服务到达预算退出的首次拒连属于夹具失效；新实例 PID 51708、创建时间 18:15:30、回环端点重新核对 200 后才测试 /browser。直接 HTTP 控制请求不计浏览器访问。

证据根：`F:\CodexTests\AntigravityAA\value-20261110-230929`。原始失败、基线 VSIX、源码、红绿日志、安装字节、窗口身份、UIA 与扩展日志保留。原生资源长测的历史结果只引用已有记录；本轮未重新声称小时稳定性、全部权限类型或所有后端版本均通过。

## 收尾与发布边界

两个独立测试扫描器均正常停止，两个 IDE 窗口正常关闭；按原 PID 与创建身份复核，两 IDE 根、后端、MCP 子进程和 HTTP 辅助服务均已退出。最终两窗扩展日志按只读共享句柄归档并验证读取时长度稳定。F 盘独占测试目录和失败原件保留，未递归删除或清理日常配置。

版本发布使用同次 main CI 原始 VSIX，公开下载与商店状态另行记录；缺少商店凭据的绿色作业不算商店成功。

## GitHub 发布回执（2026-11-11 19:52）

- **已跑验证**：[PR #70](https://github.com/fhgffy/antigravity-auto-accept/pull/70) 的 head `5529082488dbf43c3ac7ad50c52df4e8ecc7988b` 经两引擎、包与 lint 校验后合并；main `92031c12e8ccd6f2d89caf1a3e5dadfcc7f2dcb7` 的树与该 head 相同。
- [main CI 43013835548](https://github.com/fhgffy/antigravity-auto-accept/actions/runs/43013835548) 两引擎、32 位扫描器及并发补测、Verified VSIX 和发布作业均成功。CI 观察客户端的首次 EOF 保留，直接查询同一原 run 后继续，没有重新触发构建。
- [GitHub v5.3.17](https://github.com/fhgffy/antigravity-auto-accept/releases/tag/v5.3.17) 于 2026-11-11T11:46:57Z 公开，非草稿、非预发布；标签指向精确 main CI 提交。Release ID `441621579`，VSIX 资产 `735329241`，同次 CI artifact `13852690843`。
- 原包 SHA-256：`2a40f7fe7e289acbbff5d51b1c3be18bed20150cae16e07fab2420c523b3c0c3`。同次 CI 原包、匿名公开下载、Release API 摘要和两份校验文件一致，8 文件运行字节校验通过；未重新打包作为分发资产。
- 两商店公开核验仍未发现 5.3.17，Open VSX 精确版本 API 返回 404。CI 的 credential not configured 是未发布；本机 VSCE 已保存发布者列表为空、当前环境无商店令牌。浏览器发布标签连接失败，原生浏览器入口因无法可靠识别网址由工具停止，未绕过该限制。
- 已准备原始 VSIX、发布交接和完整回执于本轮证据根；等待本人接入已有发布身份，之后仍须比较两商店实际公开包 SHA。GitHub 已发布不能当作三渠道完成。
