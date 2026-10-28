using System.Reflection;
using CSharpModBase;

namespace FasterLeveling
{
    // C# Loader creates this class and calls Init() once the game runs (on the loader's own thread, not the game
    // thread), and DeInit() before it reloads the mods (Ctrl+F5 with Develop=1 in b1cs.ini).
    public class ModMain : ICSharpMod
    {
        private LevelTable levelTable;

        public string Name => "Faster Leveling (C#)";

        // build.ps1 sets the version from mod.json.
        public string Version { get; } = typeof(ModMain).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "?";

        public void Init()
        {
            ModLog.Start(Name, Version);
            ModLog.Info($"{Version} loaded.");
            Config.Load();
            if (!Config.Enable)
            {
                ModLog.Info("turned off in config.json: the game's level table stays as it is.");
                return;
            }
            LevelTable.WarnAboutPakVersion();
            levelTable = new LevelTable(Config.XpDivider);
            levelTable.Start();
        }

        public void DeInit()
        {
            levelTable?.Stop();
            levelTable = null;
            ModLog.Info("unloaded.");
        }
    }
}
