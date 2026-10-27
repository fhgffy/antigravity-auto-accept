# Antigravity Auto Accept 维护状态

当前代码版本 **v5.3.16**（2026-10-27）：撤销 5.3.15 对会话、工作区和站点范围 `Allow` 的收紧，恢复与 5.3.14 一致的自动批准。各渠道发布状态以 GitHub Release 和两个商店页面为准。

## 产品原则（2026-10-27，维护者确认；所有目标、issue 和 PR 都须遵守）

- 安装并启用本插件，即视为用户授权它代为批准 agent 的审批；插件的职责是让 agent 不因审批停下。
- agent 运行中出现的审批都应自动通过，包括会话、工作区和站点范围的 `Allow`；卡片同时提供“仅本次”选项时优先选它。
- 不得把已能自动批准的类型改为人工点击。任何收紧只能做成默认关闭的可选设置，并须事先征得维护者同意。
- 保留人工处理：计划/产物审阅的 `Proceed`、出错后的 `Retry`、agent 的提问、登录/OAuth/验证码/付款、企业策略与拒绝规则、工作区信任。
- 不抢焦点、不打断用户输入、动作前复核目标身份和单实例等保护照旧保留。

当前验收：无回收三扫描器小时长测、等待内存降低至少 40%、审批延迟与原生 M1–M5 达到对应门；严格 CPU 对照降低 55.38%。二十组完整双引擎及包验证已通过，内存机制仅有部分分层证据，历史停顿内部原因仍未证实。正式包保留 15 分钟回收；详见[最新验收与发布状态](docs/verification-2026-10-24-final-5.3.14.md)。

约束（针对测试与维护过程，不限制插件代用户点击的批准）：测试使用独立配置，不修改维护者日常 IDE 的安装、信任、审批设置或浏览器配置；保留动作前 live 身份、输入保护和单实例语义。文档和测试维护不另发运行版本。

验证：`npm test` → `npm run package` → `tests/validate-vsix.ps1`；本机桌面、CI 和商店公开原包分别给证据。

常驻：[项目路由](.agent/workflows/main-routing.md) · [原生桌面验收](.agent/skills/native-desktop-acceptance/SKILL.md) · [三渠道发布核对](.agent/skills/three-channel-publication/SKILL.md) · [有效经验索引](.agent/skills/self-improvement/references/lessons.md)。

历史：[资源阶段记录](docs/verification-2026-10-21-resource-stability.md) · [并发验收](docs/verification-2026-10-20-concurrency.md) · [启动恢复](docs/verification-2026-10-20-startup.md) · [发布配置](docs/publishing.md)。
