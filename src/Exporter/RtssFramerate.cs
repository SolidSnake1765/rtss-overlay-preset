// RTSS Overlay Preset — framerate of the foreground 3D application, once per second, from RTSS shared memory.
//
// The overlay's own FPS graph (<G=Framerate>) adds a point per frame, so at 150 FPS it covers half a second and
// jitters. A graph of this sensor gets one point per overlay refresh (1 s) and shows the last minute or so, like the
// Steam performance monitor. The value is RTSS's own "framerate calculated once per second":
// 1000 * dwFrames / (dwTime1 - dwTime0) of the last foreground application (RTSS SDK, RTSSSharedMemory.h).
//
// The same for frame time: the slowest frame of the last second, from RTSS's frame time ring buffer
// (dwStatFrameTimeBuf, 1024 entries in microseconds, the newest at dwStatFrameTimeBufPos) — a slow graph that still
// shows every stutter as a spike.
//
// Exported sensors: /overlay-preset/fps/data/0 "Framerate (1 s)", /overlay-preset/fps/data/1 "Frametime max (1 s)", ms.
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
		const int APP_FT_BUF	= 924;		// DWORD dwStatFrameTimeBuf[1024], microseconds
		const int APP_FT_POS	= 5020;		// index of the newest entry
		const int FT_BUF_SIZE	= 1024;

		/// <summary>Path of the foreground 3D application from the last read, or null.</summary>
		public static string ForegroundApp;

		static uint s_lastPid;
		static uint s_lastPos;

		public static string ToXml()
		{
			double fps, ftMax;
			if (!TryRead(out fps, out ftMax))
				return "";

			string xml = "<hardware>\n<id>/overlay-preset/fps</id><name>Framerate</name><type>Cpu</type>\n" +
						 "<sensor><id>/overlay-preset/fps/data/0</id><name>Framerate (1 s)</name><type>Data</type><value>" +
						 fps.ToString("F1", CultureInfo.InvariantCulture) + "</value></sensor>\n";
			if (ftMax > 0)
				xml += "<sensor><id>/overlay-preset/fps/data/1</id><name>Frametime max (1 s)</name><type>Data</type><value>" +
					   ftMax.ToString("F1", CultureInfo.InvariantCulture) + "</value></sensor>\n";
			return xml + "</hardware>\n";
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

					// frames added to the ring buffer since the previous call (~1 s ago)
					uint pos = view.ReadUInt32(entry + APP_FT_POS) % FT_BUF_SIZE;
					if (pid == s_lastPid)
					{
						uint added = (pos + FT_BUF_SIZE - s_lastPos) % FT_BUF_SIZE;
						uint max = 0;
						for (uint k = 0; k < added; k++)
						{
							uint ft = view.ReadUInt32(entry + APP_FT_BUF + 4 * ((pos + FT_BUF_SIZE - k) % FT_BUF_SIZE));
							if (ft > max)
								max = ft;
						}
						ftMax = max / 1000.0;
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
