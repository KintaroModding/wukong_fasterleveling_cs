using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Threading;
using b1;
using CSharpModBase;
using Google.Protobuf.Collections;
using ResB1;

namespace FasterLeveling
{
    // Divides the XP for each level in the game's level table (PlayerLevelDesc, field NextLevelExp) in memory; the game
    // files stay as they are. The game loads its tables when the game instance starts (BGW_GameInstance_B1
    // .InitGameInstObj calls BGW_GameDB.Init before InitGameInstObjDone is set). Every XP check and XP bar reads the rows
    // of that table (GameDBRuntime.GetPlayerLevelDesc; its lookup dictionary holds the same row objects as the list), so
    // one change of the rows reaches all of them. A background thread waits for the table and changes its rows once.
    // When the game loads the tables again (a new TBPlayerLevelDesc object), it changes the new rows too.
    internal sealed class LevelTable
    {
        private const string PakVersion = "wukong_fasterleveling";

        private readonly double divider;
        private readonly object gate = new object();
        private volatile bool stopping;
        private Thread thread;
        // The table the mod changed, its rows and their values from the game.
        private TBPlayerLevelDesc changed;
        private PlayerLevelDesc[] rows;
        private int[] original;

        public LevelTable(double divider)
        {
            this.divider = divider;
        }

        public void Start()
        {
            thread = new Thread(Loop) { IsBackground = true, Name = "FasterLeveling" };
            thread.Start();
        }

        // Puts the game's values back (C# Loader calls DeInit before it reloads the mods with Ctrl+F5).
        public void Stop()
        {
            stopping = true;
            thread?.Join(3000);
            lock (gate)
            {
                if (changed == null)
                {
                    return;
                }
                for (int i = 0; i < rows.Length; i++)
                {
                    rows[i].NextLevelExp = original[i];
                }
                changed = null;
                rows = null;
                original = null;
            }
            ModLog.Info("level table: the game's values are back.");
        }

        // The pak version of this mod halves the same table in the game files; with both, each level needs a quarter.
        public static void WarnAboutPakVersion()
        {
            try
            {
                // Common.ModDir is b1\Binaries\Win64\CSharpLoader\Mods; the paks are in b1\Content\Paks\~mods.
                string mods = Path.Combine(Common.ModDir, "..", "..", "..", "..", "Content", "Paks", "~mods");
                if (!Directory.Exists(mods))
                {
                    return;
                }
                foreach (string file in Directory.GetFiles(mods, PakVersion + "*.pak"))
                {
                    ModLog.Error($"{Path.GetFileName(file)} in Paks\\~mods is the pak version of this mod: with both, the " +
                                 "divider applies to the already halved table. Remove one of them.");
                }
            }
            catch (Exception e)
            {
                ModLog.Error($"pak check: {e.Message}");
            }
        }

        private void Loop()
        {
            int failures = 0;
            while (!stopping)
            {
                try
                {
                    Check();
                }
                catch (Exception e)
                {
                    if (failures++ < 5)
                    {
                        ModLog.Error($"level table: {e}");
                    }
                }
                for (int i = 0; i < 10 && !stopping; i++)
                {
                    Thread.Sleep(100);
                }
            }
        }

        private void Check()
        {
            List<BGWGameInstanceCS> instances = BGWGameInstanceCS.GetAllAliveInstance();
            BGWGameInstanceCS instance = instances != null && instances.Count > 0 ? instances[0] : null;
            if (ReferenceEquals(instance, null) || !instance.InitGameInstObjDone)
            {
                return;
            }
            TBPlayerLevelDesc table = GameDBRuntime.GetTBPlayerLevelDesc();
            if (table == null || table.List.Count == 0 || ReferenceEquals(table, changed))
            {
                return;
            }
            Apply(table);
        }

        private void Apply(TBPlayerLevelDesc table)
        {
            RepeatedField<PlayerLevelDesc> list = table.List;
            PlayerLevelDesc[] newRows = new PlayerLevelDesc[list.Count];
            int[] values = new int[list.Count];
            int[] divided = new int[list.Count];
            long gameTotal = 0;
            long modTotal = 0;
            for (int i = 0; i < list.Count; i++)
            {
                newRows[i] = list[i];
                values[i] = newRows[i].NextLevelExp;
                divided[i] = Divide(values[i]);
                gameTotal += values[i];
                modTotal += divided[i];
            }
            bool again;
            lock (gate)
            {
                if (stopping)
                {
                    return;
                }
                for (int i = 0; i < newRows.Length; i++)
                {
                    newRows[i].NextLevelExp = divided[i];
                }
                again = changed != null;
                changed = table;
                rows = newRows;
                original = values;
            }
            ModLog.Info(string.Format(CultureInfo.InvariantCulture,
                "level table{0}: {1} levels divided by {2}. Level {3} needs {4} XP (game {5}); all levels {6} XP (game {7}).",
                again ? " loaded again by the game" : "", newRows.Length, divider, newRows[0].Id, divided[0], values[0],
                modTotal, gameTotal));
        }

        // Rounded up, so a level never needs less than the game's XP divided by the divider. 0 stays 0.
        private int Divide(int xp)
        {
            if (xp <= 0)
            {
                return xp;
            }
            decimal value = Math.Ceiling(xp / (decimal)divider);
            return (int)Math.Max(1, value);
        }
    }
}
