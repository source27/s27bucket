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

function Convert-AutoupdateUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template
    )

    # packages.json stores Scoop placeholders as $version / $matchX.
    # Escape accidental {version} style tokens into Scoop $version form.
    return ($Template -replace '\{version\}', '$version')
}

function New-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Hash,
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $autoupdateUrl = Convert-AutoupdateUrl -Template ([string]$PackageConfig.autoupdateUrl)

    $manifest = [ordered]@{
        version      = $Version
        description  = $PackageConfig.description
        homepage     = $PackageConfig.homepage
        license      = $PackageConfig.license
        architecture = [ordered]@{
            '64bit' = [ordered]@{
                url  = $Url
                hash = $Hash
            }
        }
        bin          = $PackageConfig.bin
    }

    if ($PackageConfig.PSObject.Properties.Name -contains 'notes' -and $PackageConfig.notes) {
        $manifest['notes'] = @($PackageConfig.notes)
    }

    if ($PackageConfig.PSObject.Properties.Name -contains 'checkver' -and $PackageConfig.checkver) {
        $checkver = [ordered]@{}
        foreach ($prop in $PackageConfig.checkver.PSObject.Properties) {
            $checkver[$prop.Name] = $prop.Value
        }
        $manifest['checkver'] = $checkver
    }
    else {
        $manifest['checkver'] = [ordered]@{
            github = "https://github.com/$($PackageConfig.repository)"
        }
    }

    $manifest['autoupdate'] = [ordered]@{
        architecture = [ordered]@{
            '64bit' = [ordered]@{
                url = $autoupdateUrl
            }
        }
    }

    return $manifest
}

function ConvertTo-ScoopJson {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [int]$Depth = 0
    )

    $indent = '  ' * $Depth
    $childIndent = '  ' * ($Depth + 1)

    if ($null -eq $InputObject) {
        return 'null'
    }

    if ($InputObject -is [string]) {
        $escaped = $InputObject.
            Replace('\', '\\').
            Replace('"', '\"').
            Replace("`r", '\r').
            Replace("`n", '\n').
            Replace("`t", '\t')
        return "`"$escaped`""
    }

    if ($InputObject -is [bool]) {
        if ($InputObject) { return 'true' } else { return 'false' }
    }

    if ($InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal]) {
        return [string]$InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $entries = @()
        foreach ($key in $InputObject.Keys) {
            $valueJson = ConvertTo-ScoopJson -InputObject $InputObject[$key] -Depth ($Depth + 1)
            $entries += "$childIndent$(ConvertTo-ScoopJson -InputObject ([string]$key) -Depth 0): $valueJson"
        }
        if ($entries.Count -eq 0) {
            return '{}'
        }
        return "{`r`n$($entries -join ",`r`n")`r`n$indent}"
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += "$childIndent$(ConvertTo-ScoopJson -InputObject $item -Depth ($Depth + 1))"
        }
        if ($items.Count -eq 0) {
            return '[]'
        }
        return "[`r`n$($items -join ",`r`n")`r`n$indent]"
    }

    # PSCustomObject / generic object
    $props = @($InputObject.PSObject.Properties)
    if ($props.Count -gt 0 -and ($InputObject -is [psobject])) {
        $entries = @()
        foreach ($prop in $props) {
            $valueJson = ConvertTo-ScoopJson -InputObject $prop.Value -Depth ($Depth + 1)
            $entries += "$childIndent$(ConvertTo-ScoopJson -InputObject ([string]$prop.Name) -Depth 0): $valueJson"
        }
        return "{`r`n$($entries -join ",`r`n")`r`n$indent}"
    }

    return (ConvertTo-ScoopJson -InputObject ([string]$InputObject) -Depth $Depth)
}

function Write-PackageManifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig,
        [Parameter(Mandatory = $true)]
        $Manifest,
        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    $manifestJson = (ConvertTo-ScoopJson -InputObject $Manifest) + "`r`n"

    $manifestPath = Join-Path (Join-Path $scriptRoot '..\bucket') ($PackageConfig.name + '.json')
    $resolvedManifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    $manifestDir = Split-Path -Parent $resolvedManifestPath
    if (-not (Test-Path $manifestDir)) {
        New-Item -ItemType Directory -Path $manifestDir | Out-Null
    }

    [System.IO.File]::WriteAllText($resolvedManifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated manifest: $resolvedManifestPath"
    Write-Host "Package: $($PackageConfig.name)"
    Write-Host "Version: $($Manifest.version)"
    Write-Host "Asset: $AssetName"
    Write-Host "SHA256: $($Manifest.architecture.'64bit'.hash)"
}

function Get-GitHubReleaseWithAsset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string]$AssetPattern,
        [switch]$IncludePrerelease
    )

    if (-not $IncludePrerelease) {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        if (-not $asset) {
            throw "Asset pattern '$AssetPattern' not found in latest release for $Repository"
        }
        return [pscustomobject]@{
            Release = $release
            Asset   = $asset
        }
    }

    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases?per_page=30"
    foreach ($release in $releases) {
        if ($release.draft) {
            continue
        }
        $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        if ($asset) {
            return [pscustomobject]@{
                Release = $release
                Asset   = $asset
            }
        }
    }

    throw "No release with asset pattern '$AssetPattern' found for $Repository"
}

function Update-GitHubPackageManifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig
    )

    $includePrerelease = $false
    if ($PackageConfig.PSObject.Properties.Name -contains 'includePrerelease') {
        $includePrerelease = [bool]$PackageConfig.includePrerelease
    }

    $found = Get-GitHubReleaseWithAsset `
        -Repository $PackageConfig.repository `
        -AssetPattern $PackageConfig.assetPattern `
        -IncludePrerelease:$includePrerelease

    $release = $found.Release
    $asset = $found.Asset
    $version = $release.tag_name.TrimStart('v')

    if ($PackageConfig.PSObject.Properties.Name -contains 'versionStripPrefix' -and $PackageConfig.versionStripPrefix) {
        $prefix = [string]$PackageConfig.versionStripPrefix
        if ($version.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $version = $version.Substring($prefix.Length)
        }
    }

    $hashSidecarSuffix = '.sha256'
    if ($PackageConfig.PSObject.Properties.Name -contains 'hashSidecarSuffix' -and $PackageConfig.hashSidecarSuffix) {
        $hashSidecarSuffix = [string]$PackageConfig.hashSidecarSuffix
    }

    $hash = Resolve-Hash -Release $release -Asset $asset -HashSidecarSuffix $hashSidecarSuffix
    $manifest = New-Manifest -PackageConfig $PackageConfig -Url $asset.browser_download_url -Hash $hash -Version $version
    Write-PackageManifest -PackageConfig $PackageConfig -Manifest $manifest -AssetName $asset.name
}

function Update-PreviewManifestPackage {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig
    )

    $manifestUrl = [string]$PackageConfig.manifestUrl
    if (-not $manifestUrl) {
        throw "Package '$($PackageConfig.name)' is missing manifestUrl"
    }

    $preview = Invoke-RestMethod -Uri $manifestUrl
    $assetKey = [string]$PackageConfig.assetKey
    if (-not $assetKey) {
        throw "Package '$($PackageConfig.name)' is missing assetKey"
    }

    $assetProp = $preview.assets.PSObject.Properties[$assetKey]
    if (-not $assetProp) {
        throw "Asset key '$assetKey' not found in $manifestUrl"
    }

    $asset = $assetProp.Value
    $url = if ($asset -is [string]) { [string]$asset } else { [string]$asset.url }
    if (-not $url) {
        throw "Asset key '$assetKey' has no url in $manifestUrl"
    }

    $hash = $null
    if ($asset -isnot [string] -and $asset.PSObject.Properties.Name -contains 'sha256' -and $asset.sha256) {
        $hash = ([string]$asset.sha256).ToLowerInvariant()
    }
    if (-not $hash) {
        throw "Asset key '$assetKey' is missing sha256 in $manifestUrl"
    }

    $baseVersion = [string]$preview.base_version
    $buildId = [string]$preview.build_id
    if (-not $baseVersion -or -not $buildId) {
        throw "Preview manifest is missing base_version or build_id: $manifestUrl"
    }

    $version = "$baseVersion-preview.$buildId"
    $assetName = Split-Path -Leaf ([Uri]$url).AbsolutePath
    $manifest = New-Manifest -PackageConfig $PackageConfig -Url $url -Hash $hash -Version $version
    Write-PackageManifest -PackageConfig $PackageConfig -Manifest $manifest -AssetName $assetName
}

function Update-PackageManifest {
    param(
        [Parameter(Mandatory = $true)]
        $PackageConfig
    )

    $source = 'github'
    if ($PackageConfig.PSObject.Properties.Name -contains 'source' -and $PackageConfig.source) {
        $source = [string]$PackageConfig.source
    }

    switch ($source) {
        'github' {
            Update-GitHubPackageManifest -PackageConfig $PackageConfig
        }
        'preview-manifest' {
            Update-PreviewManifestPackage -PackageConfig $PackageConfig
        }
        default {
            throw "Unsupported package source '$source' for $($PackageConfig.name)"
        }
    }
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
