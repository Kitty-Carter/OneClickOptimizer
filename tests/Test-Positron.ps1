#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
$entry=Join-Path $root 'modules\positron\Optimize-Positron.ps1'
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Assert($ok,[string]$message) { if (-not $ok) { throw $message }; Write-Host "PASS: $message" }
function Run([int]$Expected,[string[]]$Arguments) {
    & $ps -NoProfile -ExecutionPolicy Bypass -File $entry @Arguments
    Assert ($LASTEXITCODE -eq $Expected) "Expected exit $Expected"
}
$t=Join-Path ([IO.Path]::GetTempPath()) ('oco-fixture-'+[guid]::NewGuid().ToString('N'))
$install=Join-Path $t '自定义 软件目录\Positron'; $app=Join-Path $install 'resources\app'; $settings=Join-Path $t '自定义 配置\settings.json'; $backups=Join-Path $t 'backups'
try {
    foreach ($d in @($app,(Split-Path $settings),(Join-Path $app 'extensions\positron-r'),(Join-Path $app 'extensions\quarto'),(Join-Path $app 'out\vs\workbench'),$backups)) { [void][IO.Directory]::CreateDirectory($d) }
    # Dummy file is never launched; executable metadata is not required for fixtures.
    Copy-Item -LiteralPath $ps -Destination (Join-Path $install 'Positron.exe')
    Set-Content -LiteralPath (Join-Path $app 'package.json') -Value '{"name":"fixture"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $app 'extensions\positron-r\package.json') -Value '{"contributes":{"configuration":{"properties":{"positron.r.diagnostics.enabled":{"type":"boolean"}}}}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $app 'extensions\quarto\package.json') -Value '{"contributes":{"configuration":{"properties":{"quarto.symbols.showCodeCellsInOutline":{"type":"boolean"}}}}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $app 'out\vs\workbench\workbench.desktop.main.js') -Value '"packages.r.installer":{enum:["auto","pak","base"]}, "quarto.inlineOutput.enabled", "console.showNotebookConsoles"' -Encoding UTF8
    $old="// keep comment`r`n{`r`n  `"other`": {`"url`":`"https://example.test/a`"},`r`n  `"editor.rulers`": [80],`r`n}`r`n"
    [IO.File]::WriteAllText($settings,$old,(New-Object Text.UTF8Encoding($false)))
    $hash=(Get-FileHash -LiteralPath $settings).Hash
    $argsCommon=@('-InstallPath',$install,'-SettingsPath',$settings,'-BackupRoot',$backups)
    Run 0 @('-SelfTest')
    Run 0 ($argsCommon+@('-CheckOnly'))
    Assert ((Get-FileHash -LiteralPath $settings).Hash -ceq $hash) 'Check-only preserves bytes'
    Assert (@(Get-ChildItem -LiteralPath $backups).Count -eq 0) 'Check-only creates no backups'
    Run 0 $argsCommon
    $after=Get-Content -LiteralPath $settings -Raw -Encoding UTF8
    Assert ($after.Contains('// keep comment') -and $after.Contains('https://example.test/a') -and $after.Contains('"positron.r.diagnostics.enabled": false')) 'Existing text retained; new settings present'
    $b=@(Get-ChildItem -LiteralPath $backups -Directory)
    Assert ($b.Count -eq 1) 'One backup folder'
    Assert ((Get-FileHash -LiteralPath (Join-Path $b[0].FullName 'settings.before.json')).Hash -ceq $hash) 'Exact original bytes backed up'
    $hashAfter=(Get-FileHash -LiteralPath $settings).Hash
    Run 0 $argsCommon
    Assert ((Get-FileHash -LiteralPath $settings).Hash -ceq $hashAfter) 'Idempotent output'
    Assert (@(Get-ChildItem -LiteralPath $backups -Directory).Count -eq 1) 'No redundant backup'
    # Invalid duplicate keys must fail before any write.
    [IO.File]::WriteAllText($settings,'{"a":1,"a":2}')
    $badHash=(Get-FileHash -LiteralPath $settings).Hash
    Run 1 $argsCommon
    Assert ((Get-FileHash -LiteralPath $settings).Hash -ceq $badHash) 'Malformed config unchanged'
    Write-Host 'INTEGRATION_TEST_OK' -ForegroundColor Green
} finally { if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force } }
