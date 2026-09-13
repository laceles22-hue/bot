#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using NinjaTrader.Cbi;
using NinjaTrader.Gui.Tools;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.Indicators;
using NinjaTrader.NinjaScript.Strategies;
#endregion

// ============================================================================================
// TripleMACrossPropFutures
// ---------------------------------------------------------------------------------------------
// Estrategia mecanica de triple cruce de medias moviles para cuentas de fondeo de FUTUROS
// (Apex Trader Funding / Bulenox y firmas con reglas de "trailing threshold drawdown"
// calculado a cierre de dia -EOD-, tipo Topstep-style). Disenada para operativa intradia
// en indices (MNQ/NQ, MYM/YM, MES/ES, etc.) en NinjaTrader 8.
//
// IMPORTANTE - LEE ANTES DE USAR EN CUENTA REAL:
//   1) Los valores por defecto (drawdown, profit target, tick value, etc.) son una
//      aproximacion tipica de cuentas de 50K de Apex/Bulenox a fecha de escritura de este
//      codigo. Las prop firms cambian sus reglas con frecuencia: VERIFICA los numeros
//      exactos de tu cuenta en el panel de tu prop firm antes de operar en real.
//   2) Este codigo NO ha sido testeado en el Strategy Analyzer de NinjaTrader (este entorno
//      no tiene NinjaTrader instalado ni datos historicos). Debes compilarlo e importarlo en
//      tu propia instalacion de NinjaTrader 8 y correr un backtest / forward test en
//      simulador antes de arriesgar capital real o una cuenta de evaluacion.
//   3) Ninguna estrategia mecanica garantiza pasar una evaluacion ni evitar un drawdown.
//      Los kill-switches de esta estrategia son una ayuda, no una garantia: la prop firm
//      calcula el drawdown con SU broker/feed, que puede diferir ligeramente del calculo
//      interno de esta estrategia (slippage, comisiones, horario de servidor, etc.).
// ============================================================================================

namespace NinjaTrader.NinjaScript.Strategies
{
	public enum MovingAverageType
	{
		SMA,
		EMA
	}

	public enum TrailingDrawdownMode
	{
		// Recalcula el "peak" de balance solo al cierre de cada sesion (estilo Apex/Bulenox:
		// el trailing drawdown se mueve con el balance de cierre del dia, no intradia).
		EndOfDaySession,
		// Recalcula el "peak" en tiempo real con cada nuevo maximo de equity intradia
		// (estilo Topstep: trailing drawdown intradia tick a tick).
		RealTimeIntraday
	}

	public class TripleMACrossPropFutures : Strategy
	{
		// ------------------------------------------------------------------------------------
		// Indicadores
		// ------------------------------------------------------------------------------------
		private NinjaTrader.NinjaScript.Indicators.SMA fastSma, mediumSma, slowSma;
		private NinjaTrader.NinjaScript.Indicators.EMA fastEma, mediumEma, slowEma;
		private ATR atr;

		// ------------------------------------------------------------------------------------
		// Estado interno de gestion de riesgo / kill-switches
		// ------------------------------------------------------------------------------------
		private double tickValue;                 // $ por tick por contrato
		private double sessionStartEquity;         // equity al inicio del dia (para DD diario)
		private double trailingPeakEquity;         // pico de equity usado para el trailing DD
		private double trailingLockLevel;          // nivel en el que el trailing DD "se congela"
		private bool trailingLocked;               // true cuando el trailing ya se congelo
		private DateTime currentTradingDay = DateTime.MinValue;
		private bool dailyHalted;                  // kill-switch diario activo
		private bool totalHalted;                  // kill-switch total activo (irreversible en la corrida)
		private int barsSinceBullAlignment = int.MaxValue;
		private int barsSinceBearAlignment = int.MaxValue;
		private double lastClosedTradesPnL;        // cache de PnL realizado acumulado

		#region Parametros configurables

		[NinjaScriptProperty]
		[Display(Name = "Tipo de media movil", GroupName = "1. Medias moviles", Order = 0)]
		public MovingAverageType MAType { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo media rapida", GroupName = "1. Medias moviles", Order = 1)]
		public int FastPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo media media", GroupName = "1. Medias moviles", Order = 2)]
		public int MediumPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo media lenta", GroupName = "1. Medias moviles", Order = 3)]
		public int SlowPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Max. velas desde alineacion (evita entradas tardias)", GroupName = "1. Medias moviles", Order = 4)]
		public int MaxCrossAgeBars { get; set; }

		[NinjaScriptProperty]
		[Range(0, int.MaxValue)]
		[Display(Name = "Separacion minima media-lenta (ticks, evita mercado plano)", GroupName = "1. Medias moviles", Order = 5)]
		public int MinMASeparationTicks { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Usar filtro ATR minimo", GroupName = "2. Filtros", Order = 0)]
		public bool UseATRFilter { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo ATR", GroupName = "2. Filtros", Order = 1)]
		public int ATRPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(0, int.MaxValue)]
		[Display(Name = "ATR minimo en ticks para operar", GroupName = "2. Filtros", Order = 2)]
		public int MinATRTicks { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Hora inicio operativa (hora de la sesion del grafico)", GroupName = "3. Horario", Order = 0)]
		public TimeSpan SessionStartTime { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Hora fin de nuevas entradas", GroupName = "3. Horario", Order = 1)]
		public TimeSpan SessionEndTime { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Hora de cierre forzado de posiciones", GroupName = "3. Horario", Order = 2)]
		public TimeSpan FlattenTime { get; set; }

		[NinjaScriptProperty]
		[Range(0.01, 100)]
		[Display(Name = "Riesgo por operacion (% del capital inicial)", GroupName = "4. Riesgo", Order = 0)]
		public double RiskPercentPerTrade { get; set; }

		[NinjaScriptProperty]
		[Range(0.1, 100)]
		[Display(Name = "Multiplicador ATR para Stop Loss", GroupName = "4. Riesgo", Order = 1)]
		public double ATRStopMultiplier { get; set; }

		[NinjaScriptProperty]
		[Range(0.1, 100)]
		[Display(Name = "Ratio Riesgo:Beneficio (TP = SL * ratio)", GroupName = "4. Riesgo", Order = 2)]
		public double RewardRiskRatio { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Maximo de contratos por operacion", GroupName = "4. Riesgo", Order = 3)]
		public int MaxContracts { get; set; }

		[NinjaScriptProperty]
		[Range(0, double.MaxValue)]
		[Display(Name = "Capital inicial de la cuenta ($)", GroupName = "5. Reglas prop firm", Order = 0)]
		public double StartingBalance { get; set; }

		[NinjaScriptProperty]
		[Range(0.01, 100)]
		[Display(Name = "Kill-switch diario (% de perdida sobre capital inicial)", GroupName = "5. Reglas prop firm", Order = 1)]
		public double DailyLossLimitPercent { get; set; }

		[NinjaScriptProperty]
		[Range(0, double.MaxValue)]
		[Display(Name = "Max. Trailing Drawdown ($, ej. 2500 en cuenta 50K Apex/Bulenox)", GroupName = "5. Reglas prop firm", Order = 2)]
		public double MaxTrailingDrawdown { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Modo de calculo del trailing drawdown", GroupName = "5. Reglas prop firm", Order = 3)]
		public TrailingDrawdownMode TrailingMode { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Congelar trailing al alcanzar capital inicial + Max Trailing DD (estilo Apex)", GroupName = "5. Reglas prop firm", Order = 4)]
		public bool TrailingLockEnabled { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Activar regla de consistencia (ningun dia > X% del profit total)", GroupName = "5. Reglas prop firm", Order = 5)]
		public bool ConsistencyRuleEnabled { get; set; }

		[NinjaScriptProperty]
		[Range(1, 100)]
		[Display(Name = "Consistencia: % maximo de un solo dia sobre el profit total", GroupName = "5. Reglas prop firm", Order = 6)]
		public double ConsistencyMaxDayPercent { get; set; }

		#endregion

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description = "Triple cruce de medias moviles con gestion de riesgo para cuentas de fondeo de futuros (Apex/Bulenox style).";
				Name = "TripleMACrossPropFutures";
				Calculate = Calculate.OnBarClose;
				EntriesPerDirection = 1;
				EntryHandling = EntryHandling.AllEntries;
				IsExitOnSessionCloseStrategy = false; // el cierre forzado lo gestionamos nosotros (hora configurable)
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
				BarsRequiredToTrade = 50;
				IsInstantiatedOnEachOptimizationIteration = true;

				// --- Valores por defecto: 3 medias, futuros de indice intradia, cuenta 50K Apex/Bulenox ---
				MAType = MovingAverageType.EMA;
				FastPeriod = 8;
				MediumPeriod = 21;
				SlowPeriod = 50;
				MaxCrossAgeBars = 3;
				MinMASeparationTicks = 10;

				UseATRFilter = true;
				ATRPeriod = 14;
				MinATRTicks = 15;

				// Horario de sesion regular de EE.UU. (hora de Nueva York / hora del grafico).
				// Ajusta segun el time zone configurado en tus datos de NinjaTrader.
				SessionStartTime = new TimeSpan(9, 45, 0);   // evita el primer ruido de apertura (9:30)
				SessionEndTime = new TimeSpan(15, 30, 0);    // no abrir nuevas entradas tras esta hora
				FlattenTime = new TimeSpan(15, 55, 0);        // cierre forzado antes del cierre de sesion (16:00 ET)

				RiskPercentPerTrade = 0.5;
				ATRStopMultiplier = 1.5;
				RewardRiskRatio = 2.0;
				MaxContracts = 1;

				StartingBalance = 50000;
				DailyLossLimitPercent = 1.0;      // kill-switch diario propio (autoimpuesto, mas estricto que la firm)
				MaxTrailingDrawdown = 2500;        // tipico Apex/Bulenox cuenta 50K
				TrailingMode = TrailingDrawdownMode.EndOfDaySession;
				TrailingLockEnabled = true;        // Apex "congela" el trailing al llegar a balance inicial + maxDD
				ConsistencyRuleEnabled = true;
				ConsistencyMaxDayPercent = 30;
			}
			else if (State == State.Configure)
			{
			}
			else if (State == State.DataLoaded)
			{
				if (MAType == MovingAverageType.SMA)
				{
					fastSma = SMA(FastPeriod);
					mediumSma = SMA(MediumPeriod);
					slowSma = SMA(SlowPeriod);
					AddChartIndicator(fastSma);
					AddChartIndicator(mediumSma);
					AddChartIndicator(slowSma);
				}
				else
				{
					fastEma = EMA(FastPeriod);
					mediumEma = EMA(MediumPeriod);
					slowEma = EMA(SlowPeriod);
					AddChartIndicator(fastEma);
					AddChartIndicator(mediumEma);
					AddChartIndicator(slowEma);
				}

				atr = ATR(ATRPeriod);

				tickValue = TickSize * Instrument.MasterInstrument.PointValue;

				sessionStartEquity = StartingBalance;
				trailingPeakEquity = StartingBalance;
				trailingLockLevel = StartingBalance + MaxTrailingDrawdown;
				trailingLocked = false;
				dailyHalted = false;
				totalHalted = false;
				lastClosedTradesPnL = 0;
			}
		}

		// Series activas segun el tipo de media elegido (evita duplicar logica abajo)
		private double Fast(int barsAgo) { return MAType == MovingAverageType.SMA ? fastSma[barsAgo] : fastEma[barsAgo]; }
		private double Medium(int barsAgo) { return MAType == MovingAverageType.SMA ? mediumSma[barsAgo] : mediumEma[barsAgo]; }
		private double Slow(int barsAgo) { return MAType == MovingAverageType.SMA ? slowSma[barsAgo] : slowEma[barsAgo]; }

		private ISeries<double> FastSeries { get { return MAType == MovingAverageType.SMA ? (ISeries<double>)fastSma : fastEma; } }
		private ISeries<double> MediumSeries { get { return MAType == MovingAverageType.SMA ? (ISeries<double>)mediumSma : mediumEma; } }

		protected override void OnBarUpdate()
		{
			if (BarsInProgress != 0 || CurrentBar < BarsRequiredToTrade)
				return;

			// ------------------------------------------------------------------------------
			// 1) Gestion de dia de trading: reset de contadores diarios
			// ------------------------------------------------------------------------------
			if (Time[0].Date != currentTradingDay)
			{
				currentTradingDay = Time[0].Date;
				dailyHalted = false;
				sessionStartEquity = StartingBalance + GetClosedTradesPnL();

				if (TrailingMode == TrailingDrawdownMode.EndOfDaySession)
					UpdateTrailingPeak(StartingBalance + GetClosedTradesPnL());
			}

			double closedPnL = GetClosedTradesPnL();
			double openPnL = Position.MarketPosition != MarketPosition.Flat
				? Position.GetUnrealizedProfitLoss(PerformanceUnit.Currency, Close[0])
				: 0.0;
			double currentEquity = StartingBalance + closedPnL + openPnL;

			if (TrailingMode == TrailingDrawdownMode.RealTimeIntraday)
				UpdateTrailingPeak(currentEquity);

			// ------------------------------------------------------------------------------
			// 2) KILL-SWITCH TOTAL: trailing drawdown maximo de la prop firm
			// ------------------------------------------------------------------------------
			double trailingFloor = trailingLocked ? trailingLockLevel - MaxTrailingDrawdown : trailingPeakEquity - MaxTrailingDrawdown;

			if (!totalHalted && currentEquity <= trailingFloor)
			{
				totalHalted = true;
				Print(string.Format("[KILL-SWITCH TOTAL] Equity {0:C} <= piso de trailing drawdown {1:C}. Estrategia detenida.", currentEquity, trailingFloor));
			}

			if (totalHalted)
			{
				if (Position.MarketPosition != MarketPosition.Flat)
					FlattenAll("kill-switch-total");
				return; // no se opera mas en el resto de la corrida
			}

			// ------------------------------------------------------------------------------
			// 3) KILL-SWITCH DIARIO: perdida diaria maxima autoimpuesta
			// ------------------------------------------------------------------------------
			double dailyPnL = currentEquity - sessionStartEquity;
			double dailyLossLimit = StartingBalance * (DailyLossLimitPercent / 100.0);

			if (!dailyHalted && dailyPnL <= -dailyLossLimit)
			{
				dailyHalted = true;
				Print(string.Format("[KILL-SWITCH DIARIO] PnL del dia {0:C} <= limite -{1:C}. Sin nuevas operaciones el resto del dia.", dailyPnL, dailyLossLimit));
			}

			// ------------------------------------------------------------------------------
			// 4) Cierre forzado por horario (independiente de kill-switches)
			// ------------------------------------------------------------------------------
			if (Time[0].TimeOfDay >= FlattenTime && Position.MarketPosition != MarketPosition.Flat)
			{
				FlattenAll("cierre-horario");
			}

			// A partir de aqui, solo evaluamos NUEVAS entradas si no hay halts activos,
			// estamos dentro del horario permitido y no hay posicion abierta (max. 1 simultanea).
			bool withinEntryWindow = Time[0].TimeOfDay >= SessionStartTime && Time[0].TimeOfDay <= SessionEndTime;

			// ------------------------------------------------------------------------------
			// 5) Tracking de "alineacion" de las 3 medias para el filtro anti-entrada-tardia
			// ------------------------------------------------------------------------------
			bool bullAligned = Fast(0) > Medium(0) && Medium(0) > Slow(0);
			bool bearAligned = Fast(0) < Medium(0) && Medium(0) < Slow(0);

			// Contador de velas consecutivas de alineacion: 0 = se acaba de formar en esta vela,
			// 1 = se formo la vela anterior, etc. Se resetea a "infinito" en cuanto se rompe.
			barsSinceBullAlignment = bullAligned ? (barsSinceBullAlignment == int.MaxValue ? 0 : barsSinceBullAlignment + 1) : int.MaxValue;
			barsSinceBearAlignment = bearAligned ? (barsSinceBearAlignment == int.MaxValue ? 0 : barsSinceBearAlignment + 1) : int.MaxValue;

			if (!withinEntryWindow || dailyHalted || Position.MarketPosition != MarketPosition.Flat)
				return;

			// ------------------------------------------------------------------------------
			// 6) Filtros de calidad de senal
			// ------------------------------------------------------------------------------
			bool separationOk = Math.Abs(Medium(0) - Slow(0)) / TickSize >= MinMASeparationTicks;
			bool atrOk = !UseATRFilter || (atr[0] / TickSize) >= MinATRTicks;

			// Informativo: si el cruce exacto rapida/media ocurrio en esta vela (para logging).
			// El criterio de entrada real es "alineacion formada hace <= MaxCrossAgeBars velas",
			// que ya cubre tanto el cruce exacto como la confirmacion de la media lenta.
			bool crossedUpNow = CrossAbove(FastSeries, MediumSeries, 1);
			bool crossedDownNow = CrossBelow(FastSeries, MediumSeries, 1);

			bool longSignal = bullAligned && separationOk && atrOk && barsSinceBullAlignment <= MaxCrossAgeBars;
			bool shortSignal = bearAligned && separationOk && atrOk && barsSinceBearAlignment <= MaxCrossAgeBars;

			// ------------------------------------------------------------------------------
			// 7) Regla de consistencia (opcional): si el profit de HOY ya supera el X% del
			//    profit total acumulado, no abrimos mas operaciones hoy para no arriesgar
			//    violar la regla de consistencia de la prop firm al retirar fondos.
			// ------------------------------------------------------------------------------
			if (ConsistencyRuleEnabled && closedPnL > 0)
			{
				double todaysRealized = closedPnL - (sessionStartEquity - StartingBalance);
				if (todaysRealized > 0 && (todaysRealized / closedPnL) * 100.0 >= ConsistencyMaxDayPercent)
				{
					Print(string.Format("[CONSISTENCIA] Profit de hoy ya es el {0:F1}% del total. Se detienen nuevas entradas por hoy.",
						(todaysRealized / closedPnL) * 100.0));
					return;
				}
			}

			if (!longSignal && !shortSignal)
				return;

			// ------------------------------------------------------------------------------
			// 8) Gestion de riesgo: distancia de SL por ATR y calculo de contratos
			// ------------------------------------------------------------------------------
			double slDistance = atr[0] * ATRStopMultiplier;
			if (slDistance <= 0)
				return;

			double riskAmount = StartingBalance * (RiskPercentPerTrade / 100.0);
			double riskPerContract = (slDistance / TickSize) * tickValue;
			int contracts = riskPerContract > 0 ? (int)Math.Floor(riskAmount / riskPerContract) : 0;
			contracts = Math.Min(contracts, MaxContracts);

			if (contracts < 1)
			{
				// El SL (por ATR) implica arriesgar mas de lo permitido incluso con 1 solo
				// contrato: se descarta la operacion en vez de sobre-arriesgar la cuenta.
				Print("Senal valida descartada: riesgo con 1 contrato excede el % de riesgo configurado.");
				return;
			}

			double tpDistance = slDistance * RewardRiskRatio;

			if (longSignal)
			{
				double stopPrice = Close[0] - slDistance;
				double targetPrice = Close[0] + tpDistance;

				Print(string.Format("[ENTRADA LONG] {0} contrato(s) @ {1:F2} | SL {2:F2} | TP {3:F2} | cruce exacto esta vela: {4} | velas desde alineacion: {5}",
					contracts, Close[0], stopPrice, targetPrice, crossedUpNow, barsSinceBullAlignment));

				EnterLong(contracts, "TripleMA-Long");
				SetStopLoss("TripleMA-Long", CalculationMode.Price, stopPrice, false);
				SetProfitTarget("TripleMA-Long", CalculationMode.Price, targetPrice);
			}
			else if (shortSignal)
			{
				double stopPrice = Close[0] + slDistance;
				double targetPrice = Close[0] - tpDistance;

				Print(string.Format("[ENTRADA SHORT] {0} contrato(s) @ {1:F2} | SL {2:F2} | TP {3:F2} | cruce exacto esta vela: {4} | velas desde alineacion: {5}",
					contracts, Close[0], stopPrice, targetPrice, crossedDownNow, barsSinceBearAlignment));

				EnterShort(contracts, "TripleMA-Short");
				SetStopLoss("TripleMA-Short", CalculationMode.Price, stopPrice, false);
				SetProfitTarget("TripleMA-Short", CalculationMode.Price, targetPrice);
			}
		}

		private void UpdateTrailingPeak(double equity)
		{
			if (equity > trailingPeakEquity)
				trailingPeakEquity = equity;

			if (TrailingLockEnabled && !trailingLocked && trailingPeakEquity >= trailingLockLevel)
			{
				trailingLocked = true;
				Print(string.Format("[TRAILING LOCK] Trailing drawdown congelado en piso {0:C} (estilo Apex).", trailingLockLevel - MaxTrailingDrawdown));
			}
		}

		private double GetClosedTradesPnL()
		{
			// Suma el PnL realizado (en $, ya neto de comisiones si SystemPerformance las incluye)
			// de todas las operaciones cerradas por esta instancia de estrategia.
			if (SystemPerformance == null || SystemPerformance.AllTrades == null)
				return 0.0;

			return SystemPerformance.AllTrades.TradesPerformance.Currency.CumProfit;
		}

		private void FlattenAll(string reason)
		{
			if (Position.MarketPosition == MarketPosition.Long)
				ExitLong("flatten-" + reason, "TripleMA-Long");
			else if (Position.MarketPosition == MarketPosition.Short)
				ExitShort("flatten-" + reason, "TripleMA-Short");
		}
	}
}
