using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using LLama;
using LLama.Common;
using LLama.Sampling;

namespace Animundi.Sim;

/// <summary>
/// The language model built into the game (0.5 AI minds): llama.cpp compiled with the game
/// through LLamaSharp (native libraries for Windows, macOS and Linux ship with every build), so
/// every player has a mind without installing anything.
///
/// The model's weights (a small instruct model in GGUF format) are looked for:
/// 1. next to the game's executable, in models/ (a build can ship them: tools/bundle_model.sh);
/// 2. in the player's data folder (user://models);
/// 3. else they are downloaded there, once, in the background, on the first launch.
/// Until the model is ready (or if it cannot be), the procedural inventor invents: the game never
/// waits. Answers are forced into the invention language by a grammar (GBNF).
/// </summary>
public static class LocalModel
{
	public enum State { Off, Missing, Downloading, Loading, Ready, Failed }

	/// <summary>Default model: Qwen2.5 0.5B Instruct, Q4_K_M (about 400 MB, Apache 2.0).</summary>
	public const string DefaultFile = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
	public const string DefaultUrl = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf";

	public static State Status { get; private set; } = State.Off;
	/// <summary>Download progress, 0..1.</summary>
	public static float Progress { get; private set; }
	public static string Error { get; private set; } = "";
	public static string File { get; private set; } = "";

	private static LLamaWeights _weights;
	private static ModelParams _params;
	private static readonly SemaphoreSlim _busy = new(1, 1);
	private static Thread _starter;

	/// <summary>Folders searched for the model, in order.</summary>
	public static List<string> SearchFolders()
	{
		var list = new List<string>();
		string exe = Godot.OS.GetExecutablePath();
		if (!string.IsNullOrEmpty(exe))
			list.Add(Path.Combine(Path.GetDirectoryName(exe) ?? "", "models"));
		list.Add(Godot.ProjectSettings.GlobalizePath("res://models"));
		list.Add(Godot.ProjectSettings.GlobalizePath("user://models"));
		return list;
	}

	/// <summary>Starts the built-in mind in the background: finds the model, downloads it if
	/// allowed and missing, loads it. Safe to call more than once.</summary>
	public static void Start(string file, string url, bool download)
	{
		if (_starter != null || Status == State.Ready)
			return;
		file = string.IsNullOrEmpty(file) ? DefaultFile : file;
		url = string.IsNullOrEmpty(url) ? DefaultUrl : url;
		var folders = SearchFolders();
		_starter = new Thread(() => Run(file, url, download, folders)) { IsBackground = true, Name = "animundi-mind" };
		_starter.Start();
	}

	private static void Run(string file, string url, bool download, List<string> folders)
	{
		try
		{
			// A full path given: that file.
			string path = Path.IsPathRooted(file) && System.IO.File.Exists(file) ? file : null;
			foreach (var folder in path == null ? folders : new List<string>())
				if (System.IO.File.Exists(Path.Combine(folder, file)))
				{
					path = Path.Combine(folder, file);
					break;
				}
			if (path == null)
			{
				if (!download)
				{
					Status = State.Missing;
					return;
				}
				path = Path.Combine(folders[^1], file);
				Download(url, path);
			}
			File = path;
			Status = State.Loading;
			Preload();
			_params = new ModelParams(path)
			{
				ContextSize = 2048,
				GpuLayerCount = 0,
				Threads = Math.Max(1, Environment.ProcessorCount / 2),
			};
			_weights = LLamaWeights.LoadFromFile(_params);
			Status = State.Ready;
		}
		catch (Exception e)
		{
			Error = e.Message;
			Status = State.Failed;
		}
	}

	private static void Download(string url, string path)
	{
		Status = State.Downloading;
		Directory.CreateDirectory(Path.GetDirectoryName(path)!);
		string part = path + ".part";
		using var http = new HttpClient { Timeout = TimeSpan.FromHours(2) };
		using var response = http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead).GetAwaiter().GetResult();
		response.EnsureSuccessStatusCode();
		long total = response.Content.Headers.ContentLength ?? -1;
		using (var input = response.Content.ReadAsStream())
		using (var output = System.IO.File.Create(part))
		{
			var buffer = new byte[1 << 16];
			long done = 0;
			int n;
			while ((n = input.Read(buffer, 0, buffer.Length)) > 0)
			{
				output.Write(buffer, 0, n);
				done += n;
				if (total > 0)
					Progress = (float)done / total;
			}
		}
		System.IO.File.Move(part, path, overwrite: true);
		Progress = 1f;
	}

	/// <summary>Unloads the model (the procedural inventor takes over); Start loads it again.</summary>
	public static void Stop()
	{
		_starter?.Join(TimeSpan.FromSeconds(30));
		_starter = null;
		_busy.Wait();
		try
		{
			_weights?.Dispose();
			_weights = null;
			Status = State.Off;
		}
		finally
		{
			_busy.Release();
		}
	}

	/// <summary>Asks the model, in the background; the answer is forced into the invention
	/// language by its grammar. One question at a time.</summary>
	public static System.Threading.Tasks.Task<string> Generate(string prompt)
	{
		return System.Threading.Tasks.Task.Run(async () =>
		{
			await _busy.WaitAsync();
			try
			{
				var executor = new StatelessExecutor(_weights, _params);
				var inference = new InferenceParams
				{
					MaxTokens = 600,
					SamplingPipeline = new DefaultSamplingPipeline { Temperature = 0.8f, Grammar = new Grammar(Grammar(), "root") },
				};
				string chat = "<|im_start|>system\nYou invent things for a people in a world simulation. Answer with one JSON record.<|im_end|>\n"
					+ $"<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n";
				var sb = new StringBuilder();
				await foreach (var piece in executor.InferAsync(chat, inference))
					sb.Append(piece);
				return sb.ToString().Trim();
			}
			finally
			{
				_busy.Release();
			}
		});
	}

	/// <summary>The invention language as a GBNF grammar (what llama.cpp samples under): only
	/// records with known kinds, effects and jobs can come out. Caps and budgets are checked by
	/// the engine's validator afterwards, like for any other record.</summary>
	public static string Grammar()
	{
		static string Alt(IEnumerable<string> words)
		{
			var parts = new List<string>();
			foreach (var w in words)
				parts.Add($"\"\\\"{w}\\\"\"");
			return string.Join(" | ", parts);
		}
		// A whole number from 1 to max (max under 100): an effect's amount within its cap.
		static string UpTo(int max)
		{
			var parts = new List<string> { "[1-9]" };
			int tens = max / 10, units = max % 10;
			if (tens >= 2)
				parts.Add($"[1-{tens - 1}] [0-9]");
			if (tens >= 1)
				parts.Add($"\"{tens}\" [0-{units}]");
			return string.Join(" | ", parts);
		}
		// GBNF rule names allow letters, digits and hyphens only.
		static string Rule(string word) => word.Replace('_', '-');
		var lines = new List<string>();
		// One record per kind: each kind lists only the effects it may have.
		var records = new List<string>();
		foreach (var kind in Simulation.InventionKinds)
		{
			records.Add("rec-" + kind);
			lines.Add($"rec-{kind} ::= \"{{\" ws \"\\\"name\\\":\" ws name \",\" ws \"\\\"kind\\\":\" ws \"\\\"{kind}\\\"\" \",\" ws \"\\\"improves\\\":\" ws text \",\" ws \"\\\"description\\\":\" ws text \",\" ws \"\\\"cost\\\":\" ws cost \",\" ws \"\\\"effects\\\":\" ws \"[\" ws eff-{kind} (ws \",\" ws eff-{kind}){{0,2}} ws \"]\" \",\" ws \"\\\"sprite\\\":\" ws sprite ws \"}}\"");
			var allowed = new List<string>();
			foreach (var (name, block) in Simulation.EffectBlocks)
				if (Array.IndexOf(block.kinds, kind) >= 0)
					allowed.Add("do-" + Rule(name));
			lines.Add($"eff-{kind} ::= {string.Join(" | ", allowed)}");
		}
		// Work effects (work_speed, yield) always name a job; the others never do.
		foreach (var (name, block) in Simulation.EffectBlocks)
			lines.Add($"do-{Rule(name)} ::= \"{{\" ws \"\\\"do\\\":\" ws \"\\\"{name}\\\"\" \",\" ws "
				+ (block.job ? "\"\\\"job\\\":\" ws job \",\" ws " : "")
				+ $"\"\\\"amount\\\":\" ws ({UpTo((int)block.max)}) ws \"}}\"");
		lines.InsertRange(0, new[]
		{
			$"root ::= {string.Join(" | ", records)}",
			"name ::= \"\\\"\" [A-Z] [a-zA-Z' -]{1,26} \"\\\"\"",
			"text ::= \"\\\"\" [a-zA-Z0-9 ,.'!?-]{0,60} \"\\\"\"",
			"cost ::= \"{\" ws \"\\\"wood\\\":\" ws num \",\" ws \"\\\"stone\\\":\" ws num \",\" ws \"\\\"metal\\\":\" ws num \",\" ws \"\\\"gold\\\":\" ws num ws \"}\"",
			$"job ::= {Alt(Simulation.WorkJobs)}",
			// JSON numbers: no leading zero ("09" is not JSON).
			"num ::= (\"0\" | [1-9] [0-9]?) (\".\" [0-9])?",
			$"sprite ::= [0-9] | [1-2] [0-9] | \"3\" [0-{Simulation.InventionSprites - 31}]",
			"ws ::= [ ]?",
		});
		return string.Join("\n", lines) + "\n";
	}

	private static bool _preloaded;
	public static string NativeFolder { get; private set; } = "";

	/// <summary>Loads llama.cpp's native libraries from the folder that matches this computer
	/// (platform, processor, and on x64 the best of AVX-512, AVX2, AVX or none), before LLamaSharp
	/// looks for them: run inside Godot, its own search does not find them. Dependencies first,
	/// so each library finds the others already loaded.</summary>
	public static void Preload()
	{
		if (_preloaded)
			return;
		_preloaded = true;
		// llama.cpp's own log: errors only, everything with ANIMUNDI_LLM_LOG=1.
		bool verbose = Environment.GetEnvironmentVariable("ANIMUNDI_LLM_LOG") == "1";
		LLama.Native.NativeLibraryConfig.All.WithLogCallback((level, message) =>
		{
			if (verbose || level == LLama.Native.LLamaLogLevel.Error)
				Console.Write($"[llama {level}] {message}");
		});
		string baseDir = Path.GetDirectoryName(typeof(LocalModel).Assembly.Location) ?? AppContext.BaseDirectory;
		string os = OperatingSystem.IsWindows() ? "win" : OperatingSystem.IsMacOS() ? "osx" : "linux";
		string arch = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture switch
		{
			System.Runtime.InteropServices.Architecture.Arm64 => "arm64",
			_ => "x64",
		};
		var variants = new List<string>();
		if (arch == "x64" && os != "osx")
		{
			if (System.Runtime.Intrinsics.X86.Avx512F.IsSupported)
				variants.Add("avx512");
			if (System.Runtime.Intrinsics.X86.Avx2.IsSupported)
				variants.Add("avx2");
			if (System.Runtime.Intrinsics.X86.Avx.IsSupported)
				variants.Add("avx");
			variants.Add("noavx");
		}
		variants.Add("");
		string prefix = os == "win" ? "" : "lib";
		string ext = os == "win" ? ".dll" : os == "osx" ? ".dylib" : ".so";
		var folders = new List<string>();
		foreach (var v in variants)
			folders.Add(Path.Combine(baseDir, "runtimes", $"{os}-{arch}", "native", v));
		// Exported games: the libraries sit next to the assembly.
		folders.Add(baseDir);
		foreach (var folder in folders)
		{
			string llama = Path.Combine(folder, prefix + "llama" + ext);
			if (!System.IO.File.Exists(llama))
				continue;
			try
			{
				var handles = new Dictionary<string, IntPtr>();
				foreach (var lib in new[] { "ggml-base", "ggml-cpu", "ggml-blas", "ggml-metal", "ggml", "llama", "mtmd" })
				{
					string path = Path.Combine(folder, prefix + lib + ext);
					if (System.IO.File.Exists(path))
						handles[lib] = System.Runtime.InteropServices.NativeLibrary.Load(path);
				}
				NativeFolder = folder;
				UseLoadedLibraries(handles);
				return;
			}
			catch (Exception)
			{
				// This variant does not run here (an instruction set missing): try the next one.
			}
		}
	}

	/// <summary>Hands LLamaSharp the libraries loaded above. Its netstandard2.0 build (the one a
	/// net8.0 game gets) sets no resolver: .NET then looks for "llama" next to the host, which is
	/// Godot's executable, not the game's folder. On macOS the libraries loaded by path don't
	/// satisfy that lookup either (their install names are libllama.0.dylib…), so it fails.</summary>
	private static void UseLoadedLibraries(Dictionary<string, IntPtr> handles)
	{
		try
		{
			System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(typeof(LLama.Native.NativeApi).Assembly,
				(name, _, _) => handles.TryGetValue(name, out var handle) ? handle : IntPtr.Zero);
		}
		catch (InvalidOperationException)
		{
			// LLamaSharp (a newer build) already set its own resolver: it finds the libraries itself.
		}
	}

	/// <summary>Whether llama.cpp's native library loads on this computer (tests, settings).</summary>
	public static bool NativeLoads(out string detail)
	{
		try
		{
			Preload();
			LLama.Native.NativeApi.llama_empty_call();
			detail = "llama.cpp loaded from " + NativeFolder;
			return true;
		}
		catch (Exception e)
		{
			detail = e.GetType().Name + ": " + e.Message;
			for (var inner = e.InnerException; inner != null; inner = inner.InnerException)
				detail += " <- " + inner.GetType().Name + ": " + inner.Message;
			return false;
		}
	}
}
