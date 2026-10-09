# install-artcraft.ps1 - ArtCraft installer/updater for the storytold xcraft apps.
# Knows about every X:\ArtCraft folder on every drive, installs to the active one,
# and updates any installed copy in place on its own drive.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File install-artcraft.ps1 [-Update]
#   arrows move, Enter toggles the highlighted row, U selects all updates,
#   C confirms and runs install/update of the selected, D changes drive/location,
#   R refreshes, Q quits.  -Update lists every installed copy across all drives.

param([switch]$Update, [switch]$NoSelfUpdate)

$script:failed = $false
$script:selfUrl = 'https://raw.githubusercontent.com/SaltyMaud/ArtcraftInstaller/main/install-artcraft.ps1'
$script:listWidth = 50   # columns used by the list; the description pane starts after it
$script:note = ''
$script:desktop = $false   # set at confirm: user agreed to create missing desktop shortcuts

function FirstVersion([string[]]$lines) {
    foreach ($l in $lines) { if ($l -match '^\s*version\s*=\s*"([^"]+)"') { return $Matches[1] } }
    return '?'
}
function WrapText([string]$text, [int]$width) {
    $lines = @(); $cur = ''
    foreach ($w in ($text -split '\s+')) {
        if (-not $w) { continue }
        if ($cur -eq '') { $cur = $w }
        elseif (($cur.Length + 1 + $w.Length) -le $width) { $cur = "$cur $w" }
        else { $lines += $cur; $cur = $w }
    }
    if ($cur) { $lines += $cur }
    return , $lines   # comma prevents pipeline unroll (single-line wrap would arrive as a String)
}
function Hide-Cursor { try { [Console]::CursorVisible = $false } catch { } }
function Show-Cursor { try { [Console]::CursorVisible = $true } catch { } }
function Wait-AnyKey {
    if ([Console]::IsInputRedirected) { return }   # non-interactive: never blocks
    Show-Cursor
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan
    [void][Console]::ReadKey($true)
}
function Exit-App([int]$code) { Wait-AnyKey; exit $code }
function AppDisplay([string]$name) {
    ((Get-Culture).TextInfo.ToTitleCase(($name -replace 'craft$',''))) + 'Craft'
}
function New-Shortcut([string]$lnk, [string]$target, [string]$work) {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $s.TargetPath = $target; $s.WorkingDirectory = $work
    $s.IconLocation = "$target,0"
    $s.Save()
}
function Desktop-Lnk([string]$name) { Join-Path ([Environment]::GetFolderPath('Desktop')) ((AppDisplay $name) + '.lnk') }
function Make-StartMenuShortcut([string]$dir, [string]$name) {
    # start-menu .lnk for the built exe; skipped when the exe is absent
    # (library-only crate, build failure). Overwriting is idempotent.
    $exe = Join-Path $dir "target\release\$name.exe"
    if (-not (Test-Path $exe)) { return }
    New-Shortcut (Join-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" ((AppDisplay $name) + '.lnk')) $exe $dir
}
function Make-DesktopShortcut([string]$dir, [string]$name) {
    # desktop .lnk; only made when the user said yes at the confirm prompt
    $exe = Join-Path $dir "target\release\$name.exe"
    if (-not (Test-Path $exe)) { return }
    New-Shortcut (Desktop-Lnk $name) $exe $dir
}
function Needs-DesktopShortcut($e) {
    # counts toward the desktop-shortcut prompt: 'new' rows get their exe after the build,
    # installed rows count only when the exe exists (library-only crates can't be shortcut)
    if (-not (Test-Path (Desktop-Lnk $e.Name))) {
        return ($e.State -eq 'new' -or (Test-Path (Join-Path $e.Dir "target\release\$($e.Name).exe")))
    }
    return $false
}
function RepoDesc($api, [string]$name) {
    if (-not $api) { return '' }
    return ((($api | Where-Object { $_.name -eq $name }).description) -replace '\s+', ' ').Trim()
}

# ---- drives and roots -------------------------------------------------------------------
function Get-Roots {
    $list = @()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $d.IsReady) { continue }
            if ($d.DriveType -notin 'Fixed', 'Removable', 'Network') { continue }
            $letter = $d.Name.TrimEnd('\')                    # "C:"
            $path = "$letter\ArtCraft"
            $apps = @()
            if (Test-Path $path) {
                $apps = @(Get-ChildItem $path -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^[A-Za-z]+craft$' -and (Test-Path (Join-Path $_.FullName '.git')) } |
                    ForEach-Object { $_.Name })
            }
            $list += [pscustomobject]@{
                Path = $path; Letter = $letter; Label = $d.VolumeLabel
                FreeGB = [Math]::Round($d.AvailableFreeSpace / 1GB, 1)
                TotalGB = [Math]::Round($d.TotalSize / 1GB, 0)
                Apps = $apps
            }
        } catch { }
    }
    return , $list
}
function Find-Root([string]$dir) { $script:roots | Where-Object { $_.Path -eq $dir } | Select-Object -First 1 }

function Set-ActiveRoot([int]$i) {
    $r = $script:roots[$i]
    try {
        if (Test-Path $r.Path) {
            $probe = Join-Path $r.Path '.write-test'
            Set-Content -Path $probe -Value 'x' -ErrorAction Stop
            Remove-Item $probe -ErrorAction Stop
        } else {
            # folder does not exist: transiently create + remove it to test writability,
            # so nothing is left behind - the real folder is made on a confirmed install
            New-Item -ItemType Directory -Path $r.Path -ErrorAction Stop | Out-Null
            $probe = Join-Path $r.Path '.write-test'
            Set-Content -Path $probe -Value 'x' -ErrorAction Stop
            Remove-Item $probe -ErrorAction Stop
            Remove-Item $r.Path -Force -ErrorAction Stop
        }
    } catch {
        return "no write access to $($r.Path) - pick another drive."
    }
    $script:active = $i
    return ''
}
function NormalizedHash([string]$path) {
    # hash of file content with line endings normalized to LF and no BOM, so git
    # autocrlf and CDN line-ending differences can never trigger a false update
    $text = [IO.File]::ReadAllText($path)
    $text = ($text -replace "`r`n", "`n") -replace "`r", "`n"
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    (($sha.ComputeHash($bytes)) | ForEach-Object { $_.ToString('x2') }) -join ''
}
function Seed-ArtcraftRoot([string]$path) {
    # drop a copy of the installer + launchers at the root of a freshly created ArtCraft dir
    try {
        Copy-Item $PSCommandPath (Join-Path $path 'install-artcraft.ps1') -Force -ErrorAction Stop
        foreach ($b in 'install-artcraft.bat', 'update-artcraft.bat') {
            $src = Join-Path $PSScriptRoot $b
            if (Test-Path $src) { Copy-Item $src (Join-Path $path $b) -Force }
        }
    } catch { }
}
function ActiveRoot { $script:roots[$script:active] }
function Disk-Note($r) {
    if ($r.FreeGB -lt 5) { return "low disk space: $($r.FreeGB) GB free on $($r.Letter) - builds may fail." }
    return ''
}

# ---- per-installation status -------------------------------------------------------------
function Get-Status([string]$dir) {
    $s = [pscustomobject]@{ State = 'new'; Ver = ''; RemoteVer = ''; Sha = ''; Behind = 0; Ahead = 0 }
    if (-not (Test-Path (Join-Path $dir '.git'))) { return $s }
    $s.Ver = FirstVersion (Get-Content (Join-Path $dir 'Cargo.toml') -ErrorAction SilentlyContinue)
    git -C $dir fetch origin 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $s.State = 'fetchfail'; return $s }
    $s.Behind = [int](git -C $dir rev-list --count 'HEAD..origin/main')
    $s.Ahead  = [int](git -C $dir rev-list --count 'origin/main..HEAD')
    $s.Sha = (git -C $dir rev-parse --short HEAD).Trim()
    $s.RemoteVer = FirstVersion (git -C $dir show origin/main:Cargo.toml)
    $s.State = if ($s.Ahead -gt 0) { 'diverged' } elseif ($s.Behind -gt 0) { 'behind' } else { 'uptodate' }
    if ($s.State -eq 'uptodate' -and -not (Test-Path (Join-Path $dir "target\release\$(Split-Path $dir -Leaf).exe"))) { $s.State = 'nobinary' }
    return $s
}

# ---- row building ------------------------------------------------------------------------
function Build-Rows {
    $rows = @()
    $api = $null
    try {
        $api = Invoke-RestMethod -Uri 'https://api.github.com/orgs/storytold/repos?per_page=100' `
            -Headers @{ 'User-Agent' = 'artcraft-installer' } -TimeoutSec 20
    } catch { $api = $null }
    if ($Update) {
        # one row per installed copy across all roots, drive-tagged
        foreach ($r in $script:roots) {
            foreach ($name in $r.Apps) {
                $dir = Join-Path $r.Path $name
                $s = Get-Status $dir
                $desc = RepoDesc $api $name
                if (-not $desc) { $desc = '(no description on GitHub)' }
                $rows += [pscustomobject]@{ Name = $name; Desc = $desc; Letter = $r.Letter; Dir = $dir
                    State = $s.State; Ver = $s.Ver; RemoteVer = $s.RemoteVer; Sha = $s.Sha; Behind = $s.Behind; Ahead = $s.Ahead; Other = '' }
            }
        }
        return , $rows
    }
    # install mode: one row per app, status measured on the active root
    if (-not $api) { Show-Cursor; Write-Host 'GitHub API unreachable - cannot list apps.' -ForegroundColor Red; Exit-App 1 }
    $names = @($api | Sort-Object name | Where-Object { $_.name -match '^[A-Za-z]+craft$' } | ForEach-Object { $_.name })
    foreach ($r in $script:roots) { $names += $r.Apps }
    $names = @($names | Sort-Object -Unique)
    $ar = ActiveRoot
    foreach ($name in $names) {
        $desc = RepoDesc $api $name
        if (-not $desc) { $desc = '(no description on GitHub)' }
        $dir = Join-Path $ar.Path $name
        $s = Get-Status $dir
        $other = @($script:roots | Where-Object { $_.Letter -ne $ar.Letter -and $_.Apps -contains $name } | ForEach-Object { $_.Letter.TrimEnd(':') }) -join ','
        $rows += [pscustomobject]@{ Name = $name; Desc = $desc; Letter = $ar.Letter; Dir = $dir
            State = $s.State; Ver = $s.Ver; RemoteVer = $s.RemoteVer; Sha = $s.Sha; Behind = $s.Behind; Ahead = $s.Ahead; Other = $other }
    }
    return , $rows
}

function Row-Key($e) { "$($e.Letter)|$($e.Name)|$(if ($Update) { $e.Dir } else { 'new' })" }
function Row-Text($e) {
    $tag = if ($Update) { "$($e.Letter.TrimEnd(':')): " } else { '' }
    switch ($e.State) {
        'uptodate'  { return "$tag" + "up to date  v$($e.Ver) @ $($e.Sha)" }
        'behind'    { $v = if ($e.RemoteVer -ne $e.Ver) { "v$($e.Ver) -> v$($e.RemoteVer)" } else { "v$($e.Ver)" }; return "$tag" + "$($e.Behind) behind  $v" }
        'diverged'  { return "$tag" + "diverged - $($e.Ahead) local commit(s)" }
        'fetchfail' { return "$tag" + "git fetch failed  v$($e.Ver)" }
        'nobinary'  { return "$tag" + "not built  v$($e.Ver) @ $($e.Sha)" }
        default     { $o = if ($e.Other) { " (also on $($e.Other))" } else { '' }; return "$tag" + "not installed$o" }
    }
}
function Row-Mark($e) {
    if ($script:selected.ContainsKey((Row-Key $e))) { return '[>]' }
    if ($e.State -eq 'uptodate') { return '[x]' }
    if ($e.State -eq 'diverged') { return '[!]' }
    return '[ ]'
}

# ---- menu rendering ------------------------------------------------------------------------
$script:cursor = 0
function Show-Menu {
    Clear-Host
    $ar = ActiveRoot
    $title = if ($Update) { 'ArtCraft updater' } else { "ArtCraft installer  -  $($ar.Path)" }
    Write-Host $title -ForegroundColor Cyan
    Write-Host ''
    $paneWidth = 0
    try {
        $w = [Console]::WindowWidth
        if ($w -gt 0) { if (($w - $script:listWidth - 6) -ge 20) { $paneWidth = $w - $script:listWidth - 6 } }
        else { $paneWidth = 52 }
    } catch { $paneWidth = 52 }
    $desc = if ($paneWidth -gt 0) { WrapText $script:rows[$script:cursor].Desc $paneWidth } else { @() }
    $top = if ($desc.Count) { [Math]::Min($script:cursor, [Math]::Max(0, $script:rows.Count - $desc.Count)) } else { 0 }
    for ($i = 0; $i -lt $script:rows.Count; $i++) {
        $e = $script:rows[$i]
        $nameCol = (' [{0}] {1,-12} ' -f ((Row-Mark $e).Substring(1, 1)), $e.Name)
        $status = Row-Text $e
        $rel = $i - $top
        $pane = if ($rel -ge 0 -and $rel -lt $desc.Count) { '  |  ' + $desc[$rel] } else { '' }
        $isSel = $script:selected.ContainsKey((Row-Key $e))
        if ($i -eq $script:cursor) {
            $band = if ($isSel) { 'DarkGreen' } elseif ($e.State -eq 'diverged') { 'DarkYellow' }
                    elseif ($e.State -eq 'uptodate') { 'DarkGray' } else { 'DarkCyan' }
            Write-Host ($nameCol + $status).PadRight($script:listWidth) -NoNewline -ForegroundColor Black -BackgroundColor $band
            Write-Host $pane -ForegroundColor White
        } else {
            $nameColor = if ($isSel) { 'Green' } elseif ($e.State -eq 'uptodate') { 'DarkGray' }
                         elseif ($e.State -eq 'diverged') { 'Yellow' } else { 'Gray' }
            $statusColor = switch ($e.State) { 'behind' { 'Yellow' } 'fetchfail' { 'Red' } 'nobinary' { 'Yellow' } 'diverged' { 'Yellow' } 'uptodate' { 'DarkGray' } default { 'Gray' } }
            Write-Host $nameCol -NoNewline -ForegroundColor $nameColor
            Write-Host ($status.PadRight($script:listWidth - $nameCol.Length)) -NoNewline -ForegroundColor $statusColor
            Write-Host $pane -ForegroundColor White
        }
    }
    Write-Host ''
    $legend = '  arrows move   Enter toggle   U select all updates   C confirm & run'
    if (-not $Update) { $legend += '   D change drive' }
    $legend += '   R refresh   Q quit'
    Write-Host $legend -ForegroundColor Cyan
    if ($script:note) { Write-Host "  $($script:note)" -ForegroundColor Yellow } else { Write-Host '' }
}

# ---- drive picker ---------------------------------------------------------------------------
function Show-Picker {
    Clear-Host
    Write-Host 'ArtCraft - choose the drive' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $script:roots.Count; $i++) {
        $r = $script:roots[$i]
        $mark = if ($i -eq $script:active) { '[>]' } else { '[ ]' }
        $info = if ($r.Apps.Count -gt 0) { "$($r.Apps.Count) apps" } elseif (Test-Path $r.Path) { 'empty' } else { 'new' }
        $text = (' {0} {1,-13} {2,-6} {3,5:N0} GB free' -f $mark, "$($r.Letter)\ArtCraft", $info, $r.FreeGB)
        if ($r.Label) { $text += "  $($r.Label)" }
        if ($i -eq $script:pick) {
            $band = if ($i -eq $script:active) { 'DarkGreen' } else { 'DarkCyan' }
            Write-Host $text.PadRight($script:listWidth) -ForegroundColor Black -BackgroundColor $band
        } else {
            $color = if ($r.Apps.Count -gt 0) { 'Green' } else { 'Gray' }
            Write-Host $text -ForegroundColor $color
        }
    }
    Write-Host ''
    Write-Host '  arrows move   Enter choose   Esc/Q back' -ForegroundColor Cyan
    if ($script:note) { Write-Host "  $($script:note)" -ForegroundColor Yellow } else { Write-Host '' }
}
function Pick-Root() {
    $script:pick = $script:active
    Hide-Cursor
    while ($true) {
        Show-Picker
        $key = [Console]::ReadKey($true).Key
        $script:note = ''
        switch ($key) {
            UpArrow   { if ($script:pick -gt 0) { $script:pick-- } }
            DownArrow { if ($script:pick -lt $script:roots.Count - 1) { $script:pick++ } }
            Enter {
                $err = Set-ActiveRoot $script:pick
                if ($err) { $script:note = $err; continue }
                $script:note = ''
                $script:rows = Build-Rows
                $script:note = Disk-Note (ActiveRoot)
                $script:cursor = 0
                return
            }
            Escape { return }
            Q { return }
        }
    }
}

# ---- rust + git preflight (global, hard requirements) ---------------------------------------
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo -and (Test-Path (Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'))) {
    $env:Path = "$(Join-Path $env:USERPROFILE '.cargo\bin');$env:Path"
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
}
if (-not $cargo) {
    if ([Console]::IsInputRedirected) { Write-Host 'Rust is required - install it from https://rustup.rs and rerun.' -ForegroundColor Red; Exit-App 1 }
    Hide-Cursor
    Write-Host 'Rust is required to build the apps. Install it now?   [Enter] yes   [Esc] quit' -ForegroundColor Cyan
    $go = $false
    while ($true) {
        $k = [Console]::ReadKey($true).Key
        if ($k -eq 'Enter')  { $go = $true; break }
        if ($k -eq 'Escape') { Show-Cursor; Write-Host 'Rust is required - quitting.'; Exit-App 1 }
    }
    if ($go) {
        Show-Cursor
        Write-Host 'Downloading rustup-init...' -ForegroundColor Cyan
        $init = Join-Path $env:TEMP 'rustup-init.exe'
        Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile $init -UseBasicParsing
        & $init --default-toolchain stable -y
        $env:Path = "$(Join-Path $env:USERPROFILE '.cargo\bin');$env:Path"
        if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
            Write-Host 'Rust install did not complete - quitting. Run https://win.rustup.rs/x86_64 yourself and rerun.' -ForegroundColor Red
            Exit-App 1
        }
    }
    Hide-Cursor
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git -and (Test-Path 'C:\Program Files\Git\cmd\git.exe')) {
    $env:Path = 'C:\Program Files\Git\cmd;' + $env:Path
    $git = Get-Command git -ErrorAction SilentlyContinue
}
if (-not $git) {
    if ([Console]::IsInputRedirected) { Write-Host 'Git is required - install it from https://git-scm.com/downloads and rerun.' -ForegroundColor Red; Exit-App 1 }
    Hide-Cursor
    Write-Host 'Git is required. Install it now?   [Enter] yes   [Esc] quit' -ForegroundColor Cyan
    $go = $false
    while ($true) {
        $k = [Console]::ReadKey($true).Key
        if ($k -eq 'Enter')  { $go = $true; break }
        if ($k -eq 'Escape') { Show-Cursor; Write-Host 'Git is required - quitting.'; Exit-App 1 }
    }
    if ($go) {
        Show-Cursor
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host 'Installing Git with winget (accept the elevation prompt)...' -ForegroundColor Cyan
            winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        } else {
            Write-Host 'Downloading the official Git installer...' -ForegroundColor Cyan
            $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'artcraft-installer' }
            $url = ($rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1).browser_download_url
            $setup = Join-Path $env:TEMP (Split-Path $url -Leaf)
            Invoke-WebRequest -Uri $url -OutFile $setup -UseBasicParsing
            Start-Process $setup -ArgumentList '/VERYSILENT', '/NORESTART', '/SP-' -Wait
        }
        if (Test-Path 'C:\Program Files\Git\cmd\git.exe') { $env:Path = 'C:\Program Files\Git\cmd;' + $env:Path }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host 'Git install did not complete - quitting. Install from https://git-scm.com/downloads and rerun.' -ForegroundColor Red
            Exit-App 1
        }
    }
    Hide-Cursor
}

# ---- MSVC Build Tools preflight (the Rust linker; rustup alone does not provide it) -----
function Test-MSVC {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    return [bool]$path
}
if (-not (Test-MSVC)) {
    if ([Console]::IsInputRedirected) {
        Write-Host 'MSVC Build Tools (C++) are required to link the apps. Install them with:' -ForegroundColor Red
        Write-Host '  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"' -ForegroundColor Yellow
        Exit-App 1
    }
    Hide-Cursor
    Write-Host 'MSVC Build Tools (C++) are required to link the apps. Install now?   [Enter] yes   [Esc] quit' -ForegroundColor Cyan
    $go = $false
    while ($true) {
        $k = [Console]::ReadKey($true).Key
        if ($k -eq 'Enter')  { $go = $true; break }
        if ($k -eq 'Escape') { Show-Cursor; Write-Host 'MSVC Build Tools are required - quitting.'; Exit-App 1 }
    }
    if ($go) {
        Show-Cursor
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host 'Installing MSVC Build Tools with winget (accept the elevation prompt)...' -ForegroundColor Cyan
            winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        } else {
            Write-Host 'Downloading the Visual Studio Build Tools installer...' -ForegroundColor Cyan
            $bt = Join-Path $env:TEMP 'vs_buildtools.exe'
            Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $bt -UseBasicParsing
            Start-Process $bt -ArgumentList '--quiet', '--wait', '--norestart', '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended' -Wait
        }
        if (-not (Test-MSVC)) {
            Write-Host 'MSVC Build Tools install did not complete - install them from https://visualstudio.microsoft.com/downloads/ and rerun.' -ForegroundColor Red
            Exit-App 1
        }
    }
    Hide-Cursor
}

# ---- self-update --------------------------------------------------------------------------
if ($PSCommandPath -and $PSScriptRoot -and -not $NoSelfUpdate) {
    $selfPath = $PSCommandPath
    $remoteFile = Join-Path $env:TEMP 'install-artcraft.remote.ps1'
    $gotRemote = $true
    try {
        Invoke-WebRequest -Uri $script:selfUrl -OutFile $remoteFile -Headers @{ 'User-Agent' = 'artcraft-installer' } -TimeoutSec 10 -UseBasicParsing
    } catch {
        $gotRemote = $false
        Write-Host 'self-update check skipped (offline).' -ForegroundColor Yellow
    }
    if ($gotRemote) {
        # refresh the launcher .bat files living next to this script - nothing else
        # updates them, and the pre-fix copies end with echo + pause (double prompt)
        $base = $script:selfUrl.Substring(0, $script:selfUrl.LastIndexOf('/') + 1)
        foreach ($b in 'install-artcraft.bat', 'update-artcraft.bat') {
            try {
                $rb = Join-Path $env:TEMP "artcraft.$b.remote"
                Invoke-WebRequest -Uri "$base$b" -OutFile $rb -Headers @{ 'User-Agent' = 'artcraft-installer' } -TimeoutSec 10 -UseBasicParsing
                # CRLF endings, no BOM - cmd.exe wants it that way
                $bt = ([IO.File]::ReadAllText($rb)) -replace "`r`n", "`n" -replace "`n", "`r`n"
                [IO.File]::WriteAllText((Join-Path $PSScriptRoot $b), $bt, (New-Object System.Text.UTF8Encoding($false)))
                Remove-Item $rb -ErrorAction SilentlyContinue
            } catch { }
        }
        if ((NormalizedHash $remoteFile) -ne (NormalizedHash $selfPath)) {
            if ([Console]::IsInputRedirected) {
                Write-Host 'A newer install-artcraft.ps1 is on GitHub - rerun interactively to update.' -ForegroundColor Yellow
            } else {
                Hide-Cursor
                Write-Host 'A newer install-artcraft.ps1 is on GitHub. Update and restart?   [Enter] yes   [Esc] keep this copy' -ForegroundColor Cyan
                $go = $false
                while ($true) {
                    $k = [Console]::ReadKey($true).Key
                    if ($k -eq 'Enter')  { $go = $true; break }
                    if ($k -eq 'Escape') { break }
                }
                if ($go) {
                    $tokErr = $null
                    [void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $remoteFile), [ref]$tokErr)
                    if ($tokErr.Count) {
                        Show-Cursor
                        Write-Host 'The GitHub copy failed its parse check - keeping this copy.' -ForegroundColor Red
                        $tokErr | ForEach-Object { Write-Host "  $($_.Message)" -ForegroundColor Red }
                    } else {
                        # land the new copy with normalized LF endings and no BOM so the
                        # next run hashes identical and never re-prompts
                        $text = ([IO.File]::ReadAllText($remoteFile)) -replace "`r`n", "`n"
                        [IO.File]::WriteAllText($selfPath, $text, (New-Object System.Text.UTF8Encoding($false)))
                        Show-Cursor
                        $extra = @(); if ($Update) { $extra = @('-Update') }
                        Start-Process powershell -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $selfPath) + $extra)
                        # exit code 7 tells the launching .bat to close the window by itself
                        exit 7
                    }
                }
                Hide-Cursor
            }
        }
        Remove-Item $remoteFile -ErrorAction SilentlyContinue
    }
}

# ---- root selection --------------------------------------------------------------------------
$script:roots = Get-Roots
if ($script:roots.Count -eq 0) { Show-Cursor; Write-Host 'No usable drives found.' -ForegroundColor Red; Exit-App 1 }
$script:active = -1
$home_ = Find-Root ([string]$PSScriptRoot)
if ($home_) { $script:active = [array]::IndexOf($script:roots, $home_) }
if ($script:active -lt 0) {
    $withApps = @($script:roots | Where-Object { $_.Apps.Count -gt 0 })
    if ($withApps.Count -eq 1) { $script:active = [array]::IndexOf($script:roots, $withApps[0]) }
}
if ($script:active -lt 0) {
    # script's own drive as the default ArtCraft location
    $q = (Split-Path $PSScriptRoot -Qualifier).TrimEnd('\')
    $byLetter = $script:roots | Where-Object { $_.Letter -eq $q } | Select-Object -First 1
    $script:active = [array]::IndexOf($script:roots, $byLetter)
}
if ($script:active -lt 0) { $script:active = 0 }
$err = Set-ActiveRoot $script:active
if ($err) { Show-Cursor; Write-Host $err -ForegroundColor Red; Exit-App 1 }
if (@($script:roots | Where-Object { $_.Apps.Count -gt 0 }).Count -gt 1 -and -not [Console]::IsInputRedirected -and -not $Update) {
    Pick-Root    # more than one drive has an ArtCraft installation - ask which one to work on
}

# ---- main loop ------------------------------------------------------------------------------
$script:selected = @{}
$script:rows = Build-Rows
$script:note = Disk-Note (ActiveRoot)

if ([Console]::IsInputRedirected) {
    Show-Menu
    Show-Cursor
    Write-Host 'No interactive console available - nothing changed.' -ForegroundColor Yellow
    Exit-App 0
}
Hide-Cursor
:loop
while ($true) {
    Show-Menu
    $w0 = [Console]::WindowWidth; $h0 = [Console]::WindowHeight
    while (-not [Console]::KeyAvailable) {          # a window resize re-wraps stale lines on the spot -
        if ([Console]::WindowWidth -ne $w0 -or [Console]::WindowHeight -ne $h0) { continue loop }   # repaint immediately instead of waiting for a key
        Start-Sleep -Milliseconds 60
    }
    $key = [Console]::ReadKey($true).Key
    $script:note = ''
    switch ($key) {
        UpArrow   { if ($script:cursor -gt 0) { $script:cursor-- } }
        DownArrow { if ($script:cursor -lt $script:rows.Count - 1) { $script:cursor++ } }
        Enter {
            $e = $script:rows[$script:cursor]
            if ($e.State -eq 'uptodate') { $script:note = "$($e.Name) is up to date - nothing to do." }
            elseif ($e.State -eq 'diverged' -or $e.State -eq 'fetchfail') { $script:note = "$($e.Name) has local changes/fetch trouble - left alone." }
            elseif ($script:selected.ContainsKey((Row-Key $e))) { $script:selected.Remove((Row-Key $e)) }
            else { $script:selected[(Row-Key $e)] = $e }
        }
        U {
            $n = 0
            foreach ($e in $script:rows) { if ($e.State -eq 'behind') { $script:selected[(Row-Key $e)] = $e; $n++ } }
            $script:note = if ($n -gt 0) { "selected $n update(s)." } else { 'nothing to update.' }
        }
        C {
            if ($script:selected.Count -eq 0) { $script:note = 'nothing selected - toggle a row first.'; break }
            $need = @($script:selected.Values | Where-Object { Needs-DesktopShortcut $_ })
            $script:desktop = $false
            if ($need.Count -gt 0) {
                Show-Menu
                Write-Host ''
                $ask = if ($need.Count -eq 1) { "Create a desktop shortcut for $(AppDisplay $need[0].Name)?   [Enter] yes   [Q/Esc] no" }
                       else { "Create desktop shortcuts for $($need.Count) apps?   [Enter] yes   [Q/Esc] no" }
                Write-Host $ask -ForegroundColor Yellow
                Show-Cursor
                while ($true) {
                    $k = [Console]::ReadKey($true).Key
                    if ($k -eq 'Enter') { $script:desktop = $true; break }
                    if ($k -in 'Escape', 'Q') { $script:desktop = $false; break }
                }
                Hide-Cursor
            }
            break loop
        }
        D { if ($Update) { $script:note = 'drive select applies to install mode.' } else { Pick-Root; $script:note = "now working on $((ActiveRoot).Path)." } }
        R { $script:roots = Get-Roots; $script:rows = Build-Rows; $script:note = 'refreshed.' }
        Q { Show-Cursor; Write-Host ''; Write-Host 'Quit - nothing changed.'; Exit-App 0 }
    }
}
Show-Cursor

# ---- run: clone new (to active root), pull + build updates (in place) ------------------------
Clear-Host
Write-Host 'Running...' -ForegroundColor Cyan
$results = @{}
foreach ($e in $script:selected.Values) {
    $name = $e.Name
    $tag = "$($e.Letter.TrimEnd(':')): "
    if ($e.State -eq 'new') {
        $ar = ActiveRoot
        $dir = Join-Path $ar.Path $name
        Write-Host ''
        Write-Host "$($tag)$name`: cloning into $($ar.Path)..." -ForegroundColor Cyan
        if (-not (Test-Path $ar.Path)) { New-Item -ItemType Directory -Path $ar.Path -ErrorAction SilentlyContinue | Out-Null; Seed-ArtcraftRoot $ar.Path }
        if (-not (Test-Path $ar.Path)) { Write-Host "$($tag)$name`: install FAILED (could not create $($ar.Path))" -ForegroundColor Red; $results[$name] = "$($tag)install FAILED"; $script:failed = $true; continue }
        git clone "https://github.com/storytold/$name" $dir
        if ($LASTEXITCODE -ne 0) { Write-Host "$($tag)$name`: clone FAILED" -ForegroundColor Red; $results[$name] = "$($tag)clone FAILED"; $script:failed = $true; continue }
        Write-Host "$($tag)$name`: building..." -ForegroundColor Cyan
        cargo build --release -p $name --manifest-path (Join-Path $dir 'Cargo.toml')
        $ok = ($LASTEXITCODE -eq 0)
        if ($ok) {
            Make-StartMenuShortcut $dir $name
            if ($script:desktop) { Make-DesktopShortcut $dir $name }
        }
        $results[$name] = if ($ok) { "$($tag)installed" } else { "$($tag)installed, BUILD FAILED"; $script:failed = $true }
    } else {
        $dir = $e.Dir
        Write-Host ''
        Write-Host "$($tag)$name`: pulling..." -ForegroundColor Cyan
        git -C $dir pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Host "$($tag)$name`: pull FAILED" -ForegroundColor Red; $results[$name] = "$($tag)pull FAILED"; $script:failed = $true; continue }
        Write-Host "$($tag)$name`: building..." -ForegroundColor Cyan
        cargo build --release -p $name --manifest-path (Join-Path $dir 'Cargo.toml')
        $ok = ($LASTEXITCODE -eq 0)
        if ($ok) { Make-StartMenuShortcut $dir $name }   # start menu self-heals (backfills pre-shortcut installs); desktop only on user consent
        $newVer = FirstVersion (Get-Content (Join-Path $dir 'Cargo.toml') -ErrorAction SilentlyContinue)
        $verNote = if ($newVer -ne $e.Ver) { "v$($e.Ver) -> v$newVer" } else { "v$newVer" }
        $results[$name] = if ($ok) { "$($tag)updated $verNote" } else { "$($tag)pulled $verNote but BUILD FAILED"; $script:failed = $true }
    }
}

# desktop shortcuts the user approved at confirm; Make-DesktopShortcut skips rows whose
# exe is absent (build failure, library-only crate)
if ($script:desktop) {
    foreach ($e in $script:selected.Values) {
        if ($e.State -eq 'new') { continue }   # fresh installs already made theirs above
        Make-DesktopShortcut $e.Dir $e.Name
    }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor Cyan
foreach ($name in ($results.Keys | Sort-Object)) {
    Write-Host ('  {0}: {1}' -f $name, $results[$name]) -ForegroundColor $(if ($results[$name] -match 'FAILED') { 'Red' } else { 'Green' })
}
Write-Host ''
if ($script:failed) { Exit-App 1 } else { Exit-App 0 }
