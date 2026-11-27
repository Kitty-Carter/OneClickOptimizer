[CmdletBinding()]
param([switch]$SelfTest,[switch]$DiscoverOnly,[ValidateSet("Menu","Check","Optimize","Restore")][string]$Action="Menu",[string]$AppPath,[string]$DataPath,[ValidateRange(1,65535)][int]$Port=7897)
$ErrorActionPreference='Stop'
$explicitPort=$PSBoundParameters.ContainsKey('Port')
function Say([string]$s){Write-Host $s}
function Valid-App([string]$p){
 if(!$p){return $false}
 try{return ([IO.Path]::GetFileName($p) -ieq 'clash-verge.exe' -and (Test-Path -LiteralPath $p -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $p) 'verge-mihomo.exe') -PathType Leaf))}catch{return $false}
}
function Valid-Data([string]$p){
 if(!$p){return $false}
 try{foreach($n in @('verge.yaml','profiles.yaml','profiles\Merge.yaml','profiles\Script.js')){if(!(Test-Path -LiteralPath (Join-Path $p $n) -PathType Leaf)){return $false}};return $true}catch{return $false}
}
function Extract-Exe([string]$s){
 if(!$s){return}
 $s=[Environment]::ExpandEnvironmentVariables($s.Trim())
 if($s -match '^"([^"]+\.exe)"(?:,.*|\s.*)?$'){return $Matches[1]}
 if($s -match '^(.*?\.exe)(?:,\s*-?\d+|\s.*)?$'){return $Matches[1]}
}
function Find-Apps {
 $paths=New-Object 'System.Collections.Generic.List[string]'
 foreach($p in @(Get-Process clash-verge -ErrorAction SilentlyContinue)){try{if($p.Path){$paths.Add($p.Path)}}catch{}}
 foreach($base in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),$env:LOCALAPPDATA,$env:USERPROFILE)){
  if($base){foreach($sub in @('Clash Verge','Clash Verge Rev','Programs\Clash Verge','Programs\Clash Verge Rev','Downloads\Clash Verge','Desktop\Clash Verge')){$paths.Add((Join-Path $base "$sub\clash-verge.exe"))}}
 }
 foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){
  foreach($r in @(Get-ItemProperty $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -like '*Clash Verge*'})){
   if($r.InstallLocation){try{$paths.Add((Join-Path $r.InstallLocation 'clash-verge.exe'))}catch{}}
   $x=Extract-Exe $r.DisplayIcon;if($x){$paths.Add($x)}
   $x=Extract-Exe $r.UninstallString;if($x){try{$paths.Add((Join-Path (Split-Path -Parent $x) 'clash-verge.exe'))}catch{}}
  }
 }
 foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\clash-verge.exe','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\clash-verge.exe')){
  try{$x=(Get-Item -LiteralPath $key -ErrorAction Stop).GetValue('');if($x){$paths.Add((Extract-Exe $x))}}catch{}
 }
 try{
  $shell=New-Object -ComObject WScript.Shell
  foreach($folder in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'),[Environment]::GetFolderPath('CommonDesktopDirectory'))){
   if($folder -and (Test-Path -LiteralPath $folder)){
    foreach($link in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue|Where-Object {$_.Name -like '*Clash*'}|Select-Object -First 50)){
     try{$x=$shell.CreateShortcut($link.FullName).TargetPath;if($x){$paths.Add($x)}}catch{}
    }
   }
  }
 }catch{}
 foreach($drive in [IO.DriveInfo]::GetDrives()){
  if($drive.DriveType -eq [IO.DriveType]::Fixed -and $drive.IsReady){
   foreach($n in @('Clash Verge','Clash Verge Rev','ClashVerge','Apps\Clash Verge','Software\Clash Verge','Program Files\Clash Verge','Tools\Clash Verge')){$paths.Add((Join-Path $drive.RootDirectory.FullName "$n\clash-verge.exe"))}
  }
 }
 @($paths|Where-Object {Valid-App $_}|ForEach-Object {[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)
}
function Search-Apps([string[]]$roots){
 # Bounded fallback: no network drives, reparse points or system directory traversal.
 $q=New-Object 'System.Collections.Generic.Queue[object]'
 foreach($root in $roots){if($root -and (Test-Path -LiteralPath $root -PathType Container)){$q.Enqueue(@($root,0))}}
 $sw=[Diagnostics.Stopwatch]::StartNew();$seen=0;$found=@()
 while($q.Count -and $seen -lt 3500 -and $sw.Elapsed.TotalSeconds -lt 12){
  $item=$q.Dequeue();$d=[string]$item[0];$depth=[int]$item[1];$seen++
  try{
   if((Get-Item -LiteralPath $d -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
   $p=Join-Path $d 'clash-verge.exe';if(Valid-App $p){$found+=$p;continue}
   if($depth -ge 4){continue}
   foreach($child in Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue){
    if($child.Name -in @('Windows','Windows.old','System Volume Information','$Recycle.Bin','AppData','node_modules','.git','Users','ProgramData','Recovery','WinSxS')){continue}
    if(!($child.Attributes -band [IO.FileAttributes]::ReparsePoint)){$q.Enqueue(@($child.FullName,($depth+1)))}
   }
  }catch{}
 }
 @($found|Sort-Object -Unique)
}
function Choose([string[]]$items,[string]$prompt){
 if($items.Count -eq 1){return $items[0]}
 if($items.Count -gt 1){
  for($i=0;$i -lt $items.Count;$i++){Say ("{0}. {1}" -f ($i+1),$items[$i])}
  $n=0;if([int]::TryParse((Read-Host '选择序号；输入 0 手动指定'),[ref]$n) -and $n -gt 0 -and $n -le $items.Count){return $items[$n-1]}
 }
 (Read-Host $prompt).Trim().Trim([char]34)
}
function Find-Data([string]$app){
 $id='io.github.clash-verge-rev.clash-verge-rev'
 $a=@((Join-Path $env:APPDATA $id),(Join-Path $env:LOCALAPPDATA $id))
 if($app){$parent=Split-Path -Parent $app;$a+=@($parent,(Join-Path $parent 'data'),(Join-Path $parent $id),(Join-Path $parent "data\$id"))}
 @($a|Where-Object {Valid-Data $_}|ForEach-Object {[IO.Path]::GetFullPath($_)}|Sort-Object -Unique)
}
function Locate {
 if(!(Valid-App $script:AppPath)){
  $a=@(Find-Apps)
  if(!$a.Count){
   Say '常规发现未命中，正在有限搜索本地磁盘及下载目录……'
   $roots=@((Join-Path $env:USERPROFILE 'Downloads'),(Join-Path $env:USERPROFILE 'Desktop'))
   $roots+=@([IO.DriveInfo]::GetDrives()|Where-Object {$_.DriveType -eq 'Fixed' -and $_.IsReady}|ForEach-Object {$_.RootDirectory.FullName})
   $a=@(Search-Apps $roots)
  }
  $script:AppPath=Choose $a '请输入已安装 clash-verge.exe 的完整路径（不是安装包）'
 }
 if(!(Valid-App $script:AppPath)){throw '未确认已安装客户端及同目录内核'}
 if(!(Valid-Data $script:DataPath)){$script:DataPath=Choose @(Find-Data $script:AppPath) '请输入实际 Clash 数据目录'}
 if(!(Valid-Data $script:DataPath)){throw '未找到完整数据目录，拒绝猜测写入'}
 $script:AppPath=[IO.Path]::GetFullPath($script:AppPath);$script:DataPath=[IO.Path]::GetFullPath($script:DataPath)
}
function Run-PS([string]$name,[string[]]$argv){
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name) @argv
 Say "退出码：$LASTEXITCODE（请结合实际输出判断）"
}
function Run-Node([string[]]$args1){
 & (Join-Path $PSScriptRoot 'bin\oco-node-quality.exe') @args1
 Say "节点检测退出码：$LASTEXITCODE"
}
try{
 if($SelfTest){
  $tmp=Join-Path ([IO.Path]::GetTempPath()) ('OCO path test '+[guid]::NewGuid().ToString('N'))
  try{
   $a=Join-Path $tmp 'custom apps\level\Clash';$d=Join-Path $tmp 'custom data'
   New-Item -ItemType Directory -Path $a,(Join-Path $d 'profiles') -Force|Out-Null
   foreach($n in @('clash-verge.exe','verge-mihomo.exe')){[IO.File]::WriteAllText((Join-Path $a $n),'fixture')}
   foreach($n in @('verge.yaml','profiles.yaml','profiles\Merge.yaml','profiles\Script.js')){[IO.File]::WriteAllText((Join-Path $d $n),'fixture')}
   $expected=Join-Path $a 'clash-verge.exe'
   if(!(Valid-App $expected) -or !(Valid-Data $d) -or (@(Search-Apps @($tmp)) -notcontains $expected)){throw 'Custom-path fixture failed'}
   if((Extract-Exe '"D:\Custom Apps\Clash\clash-verge.exe",0') -ne 'D:\Custom Apps\Clash\clash-verge.exe'){throw 'Registry parsing failed'}
   Remove-Item -LiteralPath (Join-Path $a 'verge-mihomo.exe')
   if(Valid-App $expected){throw 'Missing core fixture failed'}
   'DISCOVERY_SELFTEST_OK';exit 0
  }finally{Remove-Item -LiteralPath $tmp -Recurse -Force}
 }
 Locate
 if(!$explicitPort){
  $runtime=Join-Path $DataPath 'clash-verge.yaml'
  if(Test-Path -LiteralPath $runtime -PathType Leaf){
   $matchesPort=@(Get-Content -LiteralPath $runtime -Encoding UTF8|Where-Object {$_ -match '^mixed-port:\s*[0-9]+\s*(?:#.*)?$'})
   if($matchesPort.Count -eq 1 -and $matchesPort[0] -match '^mixed-port:\s*([0-9]+)'){
    $n=0;if([int]::TryParse($Matches[1],[ref]$n) -and $n -ge 1 -and $n -le 65535){$Port=$n}
   }
  }
 }
 Say "客户端：$AppPath";Say "数据目录：$DataPath";Say "混合代理端口：$Port"
 if($DiscoverOnly){exit 0}
 if($Action -ne 'Menu'){
  $argv=@('-DataPath',$DataPath,'-AppPath',$AppPath)
  if($Action -eq 'Check'){$argv+='-CheckOnly'}
  if($Action -eq 'Restore'){$argv+='-RestorePrompt'}
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Optimize-Clash.ps1') @argv
  exit $LASTEXITCODE
 }
 Say '首次建议使用 1 检查；已有优化预设一致时不会重复写入。'
 do{
  Say '';Say '========== Clash Verge Rev 一键优化 · 精简版 =========='
  Say '1 检查配置 / 2 安全应用优化 / 3 恢复原配置'
  Say '4 独立节点检测（分批，可选深入下载及 ChatGPT HTTP 测试）'
  Say '5 当前网络诊断 / 6 IPPure 单次出口检查 / 7 本地代理状态'
  Say '8 自定义配置安全补全（仅补3个缺失字段） / 9 实测策略组候选'
  Say '10 安全暂存已验证策略组（先退出 Clash；保留 AI 出口）'
  Say 'A 重新选择客户端与数据目录 / P 自定义代理端口 / 0 退出'
  $choice=(Read-Host '请选择').Trim()
  try{
   switch($choice){
    '1'{Run-PS 'Optimize-Clash.ps1' @('-CheckOnly','-DataPath',$DataPath)}
    '2'{Say '先正常退出 Clash；工具不会强制退出或覆盖自定义扩展。';Run-PS 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-AppPath',$AppPath)}
    '3'{Run-PS 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-RestorePrompt')}
    '4'{
     $core=Join-Path (Split-Path -Parent $AppPath) 'verge-mihomo.exe'
     $cfg=Join-Path $DataPath 'clash-verge.yaml'
     Run-Node @('--list',$cfg,$core)
     $batch=0
     $selection=(Read-Host '输入批次编号（每批最多6个）；ALL 一次初筛全部（最多120个）；0取消').Trim()
     if($selection -ieq 'ALL'){Run-Node @('--scan',$cfg,$core,'--all')}
     elseif([int]::TryParse($selection,[ref]$batch) -and $batch -gt 0){
      $args1=@('--scan',$cfg,$core,'--batch',[string]$batch)
      if((Read-Host '增加每节点1MiB下载及ChatGPT HTTP测试？[Y/N]') -match '^[Yy]$'){$args1+='--deep'}
      Run-Node $args1
     }
    }
    '5'{if((Read-Host '发送6次HTTPS请求？[Y/N]') -match '^[Yy]$'){Run-PS 'Diagnose-Clash.ps1' @('-Port',[string]$Port,'-Rounds','2')}}
    '6'{Run-PS 'Diagnose-Clash.ps1' @('-Port',[string]$Port,'-ExitPrompt')}
    '7'{Run-PS 'Inspect-Local.ps1' @('-Port',[string]$Port)}
    '8'{Run-PS 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-AppPath',$AppPath,'-AddMissing')}
    '9'{
     $core=Join-Path (Split-Path -Parent $AppPath) 'verge-mihomo.exe'
     $cfg=Join-Path $DataPath 'clash-verge.yaml'
     Run-Node @('--list',$cfg,$core)
     $n=0;$choice9=(Read-Host '输入 AUTO 全量初筛后深测前6；或批次号（3次204+2次1MiB）；0取消').Trim()
     $auto=($choice9 -ieq 'AUTO')
     if($auto -or ([int]::TryParse($choice9,[ref]$n) -and $n -gt 0)){
      $folder=Join-Path $env:LOCALAPPDATA ('OCO-Policy-'+[guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $folder|Out-Null
      try{
       $acl=New-Object Security.AccessControl.DirectorySecurity
       $acl.SetAccessRuleProtection($true,$false)
       $me=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
       foreach($sid in @($me,'S-1-5-18','S-1-5-32-544')){
        $id=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
       }
       Set-Acl -LiteralPath $folder -AclObject $acl
       $file=Join-Path $folder 'policy-groups.yaml'
       $argv=@('--scan',$cfg,$core,'--recommend',$file);if($auto){$argv+='--auto'}else{$argv+=@('--batch',[string]$n)}
       Run-Node $argv
       if(Test-Path -LiteralPath $file -PathType Leaf){Say "候选片段（不包含认证参数）：$file";Say '候选需在1小时内使用菜单10暂存；不可直接覆盖全局 Merge.yaml。未修改正式策略组。'}
       else{Remove-Item -LiteralPath $folder -Force}
      }catch{Write-Warning '未完成策略组候选生成';throw}
     }
    }
    '10'{
     $cfg=Join-Path $DataPath 'clash-verge.yaml'
     Say '候选可追加到以下非 AI 的现有手动选择组：'
     Run-Node @('--parents',$cfg)
     $parent=(Read-Host '输入现有组的准确名称（不能选 AI 固定出口）').Trim()
     $proposal=(Read-Host '输入菜单9生成的 policy-groups.yaml 完整路径').Trim().Trim([char]34)
     if($parent -and $proposal){Run-PS 'Optimize-Clash.ps1' @('-DataPath',$DataPath,'-AppPath',$AppPath,'-PolicyFrom',$proposal,'-PolicyParent',$parent)}
    }
    'A'{$oldApp=$script:AppPath;$oldData=$script:DataPath;$script:AppPath=(Read-Host '请输入实际 clash-verge.exe 完整路径').Trim().Trim([char]34);$script:DataPath=(Read-Host '请输入实际数据目录').Trim().Trim([char]34);if(!(Valid-App $script:AppPath) -or !(Valid-Data $script:DataPath)){$script:AppPath=$oldApp;$script:DataPath=$oldData;throw '路径无效，保留原选择'};Locate;Say "客户端：$AppPath";Say "数据目录：$DataPath";Say "若端口不同，请使用 P 明确设置。"}
    'P'{$v=0;if([int]::TryParse((Read-Host '本地混合端口'),[ref]$v) -and $v -ge 1 -and $v -le 65535){$Port=$v}else{Say '端口无效'}}
    '0'{}
    default{Say '无效选择'}
   }
  }catch{Write-Warning $_.Exception.Message}
 }while($choice -ne '0')
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
