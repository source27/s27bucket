[CmdletBinding()]
param()

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$genericScript = Join-Path $scriptRoot 'update-manifests.ps1'

& $genericScript -Package usagi
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
