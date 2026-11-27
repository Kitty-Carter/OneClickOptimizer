[CmdletBinding()]
param([switch]$CheckOnly,[switch]$SelfTest)
$ErrorActionPreference='Stop'
if($SelfTest){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SelfTest.ps1');exit $LASTEXITCODE}
$mode=if($CheckOnly){'Check'}else{'Optimize'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Start-ClashOptimizer.ps1') -Action $mode
exit $LASTEXITCODE
