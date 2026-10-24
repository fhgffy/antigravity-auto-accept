# Antigravity Auto Accept 维护状态

当前运行版 **v5.3.14 已在 GitHub 发布**；最近完成三渠道公开原包核验的版本仍是 **v5.3.13**。Marketplace 的本人验证码与 Open VSX 服务端登录故障尚未完成，因此不称三渠道已上线。

当前验收：无回收三扫描器小时长测、等待内存降低至少 40%、审批延迟与原生 M1–M5 达到对应门；严格 CPU 对照降低 55.38%。二十组完整双引擎及包验证已通过，内存机制仅有部分分层证据，历史停顿内部原因仍未证实。正式包保留 15 分钟回收；详见[最新验收与发布状态](docs/verification-2026-10-24-final-5.3.14.md)。

约束：保留动作前 live 身份、一次允许、输入保护和单实例语义；不修改用户 IDE 安装、信任、审批设置或浏览器配置。文档和测试维护不另发运行版本。

验证：`npm test` → `npm run package` → `tests/validate-vsix.ps1`；本机桌面、CI 和商店公开原包分别给证据。

常驻：[项目路由](.agent/workflows/main-routing.md) · [原生桌面验收](.agent/skills/native-desktop-acceptance/SKILL.md) · [三渠道发布核对](.agent/skills/three-channel-publication/SKILL.md) · [有效经验索引](.agent/skills/self-improvement/references/lessons.md)。

历史：[资源阶段记录](docs/verification-2026-10-21-resource-stability.md) · [并发验收](docs/verification-2026-10-20-concurrency.md) · [启动恢复](docs/verification-2026-10-20-startup.md) · [发布配置](docs/publishing.md)。
