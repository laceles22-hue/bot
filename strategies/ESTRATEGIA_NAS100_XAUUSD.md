# Estrategia personalizada: NAS100 / XAUUSD — Tendencia + Pullback (Riesgo Bajo)

Especificación de la estrategia implementada en
[`nas100_xauusd_tendencia_pullback.pine`](./nas100_xauusd_tendencia_pullback.pine)
(Pine Script v6, TradingView). Aplicar el indicador/estrategia por separado en
el gráfico de cada instrumento (NAS100 y XAUUSD), en temporalidad de 15
minutos a 1 hora.

## 1. Mercado

- **Nasdaq 100** (NAS100 / US100 — CFD o futuro sobre el índice)
- **XAUUSD** (Oro spot / CFD)

Ambos instrumentos comparten la misma lógica porque los dos son activos de
alta liquidez y tendencia marcada en intradía, con reacciones similares a
RSI/MACD/Bollinger en time frames cortos.

## 2. Temporalidad

**15 minutos a 1 hora.** El script funciona en cualquier temporalidad del
gráfico; se recomienda usar 1H para el filtro de tendencia (EMA50/EMA200) y
15M para afinar el timing de entrada. Evitar temporalidades inferiores a 15M
con esta configuración: el ruido aumenta la tasa de falsas señales de RSI y
MACD.

## 3. Nivel de riesgo

**Bajo.**

- Riesgo por operación: **0.5% del capital** (configurable entre 0.1%–5% en
  el input `riskPerTradePct`, pero el valor por defecto y recomendado para
  perfil bajo es 0.5%).
- Solo una posición abierta a la vez por instrumento (no se piramidea).
- Corte automático de nuevas entradas si se alcanza la pérdida máxima diaria.

## 4. Capital inicial

**10,000 USD** (`initial_capital` en la declaración `strategy()`, usado como
referencia para el backtest y para el cálculo de tamaño de posición basado en
riesgo).

## 5. Indicadores técnicos

| Indicador | Parámetros | Rol en la estrategia |
|---|---|---|
| Medias Móviles (EMA) | EMA 50 / EMA 200 | Filtro de tendencia (sesgo largo/corto) |
| RSI | Periodo 14, niveles 30/70, disparo 40/60 | Timing de entrada (salida de zona extrema) y salida anticipada |
| MACD | 12, 26, 9 | Confirmación de momentum en la dirección de la tendencia |
| Bandas de Bollinger | Periodo 20, 2 desviaciones estándar | Detección del pullback (zona de entrada) |

## 6. Condiciones de entrada

**Posición larga (Long):**

1. Tendencia alcista: `EMA50 > EMA200`.
2. Pullback: el precio (mínimo de la vela) toca o cruza la banda media o
   inferior de Bollinger — se compra el retroceso, no la persecución del
   precio.
3. RSI cruza al alza el nivel 40 (sale de una zona débil/sobreventa) y no
   está ya en sobrecompra (< 70).
4. MACD confirma el giro de momentum: la línea MACD cruza por encima de la
   señal, o el histograma pasa de negativo a positivo.
5. Vela de confirmación alcista (cierre > apertura).

**Posición corta (Short):** condiciones simétricas —
`EMA50 < EMA200`, precio rebotando hacia la banda media/superior de
Bollinger, RSI cruzando a la baja el nivel 60 sin estar en sobreventa, MACD
girando a bajista, vela de confirmación bajista.

Solo se abre una operación nueva si no hay ninguna posición abierta en ese
instrumento y no se ha alcanzado el límite de pérdida diaria.

## 7. Condiciones de salida

- **Take Profit / Stop Loss** (ver sección 8) — gestionados con
  `strategy.exit()` en cada barra mientras la posición está abierta.
- **Salida anticipada por señal:**
  - Long: se cierra si el RSI cruza por encima de 70 (sobrecompra) **o** el
    precio cierra por debajo de la EMA50 (rotura de estructura alcista).
  - Short: se cierra si el RSI cruza por debajo de 30 (sobreventa) **o** el
    precio cierra por encima de la EMA50.
- **Cierre por cambio de día** (opcional, desactivado por defecto ya que la
  operativa se definió 24/5 sin restricción horaria): activable con el input
  `flattenOnDayEnd`.

## 8. Gestión de riesgos

- **Stop Loss:** dinámico, basado en volatilidad —
  `1.5 × ATR(14)` desde el precio de entrada (no un porcentaje fijo del
  precio, para adaptarse a la volatilidad real de NAS100 y XAUUSD en cada
  momento).
- **Take Profit:** `Stop Loss × Relación R:R` desde el precio de entrada.
- **Relación Riesgo/Recompensa:** **1:2** por defecto (configurable de 1:1 a
  1:5 con el input `rrRatio`).
- **Tamaño de posición:** calculado dinámicamente en cada entrada para
  arriesgar exactamente el % de capital configurado (0.5% por defecto):
  `unidades = (capital_actual × riesgo%) / distancia_del_stop`.
- **Pérdida máxima diaria:** 2% del capital (configurable). Al alcanzarse,
  se bloquean nuevas entradas hasta el cambio de día; las posiciones ya
  abiertas se siguen gestionando con su stop/take profit normales.

## 9. Horarios de trading

**24/5** (todo el día, de domingo noche a viernes noche según horario de
mercado), sin restricción horaria por defecto — así se capturan movimientos
tanto en sesión asiática/Londres como en Nueva York, relevante sobre todo
para XAUUSD que se mueve en todas las sesiones. El script incluye un filtro
de sesión opcional (`useSessionFilter`, `sessionWindow`) por si en el futuro
se quiere acotar la operativa (p. ej. solo sesión de Nueva York o el
solapamiento Londres-NY) sin tener que reescribir la lógica.

## 10. Notas adicionales

- La estrategia es de **seguimiento de tendencia con entrada en retroceso**
  (trend-following + pullback), no de ruptura ni de reversión pura: busca
  entrar a favor de la tendencia dominante en un punto de mejor precio, con
  confirmación de momentum antes de arriesgar capital.
- El tamaño de posición basado en riesgo (y no en lotaje fijo) hace que la
  estrategia sea igual de válida para cuentas de distinto tamaño: solo hay
  que ajustar `initial_capital` y el resto se recalcula automáticamente.
- NAS100 y XAUUSD tienen distinta volatilidad absoluta (puntos de índice vs.
  dólares por onza); por eso el Stop Loss se define en múltiplos de ATR y no
  en puntos fijos — se adapta a cada instrumento sin tocar el código.
- Antes de operar en real, se recomienda: (1) backtest en TradingView con
  datos históricos de cada instrumento y comisión/slippage realistas, (2)
  validación en cuenta demo durante al menos unas semanas, (3) revisar que
  el bróker permita el tamaño de posición fraccionario que calcula la
  estrategia o redondear `qtyByRisk` al lote mínimo del bróker.
- El panel de estado en pantalla (tabla superior derecha) muestra en tiempo
  real: riesgo por operación, relación R:R objetivo, P/L del día y si la
  estrategia está ACTIVA o DETENIDA por pérdida diaria máxima.
