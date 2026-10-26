// RTSS Overlay Preset — where RTSS puts the overlay on screen, so the overlay can adapt its own layout.
//
// RTSS anchors the overlay by its bounding box, and OverlayEditor emits the position and extent of hidden layers too.
// So while the compact line is shown, the box is still as tall as the full style, and at the bottom of the screen
// (negative PositionY) the line would hang above the edge. With this sensor the overlay moves the line to the bottom
// of its box when the overlay is anchored to the bottom.
//
// The position comes from the RTSS profile files: the foreground game's own profile (Profiles\<game>.exe.cfg), if it
// sets one, otherwise the global profile (Profiles\Global). Negative = offset from the right / bottom edge.
//
// Exported sensors: /overlay-preset/osd/data/0 "Position X", /overlay-preset/osd/data/1 "Position Y".
using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

namespace Exporter
{
	static class OsdPosition
	{
		const int MISSING = int.MinValue + 1;

		// Exporter.dll lives in <RTSS>\Plugins\Client\LHMDataProvider
		static readonly string s_profiles = Path.GetFullPath(Path.Combine(
			Path.GetDirectoryName(typeof(OsdPosition).Assembly.Location), @"..\..\..\Profiles"));

		public static string ToXml()
		{
			string global = Path.Combine(s_profiles, "Global");
			if (!File.Exists(global))
				return "";

			string app = RtssFramerate.ForegroundApp;
			app = String.IsNullOrEmpty(app) ? null : Path.Combine(s_profiles, Path.GetFileName(app) + ".cfg");

			int x = Read(app, global, "PositionX");
			int y = Read(app, global, "PositionY");

			return "<hardware>\n<id>/overlay-preset/osd</id><name>On-Screen Display</name><type>Cpu</type>\n" +
				   Sensor(0, "Position X", x) + Sensor(1, "Position Y", y) + "</hardware>\n";
		}

		/// <summary>An integer from the RTSS global profile (Profiles\Global).</summary>
		public static int ReadGlobal(string section, string key, int def)
		{
			try
			{
				return (int)GetPrivateProfileInt(section, key, def, Path.Combine(s_profiles, "Global"));
			}
			catch (Exception)
			{
				return def;
			}
		}

		static int Read(string app, string global, string key)
		{
			int v = MISSING;
			if (app != null && File.Exists(app))
				v = (int)GetPrivateProfileInt("OSD", key, MISSING, app);
			if (v == MISSING)
				v = (int)GetPrivateProfileInt("OSD", key, 0, global);
			return v;
		}

		static string Sensor(int index, string name, int value)
		{
			return "<sensor><id>/overlay-preset/osd/data/" + index + "</id><name>" + name + "</name><type>Data</type><value>" +
				   value.ToString(CultureInfo.InvariantCulture) + "</value></sensor>\n";
		}

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetPrivateProfileInt(string section, string key, int def, string file);
	}
}
