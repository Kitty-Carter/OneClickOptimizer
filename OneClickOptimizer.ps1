#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('menu','list','check','optimize','selftest')][string]$Mode='menu',[string]$ModuleId)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
try {
    Import-Module (Join-Path $PSScriptRoot 'core\ModuleCatalog.psm1') -Force
    $modules=@(Get-OcoModule $PSScriptRoot)
    if ($modules.Count -eq 0) { throw '没有可用模块。' }
    Write-Host 'OneClickOptimizer | 一键优化全家桶 | 0.1.0-alpha.1' -ForegroundColor Cyan
    if ($Mode -eq 'list' -or $Mode -eq 'menu') {
        for ($i=0;$i -lt $modules.Count;$i++) { Write-Host ('[{0}] {1} ({2})' -f ($i+1),$modules[$i].Name,$modules[$i].Status) }
        if ($Mode -eq 'list') { exit 0 }
        $raw=Read-Host '选择软件编号（回车取消）'; $n=0
        if (-not [int]::TryParse($raw,[ref]$n) -or $n -lt 1 -or $n -gt $modules.Count) { exit 1 }
        $ModuleId=$modules[$n-1].Id
        $action=Read-Host '1=仅检查（推荐） 2=优化 3=自检'
        $Mode=switch ($action) {'1' {'check'} '2' {'optimize'} '3' {'selftest'} default {throw '已取消'}}
    }
    $selected=@($modules | Where-Object {$_.Id -ceq $ModuleId})
    if ($selected.Count -ne 1) { throw '请指定唯一模块，例如 -ModuleId positron。' }
    $m=$selected[0]
    if ($Mode -notin $m.Modes) { throw '模块不支持此模式。' }
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($Mode -eq 'optimize') {
        Write-Host '优化将修改选定软件的当前用户设置。请先保存工作。' -ForegroundColor Yellow
        if ((Read-Host '输入 YES 继续') -cne 'YES') { exit 1 }
        & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File $m.Entry -SelfTest
        if ($LASTEXITCODE -ne 0) { throw '自检失败，未执行优化。' }
        & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File $m.Entry
    } elseif ($Mode -eq 'check') { & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File $m.Entry -CheckOnly }
    else { & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File $m.Entry -SelfTest }
    exit $LASTEXITCODE
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
