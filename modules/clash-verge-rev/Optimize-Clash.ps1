[CmdletBinding()]
param([switch]$CheckOnly,[switch]$SelfTest,[string]$DataPath,[string]$BackupRoot,[string]$RestoreFrom,[switch]$RestorePrompt)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
$files=@('Merge.yaml','Script.js')
function Hash([byte[]]$b){$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash($b)).Replace('-','')}finally{$sha.Dispose()}}
function ReadBytes([string]$p){[IO.File]::ReadAllBytes($p)}
function IsDefault([string]$n,[byte[]]$b){
 $t=$utf8.GetString($b).TrimStart([char]0xFEFF)
 if($n -eq 'Merge.yaml'){return (($t -split '\r?\n' | Where-Object {$_ -notmatch '^\s*(#.*)?$'}) -join '').Trim() -in @('','{}')}
 $t=($t -split '\r?\n' | Where-Object {$_ -notmatch '^\s*(//.*)?$'}) -join ' '
 return ($t.Trim() -eq '' -or $t.Trim() -match '^function\s+main\s*\(\s*config\s*(,\s*profileName\s*)?\)\s*\{\s*return\s+config\s*;?\s*\}\s*;?$')
}
function Plan([string]$dir){
 foreach($n in $files){
  $p=Join-Path $dir $n
  if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing native extension: $n"}
  if((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point not supported'}
  $old=ReadBytes $p;$new=ReadBytes (Join-Path $PSScriptRoot "presets\$n")
  $state=if((Hash $old) -eq (Hash $new)){'same'}elseif(IsDefault $n $old){'ready'}else{'custom'}
  [pscustomobject]@{Name=$n;Path=$p;Old=$old;New=$new;State=$state}
 }
}
function RestorePlan([string]$dir,[string]$backup){
 if(!(Test-Path -LiteralPath $backup -PathType Container)){throw 'Backup directory not found'}
 if((Get-Item -LiteralPath $backup).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Backup reparse point not supported'}
 $manifestPath=Join-Path $backup 'manifest.json'
 if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Backup manifest missing'}
 if((Get-Item -LiteralPath $manifestPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Manifest reparse point not supported'}
 $manifest=ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8); $manifest=@($manifest)
 if($manifest.Count -ne $files.Count){throw 'Unexpected manifest'}
 foreach($n in $files){
  $row=@($manifest|Where-Object name -ceq $n)
  if($row.Count -ne 1 -or $row[0].before -notmatch '^[A-Fa-f0-9]{64}$' -or $row[0].after -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Invalid backup record'}
  $p=Join-Path $dir $n;$b=Join-Path $backup $n
  foreach($f in @($p,$b)){
   if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw 'Restore input missing'}
   if((Get-Item -LiteralPath $f).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Restore reparse point not supported'}
  }
  $old=ReadBytes $p;$new=ReadBytes $b
  if((Hash $new) -ne $row[0].before){throw 'Backup hash mismatch'}
  $state=if((Hash $old) -eq $row[0].before){'same'}elseif((Hash $old) -eq $row[0].after){'ready'}else{'custom'}
  [pscustomobject]@{Name=$n;Path=$p;Old=$old;New=$new;State=$state}
 }
}
function Apply($plan,[string]$root,[switch]$Fixture){
 if(@($plan|Where-Object State -eq 'custom').Count){throw 'Custom extensions detected. Refusing to overwrite.'}
 $change=@($plan|Where-Object State -eq 'ready')
 if(!$change.Count){return}
 if(!$Fixture -and (Get-Process clash-verge,verge-mihomo -ErrorAction SilentlyContinue)){throw 'Close Clash normally before applying; no automatic shutdown.'}
 if(!$root){throw 'Backup root required'}
 $b=Join-Path $root ('clash-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $b -Force|Out-Null
 foreach($x in $plan){[IO.File]::WriteAllBytes((Join-Path $b $x.Name),$x.Old)}
 $manifest=@($plan|ForEach-Object{[pscustomobject]@{name=$_.Name;before=(Hash $_.Old);after=(Hash $_.New)}})
 [IO.File]::WriteAllText((Join-Path $b 'manifest.json'),(ConvertTo-Json -InputObject $manifest -Depth 3),$utf8)
 $done=@()
 try{
  foreach($x in $change){
   if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit detected'}
   $tmp=$x.Path+'.oco-'+[guid]::NewGuid().ToString('N')
   try{
    [IO.File]::WriteAllBytes($tmp,$x.New)
    [IO.File]::Replace($tmp,$x.Path,($tmp+".swap"))
    $done+=,$x
    Remove-Item -LiteralPath ($tmp+".swap") -Force
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw 'Readback failed'}
   }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
  }
 }catch{
  foreach($x in $done){
   if((Hash (ReadBytes $x.Path)) -eq (Hash $x.New)){
    $tmp=$x.Path+'.restore-'+[guid]::NewGuid().ToString('N')
    try{[IO.File]::WriteAllBytes($tmp,$x.Old);[IO.File]::Replace($tmp,$x.Path,($tmp+".swap")); Remove-Item -LiteralPath ($tmp+".swap") -Force}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
   }
  }
  Write-Host "Recovery backup: $b";throw
 }
 Write-Host "Staged extensions; backup: $b"
 return $b
}
try{
 if($SelfTest){
  $t=Join-Path ([IO.Path]::GetTempPath()) ('oco clash fixture '+[guid]::NewGuid())
  try{
   New-Item -ItemType Directory -Path $t|Out-Null
   [IO.File]::WriteAllText((Join-Path $t 'Merge.yaml'),'# default',$utf8)
   [IO.File]::WriteAllText((Join-Path $t 'Script.js'),'function main(config) { return config; }',$utf8)
   $p=@(Plan $t);if(@($p|Where-Object State -eq 'ready').Count -ne 2){throw 'plan failed'}
   $backup=Apply $p (Join-Path $t 'backup') -Fixture
   $restore=@(RestorePlan $t $backup)
   if(@($restore|Where-Object State -eq 'ready').Count -ne 2){throw 'restore plan failed'}
   $null=Apply $restore (Join-Path $t 'backup') -Fixture
   if([IO.File]::ReadAllText((Join-Path $t 'Merge.yaml')) -ne '# default' -or [IO.File]::ReadAllText((Join-Path $t 'Script.js')) -ne 'function main(config) { return config; }'){throw 'restore readback failed'}
   $p=@(Plan $t)
   $null=Apply $p (Join-Path $t 'backup') -Fixture
   $bp=Join-Path $backup 'Merge.yaml';$original=ReadBytes $bp;[IO.File]::WriteAllText($bp,'tampered',$utf8)
   $refused=$false;try{$null=@(RestorePlan $t $backup)}catch{$refused=$true};if(!$refused){throw 'tampered backup accepted'}
   [IO.File]::WriteAllBytes($bp,$original)
   $p=@(Plan $t);if(@($p|Where-Object State -eq 'same').Count -ne 2){throw 'idempotence failed'}
   [IO.File]::WriteAllText((Join-Path $t 'Script.js'),'function main(config){config.mode="direct";return config;}',$utf8)
   $p=@(Plan $t);if(@($p|Where-Object State -eq 'custom').Count -ne 1){throw 'custom refusal failed'}
   $r=@(RestorePlan $t $backup);if(@($r|Where-Object State -eq 'custom').Count -ne 1){throw 'restore concurrent edit not detected'}
   $refused=$false;try{$null=Apply $r (Join-Path $t 'backup') -Fixture}catch{$refused=$true};if(!$refused){throw 'restore overwrote later edit'}
   $refused=$false;try{Apply $p (Join-Path $t 'backup') -Fixture}catch{$refused=$true};if(!$refused){throw 'custom overwritten'}
   Write-Host 'CLASH_SELF_TEST_OK';exit 0
  }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
 }
 if($RestorePrompt){
  if($RestoreFrom){throw 'Choose only one restore input'}
  $RestoreFrom=(Read-Host 'Enter full OCO backup directory path').Trim().Trim([char]34)
  if(!$RestoreFrom){exit 1}
 }
 if(!$DataPath){$DataPath=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'}
 $DataPath=[IO.Path]::GetFullPath($DataPath)
 if(!(Test-Path -LiteralPath (Join-Path $DataPath 'verge.yaml') -PathType Leaf)){throw 'Clash data directory not confirmed; use -DataPath explicitly.'}
 $dir=Join-Path $DataPath 'profiles'
 if((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Profiles reparse point not supported'}
 if($RestoreFrom){
  $p=@(RestorePlan $dir ([IO.Path]::GetFullPath($RestoreFrom)))
  $p|Select-Object Name,State|Format-Table
  if(@($p|Where-Object State -eq 'custom').Count){Write-Warning 'Later edits detected; restore refused.';exit 2}
  if($CheckOnly){exit 0}
  if(@($p|Where-Object State -eq 'ready').Count -eq 0){Write-Host 'Original bytes already present.';exit 0}
  if((Read-Host 'Restore these two extensions only? [Y/N]') -notmatch '^[Yy]$'){exit 1}
  if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
  $null=Apply $p $BackupRoot
  Write-Host 'Original bytes restored. Start Clash and reactivate subscription; verify live network.'
  exit 2
 }
 $p=@(Plan $dir)
 $p|Select-Object Name,State|Format-Table
 if(@($p|Where-Object State -eq 'custom').Count){Write-Warning 'Custom extensions preserved. Review guide and integrate manually.';exit 2}
 if($CheckOnly){exit 0}
 if(@($p|Where-Object State -eq 'ready').Count -eq 0){Write-Host 'Preset files already match; live behavior not checked.';exit 0}
 Write-Host 'China-oriented DNS and OpenAI routing preset for Clash Verge Rev 2.5.10 / Mihomo 1.19.33. Review guide. Close Clash manually first.'
 if((Read-Host 'Apply only to default extensions? [Y/N]') -notmatch '^[Yy]$'){exit 1}
 # Restrict automatic application to explicit verified version. Do not guess a core path.
 $exe=Read-Host 'Full path to installed clash-verge.exe'
 if(!(Test-Path -LiteralPath $exe -PathType Leaf) -or [IO.Path]::GetFileName($exe) -ne 'clash-verge.exe'){throw 'App executable not confirmed'}
 $version=(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
 if($version -notmatch '^2\.5\.10(?:\.0)?$'){Write-Warning 'Version not validated; manual integration only.';exit 2}
 $core=Join-Path (Split-Path -Parent $exe) 'verge-mihomo.exe'
 if(!(Test-Path -LiteralPath $core -PathType Leaf)){Write-Warning 'Bundled core not found; no write.';exit 2}
 $coreVersion=& $core -v 2>&1 | Out-String
 if($LASTEXITCODE -ne 0 -or $coreVersion -notmatch '(?m)\bMihomo\s+Meta\s+v1\.19\.33(?:\s|$)'){Write-Warning 'Core version not validated; no write.';exit 2}
 if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
 $null=Apply $p $BackupRoot
 Write-Host 'Start Clash normally, reactivate the subscription, verify network and AI routing. Live activation is not automatically verified.'
 exit 2
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
