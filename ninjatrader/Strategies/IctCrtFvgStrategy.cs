#region Using declarations
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

// =====================================================================
// Estrategia ICT: CRT (Candle Range Theory) + FVG / IFVG
// ---------------------------------------------------------------------
// Idea (metodología ICT):
//   1. Sesgo (bias) en un timeframe superior (HTF) usando CRT: si una
//      vela HTF barre (sweep) el máximo o mínimo de la vela HTF anterior
//      y CIERRA de nuevo dentro del rango de esa vela anterior, se
//      interpreta como una toma de liquidez que da sesgo direccional
//      (alcista si barrió el mínimo, bajista si barrió el máximo).
//   2. Entrada de precisión en el timeframe de ejecución (LTF, el
//      timeframe del gráfico) usando Fair Value Gaps (FVG) e Inverse
//      FVG (IFVG), tal como el indicador de referencia en
//      indicators/fvg_ifvg.pine, pero SOLO en la dirección del sesgo
//      CRT vigente.
//   3. Gestión de riesgo: stop más allá del borde del gap/zona, take
//      profit como múltiplo R, límite de operaciones y de pérdida
//      diaria, y ventana horaria de entrada.
//
// Pensada para futuros micro E-mini (MES, MNQ) pero funciona con
// cualquier instrumento con tick size definido, ya que el stop/target
// se calculan en precio y se redondean al tick del instrumento.
//
// AVISO: esto es una plantilla de trading automático. Antes de operar
// en real: 1) compilar y revisar en el NinjaScript Editor, 2) backtest
// en Strategy Analyzer, 3) Sim101 en tiempo real durante un período
// razonable. No es asesoría financiera.
// =====================================================================

namespace NinjaTrader.NinjaScript.Strategies
{
	public class IctCrtFvgStrategy : Strategy
	{
		#region Tipos internos

		private enum BiasDirection
		{
			None,
			Bullish,
			Bearish
		}

		private class FvgZone
		{
			public double Top;
			public double Bottom;
			public int CreatedBar;
			public string DrawTag;
		}

		#endregion

		#region Campos privados

		private ATR atr;

		// Zonas FVG activas (aún no mitigadas) y zonas IFVG (FVG invalidada -> zona invertida)
		private List<FvgZone> bullFvgZones;   // FVG alcistas sin mitigar
		private List<FvgZone> bearFvgZones;   // FVG bajistas sin mitigar
		private List<FvgZone> bullIfvgZones;  // Soporte (nace al invalidarse una FVG bajista)
		private List<FvgZone> bearIfvgZones;  // Resistencia (nace al invalidarse una FVG alcista)

		// Estado del sesgo CRT (timeframe superior)
		private BiasDirection bias = BiasDirection.None;
		private int biasExpiryBarLtf = -1;
		private bool biasUsed = false;
		private double biasRangeHigh = double.NaN;
		private double biasRangeLow = double.NaN;
		private DateTime biasRangeStartTime;

		// Conteo de sesión / control de riesgo diario
		private SessionIterator sessionIterator;
		private int tradesToday = 0;

		private const string LongSignal = "ICT_CRT_FVG_Long";
		private const string ShortSignal = "ICT_CRT_FVG_Short";

		private int zoneTagCounter = 0;

		#endregion

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description = "ICT: sesgo CRT (Candle Range Theory) en timeframe superior + entradas FVG/IFVG en el timeframe del gráfico. Pensada para futuros micro E-mini (MES/MNQ).";
				Name = "IctCrtFvgStrategy";
				Calculate = Calculate.OnBarClose;
				EntriesPerDirection = 1;
				EntryHandling = EntryHandling.AllEntries;
				IsExitOnSessionCloseStrategy = true;
				ExitOnSessionCloseSeconds = 30;
				IsFillLimitOnTouch = false;
				MaximumBarsLookBack = MaximumBarsLookBack.TwoHundredFiftySix;
				OrderFillResolution = OrderFillResolution.Standard;
				Slippage = 0;
				StartBehavior = StartBehavior.WaitUntilFlat;
				TimeInForce = TimeInForce.Gtc;
				TraceOrders = false;
				RealtimeErrorHandling = RealtimeErrorHandling.StopCancelClose;
				StopTargetHandling = StopTargetHandling.PerEntryExecution;
				BarsRequiredToTrade = 20;
				IsInstantiatedOnEachOptimizationIteration = true;
				IsOverlay = true;

				// --- Valores por defecto de parámetros ---
				UseDailyCrt = true;
				CrtTimeframeMinutes = 240;
				BiasExpiryBars = 60;
				OneTradePerBias = true;
				InvalidateBiasOnClose = true;

				MinGapAtrMult = 0.25;
				AtrPeriod = 14;
				MaxZonesPerSide = 20;

				EnableContinuationEntries = true;
				EnableBounceEntries = true;
				StopBufferTicks = 2;
				RewardRiskMultiple = 2.0;

				Contracts = 1;
				MaxTradesPerDay = 4;
				MaxDailyLossDollars = 300;
				EntryWindowStartHHMM = 930;
				EntryWindowEndHHMM = 1550;

				ShowZones = true;
				ShowCrtRange = true;
			}
			else if (State == State.Configure)
			{
				// Serie 1: timeframe superior (HTF) usado solo para calcular el sesgo CRT.
				if (UseDailyCrt)
					AddDataSeries(BarsPeriodType.Day, 1);
				else
					AddDataSeries(BarsPeriodType.Minute, Math.Max(1, CrtTimeframeMinutes));
			}
			else if (State == State.DataLoaded)
			{
				atr = ATR(AtrPeriod);

				bullFvgZones = new List<FvgZone>();
				bearFvgZones = new List<FvgZone>();
				bullIfvgZones = new List<FvgZone>();
				bearIfvgZones = new List<FvgZone>();

				sessionIterator = new SessionIterator(Bars);
			}
		}

		protected override void OnBarUpdate()
		{
			// BarsInProgress == 1 -> serie HTF: solo actualiza el sesgo CRT.
			if (BarsInProgress == 1)
			{
				UpdateCrtBias();
				return;
			}

			// BarsInProgress == 0 -> serie de ejecución (gráfico principal).
			if (CurrentBar < Math.Max(3, AtrPeriod + 1))
				return;

			ResetDailyCountersIfNewSession();

			ManageFvgMitigation();
			DetectNewFvgs();
			CheckBiasInvalidation();
			ExpireBiasIfNeeded();

			if (Position.MarketPosition == MarketPosition.Flat && CanOpenNewTrade())
				TryEnter();
		}

		protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
			int quantity, MarketPosition marketPosition, string orderId, DateTime time)
		{
			if (execution.Order == null)
				return;

			bool isEntryFill = (execution.Order.Name == LongSignal || execution.Order.Name == ShortSignal)
				&& execution.Order.OrderState == OrderState.Filled;

			if (isEntryFill)
			{
				tradesToday++;
				biasUsed = true;
			}
		}

		#region CRT (Candle Range Theory) — sesgo en timeframe superior

		private void UpdateCrtBias()
		{
			// Se necesita la vela HTF que se acaba de cerrar (index 0) y la vela de
			// rango de referencia anterior a ella (index 1).
			if (CurrentBars[1] < 1)
				return;

			double refHigh = Highs[1][1];
			double refLow = Lows[1][1];
			double curHigh = Highs[1][0];
			double curLow = Lows[1][0];
			double curClose = Closes[1][0];

			bool bullishSweep = curLow < refLow && curClose > refLow;
			bool bearishSweep = curHigh > refHigh && curClose < refHigh;

			// Si barre ambos lados en la misma vela (rango muy amplio) se descarta
			// por ambigüedad: no hay una toma de liquidez clara.
			if (bullishSweep && !bearishSweep)
				SetBias(BiasDirection.Bullish, refHigh, refLow);
			else if (bearishSweep && !bullishSweep)
				SetBias(BiasDirection.Bearish, refHigh, refLow);
		}

		private void SetBias(BiasDirection direction, double rangeHigh, double rangeLow)
		{
			bias = direction;
			biasRangeHigh = rangeHigh;
			biasRangeLow = rangeLow;
			biasRangeStartTime = Times[1][1];
			biasUsed = false;
			// El sesgo se referencia contra el conteo de barras de la serie principal (LTF).
			biasExpiryBarLtf = CurrentBars[0] + BiasExpiryBars;

			if (ShowCrtRange)
			{
				Brush zoneBrush = direction == BiasDirection.Bullish
					? Brushes.DodgerBlue
					: Brushes.OrangeRed;
				Draw.Rectangle(this, "CrtRange" + (zoneTagCounter++), false,
					biasRangeStartTime, rangeLow, Times[1][0], rangeHigh,
					zoneBrush, zoneBrush, 10);
			}
		}

		private void CheckBiasInvalidation()
		{
			if (!InvalidateBiasOnClose || bias == BiasDirection.None)
				return;

			if (bias == BiasDirection.Bullish && Close[0] < biasRangeLow)
				bias = BiasDirection.None;
			else if (bias == BiasDirection.Bearish && Close[0] > biasRangeHigh)
				bias = BiasDirection.None;
		}

		private void ExpireBiasIfNeeded()
		{
			if (bias != BiasDirection.None && CurrentBar > biasExpiryBarLtf)
				bias = BiasDirection.None;
		}

		#endregion

		#region FVG / IFVG — detección y gestión de zonas (timeframe de ejecución)

		private void DetectNewFvgs()
		{
			double atrVal = atr[0];

			bool bullGapUp = Low[0] > High[2];
			bool bearGapDn = High[0] < Low[2];

			double bullTop = Low[0];
			double bullBot = High[2];
			double bearTop = Low[2];
			double bearBot = High[0];

			bool bullSizeOk = MinGapAtrMult <= 0 || (bullTop - bullBot) >= atrVal * MinGapAtrMult;
			bool bearSizeOk = MinGapAtrMult <= 0 || (bearTop - bearBot) >= atrVal * MinGapAtrMult;

			if (bullGapUp && bullSizeOk)
				AddZone(bullFvgZones, bullTop, bullBot, "BullFvg", Brushes.Teal);

			if (bearGapDn && bearSizeOk)
				AddZone(bearFvgZones, bearTop, bearBot, "BearFvg", Brushes.Firebrick);
		}

		private void ManageFvgMitigation()
		{
			// FVG alcistas: se invalidan si el cierre perfora por debajo de su borde inferior.
			for (int i = bullFvgZones.Count - 1; i >= 0; i--)
			{
				FvgZone z = bullFvgZones[i];
				if (Close[0] < z.Bottom)
				{
					RemoveZone(bullFvgZones, i);
					// La zona se invierte: pasa a actuar como resistencia (IFVG bajista).
					AddZone(bearIfvgZones, z.Top, z.Bottom, "BearIfvg", Brushes.Fuchsia);
				}
			}

			// FVG bajistas: se invalidan si el cierre perfora por encima de su borde superior.
			for (int i = bearFvgZones.Count - 1; i >= 0; i--)
			{
				FvgZone z = bearFvgZones[i];
				if (Close[0] > z.Top)
				{
					RemoveZone(bearFvgZones, i);
					// La zona se invierte: pasa a actuar como soporte (IFVG alcista).
					AddZone(bullIfvgZones, z.Top, z.Bottom, "BullIfvg", Brushes.Lime);
				}
			}

			// Las IFVG desaparecen si vuelven a mitigarse (cierre las atraviesa de nuevo).
			for (int i = bullIfvgZones.Count - 1; i >= 0; i--)
			{
				if (Close[0] < bullIfvgZones[i].Bottom)
					RemoveZone(bullIfvgZones, i);
			}
			for (int i = bearIfvgZones.Count - 1; i >= 0; i--)
			{
				if (Close[0] > bearIfvgZones[i].Top)
					RemoveZone(bearIfvgZones, i);
			}
		}

		private void AddZone(List<FvgZone> zones, double top, double bottom, string tagPrefix, Brush brush)
		{
			var zone = new FvgZone
			{
				Top = top,
				Bottom = bottom,
				CreatedBar = CurrentBar,
				DrawTag = tagPrefix + (zoneTagCounter++)
			};
			zones.Add(zone);

			if (ShowZones)
			{
				Draw.Rectangle(this, zone.DrawTag, false, 2, top, 0, bottom, brush, brush, 20);
			}

			if (zones.Count > MaxZonesPerSide)
				RemoveZone(zones, 0);
		}

		private void RemoveZone(List<FvgZone> zones, int index)
		{
			FvgZone z = zones[index];
			if (ShowZones)
				RemoveDrawObject(z.DrawTag);
			zones.RemoveAt(index);
		}

		#endregion

		#region Entradas

		private bool CanOpenNewTrade()
		{
			if (bias == BiasDirection.None)
				return false;

			if (OneTradePerBias && biasUsed)
				return false;

			int nowHHMM = Time[0].Hour * 100 + Time[0].Minute;
			if (nowHHMM < EntryWindowStartHHMM || nowHHMM > EntryWindowEndHHMM)
				return false;

			if (tradesToday >= MaxTradesPerDay)
				return false;

			if (GetTodayRealizedPnL() <= -Math.Abs(MaxDailyLossDollars))
				return false;

			return true;
		}

		private void TryEnter()
		{
			if (bias == BiasDirection.Bullish)
			{
				if (EnableContinuationEntries && TryEnterLongContinuation())
					return;
				if (EnableBounceEntries)
					TryEnterLongBounce();
			}
			else if (bias == BiasDirection.Bearish)
			{
				if (EnableContinuationEntries && TryEnterShortContinuation())
					return;
				if (EnableBounceEntries)
					TryEnterShortBounce();
			}
		}

		// Entrada de continuación: se acaba de formar una FVG alcista a favor del sesgo.
		private bool TryEnterLongContinuation()
		{
			if (bullFvgZones.Count == 0)
				return false;

			FvgZone z = bullFvgZones[bullFvgZones.Count - 1];
			if (z.CreatedBar != CurrentBar)
				return false;

			return SubmitLong(z.Bottom);
		}

		private bool TryEnterShortContinuation()
		{
			if (bearFvgZones.Count == 0)
				return false;

			FvgZone z = bearFvgZones[bearFvgZones.Count - 1];
			if (z.CreatedBar != CurrentBar)
				return false;

			return SubmitShort(z.Top);
		}

		// Entrada de rebote: el precio retesteó una zona IFVG a favor del sesgo y cerró
		// confirmando el rechazo.
		private bool TryEnterLongBounce()
		{
			for (int i = bullIfvgZones.Count - 1; i >= 0; i--)
			{
				FvgZone z = bullIfvgZones[i];
				bool touched = Low[0] <= z.Top;
				bool heldAsSupport = Close[0] > z.Bottom;
				if (touched && heldAsSupport)
					return SubmitLong(z.Bottom);
			}
			return false;
		}

		private bool TryEnterShortBounce()
		{
			for (int i = bearIfvgZones.Count - 1; i >= 0; i--)
			{
				FvgZone z = bearIfvgZones[i];
				bool touched = High[0] >= z.Bottom;
				bool heldAsResistance = Close[0] < z.Top;
				if (touched && heldAsResistance)
					return SubmitShort(z.Top);
			}
			return false;
		}

		private bool SubmitLong(double stopReferencePrice)
		{
			double tick = TickSize;
			double stopPrice = RoundTick(stopReferencePrice - StopBufferTicks * tick);
			double entryRef = Close[0];
			double risk = entryRef - stopPrice;

			if (risk <= 0)
				return false;

			double targetPrice = RoundTick(entryRef + risk * RewardRiskMultiple);

			SetStopLoss(LongSignal, CalculationMode.Price, stopPrice, false);
			SetProfitTarget(LongSignal, CalculationMode.Price, targetPrice);
			EnterLong(Contracts, LongSignal);
			return true;
		}

		private bool SubmitShort(double stopReferencePrice)
		{
			double tick = TickSize;
			double stopPrice = RoundTick(stopReferencePrice + StopBufferTicks * tick);
			double entryRef = Close[0];
			double risk = stopPrice - entryRef;

			if (risk <= 0)
				return false;

			double targetPrice = RoundTick(entryRef - risk * RewardRiskMultiple);

			SetStopLoss(ShortSignal, CalculationMode.Price, stopPrice, false);
			SetProfitTarget(ShortSignal, CalculationMode.Price, targetPrice);
			EnterShort(Contracts, ShortSignal);
			return true;
		}

		private double RoundTick(double price)
		{
			return Instrument.MasterInstrument.RoundToTickSize(price);
		}

		private double TickSize
		{
			get { return Instrument.MasterInstrument.TickSize; }
		}

		#endregion

		#region Riesgo diario / sesión

		private void ResetDailyCountersIfNewSession()
		{
			if (sessionIterator.IsNewSession(Time[0], false))
			{
				sessionIterator.CalculateTradingDay(Time[0], false);
				tradesToday = 0;
			}
		}

		// Suma el PnL realizado (en moneda de cuenta) de las operaciones cerradas hoy.
		// Nota: se aproxima usando la fecha de calendario del cierre de la operación;
		// en instrumentos con sesión overnight (ej. futuros) puede diferir levemente
		// del día de sesión de trading si se opera muy cerca de medianoche.
		private double GetTodayRealizedPnL()
		{
			double sum = 0;
			for (int i = SystemPerformance.AllTrades.Count - 1; i >= 0; i--)
			{
				Trade t = SystemPerformance.AllTrades[i];
				if (t.Exit.Time.Date != Time[0].Date)
					break;
				sum += t.ProfitCurrency;
			}
			return sum;
		}

		#endregion

		#region Parámetros

		[NinjaScriptProperty]
		[Display(Name = "Usar Diario como referencia CRT", GroupName = "1. CRT (sesgo)", Order = 1)]
		public bool UseDailyCrt { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Timeframe HTF (minutos, si no es Diario)", GroupName = "1. CRT (sesgo)", Order = 2)]
		public int CrtTimeframeMinutes { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Vigencia del sesgo (barras del gráfico)", GroupName = "1. CRT (sesgo)", Order = 3)]
		public int BiasExpiryBars { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Una sola operación por sesgo", GroupName = "1. CRT (sesgo)", Order = 4)]
		public bool OneTradePerBias { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Invalidar sesgo si el cierre rompe el rango contrario", GroupName = "1. CRT (sesgo)", Order = 5)]
		public bool InvalidateBiasOnClose { get; set; }

		[NinjaScriptProperty]
		[Range(0.0, double.MaxValue)]
		[Display(Name = "Tamaño mínimo del gap (x ATR)", GroupName = "2. FVG / IFVG", Order = 1)]
		public double MinGapAtrMult { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo ATR", GroupName = "2. FVG / IFVG", Order = 2)]
		public int AtrPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(1, 200)]
		[Display(Name = "Máx. zonas activas por tipo", GroupName = "2. FVG / IFVG", Order = 3)]
		public int MaxZonesPerSide { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Habilitar entradas de continuación (FVG nueva)", GroupName = "3. Entradas", Order = 1)]
		public bool EnableContinuationEntries { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Habilitar entradas de rebote (retest IFVG)", GroupName = "3. Entradas", Order = 2)]
		public bool EnableBounceEntries { get; set; }

		[NinjaScriptProperty]
		[Range(0, int.MaxValue)]
		[Display(Name = "Buffer de stop (ticks más allá de la zona)", GroupName = "3. Entradas", Order = 3)]
		public int StopBufferTicks { get; set; }

		[NinjaScriptProperty]
		[Range(0.1, double.MaxValue)]
		[Display(Name = "Múltiplo Riesgo:Beneficio (R)", GroupName = "3. Entradas", Order = 4)]
		public double RewardRiskMultiple { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Contratos por operación", GroupName = "4. Riesgo", Order = 1)]
		public int Contracts { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Máx. operaciones por día", GroupName = "4. Riesgo", Order = 2)]
		public int MaxTradesPerDay { get; set; }

		[NinjaScriptProperty]
		[Range(0.0, double.MaxValue)]
		[Display(Name = "Máx. pérdida diaria ($)", GroupName = "4. Riesgo", Order = 3)]
		public double MaxDailyLossDollars { get; set; }

		[NinjaScriptProperty]
		[Range(0, 2359)]
		[Display(Name = "Ventana de entrada - inicio (HHMM)", GroupName = "4. Riesgo", Order = 4)]
		public int EntryWindowStartHHMM { get; set; }

		[NinjaScriptProperty]
		[Range(0, 2359)]
		[Display(Name = "Ventana de entrada - fin (HHMM)", GroupName = "4. Riesgo", Order = 5)]
		public int EntryWindowEndHHMM { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Dibujar zonas FVG/IFVG", GroupName = "5. Visualización", Order = 1)]
		public bool ShowZones { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Dibujar rango CRT de referencia", GroupName = "5. Visualización", Order = 2)]
		public bool ShowCrtRange { get; set; }

		#endregion
	}
}
