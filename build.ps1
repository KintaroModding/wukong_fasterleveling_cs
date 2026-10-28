<#
.SYNOPSIS
    Builds the C# mod (src\<folder>.csproj) into dist\mod\<folder>\, the folder for the game's CSharpLoader\Mods.

.DESCRIPTION
    A C# Loader mod is a .NET Framework 4.7.2 DLL that the game's Mono runtime loads through C# Loader
    (https://github.com/KintaroModding/b1csharploader). It builds against two things that are not in this repository:
      - the game's C# DLLs (BtlSvr.Main.dll, b1.Native.dll, ...): the folder GameDll of the C# Loader repository
        (-GameDll), else _tools\gamedata\<game>\gamedll in a parent folder of the project or in $env:UE5_TOOLS;
      - CSharpModBase.dll, the mod API of C# Loader: b1\Binaries\Win64\CSharpLoader\CSharpModBase.dll of its release
        zip (-ModBase), else _tools\b1csharploader, else the loader installed in the game.
    It needs the .NET SDK 8 or newer: _tools\dotnet when it is there (its caches then stay in _tools), else dotnet
    from PATH. The build:
      1. dotnet build (Release) into dist\bin, with the version of mod.json;
      2. dist\mod\<folder>\ gets the DLL and the files of src\files\ (when that folder exists);
      3. checks the DLL: it has the version of mod.json, and it references only assemblies that the game, C# Loader
         or src\files provide.
    With -Deploy, deploy.ps1 then copies dist\mod\<folder>\ into the game's CSharpLoader\Mods\<folder>\.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -GameDll ..\b1csharploader\GameDll -ModBase ..\CSharpModBase.dll
#>
param(
    # Copy the mod folder into the game's CSharpLoader\Mods after the build (see deploy.ps1).
    [switch]$Deploy,
    # The game's install folder. Default: gameDir of _tools\gamedata\<game>\game.json, else $env:UE5_GAMES_DIR\<gameFolder of mod.json>.
    [string]$GameDir,
    # The folder with the game's C# DLLs (GameDll of the C# Loader repository).
    [string]$GameDll,
    # CSharpModBase.dll of C# Loader.
    [string]$ModBase
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

$root = $PSScriptRoot
$mod = Get-Content (Join-Path $root "mod.json") -Raw | ConvertFrom-Json
$name = $mod.folder
$project = Join-Path $root "src\$name.csproj"
$out = Join-Path $root "dist\mod\$name"

# The shared tools: $env:UE5_TOOLS, else the first _tools folder above the project; none in a plain clone.
function Find-Tools {
    if ($env:UE5_TOOLS) {
        return $env:UE5_TOOLS
    }
    $dir = Split-Path $root -Parent
    while ($dir) {
        $candidate = Join-Path $dir "_tools"
        if (Test-Path $candidate) {
            return $candidate
        }
        $dir = Split-Path $dir -Parent
    }
    return $null
}

$tools = Find-Tools
if (-not $GameDir) {
    $GameDir = Get-GameDir
}

if (-not $GameDll -and $tools) {
    $GameDll = Join-Path $tools "gamedata\$($mod.game)\gamedll"
}
if (-not $GameDll -or -not (Test-Path (Join-Path $GameDll "BtlSvr.Main.dll"))) {
    throw "The game's C# DLLs were not found. Use -GameDll <folder>: the folder GameDll of https://github.com/KintaroModding/b1csharploader."
}
$GameDll = (Resolve-Path $GameDll).Path
if (-not $ModBase) {
    $candidates = @()
    if ($tools) {
        $candidates += Join-Path $tools "b1csharploader\package\b1\Binaries\Win64\CSharpLoader\CSharpModBase.dll"
    }
    if ($GameDir) {
        $candidates += Join-Path $GameDir "$($mod.win64Path)\CSharpLoader\CSharpModBase.dll"
    }
    $ModBase = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ModBase -or -not (Test-Path $ModBase)) {
    throw "CSharpModBase.dll was not found. Use -ModBase <file>: b1\Binaries\Win64\CSharpLoader\CSharpModBase.dll of the C# Loader release zip."
}
$ModBase = (Resolve-Path $ModBase).Path

$dotnet = $null
if ($tools -and (Test-Path (Join-Path $tools "dotnet\dotnet.exe"))) {
    $dotnet = Join-Path $tools "dotnet\dotnet.exe"
    $env:DOTNET_CLI_HOME = Join-Path $tools "dotnet_home"
    $env:NUGET_PACKAGES = Join-Path $tools "nuget"
} else {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "The .NET SDK was not found. Install the .NET SDK 8 or newer from https://dotnet.microsoft.com and run this again."
    }
    $dotnet = $command.Source
}
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_NOLOGO = "1"

# 1. Build.
& $dotnet build $project -c Release -v minimal "-p:Version=$($mod.version)" "-p:GameDll=$GameDll" "-p:ModBase=$ModBase"
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed (exit code $LASTEXITCODE)."
}
$dll = Join-Path $root "dist\bin\Release\$name.dll"

# 2. The mod folder.
if (Test-Path $out) {
    Remove-Item $out -Recurse -Force
}
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item $dll $out
$files = Join-Path $root "src\files"
if (Test-Path $files) {
    Copy-Item (Join-Path $files "*") $out -Recurse -Force
}

# 3. Check the DLL. Loaded from bytes, so the file stays unlocked.
$assembly = [System.Reflection.Assembly]::ReflectionOnlyLoad([System.IO.File]::ReadAllBytes($dll))
$info = $assembly.GetCustomAttributesData() |
    Where-Object { $_.AttributeType.FullName -eq "System.Reflection.AssemblyInformationalVersionAttribute" } |
    Select-Object -First 1
$built = if ($info) { [string]$info.ConstructorArguments[0].Value } else { "" }
if ($built -ne $mod.version) {
    throw "The DLL has the version '$built', mod.json '$($mod.version)'."
}
$known = @("mscorlib", "System", "System.Core") +
    @(Get-ChildItem $GameDll -Filter *.dll | ForEach-Object { $_.BaseName }) +
    @(Get-ChildItem (Split-Path $ModBase -Parent) -Filter *.dll | ForEach-Object { $_.BaseName }) +
    @(Get-ChildItem $out -Filter *.dll | Where-Object { $_.Name -ne "$name.dll" } | ForEach-Object { $_.BaseName })
$unknown = @($assembly.GetReferencedAssemblies() | Where-Object { $known -notcontains $_.Name } | ForEach-Object { $_.Name })
if ($unknown) {
    throw "The DLL references assemblies that neither the game nor C# Loader provides: $($unknown -join ', '). Put them into src\files, or remove the dependency."
}
Write-Host "Built $($mod.name) $($mod.version): $out ($((Get-Item $dll).Length) bytes)" -ForegroundColor Green

if ($Deploy) {
    $deployArgs = @{}
    if ($GameDir) {
        $deployArgs.GameDir = $GameDir
    }
    & (Join-Path $root "deploy.ps1") @deployArgs
    exit $LASTEXITCODE
}
