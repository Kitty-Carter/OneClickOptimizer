[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port=7897,[ValidateRange(1,3)][int]$Rounds=2,[switch]$SelfTest,[switch]$InspectExit,[switch]$ExitPrompt)
$ErrorActionPreference='Stop'
$inv=[Globalization.CultureInfo]::InvariantCulture
function Parse-Probe([string]$line,[int]$exit,[int]$expected){
 $a=$line.Trim().Split('|');$v=@()
 if($a.Count -ne 5 -or $a[0] -notmatch '^\d{3}$'){return [pscustomobject]@{State='UNAVAILABLE';HTTP=$null;TotalMs=$null;TLSMs=$null;Exit=$exit}}
 for($i=1;$i -lt 5;$i++){
  $x=0.0
  if(![double]::TryParse($a[$i],[Globalization.NumberStyles]::Float,$inv,[ref]$x) -or [double]::IsNaN($x) -or [double]::IsInfinity($x) -or $x -lt 0){return [pscustomobject]@{State='UNAVAILABLE';HTTP=$null;TotalMs=$null;TLSMs=$null;Exit=$exit}}
  $v+=$x
 }
 $http=[int]$a[0]
 $state=if($exit -ne 0){'TRANSPORT_ERROR'}elseif($http -eq $expected){'EXPECTED'}elseif($http -ge 100 -and $http -le 599){'HTTP_OTHER'}else{'UNAVAILABLE'}
 [pscustomobject]@{State=$state;HTTP=$http;TotalMs=[math]::Round($v[3]*1000,1);TLSMs=[math]::Round($v[1]*1000,1);Exit=$exit}
}
function Median($values){
 $a=@($values|Sort-Object)
 if(!$a.Count){return $null}
 $i=[int][math]::Floor($a.Count/2)
 if($a.Count%2){return $a[$i]}
 [math]::Round(($a[$i-1]+$a[$i])/2,1)
}
function Listener([int]$p){
 $rows=@(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue)
 if(!$rows.Count){throw 'No TCP listener at requested port.'}
 $loop=@($rows|Where-Object LocalAddress -eq '127.0.0.1')
 if(!$loop.Count){throw 'No explicit IPv4 loopback listener; refusing network probes.'}
 if(@($rows|Where-Object LocalAddress -notin @('127.0.0.1','::1')).Count){throw 'Listener exposed beyond loopback; refusing probes.'}
 $ids=@($loop|Select-Object -ExpandProperty OwningProcess -Unique)
 if($ids.Count -ne 1){throw 'Ambiguous listener ownership.'}
 $pobj=Get-Process -Id $ids[0] -ErrorAction Stop
 if($pobj.ProcessName -ne 'verge-mihomo'){throw 'Listener not owned by verge-mihomo.'}
 return [int]$pobj.Id
}
function Curl-Run([string[]]$args1){
 # All arguments are generated internally, ASCII, no shell interpolation.
 # No curlrc, no redirects, no direct fallback; ignore inherited NO_PROXY.
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName=(Join-Path $env:SystemRoot 'System32\curl.exe')
 if(!(Test-Path -LiteralPath $si.FileName -PathType Leaf)){throw 'Windows curl.exe missing'}
 foreach($arg in $args1){if($arg -match '[\s"]'){throw 'Unexpected argument characters'}}
 $si.Arguments=$args1 -join ' '
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $si.EnvironmentVariables.Remove('NO_PROXY');$si.EnvironmentVariables.Remove('no_proxy')
 $si.EnvironmentVariables.Remove('CURL_CA_BUNDLE');$si.EnvironmentVariables.Remove('SSL_CERT_FILE');$si.EnvironmentVariables.Remove('SSL_CERT_DIR')
 $proc=New-Object Diagnostics.Process;$proc.StartInfo=$si
 try{
  if(!$proc.Start()){throw 'curl start failed'}
  $stdout=$proc.StandardOutput.ReadToEndAsync();$stderr=$proc.StandardError.ReadToEndAsync()
  if(!$proc.WaitForExit(15000)){try{$proc.Kill()}catch{};throw 'curl watchdog timeout'}
  $body=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
  [pscustomobject]@{Exit=$proc.ExitCode;Body=$body}
 }finally{$proc.Dispose()}
}
function Base-Args([int]$p){
 @('-q','--silent','--show-error','--proxy',"http://127.0.0.1:$p",'--noproxy','oco-no-bypass.invalid','--proto','=https','--connect-timeout','4','--max-time','10','--max-filesize','1048576')
}
function Exit-Fields($j){
 $score=$null
 if($null -ne $j.fraudScore -and ($j.fraudScore -is [int] -or $j.fraudScore -is [long] -or $j.fraudScore -is [double]) -and $j.fraudScore -ge 0 -and $j.fraudScore -le 100){$score=$j.fraudScore}
 $ip=$null;$parsed=$null
 if($j.ip -is [string] -and [Net.IPAddress]::TryParse($j.ip,[ref]$parsed)){$ip=$parsed.ToString()}
 $country=if($j.countryCode -is [string] -and $j.countryCode -cmatch '^[A-Z]{2}$'){$j.countryCode}else{$null}
 $asn=if(($j.asn -is [int] -or $j.asn -is [long]) -and $j.asn -ge 0 -and $j.asn -le 4294967295){$j.asn}else{$null}
 [pscustomobject]@{IPValid=($null -ne $ip);CountryCode=$country;ASN=$asn;ProviderRiskScore=$score;Residential=if($j.isResidential -is [bool]){$j.isResidential}else{$null};Broadcast=if($j.isBroadcast -is [bool]){$j.isBroadcast}else{$null}}
}
try{
 if($SelfTest){
  $r=Parse-Probe '204|0.001|0.200|0.300|0.400' 0 204
  if($r.State -ne 'EXPECTED' -or $r.TotalMs -ne 400){throw 'probe success fixture'}
  if((Parse-Probe '403|0.01|0.2|0.3|0.4' 0 200).State -ne 'HTTP_OTHER'){throw 'HTTP error classification'}
  if((Parse-Probe '000|0|0|0|10' 28 200).State -ne 'TRANSPORT_ERROR'){throw 'transport classification'}
  if((Parse-Probe '200|NaN|0|0|1' 0 200).State -ne 'UNAVAILABLE'){throw 'nonfinite fixture'}
  if((Parse-Probe 'garbage' 1 200).State -ne 'UNAVAILABLE'){throw 'malformed fixture'}
  if((Median @(3,1,2)) -ne 2 -or (Median @(1,4)) -ne 2.5 -or $null -ne (Median @())){throw 'median fixture'}
  $j=ConvertFrom-Json '{"ip":"192.0.2.1","asn":64500,"countryCode":"JP","fraudScore":0,"isResidential":false}'
  $f=Exit-Fields $j
  if(!$f.IPValid -or $f.ProviderRiskScore -ne 0 -or $f.Residential -ne $false -or $null -ne $f.Broadcast){throw 'exit field fixture'}
  $f=Exit-Fields (ConvertFrom-Json '{"ip":"not-an-ip","fraudScore":"0","countryCode":"xx","isResidential":"false"}')
  if($f.IPValid -or $null -ne $f.ProviderRiskScore -or $null -ne $f.CountryCode -or $null -ne $f.Residential){throw 'malformed exit fields'}
  'CLASH_NETWORK_DIAGNOSTIC_SELF_TEST_OK';exit 0
 }
 $owner=Listener $Port
 Write-Host "Verified loopback listener: 127.0.0.1:$Port, verge-mihomo PID $owner"
 Write-Host 'Tests current rule-routed path, not an individual node. Mihomo may choose DIRECT by rule. No routing changes.'
 if($ExitPrompt){
  $InspectExit=(Read-Host 'Send one request to IPPure public API through this proxy? [Y/N]') -match '^[Yy]$'
  if(!$InspectExit){Write-Host 'Cancelled; no request sent.';exit 0}
 }
 if($InspectExit){
  if((Listener $Port) -ne $owner){throw 'Listener changed'}
  $a=@(Base-Args $Port)+@('--fail','https://my.ippure.com/v1/info')
  $res=Curl-Run $a
  if($res.Exit -ne 0){Write-Warning "IPPure unavailable (curl exit $($res.Exit)); no retry.";exit 2}
  else{
   try{$f=Exit-Fields (ConvertFrom-Json -InputObject $res.Body);if(!$f.IPValid){throw 'Invalid response'};$f|Format-List|Out-Host;Write-Host 'Provider estimate only; not a security or service-access guarantee. Raw IP not displayed or stored.'}catch{Write-Warning 'IPPure response unavailable or unexpected; no retry.';exit 2}
  }
  exit 0
 }
 $targets=@(
  [pscustomobject]@{Name='Cloudflare 204';URL='https://cp.cloudflare.com/generate_204';Expected=204},
  [pscustomobject]@{Name='GitHub';URL='https://github.com/';Expected=200},
  [pscustomobject]@{Name='ChatGPT';URL='https://chatgpt.com/';Expected=200}
 )
 $all=@()
 for($round=1;$round -le $Rounds;$round++){
  foreach($t in $targets){
   if((Listener $Port) -ne $owner){throw 'Listener changed during diagnostic'}
   $a=@(Base-Args $Port)+@('--output','NUL','--write-out','%{http_code}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}',$t.URL)
   $res=Curl-Run $a;$r=Parse-Probe $res.Body $res.Exit $t.Expected
   $all+=[pscustomobject]@{Round=$round;Target=$t.Name;State=$r.State;HTTP=$r.HTTP;TotalMs=$r.TotalMs;TLSMs=$r.TLSMs;Exit=$r.Exit}
  }
 }
 $all|Format-Table -AutoSize|Out-Host
 foreach($t in $targets){
  $rows=@($all|Where-Object Target -eq $t.Name)
  $ok=@($rows|Where-Object State -eq 'EXPECTED')
  [pscustomobject]@{Target=$t.Name;ExpectedResponses=$ok.Count;Attempts=$rows.Count;MedianSuccessfulMs=(Median @($ok|Select-Object -ExpandProperty TotalMs));HTTP_Other=@($rows|Where-Object State -eq 'HTTP_OTHER').Count;TransportOrUnknown=@($rows|Where-Object State -in @('TRANSPORT_ERROR','UNAVAILABLE')).Count}
 }
 Write-Host 'HTTP responses do not prove authenticated app access. DNS/TUN leak, UDP and throughput not tested.'
 if(@($all|Where-Object State -ne 'EXPECTED').Count){exit 2}
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
