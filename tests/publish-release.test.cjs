// 2026-10-07：执行 CI 原发布步骤，仅替 GitHub、商店和等待边界，不联网、不使用真实凭据。
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const workflow = fs.readFileSync(path.join(root, '.github/workflows/ci.yml'), 'utf8');

function stepScript(id) {
  const lines = workflow.replace(/\r\n/g, '\n').split('\n');
  const start = lines.findIndex((line) => line === '        id: ' + id);
  assert.ok(start >= 0, 'Missing production step: ' + id);
  const run = lines.findIndex((line, index) => index > start && line === '        run: |');
  assert.ok(run >= 0);
  const body = [];
  for (let index = run + 1; index < lines.length && lines[index].startsWith('          '); index++) {
    body.push(lines[index].slice(10));
  }
  assert.ok(body.length > 0);
  return body.join('\n');
}

// 2026-10-07：假归档仍由真实 validate-vsix 校验，ZIP 时间元数据不同可复现同 SHA 重打包风险。
const prelude = [
  "$ErrorActionPreference = 'Stop'",
  "$global:LASTEXITCODE = 0",
  "$script:Calls = [Collections.Generic.List[object]]::new()",
  "$script:Queries = 0; $script:Sleeps = 0; $script:Uploads = 0",
  // 2026-10-20：公开安装包边界只回放文件，不联网；保留下载路径以检查所有失败分支都清理了临时文件。
  "$script:Downloads = 0; $script:DownloadPaths = [Collections.Generic.List[string]]::new(); $script:MarketplaceFlags = $null",
  "$script:TagSha = if ($env:TEST_MODE -in @('new', 'release-without-tag')) { $null } elseif ($env:TEST_MODE -eq 'old-tag') { 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' } else { $env:GITHUB_SHA }",
  "$script:HasRelease = $env:TEST_MODE -ne 'new'",
  "$script:HasPackage = $env:TEST_MODE -notin @('new', 'missing-both', 'checksum-only')",
  "$script:HasChecksum = $env:TEST_MODE -notin @('new', 'missing-both', 'package-only')",
  "Add-Type -AssemblyName System.IO.Compression.FileSystem",
  "function New-TestVsix([string]$Destination, [int]$Year, [bool]$BadRuntime = $false) {",
  "  $zip = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)",
  "  try {",
  "    $entries = @{ 'extension.vsixmanifest' = '<PackageManifest><Metadata><Identity Version=\"1.2.3\" Id=\"antigravity-auto-accept\" Publisher=\"fhgffy\"/></Metadata></PackageManifest>'; '[Content_Types].xml' = '<Types/>'; 'extension/package.json' = [IO.File]::ReadAllText('package.json'); 'extension/src/autoClicker.ps1' = [IO.File]::ReadAllText('src/autoClicker.ps1'); 'extension/out/extension.js' = [IO.File]::ReadAllText('out/extension.js'); 'extension/icon.png' = 'icon'; 'extension/LICENSE.txt' = 'license'; 'extension/readme.md' = 'fixture readme' }",
  "    if ($BadRuntime) { $entries['extension/out/extension.js'] = 'wrong runtime' }",
  "    foreach ($name in $entries.Keys) {",
  "      $entry = $zip.CreateEntry($name); $entry.LastWriteTime = [DateTimeOffset]::new($Year,1,1,0,0,0,[TimeSpan]::Zero)",
  "      $stream = $entry.Open(); $bytes = [Text.UTF8Encoding]::new($false).GetBytes($entries[$name])",
  "      try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }",
  "    }",
  "  } finally { $zip.Dispose() }",
  "}",
  "function Write-TestChecksum([string]$Package) {",
  "  $hash = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()",
  "  [IO.File]::WriteAllText(\"$Package.sha256\", \"$hash  $([IO.Path]::GetFileName($Package))\", [Text.UTF8Encoding]::new($false))",
  "}",
  "$script:FileName = 'antigravity-auto-accept-1.2.3.vsix'",
  "$script:InputPath = Join-Path $env:INPUT_DIRECTORY $script:FileName",
  "$script:OriginalPath = Join-Path $env:ORIGINAL_DIRECTORY $script:FileName",
  "New-TestVsix $script:InputPath 2026; Write-TestChecksum $script:InputPath",
  "New-TestVsix $script:OriginalPath 2025 ($env:TEST_MODE -eq 'bad-original-runtime'); Write-TestChecksum $script:OriginalPath",
  "if ($env:TEST_MODE -eq 'bad-input-checksum') { [IO.File]::WriteAllText(\"$script:InputPath.sha256\", ('0' * 64) + '  ' + $script:FileName) }",
  "if ($env:TEST_MODE -eq 'bad-original-checksum') { [IO.File]::WriteAllText(\"$script:OriginalPath.sha256\", ('0' * 64) + '  ' + $script:FileName) }",
  "if ($env:TEST_MODE -eq 'extra-artifact') { [IO.File]::WriteAllText((Join-Path $env:INPUT_DIRECTORY 'extra'), 'unexpected') }",
  "function Get-TestRelease {",
  "  $assets = @(); if ($script:HasPackage) { $assets += @{ name = $script:FileName } }; if ($script:HasChecksum) { $assets += @{ name = \"$script:FileName.sha256\" } }",
  "  return @{ tag_name = 'v1.2.3'; html_url = 'https://github.com/fixture/release/v1.2.3'; draft = ($env:TEST_MODE -eq 'draft'); prerelease = $false; assets = $assets }",
  "}",
  "function gh {",
  "  $arguments = @($args); $global:LASTEXITCODE = 0",
  "  $script:Calls.Add(($arguments -join '|'))",
  "  if ($env:TEST_MODE -eq 'query-failed') { $global:LASTEXITCODE = 1; return }",
  "  if ($arguments[0] -eq 'api') {",
  "    if ($arguments -contains '--method') {",
  "      if (-not ($arguments -contains \"sha=$env:GITHUB_SHA\") -or -not ($arguments -contains 'ref=refs/tags/v1.2.3')) { throw 'Wrong tag creation arguments' }",
  "      $script:TagSha = $env:GITHUB_SHA",
  "      return @{ ref = 'refs/tags/v1.2.3'; object = @{ type = 'commit'; sha = $script:TagSha } } | ConvertTo-Json -Depth 10 -Compress",
  "    }",
  "    if ($arguments[1] -like '*/git/matching-refs/tags/*') {",
  "      if ($null -eq $script:TagSha) { return '[]' }",
  "      return ConvertTo-Json -InputObject @(@{ ref = 'refs/tags/v1.2.3'; object = @{ type = 'commit'; sha = $script:TagSha } }) -Depth 10 -Compress",
  "    }",
  "    if ($arguments[1] -like '*/releases*') { if ($script:HasRelease) { return (Get-TestRelease | ConvertTo-Json -Depth 10 -Compress) }; return }",
  "    throw 'Unexpected GitHub API request'",
  "  }",
  "  if ($arguments[0] -ne 'release') { throw 'Unexpected GitHub operation' }",
  "  if ($arguments[1] -eq 'create') {",
  "    if ($script:TagSha -ne $env:GITHUB_SHA -or -not ($arguments -contains '--verify-tag')) { throw 'Release not bound to exact tag' }",
  "    $script:HasRelease = $true; $script:HasPackage = $true; $script:HasChecksum = $true",
  "    Copy-Item -LiteralPath $script:InputPath -Destination $script:OriginalPath -Force",
  "    Copy-Item -LiteralPath \"$script:InputPath.sha256\" -Destination \"$script:OriginalPath.sha256\" -Force",
  "    return 'created'",
  "  }",
  "  if ($arguments[1] -eq 'download') {",
  "    $name = $arguments[[Array]::IndexOf($arguments, '--pattern') + 1]; $directory = $arguments[[Array]::IndexOf($arguments, '--dir') + 1]",
  "    Copy-Item -LiteralPath (Join-Path $env:ORIGINAL_DIRECTORY $name) -Destination (Join-Path $directory $name)",
  "    return",
  "  }",
  "  if ($arguments[1] -eq 'upload') {",
  "    if ($arguments -contains '--clobber') { throw 'Published asset replacement forbidden' }",
  "    $name = [IO.Path]::GetFileName($arguments[3])",
  "    if ($name.EndsWith('.vsix')) { $script:HasPackage = $true } else { $script:HasChecksum = $true }",
  "    return 'uploaded'",
  "  }",
  "  throw 'Unexpected GitHub release operation'",
  "}",
  "function npx {",
  "  $script:Calls.Add((@($args) -join '|')); $script:Uploads++",
  "  if (-not (@($args) -contains $env:VSIX_PATH)) { throw 'Store did not use selected VSIX' }",
  "  $global:LASTEXITCODE = if ($env:TEST_MODE -eq 'upload-error') { 1 } else { 0 }",
  "}",
  "function Start-Sleep { param([int]$Seconds) if ($Seconds -ne 20) { throw 'Wrong retry delay' }; $script:Sleeps++ }",
  "function Invoke-RestMethod {",
  "  param([string]$Uri, [string]$Method, [string]$ContentType, [hashtable]$Headers, [string]$Body, [int]$TimeoutSec)",
  "  $script:Queries++; if ($TimeoutSec -ne 15 -or ($Headers -and $Headers.ContainsKey('Authorization'))) { throw 'Unsafe public probe' }",
  "  $visible = $env:TEST_MODE -in @('already-public','wrong-public-package','public-download-failed','public-download-transient','missing-package-url','insecure-package-url','wrong-package-origin','wrong-identity','not-downloadable','downloadable-transient','cleanup-failed','mismatch-cleanup-failed','transport-cleanup-failed') -or ($env:TEST_MODE -in @('eventually-public','eventually-wrong-package','eventually-cleanup-failed','eventually-mismatch-cleanup-failed','eventually-transport-cleanup-failed') -and $script:Queries -ge 3)",
  "  if ($Uri -like 'https://marketplace.visualstudio.com/*') {",
  "    $request = $Body | ConvertFrom-Json; $script:MarketplaceFlags = $request.flags; if ($request.flags -notin @(33,35) -or $request.filters[0].criteria[0].filterType -ne 7) { throw 'Marketplace must exclude nonvalidated versions' }",
  "    $version = if ($visible) { '1.2.3' } else { '9.9.9' }",
  "    $publisher = if ($env:TEST_MODE -eq 'wrong-identity') { 'other' } else { 'fhgffy' }",
  "    $source = if ($env:TEST_MODE -eq 'insecure-package-url') { 'http://fhgffy.gallerycdn.vsassets.io/fixture.vsix' } elseif ($env:TEST_MODE -eq 'wrong-package-origin') { 'https://example.invalid/fixture.vsix' } else { 'https://fhgffy.gallerycdn.vsassets.io/fixture.vsix' }",
  "    $files = if ($env:TEST_MODE -eq 'missing-package-url') { @() } else { @(@{ assetType = 'Microsoft.VisualStudio.Services.VSIXPackage'; source = $source }) }",
  "    return @{ results = @(@{ extensions = @(@{ publisher = @{ publisherName = $publisher }; extensionName = 'antigravity-auto-accept'; versions = @(@{ version = $version; files = $files }, @{ version = '8.0.0' }) }) }) }",
  "  }",
  "  if ($Uri -cne 'https://open-vsx.org/api/fhgffy/antigravity-auto-accept/1.2.3') { throw 'Open VSX must query exact version' }",
  "  if (-not $visible) { return @{ error = 'not found'; namespace = 'fhgffy'; name = 'antigravity-auto-accept'; version = '1.2.3' } }",
  "  $download = if ($env:TEST_MODE -eq 'missing-package-url') { '' } elseif ($env:TEST_MODE -eq 'insecure-package-url') { 'http://open-vsx.org/fixture.vsix' } elseif ($env:TEST_MODE -eq 'wrong-package-origin') { 'https://example.invalid/fixture.vsix' } else { 'https://open-vsx.org/fixture.vsix' }",
  "  $namespace = if ($env:TEST_MODE -eq 'wrong-identity') { 'other' } else { 'fhgffy' }",
  "  return @{ namespace = $namespace; name = 'antigravity-auto-accept'; version = '1.2.3'; downloadable = ($env:TEST_MODE -ne 'not-downloadable' -and ($env:TEST_MODE -ne 'downloadable-transient' -or $script:Queries -gt 1)); files = @{ download = $download } }",
  "}",
  // 2026-10-20：同版本且运行字节相同、仅ZIP时间不同的包也必须拒绝，不能只验证版本或解压后的源码。
  "function Invoke-WebRequest {",
  "  param([string]$Uri, [string]$OutFile, [int]$TimeoutSec, [switch]$UseBasicParsing, [hashtable]$Headers)",
  "  $script:Downloads++; $script:DownloadPaths.Add($OutFile)",
  "  if ($TimeoutSec -ne 30 -or ($Headers -and $Headers.ContainsKey('Authorization'))) { throw 'Unsafe public package download' }",
  "  if ($Uri -notin @('https://fhgffy.gallerycdn.vsassets.io/fixture.vsix','https://open-vsx.org/fixture.vsix')) { throw 'Unexpected package URL' }",
  "  if ($env:TEST_MODE -eq 'public-download-failed' -or ($env:TEST_MODE -in @('public-download-transient','transport-cleanup-failed','eventually-transport-cleanup-failed') -and $script:Downloads -eq 1)) { [IO.File]::WriteAllText($OutFile,'partial'); throw 'Package transport failed' }",
  "  $source = if ($env:TEST_MODE -in @('wrong-public-package','eventually-wrong-package') -or ($env:TEST_MODE -in @('mismatch-cleanup-failed','eventually-mismatch-cleanup-failed') -and $script:Downloads -eq 1)) { $script:InputPath } else { $script:OriginalPath }",
  "  Copy-Item -LiteralPath $source -Destination $OutFile",
  "}",
  // 2026-10-20：仅首次删除失败，旧实现会用下次成功下载掩盖校验失败和残留文件。
  "function Remove-Item {",
  "  param([string]$LiteralPath, [switch]$Force)",
  "  if ($env:TEST_MODE -in @('cleanup-failed','mismatch-cleanup-failed','transport-cleanup-failed','eventually-cleanup-failed','eventually-mismatch-cleanup-failed','eventually-transport-cleanup-failed') -and $script:Downloads -eq 1) { throw [IO.IOException]::new('Simulated download cleanup failure') }",
  "  Microsoft.PowerShell.Management\\Remove-Item @PSBoundParameters",
  "}",
].join('\n');

function execute(id, mode, overrides = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'antigravity-release-ci-'));
  for (const child of ['tests', 'src', 'out', 'input', 'original']) {
    fs.mkdirSync(path.join(directory, child));
  }
  fs.writeFileSync(path.join(directory, 'package.json'), JSON.stringify({ name: 'antigravity-auto-accept', publisher: 'fhgffy', version: '1.2.3' }));
  fs.writeFileSync(path.join(directory, 'src/autoClicker.ps1'), '# inert fixture');
  fs.writeFileSync(path.join(directory, 'out/extension.js'), 'inert fixture');
  fs.writeFileSync(path.join(directory, 'icon.png'), 'icon');
  fs.writeFileSync(path.join(directory, 'LICENSE'), 'license');
  fs.copyFileSync(path.join(root, 'tests/validate-vsix.ps1'), path.join(directory, 'tests/validate-vsix.ps1'));
  const output = path.join(directory, 'output');
  const summary = path.join(directory, 'summary');
  fs.writeFileSync(output, '');
  fs.writeFileSync(summary, '');
  const body = prelude + '\n$failure = $null\ntry { & ([scriptblock]::Create(@\'\n' + stepScript(id) + '\n\'@)) } catch { $failure = $_.Exception.Message }\n' +
    '[ordered]@{ failure = $failure; calls = @($script:Calls); queries = $script:Queries; sleeps = $script:Sleeps; uploads = $script:Uploads; downloads = $script:Downloads; downloadLeftovers = @($script:DownloadPaths | Where-Object { Test-Path -LiteralPath $_ }).Count; marketplaceFlags = $script:MarketplaceFlags; output = [IO.File]::ReadAllText($env:GITHUB_OUTPUT); summary = [IO.File]::ReadAllText($env:GITHUB_STEP_SUMMARY); inputHash = (Get-FileHash $script:InputPath).Hash; originalHash = (Get-FileHash $script:OriginalPath).Hash; selectedHash = $(if (Test-Path (Join-Path $env:RUNNER_TEMP ("publish-release/" + $script:FileName))) { (Get-FileHash (Join-Path $env:RUNNER_TEMP ("publish-release/" + $script:FileName))).Hash } else { $null }) } | ConvertTo-Json -Depth 10 -Compress';
  // 2026-10-07：长 CI 脚本落临时文件，避免 Windows 进程命令行长度上限。
  const scriptPath = path.join(directory, 'fixture.ps1');
  fs.writeFileSync(scriptPath, body.replace(/\r?\n/g, '\r\n'), 'utf8');
  const result = spawnSync('pwsh.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', scriptPath], {
    cwd: directory,
    encoding: 'utf8',
    timeout: 20000,
    env: {
      ...process.env, GH_TOKEN: '', VSCE_PAT: '', OVSX_PAT: '',
      GITHUB_SHA: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      GITHUB_REPOSITORY: 'fhgffy/antigravity-auto-accept', GITHUB_SERVER_URL: 'https://github.com', GITHUB_RUN_ID: '123',
      GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary, RUNNER_TEMP: directory, INPUT_DIRECTORY: path.join(directory, 'input'),
      ORIGINAL_DIRECTORY: path.join(directory, 'original'), TEST_MODE: mode, VSIX_PATH: path.join(directory, 'original/antigravity-auto-accept-1.2.3.vsix'), RELEASE_VERSION: '1.2.3',
      ...overrides,
    },
  });
  try {
    assert.equal(result.status, 0, result.stderr || result.error?.message || result.stdout);
    const line = result.stdout.trim().split(/\r?\n/).at(-1);
    return JSON.parse(line);
  } finally {
    // 2026-10-07：只删除本测试创建且仍位于系统临时目录下的夹具。
    const resolved = fs.realpathSync(directory);
    assert.equal(path.dirname(resolved).toLowerCase(), fs.realpathSync(os.tmpdir()).toLowerCase());
    assert.ok(path.basename(resolved).startsWith('antigravity-release-ci-'));
    fs.rmSync(resolved, { recursive: true, force: true });
  }
}

test('publish entry excludes PR/fork and consumes only the same run artifact', () => {
  const job = workflow.slice(workflow.indexOf('\n  publish:'));
  assert.match(job, /needs: validation/); // 2026-10-22：发布等待共享的两引擎与打包验证整体成功。
  assert.match(job, /github\.repository == 'fhgffy\/antigravity-auto-accept'/);
  assert.match(job, /github\.event_name == 'push'/);
  assert.match(job, /github\.ref == 'refs\/heads\/main'/);
  assert.match(job, /actions\/download-artifact@v8\.0\.1/);
  assert.match(job, /name: antigravity-auto-accept-\$\{\{ github\.sha \}\}/);
  assert.doesNotMatch(job, /workflow_run|--clobber/);
  assert.match(workflow, /cancel-in-progress: \$\{\{ github\.ref != 'refs\/heads\/main' \}\}/);
});

// 2026-10-22：完整验收复用生产门，验证两引擎先于打包、默认产物契约及二十份产物隔离，防止诊断样本冒充完整CI。
test('complete stability samples reuse the same read-only two-engine and package workflow', () => {
  const core = fs.readFileSync(path.join(root, '.github/workflows/windows-validation.yml'), 'utf8');
  const stability = workflow.slice(workflow.indexOf('\n  stability:'), workflow.indexOf('\n  # 2026-10-07：只发布'));
  const validation = workflow.slice(workflow.indexOf('\n  validation:'), workflow.indexOf('\n  stability:'));
  assert.match(validation, /uses: \.\/\.github\/workflows\/windows-validation\.yml/);
  assert.match(core, /workflow_call:/);
  assert.match(core, /artifact_suffix:[\s\S]*?type: string[\s\S]*?default: ''/);
  assert.match(core, /permissions:\r?\n  contents: read/);
  assert.doesNotMatch(core, /^  (?:publish|concurrency):|secrets:|contents: write|workflow_dispatch:|pull_request:/m);
  const engine = core.slice(core.indexOf('\n  test:'), core.indexOf('\n  package:'));
  assert.match(engine, /label: Windows PowerShell 5\.1/);
  assert.match(engine, /label: PowerShell 7/);
  assert.match(engine, /fail-fast: false/);
  for (const step of ['Scanner regression on one engine', 'Host wrapper timeout diagnostics and failure boundaries', 'Host process identity across architectures', 'Mouse input interference without desktop clicks', 'Concurrent scanner handoff without desktop clicks']) assert.ok(engine.includes('name: ' + step), step);
  const pack = core.slice(core.indexOf('\n  package:'));
  assert.match(pack, /needs: test/);
  assert.match(pack, /name: antigravity-auto-accept-\$\{\{ github\.sha \}\}\$\{\{ inputs\.artifact_suffix \}\}/);
  assert.match(pack, /\.\/tests\/validate-vsix\.ps1 -VsixPath \$vsix/);
  assert.match(workflow, /complete_stability:[\s\S]*?type: boolean[\s\S]*?default: false/);
  assert.match(stability, /if: github\.event_name == 'workflow_dispatch' && inputs\.complete_stability/);
  assert.match(workflow, /permissions:\r?\n  contents: read/);
  assert.match(stability, /fail-fast: false/);
  assert.match(stability, /uses: \.\/\.github\/workflows\/windows-validation\.yml/);
  assert.match(stability, /artifact_suffix: -stability-\$\{\{ matrix\.iteration \}\}/);
  const samples = stability.match(/iteration: (\[[0-9, ]+\])/);
  assert.ok(samples);
  assert.deepEqual(JSON.parse(samples[1]), Array.from({ length: 20 }, (_, index) => index + 1));
  assert.doesNotMatch(stability, /secrets:|contents: write|workflow_run:|pull_request:|\n  push:/);
});

for (const mode of ['new', 'same-sha', 'missing-both', 'package-only']) {
  test('release preserves exact SHA and existing package: ' + mode, () => {
    const result = execute('release', mode);
    assert.equal(result.failure, null);
    assert.match(result.output, /proceed=true/);
    assert.equal(result.selectedHash, mode === 'missing-both' ? result.inputHash : result.originalHash);
    if (mode === 'same-sha' || mode === 'package-only') assert.notEqual(result.selectedHash, result.inputHash);
    if (mode === 'same-sha') assert.ok(result.calls.every((call) => !call.startsWith('release|upload') && !call.startsWith('release|create')));
    if (mode === 'package-only') assert.equal(result.calls.filter((call) => call.startsWith('release|upload')).length, 1);
    if (mode === 'missing-both') assert.equal(result.calls.filter((call) => call.startsWith('release|upload')).length, 2);
    if (mode === 'new') assert.ok(result.calls.some((call) => call.includes('sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')));
  });
}
test('old released version is skipped without tag or asset mutations', () => {
  const result = execute('release', 'old-tag');
  assert.equal(result.failure, null);
  assert.match(result.output, /proceed=false/);
  assert.equal(result.calls.length, 1);
});
for (const mode of ['bad-input-checksum', 'bad-original-checksum', 'bad-original-runtime', 'checksum-only', 'extra-artifact', 'query-failed', 'draft', 'release-without-tag']) {
  test('release rejects invalid input/state without replacement: ' + mode, () => {
    const result = execute('release', mode);
    assert.ok(result.failure);
    assert.doesNotMatch(result.output, /proceed=true/);
    assert.ok(result.calls.every((call) => !call.startsWith('release|upload') && !call.startsWith('release|create')));
  });
}
for (const store of ['marketplace', 'openvsx']) {
  /* 2026-10-20：预检和上传后复查都不得忽略清理失败，校验与传输原异常也不能被覆盖。 */
  for (const mode of ['cleanup-failed', 'mismatch-cleanup-failed', 'transport-cleanup-failed', 'eventually-cleanup-failed', 'eventually-mismatch-cleanup-failed', 'eventually-transport-cleanup-failed']) {
    test(store + ' cleanup failure cannot hide package failure: ' + mode, () => {
      const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
      const result = execute(store, mode, credential);
      assert.ok(result.failure);
      assert.equal(result.uploads, mode.startsWith('eventually-') ? 1 : 0);
      assert.equal(result.downloads, 1);
      assert.equal(result.queries, mode.startsWith('eventually-') ? 3 : 1);
      assert.equal(result.downloadLeftovers, 1);
      assert.match(result.output, mode.includes('mismatch-') ? /status=package-mismatch/ : /status=cleanup-failed/);
      if (mode.includes('mismatch-')) assert.match(result.failure, /public package checksum mismatch/);
      if (mode.includes('transport-')) assert.match(result.failure, /Package transport failed/);
      assert.doesNotMatch(result.output, /status=publicly-available/);
    });
  }
  /* 2026-10-20：版本可见不等于同一个安装包，已有错误包必须失败且不尝试覆盖上传。 */
  test(store + ' rejects wrong public package bytes without another upload', () => {
    const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
    const result = execute(store, 'wrong-public-package', credential);
    assert.match(result.failure, /public package checksum mismatch/);
    assert.equal(result.uploads, 0);
    assert.equal(result.downloads, 1);
    assert.equal(result.downloadLeftovers, 0);
    assert.match(result.output, /status=package-mismatch/);
    assert.doesNotMatch(result.output, /status=publicly-available/);
    assert.notEqual(result.originalHash, result.inputHash);
  });
  /* 2026-10-20：上传后才传播出来的错误包同样失败；网络抖动与缺少下载链接不能触发重复上传。 */
  test(store + ' rejects mismatched bytes discovered after upload', () => {
    const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
    const result = execute(store, 'eventually-wrong-package', credential);
    assert.match(result.failure, /public package checksum mismatch/);
    assert.equal(result.uploads, 1);
    assert.equal(result.downloads, 1);
    assert.equal(result.downloadLeftovers, 0);
    assert.match(result.output, /status=package-mismatch/);
    assert.doesNotMatch(result.output, /status=publicly-available/);
  });
  for (const mode of ['public-download-failed', 'public-download-transient', 'missing-package-url', 'insecure-package-url', 'wrong-package-origin']) {
    test(store + ' verifies public bytes without duplicate uploads: ' + mode, () => {
      const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
      const result = execute(store, mode, credential);
      assert.equal(result.uploads, 0);
      assert.equal(result.downloadLeftovers, 0);
      assert.equal(result.queries, mode === 'public-download-transient' ? 2 : 4);
      assert.match(result.output, /status=verification-pending/);
      if (mode === 'public-download-transient') {
        assert.equal(result.failure, null);
        assert.equal(result.downloads, 2);
        assert.match(result.output, /status=publicly-available/);
      } else {
        assert.ok(result.failure);
        assert.equal(result.downloads, mode === 'public-download-failed' ? 4 : 0);
        assert.doesNotMatch(result.output, /status=publicly-available/);
      }
    });
  }
  test(store + ' missing credential explicitly skips publication', () => {
    const result = execute(store, 'no-secret');
    assert.equal(result.failure, null);
    assert.match(result.output, /status=not-configured/);
    assert.equal(result.uploads + result.queries, 0);
    assert.equal(result.downloads, 0); // 2026-10-20：缺凭据步骤继续明确跳过，不会额外读取公开包。
  });
  for (const mode of ['already-public', 'eventually-public', 'pending', 'upload-error']) {
    test(store + ' public availability and bounded retries: ' + mode, () => {
      const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
      const result = execute(store, mode, credential);
      if (mode === 'already-public' || mode === 'eventually-public') {
        assert.equal(result.failure, null);
        assert.match(result.output, /status=publicly-available/);
        assert.equal(result.downloads, 1); // 2026-10-20：公开状态还必须读取并核对一个实际归档。
        if (store === 'marketplace') assert.equal(result.marketplaceFlags, 35);
      } else {
        assert.ok(result.failure);
        assert.doesNotMatch(result.output, /status=publicly-available/);
      }
      assert.equal(result.uploads, mode === 'already-public' ? 0 : 1);
      assert.equal(result.queries, mode === 'already-public' || mode === 'upload-error' ? 1 : mode === 'eventually-public' ? 3 : 4);
      assert.equal(result.sleeps, mode === 'pending' ? 2 : mode === 'eventually-public' ? 1 : 0);
      assert.equal(result.downloadLeftovers, 0); // 2026-10-20：成功、校验失败及部分传输都不能留下临时安装包。
      if (mode === 'pending') assert.match(result.output, /status=uploaded-pending/);
      if (mode === 'upload-error') assert.match(result.output, /status=upload-failed/);
    });
  }
}
/* 2026-10-20：版本存在但暂未开放下载属于核验等待，不能把它当缺失版本重新上传。 */
test('openvsx does not upload a visible version that is not downloadable', () => {
  const result = execute('openvsx', 'not-downloadable', { OVSX_PAT: 'inert-test-value' });
  assert.equal(result.uploads, 0);
  assert.equal(result.downloads, 0);
  assert.equal(result.queries, 4);
  assert.equal(result.sleeps, 2);
  assert.ok(result.failure);
  assert.match(result.output, /status=verification-pending/);
  assert.doesNotMatch(result.output, /status=publicly-available|status=uploaded-pending/);
});

/* 2026-10-20：同版本随后恢复可下载时只完成核验，不额外上传。 */
test('openvsx waits for an existing version to become downloadable', () => {
  const result = execute('openvsx', 'downloadable-transient', { OVSX_PAT: 'inert-test-value' });
  assert.equal(result.failure, null);
  assert.equal(result.uploads, 0);
  assert.equal(result.downloads, 1);
  assert.equal(result.queries, 2);
  assert.equal(result.downloadLeftovers, 0);
  assert.match(result.output, /status=verification-pending/);
  assert.match(result.output, /status=publicly-available/);
});

test('summary does not describe missing credentials as store availability', () => {
  const result = execute('publication_summary', 'summary', { RELEASE_OUTCOME: 'success', RELEASE_PROCEED: 'true', RELEASE_URL: 'https://github.com/fixture/release',
    MARKETPLACE_STATUS: 'not-configured', MARKETPLACE_OUTCOME: 'success', OPENVSX_STATUS: 'not-configured', OPENVSX_OUTCOME: 'success' });
  assert.equal(result.failure, null);
  assert.equal((result.summary.match(/not published/g) || []).length, 2);
  assert.doesNotMatch(result.summary, /exact version publicly available/);
});
test('summary restores store failure after independent attempts', () => {
  const result = execute('publication_summary', 'summary', { RELEASE_OUTCOME: 'success', RELEASE_PROCEED: 'true', RELEASE_URL: 'https://github.com/fixture/release',
    MARKETPLACE_STATUS: 'uploaded-pending', MARKETPLACE_OUTCOME: 'failure', OPENVSX_STATUS: 'publicly-available', OPENVSX_OUTCOME: 'success' });
  assert.ok(result.failure);
  assert.match(result.summary, /public availability unconfirmed/);
  assert.match(result.summary, /Open VSX: exact version publicly available/);
});

/* 2026-10-20：版本可见但下载未核验与字节不符都保持失败，不能在汇总里升级为上架成功。 */
test('summary distinguishes pending package verification from mismatched package failure', () => {
  const result = execute('publication_summary', 'summary', { RELEASE_OUTCOME: 'success', RELEASE_PROCEED: 'true',
    MARKETPLACE_STATUS: 'verification-pending', MARKETPLACE_OUTCOME: 'failure', OPENVSX_STATUS: 'package-mismatch', OPENVSX_OUTCOME: 'failure' });
  assert.ok(result.failure);
  assert.match(result.summary, /package download verification unconfirmed/);
  assert.doesNotMatch(result.summary, /exact version publicly available/);
});
