[CmdletBinding()]
param([switch]$SelfTest,[string]$Fixture,[ValidateRange(1,30)][int]$Delay=3)
$ErrorActionPreference='Stop'
$utf=New-Object Text.UTF8Encoding($false)
function FileDigest($p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Worker($dir,$seconds){
 $d=[IO.Path]::GetFullPath($dir)
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(!($d.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) -or [IO.Path]::GetFileName($d) -notmatch '^oco-watchdog-[0-9a-f]{32}$'){throw 'Fixture only'}
 $n=@('original.bin','candidate.bin','target.bin','guard.json')
 foreach($f in $n){$p=Join-Path $d $f;if(!(Test-Path -LiteralPath $p -PathType Leaf) -or ((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid fixture'}}
 if((Get-Item -LiteralPath $d).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point'}
 $m=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $d 'guard.json')))
 $target=Join-Path $d 'target.bin';$orig=Join-Path $d 'original.bin';$cand=Join-Path $d 'candidate.bin'
 if((FileDigest $orig) -ne $m.before -or (FileDigest $cand) -ne $m.after){throw 'Bad fixture hashes'}
 [IO.File]::WriteAllText((Join-Path $d 'armed'),'armed',$utf)
 Start-Sleep -Seconds $seconds
 $result='CONFLICT'
 if(Test-Path -LiteralPath (Join-Path $d 'cancel')){$result='CANCELLED'}
 elseif((FileDigest $target) -eq $m.before){$result='ALREADY_ORIGINAL'}
 elseif((FileDigest $target) -eq $m.after){
  $tmp=Join-Path $d ('restore-'+[guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllBytes($tmp,[IO.File]::ReadAllBytes($orig))
  if((FileDigest $tmp) -ne $m.before -or (FileDigest $target) -ne $m.after){throw 'Guard changed'}
  [IO.File]::Replace($tmp,$target,($tmp+'.swap'))
  if((FileDigest $target) -ne $m.before){throw 'Restore readback failed'}
  Remove-Item -LiteralPath ($tmp+'.swap') -Force
  $result='RESTORED'
 }
 [IO.File]::WriteAllText((Join-Path $d 'result'),$result,$utf)
}
try{
 if($Fixture){Worker $Fixture $Delay;exit 0}
 if(!$SelfTest){throw 'Fixture demonstration only. Not a live network watchdog.'}
 foreach($mode in @('RESTORED','CANCELLED','CONFLICT')){
  $d=Join-Path ([IO.Path]::GetTempPath()) ('oco-watchdog-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $d|Out-Null
  try{
   $a=Join-Path $d 'original.bin';$b=Join-Path $d 'candidate.bin';$t=Join-Path $d 'target.bin'
   [IO.File]::WriteAllText($a,'original',$utf);[IO.File]::WriteAllText($b,'candidate',$utf);[IO.File]::WriteAllText($t,'candidate',$utf)
   [IO.File]::WriteAllText((Join-Path $d 'guard.json'),(ConvertTo-Json @{before=(FileDigest $a);after=(FileDigest $b)}),$utf)
   # A launcher exits after spawning a distinct worker. No finally-based rollback.
   $launch=Join-Path $d 'launch.ps1'
   $code='param($worker,$dir); $p=Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",(''"''+$worker+''"''),"-Fixture",(''"''+$dir+''"''),"-Delay","3") -RedirectStandardError (Join-Path $dir "worker.err") -RedirectStandardOutput (Join-Path $dir "worker.out") -PassThru; [IO.File]::WriteAllText((Join-Path $dir "worker.pid"),[string]$p.Id)'
   [IO.File]::WriteAllText($launch,$code,$utf)
   $p=Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$launch+'"'),('"'+$PSCommandPath+'"'),('"'+$d+'"')) -PassThru
   if(!$p.WaitForExit(10000) -or $p.ExitCode){throw 'Launcher failed'}
   if(!(Test-Path -LiteralPath (Join-Path $d 'worker.pid'))){throw 'Worker missing'}
   if($mode -eq 'CANCELLED'){[IO.File]::WriteAllText((Join-Path $d 'cancel'),'cancel',$utf)}
   if($mode -eq 'CONFLICT'){[IO.File]::WriteAllText($t,'later edit',$utf)}
   $deadline=(Get-Date).AddSeconds(12)
   do{Start-Sleep -Milliseconds 100}until((Test-Path -LiteralPath (Join-Path $d 'result')) -or (Get-Date) -gt $deadline)
   $result=[IO.File]::ReadAllText((Join-Path $d 'result'))
   if($result -ne $mode){throw "Expected $mode, got $result"}
   $expected=if($mode -eq 'RESTORED'){'original'}elseif($mode -eq 'CANCELLED'){'candidate'}else{'later edit'}
   if([IO.File]::ReadAllText($t) -ne $expected){throw 'Wrong final bytes'}
   "WATCHDOG_FIXTURE_$mode PASS"
  }finally{if(Test-Path (Join-Path $d "result")){Remove-Item -LiteralPath $d -Recurse -Force}else{Write-Host "Fixture retained: $d";Get-ChildItem $d|Select-Object Name;Get-Content (Join-Path $d "worker.err") -ErrorAction SilentlyContinue}}
 }
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
