// RTSS Overlay Preset — average / 1% low / 0.1% low framerate of the game's real frames under frame generation.
//
// RTSS counts every presented frame, generated ones too, so with in-game frame generation its AVG is the total FPS and
// its lows come from the gaps between real and generated frames. Here the frame times RTSS records (RtssFramerate.cs)
// are summed in groups of the frame generation multiplier: with xN every N consecutive frame times add up to exactly one
// real frame, whatever frame the group starts at. Without in-game frame generation N = 1 and the numbers match RTSS.
//
// Same rules as RTSS (verified against its shared memory values):
//   AVG = frames / time;
//   1% / 0.1% low, "integral" mode (RTSS default, [Statistics] PercentileCalc=0): the frame time at which the sum of the
//   slowest frames reaches 1% / 0.1% of the total time; "percentile" mode (PercentileCalc=1): the frame time of the
//   slowest 1% / 0.1% of frames;
//   max = the best framerate over one-second windows (RTSS dwStatFramerateMax is per second too, not per frame);
//   reset together with RTSS statistics (benchmark hotkey) — when its statistics start time changes.
// Frame times are kept in a histogram with 0.05 ms bins, so the lows are accurate to about 0.3 % at 60 FPS.
using System;

namespace Exporter
{
	static class NativeStats
	{
		const double BIN_US = 50;					// bin width, microseconds
		const int BINS = 40000;						// up to 2 s; slower frames go to the last bin with their real time
		const int LAST = BINS - 1;

		static readonly long[] s_count = new long[BINS];
		static double s_lastBinTime;					// sum of frame times in the last (overflow) bin
		static long s_frames;
		static double s_time;							// microseconds

		static double s_group;						// frame time of the real frame being summed
		static int s_inGroup;

		static double s_secTime;						// current one-second window for the max framerate
		static int s_secFrames;
		static double s_max;

		public static void Reset()
		{
			Array.Clear(s_count, 0, BINS);
			s_lastBinTime = 0;
			s_frames = 0;
			s_time = 0;
			s_group = 0;
			s_inGroup = 0;
			s_secTime = 0;
			s_secFrames = 0;
			s_max = 0;
		}

		/// <summary>One frame time from RTSS, microseconds; multiplier — current frame generation multiplier (1 = none,
		/// 0 = unknown yet: the frame is skipped).</summary>
		public static void Add(uint frameTimeUs, int multiplier)
		{
			if (multiplier < 1)
			{
				s_group = 0;
				s_inGroup = 0;
				return;
			}
			s_group += frameTimeUs;
			if (++s_inGroup < multiplier)
				return;

			double ft = s_group;
			s_group = 0;
			s_inGroup = 0;

			int bin = (int)(ft / BIN_US);
			if (bin >= LAST)
			{
				bin = LAST;
				s_lastBinTime += ft;
			}
			s_count[bin]++;
			s_frames++;
			s_time += ft;

			s_secTime += ft;
			s_secFrames++;
			if (s_secTime >= 1e6)
			{
				s_max = Math.Max(s_max, 1e6 * s_secFrames / s_secTime);
				s_secTime = 0;
				s_secFrames = 0;
			}
		}

		public static bool TryGet(bool percentile, out double avg, out double low1, out double low01, out double max)
		{
			avg = low1 = low01 = max = 0;
			if (s_frames < 10 || s_time <= 0)
				return false;
			avg = 1e6 * s_frames / s_time;
			max = s_max > 0 ? s_max : avg;
			low1 = 1e6 / Slowest(0.01, percentile);
			low01 = 1e6 / Slowest(0.001, percentile);
			return true;
		}

		// frame time (us) of the slowest frames that make up the given share of time (integral) or of frames (percentile)
		static double Slowest(double share, bool percentile)
		{
			double target = percentile ? share * s_frames : share * s_time;
			double acc = 0;
			for (int bin = LAST; bin >= 0; bin--)
			{
				long n = s_count[bin];
				if (n == 0)
					continue;
				double ft = bin == LAST ? s_lastBinTime / n : (bin + 0.5) * BIN_US;
				acc += percentile ? n : n * ft;
				if (acc >= target)
					return ft;
			}
			return s_time / s_frames;
		}
	}
}
