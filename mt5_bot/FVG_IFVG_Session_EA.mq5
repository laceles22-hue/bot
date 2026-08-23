//+------------------------------------------------------------------+
//|                                     FVG_IFVG_Session_EA.mq5      |
//+------------------------------------------------------------------+
// =====================================================================
// FVG / IFVG + Liquidez de sesión — Expert Advisor
// ---------------------------------------------------------------------
// Puerto a MQL5 de la misma lógica del indicador Pine "FVG & IFVG"
// (indicators/fvg_ifvg.pine) de este repositorio, convertida en una
// estrategia operable de forma automática:
//
//   1. Detecta Fair Value Gaps (FVG) con el patrón clásico de 3 velas.
//   2. Cuando un FVG se mitiga (el precio lo atraviesa por completo),
//      la zona se invierte y pasa a ser un IFVG (soporte/resistencia
//      en sentido contrario).
//   3. Calcula niveles de liquidez de referencia: máximo/mínimo del
//      día anterior (PDH/PDL) y máximo/mínimo de las sesiones
//      anteriores de Londres y Nueva York.
//   4. Estrategia de entrada tipo "smart money": exige (opcionalmente)
//      un barrido de liquidez sobre uno de esos niveles seguido de un
//      reclamo (cierre de vuelta al otro lado) antes de operar el
//      primer FVG/IFVG que el precio toque en la dirección del sesgo
//      resultante.
//   5. Gestión de riesgo por % de equity, con SL en el borde de la
//      zona y TP como múltiplo R configurable.
//
// IMPORTANTE — ninguna estrategia de trading garantiza beneficios.
// Antes de operar en real: probar a fondo en el Strategy Tester de
// MT5 (modo "Cada tick basado en datos reales"), en cuenta demo, y
// ajustar los parámetros a cada símbolo/timeframe/bróker concreto.
// Ver mt5_bot/README.md para la guía de instalación y parámetros.
// =====================================================================
#property copyright "bot"
#property version   "1.00"

#include <Trade/Trade.mqh>

//====================================================================
// INPUTS
//====================================================================
input group "=== Fair Value Gap (FVG) / Inverse FVG (IFVG) ==="
input bool   InpTradeIFVG          = true;   // Operar también zonas IFVG (no solo FVG)
input double InpMinGapATRMult      = 0.0;    // Tamaño mínimo del gap en múltiplos de ATR (0 = sin filtro)
input int    InpATRPeriod          = 14;     // Periodo ATR para el filtro de tamaño
input int    InpMaxZonesPerSide    = 20;     // Máx. zonas activas por lado (bull/bear FVG e IFVG)

enum ENUM_MITIGATION_MODE
{
   MITIGATION_CLOSE = 0, // Cierre de vela (recomendado)
   MITIGATION_WICK  = 1  // Mecha (toque)
};
input ENUM_MITIGATION_MODE InpMitigationMode = MITIGATION_CLOSE; // Cuándo se considera mitigada una zona

input group "=== Niveles de liquidez ==="
input bool InpUsePDHPDL        = true;  // Usar máximo/mínimo del día anterior (PDH/PDL)
input bool InpUseNYSession     = true;  // Usar sesión de Nueva York anterior
input int  InpNYStartHour      = 16;    // Inicio sesión NY (hora del SERVIDOR del bróker)
input int  InpNYStartMin       = 30;
input int  InpNYEndHour        = 23;    // Fin sesión NY (hora del servidor)
input int  InpNYEndMin         = 0;
input bool InpUseLondonSession = true;  // Usar sesión de Londres anterior
input int  InpLdnStartHour     = 10;    // Inicio sesión Londres (hora del servidor)
input int  InpLdnStartMin      = 0;
input int  InpLdnEndHour       = 18;    // Fin sesión Londres (hora del servidor)
input int  InpLdnEndMin        = 30;
// NOTA: MT5 no expone una base de datos de zonas horarias como Pine Script.
// Estas horas son en el horario del SERVIDOR de tu bróker (visible en la
// esquina del gráfico). Ajusta estos 4 pares de valores una vez, comparando
// la hora del servidor con la hora real de Londres/Nueva York (recuerda que
// el offset cambia con el horario de verano/invierno de cada zona).

input group "=== Estrategia de entrada ==="
input bool InpRequireLiquiditySweep = true;  // Exigir barrido + reclamo del nivel antes de operar
input int  InpSweepLookbackBars     = 30;    // Velas hacia atrás para buscar el barrido

enum ENUM_TRADE_DIRECTION
{
   DIR_BOTH       = 0, // Largos y cortos
   DIR_LONG_ONLY  = 1, // Solo largos
   DIR_SHORT_ONLY = 2  // Solo cortos
};
input ENUM_TRADE_DIRECTION InpTradeDirection = DIR_BOTH;

input group "=== Gestión de riesgo ==="
input bool   InpUseRiskPercent      = true;  // Calcular lote por % de riesgo (si no, usa lote fijo)
input double InpRiskPercent         = 1.0;   // % de equity arriesgado por operación
input double InpFixedLot            = 0.10;  // Lote fijo (si InpUseRiskPercent = false)
input double InpSLBufferPoints      = 20;    // Colchón extra para el SL, en puntos
input double InpRewardRiskRatio     = 2.0;   // Take profit como múltiplo del riesgo (R)
input int    InpMaxPositions        = 1;     // Máx. posiciones simultáneas abiertas por este EA
input double InpMaxSpreadPoints     = 30;    // Spread máximo permitido para entrar, en puntos
input double InpMaxDailyLossPercent = 3.0;   // Pérdida diaria máx. (%) antes de bloquear nuevas entradas (0 = desactivado)

input group "=== General ==="
input ulong InpMagicNumber          = 20260823; // Número mágico (identifica las órdenes de este EA)
input bool  InpUseTradingHoursFilter = false;    // Restringir a un horario de trading (hora servidor)
input int   InpTradeStartHour        = 0;
input int   InpTradeEndHour          = 23;
input bool  InpShowDashboard          = true;    // Mostrar panel de estado en el gráfico
input bool  InpLogSessionDiagnostics  = true;    // Registrar en el log cada cierre de sesión NY/Londres detectado (para calibrar los horarios)

//====================================================================
// TIPOS Y VARIABLES GLOBALES
//====================================================================
struct FvgZone
{
   double   top;
   double   bottom;
   datetime openTime;
   bool     traded;
};

FvgZone g_bullFvg[];
FvgZone g_bearFvg[];
FvgZone g_bullIfvg[];
FvgZone g_bearIfvg[];

CTrade  g_trade;
int     g_atrHandle = INVALID_HANDLE;

double  g_pdHigh = -1, g_pdLow = -1;
double  g_prevNYHigh = -1, g_prevNYLow = -1;
double  g_prevLdnHigh = -1, g_prevLdnLow = -1;

bool    g_bullishBias = false;
bool    g_bearishBias = false;

double  g_dayStartEquity = 0;
datetime g_dayStartDate  = 0;

//====================================================================
// UTILIDADES
//====================================================================
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime t = iTime(_Symbol, _Period, 0);
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

double GetATR()
{
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

bool InSessionWindow(datetime t, int startH, int startM, int endH, int endM)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int cur   = dt.hour * 60 + dt.min;
   int start = startH * 60 + startM;
   int end   = endH * 60 + endM;
   if(start <= end)
      return (cur >= start && cur < end);
   // Ventana que cruza medianoche (no habitual para Londres/NY, pero por seguridad)
   return (cur >= start || cur < end);
}

bool ClosedThroughBull(double bottom) // ¿el precio invalidó una zona alcista (soporte)?
{
   double c1 = iClose(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   return (InpMitigationMode == MITIGATION_CLOSE) ? (c1 < bottom) : (l1 < bottom);
}

bool ClosedThroughBear(double top) // ¿el precio invalidó una zona bajista (resistencia)?
{
   double c1 = iClose(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1);
   return (InpMitigationMode == MITIGATION_CLOSE) ? (c1 > top) : (h1 > top);
}

double NormalizeLot(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   double norm = MathFloor(lots / step) * step;
   norm = MathMax(minLot, MathMin(maxLot, norm));
   return NormalizeDouble(norm, 2);
}

double SpreadPoints()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

bool WithinTradingHours()
{
   if(!InpUseTradingHoursFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpTradeStartHour <= InpTradeEndHour)
      return (dt.hour >= InpTradeStartHour && dt.hour <= InpTradeEndHour);
   return (dt.hour >= InpTradeStartHour || dt.hour <= InpTradeEndHour);
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      count++;
   }
   return count;
}

bool DailyLossLimitHit()
{
   if(InpMaxDailyLossPercent <= 0) return false;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime todayMidnight = now - (dt.hour * 3600 + dt.min * 60 + dt.sec);

   if(todayMidnight != g_dayStartDate)
   {
      g_dayStartDate   = todayMidnight;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   if(g_dayStartEquity <= 0) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct  = (g_dayStartEquity - equity) / g_dayStartEquity * 100.0;
   return (ddPct >= InpMaxDailyLossPercent);
}

//====================================================================
// GESTIÓN DE ZONAS (array dinámico tipo "cola")
//====================================================================
void RemoveZoneAt(FvgZone &arr[], int idx)
{
   int n = ArraySize(arr);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++)
      arr[i] = arr[i + 1];
   ArrayResize(arr, n - 1);
}

void PushZone(FvgZone &arr[], double top, double bottom, datetime t)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].top      = top;
   arr[n].bottom   = bottom;
   arr[n].openTime = t;
   arr[n].traded   = false;
   if(ArraySize(arr) > InpMaxZonesPerSide)
      RemoveZoneAt(arr, 0);
}

//====================================================================
// DETECCIÓN Y MITIGACIÓN DE FVG / IFVG (una vez por vela cerrada)
//====================================================================
void UpdateFvgZones()
{
   // --- 1) Mitigación de zonas existentes (recorrido inverso: permite eliminar con seguridad) ---
   for(int i = ArraySize(g_bullFvg) - 1; i >= 0; i--)
   {
      if(ClosedThroughBull(g_bullFvg[i].bottom))
      {
         if(InpTradeIFVG)
            PushZone(g_bearIfvg, g_bullFvg[i].top, g_bullFvg[i].bottom, iTime(_Symbol, _Period, 1));
         RemoveZoneAt(g_bullFvg, i);
      }
   }
   for(int i = ArraySize(g_bearFvg) - 1; i >= 0; i--)
   {
      if(ClosedThroughBear(g_bearFvg[i].top))
      {
         if(InpTradeIFVG)
            PushZone(g_bullIfvg, g_bearFvg[i].top, g_bearFvg[i].bottom, iTime(_Symbol, _Period, 1));
         RemoveZoneAt(g_bearFvg, i);
      }
   }
   for(int i = ArraySize(g_bullIfvg) - 1; i >= 0; i--)
      if(ClosedThroughBull(g_bullIfvg[i].bottom))
         RemoveZoneAt(g_bullIfvg, i);
   for(int i = ArraySize(g_bearIfvg) - 1; i >= 0; i--)
      if(ClosedThroughBear(g_bearIfvg[i].top))
         RemoveZoneAt(g_bearIfvg, i);

   // --- 2) Detección de nuevos FVG (patrón de 3 velas ya cerradas: shift 3, 2, 1) ---
   double low1  = iLow(_Symbol, _Period, 1);
   double high1 = iHigh(_Symbol, _Period, 1);
   double low3  = iLow(_Symbol, _Period, 3);
   double high3 = iHigh(_Symbol, _Period, 3);
   double atr   = GetATR();

   bool bullGapUp = (low1 > high3);
   bool bearGapDn = (high1 < low3);

   double bullTop = low1,  bullBot = high3;
   double bearTop = low3,  bearBot = high1;

   bool bullSizeOk = (InpMinGapATRMult <= 0) || ((bullTop - bullBot) >= atr * InpMinGapATRMult);
   bool bearSizeOk = (InpMinGapATRMult <= 0) || ((bearTop - bearBot) >= atr * InpMinGapATRMult);

   if(bullGapUp && bullSizeOk)
      PushZone(g_bullFvg, bullTop, bullBot, iTime(_Symbol, _Period, 3));
   if(bearGapDn && bearSizeOk)
      PushZone(g_bearFvg, bearTop, bearBot, iTime(_Symbol, _Period, 3));
}

//====================================================================
// NIVELES DE LIQUIDEZ: PDH/PDL Y SESIONES DE LONDRES / NY
//====================================================================
void UpdatePDHPDL()
{
   if(!InpUsePDHPDL) return;
   double h = iHigh(_Symbol, PERIOD_D1, 1);
   double l = iLow(_Symbol, PERIOD_D1, 1);
   if(h > 0) g_pdHigh = h;
   if(l > 0) g_pdLow  = l;
}

// Acumula el máximo/mínimo de una sesión vela a vela y, al terminar la
// sesión, vuelca el resultado en prevHigh/prevLow (igual que el indicador).
// Si InpLogSessionDiagnostics está activo, deja en el log de Experts cada
// cierre de sesión detectado — así puedes comprobar, sin adivinar, si los
// horarios configurados caen realmente dentro de la sesión que quieres
// capturar (mira las velas/horas del gráfico en esos momentos).
void UpdateSession(string label, int startH, int startM, int endH, int endM,
                    double &runHigh, double &runLow, bool &wasIn,
                    double &prevHigh, double &prevLow)
{
   datetime t1 = iTime(_Symbol, _Period, 1);
   double   h1 = iHigh(_Symbol, _Period, 1);
   double   l1 = iLow(_Symbol, _Period, 1);
   bool     isIn = InSessionWindow(t1, startH, startM, endH, endM);

   if(isIn && !wasIn)
   {
      runHigh = h1;
      runLow  = l1;
   }
   else if(isIn)
   {
      runHigh = MathMax(runHigh, h1);
      runLow  = MathMin(runLow, l1);
   }

   if(wasIn && !isIn)
   {
      prevHigh = runHigh;
      prevLow  = runLow;
      if(InpLogSessionDiagnostics)
         PrintFormat("[FVG_IFVG_EA] Sesión %s cerrada a las %s (hora servidor) -> H=%.5f L=%.5f",
                     label, TimeToString(t1, TIME_DATE | TIME_MINUTES), prevHigh, prevLow);
   }
   wasIn = isIn;
}

void UpdateSessions()
{
   static double runNYHigh = 0, runNYLow = 0;
   static bool   wasInNY   = false;
   static double runLdnHigh = 0, runLdnLow = 0;
   static bool   wasInLdn   = false;

   if(InpUseNYSession)
      UpdateSession("NY", InpNYStartHour, InpNYStartMin, InpNYEndHour, InpNYEndMin,
                     runNYHigh, runNYLow, wasInNY, g_prevNYHigh, g_prevNYLow);

   if(InpUseLondonSession)
      UpdateSession("Londres", InpLdnStartHour, InpLdnStartMin, InpLdnEndHour, InpLdnEndMin,
                     runLdnHigh, runLdnLow, wasInLdn, g_prevLdnHigh, g_prevLdnLow);
}

//====================================================================
// SESGO: BARRIDO DE LIQUIDEZ + RECLAMO
//====================================================================
bool HasBullishSweep(double level)
{
   if(level <= 0) return false;
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 <= level) return false; // la última vela cerrada debe haber reclamado por encima del nivel
   for(int i = 2; i <= InpSweepLookbackBars + 1; i++)
      if(iLow(_Symbol, _Period, i) < level)
         return true;
   return false;
}

bool HasBearishSweep(double level)
{
   if(level <= 0) return false;
   double c1 = iClose(_Symbol, _Period, 1);
   if(c1 >= level) return false;
   for(int i = 2; i <= InpSweepLookbackBars + 1; i++)
      if(iHigh(_Symbol, _Period, i) > level)
         return true;
   return false;
}

void UpdateBias()
{
   if(!InpRequireLiquiditySweep)
   {
      g_bullishBias = true;
      g_bearishBias = true;
      return;
   }

   g_bullishBias = false;
   g_bearishBias = false;

   if(InpUsePDHPDL      && HasBullishSweep(g_pdLow))      g_bullishBias = true;
   if(InpUseNYSession    && HasBullishSweep(g_prevNYLow))  g_bullishBias = true;
   if(InpUseLondonSession && HasBullishSweep(g_prevLdnLow)) g_bullishBias = true;

   if(InpUsePDHPDL      && HasBearishSweep(g_pdHigh))      g_bearishBias = true;
   if(InpUseNYSession    && HasBearishSweep(g_prevNYHigh))  g_bearishBias = true;
   if(InpUseLondonSession && HasBearishSweep(g_prevLdnHigh)) g_bearishBias = true;
}

//====================================================================
// GESTIÓN DE RIESGO Y ENVÍO DE ÓRDENES
//====================================================================
double CalcLotSize(double slDistance)
{
   if(!InpUseRiskPercent)
      return NormalizeLot(InpFixedLot);

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0)
      return NormalizeLot(InpFixedLot);

   double valuePerPriceUnit = tickValue / tickSize;
   double lossPerLot        = slDistance * valuePerPriceUnit;
   if(lossPerLot <= 0)
      return NormalizeLot(InpFixedLot);

   return NormalizeLot(riskMoney / lossPerLot);
}

void TryEnterFromZones(FvgZone &arr[], bool isBuy)
{
   if(CountOpenPositions() >= InpMaxPositions) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double px  = isBuy ? ask : bid;

   for(int i = 0; i < ArraySize(arr); i++)
   {
      if(arr[i].traded) continue;
      if(px < arr[i].bottom || px > arr[i].top) continue; // el precio no está dentro de la zona

      double buffer = InpSLBufferPoints * _Point;
      double sl, tp, risk;

      if(isBuy)
      {
         sl   = arr[i].bottom - buffer;
         risk = ask - sl;
         if(risk <= 0) continue;
         tp = ask + risk * InpRewardRiskRatio;
      }
      else
      {
         sl   = arr[i].top + buffer;
         risk = sl - bid;
         if(risk <= 0) continue;
         tp = bid - risk * InpRewardRiskRatio;
      }

      double lots = CalcLotSize(risk);
      if(lots <= 0) continue;

      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      bool ok = isBuy ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "FVG_IFVG_EA")
                       : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "FVG_IFVG_EA");

      if(ok)
      {
         arr[i].traded = true;
         PrintFormat("[FVG_IFVG_EA] %s abierta | lote=%.2f SL=%.5f TP=%.5f",
                     isBuy ? "COMPRA" : "VENTA", lots, sl, tp);
         if(CountOpenPositions() >= InpMaxPositions) return;
      }
      else
      {
         PrintFormat("[FVG_IFVG_EA] Error al enviar orden: %d", GetLastError());
      }
   }
}

void CheckEntries()
{
   if(DailyLossLimitHit()) return;
   if(!WithinTradingHours()) return;
   if(CountOpenPositions() >= InpMaxPositions) return;
   if(SpreadPoints() > InpMaxSpreadPoints) return;

   if(InpTradeDirection != DIR_SHORT_ONLY && g_bullishBias)
   {
      TryEnterFromZones(g_bullFvg, true);
      if(InpTradeIFVG) TryEnterFromZones(g_bullIfvg, true);
   }
   if(InpTradeDirection != DIR_LONG_ONLY && g_bearishBias)
   {
      TryEnterFromZones(g_bearFvg, false);
      if(InpTradeIFVG) TryEnterFromZones(g_bearIfvg, false);
   }
}

//====================================================================
// PANEL DE ESTADO
//====================================================================
void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   string txt = StringFormat(
      "FVG_IFVG_Session_EA\n" +
      "Sesgo: %s%s\n" +
      "Zonas -> FVG alcista:%d bajista:%d | IFVG alcista:%d bajista:%d\n" +
      "PDH:%.5f PDL:%.5f | NY H:%.5f L:%.5f | LDN H:%.5f L:%.5f\n" +
      "Posiciones abiertas: %d/%d | Spread: %.1f pts",
      g_bullishBias ? "ALCISTA " : "", g_bearishBias ? "BAJISTA" : (g_bullishBias ? "" : "sin sesgo"),
      ArraySize(g_bullFvg), ArraySize(g_bearFvg), ArraySize(g_bullIfvg), ArraySize(g_bearIfvg),
      g_pdHigh, g_pdLow, g_prevNYHigh, g_prevNYLow, g_prevLdnHigh, g_prevLdnLow,
      CountOpenPositions(), InpMaxPositions, SpreadPoints());
   Comment(txt);
}

//====================================================================
// CICLO DE VIDA DEL EA
//====================================================================
int OnInit()
{
   g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("[FVG_IFVG_EA] No se pudo crear el indicador ATR.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);

   ArrayFree(g_bullFvg);
   ArrayFree(g_bearFvg);
   ArrayFree(g_bullIfvg);
   ArrayFree(g_bearIfvg);

   PrintFormat("[FVG_IFVG_EA] Inicializado en %s %s | Hora servidor ahora: %s | Hora GMT ahora: %s",
               _Symbol, EnumToString(_Period),
               TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
               TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS));
   Print("[FVG_IFVG_EA] Compara 'Hora servidor' con 'Hora GMT' de arriba para saber el offset de tu bróker, ",
         "y ajusta InpNYStart/EndHour e InpLdnStart/EndHour a la hora de SERVIDOR que corresponda a ",
         "09:30-16:00 hora de Nueva York y 08:00-16:30 hora de Londres respectivamente (recuerda el ",
         "horario de verano de cada zona).");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   Comment("");
}

void OnTick()
{
   if(Bars(_Symbol, _Period) < 10) return; // aún no hay histórico suficiente al arrancar

   if(IsNewBar())
   {
      UpdateFvgZones();
      UpdatePDHPDL();
      UpdateSessions();
      UpdateBias();
   }

   CheckEntries();
   UpdateDashboard();
}
//+------------------------------------------------------------------+
