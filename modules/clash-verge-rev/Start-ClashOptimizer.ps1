[CmdletBinding()]
param([switch]$SelfTest,[switch]$RequireBinaries,[string]$DataPath,[string]$AppPath,[ValidateRange(1,65535)][int]$Port=7897)
$ErrorActionPreference='Stop'
function Say([string]$s){Write-Host $s}
function Resolve-Apps {
 $paths=@()
 foreach($p in @(Get-Process clash-verge -ErrorAction SilentlyContinue)){
  try{if($p.Path){$paths+= $p.Path}}catch{}
 }
 foreach($base in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),$env:LOCALAPPDATA)){
  if($base){$paths+= (Join-Path $base 'Clash Verge\clash-verge.exe');$paths+= (Join-Path $base 'Programs\Clash Verge\clash-verge.exe')}
 }
 foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){
  foreach($r in @(Get-ItemProperty $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -like 'Clash Verge*'})){
   if($r.InstallLocation){try{$paths+= (Join-Path $r.InstallLocation 'clash-verge.exe')}catch{}}
  }
 }
 @($paths|Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}|Sort-Object -Unique)
}
function Ask-App{
 if($script:AppPath -and (Test-Path -LiteralPath $script:AppPath -PathType Leaf) -and [IO.Path]::GetFileName($script:AppPath) -eq 'clash-verge.exe'){return $script:AppPath}
 $c=@(Resolve-Apps)
 if($c.Count -eq 1){$script:AppPath=$c[0];return $script:AppPath}
 if($c.Count -gt 1){Say '发现多个安装位置，请明确选择实际使用的 exe：';$c|ForEach-Object {Say $_}}
 $script:AppPath=(Read-Host '请输入 clash-verge.exe 的完整路径').Trim().Trim([char]34)
 if(!$script:AppPath -or !(Test-Path -LiteralPath $script:AppPath -PathType Leaf) -or [IO.Path]::GetFileName($script:AppPath) -ne 'clash-verge.exe'){throw '未找到有效客户端'}
 return $script:AppPath
}
function Script-Run([string]$name,[string[]]$argv){
 $p=Join-Path $PSScriptRoot $name
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p @argv
 Say "退出码：$LASTEXITCODE（0 完成；1 失败/取消；2 部分完成/需人工验证）"
}
function Native-Run([string]$name,[string[]]$argv){
 $p=Join-Path $PSScriptRoot "bin\$name"
 if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw '缺少发布包原生程序，请下载完整 Windows x64 ZIP'}
 & $p @argv
 Say "退出码：$LASTEXITCODE"
}
try{
 if($SelfTest){
  foreach($f in @('Optimize-Clash.ps1','Diagnose-Clash.ps1','Monitor-Clash.ps1','Inspect-Local.ps1','presets\Merge.yaml','presets\Script.js','Start-ClashOptimizer.ps1')){
   if(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $f) -PathType Leaf)){throw "Missing $f"}
  }
  if($RequireBinaries){foreach($f in @('oco-clash-monitor.exe','oco-node-quality.exe')){if(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot "bin\$f") -PathType Leaf)){throw "Missing $f"}}}
  'CLASH_PANEL_SELFTEST_OK';exit 0
 }
 if(!$DataPath){$DataPath=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'}
 do{
  Say '';Say '============================================';Say ' OneClickOptimizer | Clash Verge Rev 控制中心';Say '============================================'
  Say "数据目录：$DataPath";Say "代理端口：$Port"
  Say '1  检查配置（只读）'
  Say '2  应用优化预设（确认、备份、版本门控）'
  Say '3  恢复 OCO 备份'
  Say '4  Rust 网络与硬件监视'
  Say '5  Rust Lite 监视（无磁盘/GPU）'
  Say '6  当前网络诊断（6 次 HTTPS）'
  Say '7  独立节点质量初筛（最多 6 个节点）'
  Say '8  IPPure 单次出口信息（确认后发送）'
  Say '9  旧硬件窗口（兼容备用）'
  Say 'D  修改数据目录（仅本次会话）'
  Say 'P  修改代理端口（仅本次会话）'
  Say 'A  修改客户端路径（仅本次会话）'
  Say '0  退出'
  $choice=(Read-Host '请选择').Trim()
  try{
   switch($choice){
    '1' {Script-Run 'Inspect-Local.ps1' @('-Port',[string]$Port);Script-Run 'Optimize-Clash.ps1' @('-CheckOnly','-DataPath',$DataPath)}
    '2' {Say '仅适用于已验证的 2.5.10 / 1.19.33 中国大陆导向预设。已有自定义配置拒绝覆盖。请正常关闭 Clash。';$a=Ask-App;Script-Run 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-AppPath',$a)}
    '3' {Script-Run 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-RestorePrompt')}
    '4' {Native-Run 'oco-clash-monitor.exe' @('--gui')}
    '5' {Native-Run 'oco-clash-monitor.exe' @('--gui','--lite')}
    '6' {if((Read-Host '通过当前规则路径发送 6 次 HTTPS 请求？[Y/N]') -match '^[Yy]$'){Script-Run 'Diagnose-Clash.ps1' @('-Port',[string]$Port,'-Rounds','2')}}
    '7' {$a=Ask-App;$core=Join-Path (Split-Path -Parent $a) 'verge-mihomo.exe';Native-Run 'oco-node-quality.exe' @('--scan',(Join-Path $DataPath 'clash-verge.yaml'),$core)}
    '8' {Script-Run 'Diagnose-Clash.ps1' @('-Port',[string]$Port,'-ExitPrompt')}
    '9' {Script-Run 'Monitor-Clash.ps1' @()}
    'D' {$p=(Read-Host '完整数据目录').Trim().Trim([char]34);if($p -and (Test-Path -LiteralPath (Join-Path $p 'verge.yaml') -PathType Leaf)){$DataPath=[IO.Path]::GetFullPath($p)}else{Say '目录无效，未修改。'}}
    'P' {$v=0;if([int]::TryParse((Read-Host '端口 1-65535'),[ref]$v) -and $v -ge 1 -and $v -le 65535){$Port=$v}else{Say '端口无效，未修改。'}}
    'A' {$script:AppPath='';$null=Ask-App}
    '0' {}
    default {Say '无效选择。'}
   }
  }catch{Write-Warning $_.Exception.Message}
 }while($choice -ne '0')
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
