[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port=7897,[switch]$SelfTest)
$ErrorActionPreference='Stop'
function Classify-Listener($rows){
 $a=@($rows)
 if(!$a.Count){return 'ABSENT'}
 if(@($a|Where-Object {$_.Address -notin @('127.0.0.1','::1')}).Count){return 'NON_LOOPBACK'}
 if(!@($a|Where-Object {$_.Address -eq '127.0.0.1'}).Count){return 'IPV4_UNAVAILABLE'}
 if(@($a|Where-Object {$_.Name -ne 'verge-mihomo'}).Count){return 'OWNER_UNKNOWN'}
 if(@($a|Select-Object -ExpandProperty PID -Unique).Count -ne 1){return 'AMBIGUOUS'}
 'LOOPBACK_MIHOMO'
}
try{
 if($SelfTest){
  if((Classify-Listener @()) -ne 'ABSENT'){throw 'missing fixture'}
  if((Classify-Listener @([pscustomobject]@{Address='0.0.0.0';Name='verge-mihomo';PID=1})) -ne 'NON_LOOPBACK'){throw 'public fixture'}
  if((Classify-Listener @([pscustomobject]@{Address='127.0.0.1';Name='other';PID=1})) -ne 'OWNER_UNKNOWN'){throw 'owner fixture'}
  if((Classify-Listener @([pscustomobject]@{Address='127.0.0.1';Name='verge-mihomo';PID=1})) -ne 'LOOPBACK_MIHOMO'){throw 'valid fixture'}
  'LOCAL_HEALTH_SELFTEST_OK';exit 0
 }
 $rows=@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue|ForEach-Object {
  $p=Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
  [pscustomobject]@{Address=$_.LocalAddress;Name=$p.ProcessName;PID=$_.OwningProcess}
 })
 $status=Classify-Listener $rows
 [pscustomobject]@{Port=$Port;Listener=$status;ClientProcessCount=@(Get-Process clash-verge -ErrorAction SilentlyContinue).Count;CoreProcessCount=@(Get-Process verge-mihomo -ErrorAction SilentlyContinue).Count}|Format-List|Out-Host
 Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object ConnectionState -eq Connected|ForEach-Object{
  $dns=Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
  [pscustomobject]@{Interface=$_.InterfaceAlias;MTU=$_.NlMtu;DnsServerCount=@($dns.ServerAddresses).Count;FakeIPResolverConfigured=($dns.ServerAddresses -contains '198.18.0.2')}
 }|Format-Table -AutoSize|Out-Host
 Write-Host 'Read-only local observations; DNS resolver address does not prove upstream path. No external requests. Listener process name is not executable attestation.'
 if($status -eq 'LOOPBACK_MIHOMO'){exit 0};exit 2
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
