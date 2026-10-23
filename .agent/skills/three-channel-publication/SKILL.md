---
name: three-channel-publication
description: 发布本项目的一个用户可感知运行版本，核对 GitHub Release、Marketplace 和 Open VSX 的精确发布者、版本及原包 SHA；测试、CI、文档改动不单独发版。
---

# 三渠道发布核对

只有运行行为发生用户可感知变化才选择新版本；同一轮修复合成一个版本。既有发布授权不扩展为创建凭据、修改权限或代过验证码。

## 发布前

1. 核对 Git 状态、目标提交和完整 diff；保留首次失败，完成本地 `npm test`、VSIX 校验、独立审查及精确 head 的 PR CI。
2. 合并后核对 main 同次 CI 的两个引擎和包校验。不要把缺少商店凭据的绿色发布作业当作商店上线。
3. 使用该 main CI 的原始 VSIX。先核对包中版本、发布者与运行字节，再创建不可变 GitHub Release 原包和校验文件。
4. 同版本若已属于另一提交，不覆盖标签或资产，不上传新字节，也不为测试/文档制造空补丁。

```powershell
gh run view $runId --json headSha,event,status,conclusion,jobs
gh release view "v$version" --json tagName,isDraft,isPrerelease,assets
gh release download "v$version" --pattern '*.vsix' --dir $ownedReleaseDirectory
Get-FileHash -LiteralPath $originalVsix -Algorithm SHA256
```

变量必须来自本轮已核对的实际提交和原包，不能填写猜测的 run ID 或查询“最新构建”替代同次产物。

## 商店上传与本人步骤

- 仓库 Secrets 配置步骤见 `docs/publishing.md`；不创建新令牌，不在聊天、日志或仓库保存秘密值。
- 配置前复用已有网页会话，向两个商店选择同一个 GitHub 原包。会话头像仍在但 Forbidden 时，先正常刷新既有 OAuth 并回读实际登录态，不扩大权限。
- 2026-10-23：异步用户 API 未就绪时，Log In 可能只是占位；等待已知 User menu 或新鲜 AX 状态后核对会话，再决定是否需要恢复既有登录。不能因占位重复授权或上传。
- CAPTCHA 仅通知本人一次并保留页面；等待本人完成期间做其他独立工作，不反复操作验证码。完成后先读实际状态，不能重复上传正在审核的版本。
- Verifying、Under review、上传接收回执均不是公开成功。只在状态变化或合理审核间隔后检查公开包，不以高频重试制造“进度”。

## 公开包验证

CI 中的 `Test-MarketplacePublic` 和 `Test-OpenVsxPublic` 是当前生产核验入口。复用时只提取该函数 AST，不执行包含上传和凭据的步骤主体；版本和比较哈希设置为本轮原包。验证器必须实际下载并匹配 SHA，不能仅看元数据或 README 标题。

```powershell
$env:RELEASE_VERSION = $version
$releasePackageHash = (Get-FileHash -LiteralPath $originalVsix -Algorithm SHA256).Hash
# 2026-10-21：在本轮独占临时目录调用从当前 CI 提取的单一公开核验函数。
$available = Test-MarketplacePublic
if (-not $available) { throw 'Exact Marketplace version and public package not verified' }
$available = Test-OpenVsxPublic
if (-not $available) { throw 'Exact Open VSX version and public package not verified' }
```

调用前将 `$env:RUNNER_TEMP` 指向本轮独占目录；按当前 `.github/workflows/ci.yml` 中相应步骤缩进提取并解析函数，确认仅有目标 FunctionDefinitionAst 后才加载。网络失败保留原异常；公开已见版本时只等待/核验，不重新上传。清理下载失败也保持失败，不能被后续成功覆盖。

2026-10-23：提取函数绑定当前 CI 原字节哈希并保留旧定义；Git blob 的 LF 与 checkout 的 CRLF 分别记录原始哈希及正文等价。Marketplace 元数据使用公开只读 POST，两个商店的包下载使用 GET，均不携带发布凭据。

逐渠道保存发布者、扩展名、精确版本、原包 SHA、查询时间及临时下载清零结果。GitHub 下载、资产摘要和校验文件一致后，再比较两商店实际字节。三处都通过才更新最终报告和目标状态。

## 完成边界

- 验证报告保留首次 Forbidden、审核中、未公开和校验失败，不用成功文件覆盖它们。
- README/CODEX 只保留用户说明与当前维护摘要；run ID、资产 ID、实际哈希和完整回执放在 `docs/verification-*` 或测试根目录。
- 2026-10-23：同版本后续纯文档提交由跨提交标签门跳过发布；绿色跳过不重新证明既有发行或商店可用，继续引用原发行回执。
- 新版本正常路径未重跑原生验收时，必须说明等价复用依据，不能把源码相同改写成新版本的重新长测。
- `update_goal` 的成功完成回执与后续“当前目标”查询分开判断；查询无当前目标不能倒推出完成失败。
