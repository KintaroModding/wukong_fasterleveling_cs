# Faster Leveling (C#)

Every level needs less XP: the game's XP per level is divided by a number you set in config.json (default 2, half the XP). Needs C# Loader.

A C# mod for Black Myth: Wukong, loaded by [C# Loader](https://github.com/KintaroModding/b1csharploader), made with game
version `1.0.21.23831` and C# Loader v1.0.1. This README is for developers; what the mod does and how
to install it are in [openmods.md](openmods.md), the mod page on [openmods](https://openmods.nexus).

## How it works

The game's XP per level is the protobuf table `PlayerLevelDesc` (`ResB1.TBPlayerLevelDesc` in `Protobuf.RunTime.dll`;
rows `Id` = level, `NextLevelExp`, `NextLevelGainTalent`). The game loads its tables when the game instance starts
(`BGW_GameInstance_B1.InitGameInstObj` calls `BGW_GameDB.Init`, before `InitGameInstObjDone` is set) and keeps them in
`GSProtobufRuntimeAPI<TBPlayerLevelDesc, PlayerLevelDesc>`: a list and a lookup dictionary with the same row objects.
Every XP check and XP bar reads these rows (`GameDBRuntime.GetPlayerLevelDesc`).

`LevelTable.cs` runs on a background thread. Once the game instance is ready
(`BGWGameInstanceCS.InitGameInstObjDone`), it takes the table (`GameDBRuntime.GetTBPlayerLevelDesc()`), keeps the game's
values and sets each row's `NextLevelExp` to the game's value divided by `XpDivider` of `config.json` (`Config.cs`),
rounded up. It then checks the table once a second: when the game loads its tables again (a new table object), it
changes the new rows too. `DeInit` (before C# Loader reloads the mods with Ctrl+F5) puts the game's values back. The mod
uses no hooks, so it does not need `EnableJit=1`. At the start it warns in its log when the pak version of this mod
(`wukong_fasterleveling*.pak`) is in `Paks\~mods`.

## Build and deploy

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -GameDll <folder> -ModBase <file>   # build into dist\mod\wukong_fasterleveling_cs
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Deploy                             # build, then copy into the game
```

The build needs:

- the .NET SDK 8 or newer (https://dotnet.microsoft.com);
- the game's C# DLLs: the folder `GameDll` of the C# Loader repository (`-GameDll`), made for game version
  `1.0.21.23831`;
- `CSharpModBase.dll`, the mod API of C# Loader: `b1\Binaries\Win64\CSharpLoader\CSharpModBase.dll` in its release zip
  (`-ModBase`). Without `-ModBase` the build takes it from the loader installed in the game.

`build.ps1` builds `src\wukong_fasterleveling_cs.csproj` with the version of `mod.json`, puts the DLL and the files of
`src\files\` (when there) into `dist\mod\wukong_fasterleveling_cs\`, and checks that the DLL has that version and needs no
assembly that the game or C# Loader lacks. `deploy.ps1` copies that folder to
`<game folder>\b1\Binaries\Win64\CSharpLoader\Mods\wukong_fasterleveling_cs\`. The game folder is
`$env:UE5_GAMES_DIR\Black Myth Wukong`; `-GameDir` or `-ModsDir` override it. The running game locks the DLL: close the
game first, or use `deploy.ps1 -Wait`.

The mod writes its lines into `wukong_fasterleveling_cs.log` in its folder and into the loader's console (`Console=1` in
`CSharpLoader\b1cs.ini`). With `Develop=1`, Ctrl+F5 in the game reloads all C# mods.

Versioning: every change raises the second number (1.0 -> 1.1) in `mod.json`: `python scripts\bump_version.py`. The
build writes it into the DLL.

## Project layout

```
src/wukong_fasterleveling_cs.csproj   The C# project (.NET Framework 4.7.2)
src/*.cs                    The mod: ModMain.cs (entry point), LevelTable.cs (divides the XP per level), Config.cs
                            (config.json), ModLog.cs (log)
src/files/config.json       The player's settings, copied into the mod folder
src/Directory.Build.props   Sends the build output to dist\
docs/                       Cover and screenshots
scripts/                    bump_version.py
build.ps1                   Builds and checks the mod folder
deploy.ps1                  Copies the mod folder into the game
mod.json                    Name, version, game and C# Loader version
```

## License

MIT, see [LICENSE](LICENSE).
