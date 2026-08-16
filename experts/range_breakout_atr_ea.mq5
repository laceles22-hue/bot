//+------------------------------------------------------------------+
//|                                      range_breakout_atr_ea.mq5    |
//|   EA de ruptura de rango horario (Opening Range Breakout)         |
//|   - Rango marcado entre dos horas configurables (hora servidor)   |
//|   - Entrada por ruptura del máximo/mínimo, confirmada al CIERRE   |
//|     de la vela                                                    |
//|   - Stop Loss por ATR (multiplicador configurable)                |
//|   - Take Profit por relación Riesgo:Beneficio sobre ese stop      |
//|   - Lotaje calculado por % de riesgo sobre un balance de          |
//|     referencia configurable (útil para cuentas de fondeo)         |
//|   - Filtro de días de la semana, máximo 1 operación por día       |
//|   - Cierre forzado de la posición a una hora configurable         |
//|   Válido para cualquier símbolo (oro, índices, forex, etc.)       |
//+------------------------------------------------------------------+
#property copyright "HobbieCode-style EA"
#property version   "1.00"
#property description "Ruptura de rango horario con SL por ATR, TP por R:R, riesgo % sobre balance de referencia, filtro de días, 1 trade/día y cierre forzado."

#include <Trade\Trade.mqh>

//================================ INPUTS =================================
input group "=== Rango horario (hora de servidor) ==="
input int    InpRangeStartHour    = 8;      // Hora de inicio del rango
input int    InpRangeStartMin     = 0;      // Minuto de inicio del rango
input int    InpRangeEndHour      = 10;     // Hora de fin del rango
input int    InpRangeEndMin       = 0;      // Minuto de fin del rango

input group "=== Timeframe de trabajo ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // TF usado para el rango y la confirmación de cierre

input group "=== Stop Loss (ATR) y Take Profit (R:R) ==="
input int    InpATRPeriod         = 14;     // Periodo del ATR
input double InpATRMultiplier     = 1.5;    // Multiplicador de ATR para el Stop Loss
input double InpRewardRiskRatio   = 2.0;    // Relación Beneficio:Riesgo (TP = R:R x distancia del SL)

input group "=== Gestión de riesgo / tamaño de posición ==="
input double InpRiskPercent       = 0.5;    // % de riesgo por operación
input bool   InpUseFixedBalance   = true;   // Usar balance de referencia fijo (recomendado en fondeos)
input double InpFixedBalance      = 10000;  // Balance de referencia si InpUseFixedBalance = true

input group "=== Filtro de días de la semana ==="
input bool   InpTradeMonday       = true;
input bool   InpTradeTuesday      = true;
input bool   InpTradeWednesday    = true;
input bool   InpTradeThursday     = true;
input bool   InpTradeFriday       = true;
input bool   InpTradeSaturday     = false;
input bool   InpTradeSunday       = false;

input group "=== Cierre forzado (hora de servidor) ==="
input bool   InpForceCloseEnabled = true;   // Activar cierre forzado por hora
input int    InpForceCloseHour    = 21;     // Hora de cierre forzado
input int    InpForceCloseMin     = 55;     // Minuto de cierre forzado

input group "=== Ejecución ==="
input int    InpSlippage          = 20;     // Desviación máxima permitida (puntos)
input ulong  InpMagicNumber       = 990211; // Número mágico
input string InpTradeComment      = "ORB-ATR-EA"; // Comentario de las operaciones

//================================ GLOBALES ================================
CTrade   m_trade;
int      m_atrHandle = INVALID_HANDLE;

datetime m_currentDay  = 0;     // 00:00 del día de servidor actualmente gestionado
double   m_rangeHigh   = 0.0;
double   m_rangeLow    = 0.0;
bool     m_rangeReady  = false;
bool     m_tradedToday = false;
bool     m_closedToday = false;
datetime m_lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRangeStartHour < 0 || InpRangeStartHour > 23 || InpRangeEndHour < 0 || InpRangeEndHour > 23 ||
      InpRangeStartMin  < 0 || InpRangeStartMin  > 59 || InpRangeEndMin  < 0 || InpRangeEndMin  > 59)
   {
      Print("ERROR: horas/minutos de rango fuera de rango válido (0-23 / 0-59).");
      return(INIT_PARAMETERS_INCORRECT);
   }

   int startSec = InpRangeStartHour * 3600 + InpRangeStartMin * 60;
   int endSec   = InpRangeEndHour   * 3600 + InpRangeEndMin   * 60;
   if(startSec >= endSec)
   {
      Print("ERROR: la hora de inicio del rango debe ser anterior a la hora de fin (no se admite rango que cruce medianoche).");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpATRPeriod <= 0 || InpATRMultiplier <= 0.0 || InpRewardRiskRatio <= 0.0 || InpRiskPercent <= 0.0)
   {
      Print("ERROR: los parámetros de ATR, R:R y riesgo deben ser mayores que 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   m_atrHandle = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: no se pudo crear el indicador ATR.");
      return(INIT_FAILED);
   }

   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(InpSlippage);
   m_trade.SetTypeFillingBySymbol(_Symbol);

   m_currentDay  = 0; // fuerza el recálculo de todo el estado diario en el primer tick
   m_lastBarTime = 0;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyState();
   UpdateRange();
   CheckForceClose();

   if(!IsNewBar())
      return;

   CheckBreakoutEntry();
}

//+------------------------------------------------------------------+
//| Devuelve la medianoche (00:00) del día de servidor de un instante |
//+------------------------------------------------------------------+
datetime StartOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return(StructToTime(dt));
}

//+------------------------------------------------------------------+
//| Reinicia el estado (rango, trade del día, cierre) al cambiar día  |
//+------------------------------------------------------------------+
void UpdateDailyState()
{
   datetime today = StartOfDay(TimeTradeServer());
   if(today != m_currentDay)
   {
      m_currentDay  = today;
      m_rangeHigh   = 0.0;
      m_rangeLow    = 0.0;
      m_rangeReady  = false;
      m_tradedToday = false;
      m_closedToday = false;
   }
}

//+------------------------------------------------------------------+
//| Calcula el máximo/mínimo del rango en cuanto cierra su ventana    |
//+------------------------------------------------------------------+
void UpdateRange()
{
   if(m_rangeReady)
      return;

   datetime now        = TimeTradeServer();
   datetime rangeStart = m_currentDay + InpRangeStartHour * 3600 + InpRangeStartMin * 60;
   datetime rangeEnd   = m_currentDay + InpRangeEndHour   * 3600 + InpRangeEndMin   * 60;

   if(now < rangeEnd)
      return; // la ventana del rango todavía no ha cerrado

   int shiftStart = iBarShift(_Symbol, InpTimeframe, rangeStart, false);
   int shiftEnd   = iBarShift(_Symbol, InpTimeframe, rangeEnd - 1, false);

   if(shiftStart < 0 || shiftEnd < 0 || shiftStart < shiftEnd)
      return; // histórico insuficiente todavía; se reintenta en el próximo tick

   int count      = shiftStart - shiftEnd + 1;
   int idxHighest = iHighest(_Symbol, InpTimeframe, MODE_HIGH, count, shiftEnd);
   int idxLowest  = iLowest(_Symbol, InpTimeframe, MODE_LOW, count, shiftEnd);

   if(idxHighest < 0 || idxLowest < 0)
      return;

   m_rangeHigh  = iHigh(_Symbol, InpTimeframe, idxHighest);
   m_rangeLow   = iLow(_Symbol, InpTimeframe, idxLowest);
   m_rangeReady = true;

   PrintFormat("Rango del día calculado: High=%s Low=%s (ventana %02d:%02d-%02d:%02d)",
               DoubleToString(m_rangeHigh, _Digits), DoubleToString(m_rangeLow, _Digits),
               InpRangeStartHour, InpRangeStartMin, InpRangeEndHour, InpRangeEndMin);
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, InpTimeframe, 0);
   if(t != m_lastBarTime)
   {
      m_lastBarTime = t;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
bool IsTradingDayAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   switch(dt.day_of_week)
   {
      case 0: return(InpTradeSunday);
      case 1: return(InpTradeMonday);
      case 2: return(InpTradeTuesday);
      case 3: return(InpTradeWednesday);
      case 4: return(InpTradeThursday);
      case 5: return(InpTradeFriday);
      case 6: return(InpTradeSaturday);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Cuenta posiciones abiertas por este EA en este símbolo            |
//+------------------------------------------------------------------+
int PositionsWithMagicCount()
{
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         total++;
   }
   return(total);
}

//+------------------------------------------------------------------+
//| Comprueba la ruptura del rango confirmada por cierre de vela      |
//+------------------------------------------------------------------+
void CheckBreakoutEntry()
{
   if(!m_rangeReady || m_tradedToday || !IsTradingDayAllowed())
      return;

   datetime rangeEnd = m_currentDay + InpRangeEndHour * 3600 + InpRangeEndMin * 60;
   datetime bar1Time = iTime(_Symbol, InpTimeframe, 1);
   if(bar1Time < rangeEnd)
      return; // todavía no hay una vela cerrada por completo fuera de la ventana del rango

   if(InpForceCloseEnabled)
   {
      datetime closeTime = m_currentDay + InpForceCloseHour * 3600 + InpForceCloseMin * 60;
      if(TimeTradeServer() >= closeTime)
         return; // fuera del horario operativo del día
   }

   if(PositionsWithMagicCount() > 0)
      return;

   double closePrice = iClose(_Symbol, InpTimeframe, 1);

   if(closePrice > m_rangeHigh)
      OpenTrade(ORDER_TYPE_BUY);
   else if(closePrice < m_rangeLow)
      OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Calcula el volumen (lotes) según % de riesgo sobre el balance de  |
//| referencia y la distancia del Stop Loss en precio                 |
//+------------------------------------------------------------------+
double CalcLots(double slDistancePrice)
{
   double balance   = InpUseFixedBalance ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistancePrice <= 0.0)
      return(0.0);

   double moneyPerLot = (slDistancePrice / tickSize) * tickValue;
   if(moneyPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / moneyPerLot;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lotStep <= 0.0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   int stepDigits = 2;
   if(lotStep >= 1.0)
      stepDigits = 0;
   else if(lotStep >= 0.1)
      stepDigits = 1;

   return(NormalizeDouble(lots, stepDigits));
}

//+------------------------------------------------------------------+
//| Abre la operación de mercado con SL por ATR y TP por R:R          |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(m_atrHandle, 0, 1, 1, atrBuf) <= 0)
   {
      Print("ERROR: no se pudo leer el valor del ATR.");
      return;
   }
   double atrValue = atrBuf[0];
   if(atrValue <= 0.0)
      return;

   double slDist = atrValue * InpATRMultiplier;

   double point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits        = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopLevelPts  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist   = stopLevelPts * point;
   if(minStopDist > 0.0 && slDist < minStopDist)
      slDist = minStopDist;

   double price, sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = price - slDist;
      tp    = price + slDist * InpRewardRiskRatio;
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = price + slDist;
      tp    = price - slDist * InpRewardRiskRatio;
   }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lots = CalcLots(slDist);
   if(lots <= 0.0)
   {
      Print("ERROR: lote calculado inválido (revisa riesgo/balance/stop). No se abre la operación.");
      return;
   }

   bool sent;
   if(orderType == ORDER_TYPE_BUY)
      sent = m_trade.Buy(lots, _Symbol, price, sl, tp, InpTradeComment);
   else
      sent = m_trade.Sell(lots, _Symbol, price, sl, tp, InpTradeComment);

   if(sent)
   {
      m_tradedToday = true;
      PrintFormat("Operación abierta: %s lotes=%.2f precio=%s SL=%s TP=%s",
                  EnumToString(orderType), lots,
                  DoubleToString(price, digits), DoubleToString(sl, digits), DoubleToString(tp, digits));
   }
   else
   {
      Print("ERROR al enviar la orden: ", m_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Cierra cualquier posición abierta por este EA a la hora fijada    |
//+------------------------------------------------------------------+
void CheckForceClose()
{
   if(!InpForceCloseEnabled || m_closedToday)
      return;

   datetime closeTime = m_currentDay + InpForceCloseHour * 3600 + InpForceCloseMin * 60;
   if(TimeTradeServer() < closeTime)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         if(m_trade.PositionClose(ticket))
            PrintFormat("Cierre forzado ejecutado (ticket %s) a las %s", (string)ticket, TimeToString(TimeTradeServer(), TIME_MINUTES));
         else
            Print("ERROR en cierre forzado: ", m_trade.ResultRetcodeDescription());
      }
   }

   m_closedToday = true;
}
//+------------------------------------------------------------------+
