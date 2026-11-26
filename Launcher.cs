using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("HEIC -> JPEG Donusturucu")]
[assembly: AssemblyDescription("iPhone HEIC fotograflarini JPEG'e donusturur ve fotograf arsivini duzenler.")]
[assembly: AssemblyProduct("HEIC -> JPEG Donusturucu")]
[assembly: AssemblyVersion("1.4.0.0")]
[assembly: AssemblyFileVersion("1.4.0.0")]

namespace HeicDonustur
{
    internal static class Program
    {
        private static readonly string[] EmbeddedScripts = new[]
        {
            "HEIC_Donustur.ps1",
            "PhotoDuplicateFinder.ps1"
        };

        private static string QuoteArg(string arg)
        {
            if (string.IsNullOrEmpty(arg)) return "\"\"";
            int backslashes = 0;
            for (int i = arg.Length - 1; i >= 0 && arg[i] == '\\'; i--)
            {
                backslashes++;
            }
            return "\"" + arg.Replace("\"", "\\\"") + new string('\\', backslashes) + "\"";
        }

        private static int Main(string[] args)
        {
            try
            {
                Console.Title = "HEIC -> JPEG Donusturucu";
                Console.OutputEncoding = Encoding.UTF8;
                Console.InputEncoding = Encoding.UTF8;
            }
            catch
            {
                // Non-interactive console handles may reject encoding/title changes.
            }

            string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            if (string.IsNullOrEmpty(exeDir))
            {
                exeDir = Environment.CurrentDirectory;
            }

            string workDir = (args != null && args.Length > 0 && !string.IsNullOrWhiteSpace(args[0]))
                ? args[0]
                : exeDir;

            string tempDir = Path.Combine(Path.GetTempPath(), "HEIC_Donustur_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);

            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                foreach (string name in EmbeddedScripts)
                {
                    using (Stream stream = asm.GetManifestResourceStream(name))
                    {
                        if (stream == null)
                        {
                            Console.Error.WriteLine("HATA: Gomulu kaynak bulunamadi: " + name);
                            return 1;
                        }
                        string destPath = Path.Combine(tempDir, name);
                        using (FileStream fs = File.Create(destPath))
                        {
                            stream.CopyTo(fs);
                        }
                    }
                }

                string mainScript = Path.Combine(tempDir, "HEIC_Donustur.ps1");
                string psExe = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"
                );
                if (!File.Exists(psExe))
                {
                    psExe = "powershell.exe";
                }

                var psi = new ProcessStartInfo
                {
                    FileName = psExe,
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + QuoteArg(mainScript) + " -WorkDir " + QuoteArg(workDir),
                    WorkingDirectory = workDir,
                    UseShellExecute = false
                };

                using (Process proc = Process.Start(psi))
                {
                    if (proc == null)
                    {
                        Console.Error.WriteLine("HATA: PowerShell baslatilamadi.");
                        return 1;
                    }
                    proc.WaitForExit();
                    return proc.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("HATA: " + ex.Message);
                Console.WriteLine("Kapatmak icin Enter'a basin...");
                try { Console.ReadLine(); } catch { }
                return 1;
            }
            finally
            {
                try
                {
                    if (Directory.Exists(tempDir))
                    {
                        Directory.Delete(tempDir, true);
                    }
                }
                catch
                {
                    // Best-effort cleanup.
                }
            }
        }
    }
}
