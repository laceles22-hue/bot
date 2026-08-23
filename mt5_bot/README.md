# FVG_IFVG_Session_EA — Bot de trading para MetaTrader 5

Expert Advisor (MQL5) que porta a un bot operable la lógica del indicador
[`indicators/fvg_ifvg.pine`](../indicators/fvg_ifvg.pine) de este repositorio:
detecta **Fair Value Gaps (FVG)**, sus inversiones (**IFVG**) y los niveles de
liquidez de referencia (**PDH/PDL** y máximos/mínimos de las sesiones de
**Londres** y **Nueva York**), y opera automáticamente cuando se cumplen las
condiciones configuradas.

Funciona sobre cualquier símbolo que tu bróker ofrezca en MT5 —forex,
índices/acciones CFD, futuros CFD, cripto CFD—, ya que la lógica solo usa
datos OHLC estándar. No hay código específico por mercado.

## ⚠️ Antes de usarlo en real

Ninguna estrategia garantiza beneficios y este EA no es una excepción.
**Nunca lo conectes a una cuenta real sin antes:**

1. Compilarlo y probarlo en el **Strategy Tester** de MT5, modo *"Cada tick
   basado en datos reales"*, sobre varios símbolos, timeframes y periodos.
2. Ejecutarlo en **cuenta demo** en tiempo real durante varias semanas.
3. Ajustar los parámetros de riesgo a tu propia tolerancia y al bróker
   concreto (spreads, slippage, horario de servidor).

## Instalación

1. Copia `FVG_IFVG_Session_EA.mq5` a la carpeta `MQL5/Experts/` de tu
   instalación de MetaTrader 5 (`Archivo → Abrir carpeta de datos → MQL5 →
   Experts`).
2. Ábrelo con MetaEditor y compila (`F7`). No tiene dependencias externas
   aparte de la librería estándar `<Trade/Trade.mqh>`.
3. Arrastra el EA sobre el gráfico del símbolo/timeframe donde quieras
   operarlo. Se recomienda **M5–M15** para que la detección de sesiones
   tenga suficiente granularidad.
4. Activa **AutoTrading** en MT5 y marca "Permitir trading algorítmico" en
   las propiedades del EA.

## Cómo decide cuándo operar

1. **Detección de FVG**: patrón de 3 velas, igual que el indicador
   (`low[1] > high[3]` alcista, `high[1] < low[3]` bajista, en índices de
   velas ya cerradas).
2. **Mitigación → IFVG**: cuando el precio atraviesa por completo una zona
   FVG (por cierre o por mecha, según `InpMitigationMode`), esa zona se
   elimina y nace una zona IFVG en sentido contrario — igual que en el
   indicador.
3. **Niveles de liquidez**: máximo/mínimo del día anterior (D1) y de las
   sesiones anteriores de Londres/NY (acumulados vela a vela dentro de la
   ventana horaria configurada).
4. **Sesgo por barrido de liquidez** (si `InpRequireLiquiditySweep = true`,
   por defecto): antes de operar una zona, exige que en las últimas
   `InpSweepLookbackBars` velas el precio haya roto uno de los niveles
   activados (PDL/NY low/London low para largos; PDH/NY high/London high
   para cortos) y que la última vela cerrada haya "reclamado" ese nivel
   (cerrado de vuelta al otro lado). Si se desactiva, el EA opera cualquier
   FVG/IFVG que toque en la dirección permitida, sin exigir barrido previo.
5. **Entrada**: en cuanto el precio (Ask para compras, Bid para ventas)
   entra dentro de una zona FVG/IFVG no operada todavía y el sesgo lo
   permite, abre una posición a mercado. Cada zona solo se opera **una
   vez** (se marca como "traded" al usarla), para evitar entradas
   repetidas mientras el precio permanece dentro de la misma zona.
6. **SL/TP**: el stop queda en el borde contrario de la zona (+ colchón en
   puntos `InpSLBufferPoints`); el take profit es un múltiplo R del riesgo
   (`InpRewardRiskRatio`).

## Parámetros principales

| Grupo | Parámetro | Descripción |
|---|---|---|
| FVG/IFVG | `InpTradeIFVG` | Operar también zonas IFVG, no solo FVG nuevas |
| FVG/IFVG | `InpMinGapATRMult` | Filtro de tamaño mínimo del gap (× ATR); 0 = sin filtro |
| FVG/IFVG | `InpMitigationMode` | Mitigar por cierre de vela o por mecha |
| Liquidez | `InpUsePDHPDL` / `InpUseNYSession` / `InpUseLondonSession` | Qué niveles usar como referencia de barrido |
| Liquidez | `InpNYStart*`, `InpNYEnd*`, `InpLdn*` | Horario de cada sesión **en hora del servidor del bróker** — ajústalo una vez comparando con la hora real de Londres/NY |
| Estrategia | `InpRequireLiquiditySweep` | Exigir barrido+reclamo antes de operar una zona |
| Estrategia | `InpTradeDirection` | Solo largos / solo cortos / ambos |
| Riesgo | `InpUseRiskPercent`, `InpRiskPercent` | Lote calculado según % de equity arriesgado |
| Riesgo | `InpFixedLot` | Lote fijo, si `InpUseRiskPercent = false` |
| Riesgo | `InpRewardRiskRatio` | Take profit como múltiplo del riesgo (R) |
| Riesgo | `InpMaxPositions`, `InpMaxSpreadPoints` | Límites de exposición y de spread para entrar |
| Riesgo | `InpMaxDailyLossPercent` | Corta las nuevas entradas si la pérdida del día supera este % de equity (0 = desactivado) |
| General | `InpMagicNumber` | Identificador de las órdenes de este EA (útil si corres varios EAs a la vez) |
| General | `InpUseTradingHoursFilter` | Restringe las horas en que el EA puede abrir operaciones |

Nota sobre las horas de sesión: MT5 no tiene una base de datos de zonas
horarias como Pine Script, así que las sesiones de Londres/NY se configuran
directamente en **hora de servidor**. Revisa la hora del servidor en la
esquina del gráfico y ajusta los inputs una vez; ten en cuenta que el
offset cambia con el horario de verano/invierno tanto del bróker como de
Londres/Nueva York.

## Si el backtest te está dando muchas pérdidas

La causa más frecuente, con diferencia, es que **`InpNYStart/EndHour` e
`InpLdnStart/EndHour` no están calibrados a la hora de tu bróker**. Si esos
horarios no coinciden con la sesión real, el EA calcula "máximo/mínimo de
sesión" sobre un rango de velas arbitrario, el sesgo de barrido de liquidez
deja de tener relación con la estructura real del mercado, y las entradas
pasan a ser básicamente ruido — con exposición real (SL/TP), es decir,
pérdidas.

Cómo calibrarlo, paso a paso:

1. Añade el EA al gráfico con `InpLogSessionDiagnostics = true` (activado
   por defecto) y corre un backtest corto (una semana). En la pestaña
   **Diario/Experts** del Strategy Tester verás:
   - Al iniciar: la hora de servidor y la hora GMT en ese momento —
     réstalas para saber el offset actual de tu bróker respecto a GMT.
   - Cada vez que se cierra una sesión NY o Londres: `Sesión NY cerrada a
     las ... -> H=... L=...`.
2. Con el offset del paso anterior, calcula a qué hora de servidor
   corresponden las 09:30–16:00 de Nueva York y las 08:00–16:30 de
   Londres, y pon esos valores en `InpNYStart/EndHour(Min)` e
   `InpLdnStart/EndHour(Min)`. Ojo: Nueva York y Londres no siempre están
   en horario de verano al mismo tiempo que tu bróker, así que el offset
   puede variar un par de veces al año.
3. Vuelve a correr el backtest y revisa en el log que los cierres de
   sesión ahora caen donde esperas (comparando con las velas del gráfico
   a esa hora).

Otras causas habituales de pérdidas en backtest, sobre todo en índices/
acciones CFD:

- **Datos de tick pobres**: muchos brókers no tienen histórico de ticks
  reales para CFDs de acciones/índices, así que el Strategy Tester genera
  ticks simulados a partir de M1. Usa el modo *"Cada tick basado en datos
  reales"* si está disponible y revisa la calidad de los datos (icono de
  calidad en la barra de resultados del tester).
- **Modelado de spread/comisión irreal**: por defecto el tester puede usar
  un spread fijo que no se parece al real de tu bróker en ese símbolo.
  Configúralo en las propiedades del símbolo del tester o usa "Spread:
  Actual" si tu bróker lo soporta.
- **Horario de cotización del símbolo**: muchas acciones CFD solo cotizan
  en el horario del mercado subyacente (~6.5h/día), no 24h. Si tu ventana
  de sesión NY no coincide con esas horas, puede quedarse casi siempre sin
  datos con las que formar el rango.
- **Periodo de prueba corto o poco representativo**: con `InpMaxPositions`
  bajo y una sola configuración, unas pocas operaciones perdedoras seguidas
  pueden parecer "muchas pérdidas" sin ser estadísticamente significativas.
  Prueba sobre varios meses/años y varios símbolos antes de sacar
  conclusiones.

Si después de calibrar los horarios sigue perdiendo de forma consistente,
dime el símbolo, el periodo probado y (si puedes) el reporte del Strategy
Tester, y reviso la lógica de entrada contigo.

## Posibles mejoras futuras (no incluidas en esta primera versión)

- Entradas con órdenes límite en el borde de la zona en vez de a mercado.
- Break-even / trailing stop automático tras alcanzar cierto R.
- Uso del punto medio de la zona (CE, "consequent encroachment") como
  entrada en vez de cualquier punto dentro de la zona.
- Backtesting/optimización asistidos (walk-forward) sobre varios símbolos.

Si quieres cualquiera de estas, o ajustar la estrategia (p. ej. cambiar las
reglas de entrada, añadir un filtro de tendencia superior, etc.), dímelo y
lo añadimos sobre esta base.
