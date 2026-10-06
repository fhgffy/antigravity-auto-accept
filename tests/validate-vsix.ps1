# 2026-10-07：对最终 VSIX 逐项核对运行文件及发布版本，开发目录和旧运行模块不得混入安装包。
param([Parameter(Mandatory = $true)][string]$VsixPath)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$packagePath = [IO.Path]::GetFullPath($VsixPath)
$strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
$manifest = $strictUtf8.GetString([IO.File]::ReadAllBytes((Join-Path $root 'package.json'))) | ConvertFrom-Json
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 2026-10-07：仅从归档读取字节，不解压、不安装，也不访问用户的 IDE 扩展目录。
function Get-VsixEntryBytes($Archive, [string]$Name) {
    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) { throw "Missing VSIX entry: $Name" }
    $stream = $entry.Open()
    $memory = New-Object IO.MemoryStream
    try {
        $stream.CopyTo($memory)
        return ,$memory.ToArray()
    }
    finally {
        $stream.Dispose()
        $memory.Dispose()
    }
}

$archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $allowed = @('extension.vsixmanifest', '[Content_Types].xml', 'extension/icon.png', 'extension/LICENSE.txt', 'extension/package.json', 'extension/readme.md', 'extension/out/extension.js', 'extension/src/autoClicker.ps1')
    $entries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | Select-Object -ExpandProperty FullName)
    if ($entries.Count -ne $allowed.Count -or @($entries | Select-Object -Unique).Count -ne $entries.Count) { throw 'Unexpected or duplicate VSIX entries' }
    foreach ($entry in $entries) { if ($entry -cnotin $allowed) { throw "Unexpected VSIX entry: $entry" } }
    $packedManifest = $strictUtf8.GetString((Get-VsixEntryBytes $archive 'extension/package.json')) | ConvertFrom-Json
    if (($manifest | ConvertTo-Json -Depth 100 -Compress) -cne ($packedManifest | ConvertTo-Json -Depth 100 -Compress)) { throw 'Packaged manifest differs from package.json' }
    [xml]$vsixManifest = $strictUtf8.GetString((Get-VsixEntryBytes $archive 'extension.vsixmanifest'))
    $identity = $vsixManifest.SelectSingleNode("/*[local-name()='PackageManifest']/*[local-name()='Metadata']/*[local-name()='Identity']")
    if ($null -eq $identity -or $identity.GetAttribute('Version') -cne $manifest.version -or $identity.GetAttribute('Id') -cne $manifest.name -or $identity.GetAttribute('Publisher') -cne $manifest.publisher) { throw 'VSIX identity or release version mismatch' }

    # 2026-10-07：README 可能被 VSCE 正常改写相对链接；运行代码与二进制资源仍要求原字节一致。
    $runtimeFiles = @{
        'extension/out/extension.js' = 'out/extension.js'
        'extension/src/autoClicker.ps1' = 'src/autoClicker.ps1'
        'extension/icon.png' = 'icon.png'
        'extension/LICENSE.txt' = 'LICENSE'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($entryName in $runtimeFiles.Keys) {
            $packedHash = [BitConverter]::ToString($sha.ComputeHash((Get-VsixEntryBytes $archive $entryName)))
            $sourceHash = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes((Join-Path $root $runtimeFiles[$entryName]))))
            if ($packedHash -cne $sourceHash) { throw "Packaged bytes differ: $entryName" }
            Write-Output "PASS packaged bytes: $entryName"
        }
    }
    finally { $sha.Dispose() }
    if ([string]::IsNullOrWhiteSpace($strictUtf8.GetString((Get-VsixEntryBytes $archive 'extension/readme.md')))) { throw 'Packaged README is empty' }
    Write-Output "___VSIX_VALIDATION_DONE___:version=$($manifest.version):files=$($entries.Count)"
}
finally { $archive.Dispose() }
