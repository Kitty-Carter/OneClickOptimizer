[CmdletBinding()]
param([switch]$CheckOnly,[switch]$SelfTest,[string]$DataPath,[string]$BackupRoot,[string]$RestoreFrom,[switch]$RestorePrompt,[string]$AppPath,[switch]$AddMissing,[string]$PolicyFrom,[string]$PolicyParent)
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
function SamePreset([byte[]]$a,[byte[]]$b){
 if((Hash $a) -eq (Hash $b)){return $true}
 # Only normalize BOM and CRLF; strict UTF8 avoids replacing invalid bytes.
 try{
  $strict=New-Object Text.UTF8Encoding($false,$true)
  $x=$strict.GetString($a).TrimStart([char]0xFEFF).Replace([string][char]13+[char]10,[string][char]10)
  $y=$strict.GetString($b).TrimStart([char]0xFEFF).Replace([string][char]13+[char]10,[string][char]10)
  return ($x -ceq $y)
 }catch{return $false}
}
function PrivateDir([string]$p){
 New-Item -ItemType Directory -Path $p -ErrorAction Stop|Out-Null
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $me=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 foreach($sid in @($me,'S-1-5-18','S-1-5-32-544')){
  $id=New-Object Security.Principal.SecurityIdentifier($sid)
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
 }
 Set-Acl -LiteralPath $p -AclObject $acl
 $actual=Get-Acl -LiteralPath $p
 if(!$actual.AreAccessRulesProtected){throw 'Private ACL verification failed'}
 foreach($r in $actual.Access){
  $sid=$r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -notin @($me,'S-1-5-18','S-1-5-32-544')){throw 'Unexpected ACL identity'}
 }
}
function SafeMerge([byte[]]$old){
 $t=Join-Path $env:LOCALAPPDATA ('OCO-Merge-'+[guid]::NewGuid().ToString('N'))
 try{
  PrivateDir $t
  $a=Join-Path $t 'input.yaml';$b=Join-Path $t 'candidate.yaml'
  [IO.File]::WriteAllBytes($a,$old)
  $exe=Join-Path $PSScriptRoot 'bin\oco-node-quality.exe'
  & $exe --merge-safe $a $b | Out-Host
  $rc=$LASTEXITCODE
  if($rc -eq 3){return ,$old}
  if($rc -ne 0 -or !(Test-Path -LiteralPath $b -PathType Leaf)){throw 'Structured merge refused; no changes'}
  return ,(ReadBytes $b)
 }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
}
function SafePolicy([string]$data,[string]$app,[string]$proposal,[string]$parent){
 if(!$app -or !$parent){throw 'Policy needs confirmed client and explicit existing non-AI parent'}
 $runtime=Join-Path $data 'clash-verge.yaml'
 $core=Join-Path (Split-Path -Parent $app) 'verge-mihomo.exe'
 $t=Join-Path $env:LOCALAPPDATA ('OCO-PolicyStage-'+[guid]::NewGuid().ToString('N'))
 try{
  PrivateDir $t
  $out=Join-Path $t 'candidate.js'
  & (Join-Path $PSScriptRoot 'bin\oco-node-quality.exe') --compose-policy $runtime $core $proposal $parent $out | Out-Host
  if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $out -PathType Leaf)){throw 'Policy validation refused; no write'}
  return ,(ReadBytes $out)
 }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
}
function Plan([string]$dir,[switch]$MissingOnly){
 foreach($n in $files){
  $p=Join-Path $dir $n
  if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing native extension: $n"}
  if((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point not supported'}
  $old=ReadBytes $p;$new=ReadBytes (Join-Path $PSScriptRoot "presets\$n")
  if($MissingOnly){
   $new=if($n -eq 'Merge.yaml'){SafeMerge $old}else{,$old}
   $new=[byte[]]$new
   $state=if((Hash $old) -eq (Hash $new)){'same'}else{'ready'}
  }else{$state=if(SamePreset $old $new){$new=$old;'same'}elseif(IsDefault $n $old){'ready'}else{'custom'}}

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
function Apply($plan,[string]$root,[switch]$Fixture,[switch]$InjectFailure){
 if($InjectFailure -and !$Fixture){throw "Fault injection restricted to fixture"}
 if(@($plan|Where-Object State -eq 'custom').Count){throw 'Custom extensions detected. Refusing to overwrite.'}
 $change=@($plan|Where-Object State -eq 'ready')
 if(!$change.Count){return}
 if(!$Fixture -and (Get-Process clash-verge,verge-mihomo -ErrorAction SilentlyContinue)){throw 'Close Clash normally before applying; no automatic shutdown.'}
 if(!$root){throw 'Backup root required'}
 $b=Join-Path $root ('clash-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
 if(!(Test-Path -LiteralPath $root -PathType Container)){New-Item -ItemType Directory -Path $root -Force|Out-Null}
 PrivateDir $b
 foreach($x in $plan){
  $bp=Join-Path $b $x.Name
  [IO.File]::WriteAllBytes($bp,$x.Old)
  if((Hash (ReadBytes $bp)) -ne (Hash $x.Old)){throw 'Backup readback failed before write'}
 }
 $manifest=@($plan|ForEach-Object{[pscustomobject]@{name=$_.Name;before=(Hash $_.Old);after=(Hash $_.New)}})
 [IO.File]::WriteAllText((Join-Path $b 'manifest.json'),(ConvertTo-Json -InputObject $manifest -Depth 3),$utf8)
 # Check the complete backup manifest and both source files before mutation.
 $backManifest=ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $b 'manifest.json') -Raw -Encoding UTF8)
 foreach($x in $plan){
  $r=@($backManifest|Where-Object name -ceq $x.Name)
  if($r.Count -ne 1 -or $r[0].before -ne (Hash $x.Old) -or $r[0].after -ne (Hash $x.New)){throw 'Backup manifest readback failed'}
  if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit before transaction'}
 }
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
    if($InjectFailure -and $done.Count -eq 1){throw 'Injected fixture failure after first write'}
   }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
  }
  foreach($x in $plan){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw "Final transaction readback failed"}}
 }catch{
  foreach($x in $done){
   if((Hash (ReadBytes $x.Path)) -eq (Hash $x.New)){
    $tmp=$x.Path+'.restore-'+[guid]::NewGuid().ToString('N')
    try{[IO.File]::WriteAllBytes($tmp,$x.Old);[IO.File]::Replace($tmp,$x.Path,($tmp+".swap")); Remove-Item -LiteralPath ($tmp+".swap") -Force; if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw "Rollback readback failed: $($x.Name); recovery backup: $b"}}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
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
   $injected=$false
   try{$null=Apply $p (Join-Path $t 'backup') -Fixture -InjectFailure}catch{if($_.Exception.Message -match 'Injected fixture failure'){$injected=$true}else{throw}}
   if(!$injected){throw 'Fault injection did not fire'}
   foreach($x in $p){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Partial write rollback failed'}}
   Write-Host 'CLASH_PARTIAL_WRITE_ROLLBACK_OK'
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
   foreach($n in $files){
    $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot "presets\$n")).Replace([string][char]13+[char]10,[string][char]10).Replace([string][char]10,[string][char]13+[char]10)
    [IO.File]::WriteAllText((Join-Path $t $n),$text,(New-Object Text.UTF8Encoding($true)))
   }
   $p=@(Plan $t);if(@($p|Where-Object State -eq 'same').Count -ne 2){throw 'BOM/CRLF equivalence failed'}
   foreach($x in $p){if((Hash $x.Old) -ne (Hash $x.New)){throw 'Equivalent file would be rewritten'}}
   [IO.File]::WriteAllText((Join-Path $t 'Merge.yaml'),"dns: {enable: false}"+[char]10+"profile: {store-selected: false}"+[char]10,$utf8)
   [IO.File]::WriteAllText((Join-Path $t 'Script.js'),'function main(c){c.mode="direct";return c;}',$utf8)
   $p=@(Plan $t -MissingOnly)
   if($p[0].State -ne 'ready' -or $p[1].State -ne 'same'){throw 'missing-only planning failed'}
   $scriptHash=Hash $p[1].Old
   $b2=Apply $p (Join-Path $t 'backup') -Fixture
   if((Hash (ReadBytes (Join-Path $t 'Script.js'))) -ne $scriptHash){throw 'Custom JS changed'}
   $again=@(Plan $t -MissingOnly)
   if(@($again|Where-Object State -ne 'same').Count){throw 'Missing-only idempotence failed'}
   $null=Apply @(RestorePlan $t $b2) (Join-Path $t 'backup') -Fixture
   if((Hash (ReadBytes (Join-Path $t 'Merge.yaml'))) -ne (Hash $p[0].Old)){throw 'Missing-only restore failed'}
   Write-Host 'CLASH_MISSING_ONLY_SELF_TEST_OK'
   Write-Host 'CLASH_SELF_TEST_OK';exit 0
  }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
 }
 if(($AddMissing -and ($RestorePrompt -or $RestoreFrom -or $PolicyFrom)) -or ($PolicyFrom -and ($RestorePrompt -or $RestoreFrom))){throw 'Choose one action'}
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
 if($PolicyFrom){
  $p=@(Plan $dir)
  $scriptRow=@($p|Where-Object Name -eq 'Script.js')[0]
  if($scriptRow.State -ne 'same'){throw 'Policy staging requires exact original v2.3 Script.js; restore baseline first'}
  $mergeRow=@($p|Where-Object Name -eq 'Merge.yaml')[0]
  $mergeRow.New=$mergeRow.Old;$mergeRow.State='same'
  $runtimePath=Join-Path $DataPath 'clash-verge.yaml'
  $runtimeHash=Hash (ReadBytes $runtimePath)
  $scriptRow.New=[byte[]](SafePolicy $DataPath $AppPath $PolicyFrom $PolicyParent)
  if((Hash (ReadBytes $runtimePath)) -ne $runtimeHash){throw 'Runtime changed during policy preparation'}
  $scriptRow.State=if((Hash $scriptRow.New) -eq (Hash $scriptRow.Old)){'same'}else{'ready'}
 }else{$p=@(Plan $dir -MissingOnly:$AddMissing)}
 $p|Select-Object Name,State|Format-Table
 if(@($p|Where-Object State -eq 'custom').Count){Write-Warning 'Custom extensions preserved. Review guide and integrate manually.';exit 2}
 if($CheckOnly){exit 0}
 if(@($p|Where-Object State -eq 'ready').Count -eq 0){Write-Host 'Preset files already match; live behavior not checked.';exit 0}
 if($PolicyFrom){
  Write-Host 'Append measured candidates to the explicitly chosen existing select group. No route or AI selection is changed. Candidate expires on future reloads after 24h; close Clash normally first.'
  if((Read-Host 'Stage validated policy extension? [Y/N]') -notmatch '^[Yy]$'){exit 1}
 }elseif($AddMissing){
  Write-Host 'Add only absent tcp-concurrent and profile persistence keys. Explicit values and Script.js preserved. YAML comments/format may change. Close Clash manually first.'
  if((Read-Host 'Apply conservative structured merge? [Y/N]') -notmatch '^[Yy]$'){exit 1}
 }else{
  Write-Host 'China-oriented DNS and OpenAI routing preset for Clash Verge Rev 2.5.10 / Mihomo 1.19.33. Review guide. Close Clash manually first.'
  if((Read-Host 'Apply only to default extensions? [Y/N]') -notmatch '^[Yy]$'){exit 1}
 }

 # Restrict automatic application to explicit verified version. Do not guess a core path.
 $exe=if($AppPath){$AppPath}else{Read-Host 'Full path to installed clash-verge.exe'}
 if(!(Test-Path -LiteralPath $exe -PathType Leaf) -or [IO.Path]::GetFileName($exe) -ne 'clash-verge.exe'){throw 'App executable not confirmed'}
 $version=(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
 if($version -notmatch '^2\.5\.10(?:\.0)?$'){Write-Warning 'Version not validated; manual integration only.';exit 2}
 $core=Join-Path (Split-Path -Parent $exe) 'verge-mihomo.exe'
 if(!(Test-Path -LiteralPath $core -PathType Leaf)){Write-Warning 'Bundled core not found; no write.';exit 2}
 $coreVersion=& $core -v 2>&1 | Out-String
 if($LASTEXITCODE -ne 0 -or $coreVersion -notmatch '(?m)\bMihomo\s+Meta\s+v1\.19\.33(?:\s|$)'){Write-Warning 'Core version not validated; no write.';exit 2}
 if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
 if($PolicyFrom){if((Hash (ReadBytes $runtimePath)) -ne $runtimeHash){throw 'Runtime changed before transaction; retest'};if((Get-Process clash-verge,verge-mihomo -ErrorAction SilentlyContinue)){throw 'Close Clash normally before applying'}; $fresh=[byte[]](SafePolicy $DataPath $AppPath $PolicyFrom $PolicyParent);if((Hash $fresh) -ne (Hash $scriptRow.New)){throw 'Policy changed during final validation'}}
 $null=Apply $p $BackupRoot
 Write-Host 'Start Clash normally, reactivate the subscription, verify network and AI routing. Live activation is not automatically verified.'
 exit 2
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
