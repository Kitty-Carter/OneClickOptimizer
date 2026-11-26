Set-StrictMode -Version 2.0
function Get-OcoModule([string]$Root) {
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $Root 'modules') -Directory | Sort-Object Name)) {
        $path=Join-Path $dir.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $m=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($m.schemaVersion -ne 1 -or $m.id -cne $dir.Name -or $m.id -cnotmatch '^[a-z0-9-]+$' -or $m.entry -cnotmatch '^[A-Za-z0-9_-]+\.ps1$') { throw "Invalid module manifest: $path" }
        $entry=Join-Path $dir.FullName $m.entry
        if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Missing module entry: $entry" }
        [pscustomobject]@{Id=$m.id;Name=$m.name;Version=$m.version;Modes=@($m.modes);Entry=$entry;Status=$m.status}
    }
}
Export-ModuleMember -Function Get-OcoModule
