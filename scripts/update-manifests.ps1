[CmdletBinding()]
param(
    [string]$Package,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $scriptRoot 'packages.json'
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

function Resolve-Hash {
    param(
        [Parameter(Mandatory = $true)]
        $Release,
        [Parameter(Mandatory = $true)]
        $Asset,
        [string]$HashSidecarSuffix = '.sha256'
    )

    if ($Asset.digest -match '^sha256:(?<value>[A-Fa-f0-9]{64})$') {
        return $Matches.value.ToLowerInvariant()
    }

    $hashAsset = $Release.assets | Where-Object { $_.name -eq ($Asset.name + $HashSidecarSuffix) } | Select-Object -First 1
    if (-not $hashAsset) {
        throw "No SHA256 digest found for asset $($Asset.name)"
    }

    return Get-Sha256FromSidecar -Url $hashAsset.browser_download_url
}

function New-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig,
        [Parameter(Mandatory = $true)]
        $Release,
        [Parameter(Mandatory = $true)]
        $Asset,
        [Parameter(Mandatory = $true)]
        [string]$Hash,
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $autoupdateUrl = $PackageConfig.autoupdateUrl -replace '\{version\}', '$version'

    return [ordered]@{
        version      = $Version
        description  = $PackageConfig.description
        homepage     = $PackageConfig.homepage
        license      = $PackageConfig.license
        architecture = [ordered]@{
            '64bit' = [ordered]@{
                url  = $Asset.browser_download_url
                hash = $Hash
            }
        }
        bin          = $PackageConfig.bin
        checkver     = [ordered]@{
            github = "https://github.com/$($PackageConfig.repository)"
        }
        autoupdate   = [ordered]@{
            architecture = [ordered]@{
                '64bit' = [ordered]@{
                    url = $autoupdateUrl
                }
            }
        }
    }
}

function Update-PackageManifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig
    )

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($PackageConfig.repository)/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like $PackageConfig.assetPattern } | Select-Object -First 1
    if (-not $asset) {
        throw "Asset pattern '$($PackageConfig.assetPattern)' not found in latest release for $($PackageConfig.repository)"
    }

    $version = $release.tag_name.TrimStart('v')
    $hashSidecarSuffix = '.sha256'
    if ($PackageConfig.PSObject.Properties.Name -contains 'hashSidecarSuffix' -and $PackageConfig.hashSidecarSuffix) {
        $hashSidecarSuffix = [string]$PackageConfig.hashSidecarSuffix
    }

    $hash = Resolve-Hash -Release $release -Asset $asset -HashSidecarSuffix $hashSidecarSuffix

    $manifest = New-Manifest -PackageConfig $PackageConfig -Release $release -Asset $asset -Hash $hash -Version $version
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    $manifestJson += "`r`n"

    $manifestPath = Join-Path (Join-Path $scriptRoot '..\bucket') ($PackageConfig.name + '.json')
    $resolvedManifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    $manifestDir = Split-Path -Parent $resolvedManifestPath
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir | Out-Null
    }

    [System.IO.File]::WriteAllText($resolvedManifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated manifest: $resolvedManifestPath"
    Write-Host "Package: $($PackageConfig.name)"
    Write-Host "Version: $version"
    Write-Host "Asset: $($asset.name)"
    Write-Host "SHA256: $hash"
}

$configItems = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
if ($Package) {
    $packagesToUpdate = @($configItems | Where-Object { $_.name -eq $Package })
    if ($packagesToUpdate.Count -eq 0) {
        throw "Package '$Package' not found in $ConfigPath"
    }
}
else {
    $packagesToUpdate = @($configItems)
}

foreach ($packageConfig in $packagesToUpdate) {
    Update-PackageManifest -PackageConfig $packageConfig
}
