@echo off
setlocal
set "OCO_SHARE_FILE=%~f0"
set "OCO_SHARE_TEST="
set "OCO_SHARE_ACTION="
if /I "%~1"=="--self-test" set "OCO_SHARE_TEST=1"
if /I "%~1"=="--check" set "OCO_SHARE_ACTION=C"
if /I "%~1"=="--apply" set "OCO_SHARE_ACTION=A"
if /I "%~1"=="--restore" set "OCO_SHARE_ACTION=R"
powershell.exe -NoProfile -Command "$s=[IO.File]::ReadAllText($env:OCO_SHARE_FILE);$marker=[Environment]::NewLine+'# === POWERSHELL ==='+[Environment]::NewLine;$i=$s.IndexOf($marker);if($i -lt 0){exit 1};& ([scriptblock]::Create($s.Substring($i+$marker.Length)))"
set "RC=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %RC%
# === POWERSHELL ===
$ErrorActionPreference='Stop'
$nl=[char]10
$utf=New-Object Text.UTF8Encoding($false,$true)
$names=@('verge.yaml','config.yaml','profiles\Merge.yaml','profiles\Script.js')
$merge=[Convert]::FromBase64String('IyBDbGFzaCBWZXJnZSBvcHRpbWl6YXRpb24gdjIuMiAvIE1paG9tbyAxLjE5LjMzDQojIEFwcGxpY2F0aW9uLW1hbmFnZWQgc2V0dGluZ3MgKFRVTiwgbW9kZSwgSVB2NiwgTEFOKSBhcmUgbm90IGZvcmNlZCBoZXJlLg0KdGNwLWNvbmN1cnJlbnQ6IHRydWUNCnByb2ZpbGU6DQogIHN0b3JlLXNlbGVjdGVkOiB0cnVlDQogIHN0b3JlLWZha2UtaXA6IHRydWUNCmRuczoNCiAgZW5hYmxlOiB0cnVlDQogIGVuaGFuY2VkLW1vZGU6IGZha2UtaXANCiAgZmFrZS1pcC1yYW5nZTogMTk4LjE4LjAuMS8xNg0KICBjYWNoZS1hbGdvcml0aG06IGFyYw0KICBwcmVmZXItaDM6IGZhbHNlDQogIHVzZS1ob3N0czogdHJ1ZQ0KICB1c2Utc3lzdGVtLWhvc3RzOiB0cnVlDQogIHJlc3BlY3QtcnVsZXM6IHRydWUNCiAgZGVmYXVsdC1uYW1lc2VydmVyOg0KICAgIC0gMjIzLjUuNS41DQogICAgLSAxMTkuMjkuMjkuMjkNCiAgcHJveHktc2VydmVyLW5hbWVzZXJ2ZXI6DQogICAgLSAyMjMuNS41LjUNCiAgICAtIDExOS4yOS4yOS4yOQ0KICBuYW1lc2VydmVyOg0KICAgIC0gaHR0cHM6Ly9kbnMuYWxpZG5zLmNvbS9kbnMtcXVlcnkNCiAgICAtIGh0dHBzOi8vZG9oLnB1Yi9kbnMtcXVlcnkNCiAgZmFsbGJhY2s6DQogICAgLSBodHRwczovL2Nsb3VkZmxhcmUtZG5zLmNvbS9kbnMtcXVlcnkNCiAgICAtIGh0dHBzOi8vZG5zLmdvb2dsZS9kbnMtcXVlcnkNCiAgZmFsbGJhY2stZmlsdGVyOg0KICAgIGdlb2lwOiB0cnVlDQogICAgZ2VvaXAtY29kZTogQ04NCiAgZmFsbGJhY2stbGF6eS1xdWVyeTogdHJ1ZQ0K')
$script=[Convert]::FromBase64String('Ly8gQ2xhc2ggVmVyZ2UgZ2xvYmFsIHNjcmlwdCB2Mi4zIC0gY29uc2VydmF0aXZlLCBpZGVtcG90ZW50Lg0KZnVuY3Rpb24gYXJyYXkodikgeyByZXR1cm4gQXJyYXkuaXNBcnJheSh2KSA/IHYgOiBbXTsgfQ0KZnVuY3Rpb24gb2JqKHYpIHsgcmV0dXJuIHYgJiYgdHlwZW9mIHYgPT09ICJvYmplY3QiICYmICFBcnJheS5pc0FycmF5KHYpID8gdiA6IHt9OyB9DQpmdW5jdGlvbiB1bmlxdWUodikgeyByZXR1cm4gQXJyYXkuZnJvbShuZXcgU2V0KGFycmF5KHYpLmZpbHRlcih4ID0+IHR5cGVvZiB4ID09PSAic3RyaW5nIiAmJiB4LnRyaW0oKSkpKTsgfQ0KZnVuY3Rpb24gbWFpbihjb25maWcsIHByb2ZpbGVOYW1lKSB7DQogIGlmICghY29uZmlnIHx8IHR5cGVvZiBjb25maWcgIT09ICJvYmplY3QiKSByZXR1cm4gY29uZmlnOw0KICAvLyBGaXJzdCBtYXRjaGluZyBydWxlIHdpbnMuIFJlbW92ZSBvbmx5IGV4YWN0IHJlcGVhdGVkIHN0cmluZ3MsIGtlZXAgb3JkZXIuDQogIGlmIChBcnJheS5pc0FycmF5KGNvbmZpZy5ydWxlcykpIHsNCiAgICBjb25zdCBzZWVuUnVsZXMgPSBuZXcgU2V0KCk7DQogICAgY29uZmlnLnJ1bGVzID0gY29uZmlnLnJ1bGVzLmZpbHRlcihydWxlID0+IHsNCiAgICAgIGlmICh0eXBlb2YgcnVsZSAhPT0gInN0cmluZyIpIHJldHVybiB0cnVlOw0KICAgICAgaWYgKHNlZW5SdWxlcy5oYXMocnVsZSkpIHJldHVybiBmYWxzZTsNCiAgICAgIHNlZW5SdWxlcy5hZGQocnVsZSk7DQogICAgICByZXR1cm4gdHJ1ZTsNCiAgICB9KTsNCiAgfQ0KDQogIGNvbnN0IGRucyA9IG9iaihjb25maWcuZG5zKTsNCiAgY29uc3QgcG9saWN5ID0gb2JqKGRuc1sibmFtZXNlcnZlci1wb2xpY3kiXSk7DQogIC8vIEtlZXAgZXhpc3RpbmcgZXhwbGljaXQgcG9saWNpZXM7IGFwcGVuZCBtaXNzaW5nIGRlZmF1bHRzIG9ubHkuDQogIGlmICghT2JqZWN0LnByb3RvdHlwZS5oYXNPd25Qcm9wZXJ0eS5jYWxsKHBvbGljeSwgImdlb3NpdGU6Y24iKSkNCiAgICBwb2xpY3lbImdlb3NpdGU6Y24iXSA9IFsiaHR0cHM6Ly9kbnMuYWxpZG5zLmNvbS9kbnMtcXVlcnkiLCAiaHR0cHM6Ly9kb2gucHViL2Rucy1xdWVyeSJdOw0KICBpZiAoIU9iamVjdC5wcm90b3R5cGUuaGFzT3duUHJvcGVydHkuY2FsbChwb2xpY3ksICJnZW9zaXRlOmdlb2xvY2F0aW9uLSFjbiIpKQ0KICAgIHBvbGljeVsiZ2Vvc2l0ZTpnZW9sb2NhdGlvbi0hY24iXSA9IFsiaHR0cHM6Ly9jbG91ZGZsYXJlLWRucy5jb20vZG5zLXF1ZXJ5IiwgImh0dHBzOi8vZG5zLmdvb2dsZS9kbnMtcXVlcnkiXTsNCiAgZG5zWyJuYW1lc2VydmVyLXBvbGljeSJdID0gcG9saWN5Ow0KICBjb25zdCBtb2RlID0gZG5zWyJmYWtlLWlwLWZpbHRlci1tb2RlIl0gfHwgImJsYWNrbGlzdCI7DQogIGlmIChkbnNbImVuaGFuY2VkLW1vZGUiXSA9PT0gImZha2UtaXAiICYmIG1vZGUgPT09ICJibGFja2xpc3QiKSB7DQogICAgZG5zWyJmYWtlLWlwLWZpbHRlciJdID0gdW5pcXVlKGFycmF5KGRuc1siZmFrZS1pcC1maWx0ZXIiXSkuY29uY2F0KFsNCiAgICAgICJsb2NhbGhvc3QiLCAiKy5sb2NhbGhvc3QiLCAiKy5sb2NhbCIsICIrLmxhbiIsICIrLmhvbWUuYXJwYSIsDQogICAgICAiKy5tc2Z0Y29ubmVjdHRlc3QuY29tIiwgIisubXNmdG5jc2kuY29tIiwgImNhcHRpdmUuYXBwbGUuY29tIiwNCiAgICAgICJ0aW1lLndpbmRvd3MuY29tIiwgInRpbWUuYXBwbGUuY29tIiwgIisucG9vbC5udHAub3JnIg0KICAgIF0pKTsNCiAgfQ0KICBjb25maWcuZG5zID0gZG5zOw0KDQogIGNvbnN0IGdyb3VwcyA9IGFycmF5KGNvbmZpZ1sicHJveHktZ3JvdXBzIl0pOw0KICBjb25zdCBwcm94aWVzID0gYXJyYXkoY29uZmlnLnByb3hpZXMpOw0KICBjb25zdCBwcm92aWRlcnMgPSBPYmplY3Qua2V5cyhvYmooY29uZmlnWyJwcm94eS1wcm92aWRlcnMiXSkpOw0KICBjb25zdCBBSSA9ICJBSS1cdTU2ZmFcdTViOWFcdTUxZmFcdTUzZTMiOw0KICBjb25zdCBURVNUID0gImh0dHBzOi8vY3AuY2xvdWRmbGFyZS5jb20vZ2VuZXJhdGVfMjA0IjsNCiAgLy8gT25seSBub3JtYWxpemUga25vd24gSFRUUCAyMDQgcHJvYmVzIG9yIG1pc3NpbmcgcHJvYmVzOyBwcmVzZXJ2ZSBjdXN0b20gVVJMcy4NCiAgY29uc3Qga25vd24gPSAvXmh0dHA6XC9cLyg/Ond3d1wuZ3N0YXRpY1wuY29tfGNwXC5jbG91ZGZsYXJlXC5jb218Y29ubmVjdGl2aXR5Y2hlY2tcLmdzdGF0aWNcLmNvbSlcL2dlbmVyYXRlXzIwNFwvPyQvaTsNCiAgZm9yIChjb25zdCBnIG9mIGdyb3Vwcykgew0KICAgIGlmICghZyB8fCAoZy50eXBlICE9PSAidXJsLXRlc3QiICYmIGcudHlwZSAhPT0gImZhbGxiYWNrIikpIGNvbnRpbnVlOw0KICAgIGlmICghZy51cmwgfHwga25vd24udGVzdChnLnVybCkpIHsNCiAgICAgIGcudXJsID0gVEVTVDsNCiAgICAgIGlmIChnWyJleHBlY3RlZC1zdGF0dXMiXSA9PSBudWxsKSBnWyJleHBlY3RlZC1zdGF0dXMiXSA9IDIwNDsNCiAgICB9DQogICAgLy8gQm91bmQgc3RhbGUgaGVhbHRoIGluZm9ybWF0aW9uIHdpdGhvdXQgYWdncmVzc2l2ZSBwb2xsaW5nLg0KICAgIC8vIEV4cGxpY2l0bHkgZGlzYWJsZWQgY2hlY2tzIChpbnRlcnZhbD0wKSBhbmQgc2hvcnRlciBpbnRlcnZhbHMgYXJlIHByZXNlcnZlZC4NCiAgICBjb25zdCBjZWlsaW5nID0gZy50eXBlID09PSAidXJsLXRlc3QiID8gMzYwMCA6IDE4MDA7DQogICAgaWYgKCFOdW1iZXIuaXNGaW5pdGUoZy5pbnRlcnZhbCkgfHwgZy5pbnRlcnZhbCA8IDApIGcuaW50ZXJ2YWwgPSBjZWlsaW5nOw0KICAgIGVsc2UgaWYgKGcuaW50ZXJ2YWwgPiBjZWlsaW5nKSBnLmludGVydmFsID0gY2VpbGluZzsNCiAgICBpZiAodHlwZW9mIGcubGF6eSAhPT0gImJvb2xlYW4iKSBnLmxhenkgPSB0cnVlOw0KICAgIGlmIChnLnR5cGUgPT09ICJ1cmwtdGVzdCIgJiYgIU51bWJlci5pc0Zpbml0ZShnLnRvbGVyYW5jZSkpIGcudG9sZXJhbmNlID0gMTAwOw0KICB9DQogIC8vIEtlZXAgcHJvdmlkZXIgaGVhbHRoLWNoZWNrIHNldHRpbmdzIGludGFjdC4NCiAgY29uc3QgcmVzZXJ2ZWQgPSBuZXcgU2V0KFsiRElSRUNUIiwgIlJFSkVDVCIsICJSRUpFQ1QtRFJPUCIsICJQQVNTIiwgIkNPTVBBVElCTEUiLCAiR0xPQkFMIiwgQUldKTsNCiAgY29uc3QgZ3JvdXBOYW1lcyA9IG5ldyBTZXQoZ3JvdXBzLmZpbHRlcihCb29sZWFuKS5tYXAoZyA9PiBnLm5hbWUpKTsNCiAgY29uc3QgaW5mbyA9IC9eKD86XHMqW1x1ezFGMzAwfS1cdXsxRkFGRn1cdTI2MDAtXHUyN0JGXHVGRTBGXSpccyopKD86XHU1MjY5XHU0ZjU5XHU2ZDQxXHU5MWNmfFx1NTk1N1x1OTkxMFx1NTIzMFx1NjcxZnxcdThkZGRcdTc5YmJcdTRlMGJcdTZiMjFcdTkxY2RcdTdmNmV8XHU2ZDQxXHU5MWNmXHU5MWNkXHU3ZjZlfFx1NTIzMFx1NjcxZlx1NjVmNlx1OTVmNHxcdTUyNjlcdTRmNTlcdTU5MjlcdTY1NzB8dHJhZmZpYyByZW1haW5pbmd8ZXhwaXJlIGRhdGUpXHMqWzpcdUZGMUFdL2l1Ow0KICBjb25zdCBub25Qcm94eVR5cGVzID0gbmV3IFNldChbImRpcmVjdCIsICJyZWplY3QiLCAicmVqZWN0LWRyb3AiLCAicGFzcyIsICJwYXNzLXJ1bGUiLCAiY29tcGF0aWJsZSJdKTsNCiAgY29uc3Qgbm9kZXMgPSB1bmlxdWUocHJveGllcy5maWx0ZXIocCA9PiBwICYmICFub25Qcm94eVR5cGVzLmhhcyhTdHJpbmcocC50eXBlIHx8ICIiKS50b0xvd2VyQ2FzZSgpKSkubWFwKHAgPT4gcC5uYW1lKSkuZmlsdGVyKG4gPT4gIXJlc2VydmVkLmhhcyhuKSAmJiAhZ3JvdXBOYW1lcy5oYXMobikgJiYgIWluZm8udGVzdChuKSk7DQogIC8vIE5ldmVyIGNyZWF0ZSBhbiBpbnZhbGlkIGdyb3VwIG9yIGZhbGwgYmFjayB0byBESVJFQ1QuDQogIGlmICgoIW5vZGVzLmxlbmd0aCAmJiAhcHJvdmlkZXJzLmxlbmd0aCkgfHwgcHJveGllcy5zb21lKHAgPT4gcCAmJiBwLm5hbWUgPT09IEFJKSB8fCBwcm92aWRlcnMuaW5jbHVkZXMoQUkpKSByZXR1cm4gY29uZmlnOw0KICAvLyBEbyBub3QgbW9kaWZ5IGEgZm9yZWlnbiwgbm9uLXNlbGVjdCBncm91cCB3aXRoIHRoZSBzYW1lIG5hbWUuDQogIGxldCBhaSA9IGdyb3Vwcy5maW5kKGcgPT4gZyAmJiBnLm5hbWUgPT09IEFJKTsNCiAgaWYgKGFpICYmIGFpLnR5cGUgIT09ICJzZWxlY3QiKSByZXR1cm4gY29uZmlnOw0KICBpZiAoIWFpKSB7DQogICAgYWkgPSB7bmFtZTogQUksIHR5cGU6ICJzZWxlY3QifTsNCiAgICBncm91cHMudW5zaGlmdChhaSk7DQogIH0NCiAgaWYgKG5vZGVzLmxlbmd0aCkgYWkucHJveGllcyA9IG5vZGVzOyBlbHNlIGRlbGV0ZSBhaS5wcm94aWVzOw0KICBpZiAocHJvdmlkZXJzLmxlbmd0aCkgYWkudXNlID0gcHJvdmlkZXJzOyBlbHNlIGRlbGV0ZSBhaS51c2U7DQogIC8vIE5ldmVyIHNpbGVudGx5IHVzZSB0aGUgZGVmYXVsdCBDT01QQVRJQkxFIHJvdXRlIHdoZW4gdGhlIEFJIGdyb3VwIGlzIGVtcHR5Lg0KICBhaVsiZW1wdHktZmFsbGJhY2siXSA9ICJSRUpFQ1QiOw0KICBkZWxldGUgYWlbImluY2x1ZGUtYWxsIl07DQogIGRlbGV0ZSBhaVsiaW5jbHVkZS1hbGwtcHJveGllcyJdOw0KICBkZWxldGUgYWlbImluY2x1ZGUtYWxsLXByb3ZpZGVycyJdOw0KICBjb25maWdbInByb3h5LWdyb3VwcyJdID0gZ3JvdXBzOw0KICBjb25zdCBkb21haW5zID0gWyJjaGF0Z3B0LmNvbSIsICJvcGVuYWkuY29tIiwgIm9haXN0YXRpYy5jb20iLCAib2FpdXNlcmNvbnRlbnQuY29tIiwgIm9haXN0YXRzaWcuY29tIiwgImNkbi5vcGVuYWltZXJnZS5jb20iLCAic29yYS5jb20iLCAiY2xhdWRlLmFpIiwgImFudGhyb3BpYy5jb20iLCAiY2xhdWRlLmNvbSIsICJjbGF1ZGV1c2VyY29udGVudC5jb20iLCAiZ2VtaW5pLmdvb2dsZS5jb20iLCAiYWlzdHVkaW8uZ29vZ2xlLmNvbSIsICJhaS5nb29nbGUuZGV2IiwgImdlbmVyYXRpdmVsYW5ndWFnZS5nb29nbGVhcGlzLmNvbSIsICJub3RlYm9va2xtLmdvb2dsZS5jb20iLCAibm90ZWJvb2tsbS5nb29nbGUiLCAiZGVlcG1pbmQuZ29vZ2xlIiwgImxhYnMuZ29vZ2xlIiwgImFpcGxhdGZvcm0uZ29vZ2xlYXBpcy5jb20iLCAiZ3Jvay5jb20iLCAieC5haSIsICJwZXJwbGV4aXR5LmFpIiwgIm1pc3RyYWwuYWkiLCAiY29waWxvdC5taWNyb3NvZnQuY29tIiwgImdpdGh1YmNvcGlsb3QuY29tIl07DQogIGNvbnN0IGFkZGVkID0gZG9tYWlucy5tYXAoZCA9PiAiRE9NQUlOLVNVRkZJWCwiICsgZCArICIsIiArIEFJKTsNCiAgY29uc3QgYWRkZWRTZXQgPSBuZXcgU2V0KGRvbWFpbnMpOw0KICBjb25maWcucnVsZXMgPSBhZGRlZC5jb25jYXQoYXJyYXkoY29uZmlnLnJ1bGVzKS5maWx0ZXIociA9PiB7DQogICAgaWYgKHR5cGVvZiByICE9PSAic3RyaW5nIikgcmV0dXJuIHRydWU7DQogICAgY29uc3QgcGFydHMgPSByLnNwbGl0KCIsIikubWFwKHggPT4geC50cmltKCkpOw0KICAgIHJldHVybiAhKHBhcnRzLmxlbmd0aCA9PT0gMyAmJiBwYXJ0c1swXS50b1VwcGVyQ2FzZSgpID09PSAiRE9NQUlOLVNVRkZJWCIgJiYNCiAgICAgIGFkZGVkU2V0LmhhcyhwYXJ0c1sxXS50b0xvd2VyQ2FzZSgpKSAmJiBwYXJ0c1syXSA9PT0gQUkpOw0KICB9KSk7DQogIHJldHVybiBjb25maWc7DQp9DQo=')
$blankMerge='# Profile Enhancement Merge Template for Clash Verge'
$blankScript=("// Define main function (script entry)"+$nl+$nl+"function main(config, profileName) {"+$nl+"  return config;"+$nl+"}")
function ReadText($p){$utf.GetString([IO.File]::ReadAllBytes($p)).TrimStart([char]0xFEFF).Replace(([string][char]13+[char]10),[string][char]10)}
function Digest([byte[]]$b){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($b))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Plain($p){$i=Get-Item -LiteralPath $p -ErrorAction Stop;while($i){if($i.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse path refused'};$i=if($i -is [IO.FileInfo]){$i.Directory}else{$i.Parent}}}
function Scalar([string]$s,[string]$k,[string]$value,[string]$indent=''){
 $m=[regex]::Matches($s,'(?m)^'+[regex]::Escape($indent+$k)+':[ \t]*(?<v>[^\n]*)$')
 if($m.Count -gt 1){throw "Duplicate key: $k"}
 if($m.Count -eq 1){
  if($m[0].Groups['v'].Value -notmatch '^(true|false|null|~|-?[0-9]+|[A-Za-z0-9_-]+)$'){throw "Unsupported scalar: $k"}
  return $s.Substring(0,$m[0].Index)+$indent+$k+': '+$value+$s.Substring($m[0].Index+$m[0].Length)
 }
 return $s.TrimEnd([char]10)+$nl+$indent+$k+': '+$value+$nl
}
function Plan($root){
 foreach($n in $names){$p=Join-Path $root $n;Plain $p;if((Get-Item -LiteralPath $p).Length -gt 1048576){throw 'File too large'}}
 $m=Join-Path $root $names[2];$s=Join-Path $root $names[3]
 if((Digest ([IO.File]::ReadAllBytes($m))) -ne (Digest $merge) -and (ReadText $m).Trim() -notin @('',$blankMerge,'{}')){throw 'Existing custom global Merge; no change'}
 if((Digest ([IO.File]::ReadAllBytes($s))) -ne (Digest $script) -and (ReadText $s).Trim() -cne $blankScript){throw 'Existing custom global Script; no change'}
 $v=ReadText (Join-Path $root $names[0]);$c=ReadText (Join-Path $root $names[1])
 foreach($z in @($v,$c)){if($z -match '(?m)^(---|\.\.\.|%YAML|[ \t]*<<:)' -or $z -match '(?m)^[ \t]*\t'){throw 'Unsupported YAML shape'}}
 $dm=[regex]::Match($v,'(?m)^profile_dns_settings:[ \t]*(?<value>[^\n]*)')
 if($dm.Success -and $dm.Groups['value'].Value.Trim() -notin @('{}','null','~')){throw 'Existing per-profile DNS overrides; review manually before applying'}
 foreach($z in @($v,$c)){
  $keys=@([regex]::Matches($z,'(?m)^([A-Za-z0-9_-]+):')|ForEach-Object {$_.Groups[1].Value})
  if(@($keys|Sort-Object -Unique).Count -ne $keys.Count){throw 'Duplicate top-level YAML key'}
  if($z -match '(?m)^[^ \t#\r\nA-Za-z0-9_-]'){throw 'Unsupported top-level YAML syntax'}
 }
 $vs=[ordered]@{traffic_graph='false';enable_memory_usage='false';enable_auto_light_weight_mode='true';auto_light_weight_minutes='10';enable_hover_jump_navigator='false';enable_auto_delay_detection='false';enable_builtin_enhanced='true';enable_external_controller='false';enable_dns_settings='false'}
 $cs=[ordered]@{mode='rule';'log-level'='warning';ipv6='false';'allow-lan'='false';'unified-delay'='true'}
 foreach($k in $vs.Keys){$v=Scalar $v $k $vs[$k]}
 foreach($k in $cs.Keys){$c=Scalar $c $k $cs[$k]}
 $ms=[regex]::Matches($c,'(?m)^tun:[ \t]*\n(?:[ \t][^\n]*\n|[ \t][^\n]*$)*')
 if($ms.Count -ne 1){throw 'Unsupported TUN mapping'}
 $b=$ms[0].Value
 $ts=[ordered]@{stack='gvisor';mtu='9000';'auto-route'='true';'strict-route'='false';'auto-detect-interface'='true'}
 foreach($k in $ts.Keys){$b=Scalar $b $k $ts[$k] '  '}
 $c=$c.Substring(0,$ms[0].Index)+$b+$c.Substring($ms[0].Index+$ms[0].Length)
 $new=@{'verge.yaml'=$utf.GetBytes($v);'config.yaml'=$utf.GetBytes($c);'profiles\Merge.yaml'=$merge;'profiles\Script.js'=$script}
 foreach($n in $names){
  $p=Join-Path $root $n;$old=[IO.File]::ReadAllBytes($p);$after=Digest $new[$n];$before=Digest $old
  if($before -ne $after){[pscustomobject]@{Name=$n;Target=$p;Old=$old;New=$new[$n];Before=$before;After=$after}}
 }
}
function Put($p,[byte[]]$b,$expected){
 Plain $p
 if((Digest ([IO.File]::ReadAllBytes($p))) -ne $expected){throw 'Target changed'}
 $tmp=$p+'.oco-'+[guid]::NewGuid().ToString('N')
 try{
  $f=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
  if((Digest ([IO.File]::ReadAllBytes($p))) -ne $expected){throw 'Target changed'}
  [IO.File]::Replace($tmp,$p,($tmp+".swap"));if((Digest ([IO.File]::ReadAllBytes($p))) -ne (Digest $b)){throw "Readback failed"};Remove-Item -LiteralPath ($tmp+".swap") -Force
  if((Digest ([IO.File]::ReadAllBytes($p))) -ne (Digest $b)){throw 'Readback failed'}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function PrivateDir($p){
 if(Test-Path -LiteralPath $p){throw 'Backup already exists'}
 New-Item -ItemType Directory -Path $p|Out-Null
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
 foreach($id in @($sid,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),(New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))){
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($id,'FullControl','ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)
 }
 Set-Acl -LiteralPath $p -AclObject $acl;Plain $p
}
function State($p,$s){[IO.File]::WriteAllText((Join-Path $p 'state.txt'),$s,$utf)}
function Restore($root,$backup){
 Plain $backup;$m=ConvertFrom-Json (ReadText (Join-Path $backup 'manifest.json'))
 if($m.Root -ine $root){throw 'Backup target mismatch'}
 foreach($row in $m.Files){
  if($row.Name -cnotin $names -or $row.File -cne (($row.Name -replace '[\\/]','_')+'.original')){throw 'Invalid backup'}
  $p=Join-Path $root $row.Name;Plain $p;$f=Join-Path $backup $row.File;Plain $f
  if((Digest ([IO.File]::ReadAllBytes($f))) -ne $row.Before -or (Digest ([IO.File]::ReadAllBytes($p))) -notin @($row.Before,$row.After)){throw 'Later edit or damaged backup; refuse restore'}
 }
 State $backup 'RESTORING'
 for($i=$m.Files.Count-1;$i -ge 0;$i--){
  $row=$m.Files[$i];$p=Join-Path $root $row.Name
  if((Digest ([IO.File]::ReadAllBytes($p))) -eq $row.After){Put $p ([IO.File]::ReadAllBytes((Join-Path $backup $row.File))) $row.After}
 }
 State $backup 'RESTORED'
}
function Apply($root,$backup,$rows){
 PrivateDir $backup;$m=@()
 foreach($row in $rows){
  $n=($row.Name -replace '[\\/]','_')+'.original';$p=Join-Path $backup $n
  [IO.File]::WriteAllBytes($p,$row.Old)
  if((Digest ([IO.File]::ReadAllBytes($p))) -ne $row.Before){throw 'Backup failed'}
  $m+= [pscustomobject]@{Name=$row.Name;File=$n;Before=$row.Before;After=$row.After}
 }
 [IO.File]::WriteAllText((Join-Path $backup 'manifest.json'),(@{Root=$root;Files=$m}|ConvertTo-Json -Depth 5),$utf)
 State $backup 'PENDING'
 try{foreach($row in $rows){Put $row.Target $row.New $row.Before};State $backup 'STAGED'}
 catch{$failure=$_;try{Restore $root $backup}catch{Write-Warning "Recovery incomplete: $backup"};throw $failure}
}
function Stopped{if(Get-Process clash-verge,verge-mihomo,verge-mihomo-alpha -ErrorAction SilentlyContinue){throw 'Quit Clash normally from its tray menu first; no change.'}}
function TestLocal{
 $r=Join-Path ([IO.Path]::GetTempPath()) ('oco-share-test-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path (Join-Path $r 'profiles')|Out-Null
 try{
  [IO.File]::WriteAllText((Join-Path $r 'verge.yaml'),(('traffic_graph: true','enable_tun_mode: false','enable_system_proxy: false','profile_dns_settings: {}','') -join $nl),$utf)
  [IO.File]::WriteAllText((Join-Path $r 'config.yaml'),(('secret: fixture-only','mode: rule','log-level: info','ipv6: true','tun:','  enable: false','  stack: system','  dns-hijack:','  - any:53','external-controller: null','') -join $nl),$utf)
  [IO.File]::WriteAllText((Join-Path $r $names[2]),$blankMerge+$nl,$utf)
  [IO.File]::WriteAllText((Join-Path $r $names[3]),$blankScript+$nl,$utf)
  $rows=@(Plan $r);if($rows.Count -ne 4){throw 'Fixture plan failed'}
  $backup=Join-Path $r 'backup';Apply $r $backup $rows
  if(@(Plan $r).Count -ne 0){throw 'Idempotence failed'}
  $cfg=ReadText (Join-Path $r 'config.yaml')
  if($cfg -notmatch '(?m)^  mtu: 9000$' -or $cfg -notmatch '(?m)^secret: fixture-only$' -or $cfg -notmatch '(?m)^  enable: false$'){throw 'Fixture mismatch'}
  Restore $r $backup
  foreach($row in $rows){if((Digest ([IO.File]::ReadAllBytes($row.Target))) -ne $row.Before){throw 'Restore failed'}}
  [IO.File]::WriteAllText((Join-Path $r $names[3]),'custom script',$utf)
  $refused=$false;try{$null=@(Plan $r)}catch{$refused=$true};if(!$refused){throw 'Custom script accepted'}
  [IO.File]::WriteAllText((Join-Path $r $names[3]),$blankScript+$nl,$utf)
  $vf=Join-Path $r 'verge.yaml';$v0=[IO.File]::ReadAllBytes($vf)
  [IO.File]::WriteAllText($vf,(ReadText $vf)+'traffic_graph: false'+$nl,$utf)
  $refused=$false;try{$null=@(Plan $r)}catch{$refused=$true};if(!$refused){throw 'Duplicate key accepted'}
  [IO.File]::WriteAllBytes($vf,$v0)
  [IO.File]::WriteAllText($vf,(ReadText $vf).Replace('profile_dns_settings: {}','profile_dns_settings:'+$nl+'  fixture:'+$nl+'    enabled: true'),$utf)
  $refused=$false;try{$null=@(Plan $r)}catch{$refused=$true};if(!$refused){throw 'Profile DNS conflict accepted'}
  [IO.File]::WriteAllBytes($vf,$v0)
  $rows=@(Plan $r);$b2=Join-Path $r 'backup2';Apply $r $b2 $rows
  [IO.File]::AppendAllText($vf,'unrelated_edit: true'+$nl,$utf)
  $refused=$false;try{Restore $r $b2}catch{$refused=$true};if(!$refused){throw 'Later edit overwritten'}
  [IO.File]::WriteAllBytes($vf,($rows|Where-Object Name -eq 'verge.yaml').New)
  State $b2 'PENDING';Restore $r $b2
  foreach($row in $rows){if((Digest ([IO.File]::ReadAllBytes($row.Target))) -ne $row.Before){throw 'Pending restore failed'}}
  Write-Host 'SELFTEST PASS: plan, apply, repeat, restore, custom/duplicate/profile DNS refusal, later-edit refusal, pending restore.'
 }finally{Remove-Item -LiteralPath $r -Recurse -Force}
}
$mutex=$null;$locked=$false
try{
 if($env:OCO_SHARE_TEST -eq '1'){TestLocal;exit 0}
 Write-Host 'Clash Verge Rev - OneClick configuration v1.4.0-rc.1 (Windows 2.5.10)'
 Write-Host 'No private subscription, credentials or node selections included.'
 Write-Host 'DNS preset and AI rules will change. TUN/system proxy activation stays manual; existing per-profile overrides are not migrated.'
 $root=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev';Plain $root
 $mutex=New-Object Threading.Mutex($false,'Local\OCO-Clash-Share-Config');$locked=$mutex.WaitOne(0);if(!$locked){throw 'Another instance is running'}
 $br=Join-Path $env:LOCALAPPDATA 'OCO-Clash-Share-Backups'
 $action=$env:OCO_SHARE_ACTION
 if(!$action){$action=Read-Host 'C = 只读检查，A = 一键配置，R = 恢复，Q = 退出'}
 if($action -notin @('C','A','R')){exit 0}
 if($action -ne 'C'){Stopped}
 if(Test-Path -LiteralPath $br){Plain $br}
 if($action -eq 'R'){
  if(!(Test-Path -LiteralPath $br)){throw 'No backups'}
  $dirs=@(Get-ChildItem -LiteralPath $br -Directory|Where-Object {Test-Path (Join-Path $_.FullName 'manifest.json')}|Sort-Object Name -Descending)
  if(!$dirs.Count){throw 'No backups'}
  for($i=0;$i -lt $dirs.Count;$i++){Write-Host ($i+1) $dirs[$i].Name}
  $choice=Read-Host '请选择备份编号';$n=0;if(![int]::TryParse($choice,[ref]$n) -or $n -lt 1 -or $n -gt $dirs.Count){throw 'Invalid choice'}
  Stopped;Restore $root $dirs[$n-1].FullName;Write-Host 'RESTORED. Start Clash and reactivate your subscription.';exit 0
 }
 if($action -eq 'A' -and (Test-Path -LiteralPath $br) -and @(Get-ChildItem -LiteralPath $br -Directory|Where-Object {(Test-Path (Join-Path $_.FullName 'state.txt')) -and (ReadText (Join-Path $_.FullName 'state.txt')) -notin @('STAGED','RESTORED')}).Count){throw 'Interrupted transaction: restore first'}
 $apps=@()
 foreach($base in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),(Join-Path $env:LOCALAPPDATA 'Programs'))){if($base){foreach($sub in @('Clash Verge','Clash Verge Rev','clash-verge')){$apps+=Join-Path (Join-Path $base $sub) 'clash-verge.exe'}}}
 foreach($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')){
  $apps+=@(Get-ItemProperty $key -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -match '^Clash Verge' -and $_.InstallLocation}|ForEach-Object {Join-Path $_.InstallLocation 'clash-verge.exe'})
 }
 $apps=@($apps|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf}|Sort-Object -Unique)
 $app=if($apps.Count -eq 1){$apps[0]}else{(Read-Host '请输入 clash-verge.exe 完整路径').Trim('"')}
 Plain $app
 if([IO.Path]::GetFileName($app) -ine 'clash-verge.exe' -or (Get-Item -LiteralPath $app).VersionInfo.ProductVersion -ne '2.5.10'){throw 'Unsupported version'}
 $core=Join-Path (Split-Path -Parent $app) 'verge-mihomo.exe';Plain $core
 $ver=(& $core -v|Out-String);if($LASTEXITCODE -or $ver -notmatch '\bv1\.19\.33\b'){throw 'Unsupported bundled core'}
 $rows=@(Plan $root)
 if(!$rows.Count){Write-Host 'NO_CHANGE';exit 0}
 Write-Host 'Files to update:';foreach($row in $rows){Write-Host $row.Name}
 if($action -eq 'C'){Write-Host 'CHECK_ONLY: proposed changes; no user files written.';exit 0}
 if((Read-Host '输入 APPLY 确认应用') -cne 'APPLY'){exit 0}
 Stopped
 $again=@(Plan $root);if((($again|ForEach-Object {$_.Name+':'+$_.Before+':'+$_.After}) -join ';') -cne (($rows|ForEach-Object {$_.Name+':'+$_.Before+':'+$_.After}) -join ';')){throw 'Plan changed; retry'}
 if(!(Test-Path -LiteralPath $br)){New-Item -ItemType Directory -Path $br|Out-Null};Plain $br
 $backup=Join-Path $br ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 Apply $root $backup $rows
 Write-Host "STAGED. Backup: $backup"
 Write-Host 'Start Clash, import/reactivate YOUR subscription, choose YOUR AI node and check connectivity.'
 Write-Host 'Enable system proxy/TUN manually if needed. Identical performance is not guaranteed.'
 Write-Host 'If problems: quit Clash and run this file again with R. Later edits are not overwritten.'
 exit 2
}catch{Write-Host ('STOPPED: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally{if($locked){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}

<#
MIT License

Copyright (c) 2026 Kitty-Carter

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

#>
