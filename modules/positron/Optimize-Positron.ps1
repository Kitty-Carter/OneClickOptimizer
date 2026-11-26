#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$SelfTest,
    [string]$InstallPath,
    [string]$UserDataDir,
    [string]$SettingsPath,
    [string]$BackupRoot
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Say([string]$Message, [string]$Color = 'Gray') { Write-Host $Message -ForegroundColor $Color }
function Read-TextFile([string]$Path) {
    $reader = New-Object IO.StreamReader($Path, (New-Object Text.UTF8Encoding($false,$true)), $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
}

# Resolve the Windows Downloads known folder, including redirected paths.
function Get-DownloadsFolder {
    $guid = '{374DE290-123F-4565-9164-39C4925E467B}'
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.NameSpace("shell:::$guid")
        if ($null -ne $folder) {
            $p = $folder.Self.Path
            if ($p -and (Test-Path -LiteralPath $p -PathType Container)) { return $p }
        }
    } catch {}
    $redirected = $false
    foreach ($reg in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')) {
        try {
            $p = (Get-ItemProperty -LiteralPath $reg -Name $guid).$guid
            $p = [Environment]::ExpandEnvironmentVariables([string]$p)
            if ($p) { $redirected = $true; if (Test-Path -LiteralPath $p -PathType Container) { return $p } }
        } catch {}
    }
    if ($redirected) { return $null }
    $p = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $p -PathType Container) { return $p }
    return $null
}

function Find-Positron([string]$Downloads, [string]$Override) {
    $found = New-Object 'System.Collections.Generic.List[object]'
    function Add-Candidate([string]$Path, [string]$Source) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try {
            $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
            if (Test-Path -LiteralPath $p -PathType Container) { $p = Join-Path $p 'Positron.exe' }
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return }
            $p = (Get-Item -LiteralPath $p).FullName
            if ([IO.Path]::GetFileName($p) -ine 'Positron.exe') { return }
            $root = Split-Path -Parent $p
            if (-not (Test-Path -LiteralPath (Join-Path $root 'resources\app\package.json') -PathType Leaf)) { return }
            if (@($found | Where-Object { $_.Exe -ieq $p }).Count -eq 0) {
                $found.Add([pscustomobject]@{Exe=$p; Root=$root; Source=$Source})
            }
        } catch {}
    }
    if ($Override) {
        Add-Candidate $Override 'manual'
        if ($found.Count -eq 0) { throw '指定的位置不是有效的 Positron 安装目录或 Positron.exe。' }
        return $found[0]
    }
    foreach ($p in @(Get-Process -Name Positron -ErrorAction SilentlyContinue)) {
        try { Add-Candidate $p.Path 'running process' } catch {}
    }
    # Running installation is authoritative if unique; avoid stale registry entries.
    if ($found.Count -eq 1) { return $found[0] }
    $registryRoots = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($entry in @(Get-ItemProperty -Path $registryRoots -ErrorAction SilentlyContinue)) {
        $name = $entry.PSObject.Properties['DisplayName']
        if ($null -eq $name -or [string]$name.Value -notmatch '^Positron(?:\s|$)') { continue }
        foreach ($field in @('InstallLocation','DisplayIcon')) {
            $prop = $entry.PSObject.Properties[$field]
            if ($null -eq $prop -or -not $prop.Value) { continue }
            $value = [string]$prop.Value
            if ($field -eq 'DisplayIcon') { $value = $value -replace ',\s*-?\d+\s*$','' }
            Add-Candidate $value 'uninstall registry'
        }
    }
    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { Add-Candidate (Join-Path $base 'Positron') 'standard install'; Add-Candidate (Join-Path $base 'Programs\Positron') 'standard install' }
    }
    foreach ($command in @(Get-Command positron,positron.exe -All -ErrorAction SilentlyContinue)) {
        if ($command.CommandType -eq 'Application' -or $command.CommandType -eq 'ExternalScript') {
            Add-Candidate $command.Source 'PATH'
            $dir = Split-Path -Parent $command.Source
            Add-Candidate $dir 'PATH'; Add-Candidate (Split-Path -Parent $dir) 'PATH'
        }
    }
    # Inspect existing shortcuts; do not launch them.
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcutRoots = @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('CommonPrograms'),[Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))
        foreach ($dir in $shortcutRoots) {
            if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
                foreach ($lnk in @(Get-ChildItem -LiteralPath $dir -Filter '*Positron*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
                    try { Add-Candidate ($wsh.CreateShortcut($lnk.FullName).TargetPath) 'shortcut' } catch {}
                }
            }
        }
    } catch {}
    if ($Downloads) {
        Add-Candidate $Downloads 'Downloads'
        foreach ($dir in @(Get-ChildItem -LiteralPath $Downloads -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match 'positron'})) {
            Add-Candidate $dir.FullName 'Downloads'
            foreach ($sub in @(Get-ChildItem -LiteralPath $dir.FullName -Directory -ErrorAction SilentlyContinue)) { Add-Candidate $sub.FullName 'Downloads' }
        }
    }
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Say '检测到多个安装，请选择要优化的版本：' Yellow
        for ($i=0;$i -lt $found.Count;$i++) { Say ('  [{0}] {1} ({2})' -f ($i+1),$found[$i].Exe,$found[$i].Source) }
        $answer = Read-Host '输入编号（回车取消）'
        $index = 0
        if ([int]::TryParse($answer,[ref]$index) -and $index -ge 1 -and $index -le $found.Count) { return $found[$index-1] }
        throw '已取消，未修改设置。'
    }
    Say '未找到已安装的 Positron。可能位于自定义目录，或只有安装包。' Yellow
    $manual = Read-Host '请粘贴 Positron.exe 或其安装文件夹的完整路径（回车取消）'
    if (-not $manual) { throw '未找到有效安装，未修改设置。' }
    Add-Candidate $manual 'manual'
    if ($found.Count -ne 1) { throw '路径无效，未修改设置。' }
    return $found[0]
}

function Get-SettingsLocation($Installation, [string]$DataOverride, [string]$FileOverride) {
    if ($FileOverride) {
        $explicit=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($FileOverride.Trim('"')))
        if ([IO.Path]::GetFileName($explicit) -ine 'settings.json') { throw '必须指定名为 settings.json 的配置文件。' }
        return $explicit
    }
    if ($DataOverride) { return Join-Path ([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DataOverride.Trim('"')))) 'User\settings.json' }
    $portable = Join-Path $Installation.Root 'data'
    $running = @()
    try { $running = @(Get-CimInstance Win32_Process -Filter "Name = 'Positron.exe'" -ErrorAction Stop | Where-Object { $_.ExecutablePath -ieq $Installation.Exe }) } catch { Say '无法读取进程启动参数；如使用自定义用户数据目录，请用 -UserDataDir 指定。' Yellow }
    $custom = @()
    $profileFlag = $false
    foreach ($p in $running) {
        $cmd = [string]$p.CommandLine
        if ($cmd -match '(?:^|\s)--profile(?:=|\s)') { $profileFlag = $true }
        $m = [regex]::Match($cmd,'(?:^|\s)(?:"--user-data-dir=([^"]+)"|--user-data-dir(?:=|\s+)(?:"([^"]+)"|([^\s"]+)))')
        if ($m.Success) {
            $v = if ($m.Groups[1].Success) {$m.Groups[1].Value} elseif ($m.Groups[2].Success) {$m.Groups[2].Value} else {$m.Groups[3].Value}
            if (-not [IO.Path]::IsPathRooted($v)) { throw '检测到相对 user-data-dir，请使用 -UserDataDir 指定完整路径。' }
            $custom += [IO.Path]::GetFullPath($v)
        }
    }
    $custom = @($custom | Sort-Object -Unique)
    if ($custom.Count -gt 1) { throw '检测到多个用户数据目录，请使用 -UserDataDir 指定目标。' }
    if ($profileFlag) { throw '检测到自定义 Profile，请使用 -SettingsPath 明确指定活动 Profile 配置文件。' }
    if ($custom.Count -eq 1) { return Join-Path $custom[0] 'User\settings.json' }
    if (Test-Path -LiteralPath $portable -PathType Container) { return Join-Path $portable 'user-data\User\settings.json' }
    return Join-Path $env:APPDATA 'Positron\User\settings.json'
}

# Locate configuration schemas in the installed application and its extensions.
function Get-ConfigurationPlan($Installation, [string]$Settings) {
    $app = Join-Path $Installation.Root 'resources\app'
    $workbench = Join-Path $app 'out\vs\workbench\workbench.desktop.main.js'
    $wb = if (Test-Path -LiteralPath $workbench -PathType Leaf) { Read-TextFile $workbench } else { '' }
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rSchema = Join-Path $app 'extensions\positron-r\package.json'
    $extensionRoots = @((Join-Path $app 'extensions'),(Join-Path $env:USERPROFILE '.positron\extensions'),(Join-Path $Installation.Root 'data\extensions'))
    # Also inspect an explicitly selected user-data directory's extensions, if present.
    $settingsUser = Split-Path -Parent $Settings
    if ((Split-Path -Leaf $settingsUser) -eq 'User') { $extensionRoots += (Join-Path (Split-Path -Parent $settingsUser) 'extensions') }
    $manifests = @($rSchema)
    foreach ($root in $extensionRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            foreach ($ext in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match 'quarto|positron-r$'})) {
                $manifests += (Join-Path $ext.FullName 'package.json')
            }
        }
    }
    foreach ($manifest in @($manifests | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        try {
            $text = Read-TextFile $manifest
            $j = $text | ConvertFrom-Json
            $contrib = $j.PSObject.Properties['contributes']
            if ($null -eq $contrib) { continue }
            $cfg = $contrib.Value.PSObject.Properties['configuration']
            if ($null -eq $cfg) { continue }
            foreach ($c in @($cfg.Value)) {
                $props = $c.PSObject.Properties['properties']
                if ($null -ne $props) { foreach ($p in $props.Value.PSObject.Properties) { [void]$known.Add($p.Name) } }
            }
        } catch { Say ('无法读取扩展配置定义：'+$manifest) Yellow }
    }
    $desired = [ordered]@{
        'quarto.symbols.showCodeCellsInOutline' = $false
        'editor.rulers' = @()
        'editor.mouseWheelZoom' = $true
        'packages.r.installer' = 'base'
        'quarto.inlineOutput.enabled' = $false
        'console.showNotebookConsoles' = $true
    }
    $plan = [ordered]@{}
    $skipped = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in $desired.Keys) {
        # editor.* is a standard VS Code editor setting. For other settings require local evidence.
        $has = $known.Contains($key) -or ($wb.IndexOf('"'+$key+'"',[StringComparison]::Ordinal) -ge 0)
        if ($key -eq 'packages.r.installer' -and -not ($wb -match '"packages\.r\.installer"\s*:\s*\{[^}]*"base"') -and -not $known.Contains($key)) { $has = $false }
        if ($has -or $key -in @('editor.rulers','editor.mouseWheelZoom')) { $plan[$key] = $desired[$key] }
        else { $skipped.Add($key) }
    }
    if ($known.Contains('positron.r.diagnostics.enabled')) { $plan['positron.r.diagnostics.enabled'] = $false }
    elseif ($known.Contains('positron.r.diagnostics.enable')) { $plan['positron.r.diagnostics.enable'] = $false }
    else { $skipped.Add('positron.r.diagnostics.enabled / enable') }
    return [pscustomobject]@{Values=$plan; Skipped=@($skipped.ToArray())}
}

# A JSONC token scanner: no regex replacement inside strings; preserve unrelated
# values, comments and layout. Refuse malformed or ambiguous top-level keys.
function Get-JsoncDocument([string]$Text) {
    $pattern = '\G(?:\s+|//[^\r\n]*|/\*[\s\S]*?\*/|"(?:[^"\\\x00-\x1F]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|[{}\[\]:,]|true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)'
    $matches = [regex]::Matches($Text,$pattern)
    $tokens = New-Object 'System.Collections.Generic.List[object]'
    $end=0
    foreach ($m in $matches) {
        if ($m.Index -ne $end) { throw 'JSONC 含无法识别的内容，已停止。' }
        $end=$m.Index+$m.Length
        if ($m.Value -match '^\s' -or $m.Value.StartsWith('//') -or $m.Value.StartsWith('/*')) { continue }
        $tokens.Add($m)
    }
    if ($end -ne $Text.Length -or $tokens.Count -lt 2 -or $tokens[0].Value -ne '{' -or $tokens[$tokens.Count-1].Value -ne '}') { throw 'settings.json 必须是有效的 JSON/JSONC 对象。' }
    $normalized = New-Object Text.StringBuilder
    for ($i=0;$i -lt $tokens.Count;$i++) {
        if ($tokens[$i].Value -eq ',' -and $i+1 -lt $tokens.Count -and $tokens[$i+1].Value -in @('}',']')) { continue }
        [void]$normalized.Append($tokens[$i].Value)
        # Space prevents adjacent invalid literals from turning into a different value.
        [void]$normalized.Append(' ')
    }
    $parsed = $normalized.ToString() | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $parsed -or $parsed -isnot [pscustomobject]) { throw '配置根节点不是对象。' }
    $props = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $i=1; $lastValueEnd=-1; $trailing=$false; $close=$tokens.Count-1
    while ($i -lt $close) {
        $kt=$tokens[$i]
        if (-not $kt.Value.StartsWith('"') -or $i+2 -ge $tokens.Count -or $tokens[$i+1].Value -ne ':') { throw 'JSONC 顶层属性格式不正确。' }
        $key = [string](('['+$kt.Value+']') | ConvertFrom-Json)
        if ($props.ContainsKey($key)) { throw ('重复或大小写冲突的配置键：'+$key) }
        $i+=2; $start=$tokens[$i].Index; $depth=0; $valueEnd=-1
        while ($i -lt $tokens.Count) {
            $v=$tokens[$i].Value
            if ($depth -eq 0 -and $v -in @(',','}')) { break }
            if ($v -in @('{','[')) { $depth++ } elseif ($v -in @('}',']')) { $depth-- }
            if ($depth -lt 0) { throw 'JSONC 括号不匹配。' }
            $valueEnd=$tokens[$i].Index+$tokens[$i].Length; $i++
        }
        if ($depth -ne 0 -or $valueEnd -le $start -or $i -gt $close) { throw 'JSONC 配置值不完整。' }
        $props.Add($key,[pscustomobject]@{Start=$start; End=$valueEnd; Key=$key})
        $lastValueEnd=$valueEnd; $trailing=$false
        if ($i -lt $close) {
            if ($tokens[$i].Value -ne ',') { throw 'JSONC 缺少分隔逗号。' }
            $i++; $trailing=($i -eq $close)
        }
    }
    return [pscustomobject]@{Properties=$props; Parsed=$parsed; Close=$tokens[$close].Index; LastValueEnd=$lastValueEnd; TrailingComma=$trailing}
}
function Json-Value($Value) { return (ConvertTo-Json -InputObject $Value -Compress -Depth 30) }
function Set-JsoncValues([string]$Text, $Values) {
    $doc=Get-JsoncDocument $Text
    $edits=New-Object 'System.Collections.Generic.List[object]'
    $new=New-Object 'System.Collections.Generic.List[string]'
    $changed=0
    foreach ($key in $Values.Keys) {
        $value=Json-Value $Values[$key]
        if ($doc.Properties.ContainsKey($key)) {
            $p=$doc.Properties[$key]
            if ($p.Key -cne $key) { throw ('配置键大小写不匹配：'+$p.Key+'；请先手动修正。') }
            $old=$doc.Parsed.PSObject.Properties[$key].Value
            if ((Json-Value $old) -cne $value) {
                $edits.Add([pscustomobject]@{Start=$p.Start; Length=($p.End-$p.Start); Value=$value}); $changed++
            }
        } else { $new.Add(('    '+(Json-Value $key)+': '+$value)); $changed++ }
    }
    if ($new.Count -gt 0) {
        $nl=if ($Text.Contains("`r`n")) {"`r`n"} else {"`n"}
        # Place new keys immediately after the opening brace. This avoids disturbing
        # trailing comments and comma placement in existing JSONC settings.
        $brace=[regex]::Match($Text,'\A(?:\s+|//[^\r\n]*|/\*[\s\S]*?\*/)*\{').Length
        if ($brace -le 0) { throw '无法定位配置对象。' }
        $suffix=if ($doc.Properties.Count -gt 0) {','} else {''}
        $insert=$nl+($new.ToArray() -join (','+$nl))+$suffix+$nl
        $edits.Add([pscustomobject]@{Start=$brace;Length=0;Value=$insert})
    }
    $result=$Text
    foreach ($e in @($edits | Sort-Object Start -Descending)) { $result=$result.Remove($e.Start,$e.Length).Insert($e.Start,$e.Value) }
    $check=Get-JsoncDocument $result
    foreach ($key in $Values.Keys) {
        if (-not $check.Properties.ContainsKey($key) -or (Json-Value $check.Parsed.PSObject.Properties[$key].Value) -cne (Json-Value $Values[$key])) { throw ('配置验证失败：'+$key) }
    }
    # Verify every unrelated root property's raw value, not just its parsed form.
    foreach ($key in $doc.Properties.Keys) {
        if ($Values.Contains($key)) { continue }
        if (-not $check.Properties.ContainsKey($key)) { throw ('原有配置丢失：'+$key) }
        $a=$doc.Properties[$key];$b=$check.Properties[$key]
        if ($Text.Substring($a.Start,$a.End-$a.Start) -cne $result.Substring($b.Start,$b.End-$b.Start)) { throw ('原有配置被改动：'+$key) }
    }
    return [pscustomobject]@{Text=$result;Changed=$changed}
}

function New-BackupFolder([string]$Downloads, [string]$Settings) {
    $name='Positron-settings-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
        $bases = if ($BackupRoot) { @([IO.Path]::GetFullPath($BackupRoot)) } else { @($Downloads,(Join-Path $env:LOCALAPPDATA 'Positron-Optimizer\Backups')) }
    foreach ($base in $bases) {
        if (-not $base) { continue }
        try { $p=Join-Path $base $name; [void][IO.Directory]::CreateDirectory($p); return $p } catch { Say ('无法写入备份目录：'+$base) Yellow }
    }
    throw '无法创建备份目录，未修改设置。'
}
function Write-SettingsSafely([string]$Path, [string]$Text, [bool]$Existed, [string]$BeforeHash, [string]$Backup) {
    $parent=Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($parent)
    $tmp=Join-Path $parent ('.positron-optimizer-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    $before=Join-Path $Backup 'settings.before.json'
    $after=Join-Path $Backup 'settings.after.json'
    $enc=New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($tmp,$Text,$enc)
        if ($Existed) {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '配置文件在修改过程中消失，已取消。' }
            $bytes=[IO.File]::ReadAllBytes($Path)
            if ((Get-BytesHash $bytes) -cne $BeforeHash) { throw '配置已被其他程序修改，已取消，请关闭 Positron 后重试。' }
            [IO.File]::WriteAllBytes($before,$bytes)
            # Same-volume atomic replacement. An extra temporary rollback copy is
            # created by File.Replace, independent of the Downloads volume.
            $rollback=$tmp+'.rollback'
            [IO.File]::Replace($tmp,$Path,$rollback)
            if ((Get-BytesHash ([IO.File]::ReadAllBytes($rollback))) -cne $BeforeHash) {
                # Retain a separate copy even if rollback fails.
                $conflict=Join-Path $Backup 'settings.concurrent.json'
                [IO.File]::Copy($rollback,$conflict,$false)
                try { [IO.File]::Replace($rollback,$Path,$null) } catch { throw ('检测到并发修改且自动恢复失败；原文件保存在：'+$rollback) }
                throw '检测到并发修改，已恢复替换前文件。'
            }
            Remove-Item -LiteralPath $rollback -Force
        } else {
            [IO.File]::WriteAllText((Join-Path $Backup 'settings.did-not-exist.txt'),'No user settings file existed before this run.',$enc)
            # Move refuses to overwrite a file created concurrently.
            [IO.File]::Move($tmp,$Path)
        }
        $actual=Read-TextFile $Path
        if ($actual -cne $Text) { throw '写入后回读内容不一致，请检查备份。' }
        [IO.File]::WriteAllBytes($after,[IO.File]::ReadAllBytes($Path))
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}

function Invoke-SelfTest {
    $v=[ordered]@{'editor.rulers'=@();'editor.mouseWheelZoom'=$true;'quarto.inlineOutput.enabled'=$false}
    $samples=@(
        '{}',
        '{"editor.rulers":[80,120],"editor.mouseWheelZoom":false,"unrelated":{"text":"https://a/b/*x*/","list":[1,2]}}',
        "// head`r`n{`r`n  // keep me`r`n  `"other`": [1,2,],`r`n  `"editor.rulers`": [80], // keep after`r`n}`r`n",
        '/* before { */ {"other":"} // /*","nested":{"editor.rulers":[99]}} // end',
        '{"editor.rulers":[],"editor.mouseWheelZoom":true,"quarto.inlineOutput.enabled":false}'
    )
    foreach ($sample in $samples) {
        $one=Set-JsoncValues $sample $v
        $two=Set-JsoncValues $one.Text $v
        if ($two.Changed -ne 0 -or $two.Text -cne $one.Text) { throw 'Self-test idempotence failure' }
        if ($sample.Contains('keep me') -and (-not $one.Text.Contains('keep me') -or -not $one.Text.Contains('keep after'))) { throw 'Self-test comment preservation failure' }
        Say 'PASS: JSONC merge, verification, repeat run' Green
    }
    foreach ($bad in @('{"a":1,"a":2}','{"editor.rulers":[1],"Editor.Rulers":[2]}','{"x": [1,}','{"x":1} garbage')) {
        $rejected=$false; try { [void](Set-JsoncValues $bad $v) } catch { $rejected=$true }
        if (-not $rejected) { throw 'Self-test invalid/duplicate JSON rejection failure' }
        Say 'PASS: reject invalid or duplicate JSON' Green
    }
    $test=Join-Path ([IO.Path]::GetTempPath()) ('positron-optimizer-test-'+[Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $test)
    try {
        $p=Join-Path $test 'settings.json'; $b=Join-Path $test 'backup';[void](New-Item -ItemType Directory -Path $b)
        [IO.File]::WriteAllText($p,'{}');$h=Get-BytesHash ([IO.File]::ReadAllBytes($p));$merged=(Set-JsoncValues '{}' $v).Text
        Write-SettingsSafely $p $merged $true $h $b
        if ((Get-BytesHash ([IO.File]::ReadAllBytes((Join-Path $b 'settings.before.json')))) -cne $h) { throw 'Self-test backup mismatch' }
        $new=Join-Path $test 'new.json';$b2=Join-Path $test 'backup2';[void](New-Item -ItemType Directory -Path $b2)
        Write-SettingsSafely $new $merged $false '' $b2
        if ((Read-TextFile $new) -cne $merged) { throw 'Self-test new file mismatch' }
        $rejected=$false; try { Write-SettingsSafely $p '{}' $true $h $b } catch {$rejected=$true}
        if (-not $rejected -or (Read-TextFile $p) -cne $merged) { throw 'Self-test concurrent change detection failure' }
        Say 'PASS: atomic write, original backup, new file, stale-hash rejection' Green
    } finally { Remove-Item -LiteralPath $test -Recurse -Force }
    Say 'SELF_TEST_OK' Green
}

try {
    if ($SelfTest) { Invoke-SelfTest; exit 0 }
    Say '============================================================' Cyan
    Say ' Positron 一键优化 | Windows | PDF 6 类 / 7 项配置' Cyan
    Say '============================================================' Cyan
    $downloads=Get-DownloadsFolder
    if ($downloads) { Say ('下载目录：'+$downloads) } else { Say '未找到 Downloads，将使用本地应用数据目录备份。' Yellow }
    $installation=Find-Positron $downloads $InstallPath
    $version=(Get-Item -LiteralPath $installation.Exe).VersionInfo.ProductVersion
    Say ('Positron 版本：'+$version)
    Say ('安装位置：'+$installation.Exe)
    Say ('识别来源：'+$installation.Source)
    $settings=Get-SettingsLocation $installation $UserDataDir $SettingsPath
    Say ('配置位置：'+$settings)
    $exists=Test-Path -LiteralPath $settings -PathType Leaf
    $hash=if ($exists) {Get-BytesHash ([IO.File]::ReadAllBytes($settings))} else {''}
    $old=if ($exists) {Read-TextFile $settings} else {"{`r`n}`r`n"}
    if ($exists -and (Get-BytesHash ([IO.File]::ReadAllBytes($settings))) -cne $hash) { throw '读取配置时文件发生变化，请关闭 Positron 后重试。' }
    $doc=Get-JsoncDocument $old
    $plan=Get-ConfigurationPlan $installation $settings
    # An existing legacy switch can conflict with the newer one; align it only if already present.
    if ($plan.Values.Contains('positron.r.diagnostics.enabled') -and $doc.Properties.ContainsKey('positron.r.diagnostics.enable')) { $plan.Values['positron.r.diagnostics.enable']=$false }
    foreach ($key in $plan.Values.Keys) { Say ('  [目标] '+$key+' = '+(Json-Value $plan.Values[$key])) }
    foreach ($key in $plan.Skipped) { Say ('  [跳过] '+$key+'（当前安装未找到支持证据）') Yellow }
    Say '注意：关闭 R 诊断会隐藏部分有价值的警告；base 安装器不保证一定更快。' Yellow
    Say '注意：关闭 Quarto 内联输出会改变执行体验；工作区或自定义 Profile 可以覆盖用户设置。' Yellow
    $merged=Set-JsoncValues $old $plan.Values
    Say ('需要变更的键：'+$merged.Changed)
    if ($CheckOnly) { Say 'CHECK_ONLY：未修改任何设置。' Green; if ($plan.Skipped.Count -gt 0) {exit 2};exit 0 }
    if ($merged.Changed -eq 0) {
        Say '无需修改：可确认的目标配置已经存在且正确。' Green
        if ($plan.Skipped.Count -gt 0) { exit 2 }; exit 0
    }
    $backup=New-BackupFolder $downloads $settings
    Say ('备份位置：'+$backup)
    Write-SettingsSafely $settings $merged.Text $exists $hash $backup
    $verified=Get-JsoncDocument (Read-TextFile $settings)
    foreach ($key in $plan.Values.Keys) {
        if ((Json-Value $verified.Parsed.PSObject.Properties[$key].Value) -cne (Json-Value $plan.Values[$key])) { throw ('回读验证失败：'+$key) }
        Say ('  [通过] '+$key) Green
    }
    $report=@('Positron configuration optimization',('Time: '+(Get-Date -Format o)),('Version: '+$version),('Install: '+$installation.Exe),('Settings: '+$settings),('Original existed: '+$exists),('Original SHA256: '+$hash),('Changed keys: '+$merged.Changed),('Verified keys: '+($plan.Values.Keys -join ', ')),('Skipped keys: '+($plan.Skipped -join ', ')),'Validation: settings file only; UI and R package speed not tested.')
    try { [IO.File]::WriteAllLines((Join-Path $backup 'report.txt'),[string[]]$report,(New-Object Text.UTF8Encoding($true))) } catch { Say '配置已验证，但报告文件写入失败。' Yellow }
    Say '已完成配置写入与回读验证。请保存工作并自行重启 Positron。' Green
    if ($plan.Skipped.Count -gt 0) { Say '部分设置因版本兼容性未确认而跳过；不代表全部七项完成。' Yellow; exit 2 }
    exit 0
} catch {
    Say ('失败：'+$_.Exception.Message) Red
    Say '请查看上方错误及已显示的备份位置；不要删除原有设置。' Yellow
    exit 1
}
