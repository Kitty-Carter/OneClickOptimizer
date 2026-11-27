[CmdletBinding()]
param([switch]$SelfTest,[switch]$Sample,[switch]$SmokeTest,[switch]$Lite,[ValidateRange(1000,10000)][int]$IntervalMs=2000)
$ErrorActionPreference='Stop'
try {
 Add-Type -AssemblyName System.Windows.Forms,System.Drawing
 Add-Type -Path (Join-Path $PSScriptRoot 'Monitor.cs') -ReferencedAssemblies @('System.dll','System.Core.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Management.dll')
 if($SelfTest){[Oco.ClashMonitor.Entry]::SelfTest();exit 0}
 $physical=@()
 try{$physical=@(Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {"$($_.InterfaceGuid)"})}catch{Write-Warning 'Physical classification unavailable; other interfaces remain unclassified.'}
 if($Sample){
  $s=New-Object Oco.ClashMonitor.Sampler -ArgumentList @([string[]]$physical,(-not $Lite))
  $null=$s.Take();Start-Sleep -Milliseconds $IntervalMs;$v=$s.Take()
  [pscustomobject]@{CPU=$v.Cpu;RAM=$v.Memory;DiskNonIdle=$v.DiskBusy;GPUBusiestEngine=$v.GpuEngine;Battery=$v.Battery;CoreCount=$v.CoreCount;CoreWorkingSetMiB=[math]::Round($v.CoreWorkingSet/1MB,1);CorePrivateMiB=[math]::Round($v.CorePrivate/1MB,1);Adapters=$v.Adapters.Count;Physical=@($v.Adapters|Where-Object Kind -eq 'Physical').Count;TunnelCandidates=@($v.Adapters|Where-Object Kind -eq 'Tunnel candidate').Count}|ConvertTo-Json
  exit 0
 }
 [Oco.ClashMonitor.Entry]::Run([string[]]$physical,$IntervalMs,[bool]$SmokeTest,(-not $Lite))
 if($SmokeTest){Write-Host 'MONITOR_GUI_SMOKE_OK'}
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
