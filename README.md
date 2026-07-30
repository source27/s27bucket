# s27bucket

Custom Scoop bucket for packages maintained in this repository.

## Add this bucket

```powershell
scoop bucket add s27bucket https://github.com/source27/s27bucket.git
```

## Install package

```powershell
scoop install usagi
```

## Current packages

| Package | Description | Source | Windows package | Install |
| --- | --- | --- | --- | --- |
| `usagi` | A simple 2D game engine for rapid prototyping with Lua. | `brettchalupa/usagi` | `usagi.exe` | `scoop install usagi` |

## Update manifests locally

This bucket includes a generic generator that reads package definitions from `scripts/packages.json` and rewrites manifests in `bucket/`.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-manifests.ps1
```

Update a single package:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-manifests.ps1 -Package usagi
```

The legacy single-package entrypoint still works:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-usagi.ps1
```

After a manifest is updated, test it with:

```powershell
scoop install .\bucket\usagi.json
```

## Repository layout

- `bucket/*.json`: Scoop manifests
- `scripts/packages.json`: package definitions for the generator
- `scripts/update-manifests.ps1`: generic manifest generator/updater
- `scripts/update-usagi.ps1`: compatibility wrapper for `usagi`
- `.github/workflows/update-usagi.yml`: scheduled auto-update workflow

## Automation

GitHub Actions runs the generic updater on a schedule and on manual dispatch. When any upstream release changes, it commits the refreshed manifests back to this repository.
