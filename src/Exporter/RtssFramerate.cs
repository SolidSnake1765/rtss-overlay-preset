// RTSS Overlay Preset — framerate of the foreground 3D application, once per second, from RTSS shared memory.
//
// The overlay's own FPS graph (<G=Framerate>) adds a point per frame, so at 150 FPS it covers half a second and
// jitters. A graph of this sensor gets one point per overlay refresh (1 s) and shows the last minute or so, like the
// Steam performance monitor. The value is RTSS's own "framerate calculated once per second":
// 1000 * dwFrames / (dwTime1 - dwTime0) of the last foreground application (RTSS SDK, RTSSSharedMemory.h).
//
// Exported sensor: /overlay-preset/fps/data/0 "Framerate (1 s)".
using System;
using System.Globalization;
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
		const int APP_TIME0		= 268;
		const int APP_TIME1		= 272;
		const int APP_FRAMES	= 276;

		public static string ToXml()
		{
			double fps;
			if (!TryRead(out fps))
				return "";

			return "<hardware>\n<id>/overlay-preset/fps</id><name>Framerate</name><type>Cpu</type>\n" +
				   "<sensor><id>/overlay-preset/fps/data/0</id><name>Framerate (1 s)</name><type>Data</type><value>" +
				   fps.ToString("F1", CultureInfo.InvariantCulture) + "</value></sensor>\n</hardware>\n";
		}

		static bool TryRead(out double fps)
		{
			fps = 0;
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
					if (pid == 0 || index >= arrSize || entrySize < APP_FRAMES + 4)
						return false;

					long entry = arrOffset + (long)index * entrySize;
					if (view.ReadUInt32(entry + APP_PID) != pid)
						return false;

					uint time0	= view.ReadUInt32(entry + APP_TIME0);
					uint time1	= view.ReadUInt32(entry + APP_TIME1);
					uint frames	= view.ReadUInt32(entry + APP_FRAMES);
					if (time0 == 0 || time1 <= time0)
						return false;

					fps = 1000.0 * frames / (time1 - time0);
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
