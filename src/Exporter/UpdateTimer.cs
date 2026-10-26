// RTSS Overlay Preset — sensor update period.
//
// LHMDataProvider.exe (RTSS SDK, Tools\LHMDataProvider) calls ExportToXML from a window timer that is hard-coded to
// 1000 ms: SetTimer(LMHDP_UPDATE_TIMER_ID = 0x1337, 1000) on its hidden window "LHMDataProviderConnectWnd".
// ExportToXML runs on that window's thread, so this replaces the timer with a faster one — SetTimer with the same
// window and ID only changes the period. It is done on every call: the very first ExportToXML comes from the window's
// OnCreate before the provider starts its own 1000 ms timer, which would override a one-time change.
// The overlay itself refreshes every 500 ms (RefreshPeriod in the .ovl), so the sensors are never more than half a
// second old.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Exporter
{
	static class UpdateTimer
	{
		public const uint PERIOD = 500;		// ms

		const string WINDOW = "LHMDataProviderConnectWnd";
		const uint TIMER_ID = 0x1337;

		static IntPtr s_wnd;
		static bool s_failed;

		public static void Apply()
		{
			if (s_failed)
				return;

			if (s_wnd == IntPtr.Zero)
			{
				IntPtr wnd = FindWindow(null, WINDOW);

				// only our own provider window, and only from its thread (a timer cannot be changed from another thread)
				uint pid;
				uint thread = GetWindowThreadProcessId(wnd, out pid);
				if (wnd == IntPtr.Zero || pid != (uint)Process.GetCurrentProcess().Id || thread != GetCurrentThreadId())
				{
					s_failed = true;
					return;
				}
				s_wnd = wnd;
			}

			SetTimer(s_wnd, (UIntPtr)TIMER_ID, PERIOD, IntPtr.Zero);
		}

		[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string name);
		[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr wnd, out uint pid);
		[DllImport("user32.dll")] static extern UIntPtr SetTimer(IntPtr wnd, UIntPtr id, uint elapse, IntPtr func);
		[DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
	}
}
