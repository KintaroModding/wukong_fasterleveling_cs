using System;
using System.Collections;
using System.Globalization;
using System.IO;
using LitJson;

namespace FasterLeveling
{
    // The settings in config.json in the mod's folder. A missing file or value keeps the default.
    internal static class Config
    {
        public const double MinDivider = 1;
        public const double MaxDivider = 100;

        public static bool Enable = true;
        // The game's XP for each level is divided by this number and rounded up: 2 = half the XP, 1 = the game's values.
        public static double XpDivider = 2;

        public static void Load()
        {
            string path = Path.Combine(ModLog.Folder, "config.json");
            if (!File.Exists(path))
            {
                ModLog.Info("config.json not found: default settings.");
                return;
            }
            try
            {
                JsonData json = JsonMapper.ToObject(File.ReadAllText(path));
                Enable = GetBool(json, "Enable", Enable);
                XpDivider = GetDivider(json, "XpDivider", XpDivider);
                ModLog.Info($"config.json read: XP divider {XpDivider.ToString(CultureInfo.InvariantCulture)}" +
                            $"{(Enable ? "" : "; turned off")}.");
            }
            catch (Exception e)
            {
                ModLog.Error($"config.json: {e.Message} (default settings for the rest)");
            }
        }

        private static bool Has(JsonData json, string key)
        {
            return json.IsObject && ((IDictionary)json).Contains(key);
        }

        private static bool GetBool(JsonData json, string key, bool fallback)
        {
            return Has(json, key) && json[key].IsBoolean ? (bool)json[key] : fallback;
        }

        // A number from 1 to 100 with up to two decimals.
        private static double GetDivider(JsonData json, string key, double fallback)
        {
            if (!Has(json, key))
            {
                return fallback;
            }
            JsonData value = json[key];
            double number = value.IsInt ? (int)value : value.IsDouble ? (double)value : fallback;
            return Math.Max(MinDivider, Math.Min(MaxDivider, Math.Round(number, 2)));
        }
    }
}
