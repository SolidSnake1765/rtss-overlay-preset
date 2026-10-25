// RTSS Overlay Preset — memory data rate and live DRAM timings for Exporter.dll.
//
// Read through the PawnIO driver (PawnIOLib.dll from the PawnIO install) with the official read-only
// modules shipped next to this DLL:
//   IntelMCHBAR.bin — memory controller registers in MCHBAR (Intel)
//   AMDFamily17.bin — SMN reads of the UMC registers (AMD Zen, families 17h-1Ah)
//
// Register layouts (public documentation):
//   Intel 6th-10th gen (Skylake ... Comet Lake): Intel 8th/9th Gen Core datasheet vol. 2 (337345), MCHBAR CH0 4000h, CH1 4400h
//   Intel 11th gen desktop (Rocket Lake):        Intel 11th Gen Core datasheet vol. 2 (636761)
//   Intel 12th-14th gen (Alder/Raptor Lake):     Intel 12th Gen Core datasheet vol. 2 (767626)
//   AMD Zen 2-5 DDR4/DDR5 UMC:                   public UMC register map (SMN 0x50000 + channel << 20)
//
// Anything else, or values that do not pass the sanity check: data rate from SMBIOS, no timings.
using System;
using System.Globalization;
using System.IO;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Exporter
{
	internal static class MemoryTimings
	{
		const int SOURCE_NONE		= 0;
		const int SOURCE_SMBIOS		= 1;
		const int SOURCE_REGISTERS	= 2;

		const int REREAD_CALLS		= 30;	// ExportToXML is called ~1/s

		enum Platform { None, IntelSkylake, IntelRocketLake, IntelAlderLake, AmdZen }

		sealed class Timings
		{
			public double DataRate;		// MT/s, 0 = take SMBIOS
			public int CL, RCD, RP, RAS, RC, RFC, CWL, REFI, CommandRate, Gear;
		}

		static int		s_calls;
		static bool		s_valid;
		static int		s_source;
		static double	s_dataRate;
		static Timings	s_timings;
		static int		s_smbiosRate = -1;	// -1 = not read yet
		static bool		s_ddr5;
		static Platform	s_platform = (Platform)(-1);

		static IntPtr	s_pawnio = IntPtr.Zero;
		static bool		s_pawnioTried;
		static Mutex	s_pciMutex;

		[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
		static extern IntPtr LoadLibrary(string path);

		[DllImport("PawnIOLib.dll")]
		static extern int pawnio_open(out IntPtr handle);
		[DllImport("PawnIOLib.dll")]
		static extern int pawnio_load(IntPtr handle, byte[] blob, UIntPtr size);
		[DllImport("PawnIOLib.dll")]
		static extern int pawnio_execute(IntPtr handle, string name, ulong[] input, UIntPtr inputCount, ulong[] output, UIntPtr outputCount, out UIntPtr returned);
		[DllImport("PawnIOLib.dll")]
		static extern int pawnio_close(IntPtr handle);

		public static void Close()
		{
			if (s_pawnio != IntPtr.Zero)
			{
				try { pawnio_close(s_pawnio); } catch (Exception) { }
				s_pawnio = IntPtr.Zero;
			}
			s_valid = false;
		}

		public static string ToXml()
		{
			if (!s_valid || s_calls % REREAD_CALLS == 0)
				Refresh();
			s_calls++;

			if (s_source == SOURCE_NONE)
				return "";

			StringBuilder xml = new StringBuilder("<hardware>\n<id>/overlay-preset/memory</id><name>Memory Timings</name><type>Memory</type>\n");

			Sensor(xml, "clock/0", "Data Rate",		"Clock", s_dataRate);
			Sensor(xml, "clock/1", "Memory Clock",	"Clock", s_dataRate / 2);
			Sensor(xml, "data/0",  "Source",		"Data",  s_source);

			Timings t = s_timings;
			if (s_source == SOURCE_REGISTERS && t != null)
			{
				Sensor(xml, "timing/tcl",	"tCL",			"Timing", t.CL);
				Sensor(xml, "timing/trcd",	"tRCD",			"Timing", t.RCD);
				Sensor(xml, "timing/trp",	"tRP",			"Timing", t.RP);
				Sensor(xml, "timing/tras",	"tRAS",			"Timing", t.RAS);
				Sensor(xml, "timing/trc",	"tRC",			"Timing", t.RC);
				Sensor(xml, "timing/trfc",	"tRFC",			"Timing", t.RFC);
				if (t.CWL > 0)			Sensor(xml, "timing/tcwl",	"tCWL",			"Timing", t.CWL);
				if (t.REFI > 0)			Sensor(xml, "timing/trefi",	"tREFI",		"Timing", t.REFI);
				if (t.CommandRate > 0)	Sensor(xml, "timing/cr",	"Command Rate",	"Timing", t.CommandRate);
				if (t.Gear > 0)			Sensor(xml, "data/1",		"Gear",			"Data",   t.Gear);
			}

			xml.Append("</hardware>\n");
			return xml.ToString();
		}

		static void Sensor(StringBuilder xml, string id, string name, string type, double value)
		{
			xml.Append("<sensor><id>/overlay-preset/memory/").Append(id).Append("</id><name>").Append(name)
			   .Append("</name><type>").Append(type).Append("</type><value>")
			   .Append(value.ToString("F1", CultureInfo.InvariantCulture)).Append("</value></sensor>\n");
		}

		/////////////////////////////////////////////////////////////////////////////

		static void Refresh()
		{
			if (s_smbiosRate < 0)
				ReadSmbios();
			if ((int)s_platform == -1)
				s_platform = DetectPlatform();

			Timings t = null;
			try
			{
				switch (s_platform)
				{
				case Platform.IntelSkylake:		t = ReadIntelSkylake(); break;
				case Platform.IntelRocketLake:	t = ReadIntelRocketLake(); break;
				case Platform.IntelAlderLake:	t = ReadIntelAlderLake(); break;
				case Platform.AmdZen:			t = ReadAmdZen(); break;
				}
			}
			catch (Exception)
			{
				t = null;
			}

			if (t != null && IsPlausible(t))
			{
				double rate = t.DataRate;
				// cross-check with SMBIOS: more than 10% off (or unknown) means we trust SMBIOS for the data rate
				if (rate <= 0 || (s_smbiosRate > 0 && Math.Abs(rate - s_smbiosRate) > 0.1 * s_smbiosRate))
					rate = s_smbiosRate;

				s_timings	= t;
				s_dataRate	= rate;
				s_source	= SOURCE_REGISTERS;
				s_valid		= true;
				return;
			}

			if (s_smbiosRate > 0)
			{
				s_timings	= null;
				s_dataRate	= s_smbiosRate;
				s_source	= SOURCE_SMBIOS;
				s_valid		= true;
			}
		}

		// values outside of these ranges mean the register layout does not match this CPU
		static bool IsPlausible(Timings t)
		{
			return t.CL >= 5 && t.CL <= 80
				&& t.RCD >= 5 && t.RCD <= 120
				&& t.RP >= 5 && t.RP <= 120
				&& t.RAS >= 10 && t.RAS <= 250
				&& t.RC >= t.RAS && t.RC <= 400
				&& t.RFC >= 30 && t.RFC <= 3000;
		}

		static void ReadSmbios()
		{
			int rate = 0, type = 0;
			try
			{
				using (ManagementObjectSearcher searcher = new ManagementObjectSearcher("SELECT ConfiguredClockSpeed, Speed, SMBIOSMemoryType FROM Win32_PhysicalMemory"))
				{
					foreach (ManagementBaseObject module in searcher.Get())
					{
						int configured	= ToInt(module["ConfiguredClockSpeed"]);
						int speed		= ToInt(module["Speed"]);
						rate = Math.Max(rate, configured > 0 ? configured : speed);
						if (type == 0) type = ToInt(module["SMBIOSMemoryType"]);
					}
				}
			}
			catch (Exception)
			{
			}
			s_smbiosRate = rate;
			s_ddr5 = type == 34 || type == 35;		// DDR5 / LPDDR5
		}

		static int ToInt(object value)
		{
			try { return value == null ? 0 : Convert.ToInt32(value); }
			catch (Exception) { return 0; }
		}

		// "Intel64 Family 6 Model 183 Stepping 1, GenuineIntel" / "AMD64 Family 25 Model 97 Stepping 2, AuthenticAMD"
		static Platform DetectPlatform()
		{
			string id = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "";
			int family = 0, model = 0;
			string[] parts = id.Split(' ', ',');
			for (int i = 0; i + 1 < parts.Length; i++)
			{
				if (parts[i] == "Family") int.TryParse(parts[i + 1], out family);
				if (parts[i] == "Model")  int.TryParse(parts[i + 1], out model);
			}

			if (id.IndexOf("GenuineIntel", StringComparison.OrdinalIgnoreCase) >= 0 && family == 6)
			{
				switch (model)
				{
				case 0x4E: case 0x5E:				// Skylake
				case 0x8E: case 0x9E:				// Kaby Lake, Coffee Lake, Whiskey Lake, Amber Lake
				case 0xA5: case 0xA6:				// Comet Lake
					return Platform.IntelSkylake;
				case 0xA7:							// Rocket Lake
					return Platform.IntelRocketLake;
				case 0x97: case 0x9A:				// Alder Lake
				case 0xB7: case 0xBA: case 0xBF:	// Raptor Lake
					return Platform.IntelAlderLake;
				}
				return Platform.None;
			}

			if (id.IndexOf("AuthenticAMD", StringComparison.OrdinalIgnoreCase) >= 0 && family >= 0x17 && family <= 0x1A)
				return Platform.AmdZen;

			return Platform.None;
		}

		/////////////////////////////////////////////////////////////////////////////
		// PawnIO

		static bool OpenPawnIO(string moduleName)
		{
			if (s_pawnio != IntPtr.Zero)
				return true;
			if (s_pawnioTried)
				return false;
			s_pawnioTried = true;

			string module = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), moduleName);
			string library = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PawnIO\\PawnIOLib.dll");
			if (!File.Exists(module) || !File.Exists(library) || LoadLibrary(library) == IntPtr.Zero)
				return false;

			IntPtr handle;
			if (pawnio_open(out handle) != 0 || handle == IntPtr.Zero)
				return false;

			byte[] blob = File.ReadAllBytes(module);
			if (pawnio_load(handle, blob, (UIntPtr)(ulong)blob.Length) != 0)
			{
				// modules refuse to load on unsupported CPUs
				pawnio_close(handle);
				return false;
			}

			s_pawnio = handle;
			return true;
		}

		static ulong Call(string ioctl, long argument)
		{
			ulong[] output = new ulong[1];
			UIntPtr returned;
			if (pawnio_execute(s_pawnio, ioctl, new ulong[] { (ulong)argument }, (UIntPtr)1u, output, (UIntPtr)1u, out returned) != 0)
				throw new IOException(ioctl);
			return output[0];
		}

		static uint Mch32(long offset)	{ return (uint)Call("ioctl_read_dword", offset); }
		static ulong Mch64(long offset)	{ return Call("ioctl_read_qword", offset); }

		static int Bits(ulong value, int hi, int lo)
		{
			return (int)((value >> lo) & ((1UL << (hi - lo + 1)) - 1));
		}

		/////////////////////////////////////////////////////////////////////////////
		// Intel

		// 6th-10th gen: CH0 at 4000h, CH1 at 4400h; tRCD is shared with tRP; data rate from SMBIOS
		static Timings ReadIntelSkylake()
		{
			if (!OpenPawnIO("IntelMCHBAR.bin"))
				return null;

			foreach (long ch in new long[] { 0x0, 0x400 })
			{
				uint odt = Mch32(ch + 0x4070);				// TC_ODT
				int cl = Bits(odt, 20, 16);
				if (cl < 5)
					continue;								// unpopulated channel reads 0

				uint pre	= Mch32(ch + 0x4000);			// TC_PRE
				uint rftp	= Mch32(ch + 0x423C);			// TC_RFTP
				uint gs		= Mch32(ch + 0x401C);			// SC_GS_CFG

				Timings t = new Timings();
				t.CL	= cl;
				t.CWL	= Bits(odt, 25, 21);
				t.RP	= Bits(pre, 5, 0);
				t.RCD	= t.RP;
				t.RAS	= Bits(pre, 14, 8);
				t.RC	= t.RAS + t.RP;
				t.RFC	= Bits(rftp, 25, 16);
				t.REFI	= Bits(rftp, 15, 0);
				t.CommandRate = CommandRate(Bits(gs, 3, 2));
				return t;
			}
			return null;
		}

		// 11th gen desktop: CH0 at 4000h, CH1 at 4400h
		static Timings ReadIntelRocketLake()
		{
			if (!OpenPawnIO("IntelMCHBAR.bin"))
				return null;

			foreach (long ch in new long[] { 0x0, 0x400 })
			{
				ulong odt = Mch64(ch + 0x4070);				// TC_ODT (64 bit)
				int cl = Bits(odt, 21, 16);
				if (cl < 5)
					continue;

				uint pre	= Mch32(ch + 0x4000);			// TC_PRE
				uint rftp	= Mch32(ch + 0x423C);			// TC_RFTP
				ulong gs	= Mch64(ch + 0x4088);			// SC_GS_CFG
				uint bios	= Mch32(0x5E04);				// MC_BIOS_DATA

				Timings t = new Timings();
				t.CL	= cl;
				t.CWL	= Bits(odt, 27, 22);
				t.RP	= Bits(pre, 5, 0);
				t.RCD	= t.RP;
				t.RAS	= Bits(pre, 15, 9);
				t.RC	= t.RAS + t.RP;
				t.RFC	= Bits(rftp, 25, 16);
				t.REFI	= Bits(rftp, 15, 0);
				t.CommandRate = CommandRate(Bits(gs, 4, 3));
				t.Gear	= Bits(bios, 16, 16) == 1 ? 2 : 1;
				t.DataRate = DataRate(Bits(bios, 7, 0), Bits(bios, 11, 8), t.Gear);
				return t;
			}
			return null;
		}

		// 12th-14th gen: MC0/MC1 (+10000h), CH0/CH1 (+800h)
		static Timings ReadIntelAlderLake()
		{
			if (!OpenPawnIO("IntelMCHBAR.bin"))
				return null;

			foreach (long ch in new long[] { 0x0, 0x800, 0x10000, 0x10800 })
			{
				uint odt = Mch32(ch + 0xE070);				// TC_ODT
				int cl = Bits(odt, 22, 16);
				if (cl < 8)
					continue;								// unpopulated channel keeps reset defaults (tCL = 5)

				ulong pre	= Mch64(ch + 0xE000);			// TC_PRE
				uint rftp	= Mch32(ch + 0xE43C);			// TC_RFTP
				ulong gs	= Mch64(ch + 0xE088);			// SC_GS_CFG
				uint bios	= Mch32(0x5E04);				// MC_BIOS_DATA

				Timings t = new Timings();
				t.CL	= cl;
				t.CWL	= Bits(odt, 31, 24);
				t.RP	= Bits(pre, 7, 0);
				t.RAS	= Bits(pre, 50, 42);
				t.RCD	= Bits(pre, 58, 51);
				t.RC	= t.RAS + t.RP;
				t.RFC	= Bits(rftp, 30, 18);
				t.REFI	= Bits(rftp, 17, 0);
				t.CommandRate = CommandRate(Bits(gs, 4, 3));
				int gear = Bits(bios, 13, 12);				// 0 = Gear1, 1 = Gear2, 2 = Gear4
				t.Gear	= gear == 0 ? 1 : (gear == 1 ? 2 : 4);
				t.DataRate = DataRate(Bits(bios, 7, 0), Bits(bios, 11, 8), t.Gear);
				return t;
			}
			return null;
		}

		static int CommandRate(int stretch)			// 0 = 1N, 1 = 2N, 2 = 3N, 3 = N:1
		{
			return stretch < 3 ? stretch + 1 : 1;
		}

		static double DataRate(int ratio, int refType, int gear)	// refType 0 = 133.33 MHz, 1 = 100 MHz
		{
			return ratio * (refType == 1 ? 100.0 : 400.0 / 3.0) * gear;
		}

		/////////////////////////////////////////////////////////////////////////////
		// AMD Zen 2-5: UMC registers through SMN

		static uint Smn(long address)
		{
			return (uint)Call("ioctl_read_smn", address);
		}

		static Timings ReadAmdZen()
		{
			if (!OpenPawnIO("AMDFamily17.bin"))
				return null;

			// PCI config space access is shared with other monitoring tools
			if (s_pciMutex == null)
				s_pciMutex = new Mutex(false, "Global\\Access_PCI");

			bool locked = false;
			try
			{
				try { locked = s_pciMutex.WaitOne(100); }
				catch (AbandonedMutexException) { locked = true; }
				if (!locked)
					return null;

				for (long channel = 0; channel < 8; channel++)
				{
					long umc = channel << 20;

					bool enabled = Bits(Smn(umc | 0x50DF0), 19, 19) == 0
								&& ((Smn(umc | 0x50000) & 1) != 0 || (Smn(umc | 0x50008) & 1) != 0);
					if (!enabled)
						continue;

					uint cfg	= Smn(umc | 0x50200);
					uint t1		= Smn(umc | 0x50204);
					uint t2		= Smn(umc | 0x50208);
					uint t6		= Smn(umc | 0x50214);

					Timings t = new Timings();
					t.CL	= Bits(t1, 5, 0);
					t.RAS	= Bits(t1, 14, 8);
					t.RCD	= Bits(t1, 21, 16);
					t.RC	= Bits(t2, 7, 0);
					t.RP	= Bits(t2, 21, 16);
					t.CWL	= Bits(t6, 5, 0);

					if (s_ddr5)
					{
						t.CommandRate	= Bits(cfg, 17, 17) + 1;
						t.DataRate		= Bits(cfg, 15, 0) * 2.0;				// MEMCLK in MHz * 2
						foreach (long reg in new long[] { 0x50260, 0x50264, 0x50268, 0x5026C })
						{
							uint value = Smn(umc | reg);
							if (value != 0 && value != 0x00C00138) { t.RFC = Bits(value, 15, 0); break; }
						}
					}
					else
					{
						t.CommandRate	= Bits(cfg, 10, 10) + 1;
						t.DataRate		= Bits(cfg, 6, 0) / 3.0 * 100.0 * 2.0;	// ratio in 1/3 of 100 MHz
						uint rfc0 = Smn(umc | 0x50260), rfc1 = Smn(umc | 0x50264);
						uint rfc = rfc0 != rfc1 ? (rfc0 != 0x21060138 ? rfc0 : rfc1) : rfc0;
						t.RFC = Bits(rfc, 10, 0);
					}
					return t;
				}
				return null;
			}
			finally
			{
				if (locked)
					s_pciMutex.ReleaseMutex();
			}
		}
	}
}
