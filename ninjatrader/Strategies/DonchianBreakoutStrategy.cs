#region Using declarations
using System;
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
// Estrategia de ruptura (breakout) con órdenes stop pendientes
// ---------------------------------------------------------------------
// Reproduce el patrón de órdenes visto en capturas típicas de bots de
// breakout: una orden "SellStop" (o "BuyStop") pendiente por debajo/
// encima del rango reciente, con su "Profit target" ya calculado desde
// que se coloca la orden.
//
// Lógica:
//   1. Canal Donchian de N velas (máximo/mínimo de las últimas N velas,
//      sin incluir la vela en formación) define el "rango reciente".
//   2. Mientras está plano, coloca (y va actualizando) dos órdenes stop
//      de entrada: BuyStop justo por encima del máximo del canal y
//      SellStop justo por debajo del mínimo — igual que una orden stop
//      pendiente colocada manualmente en la plataforma.
//   3. En cuanto una se ejecuta (ruptura confirmada), se cancela la
//      contraria y se define stop loss (ATR) y profit target
//      (múltiplo R) para la posición.
//   4. Gestión de riesgo: contratos, máx. operaciones/día, pérdida
//      diaria máxima, ventana horaria de entrada, cierre al final de
//      sesión.
//
// Pensada para futuros micro E-mini (MES, MNQ) pero funciona con
// cualquier instrumento con tick size definido.
//
// AVISO: plantilla de trading automático. Antes de operar en real:
// compilar y revisar en el NinjaScript Editor, backtest en Strategy
// Analyzer y Sim101 en tiempo real durante un período razonable. No es
// asesoría financiera.
// =====================================================================

namespace NinjaTrader.NinjaScript.Strategies
{
	public class DonchianBreakoutStrategy : Strategy
	{
		#region Campos privados

		private ATR atr;
		private Highest donchianHigh;
		private Lowest donchianLow;

		private Order buyStopOrder = null;
		private Order sellStopOrder = null;

		private SessionIterator sessionIterator;
		private int tradesToday = 0;

		private const string BuySignal = "DonchianBuyStop";
		private const string SellSignal = "DonchianSellStop";

		private string channelTag = "DonchianChannel";

		#endregion

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description = "Breakout de canal Donchian con órdenes stop pendientes (BuyStop/SellStop) a ambos lados del rango reciente, stop ATR y target por múltiplo R. Pensada para futuros micro E-mini (MES/MNQ).";
				Name = "DonchianBreakoutStrategy";
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
				DonchianPeriod = 20;
				BufferTicks = 2;
				MinChannelAtrMult = 0.5;
				AtrPeriod = 14;

				EnableLongBreakouts = true;
				EnableShortBreakouts = true;

				StopLossAtrMult = 1.0;
				RewardRiskMultiple = 2.0;

				Contracts = 1;
				MaxTradesPerDay = 4;
				MaxDailyLossDollars = 300;
				EntryWindowStartHHMM = 930;
				EntryWindowEndHHMM = 1550;

				ShowChannel = true;
			}
			else if (State == State.DataLoaded)
			{
				atr = ATR(AtrPeriod);
				// Canal calculado sobre las N velas anteriores a la actual (barsAgo 1),
				// para no incluir la vela en formación/recién cerrada en su propio rango.
				donchianHigh = Highest(High, DonchianPeriod);
				donchianLow = Lowest(Low, DonchianPeriod);

				sessionIterator = new SessionIterator(Bars);
			}
		}

		protected override void OnBarUpdate()
		{
			if (CurrentBar < Math.Max(DonchianPeriod + 1, AtrPeriod + 1))
				return;

			ResetDailyCountersIfNewSession();

			bool withinWindow = IsWithinEntryWindow();
			bool canTrade = withinWindow && tradesToday < MaxTradesPerDay
				&& GetTodayRealizedPnL() > -Math.Abs(MaxDailyLossDollars);

			if (Position.MarketPosition == MarketPosition.Flat && canTrade)
				UpdateRestingStopOrders();
			else
				CancelRestingStopOrders();

			if (ShowChannel)
				DrawChannel();
		}

		protected override void OnOrderUpdate(Order order, double limitPrice, double stopPrice, int quantity,
			int filled, double averageFillPrice, OrderState orderState, DateTime time, ErrorCode error,
			string nativeError)
		{
			if (order.Name == BuySignal)
				buyStopOrder = (orderState == OrderState.Filled || orderState == OrderState.Cancelled
					|| orderState == OrderState.Rejected) ? null : order;
			else if (order.Name == SellSignal)
				sellStopOrder = (orderState == OrderState.Filled || orderState == OrderState.Cancelled
					|| orderState == OrderState.Rejected) ? null : order;
		}

		protected override void OnExecutionUpdate(Execution execution, string executionId, double price,
			int quantity, MarketPosition marketPosition, string orderId, DateTime time)
		{
			if (execution.Order == null || execution.Order.OrderState != OrderState.Filled)
				return;

			if (execution.Order.Name == BuySignal)
			{
				tradesToday++;
				CancelOrderIfWorking(sellStopOrder);
				SetProtectiveOrders(true, price);
			}
			else if (execution.Order.Name == SellSignal)
			{
				tradesToday++;
				CancelOrderIfWorking(buyStopOrder);
				SetProtectiveOrders(false, price);
			}
		}

		#region Canal Donchian y órdenes de entrada

		private void UpdateRestingStopOrders()
		{
			double atrVal = atr[0];
			double channelTop = donchianHigh[1];
			double channelBottom = donchianLow[1];
			double channelWidth = channelTop - channelBottom;

			bool channelSizeOk = MinChannelAtrMult <= 0 || channelWidth >= atrVal * MinChannelAtrMult;
			if (!channelSizeOk)
			{
				CancelRestingStopOrders();
				return;
			}

			if (EnableLongBreakouts)
			{
				double buyStopPrice = RoundTick(channelTop + BufferTicks * TickSize);
				EnterLongStopMarket(0, true, Contracts, buyStopPrice, BuySignal);
			}
			else
			{
				CancelOrderIfWorking(buyStopOrder);
			}

			if (EnableShortBreakouts)
			{
				double sellStopPrice = RoundTick(channelBottom - BufferTicks * TickSize);
				EnterShortStopMarket(0, true, Contracts, sellStopPrice, SellSignal);
			}
			else
			{
				CancelOrderIfWorking(sellStopOrder);
			}
		}

		private void CancelRestingStopOrders()
		{
			CancelOrderIfWorking(buyStopOrder);
			CancelOrderIfWorking(sellStopOrder);
		}

		private void CancelOrderIfWorking(Order order)
		{
			if (order != null && order.OrderState == OrderState.Working)
				CancelOrder(order);
		}

		private void SetProtectiveOrders(bool isLong, double fillPrice)
		{
			double atrVal = atr[0];
			double stopDistance = Math.Max(atrVal * StopLossAtrMult, TickSize);
			string signal = isLong ? BuySignal : SellSignal;

			double stopPrice = isLong
				? RoundTick(fillPrice - stopDistance)
				: RoundTick(fillPrice + stopDistance);
			double targetPrice = isLong
				? RoundTick(fillPrice + stopDistance * RewardRiskMultiple)
				: RoundTick(fillPrice - stopDistance * RewardRiskMultiple);

			SetStopLoss(signal, CalculationMode.Price, stopPrice, false);
			SetProfitTarget(signal, CalculationMode.Price, targetPrice);
		}

		private void DrawChannel()
		{
			Draw.Rectangle(this, channelTag, false, DonchianPeriod, donchianHigh[1], 0, donchianLow[1],
				Brushes.Goldenrod, Brushes.Goldenrod, 5);
		}

		#endregion

		#region Ventana horaria / riesgo diario

		private bool IsWithinEntryWindow()
		{
			int nowHHMM = Time[0].Hour * 100 + Time[0].Minute;
			return nowHHMM >= EntryWindowStartHHMM && nowHHMM <= EntryWindowEndHHMM;
		}

		private void ResetDailyCountersIfNewSession()
		{
			if (sessionIterator.IsNewSession(Time[0], false))
			{
				sessionIterator.CalculateTradingDay(Time[0], false);
				tradesToday = 0;
			}
		}

		// Suma el PnL realizado (moneda de cuenta) de operaciones cerradas hoy.
		// Nota: agrupa por fecha de calendario del cierre; en sesiones de
		// futuros que cruzan medianoche puede diferir levemente del día de
		// sesión de trading.
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

		#region Utilidades de precio

		private double RoundTick(double price)
		{
			return Instrument.MasterInstrument.RoundToTickSize(price);
		}

		private double TickSize
		{
			get { return Instrument.MasterInstrument.TickSize; }
		}

		#endregion

		#region Parámetros

		[NinjaScriptProperty]
		[Range(2, int.MaxValue)]
		[Display(Name = "Periodo del canal Donchian (velas)", GroupName = "1. Ruptura", Order = 1)]
		public int DonchianPeriod { get; set; }

		[NinjaScriptProperty]
		[Range(0, int.MaxValue)]
		[Display(Name = "Buffer de disparo (ticks más allá del canal)", GroupName = "1. Ruptura", Order = 2)]
		public int BufferTicks { get; set; }

		[NinjaScriptProperty]
		[Range(0.0, double.MaxValue)]
		[Display(Name = "Ancho mínimo del canal (x ATR)", GroupName = "1. Ruptura", Order = 3)]
		public double MinChannelAtrMult { get; set; }

		[NinjaScriptProperty]
		[Range(1, int.MaxValue)]
		[Display(Name = "Periodo ATR", GroupName = "1. Ruptura", Order = 4)]
		public int AtrPeriod { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Habilitar rupturas al alza (BuyStop)", GroupName = "2. Dirección", Order = 1)]
		public bool EnableLongBreakouts { get; set; }

		[NinjaScriptProperty]
		[Display(Name = "Habilitar rupturas a la baja (SellStop)", GroupName = "2. Dirección", Order = 2)]
		public bool EnableShortBreakouts { get; set; }

		[NinjaScriptProperty]
		[Range(0.1, double.MaxValue)]
		[Display(Name = "Stop loss (x ATR desde la entrada)", GroupName = "3. Salida", Order = 1)]
		public double StopLossAtrMult { get; set; }

		[NinjaScriptProperty]
		[Range(0.1, double.MaxValue)]
		[Display(Name = "Múltiplo Riesgo:Beneficio (R)", GroupName = "3. Salida", Order = 2)]
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
		[Display(Name = "Dibujar canal Donchian", GroupName = "5. Visualización", Order = 1)]
		public bool ShowChannel { get; set; }

		#endregion
	}
}
