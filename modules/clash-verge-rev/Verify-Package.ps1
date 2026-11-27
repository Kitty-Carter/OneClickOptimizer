[CmdletBinding()]
param([string]$Root=$PSScriptRoot,[switch]$SelfTest,[switch]$Required)
$ErrorActionPreference='Stop'
function Confirm-Package([string]$root,[bool]$required){
 $root=[IO.Path]::GetFullPath($root)
 $p=Join-Path $root 'package-manifest.json'
 if(!(Test-Path -LiteralPath $p -PathType Leaf)){if($required){throw 'Package manifest missing; re-extract the ZIP.'};return 'SOURCE_NO_MANIFEST'}
 $m=Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json
 if($m.ref -notmatch '^[0-9a-f]{40}$' -or !$m.files){throw 'Invalid package manifest'}
 $entries=@($m.files.PSObject.Properties)
 if($entries.Count -lt 1 -or $entries.Count -gt 300){throw 'Invalid package manifest count'}
 $seen=@{}
 foreach($x in $entries){
  $n=$x.Name
  if($n -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -or $n.Split('/') -contains '..' -or $n.Split('/') -contains '.' -or $seen.ContainsKey($n)){throw 'Unsafe manifest path'}
  $seen[$n]=$true
  if($x.Value -notmatch '^[0-9a-f]{64}$'){throw 'Invalid file digest'}
  $f=Join-Path $root $n.Replace('/','\')
  if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw "Missing package file: $n"}
  $item=Get-Item -LiteralPath $f
  while($item){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse path refused'};$item=if($item -is [IO.FileInfo]){$item.Directory}else{$item.Parent}}
  if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $x.Value){throw "Package hash mismatch: $n"}
 }
 if($required){foreach($n in @('Start-ClashOptimizer.ps1','Optimize-Clash.ps1','Verify-Package.ps1','bin/oco-node-quality.exe','presets/Merge.yaml','presets/Script.js')){if(!$seen.ContainsKey($n)){throw "Missing required manifest record: $n"}}}
 "PACKAGE_INTEGRITY_OK $($entries.Count) files (not a publisher signature)"
}
try{
 if($SelfTest){
  $t=Join-Path ([IO.Path]::GetTempPath()) ('oco package fixture '+[guid]::NewGuid())
  try{
   New-Item -ItemType Directory -Path $t|Out-Null
   $p=Join-Path $t 'a.txt';[IO.File]::WriteAllText($p,'fixture')
   $m=@{ref=('a'*40);files=@{'a.txt'=(Get-FileHash $p).Hash.ToLowerInvariant()}}
   $mf=Join-Path $t 'package-manifest.json';[IO.File]::WriteAllText($mf,($m|ConvertTo-Json -Depth 4))
   if((Confirm-Package $t $false) -notmatch '^PACKAGE_INTEGRITY_OK'){throw 'Valid fixture failed'}
   [IO.File]::WriteAllText($p,'tampered')
   $bad=$false;try{$null=Confirm-Package $t $false}catch{$bad=$true};if(!$bad){throw 'Tampered fixture accepted'}
   $m.files=@{'../a.txt'=('a'*64)};[IO.File]::WriteAllText($mf,($m|ConvertTo-Json -Depth 4))
   $bad=$false;try{$null=Confirm-Package $t $false}catch{$bad=$true};if(!$bad){throw 'Traversal fixture accepted'}
   'PACKAGE_INTEGRITY_SELFTEST_OK';exit 0
  }finally{if(Test-Path -LiteralPath $t){Remove-Item -LiteralPath $t -Recurse -Force}}
 }
 Confirm-Package $Root ([bool]$Required)
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
