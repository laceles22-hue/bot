//+------------------------------------------------------------------+
//| XAUUSD (Oro) - Breakout de Rango: sesión Londres + sesión NY      |
//|         Reformulado para operar XAUUSD en MT5 - Broker IC Markets |
//|                                                                    |
//|  Basado en el EA de un solo ciclo diario (rango asiático ->       |
//|  breakout de Londres). Esta versión corre DOS ciclos independien- |
//|  tes el mismo día, cada uno con su propio rango/breakout/gestión: |
//|                                                                    |
//|   - Ciclo "Londres": identifica el rango asiático y opera el      |
//|     breakout que suele producirse en la apertura de Londres.      |
//|   - Ciclo "Nueva York": identifica el rango de la mañana de       |
//|     Londres y opera el breakout que suele producirse en la        |
//|     apertura de Nueva York.                                       |
//|                                                                    |
//|  Cada ciclo tiene su propio magic number, así que pueden tener    |
//|  una posición abierta cada uno al mismo tiempo sin interferirse.  |
//|  El límite de operaciones diarias (MaxDailyTrades) es compartido  |
//|  entre ambos ciclos (cuenta el total del día, no por ciclo).      |
//|                                                                    |
//|  El resto de correcciones de la versión anterior se mantienen:    |
//|  SL/TP en USD (no "pips" de forex), horario en UTC + offset de    |
//|  servidor de IC Markets, validación de símbolo de oro, filtro de  |
//|  spread, y detección de breakout sobre velas ya CERRADAS (no la   |
//|  vela en formación, que da cuerpo 0 en el modelo de tester        |
//|  "Precios de apertura únicamente").                               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>

// Crear objeto para operaciones de trading (compartido, el magic number se
// cambia según el ciclo antes de cada operación)
CTrade trade;

// Parámetros de entrada
input string   TimeSettings      = "===== Configuración de Tiempo =====";
input int      BrokerGMTOffset   = 3;     // Offset servidor IC Markets vs UTC (2=invierno EET, 3=verano/DST). Verifica el reloj del terminal contra la hora UTC real.

input string   SymbolSettings    = "===== Configuración de Símbolo =====";
input bool     ValidateGoldSymbol = true;  // Verificar que el gráfico esté en un símbolo de Oro (XAU/GOLD)

input string   LondonSettings    = "===== Ciclo Londres: Rango Asiático -> Breakout apertura Londres =====";
input bool     EnableLondonSession      = true; // Activar ciclo de Londres
input int      London_RangeStartHourUTC = 0;    // Hora inicio rango asiático (UTC)
input int      London_RangeStartMin     = 0;    // Minuto inicio rango
input int      London_RangeEndHourUTC   = 7;    // Hora fin rango (UTC) - antes de apertura de Londres
input int      London_RangeEndMin       = 0;    // Minuto fin rango

input string   NewYorkSettings   = "===== Ciclo Nueva York: Rango mañana Londres -> Breakout apertura NY =====";
input bool     EnableNewYorkSession = true;  // Activar ciclo de Nueva York
input int      NY_RangeStartHourUTC = 7;     // Hora inicio rango (UTC) - apertura de Londres
input int      NY_RangeStartMin     = 0;     // Minuto inicio rango
input int      NY_RangeEndHourUTC   = 12;    // Hora fin rango (UTC) - antes de apertura de Nueva York
input int      NY_RangeEndMin       = 0;     // Minuto fin rango

input string   TradeSettings     = "===== Configuración de Trading (compartida por ambos ciclos) =====";
input bool     UseVolume         = false;  // Usar volumen para confirmación
input double   MinVolumeIncrease = 1.5;    // Incremento mínimo de volumen para confirmar breakout
input double   RiskPercent       = 1.0;    // Riesgo por operación (%)
input int      MaxSpreadPoints   = 50;     // Spread máximo permitido para entrar (puntos, 0 = sin filtro)

input string   IndicatorSettings = "===== Configuración de Indicadores =====";
input bool     UseBB            = true;   // Usar validación con Bandas de Bollinger
input int      BBPeriod         = 20;     // Periodo para Bandas de Bollinger
input double   BBDeviation      = 2.0;    // Desviación estándar para Bandas Bollinger
input ENUM_APPLIED_PRICE BBAppliedPrice = PRICE_CLOSE; // Precio aplicado para Bandas de Bollinger

input string   RangeSettings     = "===== Configuración del Rango =====";
input double   MinRangeUSD       = 3.0;   // Tamaño mínimo del rango para operar (USD), aplica a ambos ciclos

input string   SLTPSettings     = "===== Configuración de Stop Loss y Take Profit (USD) =====";
input bool     UseRangeForSLTP  = true;   // Usar tamaño del rango para SL/TP (si no, usar valores en USD)
input double   StopLossUSD      = 5.0;    // Stop Loss en USD (si no usa rango)
input double   TakeProfit1USD   = 8.0;    // Take Profit 1 en USD (si no usa rango)
input double   TakeProfit2USD   = 16.0;   // Take Profit 2 en USD (si no usa rango)
input bool     UseBreakEven     = true;   // Activar movimiento de SL a breakeven
input double   BreakEvenPercent = 50.0;   // Porcentaje hacia TP1 para mover a breakeven
input double   BreakEvenBufferUSD = 0.10; // Buffer adicional al mover a breakeven (USD)

input string   TPSettings        = "===== Configuración de Take Profit =====";
input bool     UseTP1            = true;   // Usar TP1 (1x tamaño del rango o TakeProfit1USD)
input bool     UseTP2            = true;   // Usar TP2 (2x tamaño del rango o TakeProfit2USD)
input double   TP1Percent        = 50.0;   // Porcentaje del volumen para cerrar en TP1 (%)
input double   TP2Percent        = 50.0;   // Porcentaje del volumen para cerrar en TP2 (%)

input string   EntrySettings     = "===== Configuración de Entrada =====";
input bool     UsePullbackEntry  = true;   // Usar entrada en pullback
input double   PullbackPercent   = 30.0;   // Porcentaje de retroceso para entrada (%)
input bool     UseContinuationEntry = true; // Usar entrada en continuación

input string   LimitsSettings    = "===== Límites de Operaciones =====";
input int      MaxDailyTrades    = 4;     // Máximo de operaciones por día, SUMANDO ambos ciclos (0 = sin límite)

input string   DebugSettings     = "===== Diagnóstico =====";
input bool     DebugLogs         = true;  // Imprimir logs detallados para diagnosticar por qué no entra

//+------------------------------------------------------------------+
//| Estado de un ciclo de sesión (Londres o Nueva York)               |
//+------------------------------------------------------------------+
struct SessionState
{
   string   name;              // Nombre para logs, ej. "Londres"
   int      magicNumber;
   int      rangeStartHourSrv; // Hora inicio de rango ya convertida a hora de servidor
   int      rangeStartMin;
   int      rangeEndHourSrv;   // Hora fin de rango ya convertida a hora de servidor
   int      rangeEndMin;
   double   rangeHigh;
   double   rangeLow;
   double   rangeSize;
   bool     rangeIdentified;
   bool     breakoutDetected;
   bool     secondCloseConfirmed;
   int      breakoutDirection; // 1 alcista, -1 bajista
   datetime breakoutTime;
   ulong    ticket;
   bool     inTrade;
};

SessionState g_london;
SessionState g_newyork;

// Variables para control de operaciones diarias (compartidas por ambos ciclos)
datetime currentDay = 0;
int dailyTradesCount = 0;

// Manejador para indicador de Bandas de Bollinger (compartido, mismo símbolo/periodo)
int bbHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verificar que el gráfico corresponde a un símbolo de Oro
   if(ValidateGoldSymbol)
   {
      string sym = _Symbol;
      StringToUpper(sym);
      if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      {
         Print("ERROR: Este EA está pensado para XAUUSD (Oro). Símbolo actual: ", _Symbol,
               ". Adjúntalo al gráfico de XAUUSD o desactiva ValidateGoldSymbol.");
         return INIT_FAILED;
      }
   }

   // Asegurar que el símbolo está disponible en Market Watch (necesario para CopyRates/CopyTickVolume)
   if(!SymbolSelect(_Symbol, true))
   {
      Print("Error: no se pudo seleccionar ", _Symbol, " en Market Watch.");
      return INIT_FAILED;
   }

   // Configurar ciclo Londres (rango asiático -> breakout apertura Londres)
   g_london.name = "Londres";
   g_london.magicNumber = 55010;
   g_london.rangeStartHourSrv = (London_RangeStartHourUTC + BrokerGMTOffset + 24) % 24;
   g_london.rangeStartMin     = London_RangeStartMin;
   g_london.rangeEndHourSrv   = (London_RangeEndHourUTC + BrokerGMTOffset + 24) % 24;
   g_london.rangeEndMin       = London_RangeEndMin;

   // Configurar ciclo Nueva York (rango mañana de Londres -> breakout apertura NY)
   g_newyork.name = "Nueva York";
   g_newyork.magicNumber = 55020;
   g_newyork.rangeStartHourSrv = (NY_RangeStartHourUTC + BrokerGMTOffset + 24) % 24;
   g_newyork.rangeStartMin     = NY_RangeStartMin;
   g_newyork.rangeEndHourSrv   = (NY_RangeEndHourUTC + BrokerGMTOffset + 24) % 24;
   g_newyork.rangeEndMin       = NY_RangeEndMin;

   // Inicializar el manejador de las Bandas de Bollinger si se utilizan
   if(UseBB)
   {
      bbHandle = iBands(_Symbol, _Period, BBPeriod, 0, BBDeviation, BBAppliedPrice);
      if(bbHandle == INVALID_HANDLE)
      {
         Print("Error al crear el indicador Bandas de Bollinger");
         return INIT_FAILED;
      }
   }

   // Inicializar variables de control de operaciones diarias
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   currentDay = TimeCurrent() - currentTime.hour*3600 - currentTime.min*60 - currentTime.sec;
   dailyTradesCount = 0;

   Print("XAUUSD London+NY Breakout EA (IC Markets) inicializado. Símbolo=", _Symbol,
         " Digits=", _Digits, " Point=", _Point,
         " Spread actual=", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), " puntos");
   Print("[Londres] Activo=", EnableLondonSession, " | Rango en hora servidor: ",
         g_london.rangeStartHourSrv, ":", g_london.rangeStartMin, " - ",
         g_london.rangeEndHourSrv, ":", g_london.rangeEndMin,
         " (UTC ", London_RangeStartHourUTC, ":00 - ", London_RangeEndHourUTC, ":00)");
   Print("[Nueva York] Activo=", EnableNewYorkSession, " | Rango en hora servidor: ",
         g_newyork.rangeStartHourSrv, ":", g_newyork.rangeStartMin, " - ",
         g_newyork.rangeEndHourSrv, ":", g_newyork.rangeEndMin,
         " (UTC ", NY_RangeStartHourUTC, ":00 - ", NY_RangeEndHourUTC, ":00)");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(UseBB && bbHandle != INVALID_HANDLE)
      IndicatorRelease(bbHandle);

   Print("XAUUSD London+NY Breakout EA (IC Markets) desactivado");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Chequear si es un nuevo día de trading
   if(IsNewTradingDay())
   {
      ResetSessionDailyState(g_london);
      ResetSessionDailyState(g_newyork);
   }

   if(EnableLondonSession)
      ProcessSession(g_london);

   if(EnableNewYorkSession)
      ProcessSession(g_newyork);
}

//+------------------------------------------------------------------+
//| Ejecutar la máquina de estados de un ciclo (Londres o NY)         |
//+------------------------------------------------------------------+
void ProcessSession(SessionState &s)
{
   // 1. Identificar el rango del ciclo
   if(!s.rangeIdentified)
      IdentifyRange(s);

   // 2. Detectar breakout con vela de impulso
   if(s.rangeIdentified && !s.breakoutDetected)
      DetectBreakout(s);

   // 3. Confirmar con segundo cierre fuera del rango
   if(s.breakoutDetected && !s.secondCloseConfirmed)
      ConfirmBreakout(s);

   // 4. Entrada en pullback o continuación
   if(s.secondCloseConfirmed && !s.inTrade)
      EnterTrade(s);

   // 5. Gestión de operaciones abiertas
   if(s.inTrade)
      ManageTrade(s);
}

//+------------------------------------------------------------------+
//| Resetear el estado diario de un ciclo (se llama al nuevo día).   |
//| No toca inTrade: ManageTrade() lo pondrá en false cuando detecte |
//| que la posición realmente se cerró.                              |
//+------------------------------------------------------------------+
void ResetSessionDailyState(SessionState &s)
{
   s.rangeIdentified = false;
   s.breakoutDetected = false;
   s.secondCloseConfirmed = false;
   s.breakoutDirection = 0;
   s.breakoutTime = 0;
}

//+------------------------------------------------------------------+
//| Verificar si es un nuevo día de trading                          |
//+------------------------------------------------------------------+
bool IsNewTradingDay()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);

   // Crear marca de tiempo para el día actual (sin horas, minutos, segundos)
   datetime todayDate = TimeCurrent() - currentTime.hour*3600 - currentTime.min*60 - currentTime.sec;

   // Reset al comenzar un nuevo día
   if(todayDate != currentDay)
   {
      currentDay = todayDate;
      dailyTradesCount = 0; // Resetear contador de operaciones (compartido por ambos ciclos)
      Print("Nuevo día de trading. Contador de operaciones reseteado.");
      if(DebugLogs)
      {
         Print("[DEBUG] Hora servidor actual: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
         Print("[DEBUG][Londres] Ventana de rango (hora servidor): ", g_london.rangeStartHourSrv, ":", g_london.rangeStartMin,
               " - ", g_london.rangeEndHourSrv, ":", g_london.rangeEndMin);
         Print("[DEBUG][Nueva York] Ventana de rango (hora servidor): ", g_newyork.rangeStartHourSrv, ":", g_newyork.rangeStartMin,
               " - ", g_newyork.rangeEndHourSrv, ":", g_newyork.rangeEndMin);
      }
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Identificar el rango de un ciclo (ventana ya en hora de servidor)|
//+------------------------------------------------------------------+
void IdentifyRange(SessionState &s)
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);

   // Verificar si ya pasó el periodo de rango (comparación correcta en minutos totales)
   int curTotalMin = currentTime.hour * 60 + currentTime.min;
   int endTotalMin = s.rangeEndHourSrv * 60 + s.rangeEndMin;

   if(curTotalMin >= endTotalMin)
   {
      // Calcular timestamps para el inicio y fin del rango (hora de servidor)
      MqlDateTime rangeStart, rangeEnd;
      TimeToStruct(TimeCurrent(), rangeStart);
      TimeToStruct(TimeCurrent(), rangeEnd);

      rangeStart.hour = s.rangeStartHourSrv;
      rangeStart.min = s.rangeStartMin;
      rangeStart.sec = 0;

      rangeEnd.hour = s.rangeEndHourSrv;
      rangeEnd.min = s.rangeEndMin;
      rangeEnd.sec = 0;

      datetime rangeStartTime = StructToTime(rangeStart);
      datetime rangeEndTime = StructToTime(rangeEnd);

      // Si el fin de rango cae "antes" que el inicio (cruce de medianoche por el offset), ajustar
      if(rangeEndTime < rangeStartTime)
      {
         rangeEndTime += 86400; // Añadir un día
      }

      // Encontrar máximo y mínimo durante el periodo de rango
      s.rangeHigh = 0;
      s.rangeLow = 999999;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(_Symbol, _Period, rangeStartTime, rangeEndTime, rates);

      if(copied > 0)
      {
         for(int i = 0; i < copied; i++)
         {
            if(rates[i].high > s.rangeHigh) s.rangeHigh = rates[i].high;
            if(rates[i].low < s.rangeLow) s.rangeLow = rates[i].low;
         }

         s.rangeSize = s.rangeHigh - s.rangeLow;

         // Validar que el rango es significativo (en USD, el oro se mueve mucho más que un par de forex)
         if(s.rangeSize >= MinRangeUSD)
         {
            s.rangeIdentified = true;
            Print("[", s.name, "] Rango identificado: Alto=", s.rangeHigh, " Bajo=", s.rangeLow,
                  " Tamaño=", DoubleToString(s.rangeSize, 2), " USD");
         }
         else
         {
            Print("[", s.name, "] Rango demasiado pequeño (", DoubleToString(s.rangeSize, 2),
                  " USD < ", DoubleToString(MinRangeUSD, 2), " USD), no se opera este ciclo hoy");
         }
      }
      else
      {
         Print("[", s.name, "] Error al obtener datos de precio. Error=", GetLastError(),
               " | rangeStartTime=", TimeToString(rangeStartTime, TIME_DATE|TIME_MINUTES),
               " rangeEndTime=", TimeToString(rangeEndTime, TIME_DATE|TIME_MINUTES),
               " (revisa si hay histórico cargado para ese rango de fechas/horas en el Strategy Tester)");
      }
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout con vela de impulso (sobre la última vela YA   |
//| CERRADA, para no depender del modelo del Strategy Tester)         |
//+------------------------------------------------------------------+
void DetectBreakout(SessionState &s)
{
   if(!s.rangeIdentified || s.rangeSize <= 0)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1, 2, rates);

   if(copied != 2)
   {
      Print("[", s.name, "] Error al obtener datos de precio. Error=", GetLastError());
      return;
   }

   double close0 = rates[0].close;
   double open0 = rates[0].open;
   double high0 = rates[0].high;
   double low0 = rates[0].low;

   double candleSize0 = MathAbs(close0 - open0);

   bool bbCondition = true; // Por defecto, pasamos la condición si no usamos BB

   if(UseBB)
   {
      double upperBand[], lowerBand[];
      ArraySetAsSeries(upperBand, true);
      ArraySetAsSeries(lowerBand, true);

      // Posición 1 = última vela cerrada, en línea con el CopyRates de más arriba
      bool bbCopied = CopyBuffer(bbHandle, 1, 1, 1, upperBand) > 0 &&
                     CopyBuffer(bbHandle, 2, 1, 1, lowerBand) > 0;

      if(!bbCopied)
      {
         Print("[", s.name, "] Error al obtener datos de Bandas de Bollinger. Error=", GetLastError());
         return;
      }

      if(close0 > s.rangeHigh)
         bbCondition = (high0 >= upperBand[0]);
      else if(close0 < s.rangeLow)
         bbCondition = (low0 <= lowerBand[0]);
   }

   // Revisar breakout alcista
   if(close0 > s.rangeHigh && candleSize0 > s.rangeSize * 0.15) // Vela de impulso (al menos 15% del rango)
   {
      if(bbCondition)
      {
         if(!UseVolume || IsVolumeIncreased())
         {
            s.breakoutDetected = true;
            s.breakoutDirection = 1; // Alcista
            s.breakoutTime = rates[0].time;
            Print("[", s.name, "] Breakout alcista detectado");
         }
         else if(DebugLogs)
            Print("[DEBUG][", s.name, "] Close rompió el rango al alza pero el filtro de volumen no confirmó");
      }
      else if(DebugLogs)
         Print("[DEBUG][", s.name, "] Close rompió el rango al alza pero no validó con Bandas de Bollinger (high0=", high0, ")");
   }
   // Revisar breakout bajista
   else if(close0 < s.rangeLow && candleSize0 > s.rangeSize * 0.15)
   {
      if(bbCondition)
      {
         if(!UseVolume || IsVolumeIncreased())
         {
            s.breakoutDetected = true;
            s.breakoutDirection = -1; // Bajista
            s.breakoutTime = rates[0].time;
            Print("[", s.name, "] Breakout bajista detectado");
         }
         else if(DebugLogs)
            Print("[DEBUG][", s.name, "] Close rompió el rango a la baja pero el filtro de volumen no confirmó");
      }
      else if(DebugLogs)
         Print("[DEBUG][", s.name, "] Close rompió el rango a la baja pero no validó con Bandas de Bollinger (low0=", low0, ")");
   }
   else if(DebugLogs && (close0 > s.rangeHigh || close0 < s.rangeLow))
   {
      Print("[DEBUG][", s.name, "] Close fuera del rango (close0=", close0, " rangeHigh=", s.rangeHigh,
            " rangeLow=", s.rangeLow, ") pero la vela es muy pequeña: candleSize0=",
            DoubleToString(candleSize0, 2), " requerido>", DoubleToString(s.rangeSize * 0.15, 2));
   }
}

//+------------------------------------------------------------------+
//| Verificar si el volumen ha aumentado significativamente          |
//| (genérico, no depende del ciclo)                                  |
//+------------------------------------------------------------------+
bool IsVolumeIncreased()
{
   if(!UseVolume)
      return true;

   // Tick volume de velas cerradas (posición 1 en adelante)
   long volume[];
   ArraySetAsSeries(volume, true);
   int copied = CopyTickVolume(_Symbol, _Period, 1, 6, volume);

   if(copied != 6)
   {
      Print("Error al obtener datos de volumen. Error=", GetLastError());
      return false;
   }

   long volumeNow = volume[0];

   double avgVolume = 0;
   for(int i = 1; i <= 5; i++)
   {
      avgVolume += (double)volume[i];
   }
   avgVolume /= 5;

   return ((double)volumeNow >= avgVolume * MinVolumeIncrease);
}

//+------------------------------------------------------------------+
//| Confirmar con segundo cierre fuera del rango (vela distinta a la  |
//| que generó el breakout)                                           |
//+------------------------------------------------------------------+
void ConfirmBreakout(SessionState &s)
{
   if(!s.breakoutDetected)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1, 1, rates);

   if(copied != 1)
   {
      Print("[", s.name, "] Error al obtener datos de precio. Error=", GetLastError());
      return;
   }

   // Exigir que sea una vela posterior a la que generó el breakout
   if(rates[0].time <= s.breakoutTime)
      return;

   double close0 = rates[0].close;

   if(s.breakoutDirection == 1 && close0 > s.rangeHigh)
   {
      s.secondCloseConfirmed = true;
      Print("[", s.name, "] Breakout alcista confirmado con segundo cierre");
   }
   else if(s.breakoutDirection == -1 && close0 < s.rangeLow)
   {
      s.secondCloseConfirmed = true;
      Print("[", s.name, "] Breakout bajista confirmado con segundo cierre");
   }
}

//+------------------------------------------------------------------+
//| Analizar patrón de vela para entrada (última vela YA CERRADA)     |
//+------------------------------------------------------------------+
bool IsValidCandlePattern(SessionState &s)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1, 1, rates);

   if(copied != 1)
   {
      Print("[", s.name, "] Error al obtener datos de precio. Error=", GetLastError());
      return false;
   }

   double open0 = rates[0].open;
   double close0 = rates[0].close;
   double high0 = rates[0].high;
   double low0 = rates[0].low;
   double body = MathAbs(open0 - close0);
   double totalSize = high0 - low0;

   if(s.breakoutDirection == 1)
   {
      if(close0 > open0 && body > totalSize * 0.6)
         return true;

      if(close0 > open0 && (close0 - open0) > (high0 - close0) * 3 && (open0 - low0) > (close0 - open0) * 2)
         return true;
   }
   else if(s.breakoutDirection == -1)
   {
      if(close0 < open0 && body > totalSize * 0.6)
         return true;

      if(close0 < open0 && (open0 - close0) > (open0 - high0) * 3 && (low0 - close0) > (open0 - close0) * 2)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Verificar si hay pullback para entrada (usa precio en vivo, no    |
//| espera a que cierre una vela: el retroceso hay que cazarlo ya)    |
//+------------------------------------------------------------------+
bool IsPullback(SessionState &s)
{
   if(!UsePullbackEntry)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, 1, rates);

   if(copied != 1)
   {
      Print("[", s.name, "] Error al obtener datos de precio. Error=", GetLastError());
      return false;
   }

   double close0 = rates[0].close;

   if(s.breakoutDirection == 1)
   {
      double pullbackLevel = s.rangeHigh + (close0 - s.rangeHigh) * (1 - PullbackPercent/100);
      return (close0 <= pullbackLevel && close0 > s.rangeHigh);
   }
   else if(s.breakoutDirection == -1)
   {
      double pullbackLevel = s.rangeLow - (s.rangeLow - close0) * (1 - PullbackPercent/100);
      return (close0 >= pullbackLevel && close0 < s.rangeLow);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Entrar en operación para un ciclo                                |
//+------------------------------------------------------------------+
void EnterTrade(SessionState &s)
{
   // Límite de operaciones diarias, compartido por ambos ciclos
   if(MaxDailyTrades > 0 && dailyTradesCount >= MaxDailyTrades)
   {
      Print("[", s.name, "] Límite de operaciones diarias alcanzado (", dailyTradesCount, "/", MaxDailyTrades,
            "). No se abrirán más operaciones hoy.");
      return;
   }

   // Filtro de spread
   if(MaxSpreadPoints > 0)
   {
      long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(currentSpread > MaxSpreadPoints)
      {
         Print("[", s.name, "] Spread demasiado alto (", currentSpread, " puntos > ", MaxSpreadPoints, "). No se abre operación.");
         return;
      }
   }

   bool enterTrade = false;

   if(UsePullbackEntry && IsPullback(s))
   {
      enterTrade = true;
      Print("[", s.name, "] Entrada en pullback");
   }
   else if(UseContinuationEntry && IsValidCandlePattern(s))
   {
      enterTrade = true;
      Print("[", s.name, "] Entrada en continuación");
   }

   if(!enterTrade)
   {
      if(DebugLogs)
         Print("[DEBUG][", s.name, "] Breakout confirmado (dirección=", s.breakoutDirection,
               ") pero ni pullback ni patrón de vela válidos todavía. Esperando siguiente vela.");
      return;
   }

   double stopLossLevel = 0, takeProfitLevel1 = 0, takeProfitLevel2 = 0;

   if(s.breakoutDirection == 1) // Compra
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(UseRangeForSLTP)
      {
         stopLossLevel = s.rangeLow;
         takeProfitLevel1 = s.rangeHigh + s.rangeSize;
         takeProfitLevel2 = s.rangeHigh + s.rangeSize * 2;
      }
      else
      {
         stopLossLevel = entryPrice - StopLossUSD;
         takeProfitLevel1 = entryPrice + TakeProfit1USD;
         takeProfitLevel2 = entryPrice + TakeProfit2USD;
      }
   }
   else if(s.breakoutDirection == -1) // Venta
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(UseRangeForSLTP)
      {
         stopLossLevel = s.rangeHigh;
         takeProfitLevel1 = s.rangeLow - s.rangeSize;
         takeProfitLevel2 = s.rangeLow - s.rangeSize * 2;
      }
      else
      {
         stopLossLevel = entryPrice + StopLossUSD;
         takeProfitLevel1 = entryPrice - TakeProfit1USD;
         takeProfitLevel2 = entryPrice - TakeProfit2USD;
      }
   }
   else
   {
      return; // No hay dirección de breakout válida
   }

   // Calcular tamaño de posición basado en riesgo
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * RiskPercent / 100;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue * _Point / tickSize;

   double entryPrice = (s.breakoutDirection == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLossDistance = MathAbs(entryPrice - stopLossLevel) / _Point;

   double lotSize = NormalizeDouble(riskAmount / (stopLossDistance * pointValue), 2);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;

   // Usar el magic number del ciclo correspondiente
   trade.SetExpertMagicNumber(s.magicNumber);

   bool success = false;
   string tradeComment = "XAUUSD " + s.name + " BO";

   if(s.breakoutDirection == 1) // Compra
   {
      if(UseTP1 || UseTP2)
         success = trade.Buy(lotSize, _Symbol, 0, stopLossLevel, 0, tradeComment);
      else
         success = trade.Buy(lotSize, _Symbol, 0, stopLossLevel, takeProfitLevel1, tradeComment);
   }
   else if(s.breakoutDirection == -1) // Venta
   {
      if(UseTP1 || UseTP2)
         success = trade.Sell(lotSize, _Symbol, 0, stopLossLevel, 0, tradeComment);
      else
         success = trade.Sell(lotSize, _Symbol, 0, stopLossLevel, takeProfitLevel1, tradeComment);
   }

   if(success)
   {
      Print("[", s.name, "] Orden abierta con éxito. Ticket=", trade.ResultOrder());
      s.ticket = trade.ResultOrder();
      s.inTrade = true;

      dailyTradesCount++;
      Print("Operaciones realizadas hoy (ambos ciclos): ", dailyTradesCount, "/", MaxDailyTrades);

      if(UseTP1 || UseTP2)
         SetPartialTakeProfits(s.ticket, takeProfitLevel1, takeProfitLevel2);
   }
   else
   {
      Print("[", s.name, "] Error al abrir orden: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Establecer TP inicial (genérico, no depende del ciclo)            |
//+------------------------------------------------------------------+
void SetPartialTakeProfits(ulong ticket, double tp1Level, double tp2Level)
{
   CPositionInfo position;
   if(!position.SelectByTicket(ticket))
   {
      Print("Error: No se pudo seleccionar la posición. Ticket=", ticket);
      return;
   }

   if(UseTP1)
   {
      if(!UseTP2)
      {
         trade.PositionModify(ticket, position.StopLoss(), tp1Level);
         Print("Take Profit 1 establecido en ", tp1Level);
      }
      else
      {
         trade.PositionModify(ticket, position.StopLoss(), tp1Level);
         Print("Take Profit 1 establecido en ", tp1Level, " - TP2 será gestionado manualmente");
      }
   }
   else if(UseTP2)
   {
      trade.PositionModify(ticket, position.StopLoss(), tp2Level);
      Print("Take Profit 2 establecido en ", tp2Level);
   }
}

//+------------------------------------------------------------------+
//| Gestionar operación abierta de un ciclo                          |
//+------------------------------------------------------------------+
void ManageTrade(SessionState &s)
{
   CPositionInfo position;
   bool foundOpenTrade = false;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == s.magicNumber)
         {
            foundOpenTrade = true;
            break;
         }
      }
   }

   if(!foundOpenTrade)
   {
      s.inTrade = false;
      return;
   }

   if(position.SelectByTicket(s.ticket))
   {
      double openPrice = position.PriceOpen();
      double currentPrice = position.PriceCurrent();
      double stopLoss = position.StopLoss();

      // Mover SL a breakeven después del porcentaje configurado hacia TP1
      if(UseBreakEven)
      {
         double takeProfitLevel1 = 0;

         if(position.PositionType() == POSITION_TYPE_BUY)
         {
            if(UseRangeForSLTP)
               takeProfitLevel1 = s.rangeHigh + s.rangeSize;
            else
               takeProfitLevel1 = openPrice + TakeProfit1USD;

            double targetMove = (takeProfitLevel1 - openPrice) * (BreakEvenPercent / 100.0);
            if(currentPrice >= openPrice + targetMove && stopLoss < openPrice)
            {
               trade.PositionModify(position.Ticket(), openPrice + BreakEvenBufferUSD, position.TakeProfit());
               Print("[", s.name, "] Stop loss movido a breakeven");
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL)
         {
            if(UseRangeForSLTP)
               takeProfitLevel1 = s.rangeLow - s.rangeSize;
            else
               takeProfitLevel1 = openPrice - TakeProfit1USD;

            double targetMove = (openPrice - takeProfitLevel1) * (BreakEvenPercent / 100.0);
            if(currentPrice <= openPrice - targetMove && stopLoss > openPrice)
            {
               trade.PositionModify(position.Ticket(), openPrice - BreakEvenBufferUSD, position.TakeProfit());
               Print("[", s.name, "] Stop loss movido a breakeven");
            }
         }
      }

      // Gestión manual de cierre parcial en TP1 si estamos usando TP1 y TP2
      if(UseTP1 && UseTP2)
      {
         double tp1Level = 0, tp2Level = 0;

         if(position.PositionType() == POSITION_TYPE_BUY)
         {
            if(UseRangeForSLTP)
            {
               tp1Level = s.rangeHigh + s.rangeSize;
               tp2Level = s.rangeHigh + s.rangeSize * 2;
            }
            else
            {
               tp1Level = openPrice + TakeProfit1USD;
               tp2Level = openPrice + TakeProfit2USD;
            }

            if(currentPrice >= tp1Level && position.TakeProfit() != tp2Level)
            {
               double closeVolume = NormalizeDouble(position.Volume() * TP1Percent / 100, 2);
               if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
               {
                  if(trade.PositionClosePartial(position.Ticket(), closeVolume, 0))
                  {
                     Print("[", s.name, "] Cierre parcial en TP1: ", closeVolume, " lotes");
                     if(position.SelectByTicket(position.Ticket()))
                     {
                        trade.PositionModify(position.Ticket(), position.StopLoss(), tp2Level);
                        Print("[", s.name, "] TP modificado a TP2: ", tp2Level);
                     }
                  }
               }
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL)
         {
            if(UseRangeForSLTP)
            {
               tp1Level = s.rangeLow - s.rangeSize;
               tp2Level = s.rangeLow - s.rangeSize * 2;
            }
            else
            {
               tp1Level = openPrice - TakeProfit1USD;
               tp2Level = openPrice - TakeProfit2USD;
            }

            if(currentPrice <= tp1Level && position.TakeProfit() != tp2Level)
            {
               double closeVolume = NormalizeDouble(position.Volume() * TP1Percent / 100, 2);
               if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
               {
                  if(trade.PositionClosePartial(position.Ticket(), closeVolume, 0))
                  {
                     Print("[", s.name, "] Cierre parcial en TP1: ", closeVolume, " lotes");
                     if(position.SelectByTicket(position.Ticket()))
                     {
                        trade.PositionModify(position.Ticket(), position.StopLoss(), tp2Level);
                        Print("[", s.name, "] TP modificado a TP2: ", tp2Level);
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Convertir código de error a descripción                          |
//+------------------------------------------------------------------+
string GetErrorDescription(int error_code)
{
   string error_string;

   switch(error_code)
   {
      case TRADE_RETCODE_REQUOTE:
         error_string = "Requote";
         break;
      case TRADE_RETCODE_REJECT:
         error_string = "Solicitud rechazada";
         break;
      case TRADE_RETCODE_CANCEL:
         error_string = "Solicitud cancelada por el trader";
         break;
      case TRADE_RETCODE_TIMEOUT:
         error_string = "Solicitud cancelada por tiempo de espera expirado";
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         error_string = "Volumen inválido en la solicitud";
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         error_string = "Precio inválido en la solicitud";
         break;
      case TRADE_RETCODE_INVALID_STOPS:
         error_string = "Stops inválidos en la solicitud";
         break;
      case TRADE_RETCODE_TRADE_DISABLED:
         error_string = "Trading deshabilitado";
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         error_string = "Mercado cerrado";
         break;
      case TRADE_RETCODE_NO_MONEY:
         error_string = "Fondos insuficientes";
         break;
      case TRADE_RETCODE_PRICE_CHANGED:
         error_string = "Precio cambiado";
         break;
      case TRADE_RETCODE_PRICE_OFF:
         error_string = "Cotizaciones no disponibles";
         break;
      case TRADE_RETCODE_INVALID_EXPIRATION:
         error_string = "Fecha de expiración inválida";
         break;
      case TRADE_RETCODE_ORDER_CHANGED:
         error_string = "Estado de la orden cambiado";
         break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         error_string = "Demasiadas solicitudes";
         break;
      case TRADE_RETCODE_NO_CHANGES:
         error_string = "Sin cambios en la solicitud";
         break;
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         error_string = "Autotrading deshabilitado por el servidor";
         break;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         error_string = "Autotrading deshabilitado por el cliente";
         break;
      case TRADE_RETCODE_LOCKED:
         error_string = "Solicitud bloqueada para procesamiento";
         break;
      case TRADE_RETCODE_LIMIT_ORDERS:
         error_string = "Límite de órdenes alcanzado";
         break;
      default:
         error_string = "Error desconocido";
   }

   return error_string;
}
