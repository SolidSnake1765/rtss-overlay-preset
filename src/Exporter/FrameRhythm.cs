// RTSS Overlay Preset — frame generation rhythm from PresentMon frame data.
//
// With in-game frame generation a real frame is heavy for the GPU and the generated ones are light, so the per-frame
// GPU busy time repeats with the period of the multiplier: x2 — heavy, light; x3 — heavy, light, light (DLSS 4 MFG,
// OptiScaler); x4 … x6 the same with more light frames. PresentMon (bundled with RTSS) does not mark these frames,
// so the rhythm is the sign. Overlay formulas cannot do this reliably: OverlayEditor receives PresentMon frames in
// batches and buf() inside a per-frame formula always sees the end of the batch. So the frames are read here, straight
// from PresentMonDataProvider's shared memory (RTSS SDK, Include\PMDPSharedMemory.h), the last ~240 of the game:
//   D(k) = average |gpu[i] - gpu[i-k]|;   rhythm = D(1) / average gpu;
//   multiplier = the smallest k in 2..8 with D(k) <= D(1) / 2 (the pattern repeats every k frames), 0 if none.
// Without frame generation the rhythm is 0.0-0.1, with it 1.5-2.5 (Witcher 3 + OptiScaler, x2 and x3, 26.10.2026).
//
// Exported sensors: /overlay-preset/fgr/data/0 "Rhythm", /overlay-preset/fgr/data/1 "Multiplier" (this update),
// /overlay-preset/fgr/data/2 "Multiplier (5 s)" — the most frequent non-zero multiplier of the last 10 updates.
using System;
using System.Globalization;
using System.IO.MemoryMappedFiles;

namespace Exporter
{
	static class FrameRhythm
	{
		const uint SIGNATURE = 0x504D4450;		// 'PMDP'
		const int FRAMES = 240;
		const int MIN_FRAMES = 32;
		const int MAX_PERIOD = 8;
		const int HISTORY = 10;					// updates (~5 s at 500 ms)

		// PMDP_FRAME_DATA offsets: data1 (PM_FRAME_DATA_V1) then data2 (PM_FRAME_DATA_V2)
		const int FRAME_PID			= 260;
		const int FRAME_GPU_ACTIVE	= 368;		// data1.msGpuActive (PresentMon 1.x console path)
		const int FRAME_CPU_START	= 384;		// data2.CPUStart, non-zero when V2 metrics are filled
		const int FRAME_GPU_BUSY	= 432;		// data2.GPUBusy (PresentMon 2.x API path)

		static readonly int[] s_history = new int[HISTORY];
		static int s_historyPos;
		static double s_lastRhythm;

		/// <summary>Multiplier of in-game frame generation now (the same signs as the overlay's GameFG), or 1.</summary>
		/// <remarks>Called once per update (RtssFramerate). In menus, loading screens and while the game is in the background
		/// the rhythm drowns in noise for a while; the last multiplier is kept for up to STICKY updates (10 s) meanwhile,
		/// otherwise those generated frames would count as real ones and push the AVG up.</remarks>
		public static int ActiveMultiplier()
		{
			// a game with a frame generation library, but no PresentMon frames yet (the provider starts ~10 s after RTSS):
			// the multiplier is unknown — 0, NativeStats skips these frames instead of counting generated ones as real
			if (FrameGenProbe.HasLibrary && !s_haveData && s_lastActive < 2)
				return 0;
			int m = StableMultiplier();
			if (FrameGenProbe.HasLibrary && s_lastRhythm >= 0.25 && m >= 2)
			{
				s_lastActive = m;
				s_lostUpdates = 0;
				return m;
			}
			if (FrameGenProbe.HasLibrary && s_lastActive >= 2 && ++s_lostUpdates <= STICKY)
				return s_lastActive;
			s_lastActive = 0;
			return 1;
		}

		const int STICKY = 20;
		static int s_lastActive;
		static int s_lostUpdates;
		static bool s_haveData;

		public static string ToXml()
		{
			double rhythm;
			int multiplier;
			s_haveData = TryRead(out rhythm, out multiplier);
			if (!s_haveData)
			{
				rhythm = 0;
				multiplier = 0;
			}
			s_lastRhythm = rhythm;
			s_history[s_historyPos] = multiplier;
			s_historyPos = (s_historyPos + 1) % HISTORY;

			return "<hardware>\n<id>/overlay-preset/fg-rhythm</id><name>Frame Generation Rhythm</name><type>Cpu</type>\n" +
				   Sensor(0, "Rhythm", rhythm.ToString("F2", CultureInfo.InvariantCulture)) +
				   Sensor(1, "Multiplier", multiplier.ToString(CultureInfo.InvariantCulture)) +
				   Sensor(2, "Multiplier (5 s)", StableMultiplier().ToString(CultureInfo.InvariantCulture)) +
				   "</hardware>\n";
		}

		static string Sensor(int index, string name, string value)
		{
			return "<sensor><id>/overlay-preset/fgr/data/" + index + "</id><name>" + name + "</name><type>Data</type><value>" +
				   value + "</value></sensor>\n";
		}

		static int StableMultiplier()
		{
			int best = 0, bestCount = 0;
			for (int m = 2; m <= MAX_PERIOD; m++)
			{
				int count = 0;
				foreach (int h in s_history)
					if (h == m)
						count++;
				if (count > bestCount)
				{
					best = m;
					bestCount = count;
				}
			}
			return best;
		}

		static bool TryRead(out double rhythm, out int multiplier)
		{
			rhythm = 0;
			multiplier = 0;
			try
			{
				using (MemoryMappedFile map = MemoryMappedFile.OpenExisting("PMDPSharedMemory", MemoryMappedFileRights.Read))
				using (MemoryMappedViewAccessor view = map.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read))
				{
					if (view.ReadUInt32(0) != SIGNATURE)
						return false;
					uint entrySize	= view.ReadUInt32(8);
					uint arrOffset	= view.ReadUInt32(12);
					uint arrSize	= view.ReadUInt32(16);			// power of two
					uint count		= view.ReadUInt32(20);
					uint pos		= view.ReadUInt32(24);			// next write position
					if (entrySize < FRAME_GPU_BUSY + 8 || arrSize == 0 || count < MIN_FRAMES)
						return false;

					int n = (int)Math.Min(Math.Min(count, arrSize), FRAMES);
					double[] gpu = new double[n];
					uint pid = 0;
					int got = 0;
					// newest first, only frames of the newest frame's process
					for (int k = 1; k <= n; k++)
					{
						long frame = arrOffset + (long)((pos - (uint)k) & (arrSize - 1)) * entrySize;
						uint framePid = view.ReadUInt32(frame + FRAME_PID);
						if (k == 1)
							pid = framePid;
						else if (framePid != pid)
							break;
						double g = view.ReadUInt64(frame + FRAME_CPU_START) != 0 ? view.ReadDouble(frame + FRAME_GPU_BUSY) : view.ReadDouble(frame + FRAME_GPU_ACTIVE);
						if (g < 0 || g > 1000)
							g = 0;
						gpu[got++] = g;
					}
					if (got < MIN_FRAMES)
						return false;

					double mean = 0;
					for (int i = 0; i < got; i++)
						mean += gpu[i];
					mean /= got;
					if (mean <= 0.01)
						return false;

					double[] d = new double[MAX_PERIOD + 1];
					for (int k = 1; k <= MAX_PERIOD; k++)
					{
						double sum = 0;
						for (int i = k; i < got; i++)
							sum += Math.Abs(gpu[i] - gpu[i - k]);
						d[k] = sum / (got - k);
					}

					rhythm = d[1] / mean;
					for (int k = 2; k <= MAX_PERIOD; k++)
					{
						if (d[k] <= d[1] / 2)
						{
							multiplier = k;
							break;
						}
					}
					return true;
				}
			}
			catch (Exception)
			{
				return false;
			}
		}
	}
}
