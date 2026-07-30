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

## Update manifest locally

This bucket includes a generator script that reads the latest GitHub release from `brettchalupa/usagi` and rewrites `bucket/usagi.json`.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-usagi.ps1
```

After the manifest is updated, test it with:

```powershell
scoop install .\bucket\usagi.json
```

## Repository layout

- `bucket/usagi.json`: Scoop manifest for `usagi`
- `scripts/update-usagi.ps1`: manifest generator/updater
- `.github/workflows/update-usagi.yml`: scheduled auto-update workflow

## Automation

GitHub Actions runs the updater on a schedule and on manual dispatch. When a new upstream release is detected, it commits the refreshed manifest back to this repository.
