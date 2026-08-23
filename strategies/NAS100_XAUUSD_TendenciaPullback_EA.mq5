//+------------------------------------------------------------------+
//|                        NAS100_XAUUSD_TendenciaPullback_EA.mq5    |
//+------------------------------------------------------------------+
//| Estrategia: NAS100 / XAUUSD - Tendencia + Pullback (Riesgo Bajo) |
//| ------------------------------------------------------------------
//| Mercado:        Nasdaq 100 (NAS100/US100) y XAUUSD. Adjuntar el
//|                 EA por separado en el gráfico de cada instrumento.
//| Temporalidad:   15 minutos a 1 hora.
//| Riesgo:         Bajo (0.5% del capital por operación por defecto).
//| Indicadores:    EMA 50/200, RSI(14), MACD(12,26,9),
//|                 Bandas de Bollinger (20,2), ATR(14) para el stop.
//|
//| LÓGICA (idéntica a la versión Pine Script de TradingView):
//|   Tendencia: EMA50 vs EMA200 define el sesgo direccional.
//|   Entrada:   Pullback hacia la banda media/inferior (o superior)
//|              de Bollinger + RSI saliendo de zona extrema a favor
//|              de la tendencia + MACD confirmando el giro de
//|              momentum + vela de confirmación.
//|   Salida:    Stop Loss / Take Profit por ATR y relación R:R,
//|              con salida anticipada si el RSI llega al extremo
//|              opuesto o el precio rompe la EMA rápida en contra.
//|   Gestión:   Lote calculado para arriesgar un % fijo del capital
//|              por operación; corte de nuevas entradas al alcanzar
//|              la pérdida máxima diaria configurada.
//|
//| Nota: todas las condiciones se evalúan sobre la última vela
//| CERRADA (shift 1), no sobre la vela en formación, para evitar
//| señales que cambien antes del cierre de la vela.
//+------------------------------------------------------------------+
#property copyright "Estrategia personalizada"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

// ============================= INPUTS: GESTIÓN DE RIESGO =============================
input group "Gestión de Riesgo"
input double InpRiskPercent         = 0.5;   // Riesgo por operación (% del capital)
input double InpMaxDailyLossPercent = 2.0;   // Pérdida máxima diaria (% del capital)
input double InpRRRatio             = 2.0;   // Relación Riesgo/Recompensa (R:R)
input int    InpATRPeriod           = 14;    // Periodo ATR (para el Stop Loss)
input double InpATRMultSL           = 1.5;   // Multiplicador ATR para el Stop Loss
input double InpFixedLotFallback    = 0.01;  // Lote de respaldo si no se puede calcular por riesgo

// ============================= INPUTS: TENDENCIA =============================
input group "Tendencia (Medias Móviles)"
input int InpEmaFastPeriod = 50;   // EMA rápida
input int InpEmaSlowPeriod = 200;  // EMA lenta

// ============================= INPUTS: RSI =============================
input group "RSI"
input int InpRSIPeriod       = 14; // Periodo RSI
input int InpRSIOversold     = 30; // Nivel de sobreventa
input int InpRSIOverbought   = 70; // Nivel de sobrecompra
input int InpRSILongTrigger  = 40; // Disparo de entrada en largos (cruce al alza)
input int InpRSIShortTrigger = 60; // Disparo de entrada en cortos (cruce a la baja)

// ============================= INPUTS: MACD =============================
input group "MACD"
input int InpMACDFast   = 12; // EMA rápida MACD
input int InpMACDSlow   = 26; // EMA lenta MACD
input int InpMACDSignal = 9;  // Señal MACD

// ============================= INPUTS: BANDAS DE BOLLINGER =============================
input group "Bandas de Bollinger"
input int    InpBBPeriod     = 20;  // Periodo
input double InpBBDeviation  = 2.0; // Desviaciones estándar

// ============================= INPUTS: FILTROS Y OPERATIVA =============================
input group "Filtros y Operativa"
input bool   InpAllowLong          = true;    // Permitir posiciones largas
input bool   InpAllowShort         = true;    // Permitir posiciones cortas
input bool   InpUseSessionFilter   = false;   // Restringir a una franja horaria (hora del servidor)
input int    InpSessionStartHour   = 0;       // Hora de inicio (0-23)
input int    InpSessionEndHour     = 23;      // Hora de fin (0-23)
input bool   InpFlattenOnDayEnd    = false;   // Cerrar posiciones abiertas al cambio de día
input bool   InpSendAlerts         = true;    // Enviar Alert()/notificación en cada señal
input ulong  InpMagicNumber        = 20260823;// Número mágico del EA

// ============================= VARIABLES GLOBALES =============================
int hEmaFast, hEmaSlow, hRSI, hMACD, hBB, hATR;
datetime lastBarTime   = 0;
double   dayStartEquity = 0.0;
int      lastDay        = -1;

//+------------------------------------------------------------------+
int OnInit()
  {
   hEmaFast = iMA(_Symbol, _Period, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, _Period, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   hMACD    = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   hBB      = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hATR     = iATR(_Symbol, _Period, InpATRPeriod);

   if(hEmaFast==INVALID_HANDLE || hEmaSlow==INVALID_HANDLE || hRSI==INVALID_HANDLE ||
      hMACD==INVALID_HANDLE || hBB==INVALID_HANDLE || hATR==INVALID_HANDLE)
     {
      Print("Error creando handles de indicadores");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   lastDay        = dt.day;
   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   IndicatorRelease(hBB);
   IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   if(!PositionSelect(_Symbol))
      return(false);
   return(PositionGetInteger(POSITION_MAGIC)==(long)InpMagicNumber);
  }

//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC)==(long)InpMagicNumber)
      trade.PositionClose(_Symbol);
  }

//+------------------------------------------------------------------+
double CalcLotByRisk(double slDistance)
  {
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent/100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double lots = InpFixedLotFallback;
   if(tickSize > 0.0 && tickValue > 0.0 && slDistance > 0.0)
     {
      double moneyPerLotAtSL = (slDistance/tickSize) * tickValue;
      if(moneyPerLotAtSL > 0.0)
         lots = riskMoney / moneyPerLotAtSL;
     }

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lotStep > 0.0)
      lots = MathFloor(lots/lotStep) * lotStep;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return(lots);
  }

//+------------------------------------------------------------------+
bool InAllowedSession(const MqlDateTime &dt)
  {
   if(!InpUseSessionFilter)
      return(true);

   int hour = dt.hour;
   if(InpSessionStartHour <= InpSessionEndHour)
      return(hour >= InpSessionStartHour && hour <= InpSessionEndHour);

   // Ventana que cruza la medianoche (ej. 22 -> 5)
   return(hour >= InpSessionStartHour || hour <= InpSessionEndHour);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
// Evaluar solo al cierre de cada vela nueva (no en cada tick intrabar)
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == lastBarTime)
      return;
   lastBarTime = t0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

// Reinicio / cierre por cambio de día
   if(dt.day != lastDay)
     {
      if(InpFlattenOnDayEnd)
         CloseAllPositions();
      lastDay        = dt.day;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
     }

   double dailyPnLPct = 0.0;
   if(dayStartEquity > 0.0)
      dailyPnLPct = (AccountInfoDouble(ACCOUNT_EQUITY) - dayStartEquity) / dayStartEquity * 100.0;
   bool dailyLossHit = dailyPnLPct <= -InpMaxDailyLossPercent;

// ---- Copiar buffers de indicadores (shift 1 = última vela cerrada) ----
   double emaFast[], emaSlow[], rsi[], macdMain[], macdSignal[], bbBase[], bbUpper[], bbLower[], atrBuf[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(bbBase, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(atrBuf, true);

   if(CopyBuffer(hEmaFast, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(hEmaSlow, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return;
   if(CopyBuffer(hMACD, 0, 0, 3, macdMain) < 3) return;
   if(CopyBuffer(hMACD, 1, 0, 3, macdSignal) < 3) return;
   if(CopyBuffer(hBB, 0, 0, 3, bbBase) < 3) return;
   if(CopyBuffer(hBB, 1, 0, 3, bbUpper) < 3) return;
   if(CopyBuffer(hBB, 2, 0, 3, bbLower) < 3) return;
   if(CopyBuffer(hATR, 0, 0, 3, atrBuf) < 3) return;

   double emaFastCur = emaFast[1], emaFastPrev2 = emaFast[2];
   double emaSlowCur = emaSlow[1];
   double rsiCur = rsi[1], rsiPrev = rsi[2];
   double macdMainCur = macdMain[1], macdMainPrev = macdMain[2];
   double macdSignalCur = macdSignal[1], macdSignalPrev = macdSignal[2];
   double histCur = macdMainCur - macdSignalCur;
   double histPrev = macdMainPrev - macdSignalPrev;
   double bbBaseCur = bbBase[1], bbUpperCur = bbUpper[1], bbLowerCur = bbLower[1];
   double atrCur = atrBuf[1];

   double o1 = iOpen(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);
   double c2 = iClose(_Symbol, _Period, 2);

// ---- Tendencia ----
   bool uptrend   = emaFastCur > emaSlowCur;
   bool downtrend = emaFastCur < emaSlowCur;

// ---- Pullback (retroceso hacia la media/banda de Bollinger) ----
   bool pullbackLong  = (l1 <= bbBaseCur) || (l1 <= bbLowerCur);
   bool pullbackShort = (h1 >= bbBaseCur) || (h1 >= bbUpperCur);

// ---- RSI saliendo de zona extrema a favor de la tendencia ----
   bool rsiTriggerLong  = (rsiPrev <= InpRSILongTrigger  && rsiCur > InpRSILongTrigger)  && rsiCur < InpRSIOverbought;
   bool rsiTriggerShort = (rsiPrev >= InpRSIShortTrigger && rsiCur < InpRSIShortTrigger) && rsiCur > InpRSIOversold;

// ---- MACD confirmando el giro de momentum ----
   bool macdCrossUp    = (macdMainPrev <= macdSignalPrev && macdMainCur > macdSignalCur);
   bool macdCrossDown  = (macdMainPrev >= macdSignalPrev && macdMainCur < macdSignalCur);
   bool histFlipUp     = (histPrev <= 0.0 && histCur > 0.0);
   bool histFlipDown   = (histPrev >= 0.0 && histCur < 0.0);
   bool macdTriggerLong  = macdCrossUp   || histFlipUp;
   bool macdTriggerShort = macdCrossDown || histFlipDown;

// ---- Vela de confirmación ----
   bool candleConfirmLong  = c1 > o1;
   bool candleConfirmShort = c1 < o1;

// ---- Filtro de sesión ----
   bool inSession = InAllowedSession(dt);

   bool hasPosition = HasOpenPosition();

   bool longCondition = InpAllowLong && uptrend && pullbackLong && rsiTriggerLong && macdTriggerLong &&
                         candleConfirmLong && inSession && !dailyLossHit && !hasPosition;

   bool shortCondition = InpAllowShort && downtrend && pullbackShort && rsiTriggerShort && macdTriggerShort &&
                          candleConfirmShort && inSession && !dailyLossHit && !hasPosition;

// ---- Stop Loss / Take Profit por ATR y relación R:R ----
   double slDistance = MathMax(atrCur * InpATRMultSL, _Point * 10);
   double tpDistance = slDistance * InpRRRatio;
   double lots       = CalcLotByRisk(slDistance);

   if(longCondition)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - slDistance;
      double tp  = ask + tpDistance;
      if(trade.Buy(lots, _Symbol, ask, sl, tp, "NAS100/XAUUSD Tendencia+Pullback"))
        {
         if(InpSendAlerts)
            Alert(_Symbol, ": ENTRADA LARGA - tendencia alcista + pullback + RSI + MACD confirmados");
        }
     }
   else if(shortCondition)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + slDistance;
      double tp  = bid - tpDistance;
      if(trade.Sell(lots, _Symbol, bid, sl, tp, "NAS100/XAUUSD Tendencia+Pullback"))
        {
         if(InpSendAlerts)
            Alert(_Symbol, ": ENTRADA CORTA - tendencia bajista + rebote + RSI + MACD confirmados");
        }
     }

// ---- Salida anticipada por señal (además del SL/TP ya fijados en la orden) ----
   if(hasPosition)
     {
      long posType = PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
        {
         bool exitLongSignal = (rsiPrev <= InpRSIOverbought && rsiCur > InpRSIOverbought) ||
                                (c1 < emaFastCur && c2 >= emaFastPrev2);
         if(exitLongSignal)
           {
            trade.PositionClose(_Symbol);
            if(InpSendAlerts)
               Alert(_Symbol, ": Salida anticipada de LARGO - RSI en sobrecompra o ruptura de EMA rápida");
           }
        }
      else if(posType == POSITION_TYPE_SELL)
        {
         bool exitShortSignal = (rsiPrev >= InpRSIOversold && rsiCur < InpRSIOversold) ||
                                 (c1 > emaFastCur && c2 <= emaFastPrev2);
         if(exitShortSignal)
           {
            trade.PositionClose(_Symbol);
            if(InpSendAlerts)
               Alert(_Symbol, ": Salida anticipada de CORTO - RSI en sobreventa o ruptura de EMA rápida");
           }
        }
     }

// ---- Panel de estado en pantalla ----
   string estado = dailyLossHit ? "DETENIDO (pérdida máx. diaria)" : "ACTIVO";
   Comment(StringFormat(
      "%s | Riesgo/operación: %.2f%% | R:R objetivo: 1:%.1f\nP/L diario: %.2f%% (máx. permitido: -%.2f%%) | Estado: %s",
      _Symbol, InpRiskPercent, InpRRRatio, dailyPnLPct, InpMaxDailyLossPercent, estado));
  }
//+------------------------------------------------------------------+
