<#
.SYNOPSIS
    Copies the built mod folder (dist\mod\<folder>) into the game's CSharpLoader\Mods\<folder> and replaces old files
    safely.

.DESCRIPTION
    C# Loader must be installed in the game (<win64Path>\version.dll and CSharpLoader\). It loads each mod from
    CSharpLoader\Mods\<folder>\<folder>.dll at game start, and the running game locks that DLL. The script checks the
    files first; with -Wait it waits until the game is closed. Each changed file is copied under a temporary name,
    checked, and then swapped in with one rename, so the game never sees a half-written file. Files in the target
    folder that the build does not make (the mod's log, a player's own settings) stay as they are.

    Exit codes: 0 = deployed or already up to date, 2 = the game is running (without -Wait), 1 = error.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\deploy.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Wait
#>
param(
    # The game's install folder. Default: gameDir of _tools\gamedata\<game>\game.json, else $env:UE5_GAMES_DIR\<gameFolder of mod.json>.
    [string]$GameDir,
    # The C# Loader mods folder. Default: <GameDir>\<win64Path of mod.json>\CSharpLoader\Mods.
    [string]$ModsDir,
    # Wait until the game releases the files instead of stopping.
    [switch]$Wait,
    [int]$WaitMinutes = 360
)

$ErrorActionPreference = "Stop"

# The game folder: "gameDir" of _tools\gamedata\<game>\game.json, for a game outside UE5_GAMES_DIR (for example in a
# Steam library), else $env:UE5_GAMES_DIR\<gameFolder of mod.json>; $null when neither is known. The tools folder is
# $env:UE5_TOOLS, else the first _tools folder above the project (a plain clone has none).
function Get-GameDir {
    $toolsDir = $env:UE5_TOOLS
    if (-not $toolsDir -and $PSScriptRoot) {
        $dir = Split-Path $PSScriptRoot -Parent
        while (-not $toolsDir -and $dir) {
            if (Test-Path (Join-Path $dir "_tools")) {
                $toolsDir = Join-Path $dir "_tools"
            }
            $dir = Split-Path $dir -Parent
        }
    }
    if ($toolsDir) {
        $gameJson = Join-Path $toolsDir "gamedata\$($mod.game)\game.json"
        if (Test-Path $gameJson) {
            $gameInfo = Get-Content $gameJson -Raw | ConvertFrom-Json
            if ($gameInfo.gameDir) {
                return $gameInfo.gameDir
            }
        }
    }
    if ($env:UE5_GAMES_DIR) {
        return Join-Path $env:UE5_GAMES_DIR $mod.gameFolder
    }
    return $null
}

$mod = Get-Content (Join-Path $PSScriptRoot "mod.json") -Raw | ConvertFrom-Json
$source = Join-Path $PSScriptRoot "dist\mod\$($mod.folder)"
if (-not (Test-Path (Join-Path $source "$($mod.folder).dll"))) {
    throw "$source\$($mod.folder).dll not found. Build it first with build.ps1."
}
if (-not $ModsDir) {
    if (-not $GameDir) {
        $GameDir = Get-GameDir
    }
    if (-not $GameDir) {
        throw "The game folder is unknown: set UE5_GAMES_DIR (the folder that holds '$($mod.gameFolder)'), give the game a gameDir in _tools\gamedata\$($mod.game)\game.json, or use -GameDir or -ModsDir."
    }
    $loader = Join-Path (Join-Path $GameDir $mod.win64Path) "CSharpLoader"
    if (-not (Test-Path (Join-Path $loader "CSharpManager.bin"))) {
        throw "C# Loader is not installed in the game ($loader\CSharpManager.bin is missing). Install it first: https://github.com/KintaroModding/b1csharploader/releases/latest"
    }
    $ModsDir = Join-Path $loader "Mods"
}
$target = Join-Path $ModsDir $mod.folder
New-Item -ItemType Directory -Force $target | Out-Null

function Test-Locked([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $false
    }
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        return $false
    } catch {
        return $true
    }
}

function Get-Hash([string]$Path) {
    try {
        return (Get-FileHash $Path -ErrorAction Stop).Hash
    } catch {
        return $null
    }
}

$changed = @(Get-ChildItem $source -Recurse -File | ForEach-Object {
    $destination = Join-Path $target $_.FullName.Substring($source.Length + 1)
    $hash = Get-Hash $_.FullName
    if ((Get-Hash $destination) -ne $hash) {
        [pscustomobject]@{ Source = $_.FullName; Target = $destination; Hash = $hash }
    }
})
if (-not $changed) {
    Write-Host "Already up to date: $target" -ForegroundColor Green
    exit 0
}

$locked = @($changed | Where-Object { Test-Locked $_.Target })
if ($locked) {
    if (-not $Wait) {
        Write-Host "The game is running and uses $($locked[0].Target)." -ForegroundColor Yellow
        Write-Host "Close the game and run this again, or use the -Wait option." -ForegroundColor Yellow
        exit 2
    }
    Write-Host "The game is running. Waiting until it is closed (checking every 5 seconds)..."
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    while (@($changed | Where-Object { Test-Locked $_.Target })) {
        if ((Get-Date) -gt $deadline) {
            throw "The game did not release the mod files within $WaitMinutes minutes."
        }
        Start-Sleep -Seconds 5
    }
}

foreach ($file in $changed) {
    New-Item -ItemType Directory -Force (Split-Path $file.Target -Parent) | Out-Null
    $temp = "$($file.Target).tmp"
    Copy-Item $file.Source $temp -Force
    if ((Get-Hash $temp) -ne $file.Hash) {
        Remove-Item $temp -Force
        throw "The copy in $temp is damaged. $($file.Target) was not replaced."
    }
    try {
        if (Test-Path $file.Target) {
            # [NullString]::Value: Windows PowerShell passes $null as "" to string parameters.
            [System.IO.File]::Replace($temp, $file.Target, [NullString]::Value)
        } else {
            Move-Item $temp $file.Target
        }
    } catch {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        throw "Could not replace $($file.Target) (did the game start again?): $($_.Exception.Message)"
    }
    if ((Get-Hash $file.Target) -ne $file.Hash) {
        throw "Check failed: $($file.Target) does not match $($file.Source)."
    }
}
Write-Host "Deployed $($mod.name) $($mod.version) to $target ($($changed.Count) files; active from the next game start)" -ForegroundColor Green
