# Antigravity Auto Accept 维护状态

当前发行版：**v5.3.12**，Windows 本地 UIAutomation 扫描器；原包发布事实见[发布与自测记录](docs/verification-2026-10-21-selftest-desktop.md)。

当前目标：先测真实资源与审批延迟，再优化发现热路径和等待者初始化；完成连续 CI、真实长测后合成一个运行版本。未完成的性能指标不写成已通过。

约束：保留最终 live 身份、一次允许、输入保护和单实例语义；不修改用户 IDE 安装、信任、审批设置或浏览器配置。

验证：`npm test` → `npm run package` → `tests/validate-vsix.ps1`；两个 PowerShell 引擎、本机桌面、CI 与商店公开包分别给证据。

常驻：按[项目路由](.agent/workflows/main-routing.md)加载编码、注释、代码边界及对应任务技能。

任务技能：[原生桌面验收](.agent/skills/native-desktop-acceptance/SKILL.md) · [三渠道发布核对](.agent/skills/three-channel-publication/SKILL.md) · [有效经验索引](.agent/skills/self-improvement/references/lessons.md)。

详细证据：[并发验收](docs/verification-2026-10-20-concurrency.md) · [启动恢复](docs/verification-2026-10-20-startup.md) · [发布配置](docs/publishing.md)。

历史：[旧经验流水](docs/verification-2026-10-21-lessons-archive.md) · [旧维护状态与更新日志](docs/verification-2026-10-21-maintenance-archive.md)。
