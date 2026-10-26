// RTSS Overlay Preset — framerate of the foreground 3D application per sensor update (500 ms), from RTSS shared memory.
//
// The overlay's own FPS graph (<G=Framerate>) adds a point per frame, so at 150 FPS it covers half a second and
// jitters. A graph of this sensor gets one point per overlay refresh (500 ms) and shows the last half a minute or so,
// like the Steam performance monitor. The value is the average over the frames RTSS added to its frame time ring
// buffer since the previous update (dwStatFrameTimeBuf, 1024 entries in microseconds, the newest at
// dwStatFrameTimeBufPos); on the first update of an application — RTSS's own "framerate calculated once per second",
// 1000 * dwFrames / (dwTime1 - dwTime0) of the last foreground application (RTSS SDK, RTSSSharedMemory.h).
//
// The same buffer gives the slowest frame since the previous update — a slow graph that still shows every stutter as
// a spike.
//
// Every frame time is also passed to NativeStats with the current frame generation multiplier — AVG / 1% / 0.1% low of
// the real frames; RTSS's own statistics are exported next to them (for the overlay's warning colours).
//
// Exported sensors: /overlay-preset/fps/data/0 "Framerate", /overlay-preset/fps/data/1 "Frametime max", ms;
// /overlay-preset/fps/data/2..4 "Native AVG / 1% low / 0.1% low", /overlay-preset/fps/data/5..7 "RTSS AVG / 1% low /
// 0.1% low", /overlay-preset/fps/data/8 "Native max", /overlay-preset/fps/data/9 "RTSS framerate" — RTSS's own
// once-per-second framerate (the same as <FR>), FPS.
using System;
using System.Globalization;
using System.Text;
using System.IO.MemoryMappedFiles;

namespace Exporter
{
	static class RtssFramerate
	{
		const uint SIGNATURE = 0x52545353;		// 'RTSS'

		// RTSS_SHARED_MEMORY (v2) header offsets
		const int OFS_VERSION			= 4;
		const int OFS_APP_ENTRY_SIZE	= 8;
		const int OFS_APP_ARR_OFFSET	= 12;
		const int OFS_APP_ARR_SIZE		= 16;
		const int OFS_LAST_FG_APP		= 64;	// v2.16+
		const int OFS_LAST_FG_PID		= 68;

		// RTSS_SHARED_MEMORY_APP_ENTRY offsets
		const int APP_PID		= 0;
		const int APP_NAME		= 4;		// char szName[MAX_PATH], full path of the executable
		const int APP_TIME0		= 268;
		const int APP_TIME1		= 272;
		const int APP_FRAMES	= 276;
		const int APP_STAT_TIME0	= 288;		// statistics start, changes on a statistics reset
		const int APP_STAT_AVG	= 308;		// dwStatFramerateAvg, 0.1 FPS
		const int APP_STAT_LOW1	= 9176;		// dwStatFramerate1Dot0PercentLow, 0.1 FPS (v2.13+)
		const int APP_STAT_LOW01	= 9180;		// dwStatFramerate0Dot1PercentLow
		const int APP_FT_BUF	= 924;		// DWORD dwStatFrameTimeBuf[1024], microseconds
		const int APP_FT_POS	= 5020;		// index of the newest entry
		const int FT_BUF_SIZE	= 1024;

		/// <summary>Path of the foreground 3D application from the last read, or null.</summary>
		public static string ForegroundApp;

		static uint s_lastPid;
		static uint s_lastPos;
		static uint s_lastStatTime0;
		static double s_rtssAvg, s_rtssLow1, s_rtssLow01;
		static double s_rtssFps;

		public static string ToXml()
		{
			double fps, ftMax;
			if (!TryRead(out fps, out ftMax))
				return "";

			string xml = "<hardware>\n<id>/overlay-preset/fps</id><name>Framerate</name><type>Cpu</type>\n" +
						 "<sensor><id>/overlay-preset/fps/data/0</id><name>Framerate</name><type>Data</type><value>" +
						 fps.ToString("F1", CultureInfo.InvariantCulture) + "</value></sensor>\n";
			if (ftMax > 0)
				xml += Sensor(1, "Frametime max", ftMax);
			double avg, low1, low01, max;
			if (NativeStats.TryGet(PercentileMode(), out avg, out low1, out low01, out max))
				xml += Sensor(2, "Native AVG", avg) + Sensor(3, "Native 1% low", low1) + Sensor(4, "Native 0.1% low", low01) +
					   Sensor(8, "Native max", max);
			if (s_rtssFps > 0)
				xml += Sensor(9, "RTSS framerate", s_rtssFps);
			if (s_rtssAvg > 0)
				xml += Sensor(5, "RTSS AVG", s_rtssAvg) + Sensor(6, "RTSS 1% low", s_rtssLow1) + Sensor(7, "RTSS 0.1% low", s_rtssLow01);
			return xml + "</hardware>\n";
		}

		static string Sensor(int index, string name, double value)
		{
			return "<sensor><id>/overlay-preset/fps/data/" + index + "</id><name>" + name + "</name><type>Data</type><value>" +
				   value.ToString("F1", CultureInfo.InvariantCulture) + "</value></sensor>\n";
		}

		// RTSS setting [Statistics] PercentileCalc in the global profile: 0 — integral 1% / 0.1% low (default), 1 — percentile
		static bool PercentileMode()
		{
			return OsdPosition.ReadGlobal("Statistics", "PercentileCalc", 0) == 1;
		}

		static bool TryRead(out double fps, out double ftMax)
		{
			fps = 0;
			ftMax = 0;
			ForegroundApp = null;
			try
			{
				using (MemoryMappedFile map = MemoryMappedFile.OpenExisting("RTSSSharedMemoryV2", MemoryMappedFileRights.Read))
				using (MemoryMappedViewAccessor view = map.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read))
				{
					if (view.ReadUInt32(0) != SIGNATURE || view.ReadUInt32(OFS_VERSION) < 0x00020010)
						return false;

					uint entrySize	= view.ReadUInt32(OFS_APP_ENTRY_SIZE);
					uint arrOffset	= view.ReadUInt32(OFS_APP_ARR_OFFSET);
					uint arrSize	= view.ReadUInt32(OFS_APP_ARR_SIZE);
					uint index		= view.ReadUInt32(OFS_LAST_FG_APP);
					uint pid		= view.ReadUInt32(OFS_LAST_FG_PID);
					if (pid == 0 || index >= arrSize || entrySize < APP_FT_POS + 4)
						return false;

					long entry = arrOffset + (long)index * entrySize;
					if (view.ReadUInt32(entry + APP_PID) != pid)
						return false;

					byte[] name = new byte[260];
					view.ReadArray(entry + APP_NAME, name, 0, name.Length);
					int len = Array.IndexOf(name, (byte)0);
					ForegroundApp = Encoding.Default.GetString(name, 0, len < 0 ? name.Length : len);

					uint time0	= view.ReadUInt32(entry + APP_TIME0);
					uint time1	= view.ReadUInt32(entry + APP_TIME1);
					uint frames	= view.ReadUInt32(entry + APP_FRAMES);
					if (time0 == 0 || time1 <= time0)
						return false;

					fps = 1000.0 * frames / (time1 - time0);
					s_rtssFps = fps;

					// RTSS statistics; a new start time means they were reset (benchmark hotkey) — reset ours too
					uint statTime0 = view.ReadUInt32(entry + APP_STAT_TIME0);
					if (pid != s_lastPid || statTime0 != s_lastStatTime0)
						NativeStats.Reset();
					s_lastStatTime0 = statTime0;
					s_rtssAvg = view.ReadUInt32(entry + APP_STAT_AVG) / 10.0;
					if (entrySize >= APP_STAT_LOW01 + 4)
					{
						s_rtssLow1 = view.ReadUInt32(entry + APP_STAT_LOW1) / 10.0;
						s_rtssLow01 = view.ReadUInt32(entry + APP_STAT_LOW01) / 10.0;
					}

					// frames added to the ring buffer since the previous call (UpdateTimer.PERIOD ago)
					uint pos = view.ReadUInt32(entry + APP_FT_POS) % FT_BUF_SIZE;
					if (pid == s_lastPid)
					{
						uint added = (pos + FT_BUF_SIZE - s_lastPos) % FT_BUF_SIZE;
						uint max = 0;
						ulong sum = 0;
						int multiplier = FrameRhythm.ActiveMultiplier();		// 0 — unknown yet, NativeStats skips
						for (uint k = added; k-- > 0; )		// oldest first: NativeStats sums frames in order
						{
							uint ft = view.ReadUInt32(entry + APP_FT_BUF + 4 * ((pos + FT_BUF_SIZE - k) % FT_BUF_SIZE));
							sum += ft;
							if (ft > max)
								max = ft;
							NativeStats.Add(ft, multiplier);
						}
						ftMax = max / 1000.0;
						if (sum > 0)
							fps = 1000000.0 * added / sum;
					}
					s_lastPid = pid;
					s_lastPos = pos;
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
