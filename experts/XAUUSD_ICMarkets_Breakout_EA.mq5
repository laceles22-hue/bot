//+------------------------------------------------------------------+
//|      XAUUSD (Oro) - Breakout de Rango Asiático + Gestión Activa   |
//|         Reformulado para operar XAUUSD en MT5 - Broker IC Markets |
//|                                                                    |
//|  Adaptado a partir de una versión original para GBP/JPY. Cambios  |
//|  clave respecto al original:                                      |
//|   - SL/TP fijos expresados en USD (precio directo), no en "pips"  |
//|     multiplicados por 10 (esa convención es de forex, no de oro). |
//|   - Tamaño mínimo de rango en USD, configurable (antes 30 pips    |
//|     fijos pensados para GBP/JPY).                                 |
//|   - Horario de rango definido en UTC + offset del servidor de     |
//|     IC Markets (GMT+2 en invierno / GMT+3 en verano-DST), porque  |
//|     TimeCurrent() devuelve la hora del servidor, no UTC.          |
//|   - Verificación de que el símbolo del gráfico es de Oro (XAU) y  |
//|     que está seleccionado en Market Watch.                        |
//|   - Filtro opcional de spread máximo (el oro puede tener spreads  |
//|     variables, especialmente fuera de sesión de Londres/NY).      |
//|   - El cálculo de lotaje por riesgo ya usaba TICK_VALUE/TICK_SIZE |
//|     de forma genérica, por lo que funciona igual de bien en oro.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>

// Crear objeto para operaciones de trading
CTrade trade;

// Parámetros de entrada
input string   TimeSettings      = "===== Configuración de Tiempo (hora UTC) =====";
input int      RangeStartHourUTC = 0;     // Hora inicio rango (UTC) - sesión asiática
input int      RangeStartMin     = 0;     // Minuto inicio rango
input int      RangeEndHourUTC   = 7;     // Hora fin rango (UTC) - antes de apertura de Londres
input int      RangeEndMin       = 0;     // Minuto fin rango
input int      BrokerGMTOffset   = 3;     // Offset servidor IC Markets vs UTC (2=invierno EET, 3=verano/DST). Verifica el reloj del terminal contra la hora UTC real.

input string   SymbolSettings    = "===== Configuración de Símbolo =====";
input bool     ValidateGoldSymbol = true;  // Verificar que el gráfico esté en un símbolo de Oro (XAU/GOLD)

input string   TradeSettings     = "===== Configuración de Trading =====";
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
input double   MinRangeUSD       = 3.0;   // Tamaño mínimo del rango para operar (USD)

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
input int      MaxDailyTrades    = 3;     // Máximo de operaciones por día (0 = sin límite)

// Variables globales
datetime lastRangeDay = 0;
double rangeHigh = 0;
double rangeLow = 0;
double rangeSize = 0;
bool rangeIdentified = false;
bool breakoutDetected = false;
bool secondCloseConfirmed = false;
int breakoutDirection = 0; // 1 para arriba, -1 para abajo
datetime breakoutTime = 0;
ulong breakoutTicket = 0;
bool inTrade = false;
int magicNumber = 55010;

// Horario de rango ya convertido a hora de servidor (UTC + BrokerGMTOffset)
int g_rangeStartHour = 0;
int g_rangeStartMin  = 0;
int g_rangeEndHour   = 0;
int g_rangeEndMin    = 0;

// Variables para control de operaciones diarias
datetime currentDay = 0;
int dailyTradesCount = 0;

// Manejadores para indicadores
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

   // Convertir el horario de rango (UTC) a hora de servidor de IC Markets
   g_rangeStartHour = (RangeStartHourUTC + BrokerGMTOffset + 24) % 24;
   g_rangeStartMin  = RangeStartMin;
   g_rangeEndHour   = (RangeEndHourUTC + BrokerGMTOffset + 24) % 24;
   g_rangeEndMin    = RangeEndMin;

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

   // Configurar el objeto de trading
   trade.SetExpertMagicNumber(magicNumber);

   Print("XAUUSD Breakout EA (IC Markets) inicializado. Símbolo=", _Symbol,
         " Digits=", _Digits, " Point=", _Point,
         " Spread actual=", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), " puntos",
         " | Rango en hora servidor: ", g_rangeStartHour, ":", g_rangeStartMin,
         " - ", g_rangeEndHour, ":", g_rangeEndMin);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar los manejadores de indicadores
   if(UseBB && bbHandle != INVALID_HANDLE)
      IndicatorRelease(bbHandle);

   Print("XAUUSD Breakout EA (IC Markets) desactivado");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Chequear si es un nuevo día de trading
   if(IsNewTradingDay())
   {
      rangeIdentified = false;
      breakoutDetected = false;
      secondCloseConfirmed = false;
      breakoutDirection = 0;
      breakoutTime = 0;
   }

   // 1. Identificar el rango asiático
   if(!rangeIdentified)
   {
      IdentifyAsianRange();
   }

   // 2. Detectar breakout con vela de impulso
   if(rangeIdentified && !breakoutDetected)
   {
      DetectBreakout();
   }

   // 3. Confirmar con segundo cierre fuera del rango
   if(breakoutDetected && !secondCloseConfirmed)
   {
      ConfirmBreakout();
   }

   // 4. Entrada en pullback o continuación
   if(secondCloseConfirmed && !inTrade)
   {
      EnterTrade();
   }

   // 5. Gestión de operaciones abiertas
   if(inTrade)
   {
      ManageTrade();
   }
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
      lastRangeDay = todayDate;
      currentDay = todayDate;
      dailyTradesCount = 0; // Resetear contador de operaciones
      Print("Nuevo día de trading. Contador de operaciones reseteado.");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Identificar el rango asiático (definido en UTC, convertido a     |
//| hora de servidor de IC Markets)                                  |
//+------------------------------------------------------------------+
void IdentifyAsianRange()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);

   // Verificar si ya pasó el periodo de rango (comparación correcta en minutos totales)
   int curTotalMin = currentTime.hour * 60 + currentTime.min;
   int endTotalMin = g_rangeEndHour * 60 + g_rangeEndMin;

   if(curTotalMin >= endTotalMin)
   {
      // Calcular timestamps para el inicio y fin del rango (hora de servidor)
      MqlDateTime rangeStart, rangeEnd;
      TimeToStruct(TimeCurrent(), rangeStart);
      TimeToStruct(TimeCurrent(), rangeEnd);

      rangeStart.hour = g_rangeStartHour;
      rangeStart.min = g_rangeStartMin;
      rangeStart.sec = 0;

      rangeEnd.hour = g_rangeEndHour;
      rangeEnd.min = g_rangeEndMin;
      rangeEnd.sec = 0;

      datetime rangeStartTime = StructToTime(rangeStart);
      datetime rangeEndTime = StructToTime(rangeEnd);

      // Si el fin de rango cae "antes" que el inicio (cruce de medianoche por el offset), ajustar
      if(rangeEndTime < rangeStartTime)
      {
         rangeEndTime += 86400; // Añadir un día
      }

      // Encontrar máximo y mínimo durante el periodo de rango
      rangeHigh = 0;
      rangeLow = 999999;

      // Obtener datos de las velas
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      int copied = CopyRates(_Symbol, _Period, rangeStartTime, rangeEndTime, rates);

      if(copied > 0)
      {
         for(int i = 0; i < copied; i++)
         {
            if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
            if(rates[i].low < rangeLow) rangeLow = rates[i].low;
         }

         rangeSize = rangeHigh - rangeLow;

         // Validar que el rango es significativo (en USD, el oro se mueve mucho más que un par de forex)
         if(rangeSize >= MinRangeUSD)
         {
            rangeIdentified = true;
            Print("Rango asiático identificado: Alto=", rangeHigh, " Bajo=", rangeLow,
                  " Tamaño=", DoubleToString(rangeSize, 2), " USD");
         }
         else
         {
            Print("Rango demasiado pequeño (", DoubleToString(rangeSize, 2),
                  " USD < ", DoubleToString(MinRangeUSD, 2), " USD), no se operará hoy");
         }
      }
      else
      {
         Print("Error al obtener datos de precio. Error=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout con vela de impulso                            |
//+------------------------------------------------------------------+
void DetectBreakout()
{
   // Verificar que tenemos un rango válido
   if(!rangeIdentified || rangeSize <= 0)
      return;

   // Obtener datos de las últimas velas
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, 2, rates);

   if(copied != 2)
   {
      Print("Error al obtener datos de precio. Error=", GetLastError());
      return;
   }

   double close0 = rates[0].close;
   double close1 = rates[1].close;
   double open0 = rates[0].open;
   double open1 = rates[1].open;
   double high0 = rates[0].high;
   double low0 = rates[0].low;

   // Calcular tamaño de las velas
   double candleSize0 = MathAbs(close0 - open0);
   double candleSize1 = MathAbs(close1 - open1);

   // Verificar Bandas Bollinger para validación si están activadas
   bool bbCondition = true; // Por defecto, pasamos la condición si no usamos BB

   if(UseBB)
   {
      double upperBand[], lowerBand[], middleBand[];
      ArraySetAsSeries(upperBand, true);
      ArraySetAsSeries(lowerBand, true);
      ArraySetAsSeries(middleBand, true);

      // Copiar datos de bandas de Bollinger
      bool bbCopied = CopyBuffer(bbHandle, 1, 0, 1, upperBand) > 0 &&
                     CopyBuffer(bbHandle, 2, 0, 1, lowerBand) > 0;

      if(!bbCopied)
      {
         Print("Error al obtener datos de Bandas de Bollinger. Error=", GetLastError());
         return;
      }

      // Revisar breakout alcista con validación BB
      if(close0 > rangeHigh)
         bbCondition = (high0 >= upperBand[0]);
      // Revisar breakout bajista con validación BB
      else if(close0 < rangeLow)
         bbCondition = (low0 <= lowerBand[0]);
   }

   // Revisar breakout alcista
   if(close0 > rangeHigh && candleSize0 > rangeSize * 0.15) // Vela de impulso (al menos 15% del rango)
   {
      // Validación con bandas de Bollinger (si están activadas)
      if(bbCondition)
      {
         // Validación opcional con volumen
         if(!UseVolume || IsVolumeIncreased())
         {
            breakoutDetected = true;
            breakoutDirection = 1; // Alcista
            breakoutTime = rates[0].time;
            Print("Breakout alcista detectado");
         }
      }
   }
   // Revisar breakout bajista
   else if(close0 < rangeLow && candleSize0 > rangeSize * 0.15)
   {
      // Validación con bandas de Bollinger (si están activadas)
      if(bbCondition)
      {
         // Validación opcional con volumen
         if(!UseVolume || IsVolumeIncreased())
         {
            breakoutDetected = true;
            breakoutDirection = -1; // Bajista
            breakoutTime = rates[0].time;
            Print("Breakout bajista detectado");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar si el volumen ha aumentado significativamente          |
//+------------------------------------------------------------------+
bool IsVolumeIncreased()
{
   if(!UseVolume)
      return true;

   // Obtener datos de volumen (tick volume, ya que XAUUSD es un CFD sin volumen real)
   long volume[];
   ArraySetAsSeries(volume, true);
   int copied = CopyTickVolume(_Symbol, _Period, 0, 6, volume);

   if(copied != 6)
   {
      Print("Error al obtener datos de volumen. Error=", GetLastError());
      return false;
   }

   long volumeNow = volume[0];

   // Calcular volumen promedio de las últimas 5 velas
   double avgVolume = 0;
   for(int i = 1; i <= 5; i++)
   {
      avgVolume += (double)volume[i];
   }
   avgVolume /= 5;

   // Verificar si el volumen actual supera el promedio por el factor mínimo
   return ((double)volumeNow >= avgVolume * MinVolumeIncrease);
}

//+------------------------------------------------------------------+
//| Confirmar con segundo cierre fuera del rango                      |
//+------------------------------------------------------------------+
void ConfirmBreakout()
{
   if(!breakoutDetected)
      return;

   // Obtener datos de la última vela
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, 1, rates);

   if(copied != 1)
   {
      Print("Error al obtener datos de precio. Error=", GetLastError());
      return;
   }

   double close0 = rates[0].close;

   // Confirmar breakout alcista
   if(breakoutDirection == 1 && close0 > rangeHigh)
   {
      secondCloseConfirmed = true;
      Print("Breakout alcista confirmado con segundo cierre");
   }
   // Confirmar breakout bajista
   else if(breakoutDirection == -1 && close0 < rangeLow)
   {
      secondCloseConfirmed = true;
      Print("Breakout bajista confirmado con segundo cierre");
   }
}

//+------------------------------------------------------------------+
//| Analizar patrón de vela para entrada                             |
//+------------------------------------------------------------------+
bool IsValidCandlePattern()
{
   // Obtener datos de las últimas velas
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, 1, rates);

   if(copied != 1)
   {
      Print("Error al obtener datos de precio. Error=", GetLastError());
      return false;
   }

   double open0 = rates[0].open;
   double close0 = rates[0].close;
   double high0 = rates[0].high;
   double low0 = rates[0].low;
   double body = MathAbs(open0 - close0);
   double totalSize = high0 - low0;

   // Para entradas en breakout alcista
   if(breakoutDirection == 1)
   {
      // Vela alcista con cuerpo fuerte (más del 60% del tamaño total)
      if(close0 > open0 && body > totalSize * 0.6)
         return true;

      // Patrón de martillo en soporte
      if(close0 > open0 && (close0 - open0) > (high0 - close0) * 3 && (open0 - low0) > (close0 - open0) * 2)
         return true;
   }
   // Para entradas en breakout bajista
   else if(breakoutDirection == -1)
   {
      // Vela bajista con cuerpo fuerte (más del 60% del tamaño total)
      if(close0 < open0 && body > totalSize * 0.6)
         return true;

      // Patrón de martillo invertido en resistencia
      if(close0 < open0 && (open0 - close0) > (open0 - high0) * 3 && (low0 - close0) > (open0 - close0) * 2)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Verificar si hay pullback para entrada                           |
//+------------------------------------------------------------------+
bool IsPullback()
{
   if(!UsePullbackEntry)
      return false;

   // Obtener datos de la última vela
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, 1, rates);

   if(copied != 1)
   {
      Print("Error al obtener datos de precio. Error=", GetLastError());
      return false;
   }

   double close0 = rates[0].close;

   // Para breakout alcista
   if(breakoutDirection == 1)
   {
      // Verificar si el precio ha retrocedido el porcentaje indicado desde el breakout
      double pullbackLevel = rangeHigh + (close0 - rangeHigh) * (1 - PullbackPercent/100);
      return (close0 <= pullbackLevel && close0 > rangeHigh);
   }
   // Para breakout bajista
   else if(breakoutDirection == -1)
   {
      // Verificar si el precio ha retrocedido el porcentaje indicado desde el breakout
      double pullbackLevel = rangeLow - (rangeLow - close0) * (1 - PullbackPercent/100);
      return (close0 >= pullbackLevel && close0 < rangeLow);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Entrar en operación                                              |
//+------------------------------------------------------------------+
void EnterTrade()
{
   // Verificar límite de operaciones diarias
   if(MaxDailyTrades > 0 && dailyTradesCount >= MaxDailyTrades)
   {
      Print("Límite de operaciones diarias alcanzado (", dailyTradesCount, "/", MaxDailyTrades, "). No se abrirán más operaciones hoy.");
      return;
   }

   // Filtro de spread (el oro en IC Markets puede ensanchar el spread fuera de Londres/NY)
   if(MaxSpreadPoints > 0)
   {
      long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(currentSpread > MaxSpreadPoints)
      {
         Print("Spread demasiado alto (", currentSpread, " puntos > ", MaxSpreadPoints, "). No se abre operación.");
         return;
      }
   }

   // Verificar condiciones de entrada
   bool enterTrade = false;

   // Entrada en pullback
   if(UsePullbackEntry && IsPullback())
   {
      enterTrade = true;
      Print("Entrada en pullback");
   }
   // Entrada en continuación
   else if(UseContinuationEntry && IsValidCandlePattern())
   {
      enterTrade = true;
      Print("Entrada en continuación");
   }

   if(!enterTrade)
      return;

   // Calcular niveles de stop loss y take profit
   double stopLossLevel = 0, takeProfitLevel1 = 0, takeProfitLevel2 = 0;

   if(breakoutDirection == 1) // Compra
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(UseRangeForSLTP)
      {
         // Usar el rango para calcular SL/TP
         stopLossLevel = rangeLow;
         takeProfitLevel1 = rangeHigh + rangeSize;
         takeProfitLevel2 = rangeHigh + rangeSize * 2;
      }
      else
      {
         // Usar distancia en USD para calcular SL/TP (precio directo, no "pips" de forex)
         stopLossLevel = entryPrice - StopLossUSD;
         takeProfitLevel1 = entryPrice + TakeProfit1USD;
         takeProfitLevel2 = entryPrice + TakeProfit2USD;
      }
   }
   else if(breakoutDirection == -1) // Venta
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(UseRangeForSLTP)
      {
         // Usar el rango para calcular SL/TP
         stopLossLevel = rangeHigh;
         takeProfitLevel1 = rangeLow - rangeSize;
         takeProfitLevel2 = rangeLow - rangeSize * 2;
      }
      else
      {
         // Usar distancia en USD para calcular SL/TP
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

   // Obtener valor de punto (genérico: funciona igual para XAUUSD que para forex)
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue * _Point / tickSize;

   // Calcular distancia al stop loss en puntos
   double entryPrice = (breakoutDirection == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLossDistance = MathAbs(entryPrice - stopLossLevel) / _Point;

   // Calcular lotes basados en riesgo
   double lotSize = NormalizeDouble(riskAmount / (stopLossDistance * pointValue), 2);

   // Limitar tamaño de lotes
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;

   // Configurar objeto de trading
   trade.SetExpertMagicNumber(magicNumber);

   // Abrir operación
   bool success = false;

   if(breakoutDirection == 1) // Compra
   {
      if(UseTP1 || UseTP2)
      {
         // Sin TP en la orden inicial, se gestionarán después
         success = trade.Buy(lotSize, _Symbol, 0, stopLossLevel, 0, "XAUUSD Breakout EA");
      }
      else
      {
         // Con TP1 como TP final
         success = trade.Buy(lotSize, _Symbol, 0, stopLossLevel, takeProfitLevel1, "XAUUSD Breakout EA");
      }
   }
   else if(breakoutDirection == -1) // Venta
   {
      if(UseTP1 || UseTP2)
      {
         // Sin TP en la orden inicial, se gestionarán después
         success = trade.Sell(lotSize, _Symbol, 0, stopLossLevel, 0, "XAUUSD Breakout EA");
      }
      else
      {
         // Con TP1 como TP final
         success = trade.Sell(lotSize, _Symbol, 0, stopLossLevel, takeProfitLevel1, "XAUUSD Breakout EA");
      }
   }

   // Verificar si la orden se ejecutó correctamente
   if(success)
   {
      Print("Orden abierta con éxito. Ticket=", trade.ResultOrder());
      breakoutTicket = trade.ResultOrder();
      inTrade = true;

      // Incrementar contador de operaciones diarias
      dailyTradesCount++;
      Print("Operaciones realizadas hoy: ", dailyTradesCount, "/", MaxDailyTrades);

      // Establecer órdenes parciales de take profit si se usan
      if(UseTP1 || UseTP2)
      {
         SetPartialTakeProfits(breakoutTicket, takeProfitLevel1, takeProfitLevel2);
      }
   }
   else
   {
      Print("Error al abrir orden: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Establecer órdenes parciales de take profit                      |
//+------------------------------------------------------------------+
void SetPartialTakeProfits(ulong ticket, double tp1Level, double tp2Level)
{
   // En lugar de crear órdenes límite, modificamos la posición para incluir los TP
   CPositionInfo position;
   if(!position.SelectByTicket(ticket))
   {
      Print("Error: No se pudo seleccionar la posición. Ticket=", ticket);
      return;
   }

   // Simplemente establecemos el TP en la posición actual
   if(UseTP1)
   {
      // Si solo usamos TP1, lo establecemos directamente
      if(!UseTP2)
      {
         trade.PositionModify(ticket, position.StopLoss(), tp1Level);
         Print("Take Profit 1 establecido en ", tp1Level);
      }
      // Si usamos ambos TPs, establecemos el primero y gestionaremos el segundo manualmente
      else
      {
         trade.PositionModify(ticket, position.StopLoss(), tp1Level);
         Print("Take Profit 1 establecido en ", tp1Level, " - TP2 será gestionado manualmente");
      }
   }
   else if(UseTP2)
   {
      // Si solo usamos TP2
      trade.PositionModify(ticket, position.StopLoss(), tp2Level);
      Print("Take Profit 2 establecido en ", tp2Level);
   }
}

//+------------------------------------------------------------------+
//| Gestionar operación abierta                                      |
//+------------------------------------------------------------------+
void ManageTrade()
{
   // Verificar si aún tenemos una posición abierta
   CPositionInfo position;
   bool foundOpenTrade = false;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == magicNumber)
         {
            foundOpenTrade = true;
            break;
         }
      }
   }

   if(!foundOpenTrade)
   {
      inTrade = false;
      return;
   }

   // Aquí se pueden añadir reglas de gestión activa
   if(position.SelectByTicket(breakoutTicket))
   {
      double openPrice = position.PriceOpen();
      double currentPrice = position.PriceCurrent();
      double stopLoss = position.StopLoss();

      // Mover SL a breakeven después del porcentaje configurado hacia TP1
      if(UseBreakEven)
      {
         double takeProfitLevel1 = 0;

         // Calcular nivel de TP1 según configuración
         if(position.PositionType() == POSITION_TYPE_BUY)
         {
            if(UseRangeForSLTP)
               takeProfitLevel1 = rangeHigh + rangeSize;
            else
               takeProfitLevel1 = openPrice + TakeProfit1USD;

            double targetMove = (takeProfitLevel1 - openPrice) * (BreakEvenPercent / 100.0);
            if(currentPrice >= openPrice + targetMove && stopLoss < openPrice)
            {
               trade.PositionModify(position.Ticket(), openPrice + BreakEvenBufferUSD, position.TakeProfit());
               Print("Stop loss movido a breakeven");
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL)
         {
            if(UseRangeForSLTP)
               takeProfitLevel1 = rangeLow - rangeSize;
            else
               takeProfitLevel1 = openPrice - TakeProfit1USD;

            double targetMove = (openPrice - takeProfitLevel1) * (BreakEvenPercent / 100.0);
            if(currentPrice <= openPrice - targetMove && stopLoss > openPrice)
            {
               trade.PositionModify(position.Ticket(), openPrice - BreakEvenBufferUSD, position.TakeProfit());
               Print("Stop loss movido a breakeven");
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
               tp1Level = rangeHigh + rangeSize;
               tp2Level = rangeHigh + rangeSize * 2;
            }
            else
            {
               tp1Level = openPrice + TakeProfit1USD;
               tp2Level = openPrice + TakeProfit2USD;
            }

            // Si el precio alcanza o supera TP1, cerramos parcialmente
            if(currentPrice >= tp1Level && position.TakeProfit() != tp2Level)
            {
               // Cerrar parte de la posición (TP1Percent)
               double closeVolume = NormalizeDouble(position.Volume() * TP1Percent / 100, 2);
               if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
               {
                  // Cerrar parcialmente y modificar el TP restante a TP2
                  if(trade.PositionClosePartial(position.Ticket(), closeVolume, 0))
                  {
                     Print("Cierre parcial en TP1: ", closeVolume, " lotes");
                     // Modificar TP para el resto de la posición
                     if(position.SelectByTicket(position.Ticket())) // Reseleccionar después del cierre parcial
                     {
                        trade.PositionModify(position.Ticket(), position.StopLoss(), tp2Level);
                        Print("TP modificado a TP2: ", tp2Level);
                     }
                  }
               }
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL)
         {
            if(UseRangeForSLTP)
            {
               tp1Level = rangeLow - rangeSize;
               tp2Level = rangeLow - rangeSize * 2;
            }
            else
            {
               tp1Level = openPrice - TakeProfit1USD;
               tp2Level = openPrice - TakeProfit2USD;
            }

            // Si el precio alcanza o queda por debajo de TP1, cerramos parcialmente
            if(currentPrice <= tp1Level && position.TakeProfit() != tp2Level)
            {
               // Cerrar parte de la posición (TP1Percent)
               double closeVolume = NormalizeDouble(position.Volume() * TP1Percent / 100, 2);
               if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
               {
                  // Cerrar parcialmente y modificar el TP restante a TP2
                  if(trade.PositionClosePartial(position.Ticket(), closeVolume, 0))
                  {
                     Print("Cierre parcial en TP1: ", closeVolume, " lotes");
                     // Modificar TP para el resto de la posición
                     if(position.SelectByTicket(position.Ticket())) // Reseleccionar después del cierre parcial
                     {
                        trade.PositionModify(position.Ticket(), position.StopLoss(), tp2Level);
                        Print("TP modificado a TP2: ", tp2Level);
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
