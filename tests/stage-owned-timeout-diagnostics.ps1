# 2026-10-23：失败后只复制五种自有诊断目录到单个独占根；原件不动，重解析成员和部分复制失败分别保留。
$ErrorActionPreference = 'Stop'
$errors = [Collections.Generic.List[string]]::new()
$roots = [Collections.Generic.List[string]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$candidates = @($env:RUNNER_TEMP, [IO.Path]::GetTempPath())
if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $candidates += [IO.Path]::Combine($env:USERPROFILE, 'AppData', 'Local', 'Temp') }
foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    try {
        $full = [IO.Path]::GetFullPath($candidate)
        if (-not [IO.Directory]::Exists($full) -or -not $seen.Add($full.TrimEnd([char[]]'\/'))) { continue }
        $directory = [IO.DirectoryInfo]::new($full)
        for ($ancestor = $directory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
            if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Rejected reparse temporary root: $full" }
        }
        $roots.Add($directory.FullName)
    } catch { $errors.Add("Temporary root $candidate`: " + $_.Exception.Message) }
}
if ($roots.Count -eq 0) { throw 'No safe existing temporary root for owned timeout staging' }
$uploadRoot = [IO.Path]::Combine($roots[0], 'AntigravityAA-TimeoutUpload-' + [Guid]::NewGuid().ToString('N'))
if ([IO.Directory]::Exists($uploadRoot) -or [IO.File]::Exists($uploadRoot)) { throw 'Preserve an existing timeout staging root' }
[void][IO.Directory]::CreateDirectory($uploadRoot)
$boundary = [IO.Path]::GetFullPath($uploadRoot).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
# 2026-10-23：先交付已知单根，再逐项复制；后续目录、文件或记录错误不阻止上传已可用的旁证。
try { [IO.File]::AppendAllText($env:GITHUB_OUTPUT, "path=$uploadRoot" + [Environment]::NewLine, [Text.UTF8Encoding]::new($false)) }
catch { $errors.Add('Upload output: ' + $_.Exception.Message) }
$sources = [Collections.Generic.List[object]]::new()
$matched = 0
$copied = 0
for ($index = 0; $index -lt $roots.Count; $index++) {
    $sourceName = 'source-' + $index
    $sources.Add([ordered]@{ Name = $sourceName; Path = $roots[$index] })
    try { $directories = ([IO.DirectoryInfo]::new($roots[$index])).GetDirectories() }
    catch { $errors.Add($roots[$index] + ': ' + $_.Exception.Message); continue }
    foreach ($directory in $directories) {
        if ($directory.Name -cnotmatch '^AntigravityAA-(HostBinary|HostWrapper|ScannerTimeout|DumpCollector|LifecycleTimeout)-.+$') { continue }
        $matched++
        try {
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Rejected reparse owned directory' }
            $destinationBase = [IO.Path]::Combine($uploadRoot, $sourceName, $directory.Name)
            if (-not ([IO.Path]::GetFullPath($destinationBase)).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Owned staging directory escaped output root' }
            [void][IO.Directory]::CreateDirectory($destinationBase)
            $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
            $pending.Push($directory)
            while ($pending.Count -gt 0) {
                $current = $pending.Pop()
                try {
                    if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Rejected reparse owned directory' }
                    $entries = $current.GetFileSystemInfos()
                } catch { $errors.Add($current.FullName + ': ' + $_.Exception.Message); continue }
                foreach ($entry in $entries) {
                    try {
                        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Rejected reparse diagnostic member' }
                        $relative = $entry.FullName.Substring($directory.FullName.Length).TrimStart([char[]]'\/')
                        $destination = [IO.Path]::GetFullPath([IO.Path]::Combine($destinationBase, $relative))
                        if (-not $destination.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Owned staging member escaped output root' }
                        if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                            [void][IO.Directory]::CreateDirectory($destination)
                            $pending.Push([IO.DirectoryInfo]$entry)
                        } else { [IO.File]::Copy($entry.FullName, $destination, $false); $copied++ }
                    } catch { $errors.Add($entry.FullName + ': ' + $_.Exception.Message) }
                }
            }
        } catch { $errors.Add($directory.FullName + ': ' + $_.Exception.Message) }
    }
}
# 2026-10-23：空集合保持空根供原上传步骤warn；非空或部分失败才附带来源映射和复制错误，不掩盖原测试失败。
$summary = [ordered]@{ UploadRoot = $uploadRoot; Sources = $sources.ToArray(); DirectoriesMatched = $matched; FilesCopied = $copied; Errors = $errors.ToArray(); OriginalFilesModified = $false }
if ($matched -gt 0 -or $errors.Count -gt 0) {
    try { [IO.File]::WriteAllText([IO.Path]::Combine($uploadRoot, 'staging.json'), ($summary | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false)) }
    catch { $errors.Add('Staging receipt: ' + $_.Exception.Message) }
}
$summary.Errors = $errors.ToArray()
Write-Output ('___OWNED_TIMEOUT_STAGING___:' + ($summary | ConvertTo-Json -Depth 5 -Compress))
if ($errors.Count -gt 0) { throw ('Owned timeout staging incomplete: ' + $errors.Count + ' errors; original diagnostics retained') }
