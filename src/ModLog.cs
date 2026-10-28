using System;
using System.IO;
using CSharpModBase;

namespace FasterLeveling
{
    // Writes the mod's lines to the C# Loader console (Console=1 in b1cs.ini) and to wukong_fasterleveling_cs.log in the mod's
    // folder, which each game start overwrites.
    internal static class ModLog
    {
        // The mod's folder. The game runs in b1\Binaries\Win64, and C# Loader's paths start there.
        public static readonly string Folder = Path.Combine(Common.ModDir, "wukong_fasterleveling_cs");

        private static readonly object Gate = new object();
        private static string prefix = "";
        private static string path;

        public static void Start(string name, string version)
        {
            prefix = $"[{name}] ";
            path = Path.Combine(Folder, "wukong_fasterleveling_cs.log");
            try
            {
                File.WriteAllText(path, $"{name} {version}{Environment.NewLine}");
            }
            catch
            {
                path = null;
            }
        }

        public static void Info(string message) => Write(message, false);

        public static void Error(string message) => Write(message, true);

        private static void Write(string message, bool error)
        {
            if (error)
            {
                Log.Error(prefix + message);
            }
            else
            {
                Log.Info(prefix + message);
            }
            lock (Gate)
            {
                if (path == null)
                {
                    return;
                }
                try
                {
                    File.AppendAllText(path, $"{DateTime.Now:HH:mm:ss.fff} {(error ? "ERROR " : "")}{message}{Environment.NewLine}");
                }
                catch
                {
                }
            }
        }
    }
}
