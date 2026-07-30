[CmdletBinding()]
param(
    [string]$Repository = 'brettchalupa/usagi',
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

if (-not $ManifestPath) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ManifestPath = Join-Path $scriptRoot '..\bucket\usagi.json'
}

function Get-Sha256FromSidecar {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $content = Invoke-RestMethod -Uri $Url
    if ($content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($content)
    }

    $text = [string]$content
    $hash = ($text -split '\s+')[0].Trim()
    if (-not $hash) {
        throw "Unable to parse SHA256 from sidecar file: $Url"
    }

    return $hash.ToLowerInvariant()
}

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest"

$asset = $release.assets | Where-Object { $_.name -like '*-windows-x86_64.zip' } | Select-Object -First 1
if (-not $asset) {
    throw "Windows x86_64 zip asset not found in latest release for $Repository"
}

$hash = $null
if ($asset.digest -match '^sha256:(?<value>[A-Fa-f0-9]{64})$') {
    $hash = $Matches.value.ToLowerInvariant()
}

if (-not $hash) {
    $hashAsset = $release.assets | Where-Object { $_.name -eq ($asset.name + '.sha256') } | Select-Object -First 1
    if (-not $hashAsset) {
        throw "No SHA256 digest found for asset $($asset.name)"
    }

    $hash = Get-Sha256FromSidecar -Url $hashAsset.browser_download_url
}

$version = $release.tag_name.TrimStart('v')

$manifest = [ordered]@{
    version      = $version
    description  = 'A simple 2D game engine for rapid prototyping with Lua.'
    homepage     = 'https://github.com/brettchalupa/usagi'
    license      = 'Unlicense'
    architecture = [ordered]@{
        '64bit' = [ordered]@{
            url  = $asset.browser_download_url
            hash = $hash
        }
    }
    bin          = 'usagi.exe'
    checkver     = [ordered]@{
        github = 'https://github.com/brettchalupa/usagi'
    }
    autoupdate   = [ordered]@{
        architecture = [ordered]@{
            '64bit' = [ordered]@{
                url = 'https://github.com/brettchalupa/usagi/releases/download/v$version/usagi-$version-windows-x86_64.zip'
            }
        }
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 8
$manifestJson += "`r`n"

$resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$manifestDir = Split-Path -Parent $resolvedManifestPath
if (-not (Test-Path $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir | Out-Null
}

[System.IO.File]::WriteAllText($resolvedManifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated manifest: $resolvedManifestPath"
Write-Host "Version: $version"
Write-Host "Asset: $($asset.name)"
Write-Host "SHA256: $hash"
