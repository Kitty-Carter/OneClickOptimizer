$ErrorActionPreference='Stop'
foreach($f in @('Verify-Package.ps1','Start-ClashOptimizer.ps1','Optimize-Clash.ps1','Diagnose-Clash.ps1','Inspect-Local.ps1')){
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $f) -SelfTest
 if($LASTEXITCODE){throw "SelfTest failed: $f"}
}
& (Join-Path $PSScriptRoot 'bin\oco-node-quality.exe') --selftest
if($LASTEXITCODE){throw 'Rust self-test failed'}
Write-Host 'ALL OFFLINE SELF-TESTS PASSED'
