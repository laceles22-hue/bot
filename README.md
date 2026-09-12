# bot — Estrategias automáticas para NinjaTrader 8 (futuros MES/MNQ)

Este repo contiene **dos estrategias** de trading automático para
**NinjaTrader 8**, orientadas a futuros **micro E-mini (MES, MNQ)**:

1. **`IctCrtFvgStrategy`** — sesgo CRT (ICT) en timeframe superior +
   entradas de precisión con FVG/IFVG.
2. **`DonchianBreakoutStrategy`** — breakout de canal Donchian con
   órdenes stop pendientes (BuyStop/SellStop) a ambos lados del rango
   reciente, replicando el patrón de "orden stop + profit target ya
   calculado" típico de bots de ruptura.

## Estructura del repositorio

```
bot/
├── indicators/
│   └── fvg_ifvg.pine                  # Indicador visual FVG/IFVG (Pine Script v6, TradingView)
├── ninjatrader/
│   └── Strategies/
│       ├── IctCrtFvgStrategy.cs       # Estrategia NinjaScript (C#): CRT + FVG/IFVG
│       └── DonchianBreakoutStrategy.cs # Estrategia NinjaScript (C#): breakout Donchian con stop orders
├── README.md
└── CLAUDE.md
```

## 1. IctCrtFvgStrategy — CRT (Candle Range Theory) + FVG/IFVG

Combina dos conceptos de la metodología ICT (Inner Circle Trader):

1. **CRT (Candle Range Theory)** en un timeframe superior (por defecto,
   velas **Diarias**): detecta cuándo una vela barre (sweep) el máximo o
   mínimo de la vela de rango anterior y **cierra de nuevo dentro** de
   ese rango — una toma de liquidez que da **sesgo direccional**
   (alcista si barrió el mínimo, bajista si barrió el máximo).
2. **FVG / IFVG (Fair Value Gap / Inverse FVG)** en el timeframe del
   gráfico (el timeframe de ejecución): se usan como **gatillo de
   entrada de precisión**, pero solo a favor del sesgo CRT vigente.

El indicador visual de referencia (solo Pine Script / TradingView, sin
ejecutar órdenes) está en [`indicators/fvg_ifvg.pine`](indicators/fvg_ifvg.pine).
`IctCrtFvgStrategy.cs` reimplementa esa misma lógica de FVG/IFVG en C#
(NinjaScript) y le añade el filtro de sesgo CRT y la gestión de riesgo
necesaria para operar en real/sim.

### Cómo funciona

En cada vela cerrada del timeframe **superior** (Diario por defecto):

- Vela de referencia = la vela HTF ya cerrada anterior a la actual.
- Si la vela HTF actual perfora el **mínimo** de la vela de referencia
  pero **cierra por encima** de ese mínimo → sesgo **alcista**.
- Si perfora el **máximo** de la vela de referencia pero **cierra por
  debajo** → sesgo **bajista**.
- El sesgo queda "vigente" un número configurable de barras del
  gráfico (`Vigencia del sesgo`), se invalida si el precio cierra más
  allá del extremo contrario del rango, y (por defecto) se consume tras
  una sola operación.

En cada vela cerrada del timeframe de **ejecución** (el del gráfico):

- Se detectan y gestionan zonas FVG/IFVG con la misma lógica que el
  indicador Pine (patrón de 3 velas, mitigación por cierre, inversión a
  IFVG).
- Si hay sesgo **alcista** vigente: entra en largo por continuación
  (FVG alcista recién formada) o por rebote (retest de una zona IFVG de
  soporte que se sostiene).
- Simétrico para sesgo **bajista** con FVG/IFVG bajistas → entra en
  corto.
- Cada entrada define **stop** justo detrás del borde de la zona (con
  buffer en ticks) y **take profit** como múltiplo R del riesgo.

### Parámetros principales

| Grupo | Parámetro | Por defecto | Descripción |
|---|---|---|---|
| CRT | Usar Diario como referencia CRT | `true` | Si es `false`, usa el timeframe en minutos de abajo como HTF. |
| CRT | Timeframe HTF (minutos) | `240` | Solo aplica si el anterior es `false` (ej. 240 = 4H). |
| CRT | Vigencia del sesgo (barras) | `60` | Barras del gráfico que el sesgo permanece activo si no se usa. |
| CRT | Una sola operación por sesgo | `true` | Evita reentradas repetidas con el mismo sesgo. |
| CRT | Invalidar sesgo si el cierre rompe el rango contrario | `true` | Seguridad ante sesgos fallidos. |
| FVG | Tamaño mínimo del gap (x ATR) | `0.25` | Filtra gaps pequeños/ruido. `0` = sin filtro. |
| FVG | Periodo ATR | `14` | |
| FVG | Máx. zonas activas por tipo | `20` | |
| Entradas | Continuación / Rebote | `true` / `true` | Activa/desactiva cada modo de entrada. |
| Entradas | Buffer de stop (ticks) | `2` | Ticks extra más allá del borde de la zona para el stop. |
| Entradas | Múltiplo R | `2.0` | Take profit = riesgo × este múltiplo. |
| Riesgo | Contratos | `1` | Pensado para 1 contrato de MES/MNQ por defecto. |
| Riesgo | Máx. operaciones/día | `4` | |
| Riesgo | Máx. pérdida diaria ($) | `300` | Ajusta según tu cuenta y tamaño de contrato. |
| Riesgo | Ventana de entrada HHMM | `930`–`1550` | Hora del gráfico (normalmente hora de Nueva York en datos de futuros CME). |

### Notas de compatibilidad

- Usa `AddDataSeries` para añadir la serie de timeframe superior (HTF):
  `BarsInProgress == 1` es esa serie; `BarsInProgress == 0` es el
  gráfico principal (ejecución).

## 2. DonchianBreakoutStrategy — ruptura con órdenes stop pendientes

Reproduce el patrón de órdenes que se ve típicamente en bots de
breakout: una orden **`SellStop`** (o **`BuyStop`**) pendiente justo
por debajo/encima del rango reciente, con su **`Profit target`** ya
calculado desde el momento en que se coloca la orden.

### Cómo funciona

1. **Canal Donchian** de N velas (máximo/mínimo de las últimas N velas,
   sin contar la vela en formación) define el "rango reciente".
2. Mientras la estrategia está plana, mantiene **dos órdenes stop de
   entrada activas**: `BuyStop` justo por encima del máximo del canal y
   `SellStop` justo por debajo del mínimo — se van actualizando cada
   vela junto con el canal, igual que una orden stop pendiente movida
   manualmente en la plataforma.
3. En cuanto una se ejecuta (ruptura confirmada), se **cancela la
   contraria** y se define **stop loss** (múltiplo de ATR) y **profit
   target** (múltiplo R del riesgo) para la posición.
4. Un filtro de **ancho mínimo del canal (x ATR)** evita operar rupturas
   de rangos demasiado estrechos/ruidosos.

### Parámetros principales

| Grupo | Parámetro | Por defecto | Descripción |
|---|---|---|---|
| Ruptura | Periodo del canal Donchian (velas) | `20` | Ventana para el máximo/mínimo reciente. |
| Ruptura | Buffer de disparo (ticks) | `2` | Ticks más allá del canal para el precio de la orden stop. |
| Ruptura | Ancho mínimo del canal (x ATR) | `0.5` | `0` = sin filtro. |
| Ruptura | Periodo ATR | `14` | |
| Dirección | Habilitar rupturas al alza / a la baja | `false` / `true` | Por defecto **solo lado corto** (`SellStop`), como en el patrón original. Activa el alza si también quieres `BuyStop`. |
| Salida | Stop loss (x ATR) | `1.0` | Distancia del stop desde el precio de entrada. |
| Salida | Múltiplo Riesgo:Beneficio (R) | `2.0` | Take profit = riesgo × este múltiplo. |
| Riesgo | Contratos | `1` | |
| Riesgo | Máx. operaciones/día | `4` | |
| Riesgo | Máx. pérdida diaria ($) | `300` | |
| Riesgo | Ventana de entrada HHMM | `930`–`1550` | Fuera de esta ventana se cancelan las órdenes stop pendientes. |
| Visualización | Dibujar canal Donchian | `true` | |

### Notas de compatibilidad y limitaciones

- Usa `EnterLongStopMarket` / `EnterShortStopMarket` (enfoque
  administrado de NinjaScript) para colocar y actualizar las órdenes
  stop pendientes; `OnOrderUpdate` rastrea sus referencias y
  `OnExecutionUpdate` cancela la orden contraria al llenarse una.
- En un gap extremo donde el precio cruce **ambos** niveles en la misma
  vela, en teoría podrían llenarse las dos órdenes antes de que la
  cancelación de la contraria surta efecto; es un caso extremo poco
  común pero a tener en cuenta en instrumentos muy volátiles.

## Instalación en NinjaTrader 8

Ambas estrategias se instalan igual:

1. Abre NinjaTrader 8 → **New** → **NinjaScript Editor**.
2. En el árbol de la izquierda, clic derecho sobre **Strategies** →
   **New NinjaScript** → **Strategy**, o simplemente copia el archivo
   `.cs` correspondiente
   ([`IctCrtFvgStrategy.cs`](ninjatrader/Strategies/IctCrtFvgStrategy.cs) o
   [`DonchianBreakoutStrategy.cs`](ninjatrader/Strategies/DonchianBreakoutStrategy.cs))
   dentro de:
   `Documentos\NinjaTrader 8\bin\Custom\Strategies\`
3. Vuelve al NinjaScript Editor y pulsa **Compile (F5)**. Corrige
   cualquier aviso de compilación si tu versión de NinjaTrader 8 difiere
   ligeramente en la API.
4. Abre un gráfico de **MES** o **MNQ** con el timeframe intradía que
   quieras usar como ejecución (por ejemplo, 5 min).
5. Clic derecho sobre el gráfico → **Strategies...** → selecciona la
   estrategia deseada, configura los parámetros (ver tablas arriba) y
   actívala.
6. **Recomendado**: pruébala primero en **Strategy Analyzer**
   (backtest) y luego en cuenta **Sim101** antes de arriesgar capital
   real.

### Notas de compatibilidad generales

- Escritas para la API de **NinjaTrader 8** (NinjaScript, C#). No son
  compatibles con NinjaTrader 7 sin adaptar namespaces y firmas.
- El cálculo de pérdida diaria (`GetTodayRealizedPnL`) agrupa las
  operaciones cerradas por fecha de calendario del cierre; en sesiones
  de futuros que cruzan medianoche puede diferir levemente del día de
  sesión de trading — ajusta si tu bróker/instrumento lo requiere.

## Aviso de riesgo

Operar futuros implica riesgo real de pérdida de capital. Estas
estrategias son plantillas educativas/de partida: valida su
rendimiento con backtesting y simulación antes de usarlas con dinero
real, y ajusta los parámetros de riesgo a tu propia tolerancia y al
tamaño de tu cuenta. Esto no constituye asesoría financiera.
