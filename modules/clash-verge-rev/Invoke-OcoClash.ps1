[CmdletBinding()]
param([switch]$CheckOnly,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$arg=if($SelfTest){'--self-test'}elseif($CheckOnly){'--check'}else{'--apply'}
& (Join-Path $PSScriptRoot 'Clash-OneClick-Config.bat') $arg
exit $LASTEXITCODE
