# TripleMACrossPropFutures — NinjaTrader 8 (NinjaScript / C#)

Estrategia mecánica de **triple cruce de medias móviles** con gestión de riesgo pensada para
cuentas de **fondeo de futuros** (Apex Trader Funding, Bulenox y firmas con reglas de
*trailing threshold drawdown*), operando **intradía** en futuros de índice (MNQ/NQ, MYM/YM,
MES/ES, etc.) desde NinjaTrader 8.

## ⚠️ Antes de usarla en real — léelo primero

1. **No se ha ejecutado ningún backtest.** Este entorno de desarrollo no tiene NinjaTrader
   instalado ni acceso a datos históricos de futuros, así que no puedo generarte winrate,
   profit factor, drawdown máximo ni ratio riesgo-beneficio reales — cualquier número que te
   diera aquí sería inventado. Debes importar el código en tu propia instalación de
   NinjaTrader 8 y correrlo en el **Strategy Analyzer** (o en Sim101 en tiempo real) para
   obtener esas métricas antes de arriesgar una cuenta de evaluación.
2. **Verifica las reglas exactas de tu cuenta** contra el panel de tu prop firm: tamaño de
   cuenta, Max Trailing Drawdown en $, si el trailing es *end-of-day* o *intradía real*, si
   existe regla de consistencia y su %, y el número máximo de contratos permitido para tu
   fase/tamaño de cuenta. Los valores por defecto del código son una aproximación típica de
   una cuenta de 50K de Apex/Bulenox a la fecha de este documento, no un dato garantizado.
3. El cálculo interno de equity/drawdown de esta estrategia es una **aproximación**: usa el
   `SystemPerformance` de NinjaTrader (P&L de las operaciones ejecutadas por esta instancia).
   El cálculo oficial de tu prop firm lo hace **su** broker/plataforma y puede diferir por
   comisiones, slippage, horario de servidor o si operas manualmente en paralelo. Los
   kill-switches de este código son una **ayuda de gestión de riesgo, no una garantía**.
4. Prueba siempre primero en cuenta SIM antes de conectar a la cuenta de evaluación/fondeada.

## Parámetros usados (resumen)

| Sección | Parámetro | Valor por defecto | Fuente / nota |
|---|---|---|---|
| Contexto cuenta | Plataforma | NinjaTrader 8 (NinjaScript C#) | confirmado por ti |
| Contexto cuenta | Prop firm | Apex Trader Funding / Bulenox | confirmado por ti |
| Contexto cuenta | Capital de cuenta | $50,000 | confirmado por ti |
| Contexto cuenta | Instrumento | MNQ/NQ (Nasdaq-100 futuro) | confirmado por ti (elige el contrato exacto en NinjaTrader) |
| Contexto cuenta | Temporalidad | Intradía | confirmado por ti — **falta confirmar el timeframe exacto de entrada** (ver abajo) |
| Contexto cuenta | Drawdown máx. (Max Trailing DD) | **$2,500** | **asumido** — típico en cuenta 50K Apex/Bulenox, verifica tu contrato |
| Contexto cuenta | Modo de trailing | End-of-day (EOD) | **asumido** — estilo Apex/Bulenox; cambia a "RealTimeIntraday" si tu firm lo calcula tick a tick (estilo Topstep) |
| Contexto cuenta | Regla de consistencia | 30% máx. de un día sobre el total | **asumido** — verifica si tu firm la exige en tu fase actual |
| Medias móviles | Tipo | EMA | por defecto, configurable a SMA |
| Medias móviles | Rápida / Media / Lenta | 8 / 21 / 50 | valores estándar sugeridos en tu prompt |
| Medias móviles | Antigüedad máx. de la señal | 3 velas | evita entradas tardías |
| Filtros | Separación mínima medias | 10 ticks | evita mercado lateral/plano |
| Filtros | ATR mínimo | 14 periodos, 15 ticks | evita operar con volatilidad insuficiente |
| Horario | Entradas permitidas | 09:45–15:30 (hora del gráfico / NY) | **asumido**, ajusta a tu zona horaria de datos |
| Horario | Cierre forzado | 15:55 | antes del cierre de sesión regular (16:00 ET); nunca overnight ni fin de semana |
| Riesgo | Riesgo por operación | 0.5% del capital inicial | valor conservador típico de cuenta de fondeo |
| Riesgo | Stop Loss | 1.5 × ATR(14) | método por volatilidad, evita SL fijo en mercados con distinto rango |
| Riesgo | Ratio Riesgo:Beneficio | 1:2 | configurable (`RewardRiskRatio`) |
| Riesgo | Contratos máximos | **1 contrato fijo** | confirmado por ti |
| Riesgo | Kill-switch diario | 1% del capital inicial | autoimpuesto (más estricto que la firm), configurable |
| Riesgo | Kill-switch total | Max Trailing DD ($2,500) | detiene la estrategia por completo el resto de la corrida |

**Dato pendiente de confirmar:** dijiste "intradía" pero no el timeframe exacto de las velas de
entrada (M1, M5, M15…). Dejé el código listo para cualquier timeframe del gráfico donde lo
apliques — con NQ/MNQ intradía, M5 o M15 son los más comunes para un triple cruce de medias sin
exceso de ruido; **por defecto asumo que lo aplicarás en un gráfico de 15 minutos**, pero
selecciona el timeframe en NinjaTrader al añadir la estrategia al gráfico (el código no fija el
periodo del gráfico, solo los periodos de las medias sobre esas velas). Si querías otro
timeframe o quieres que ajuste `FastPeriod`/`MediumPeriod`/`SlowPeriod` para M1 o M5, dímelo y
lo recalibro.

## Instalación en NinjaTrader 8

1. Abre NinjaTrader 8 → **Tools → Edit NinjaScript → Strategy... → New**, o simplemente copia
   `TripleMACrossPropFutures.cs` a tu carpeta
   `Documents\NinjaTrader 8\bin\Custom\Strategies\`.
2. En el NinjaScript Editor: **Compile** (F5). Corrige cualquier diferencia de API si tu
   versión de NinjaTrader difiere (el código está escrito para NinjaTrader 8, .NET/C#
   estándar del NinjaScript Editor).
3. Abre el **Strategy Analyzer**, selecciona `TripleMACrossPropFutures`, elige el instrumento
   (ej. `MNQ 12-26`), el periodo de velas (ej. 15 minutos) y un rango histórico representativo
   (mínimo varios meses, incluyendo distintos regímenes de mercado).
4. Ajusta los parámetros en el panel de propiedades si tu prop firm difiere del Apex/Bulenox
   50K asumido (Max Trailing Drawdown, modo de trailing, regla de consistencia, contratos
   máximos, horario de sesión según tu zona horaria de datos).
5. Ejecuta el backtest y revisa el reporte de **Strategy Analyzer** (Trade Performance,
   Drawdown, Profit Factor, Win %, etc.) — ese es el reporte real que debes usar para validar
   la estrategia antes de tocar una cuenta de evaluación.
6. Antes de ir a real: fuerza test en **Sim101** en tiempo real durante al menos varias
   semanas para verificar ejecución, slippage y que los kill-switches se comportan como
   esperas en condiciones de mercado en vivo.

## Qué valida (y qué NO valida) el kill-switch de esta estrategia

- ✅ Detiene nuevas entradas si la pérdida del día alcanza el % configurado.
- ✅ Cierra posiciones y detiene la estrategia por completo si el equity cae al piso del
  trailing drawdown configurado.
- ✅ Fuerza el cierre de toda posición a la hora configurada (no overnight, no fin de semana).
- ✅ Avisa (log) si el profit de un día supera el % de consistencia configurado y deja de
  abrir nuevas operaciones ese día.
- ❌ **No** puede impedir que el drawdown oficial de tu prop firm se calcule distinto (otro
  broker/feed, comisiones, o el momento exacto de corte del "día de trading" de la firm).
- ❌ **No** sustituye la verificación manual de las reglas de tu cuenta ni un backtest real
  ejecutado en tu propia instalación de NinjaTrader.

## Estructura del código

- Triple cruce (`Fast/Medium/Slow`) con filtro de "antigüedad de la señal" (`MaxCrossAgeBars`)
  y filtro de separación mínima entre medias para evitar mercado lateral.
- Filtro ATR opcional para exigir volatilidad mínima antes de operar.
- Ventana horaria de entradas + cierre forzado por hora, independiente de los kill-switches.
- Módulo de riesgo: SL por ATR, contratos calculados según `% riesgo / distancia de SL en $`,
  capado al máximo de contratos configurado (1 por defecto) — si el riesgo con 1 solo
  contrato ya excede el % configurado, la señal se descarta en vez de sobre-arriesgar.
- TP fijado como múltiplo del SL según el ratio riesgo:beneficio configurado.
- Kill-switch diario y kill-switch total (trailing drawdown, con opción de "congelar" el
  trailing al estilo Apex una vez se alcanza capital inicial + Max Trailing DD).
- Regla de consistencia opcional (log + bloqueo de nuevas entradas el resto del día).
