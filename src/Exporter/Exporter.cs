// RTSS Overlay Preset — Exporter.dll for RTSS LHMDataProvider.
//
// RTSS (7.3.7+) ships LHMDataProvider.exe, which loads Importer.dll, which calls
// Exporter.ExportClass.ExportToXML(bool) once per second (this DLL makes it every 500 ms, UpdateTimer.cs) and publishes the returned XML
// through shared memory to the OverlayEditor plugin. This is an independent implementation
// of that contract on top of LibreHardwareMonitorLib, plus an extra "/overlay-preset/memory" block
// with the memory data rate and the live DRAM timings, and "/overlay-preset/fg" — whether the foreground
// game has a frame generation library (FrameGenProbe.cs), "/overlay-preset/fgr" — the frame generation rhythm
// and multiplier from PresentMon frame data (FrameRhythm.cs), and "/overlay-preset/fps" — the foreground game's
// framerate per sensor update from RTSS shared memory (RtssFramerate.cs), and "/overlay-preset/osd" — where RTSS
// places the overlay (OsdPosition.cs).
//
// XML contract (parsed by OverlayEditor's LHMParser):
//   <hardware>\n<id>..</id><name>..</name><type>..</type>\n
//     <subhardware>\n<id>..</id><name>..</name><type>..</type>\n<sensor>..</sensor>\n..</subhardware>\n
//     <sensor><id>..</id><name>..</name><type>..</type><value>..</value></sensor>\n
//   </hardware>\n
// Values may use ',' or '.', the parser normalises both.
//
// License: MIT (see LICENSE). Build: build.cmd (csc.exe from .NET Framework 4.x, C# 5).
using System;
using System.Globalization;
using System.IO;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using LibreHardwareMonitor.Hardware;

[assembly: AssemblyTitle("Exporter")]
[assembly: AssemblyProduct("RTSS Overlay Preset")]
[assembly: AssemblyDescription("LibreHardwareMonitor exporter for RTSS with live DRAM timings")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: ComVisible(false)]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]

namespace Exporter
{
	public static class ExportClass
	{
		static readonly Computer s_computer = CreateComputer();
		static readonly UpdateVisitor s_visitor = new UpdateVisitor();

		/// <summary>Called by RTSS Importer.dll. bUninit = true on provider shutdown.</summary>
		public static string ExportToXML(bool bUninit)
		{
			UpdateTimer.Apply();		// 1000 → 500 ms (UpdateTimer.cs)

			StringBuilder xml = new StringBuilder(32 * 1024);

			try
			{
				s_computer.Open();
				s_computer.Accept(s_visitor);

				foreach (IHardware hardware in s_computer.Hardware)
					AppendHardware(xml, hardware);
			}
			catch (Exception)
			{
			}

			try
			{
				xml.Append(MemoryTimings.ToXml());
			}
			catch (Exception)
			{
			}

			try
			{
				xml.Append(FrameGenProbe.ToXml());
			}
			catch (Exception)
			{
			}

			try
			{
				xml.Append(FrameRhythm.ToXml());
			}
			catch (Exception)
			{
			}

			try
			{
				xml.Append(RtssFramerate.ToXml());
			}
			catch (Exception)
			{
			}

			try
			{
				xml.Append(OsdPosition.ToXml());		// after RtssFramerate: uses its foreground application
			}
			catch (Exception)
			{
			}

			if (bUninit)
			{
				s_computer.Close();
				MemoryTimings.Close();
			}

			return xml.ToString();
		}

		static Computer CreateComputer()
		{
			Computer computer = new Computer();
			computer.IsMotherboardEnabled	= true;
			computer.IsCpuEnabled			= true;
			computer.IsMemoryEnabled		= true;
			computer.IsGpuEnabled			= true;

			// optional Exporter.config next to the DLL: <configuration><cpu>true</cpu>...</configuration>
			try
			{
				string config = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "Exporter.config");
				if (File.Exists(config))
				{
					XmlDocument doc = new XmlDocument();
					doc.Load(config);
					if (doc.DocumentElement != null)
					{
						foreach (XmlNode node in doc.DocumentElement.ChildNodes)
						{
							bool enabled;
							if (!bool.TryParse(node.InnerText, out enabled))
								continue;

							switch (node.Name)
							{
							case "motherboard":	computer.IsMotherboardEnabled	= enabled; break;
							case "cpu":			computer.IsCpuEnabled			= enabled; break;
							case "memory":		computer.IsMemoryEnabled		= enabled; break;
							case "gpu":			computer.IsGpuEnabled			= enabled; break;
							case "controller":	computer.IsControllerEnabled	= enabled; break;
							case "storage":		computer.IsStorageEnabled		= enabled; break;
							case "network":		computer.IsNetworkEnabled		= enabled; break;
							case "psu":			computer.IsPsuEnabled			= enabled; break;
							case "battery":		computer.IsBatteryEnabled		= enabled; break;
							}
						}
					}
				}
			}
			catch (Exception)
			{
			}

			return computer;
		}

		static void AppendHardware(StringBuilder xml, IHardware hardware)
		{
			xml.Append("<hardware>\n");
			AppendHeader(xml, hardware);

			foreach (IHardware sub in hardware.SubHardware)
			{
				xml.Append("<subhardware>\n");
				AppendHeader(xml, sub);
				foreach (ISensor sensor in sub.Sensors)
					AppendSensor(xml, sensor);
				xml.Append("</subhardware>\n");
			}

			foreach (ISensor sensor in hardware.Sensors)
				AppendSensor(xml, sensor);

			xml.Append("</hardware>\n");
		}

		static void AppendHeader(StringBuilder xml, IHardware hardware)
		{
			xml.Append("<id>").Append(hardware.Identifier).Append("</id><name>").Append(Escape(hardware.Name))
			   .Append("</name><type>").Append(hardware.HardwareType).Append("</type>\n");
		}

		static void AppendSensor(StringBuilder xml, ISensor sensor)
		{
			string value = "";
			if (sensor.Value.HasValue)
			{
				// voltages and currents need three decimals, everything else one
				bool fine = sensor.SensorType == SensorType.Voltage || sensor.SensorType == SensorType.Current;
				value = sensor.Value.Value.ToString(fine ? "F3" : "F1", CultureInfo.InvariantCulture);
			}

			xml.Append("<sensor><id>").Append(sensor.Identifier).Append("</id><name>").Append(Escape(sensor.Name))
			   .Append("</name><type>").Append(sensor.SensorType).Append("</type><value>").Append(value).Append("</value></sensor>\n");
		}

		static string Escape(string text)
		{
			return text == null ? "" : text.Replace("&", "and").Replace("<", "(").Replace(">", ")");
		}

		sealed class UpdateVisitor : IVisitor
		{
			public void VisitComputer(IComputer computer)		{ computer.Traverse(this); }
			public void VisitHardware(IHardware hardware)
			{
				hardware.Update();
				foreach (IHardware sub in hardware.SubHardware)
					sub.Accept(this);
			}
			public void VisitSensor(ISensor sensor)				{ }
			public void VisitParameter(IParameter parameter)	{ }
		}
	}

}
