//+------------------------------------------------------------------+
//|                                  RSI_BB_MeanReversion_M15.mq5    |
//+------------------------------------------------------------------+
//|
//| ESTRATEGIA: Reversion a la media en indices (M15)
//| ---------------------------------------------------------------
//| Mercado:    Indices CFD (US30, NAS100, US500, GER40, etc.)
//| Timeframe:  M15 (operativo). El EA solo evalua senales al cierre
//|             de cada vela M15; el grafico donde se adjunte debe
//|             estar en ese timeframe.
//|
//| IDEA GENERAL
//|   Los indices pasan buena parte del tiempo oscilando dentro de un
//|   rango. Esta estrategia busca entradas contrarias cuando el
//|   precio se sobre-extiende fuera de las Bandas de Bollinger y el
//|   momentum (RSI + Estocastico) confirma agotamiento, siempre que
//|   el ADX indique que NO hay una tendencia fuerte en curso (filtro
//|   de rango). El objetivo es la vuelta hacia la media (banda
//|   central de Bollinger).
//|
//| INDICADORES
//|   - Bollinger Bands (periodo, desviacion configurables)
//|   - RSI (sobrecompra / sobreventa)
//|   - Estocastico (%K, %D) - cruce en zona extrema
//|   - ADX - filtro de mercado en rango (ADX bajo = sin tendencia)
//|   - ATR - dimensiona SL/TP y el tamano de posicion
//|
//| REGLAS DE ENTRADA (evaluadas en la vela M15 recien cerrada)
//|   COMPRA (long):
//|     1) La mecha minima de la vela toca o perfora la banda inferior
//|        de Bollinger (Low[1] <= BandaInferior[1])
//|     2) La vela cierra de nuevo dentro de las bandas
//|        (Close[1] >= BandaInferior[1])  -> vela de rechazo
//|     3) RSI[1] < RSI_Oversold (sobreventa)
//|     4) Cruce alcista del Estocastico (%K cruza por encima de %D)
//|        habiendo estado %K o %D en zona de sobreventa
//|     5) ADX[1] < ADX_MaxTrend (no hay tendencia fuerte -> mercado
//|        lateral, condicion necesaria para reversion a la media)
//|
//|   VENTA (short): condiciones simetricas con la banda superior,
//|     RSI en sobrecompra y cruce bajista del Estocastico.
//|
//|   Filtros adicionales para permitir una nueva entrada:
//|     - Sin posicion abierta de este EA en el simbolo (una a la vez)
//|     - Spread actual <= SpreadMaximo
//|     - Hora del servidor dentro de la sesion configurada
//|     - No se ha alcanzado la perdida maxima diaria permitida
//|
//| REGLAS DE SALIDA
//|   - Stop Loss:  Entrada -/+ (ATR * ATR_SL_Mult)
//|   - Take Profit: banda central de Bollinger en el momento de la
//|     entrada (objetivo de reversion a la media). Si esa distancia
//|     es menor que un minimo razonable, se usa como piso
//|     ATR * ATR_TP_Mult para evitar objetivos demasiado cortos.
//|   - Trailing stop opcional en multiplos de ATR una vez el precio
//|     se mueve a favor.
//|   - Cierre por tiempo: si la operacion sigue abierta tras
//|     MaxBarsInTrade velas M15, se cierra (evita quedar atrapado en
//|     una tendencia que invalido la premisa de "rango").
//|
//| GESTION DE RIESGO
//|   - Riesgo fijo por operacion como % del balance de la cuenta
//|     (RiskPercent). El lote se calcula a partir de la distancia de
//|     SL en dinero (usa tick value / tick size del simbolo, por lo
//|     que funciona igual de bien en indices con distinto valor de
//|     punto).
//|   - Circuit breaker de perdida diaria: si la equity cae por debajo
//|     de balance_inicio_del_dia * (1 - MaxDailyLossPct/100), el EA
//|     deja de abrir nuevas operaciones hasta el dia siguiente (las
//|     posiciones abiertas se siguen gestionando con su SL/TP).
//|   - Una sola posicion simultanea por simbolo/EA (magic number).
//|
//| ADVERTENCIA
//|   Esta plantilla es un punto de partida. Antes de operar en real
//|   valida en el Strategy Tester (modo "Every tick based on real
//|   ticks") con datos historicos del indice y el broker concretos,
//|   ajusta los parametros y confirma comisiones/swaps/spread reales.
//+------------------------------------------------------------------+
#property copyright "Estrategia de reversion a la media para indices"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//=================== INPUTS ===================//
input group "=== General ==="
input ulong  InpMagicNumber        = 20260913;   // Magic number
input string InpTradeComment       = "RSI_BB_MeanRev";
input int    InpMaxSpreadPoints    = 50;         // Spread maximo permitido (puntos)

input group "=== Filtro de sesion (hora del servidor) ==="
input bool   InpUseSessionFilter   = true;
input int    InpSessionStartHour   = 8;          // Hora de inicio (0-23)
input int    InpSessionEndHour     = 20;         // Hora de fin (0-23)

input group "=== Bandas de Bollinger ==="
input int    InpBBPeriod           = 20;
input double InpBBDeviation        = 2.0;

input group "=== RSI ==="
input int    InpRSIPeriod          = 14;
input double InpRSIOversold        = 30.0;
input double InpRSIOverbought      = 70.0;

input group "=== Estocastico ==="
input int    InpStochK             = 14;
input int    InpStochD             = 3;
input int    InpStochSlowing       = 3;
input double InpStochOversold      = 20.0;
input double InpStochOverbought    = 80.0;

input group "=== ADX (filtro de mercado en rango) ==="
input int    InpADXPeriod          = 14;
input double InpADXMaxTrend        = 25.0;       // Operar solo si ADX < este valor

input group "=== ATR (SL/TP dinamico) ==="
input int    InpATRPeriod          = 14;
input double InpATR_SL_Mult        = 1.5;
input double InpATR_TP_Mult        = 2.5;        // piso minimo de TP si la banda media queda muy cerca
input bool   InpUseMiddleBandTP    = true;

input group "=== Gestion de riesgo ==="
input double InpRiskPercent        = 1.0;        // % del balance arriesgado por operacion
input double InpMaxDailyLossPct    = 3.0;        // corte de perdida diaria (%)
input int    InpMaxBarsInTrade     = 24;         // cierre por tiempo (24 velas M15 = 6h)
input bool   InpUseTrailingStop    = true;
input double InpTrailingATRMult    = 1.0;

//=================== VARIABLES GLOBALES ===================//
int hBB, hRSI, hStoch, hADX, hATR;
datetime lastBarTime = 0;

double  dayStartBalance = 0.0;
int     dayStartDayOfYear = -1;
bool    dailyLossHit = false;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);

   hBB    = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, PERIOD_CURRENT, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   hADX   = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   hATR   = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE || hStoch == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Error creando handles de indicadores");
      return(INIT_FAILED);
   }

   ResetDailyTracking();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
   IndicatorRelease(hStoch);
   IndicatorRelease(hADX);
   IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| Detecta si comenzo una nueva vela                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reinicia el balance de referencia diario                          |
//+------------------------------------------------------------------+
void ResetDailyTracking()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dayStartDayOfYear = dt.day_of_year;
   dayStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyLossHit      = false;
}

//+------------------------------------------------------------------+
//| Comprueba el circuit breaker de perdida diaria                    |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != dayStartDayOfYear)
      ResetDailyTracking();

   if(!dailyLossHit && InpMaxDailyLossPct > 0.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double floorEquity = dayStartBalance * (1.0 - InpMaxDailyLossPct / 100.0);
      if(equity <= floorEquity)
      {
         dailyLossHit = true;
         Print("Corte de perdida diaria alcanzado. No se abriran nuevas operaciones hasta manana.");
      }
   }
}

//+------------------------------------------------------------------+
//| Cuenta posiciones abiertas de este EA en este simbolo             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calcula el volumen segun riesgo % y distancia de SL en precio     |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistancePrice <= 0.0)
      return 0.0;

   double moneyPerLot = (slDistancePrice / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return 0.0;

   double lots = riskMoney / moneyPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot > 0.0)
      lots = MathFloor(lots / stepLot) * stepLot;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Devuelve true si el spread actual es aceptable                    |
//+------------------------------------------------------------------+
bool SpreadOk()
{
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return spreadPoints <= InpMaxSpreadPoints;
}

//+------------------------------------------------------------------+
//| Filtro de sesion horaria (hora del servidor)                      |
//+------------------------------------------------------------------+
bool InSession()
{
   if(!InpUseSessionFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;

   if(InpSessionStartHour <= InpSessionEndHour)
      return (hour >= InpSessionStartHour && hour < InpSessionEndHour);
   else // sesion que cruza medianoche
      return (hour >= InpSessionStartHour || hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| Gestiona la posicion abierta: trailing stop y cierre por tiempo   |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double posOpen    = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL      = PositionGetDouble(POSITION_SL);
      double posTP      = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      //--- cierre por tiempo (numero de velas M15 desde la apertura)
      int period_seconds = PeriodSeconds(PERIOD_CURRENT);
      int barsElapsed = (int)((TimeCurrent() - openTime) / period_seconds);
      if(InpMaxBarsInTrade > 0 && barsElapsed >= InpMaxBarsInTrade)
      {
         trade.PositionClose(ticket);
         continue;
      }

      //--- trailing stop en multiplos de ATR
      if(InpUseTrailingStop)
      {
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(hATR, 0, 1, 1, atrBuf) <= 0) continue;
         double atr = atrBuf[0];

         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if(posType == POSITION_TYPE_BUY)
         {
            double newSL = bid - atr * InpTrailingATRMult;
            if(newSL > posOpen && (posSL == 0.0 || newSL > posSL))
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posTP);
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            double newSL = ask + atr * InpTrailingATRMult;
            if(newSL < posOpen && (posSL == 0.0 || newSL < posSL))
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), posTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Evalua senal de compra sobre la ultima vela cerrada (indice 1)    |
//+------------------------------------------------------------------+
bool CheckBuySignal(double &lowerBB1, double &middleBB1, double &atr1)
{
   double bbUpper[], bbMiddle[], bbLower[];
   double rsi[];
   double stochK[], stochD[];
   double adx[];
   double atr[];

   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hBB, 1, 1, 1, bbUpper) <= 0) return false;
   if(CopyBuffer(hBB, 0, 1, 1, bbMiddle) <= 0) return false;
   if(CopyBuffer(hBB, 2, 1, 1, bbLower) <= 0) return false;
   if(CopyBuffer(hRSI, 0, 1, 1, rsi) <= 0) return false;
   if(CopyBuffer(hStoch, 0, 1, 3, stochK) <= 0) return false;
   if(CopyBuffer(hStoch, 1, 1, 3, stochD) <= 0) return false;
   if(CopyBuffer(hADX, 0, 1, 1, adx) <= 0) return false;
   if(CopyBuffer(hATR, 0, 1, 1, atr) <= 0) return false;

   double low1  = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool touchedLower   = (low1 <= bbLower[0]);
   bool closedInside   = (close1 >= bbLower[0]);
   bool rsiOversold    = (rsi[0] < InpRSIOversold);
   bool adxRanging     = (adx[0] < InpADXMaxTrend);

   // stochK/stochD indices: [0]=vela 1 (mas reciente cerrada), [1]=vela 2, [2]=vela 3
   bool stochCrossUp   = (stochK[0] > stochD[0]) && (stochK[1] <= stochD[1]);
   bool wasOversold    = (MathMin(stochK[0], stochK[1]) < InpStochOversold);

   lowerBB1  = bbLower[0];
   middleBB1 = bbMiddle[0];
   atr1      = atr[0];

   return (touchedLower && closedInside && rsiOversold && adxRanging &&
           stochCrossUp && wasOversold);
}

//+------------------------------------------------------------------+
//| Evalua senal de venta sobre la ultima vela cerrada (indice 1)     |
//+------------------------------------------------------------------+
bool CheckSellSignal(double &upperBB1, double &middleBB1, double &atr1)
{
   double bbUpper[], bbMiddle[], bbLower[];
   double rsi[];
   double stochK[], stochD[];
   double adx[];
   double atr[];

   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hBB, 1, 1, 1, bbUpper) <= 0) return false;
   if(CopyBuffer(hBB, 0, 1, 1, bbMiddle) <= 0) return false;
   if(CopyBuffer(hBB, 2, 1, 1, bbLower) <= 0) return false;
   if(CopyBuffer(hRSI, 0, 1, 1, rsi) <= 0) return false;
   if(CopyBuffer(hStoch, 0, 1, 3, stochK) <= 0) return false;
   if(CopyBuffer(hStoch, 1, 1, 3, stochD) <= 0) return false;
   if(CopyBuffer(hADX, 0, 1, 1, adx) <= 0) return false;
   if(CopyBuffer(hATR, 0, 1, 1, atr) <= 0) return false;

   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool touchedUpper   = (high1 >= bbUpper[0]);
   bool closedInside   = (close1 <= bbUpper[0]);
   bool rsiOverbought  = (rsi[0] > InpRSIOverbought);
   bool adxRanging     = (adx[0] < InpADXMaxTrend);

   bool stochCrossDown = (stochK[0] < stochD[0]) && (stochK[1] >= stochD[1]);
   bool wasOverbought  = (MathMax(stochK[0], stochK[1]) > InpStochOverbought);

   upperBB1  = bbUpper[0];
   middleBB1 = bbMiddle[0];
   atr1      = atr[0];

   return (touchedUpper && closedInside && rsiOverbought && adxRanging &&
           stochCrossDown && wasOverbought);
}

//+------------------------------------------------------------------+
//| Abre una posicion de compra con SL/TP y lote calculados por riesgo|
//+------------------------------------------------------------------+
void OpenBuy(double middleBB1, double atr1)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double sl = ask - atr1 * InpATR_SL_Mult;
   double tpByATR = ask + atr1 * InpATR_TP_Mult;
   double tp = tpByATR;

   // Objetivo = banda media (reversion a la media), salvo que quede mas
   // cerca que el piso minimo ATR*TP_mult, en cuyo caso se usa ese piso.
   if(InpUseMiddleBandTP && middleBB1 > ask)
   {
      double distToMiddle = middleBB1 - ask;
      double floorDist     = atr1 * InpATR_TP_Mult;
      tp = (distToMiddle >= floorDist) ? middleBB1 : tpByATR;
   }

   double slDistance = ask - sl;
   double lots = CalculateLotSize(slDistance);
   if(lots <= 0.0)
   {
      Print("Lote calculado invalido, se omite la entrada de compra");
      return;
   }

   trade.Buy(lots, _Symbol, ask, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), InpTradeComment);
}

//+------------------------------------------------------------------+
//| Abre una posicion de venta con SL/TP y lote calculados por riesgo |
//+------------------------------------------------------------------+
void OpenSell(double middleBB1, double atr1)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = bid + atr1 * InpATR_SL_Mult;
   double tpByATR = bid - atr1 * InpATR_TP_Mult;
   double tp = tpByATR;

   // Objetivo = banda media (reversion a la media), salvo que quede mas
   // cerca que el piso minimo ATR*TP_mult, en cuyo caso se usa ese piso.
   if(InpUseMiddleBandTP && middleBB1 < bid)
   {
      double distToMiddle = bid - middleBB1;
      double floorDist     = atr1 * InpATR_TP_Mult;
      tp = (distToMiddle >= floorDist) ? middleBB1 : tpByATR;
   }

   double slDistance = sl - bid;
   double lots = CalculateLotSize(slDistance);
   if(lots <= 0.0)
   {
      Print("Lote calculado invalido, se omite la entrada de venta");
      return;
   }

   trade.Sell(lots, _Symbol, bid, NormalizeDouble(sl, _Digits), NormalizeDouble(tp, _Digits), InpTradeComment);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyReset();
   ManageOpenPosition();

   if(!IsNewBar())
      return;

   if(dailyLossHit)
      return;

   if(HasOpenPosition())
      return;

   if(!SpreadOk())
      return;

   if(!InSession())
      return;

   double lowerBB1, upperBB1, middleBB1, atr1;

   if(CheckBuySignal(lowerBB1, middleBB1, atr1))
   {
      OpenBuy(middleBB1, atr1);
      return;
   }

   if(CheckSellSignal(upperBB1, middleBB1, atr1))
   {
      OpenSell(middleBB1, atr1);
      return;
   }
}
//+------------------------------------------------------------------+
