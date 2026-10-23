# Antigravity Auto Accept 维护状态

当前发行版：**v5.3.13**，GitHub、Marketplace 和 Open VSX 的公开原包已核验一致；详见[资源与交付记录](docs/verification-2026-10-21-resource-stability.md)。

当前状态：CPU 与审批延迟通过；等待者内存、首小时增长未达目标，保留 15 分钟回收。CI 偶发超时根因仍未验证，正验证仅托管自测子环境的缓解候选，完整连绿仍待；本轮原生长测按已核对的运行等价范围复用。

约束：保留最终 live 身份、一次允许、输入保护和单实例语义；不修改用户 IDE 安装、信任、审批设置或浏览器配置。

验证：`npm test` → `npm run package` → `tests/validate-vsix.ps1`；两个 PowerShell 引擎、本机桌面、CI 与商店公开包分别给证据。

常驻：按[项目路由](.agent/workflows/main-routing.md)加载编码、注释、代码边界及对应任务技能。

任务技能：[原生桌面验收](.agent/skills/native-desktop-acceptance/SKILL.md) · [三渠道发布核对](.agent/skills/three-channel-publication/SKILL.md) · [有效经验索引](.agent/skills/self-improvement/references/lessons.md)。

详细证据：[本轮资源与发布](docs/verification-2026-10-21-resource-stability.md) · [并发验收](docs/verification-2026-10-20-concurrency.md) · [启动恢复](docs/verification-2026-10-20-startup.md) · [发布配置](docs/publishing.md)。

历史：[旧经验流水](docs/verification-2026-10-21-lessons-archive.md) · [旧维护状态与更新日志](docs/verification-2026-10-21-maintenance-archive.md)。
