# 发布流程（2026-10-07）

发布与测试分别记录。GitHub Release 完成不代表扩展商店已公开上架；商店上传被接受也不代表审核完成。

## 自动入口与发布输入

现有 Windows validation 工作流保留 Windows PowerShell 5.1 和 PowerShell 7 两个测试作业。两个测试通过后，package 作业生成 VSIX，执行 validate-vsix，并上传包含 VSIX 与 SHA-256 文件的同次构建产物。

publish 作业只接受本仓库 main 的 push，依赖 package 成功。PR、fork、开发分支和手动 workflow_dispatch 不进入发布。主分支不会因后续 push 取消已经开始的工作流；同一并发组保留一条运行中工作流和最多一条等待中工作流，后续 push 可以替换尚未开始的等待项，不能保证每个中间提交都执行。

发布下载名称带完整 github.sha 的当前 run 产物。重新编译同一 SHA 仅用于检查归档运行字节，不重新打包。校验失败不会创建标签、上传 Release 或访问商店。

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

Marketplace 使用固定版本 @vscode/vsce 4.0.0 的 publish --packagePath；Open VSX 使用 ovsx 1.2.0 的 publish 文件位置参数。两者直接发布已验证的现成 VSIX，不增加版本或重新打包。

缺少凭据时，summary 明确记录 not published / credential not configured；GitHub Release 可以完成，但双商店仍未发布。有凭据时两个商店独立尝试，任一实际失败最终使发布作业失败。

上传后最多进行三次公开版本查询，每次超时15秒，两次间隔各20秒。查询期间不会再次上传：

- Marketplace 请求公开 extensionquery，flags=33，即 IncludeVersions=1 与 ExcludeNonValidated=32；核对publisher、扩展名、精确版本，排除Verifying版本。
- Open VSX 请求精确版本API，核对namespace、name、version、无error、downloadable与下载地址。
- uploaded-pending 表示上传已接受但公开可用尚未确认；作业失败，不能称为已上架。审核时间可能超过此有限等待，稍后重跑时先查询精确版本，已经公开则不重复上传。

CLI或公开查询的实际失败必须保留。GitHub CI的测试成功、Release成功、商店上传成功、商店公开可用是四种不同证据。

## 当前身份与后续维护

网页登录成功不等于CI拥有发布身份。Open VSX Trusted Publishing需要namespace owner注册明确工作流；未配置时不能默认OIDC可用。Marketplace官方说明全局Azure DevOps PAT于2026-12-01退役，长期自动发布身份需另行配置。

工具合同来源：[download-artifact v8.0.1](https://github.com/actions/download-artifact/blob/v8.0.1/action.yml)、[vsce 4.0.0](https://github.com/microsoft/vscode-vsce/blob/v4.0.0/src/publish.ts)、[Open VSX发布](https://github.com/eclipse-openvsx/openvsx/wiki/Publishing-Extensions)、[Marketplace身份](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)、[Open VSX Trusted Publishing](https://github.com/eclipse-openvsx/openvsx/wiki/Trusted-Publishing)、[Marketplace查询标志](https://github.com/microsoft/azure-devops-node-api/blob/master/api/interfaces/GalleryInterfaces.ts)。

## 离线回归

运行 node --test tests/publish-release.test.cjs。测试从CI读取实际发布脚本，替换GitHub、商店与等待边界；真实归档仍由validate-vsix校验。覆盖原资产保留、部分上传恢复、校验失败、旧标签保护、缺凭据和公开版本检查；不联网、不操作桌面、不使用真实凭据。
