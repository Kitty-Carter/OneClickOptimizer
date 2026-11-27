[CmdletBinding()]
param([switch]$CheckOnly,[switch]$SelfTest,[string]$DataPath,[string]$BackupRoot,[string]$RestoreFrom,[switch]$RestorePrompt,[string]$AppPath,[switch]$AddMissing,[string]$PolicyFrom,[string]$PolicyParent,[switch]$Verify,[switch]$RecoveryList,[switch]$ConservativeAuto,[switch]$AllowExperimentalPolicy,[switch]$FixtureCrash,[string]$FixturePath,[ValidateSet('First','Last','Before','RestoreFirst')][string]$FixturePhase='First')
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
$files=@('Merge.yaml','Script.js')
function Hash([byte[]]$b){$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash($b)).Replace('-','')}finally{$sha.Dispose()}}
function ReadBytes([string]$p){
 if((Get-Item -LiteralPath $p -ErrorAction Stop).Length -gt 8MB){throw 'Input exceeds 8 MiB; no write'}
 $b=[IO.File]::ReadAllBytes($p)
 if($b.Length -gt 8MB){throw 'Input grew beyond 8 MiB; no write'}
 return ,$b
}
function IsDefault([string]$n,[byte[]]$b){
 try{$t=(New-Object Text.UTF8Encoding($false,$true)).GetString($b).TrimStart([char]0xFEFF)}catch{return $false}
 if($n -eq 'Merge.yaml'){return (($t -split '\r?\n' | Where-Object {$_ -notmatch '^\s*(#.*)?$'}) -join '').Trim() -in @('','{}')}
 $t=($t -split '\r?\n' | Where-Object {$_ -notmatch '^\s*(//.*)?$'}) -join ' '
 return ($t.Trim() -eq '' -or $t.Trim() -cmatch '^function\s+main\s*\(\s*config\s*(,\s*profileName\s*)?\)\s*\{\s*return\s+config\s*;?\s*\}\s*;?$')
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
  if(IsDefault 'Merge.yaml' $old){[IO.File]::WriteAllText($a,'{}',$utf8)}else{[IO.File]::WriteAllBytes($a,$old)}
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
# Persistent state records are advisory; recovery always verifies actual original/new hashes.
function Write-AtomicText([string]$p,[string]$text){
 $tmp=$p+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{
  $bytes=$utf8.GetBytes($text)
  $f=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
  if(Test-Path -LiteralPath $p){[IO.File]::Replace($tmp,$p,($tmp+".swap"));Remove-Item -LiteralPath ($tmp+".swap") -Force}else{[IO.File]::Move($tmp,$p)}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Assert-PlainPath([string]$p){
 $item=Get-Item -LiteralPath $p -ErrorAction Stop
 while($item){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse path refused'}
  $item=if($item -is [IO.FileInfo]){$item.Directory}else{$item.Parent}
 }
}
function TargetId([string]$dir){Hash ($utf8.GetBytes([IO.Path]::GetFullPath($dir).TrimEnd([char]92).ToUpperInvariant()))}
function Enter-TargetLock([string]$dir){
 $name='Local\OCO-Clash-'+(TargetId $dir)
 $mutex=New-Object Threading.Mutex($false,$name)
 try{
  try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(!$held){throw 'Another optimizer is operating on this configuration; retry after it exits.'}
  return $mutex
 }catch{$mutex.Dispose();throw}
}
function Assert-Stopped {
 if(Get-Process clash-verge,verge-mihomo,verge-mihomo-alpha,mihomo -ErrorAction SilentlyContinue){throw 'Close Clash and its core normally before applying. No forced shutdown.'}
}
function Set-Journal([string]$backup,[string]$status){
 Write-AtomicText (Join-Path $backup 'state.txt') $status
}
function Show-Recovery([string]$root,[string]$dir){
 if(!(Test-Path -LiteralPath $root -PathType Container)){Write-Host 'No recovery backups found.';return}
 Assert-PlainPath $root
 foreach($b in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'clash-*'|Sort-Object LastWriteTime -Descending)){
  try{
   Assert-PlainPath $b.FullName
   $id=Join-Path $b.FullName 'target.txt';$state=Join-Path $b.FullName 'state.txt'
   if(!(Test-Path -LiteralPath $id -PathType Leaf)){continue}
   Assert-PlainPath $id
   if([IO.File]::ReadAllText($id) -ne (TargetId $dir)){continue}
   Assert-PlainPath $id
   $label=if(Test-Path -LiteralPath $state){Assert-PlainPath $state;[IO.File]::ReadAllText($state)}else{'UNKNOWN'}
   $plan=@(RestorePlan $dir $b.FullName)
   $match=if(@($plan|Where-Object State -eq 'custom').Count){'LATER_EDIT'}elseif(@($plan|Where-Object State -eq 'ready').Count){'RECOVERABLE'}else{'ALREADY_ORIGINAL'}
   Write-Host "$label / $match : $($b.FullName)"
  }catch{Write-Warning 'Unreadable or inconsistent recovery record; not auto-restored.'}
 }
}
function Assert-NoPending([string]$root,[string]$dir){
 if(!(Test-Path -LiteralPath $root -PathType Container)){return}
 Assert-PlainPath $root
 foreach($b in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'clash-*')){
  Assert-PlainPath $b.FullName
  $id=Join-Path $b.FullName 'target.txt';$state=Join-Path $b.FullName 'state.txt'
  if(Test-Path -LiteralPath $id -PathType Leaf){Assert-PlainPath $id}
  if((Test-Path -LiteralPath $id -PathType Leaf) -and [IO.File]::ReadAllText($id) -eq (TargetId $dir)){
   Assert-PlainPath $id
   $label=if(Test-Path -LiteralPath $state){Assert-PlainPath $state;[IO.File]::ReadAllText($state)}else{'UNKNOWN'}
   if($label -notin @('COMMITTED','STAGED','RECOVERED','ROLLED_BACK')){
    $rp=@(RestorePlan $dir $b.FullName)
    if(@($rp|Where-Object State -ne 'same').Count){throw "RECOVERY_REQUIRED: interrupted transaction; restore this backup first: $($b.FullName)"}
    Set-Journal $b.FullName 'ROLLED_BACK'
   }
  }
 }
}
function Assert-PrivateBackup([string]$p){
 Assert-PlainPath $p
 $acl=Get-Acl -LiteralPath $p
 $me=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if(!$acl.AreAccessRulesProtected){throw 'Backup ACL inherits unverified access'}
 foreach($r in $acl.Access){
  $sid=$r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -notin @($me,'S-1-5-18','S-1-5-32-544')){throw 'Backup ACL has unexpected identity'}
 }
}
# Restore the original transaction, not a new inverse transaction. A second interruption
# leaves the SAME original manifest and RESTORING state, with each file old or new.
function Restore-Original([string]$dir,[string]$backup,[switch]$Fixture,[switch]$CrashFirst){
 if($CrashFirst -and !$Fixture){throw 'Fixture only'}
 if(!$Fixture){Assert-Stopped}
 $p=@(RestorePlan $dir $backup)
 if(@($p|Where-Object State -eq 'custom').Count){throw 'Later edits detected; recovery refused'}
 Set-Journal $backup 'RESTORING'
 $restored=@()
 Write-AtomicText (Join-Path $backup 'progress.json') (ConvertTo-Json @{operation='restore';completed=$restored} -Depth 3)
 try{
  $i=0
  foreach($x in @($p|Where-Object State -eq 'ready')){
   if(!$Fixture){Assert-Stopped}
   Assert-PlainPath $x.Path
   if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit before restore'}
   $tmp=$x.Path+'.oco-recover-'+[guid]::NewGuid().ToString('N')
   try{
    $f=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$f.Write($x.New,0,$x.New.Length);$f.Flush($true)}finally{$f.Dispose()}
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit before replacement'}
    [IO.File]::Replace($tmp,$x.Path,($tmp+'.swap'))
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw 'Recovery readback failed'}
    Remove-Item -LiteralPath ($tmp+'.swap') -Force
    $restored+=,$x.Name
    Write-AtomicText (Join-Path $backup 'progress.json') (ConvertTo-Json @{operation='restore';completed=$restored} -Depth 3)
    $i++
    if($CrashFirst -and $i -eq 1){[Environment]::Exit(78)}
   }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
  }
  $after=@(RestorePlan $dir $backup)
  if(@($after|Where-Object State -ne 'same').Count){throw 'Recovery final readback failed'}
  Set-Journal $backup 'RECOVERED'
 }catch{
  Set-Journal $backup 'RECOVERY_REQUIRED'
  throw "RECOVERY_REQUIRED: $($_.Exception.Message); same backup: $backup"
 }
}
function RestorePlan([string]$dir,[string]$backup){
 if(!(Test-Path -LiteralPath $backup -PathType Container)){throw 'Backup directory not found'}
 Assert-PrivateBackup $backup
 $id=Join-Path $backup 'target.txt'
 if(Test-Path -LiteralPath $id -PathType Leaf){Assert-PlainPath $id;if([IO.File]::ReadAllText($id) -ne (TargetId $dir)){throw 'Backup belongs to a different configuration directory'}}
 else{throw 'Legacy backup has no target identity. Use its original v1.1 tool for manual restore.'}
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
function Apply($plan,[string]$root,[switch]$Fixture,[switch]$InjectFailure,[switch]$CrashAfterFirst,[switch]$CrashBefore,[switch]$CrashLast){
 if(($InjectFailure -or $CrashAfterFirst -or $CrashBefore -or $CrashLast) -and !$Fixture){throw "Fault injection restricted to fixture"}
 if(@($plan|Where-Object State -eq 'custom').Count){throw 'Custom extensions detected. Refusing to overwrite.'}
 $change=@($plan|Where-Object State -eq 'ready')
 if(!$change.Count){return}
 if(!$Fixture){Assert-Stopped}
 $dir=Split-Path -Parent $plan[0].Path
 Assert-PlainPath $dir
 if(!$root){throw 'Backup root required'}
 $b=Join-Path $root ('clash-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
 if(!(Test-Path -LiteralPath $root -PathType Container)){New-Item -ItemType Directory -Path $root -Force|Out-Null}
 Assert-PlainPath $root
 PrivateDir $b
 foreach($x in $plan){
  $bp=Join-Path $b $x.Name
  $f=New-Object IO.FileStream($bp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($x.Old,0,$x.Old.Length);$f.Flush($true)}finally{$f.Dispose()}
  if((Hash (ReadBytes $bp)) -ne (Hash $x.Old)){throw 'Backup readback failed before write'}
 }
 $manifest=@($plan|ForEach-Object{[pscustomobject]@{name=$_.Name;before=(Hash $_.Old);after=(Hash $_.New)}})
 Write-AtomicText (Join-Path $b 'manifest.json') (ConvertTo-Json -InputObject $manifest -Depth 3)
 Write-AtomicText (Join-Path $b 'target.txt') (TargetId $dir)
 Write-AtomicText (Join-Path $b 'format.txt') 'oco-clash-transaction-v2'
 Write-AtomicText (Join-Path $b 'versions.txt') $(if($Fixture){'fixture'}else{'Clash Verge Rev 2.5.10 / Mihomo 1.19.33'})
 Write-AtomicText (Join-Path $b 'progress.json') (ConvertTo-Json @{operation='apply';completed=@()} -Depth 3)
 Set-Journal $b 'PREPARED'
 Write-Host "Recovery backup: $b"
 # Check the complete backup manifest and both source files before mutation.
 $backManifest=ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $b 'manifest.json') -Raw -Encoding UTF8)
 foreach($x in $plan){
  $r=@($backManifest|Where-Object name -ceq $x.Name)
  if($r.Count -ne 1 -or $r[0].before -ne (Hash $x.Old) -or $r[0].after -ne (Hash $x.New)){throw 'Backup manifest readback failed'}
  if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit before transaction'}
 }
 $done=@()
 try{
  Set-Journal $b 'WRITING'
  if($CrashBefore){[Environment]::Exit(77)}
  foreach($x in $change){
   if(!$Fixture){Assert-Stopped}
   Assert-PlainPath $x.Path
   if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Concurrent edit detected'}
   $tmp=$x.Path+'.oco-'+[guid]::NewGuid().ToString('N')
   try{
    $f=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$f.Write($x.New,0,$x.New.Length);$f.Flush($true)}finally{$f.Dispose()}
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw "Concurrent edit before replacement"}
    [IO.File]::Replace($tmp,$x.Path,($tmp+".swap"))
    $done+=,$x
    Remove-Item -LiteralPath ($tmp+".swap") -Force
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw 'Readback failed'}
    Write-AtomicText (Join-Path $b 'progress.json') (ConvertTo-Json @{operation='apply';completed=@($done|ForEach-Object Name)} -Depth 3)
    if($CrashAfterFirst -and $done.Count -eq 1){[Environment]::Exit(77)}
    if($InjectFailure -and $done.Count -eq 1){throw 'Injected fixture failure after first write'}
   }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
  }
  foreach($x in $plan){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw "Final transaction readback failed"}}
  if($CrashLast){[Environment]::Exit(77)}
  Set-Journal $b 'STAGED'
 }catch{
  $reason=$_.Exception.Message;$failed=$false
  # Independent per-file attempts: do not stop recovery of the second file if the first failed.
  foreach($x in $done){
   try{
    if(!$Fixture){Assert-Stopped}
    Assert-PlainPath $x.Path
    if((Hash (ReadBytes $x.Path)) -ne (Hash $x.New)){throw 'Later edit or unknown file state'}
    $tmp=$x.Path+'.restore-'+[guid]::NewGuid().ToString('N')
    try{[IO.File]::WriteAllBytes($tmp,$x.Old);[IO.File]::Replace($tmp,$x.Path,($tmp+".swap")); Remove-Item -LiteralPath ($tmp+".swap") -Force; if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Rollback readback failed'}}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
   }catch{$failed=$true;Write-Warning "Recovery needed for $($x.Name): $($_.Exception.Message)"}
  }
  foreach($x in $plan){try{if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){$failed=$true}}catch{$failed=$true}}
  if($failed){Set-Journal $b 'RECOVERY_REQUIRED'}else{Set-Journal $b 'ROLLED_BACK'}
  throw "$reason; recovery backup: $b"
 }
 Write-Host "Staged extensions; backup: $b"
 return $b
}
$lock=$null
try{
 if(!$FixtureCrash -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package-manifest.json'))){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-Package.ps1') -Required | Out-Host
  if($LASTEXITCODE){throw 'Package integrity failed; no write'}
 }
 if($FixtureCrash){
  if(!$FixturePath){throw 'Fixture path required'}
  $f=[IO.Path]::GetFullPath($FixturePath)
  if(!(Test-Path -LiteralPath (Join-Path $f 'OCO-CRASH-FIXTURE') -PathType Leaf) -or !(Split-Path -Leaf $f).StartsWith('oco crash fixture ') -or (Split-Path -Parent $f) -ne [IO.Path]::GetTempPath().TrimEnd([char]92)){throw 'Fixture only'}
  if($FixturePhase -eq 'RestoreFirst'){
   $b=@(Get-ChildItem -LiteralPath (Join-Path $f 'backup') -Directory)
   if($b.Count -ne 1){throw 'Fixture needs one original transaction'}
   Restore-Original $f $b[0].FullName -Fixture -CrashFirst
  }else{
   $p=@(Plan $f)
   $null=Apply $p (Join-Path $f 'backup') -Fixture -CrashAfterFirst:($FixturePhase -eq 'First') -CrashBefore:($FixturePhase -eq 'Before') -CrashLast:($FixturePhase -eq 'Last')
  }
  throw 'Fixture crash not injected'
 }
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
   $mp=Join-Path $backup 'manifest.json';$saved=ReadBytes $mp
   [IO.File]::WriteAllText($mp,'{malformed',$utf8)
   $refused=$false;try{$null=@(RestorePlan $t $backup)}catch{$refused=$true}
   if(!$refused){throw 'Malformed manifest accepted'}
   [IO.File]::WriteAllBytes($mp,$saved)
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
   [IO.File]::WriteAllText((Join-Path $t 'Merge.yaml'),'# default',$utf8)
   $p=@(Plan $t -MissingOnly)
   if($p[0].State -ne 'ready' -or $p[1].State -ne 'same'){throw 'Empty YAML missing-only failed'}
   Write-Host 'CLASH_MISSING_ONLY_SELF_TEST_OK'
   $wrong=Join-Path $t 'wrong';New-Item -ItemType Directory $wrong|Out-Null
   foreach($n in $files){Copy-Item -LiteralPath (Join-Path $t $n) -Destination (Join-Path $wrong $n)}
   $refused=$false;try{$null=@(RestorePlan $wrong $b2)}catch{$refused=$true};if(!$refused){throw 'Wrong target backup accepted'}
   $crash=Join-Path ([IO.Path]::GetTempPath()) ('oco crash fixture '+[guid]::NewGuid())
   try{
    New-Item -ItemType Directory $crash|Out-Null
    [IO.File]::WriteAllText((Join-Path $crash 'OCO-CRASH-FIXTURE'),'fixture',$utf8)
    [IO.File]::WriteAllText((Join-Path $crash 'Merge.yaml'),'{}',$utf8)
    [IO.File]::WriteAllText((Join-Path $crash 'Script.js'),'function main(config) { return config; }',$utf8)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FixtureCrash -FixturePath $crash
    if($LASTEXITCODE -ne 77){throw 'Crash child did not exit at first replacement'}
    $cb=@(Get-ChildItem (Join-Path $crash 'backup') -Directory)
    if($cb.Count -ne 1 -or [IO.File]::ReadAllText((Join-Path $cb[0].FullName 'state.txt')) -ne 'WRITING'){throw 'Crash journal not retained'}
    $blocked=$false;try{Assert-NoPending (Join-Path $crash 'backup') $crash}catch{$blocked=$true};if(!$blocked){throw 'Interrupted transaction not blocked'}
    $cp=@(RestorePlan $crash $cb[0].FullName)
    if(@($cp|Where-Object State -eq 'ready').Count -ne 1){throw 'Crash partial restore plan mismatch'}
    Restore-Original $crash $cb[0].FullName -Fixture
    if([IO.File]::ReadAllText((Join-Path $crash 'Merge.yaml')) -ne '{}' -or [IO.File]::ReadAllText((Join-Path $crash 'Script.js')) -ne 'function main(config) { return config; }'){throw 'Crash recovery bytes mismatch'}
    Assert-NoPending (Join-Path $crash 'backup') $crash
   }finally{if(Test-Path -LiteralPath $crash){Remove-Item -LiteralPath $crash -Recurse -Force}}
   foreach($phase in @('Before','Last','RestoreFirst')){
    $crash=Join-Path ([IO.Path]::GetTempPath()) ('oco crash fixture '+[guid]::NewGuid())
    try{
     New-Item -ItemType Directory $crash|Out-Null
     [IO.File]::WriteAllText((Join-Path $crash 'OCO-CRASH-FIXTURE'),'fixture',$utf8)
     [IO.File]::WriteAllText((Join-Path $crash 'Merge.yaml'),'{}',$utf8)
     [IO.File]::WriteAllText((Join-Path $crash 'Script.js'),'function main(config) { return config; }',$utf8)
     $orig=@(Plan $crash)
     if($phase -eq 'RestoreFirst'){$null=Apply $orig (Join-Path $crash 'backup') -Fixture}
     & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -FixtureCrash -FixturePath $crash -FixturePhase $phase
     $expected=if($phase -eq 'RestoreFirst'){78}else{77}
     if($LASTEXITCODE -ne $expected){throw "Fixture child unexpected exit: $phase"}
     $cb=@(Get-ChildItem (Join-Path $crash 'backup') -Directory)
     if($cb.Count -ne 1){throw 'Recovery generated conflicting inverse transaction'}
     $rp=@(RestorePlan $crash $cb[0].FullName)
     $ready=@($rp|Where-Object State -eq 'ready').Count
     $want=switch($phase){'Before'{0};'Last'{2};'RestoreFirst'{1}}
     if($ready -ne $want){throw "Unexpected file states: $phase"}
     Restore-Original $crash $cb[0].FullName -Fixture
     foreach($x in $orig){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw "Recovery bytes mismatch: $phase"}}
     Assert-NoPending (Join-Path $crash 'backup') $crash
     Write-Host "CLASH_CRASH_RECOVERY_OK $phase"
    }finally{if(Test-Path -LiteralPath $crash){Remove-Item -LiteralPath $crash -Recurse -Force}}
   }
   # Locked second file forces first write rollback. Preserve actual original bytes.
   [IO.File]::WriteAllText((Join-Path $t 'Merge.yaml'),'{}',$utf8)
   [IO.File]::WriteAllText((Join-Path $t 'Script.js'),'function main(config) { return config; }',$utf8)
   $lp=@(Plan $t)
   $badRoot=Join-Path $t 'not-a-directory'
   [IO.File]::WriteAllText($badRoot,'fixture',$utf8)
   $refused=$false;try{$null=Apply $lp $badRoot -Fixture}catch{$refused=$true}
   if(!$refused){throw 'Invalid backup root accepted'}
   foreach($x in $lp){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Backup preparation failure modified input'}}
   Write-Host 'CLASH_BACKUP_PREPARATION_FAILURE_OK'
   $held=[IO.File]::Open($lp[1].Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   try{$refused=$false;try{$null=Apply $lp (Join-Path $t 'backup') -Fixture}catch{$refused=$true};if(!$refused){throw 'Locked file unexpectedly replaced'}}finally{$held.Dispose()}
   foreach($x in $lp){if((Hash (ReadBytes $x.Path)) -ne (Hash $x.Old)){throw 'Locked-file recovery changed original'}}
   Write-Host 'CLASH_LOCKED_FILE_RECOVERY_OK'
   $mx=Enter-TargetLock $t
   try{
    $job=Start-Job -ScriptBlock {param($name)$m=New-Object Threading.Mutex($false,$name);try{if($m.WaitOne(0)){$m.ReleaseMutex();'UNEXPECTED'}else{'BUSY'}}finally{$m.Dispose()}} -ArgumentList ('Local\OCO-Clash-'+(TargetId $t))
    try{if((Receive-Job -Job $job -Wait) -ne 'BUSY'){throw 'Cross-process lock failed'}}finally{Remove-Job $job -Force}
   }finally{$mx.ReleaseMutex();$mx.Dispose()}
   Write-Host 'CLASH_PROCESS_DEATH_RECOVERY_AND_LOCK_OK'
   Write-Host 'CLASH_SELF_TEST_OK';exit 0
  }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
 }
 if(($Verify -or $RecoveryList) -and ($RestorePrompt -or $RestoreFrom -or $PolicyFrom -or $AddMissing -or $ConservativeAuto -or ($Verify -and $RecoveryList))){throw 'Choose one action'}
 if($PolicyFrom){throw 'PARTIAL: policy writing disabled until native selected-group lifecycle is verified. Candidate generation remains available.'}
 if(($AddMissing -and ($RestorePrompt -or $RestoreFrom -or $PolicyFrom)) -or ($PolicyFrom -and ($RestorePrompt -or $RestoreFrom))){throw 'Choose one action'}
 if(!$DataPath){$DataPath=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'}
 $DataPath=[IO.Path]::GetFullPath($DataPath)
 if(!(Test-Path -LiteralPath (Join-Path $DataPath 'verge.yaml') -PathType Leaf)){throw 'Clash data directory not confirmed; use -DataPath explicitly.'}
 $dir=Join-Path $DataPath 'profiles'
 Assert-PlainPath $dir
 if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
 if($RestorePrompt){
  if($RestoreFrom){throw 'Choose only one restore input'}
  Show-Recovery $BackupRoot $dir
  $RestoreFrom=(Read-Host 'Enter full OCO backup directory path; empty cancels').Trim().Trim([char]34)
  if(!$RestoreFrom){Write-Host 'CANCELLED';exit 1}
 }
 if($RecoveryList){Show-Recovery $BackupRoot $dir;exit 0}
 if($Verify){
  $runtime=Join-Path $DataPath 'clash-verge.yaml';Assert-PlainPath $runtime
  $exe=Join-Path $PSScriptRoot 'bin\oco-node-quality.exe'
  & $exe --verify-runtime $runtime
  exit $LASTEXITCODE
 }
 if(!$CheckOnly){$lock=Enter-TargetLock $dir}
 if(!$RestoreFrom -and !$CheckOnly){Assert-NoPending $BackupRoot $dir}
 if($RestoreFrom){
  $p=@(RestorePlan $dir ([IO.Path]::GetFullPath($RestoreFrom)))
  $p|Select-Object Name,State|Format-Table
  if(@($p|Where-Object State -eq 'custom').Count){Write-Warning 'Later edits detected; restore refused.';exit 2}
  if($CheckOnly){exit 0}
  if(@($p|Where-Object State -eq 'ready').Count -eq 0){Set-Journal ([IO.Path]::GetFullPath($RestoreFrom)) 'RECOVERED';Write-Host 'Original bytes already present.';exit 0}
  if((Read-Host 'Restore these two extensions only? [Y/N]') -notmatch '^[Yy]$'){Write-Host 'CANCELLED';exit 1}
  if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
  Restore-Original $dir ([IO.Path]::GetFullPath($RestoreFrom))
  Write-Host 'APPLIED_PENDING_ACTIVATION: original bytes restored; start Clash, reactivate subscription and verify.'
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
 $autoReduced=$false
 if($ConservativeAuto -and !$CheckOnly -and !$PolicyFrom -and !$AddMissing -and @($p|Where-Object State -eq 'custom').Count){
  Write-Warning 'Custom extensions detected. Full preset is not safe; only missing allowlisted keys can be added. Existing Script.js stays unchanged.'
  $p=@(Plan $dir -MissingOnly);$AddMissing=$true;$autoReduced=$true
 }
 $p|Select-Object Name,State|Format-Table
 if(@($p|Where-Object State -eq 'custom').Count){Write-Warning 'Custom extensions preserved. Review guide and integrate manually.';exit 2}
 if($CheckOnly){exit 0}
 if(@($p|Where-Object State -eq 'ready').Count -eq 0){
  if($autoReduced -or $AddMissing){Write-Host 'NO_CHANGE: no missing allowlisted keys; existing custom configuration preserved. Full preset not verified.';if($autoReduced){exit 2};exit 0}
  Write-Host 'NO_CHANGE: preset files match. Use V to verify generated config; live network not checked.';exit 0
 }
 if($PolicyFrom){
  Write-Host 'Append measured candidates to the explicitly chosen existing select group. No route or AI selection is changed. Candidate expires on future reloads after 24h; close Clash normally first.'
  if((Read-Host 'Stage validated policy extension? [Y/N]') -notmatch '^[Yy]$'){Write-Host 'CANCELLED';exit 1}
 }elseif($AddMissing){
  Write-Host 'Add only absent tcp-concurrent and profile persistence keys. Explicit values and Script.js preserved. YAML comments/format may change. Close Clash manually first.'
  if((Read-Host 'Apply conservative structured merge? [Y/N]') -notmatch '^[Yy]$'){Write-Host 'CANCELLED';exit 1}
 }else{
  Write-Host 'China-oriented DNS and OpenAI routing preset for Clash Verge Rev 2.5.10 / Mihomo 1.19.33. Review guide. Close Clash manually first.'
  if((Read-Host 'Apply only to default extensions? [Y/N]') -notmatch '^[Yy]$'){Write-Host 'CANCELLED';exit 1}
 }

 # Restrict automatic application to explicit verified version. Do not guess a core path.
 $exe=if($AppPath){$AppPath}else{Read-Host 'Full path to installed clash-verge.exe'}
 if(!(Test-Path -LiteralPath $exe -PathType Leaf) -or [IO.Path]::GetFileName($exe) -ne 'clash-verge.exe'){throw 'App executable not confirmed'}
 Assert-PlainPath $exe
 $official=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'))
 if($DataPath -ine $official){Write-Warning 'PARTIAL: custom data directory is read-only until its native association is verified.';exit 2}
 $version=(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
 if($version -notmatch '^2\.5\.10(?:\.0)?$'){Write-Warning 'Version not validated; manual integration only.';exit 2}
 $core=Join-Path (Split-Path -Parent $exe) 'verge-mihomo.exe'
 if(!(Test-Path -LiteralPath $core -PathType Leaf)){Write-Warning 'Bundled core not found; no write.';exit 2}
 Assert-PlainPath $core
 $coreVersion=& $core -v 2>&1 | Out-String
 if($LASTEXITCODE -ne 0 -or $coreVersion -notmatch '(?m)\bMihomo\s+Meta\s+v1\.19\.33(?:\s|$)'){Write-Warning 'Core version not validated; no write.';exit 2}
 if(!$BackupRoot){$BackupRoot=Join-Path $env:LOCALAPPDATA 'OneClickOptimizer\Backups\ClashVerge'}
 if($PolicyFrom){if((Hash (ReadBytes $runtimePath)) -ne $runtimeHash){throw 'Runtime changed before transaction; retest'};if((Get-Process clash-verge,verge-mihomo -ErrorAction SilentlyContinue)){throw 'Close Clash normally before applying'}; $fresh=[byte[]](SafePolicy $DataPath $AppPath $PolicyFrom $PolicyParent);if((Hash $fresh) -ne (Hash $scriptRow.New)){throw 'Policy changed during final validation'}}
 $null=Apply $p $BackupRoot
 Write-Host 'APPLIED_PENDING_ACTIVATION: start Clash, reactivate subscription and verify. No live activation proof.'
 exit 2
}catch{Write-Host 'FAILED_OR_RECOVERY_REQUIRED: see specific error and R recovery list';Write-Error $_ -ErrorAction Continue;exit 1}finally{if($lock){$lock.ReleaseMutex();$lock.Dispose()}}
