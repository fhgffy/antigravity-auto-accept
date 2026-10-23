# Antigravity Auto Accept 维护状态

待发布：**v5.3.14**，整合无用读取优化与 Windows x64 的系统 x86 PowerShell 宿主选择。最近完成三渠道公开原包核验的发行版仍为 **v5.3.13**；详见[资源与交付记录](docs/verification-2026-10-21-resource-stability.md)。

当前验证：最终运行候选完成超过 60 分钟的三扫描器长测，低于既定历史资源参考阈值；完整本机测试、二十组双引擎及包验证通过，多窗口和后台审批按已覆盖场景留证。旧失败、最小化目标异常及未触发的文件审批继续记录；不把不同负载的历史比较当成严格 A/B。正式包保留 15 分钟回收，历史超时内部根因仍未证实。5.3.14 最终本机全链与包校验通过；发布提交的云端复验和三渠道核验继续收尾。

约束：保留最终 live 身份、一次允许、输入保护和单实例语义；不修改用户 IDE 安装、信任、审批设置或浏览器配置。

验证：`npm test` → `npm run package` → `tests/validate-vsix.ps1`；两个 PowerShell 引擎、本机桌面、CI 与商店公开包分别给证据。

常驻：按[项目路由](.agent/workflows/main-routing.md)加载编码、注释、代码边界及对应任务技能。

任务技能：[原生桌面验收](.agent/skills/native-desktop-acceptance/SKILL.md) · [三渠道发布核对](.agent/skills/three-channel-publication/SKILL.md) · [有效经验索引](.agent/skills/self-improvement/references/lessons.md)。

详细证据：[本轮资源与发布](docs/verification-2026-10-21-resource-stability.md) · [并发验收](docs/verification-2026-10-20-concurrency.md) · [启动恢复](docs/verification-2026-10-20-startup.md) · [发布配置](docs/publishing.md)。

历史：[旧经验流水](docs/verification-2026-10-21-lessons-archive.md) · [旧维护状态与更新日志](docs/verification-2026-10-21-maintenance-archive.md)。
