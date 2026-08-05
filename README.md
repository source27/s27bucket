# s27bucket

Custom Scoop bucket for packages maintained in this repository.

## Add this bucket

```powershell
scoop bucket add s27bucket https://github.com/source27/s27bucket.git
```

## Install packages

```powershell
scoop install usagi
scoop install herdr
```

## Current packages

| Package | Description | Source | Windows package | Install |
| --- | --- | --- | --- | --- |
| `usagi` | A simple 2D game engine for rapid prototyping with Lua. | `brettchalupa/usagi` | `usagi.exe` | `scoop install usagi` |
| `herdr` | The runtime your coding agents live on: always-on agent terminal workspace. | `herdrdev/herdr` (Windows preview channel) | `herdr.exe` | `scoop install herdr` |

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
scoop install .\bucket\herdr.json
```

## Repository layout

- `bucket/*.json`: Scoop manifests
- `scripts/packages.json`: package definitions for the generator
- `scripts/update-manifests.ps1`: generic manifest generator/updater
- `scripts/update-usagi.ps1`: compatibility wrapper for `usagi`
- `.github/workflows/update-usagi.yml`: scheduled auto-update workflow (all packages in `packages.json`)

## Notes

- `herdr` Windows builds are **preview-only** upstream. This bucket tracks `https://herdr.dev/preview.json` (same channel as the official `install.ps1`).

## Automation

GitHub Actions runs the generic updater on a schedule and on manual dispatch. When any upstream release changes, it commits the refreshed manifests back to this repository.
