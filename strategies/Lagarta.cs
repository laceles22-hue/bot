#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using NinjaTrader.Cbi;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Gui.SuperDom;
using NinjaTrader.Gui.Tools;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;
using NinjaTrader.Core.FloatingPoint;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

// This namespace holds Strategies in this folder and is required. Do not change it.
namespace NinjaTrader.NinjaScript.Strategies
{
	/// <summary>
	/// Triple EMA trend-following strategy.
	///
	/// Uses a fast, slow and trend EMA. Enters long when the fast EMA crosses
	/// above the slow EMA while both are above the trend EMA, and enters short
	/// when the fast EMA crosses below the slow EMA while both are below the
	/// trend EMA. Risk is managed with fixed profit target and stop loss
	/// expressed in ticks.
	/// </summary>
	public class Lagarta : Strategy
	{
		private EMA fastEma;
		private EMA slowEma;
		private EMA trendEma;

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description									= @"Triple EMA (fast/slow/trend) crossover strategy with tick-based profit target and stop loss.";
				Name										= "Lagarta";
				Calculate									= Calculate.OnBarClose;
				EntriesPerDirection							= 1;
				EntryHandling								= EntryHandling.AllEntries;
				IsExitOnSessionCloseStrategy				= true;
				ExitOnSessionCloseSeconds					= 30;
				IsFillLimitOnTouch							= false;
				MaximumBarsLookBack							= MaximumBarsLookBack.TwoHundredFiftySix;
				OrderFillResolution							= OrderFillResolution.Standard;
				Slippage									= 0;
				StartBehavior								= StartBehavior.WaitUntilFlat;
				TimeInForce									= TimeInForce.Gtc;
				TraceOrders									= false;
				RealtimeErrorHandling						= RealtimeErrorHandling.StopCancelClose;
				StopTargetHandling							= StopTargetHandling.PerEntryExecution;
				BarsRequiredToTrade							= 20;
				// Disable this property for performance gains in Strategy Analyzer optimizations
				// See the Help Guide for additional information
				IsInstantiatedOnEachOptimizationIteration	= true;
				IncludeCommission							= false;

				FastPeriod									= 35;
				SlowPeriod									= 95;
				TrendPeriod									= 200;
				ProfitTargetTicks							= 50;
				StopLossTicks								= 32;
				UseTradingHours								= true;
				StartTime									= DateTime.Parse("09:30", System.Globalization.CultureInfo.InvariantCulture);
				EndTime										= DateTime.Parse("16:00", System.Globalization.CultureInfo.InvariantCulture);
			}
			else if (State == State.Configure)
			{
			}
			else if (State == State.DataLoaded)
			{
				fastEma		= EMA(FastPeriod);
				slowEma		= EMA(SlowPeriod);
				trendEma	= EMA(TrendPeriod);

				fastEma.Plots[0].Brush	= System.Windows.Media.Brushes.DodgerBlue;
				slowEma.Plots[0].Brush	= System.Windows.Media.Brushes.Orange;
				trendEma.Plots[0].Brush	= System.Windows.Media.Brushes.Gray;

				AddChartIndicator(fastEma);
				AddChartIndicator(slowEma);
				AddChartIndicator(trendEma);

				SetProfitTarget(CalculationMode.Ticks, ProfitTargetTicks);
				SetStopLoss(CalculationMode.Ticks, StopLossTicks);
			}
		}

		protected override void OnBarUpdate()
		{
			// Wait for enough bars to have the longest EMA (trend) fully formed
			if (CurrentBar <= TrendPeriod)
				return;

			// Avoid processing on the primary series if using multiple data series
			if (BarsInProgress != 0)
				return;

			// Only look for new entries inside the configured trading window
			if (!IsInTradingHours())
				return;

			bool fastAboveTrend		= fastEma[0] > trendEma[0];
			bool slowAboveTrend		= slowEma[0] > trendEma[0];
			bool fastBelowTrend		= fastEma[0] < trendEma[0];
			bool slowBelowTrend		= slowEma[0] < trendEma[0];

			bool longCondition		= CrossAbove(fastEma, slowEma, 1) && fastAboveTrend && slowAboveTrend;
			bool shortCondition		= CrossBelow(fastEma, slowEma, 1) && fastBelowTrend && slowBelowTrend;

			if (longCondition && Position.MarketPosition != MarketPosition.Long)
			{
				EnterLong("LongEntry");
			}
			else if (shortCondition && Position.MarketPosition != MarketPosition.Short)
			{
				EnterShort("ShortEntry");
			}
		}

		/// <summary>
		/// Returns true when the current bar's time falls inside [StartTime, EndTime].
		/// Only the hour/minute portion of StartTime/EndTime is used (they are
		/// edited as time-of-day pickers in the UI). Supports overnight windows
		/// where EndTime is earlier than StartTime (e.g. 22:00 -> 06:00).
		/// Returns true unconditionally when UseTradingHours is disabled.
		/// </summary>
		private bool IsInTradingHours()
		{
			if (!UseTradingHours)
				return true;

			int currentTime	= ToTime(Time[0]);
			int startTime		= StartTime.Hour * 10000 + StartTime.Minute * 100;
			int endTime			= EndTime.Hour * 10000 + EndTime.Minute * 100;

			if (startTime <= endTime)
				return currentTime >= startTime && currentTime <= endTime;

			return currentTime >= startTime || currentTime <= endTime;
		}

		#region Properties

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Fast Period", Description = "Period for the fast EMA", Order = 1, GroupName = "Parameters")]
		public int FastPeriod
		{ get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Slow Period", Description = "Period for the slow EMA", Order = 2, GroupName = "Parameters")]
		public int SlowPeriod
		{ get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Trend Period", Description = "Period for the trend EMA", Order = 3, GroupName = "Parameters")]
		public int TrendPeriod
		{ get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Profit Target (Ticks)", Description = "Profit target in ticks", Order = 1, GroupName = "Risk Management")]
		public int ProfitTargetTicks
		{ get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Stop Loss (Ticks)", Description = "Stop loss in ticks", Order = 2, GroupName = "Risk Management")]
		public int StopLossTicks
		{ get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Enable Trading Hours", Description = "When checked, entries are only taken between Start Time and End Time", Order = 1, GroupName = "Session Hours")]
		public bool UseTradingHours
		{ get; set; }

		[NinjaScriptProperty]
		[PropertyEditor("NinjaTrader.Gui.Tools.TimeEditorKey")]
		[Display(Name = "Start Time", Description = "Start of the trading window", Order = 2, GroupName = "Session Hours")]
		public DateTime StartTime
		{ get; set; }

		[NinjaScriptProperty]
		[PropertyEditor("NinjaTrader.Gui.Tools.TimeEditorKey")]
		[Display(Name = "End Time", Description = "End of the trading window (can be earlier than Start Time for an overnight window)", Order = 3, GroupName = "Session Hours")]
		public DateTime EndTime
		{ get; set; }

		#endregion
	}
}
