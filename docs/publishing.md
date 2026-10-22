# 发布流程（2026-10-07）

发布与测试分别记录。GitHub Release 完成不代表扩展商店已公开上架；商店上传被接受也不代表审核完成。

## 自动入口与发布输入

Windows validation 通过同提交的 windows-validation.yml 复用 Windows PowerShell 5.1 和 PowerShell 7 两个完整测试作业。两个测试通过后，其 package 作业生成 VSIX、执行 validate-vsix，并上传包含 VSIX 与 SHA-256 文件的同次构建产物；外层发布等待整个 validation 成功。默认空 artifact 后缀保留既有原包名称。

publish 作业只接受本仓库 main 的 push，依赖 validation（两引擎及 package）成功。PR、fork、开发分支和手动 workflow_dispatch 不进入发布。主分支不会因后续 push 取消已经开始的工作流；同一并发组保留一条运行中工作流和最多一条等待中工作流，后续 push 可以替换尚未开始的等待项，不能保证每个中间提交都执行。

发布下载名称带完整 github.sha 的当前 run 产物。重新编译同一 SHA 仅用于检查归档运行字节，不重新打包。校验失败不会创建标签、上传 Release 或访问商店。

## 完整稳定性验收（2026-10-22）

现有 Windows validation 的 complete_stability 选项仅手动触发，默认 false；普通 push/PR 不运行完整矩阵。二十组分别调用同一个只读验证流程，每组两个独立引擎成功后才独立打包；每张 runner 都重新检出同提交并按原步骤执行。原十五秒 SelfTest、五秒转储、步骤和作业期限均保留。矩阵不进入发布、不接收商店 Secrets；失败不会触发其他组取消，也不会自动重跑。每组加唯一 artifact 后缀避免同一运行的上传冲突。

应逐组核对两个 Test 和 Verified VSIX 三个实际作业均成功，并保存同一 head、原日志及任何失败。二十次 SelfTest 或其他单边界重复不等于二十组完整 CI；新增矩阵也不证明既有停顿根因已修复。

## GitHub Release 与重跑

稳定版本使用包内版本生成 vX.Y.Z 标签，标签指向通过测试的精确 SHA。Release 保存原 VSIX、SHA-256 文件、CI 地址与提交。

- 同版本标签指向其他 SHA：跳过本轮发布，不能覆盖已发布版本。
- 同 SHA 已有 Release：下载并校验既有原资产，商店使用原资产；不能用新 ZIP 时间元数据的包替换它。
- 仅缺校验文件：从原 VSIX 生成并补上传校验文件。
- 仅缺 VSIX：当前 CI 包必须符合既有校验文件，否则失败。
- 上传过程中失败：已经成功的资产保留；重跑只补缺失资产，不使用覆盖参数。
- Release存在但标签缺失，或标签不能解析为精确CI提交：拒绝自动恢复，不重建标签来接纳旧Release。
- 创建中断留下Draft或prerelease：需要维护者人工核对并恢复；工作流拒绝将它直接作为稳定公开版本。

测试产物保留14天。重试同一发布应重跑原精确提交的工作流，不能在较新的未提升版本提交上覆盖旧标签。

## 双商店凭据与结果

仓库或受控环境可配置 VSCE_PAT 与 OVSX_PAT。工作流不创建PAT、不复制网页登录状态、不自动注册OIDC。凭据只传给对应商店步骤，不放入命令行或公开查询的认证头。

### 维护者一次性配置（2026-10-21）

本仓库当前读取仓库级 Secrets，已有发布者和 namespace 都是 `fhgffy`，无需重新注册账号、namespace 或接受发布协议。网页登录只供手工上传，不能替代 CI 凭据。

1. 由发布者本人准备对应商店的有效发布凭据。Marketplace 当前的 PAT 路径要求 Azure DevOps 中选择 `All accessible organizations` 和 `Marketplace (Manage)`，账号必须能管理已有发布者；仅有其他 Azure 组织权限的令牌不足以发布。Open VSX 使用本人账号的 Access Tokens，先确认账号有 `fhgffy` namespace 发布权。不要把值发到聊天、issue、命令参数或仓库文件。
2. 打开[本仓库 Actions Secrets](https://github.com/fhgffy/antigravity-auto-accept/settings/secrets/actions)，依次选择 **New repository secret**，分别保存为 `VSCE_PAT` 和 `OVSX_PAT`。值只在 GitHub 的 Secret 输入框中填写；已存在时使用 Update。当前工作流没有关联 GitHub Environment，因此仅配置环境级 Secrets 不会使该作业获得值。[GitHub 官方步骤](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
3. 保持现有 CI 权限和分支规则。后续一个正常运行补丁合并到 main 且测试、打包通过后，publish 作业会使用 GitHub Release 的原包依次核对和发布两个商店。手动 workflow_dispatch 用于测试，不会触发发布。没有用户可感知的运行变更时，不为验证凭据创建空版本。
4. 在该 main 运行的 summary 中检查两个商店的公开核验结果；`credential not configured`、`uploaded-pending` 和审核中均不是公开成功。若发布阶段失败，保留原运行和原资产，修正本人凭据后重跑同一提交的失败作业；先查精确公开版本，不能重新打包覆盖。

以上 PAT 方式只是当前工作流的过渡接入。微软已公告全局 Azure DevOps PAT 将于 **2026-12-01** 退役，长期发布需由维护者配置 Microsoft Entra ID 身份并另行验证工作流；不要把 Secrets 配置当作长期身份迁移完成。[Marketplace 官方身份与范围说明](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)

Open VSX 令牌的官方入口为头像 → Settings → Access Tokens，令牌值关闭后不再显示；由本人保存到相应 Secret 即可。本轮不代建或读取任何凭据，也不修改 namespace 的 Trusted Publishing 配置。[Open VSX 官方说明](https://github.com/eclipse-openvsx/openvsx/wiki/Publishing-Extensions)

Marketplace 使用固定版本 @vscode/vsce 4.0.0 的 publish --packagePath；Open VSX 使用 ovsx 1.2.0 的 publish 文件位置参数。两者直接发布已验证的现成 VSIX，不增加版本或重新打包。

缺少凭据时，summary 明确记录 not published / credential not configured；GitHub Release 可以完成，但双商店仍未发布。有凭据时两个商店独立尝试，任一实际失败最终使发布作业失败。

公开版本与公开包均通过验证才算商店发布成功（2026-10-20）。上传前先查询；上传后最多复查三次，元数据查询每次超时15秒，包下载每次超时30秒，两次间隔各20秒。查询期间不会再次上传：

- Marketplace 请求公开 extensionquery，flags=35，即 IncludeVersions=1、IncludeFiles=2 与 ExcludeNonValidated=32；核对publisher、扩展名、精确版本，排除Verifying版本，并取得唯一VSIXPackage文件。
- Open VSX 请求精确版本API，核对namespace、name、version、无error、downloadable与下载地址。
- 两者均只从对应商店的HTTPS下载地址读取公开VSIX，不传发布凭据；全包SHA-256必须与本次选定的原GitHub Release资产一致。下载的临时文件在成功、失败或不一致时均尝试清理。
- 清理失败会使本轮发布失败，记录cleanup-failed；已发现字节不符时优先保留package-mismatch，不能因清理异常被覆盖而重试成成功。
- 同版本公开包的字节不一致立即失败，记录package-mismatch，不重传或覆盖已有版本。
- 已看到精确公开版本，但下载暂时失败、地址缺失或不符合来源要求时，记录verification-pending并有限复查；不重复上传，也不报成功。
- uploaded-pending 表示上传已接受但公开可用尚未确认；作业失败，不能称为已上架。审核时间可能超过此有限等待，稍后重跑时先查询精确版本，已经公开则不重复上传。

CLI或公开查询的实际失败必须保留。GitHub CI的测试成功、Release成功、商店上传成功、商店公开可用是四种不同证据。

## 当前身份与后续维护

网页登录成功不等于CI拥有发布身份。Open VSX Trusted Publishing需要namespace owner注册明确工作流；未配置时不能默认OIDC可用。Marketplace官方说明全局Azure DevOps PAT于2026-12-01退役，长期自动发布身份需另行配置。

工具合同来源：[download-artifact v8.0.1](https://github.com/actions/download-artifact/blob/v8.0.1/action.yml)、[vsce 4.0.0](https://github.com/microsoft/vscode-vsce/blob/v4.0.0/src/publish.ts)、[Open VSX发布](https://github.com/eclipse-openvsx/openvsx/wiki/Publishing-Extensions)、[Marketplace身份](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)、[Open VSX Trusted Publishing](https://github.com/eclipse-openvsx/openvsx/wiki/Trusted-Publishing)、[Marketplace查询标志](https://github.com/microsoft/azure-devops-node-api/blob/master/api/interfaces/GalleryInterfaces.ts)。

## 离线回归

运行 node --test tests/publish-release.test.cjs。测试从CI读取实际发布脚本，替换GitHub、商店与等待边界；真实归档仍由validate-vsix校验。覆盖原资产保留、部分上传恢复、校验失败、旧标签保护、缺凭据、公开版本与完整包字节检查、下载失败重试、临时文件清理及避免重复上传；不联网、不操作桌面、不使用真实凭据。
