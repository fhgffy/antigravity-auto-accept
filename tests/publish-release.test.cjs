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
  "  $visible = $env:TEST_MODE -eq 'already-public' -or ($env:TEST_MODE -eq 'eventually-public' -and $script:Queries -ge 3)",
  "  if ($Uri -like 'https://marketplace.visualstudio.com/*') {",
  "    $request = $Body | ConvertFrom-Json; if ($request.flags -ne 33 -or $request.filters[0].criteria[0].filterType -ne 7) { throw 'Marketplace must exclude nonvalidated versions' }",
  "    $version = if ($visible) { '1.2.3' } else { '9.9.9' }",
  "    $publisher = if ($env:TEST_MODE -eq 'wrong-identity') { 'other' } else { 'fhgffy' }",
  "    return @{ results = @(@{ extensions = @(@{ publisher = @{ publisherName = $publisher }; extensionName = 'antigravity-auto-accept'; versions = @(@{ version = $version }, @{ version = '8.0.0' }) }) }) }",
  "  }",
  "  if ($Uri -cne 'https://open-vsx.org/api/fhgffy/antigravity-auto-accept/1.2.3') { throw 'Open VSX must query exact version' }",
  "  if (-not $visible) { return @{ error = 'not found'; namespace = 'fhgffy'; name = 'antigravity-auto-accept'; version = '1.2.3' } }",
  "  return @{ namespace = 'fhgffy'; name = 'antigravity-auto-accept'; version = '1.2.3'; downloadable = $true; files = @{ download = 'https://open-vsx.org/fixture.vsix' } }",
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
    '[ordered]@{ failure = $failure; calls = @($script:Calls); queries = $script:Queries; sleeps = $script:Sleeps; uploads = $script:Uploads; output = [IO.File]::ReadAllText($env:GITHUB_OUTPUT); summary = [IO.File]::ReadAllText($env:GITHUB_STEP_SUMMARY); inputHash = (Get-FileHash $script:InputPath).Hash; originalHash = (Get-FileHash $script:OriginalPath).Hash; selectedHash = $(if (Test-Path (Join-Path $env:RUNNER_TEMP ("publish-release/" + $script:FileName))) { (Get-FileHash (Join-Path $env:RUNNER_TEMP ("publish-release/" + $script:FileName))).Hash } else { $null }) } | ConvertTo-Json -Depth 10 -Compress';
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
  assert.match(job, /needs: package/);
  assert.match(job, /github\.repository == 'fhgffy\/antigravity-auto-accept'/);
  assert.match(job, /github\.event_name == 'push'/);
  assert.match(job, /github\.ref == 'refs\/heads\/main'/);
  assert.match(job, /actions\/download-artifact@v8\.0\.1/);
  assert.match(job, /name: antigravity-auto-accept-\$\{\{ github\.sha \}\}/);
  assert.doesNotMatch(job, /workflow_run|--clobber/);
  assert.match(workflow, /cancel-in-progress: \$\{\{ github\.ref != 'refs\/heads\/main' \}\}/);
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
  test(store + ' missing credential explicitly skips publication', () => {
    const result = execute(store, 'no-secret');
    assert.equal(result.failure, null);
    assert.match(result.output, /status=not-configured/);
    assert.equal(result.uploads + result.queries, 0);
  });
  for (const mode of ['already-public', 'eventually-public', 'pending', 'upload-error']) {
    test(store + ' public availability and bounded retries: ' + mode, () => {
      const credential = store === 'marketplace' ? { VSCE_PAT: 'inert-test-value' } : { OVSX_PAT: 'inert-test-value' };
      const result = execute(store, mode, credential);
      if (mode === 'already-public' || mode === 'eventually-public') {
        assert.equal(result.failure, null);
        assert.match(result.output, /status=publicly-available/);
      } else {
        assert.ok(result.failure);
        assert.doesNotMatch(result.output, /status=publicly-available/);
      }
      assert.equal(result.uploads, mode === 'already-public' ? 0 : 1);
      assert.equal(result.queries, mode === 'already-public' || mode === 'upload-error' ? 1 : mode === 'eventually-public' ? 3 : 4);
      assert.equal(result.sleeps, mode === 'pending' ? 2 : mode === 'eventually-public' ? 1 : 0);
      if (mode === 'pending') assert.match(result.output, /status=uploaded-pending/);
      if (mode === 'upload-error') assert.match(result.output, /status=upload-failed/);
    });
  }
}
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
