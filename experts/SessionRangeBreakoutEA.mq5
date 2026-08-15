//+------------------------------------------------------------------+
//|                                     SessionRangeBreakoutEA.mq5    |
//|         EA de ruptura de rango horario, multi-símbolo (MQL5)     |
//+------------------------------------------------------------------+
#property copyright "SessionRangeBreakoutEA"
#property version   "1.00"
#property description "Ruptura de rango horario (hora de servidor). Confirmación por cierre"
#property description "de vela, SL por ATR, TP por R:R, lotaje por % de riesgo sobre balance"
#property description "de referencia, filtro de días, 1 operación/día y cierre forzado."
#property description ""
#property description "Valores por defecto pensados para oro (XAUUSD) y USTEC (Nasdaq/US Tech),"
#property description "en cuentas de fondeo. Revisa el rango horario según el huso horario del"
#property description "servidor de tu bróker y ajusta el filtro de spread al símbolo usado."

#include <Trade\Trade.mqh>

//--- Rango de ruptura (hora de servidor)
input group "===== Rango de ruptura (hora de servidor) ====="
input int              InpRangeStartHour   = 0;            // Hora inicio del rango
input int              InpRangeStartMinute = 0;             // Minuto inicio del rango
input int              InpRangeEndHour     = 8;             // Hora fin del rango
input int              InpRangeEndMinute   = 0;             // Minuto fin del rango
input ENUM_TIMEFRAMES  InpRangeTF          = PERIOD_M5;     // Timeframe para calcular máx/mín del rango

//--- Confirmación de ruptura
input group "===== Confirmación de ruptura ====="
input ENUM_TIMEFRAMES  InpConfirmTF            = PERIOD_M15; // Timeframe de confirmación (cierre de vela)
input int               InpBreakoutBufferPoints = 0;         // Buffer extra en puntos contra falsas rupturas

//--- Gestión de riesgo
input group "===== Gestión de riesgo ====="
input int      InpATRPeriod             = 14;      // Periodo ATR (mismo timeframe que confirmación)
input double   InpATRMultiplierSL       = 1.5;      // Multiplicador ATR para el Stop Loss
input double   InpRiskReward            = 2.0;      // Ratio Riesgo:Beneficio (TP = distancia SL * RR)
input double   InpRiskPercent           = 0.5;      // % de riesgo por operación
input bool     InpUseFixedBalance       = true;     // Usar balance de referencia fijo (recomendado en fondeos)
input double   InpFixedBalance          = 10000.0;  // Balance de referencia (si InpUseFixedBalance=true)
input bool     InpAllowMinLotIfTooSmall = false;    // Usar lote mínimo si el riesgo calculado da un lote menor al mínimo

//--- Filtros
input group "===== Filtros ====="
input bool   InpTradeMonday    = true;
input bool   InpTradeTuesday   = true;
input bool   InpTradeWednesday = true;
input bool   InpTradeThursday  = true;
input bool   InpTradeFriday    = true;
input bool   InpTradeSaturday  = false;
input bool   InpTradeSunday    = false;
input int    InpMaxSpreadPoints = 0;    // Spread máximo permitido en puntos (0 = filtro desactivado)

//--- Cierre forzado
input group "===== Cierre forzado ====="
input bool   InpForceCloseEnabled = true;  // Activar cierre forzado por hora
input int    InpForceCloseHour    = 21;    // Hora de cierre forzado (servidor)
input int    InpForceCloseMinute  = 0;     // Minuto de cierre forzado

//--- Trading
input group "===== Trading ====="
input ulong    InpMagic     = 990101;              // Número mágico
input int      InpSlippage  = 30;                   // Slippage / desviación máxima (puntos)
input string   InpComment   = "SessionRangeBreakoutEA";    // Comentario de las órdenes

//--- Diagnóstico
input group "===== Diagnóstico ====="
input bool     InpDebugLog  = true;   // Volcar mensajes de diagnóstico al log (recomendado en backtest)

//--- Globales
CTrade   trade;
int      g_atrHandle          = INVALID_HANDLE;
datetime g_currentDay          = 0;
double   g_rangeHigh           = 0.0;
double   g_rangeLow            = 0.0;
bool     g_rangeReady          = false;
bool     g_tradeTakenToday     = false;
bool     g_forceCloseDoneToday = false;
bool     g_rangeFailLogged     = false; // evita spamear el log si el rango no consigue datos
datetime g_lastEvalBarLogged   = 0;     // última vela de confirmación ya logueada (solo diagnóstico)

//+------------------------------------------------------------------+
//| Devuelve la medianoche (hora de servidor) del día que contiene t |
//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0;
   s.min  = 0;
   s.sec  = 0;
   return StructToTime(s);
}

//+------------------------------------------------------------------+
//| Devuelve el datetime de un día concreto a la hora hh:mm          |
//+------------------------------------------------------------------+
datetime TimeOfDay(const datetime dayStart, const int hour, const int minute)
{
   return dayStart + hour * 3600 + minute * 60;
}

//+------------------------------------------------------------------+
//| Comprueba si el día de la semana de t está habilitado            |
//+------------------------------------------------------------------+
bool IsTradingDayAllowed(const datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   switch(s.day_of_week)
   {
      case 0: return InpTradeSunday;
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
      case 6: return InpTradeSaturday;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Devuelve true si hay una posición abierta de esta EA en _Symbol  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cierra cualquier posición abierta por esta EA en _Symbol         |
//+------------------------------------------------------------------+
void ForceCloseOwnPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(ticket, (ulong)InpSlippage);
   }
}

//+------------------------------------------------------------------+
//| Reinicia el estado diario                                        |
//+------------------------------------------------------------------+
void ResetDailyState(const datetime dayStart)
{
   g_currentDay          = dayStart;
   g_rangeHigh           = 0.0;
   g_rangeLow            = 0.0;
   g_rangeReady          = false;
   g_tradeTakenToday      = false;
   g_forceCloseDoneToday = false;
   g_rangeFailLogged     = false;
   g_lastEvalBarLogged   = 0;
}

//+------------------------------------------------------------------+
//| Reconstruye el estado del día tras un reinicio de la EA/terminal |
//| (posición abierta u operación ya cerrada hoy con nuestro magic)  |
//+------------------------------------------------------------------+
void SyncStateForToday(const datetime dayStart)
{
   if(HasOpenPosition())
   {
      g_tradeTakenToday = true;
      return;
   }

   if(HistorySelect(dayStart, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            g_tradeTakenToday = true;
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calcula el máximo y el mínimo del rango horario configurado      |
//+------------------------------------------------------------------+
bool ComputeRange(const datetime dayStart)
{
   datetime rangeStart = TimeOfDay(dayStart, InpRangeStartHour, InpRangeStartMinute);
   datetime rangeEnd   = TimeOfDay(dayStart, InpRangeEndHour, InpRangeEndMinute);

   double highs[];
   double lows[];
   int n1 = CopyHigh(_Symbol, InpRangeTF, rangeStart, rangeEnd, highs);
   int n2 = CopyLow(_Symbol, InpRangeTF, rangeStart, rangeEnd, lows);
   if(n1 <= 0 || n2 <= 0)
   {
      if(InpDebugLog && !g_rangeFailLogged)
      {
         PrintFormat("SessionRangeBreakoutEA: sin datos de %s entre %s y %s (CopyHigh=%d CopyLow=%d, error=%d). "
                     "Revisa la profundidad de historial del símbolo/timeframe en el Probador de Estrategias.",
                     EnumToString(InpRangeTF), TimeToString(rangeStart, TIME_DATE|TIME_MINUTES),
                     TimeToString(rangeEnd, TIME_DATE|TIME_MINUTES), n1, n2, GetLastError());
         g_rangeFailLogged = true;
      }
      return false;
   }

   double hi = highs[0];
   double lo = lows[0];
   for(int i = 1; i < n1; i++) if(highs[i] > hi) hi = highs[i];
   for(int i = 1; i < n2; i++) if(lows[i]  < lo) lo = lows[i];

   if(hi <= lo)
      return false;

   g_rangeHigh = hi;
   g_rangeLow  = lo;

   if(InpDebugLog)
      PrintFormat("SessionRangeBreakoutEA: rango del %s listo -> High=%.5f Low=%.5f (%d/%d barras %s)",
                  TimeToString(dayStart, TIME_DATE), hi, lo, n1, n2, EnumToString(InpRangeTF));

   return true;
}

//+------------------------------------------------------------------+
//| Modo de ejecución soportado por el símbolo (FOK / IOC / RETURN)  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Calcula el lote según % de riesgo sobre el balance de referencia |
//+------------------------------------------------------------------+
double CalculateLotSize(const double slDistance, string &reason)
{
   reason = "";
   double refBalance = InpUseFixedBalance ? InpFixedBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney   = refBalance * InpRiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0)
   {
      reason = StringFormat("SYMBOL_TRADE_TICK_VALUE=%.5f / SYMBOL_TRADE_TICK_SIZE=%.5f inválidos para %s "
                             "(el símbolo puede no tener datos de contrato cargados)", tickValue, tickSize, _Symbol);
      return 0.0;
   }

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0)
   {
      reason = StringFormat("pérdida por lote calculada = %.5f (slDistance=%.5f)", lossPerLot, slDistance);
      return 0.0;
   }

   double lots = riskMoney / lossPerLot;

   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(volStep <= 0) volStep = 0.01;

   double normalized = MathFloor(lots / volStep) * volStep;
   normalized = NormalizeDouble(normalized, 2);

   if(normalized < volMin)
   {
      if(InpAllowMinLotIfTooSmall)
      {
         normalized = volMin;
      }
      else
      {
         reason = StringFormat("lote calculado %.4f < volumen mínimo %.4f del símbolo "
                                "(riesgo=%.2f %s, pérdida/lote=%.2f). Sube InpRiskPercent, "
                                "baja InpATRMultiplierSL, o activa InpAllowMinLotIfTooSmall.",
                                lots, volMin, riskMoney, AccountInfoString(ACCOUNT_CURRENCY), lossPerLot);
         return 0.0;
      }
   }
   if(normalized > volMax)
      normalized = volMax;

   return normalized;
}

//+------------------------------------------------------------------+
//| Abre la operación de ruptura en la dirección indicada            |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE dir)
{
   double atrBuf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0)
   {
      PrintFormat("SessionRangeBreakoutEA: operación omitida, no se pudo leer el ATR (buffer no listo todavía, error=%d).",
                  GetLastError());
      return;
   }

   double atr = atrBuf[0];
   if(atr <= 0)
   {
      PrintFormat("SessionRangeBreakoutEA: operación omitida, ATR devuelto = %.5f (¿historial insuficiente para %d periodos?)",
                  atr, InpATRPeriod);
      return;
   }

   double slDistance = atr * InpATRMultiplierSL;

   long stopLevelPts   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist  = MathMax((double)stopLevelPts, (double)freezeLevelPts) * _Point;
   if(slDistance < minStopDist)
      slDistance = minStopDist;
   if(slDistance <= 0)
   {
      Print("SessionRangeBreakoutEA: operación omitida, distancia de SL calculada = 0.");
      return;
   }

   double price = (dir == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   if(dir == ORDER_TYPE_BUY)
   {
      sl = price - slDistance;
      tp = price + slDistance * InpRiskReward;
   }
   else
   {
      sl = price + slDistance;
      tp = price - slDistance * InpRiskReward;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   string lotReason = "";
   double lots = CalculateLotSize(slDistance, lotReason);
   if(lots <= 0)
   {
      PrintFormat("SessionRangeBreakoutEA: operación omitida, lote inválido. %s", lotReason);
      return;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);
   trade.SetTypeFilling(GetFillingMode());

   bool ok;
   if(dir == ORDER_TYPE_BUY)
      ok = trade.Buy(lots, _Symbol, price, sl, tp, InpComment);
   else
      ok = trade.Sell(lots, _Symbol, price, sl, tp, InpComment);

   if(ok)
   {
      g_tradeTakenToday = true;
      PrintFormat("SessionRangeBreakoutEA: %s abierta. Lote=%.2f SL=%.5f TP=%.5f",
                  (dir == ORDER_TYPE_BUY ? "COMPRA" : "VENTA"), lots, sl, tp);
   }
   else
   {
      PrintFormat("SessionRangeBreakoutEA: fallo al abrir orden. Retcode=%d %s",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Comprueba la ruptura por cierre de vela y, si procede, entra     |
//+------------------------------------------------------------------+
void CheckBreakoutAndEnter(const datetime rangeEndT)
{
   if(g_rangeHigh <= 0 || g_rangeLow <= 0 || g_rangeHigh <= g_rangeLow)
      return;

   datetime closedBarTime = iTime(_Symbol, InpConfirmTF, 1);
   if(closedBarTime == 0 || closedBarTime < rangeEndT)
      return; // aún no hay una vela cerrada completamente después del rango

   double closedClose = iClose(_Symbol, InpConfirmTF, 1);
   if(closedClose <= 0)
      return;

   if(InpMaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints)
      {
         if(InpDebugLog && closedBarTime != g_lastEvalBarLogged)
            PrintFormat("SessionRangeBreakoutEA: spread %d > InpMaxSpreadPoints %d, entrada bloqueada en %s",
                        spread, InpMaxSpreadPoints, TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES));
         g_lastEvalBarLogged = closedBarTime;
         return;
      }
   }

   double buffer = InpBreakoutBufferPoints * _Point;

   if(InpDebugLog && closedBarTime != g_lastEvalBarLogged)
   {
      PrintFormat("SessionRangeBreakoutEA: vela %s cierre=%.5f vs rango [%.5f , %.5f]",
                  TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES), closedClose, g_rangeLow, g_rangeHigh);
      g_lastEvalBarLogged = closedBarTime;
   }

   if(closedClose > g_rangeHigh + buffer)
      OpenTrade(ORDER_TYPE_BUY);
   else if(closedClose < g_rangeLow - buffer)
      OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRiskPercent <= 0 || InpRiskPercent > 100)
   {
      Print("SessionRangeBreakoutEA: InpRiskPercent inválido.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpATRPeriod <= 0)
   {
      Print("SessionRangeBreakoutEA: InpATRPeriod inválido.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpATRMultiplierSL <= 0 || InpRiskReward <= 0)
   {
      Print("SessionRangeBreakoutEA: InpATRMultiplierSL / InpRiskReward inválidos.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRangeStartHour < 0 || InpRangeStartHour > 23 || InpRangeEndHour < 0 || InpRangeEndHour > 23 ||
      InpRangeStartMinute < 0 || InpRangeStartMinute > 59 || InpRangeEndMinute < 0 || InpRangeEndMinute > 59 ||
      InpForceCloseHour < 0 || InpForceCloseHour > 23 || InpForceCloseMinute < 0 || InpForceCloseMinute > 59)
   {
      Print("SessionRangeBreakoutEA: horas/minutos configurados fuera de rango (0-23 / 0-59).");
      return INIT_PARAMETERS_INCORRECT;
   }

   int rangeStartSec = InpRangeStartHour * 3600 + InpRangeStartMinute * 60;
   int rangeEndSec   = InpRangeEndHour   * 3600 + InpRangeEndMinute   * 60;
   if(rangeStartSec >= rangeEndSec)
   {
      Print("SessionRangeBreakoutEA: la hora de inicio del rango debe ser anterior a la de fin ",
            "(no se soportan rangos que cruzan medianoche).");
      return INIT_PARAMETERS_INCORRECT;
   }

   int forceCloseSec = InpForceCloseHour * 3600 + InpForceCloseMinute * 60;
   if(InpForceCloseEnabled && forceCloseSec <= rangeEndSec)
      Print("SessionRangeBreakoutEA: AVISO - la hora de cierre forzado es anterior o igual a la hora de fin ",
            "del rango; la EA no podrá abrir operaciones. Revisa InpForceCloseHour/Minute.");

   g_atrHandle = iATR(_Symbol, InpConfirmTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("SessionRangeBreakoutEA: no se pudo crear el indicador ATR.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);

   g_currentDay          = 0; // fuerza reinicio/sincronización en el primer tick
   g_rangeReady          = false;
   g_tradeTakenToday      = false;
   g_forceCloseDoneToday = false;

   if(InpDebugLog)
      PrintFormat("SessionRangeBreakoutEA: init OK. Símbolo=%s Rango=%02d:%02d-%02d:%02d (TF %s) "
                  "Confirmación=%s ATR(%d)x%.2f RR=%.2f Riesgo=%.2f%% CierreForzado=%02d:%02d (%s) "
                  "Hora de servidor actual=%s",
                  _Symbol, InpRangeStartHour, InpRangeStartMinute, InpRangeEndHour, InpRangeEndMinute,
                  EnumToString(InpRangeTF), EnumToString(InpConfirmTF), InpATRPeriod, InpATRMultiplierSL,
                  InpRiskReward, InpRiskPercent, InpForceCloseHour, InpForceCloseMinute,
                  (InpForceCloseEnabled ? "activado" : "desactivado"),
                  TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now      = TimeCurrent();
   datetime dayStart = DayStart(now);

   if(dayStart != g_currentDay)
   {
      ResetDailyState(dayStart);
      SyncStateForToday(dayStart);
   }

   datetime rangeEndT   = TimeOfDay(dayStart, InpRangeEndHour, InpRangeEndMinute);
   datetime forceCloseT = TimeOfDay(dayStart, InpForceCloseHour, InpForceCloseMinute);

   //--- Cierre forzado por hora, siempre se comprueba primero
   if(InpForceCloseEnabled && now >= forceCloseT && !g_forceCloseDoneToday)
   {
      ForceCloseOwnPositions();
      g_forceCloseDoneToday = true;
   }

   //--- Construye el rango una vez finalizada la ventana horaria
   if(!g_rangeReady && now >= rangeEndT)
   {
      if(ComputeRange(dayStart))
         g_rangeReady = true;
   }

   if(!g_rangeReady)                         return;
   if(g_tradeTakenToday)                      return;
   if(!IsTradingDayAllowed(now))              return;
   if(InpForceCloseEnabled && now >= forceCloseT) return;
   if(HasOpenPosition())                      return;

   CheckBreakoutAndEnter(rangeEndT);
}
//+------------------------------------------------------------------+
