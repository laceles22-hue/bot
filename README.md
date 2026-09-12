# bot — Estrategia automática ICT (CRT + FVG/IFVG) para NinjaTrader 8

Bot de trading automático para **NinjaTrader 8**, orientado a futuros
**micro E-mini (MES, MNQ)**, que combina dos conceptos de la metodología
ICT (Inner Circle Trader):

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
La estrategia de NinjaTrader reimplementa esa misma lógica de FVG/IFVG
en C# (NinjaScript) y le añade el filtro de sesgo CRT y la gestión de
riesgo necesaria para operar en real/sim.

## Estructura del repositorio

```
bot/
├── indicators/
│   └── fvg_ifvg.pine              # Indicador visual FVG/IFVG (Pine Script v6, TradingView)
├── ninjatrader/
│   └── Strategies/
│       └── IctCrtFvgStrategy.cs   # Estrategia NinjaScript (C#): CRT + FVG/IFVG
├── README.md
└── CLAUDE.md
```

## Cómo funciona la estrategia

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
- Si hay sesgo **alcista** vigente:
  - **Entrada de continuación**: se acaba de formar una FVG alcista →
    entra en largo.
  - **Entrada de rebote**: el precio retestea una zona IFVG de soporte
    y cierra sosteniéndola → entra en largo.
- Simétrico para sesgo **bajista** con FVG/IFVG bajistas → entra en
  corto.
- Cada entrada define **stop** justo detrás del borde de la zona (con
  un buffer en ticks) y **take profit** como múltiplo R del riesgo.

Gestión de riesgo incluida: contratos por operación, máximo de
operaciones por día, pérdida máxima diaria en dólares, ventana horaria
de entrada, y cierre de posiciones al final de la sesión
(`IsExitOnSessionCloseStrategy`).

## Instalación en NinjaTrader 8

1. Abre NinjaTrader 8 → **New** → **NinjaScript Editor**.
2. En el árbol de la izquierda, clic derecho sobre **Strategies** →
   **New NinjaScript** → **Strategy**, o simplemente copia el archivo
   [`ninjatrader/Strategies/IctCrtFvgStrategy.cs`](ninjatrader/Strategies/IctCrtFvgStrategy.cs)
   dentro de:
   `Documentos\NinjaTrader 8\bin\Custom\Strategies\`
3. Vuelve al NinjaScript Editor y pulsa **Compile (F5)**. Corrige
   cualquier aviso de compilación si tu versión de NinjaTrader 8 difiere
   ligeramente en la API (ver notas de compatibilidad más abajo).
4. Abre un gráfico de **MES** o **MNQ** con el timeframe intradía que
   quieras usar como ejecución (por ejemplo, 5 min).
5. Clic derecho sobre el gráfico → **Strategies...** → selecciona
   **IctCrtFvgStrategy**, configura los parámetros (ver tabla abajo) y
   actívala.
6. **Recomendado**: pruébala primero en **Strategy Analyzer**
   (backtest) y luego en cuenta **Sim101** antes de arriesgar capital
   real.

### Notas de compatibilidad

- Escrita para la API de **NinjaTrader 8** (NinjaScript, C#). No es
  compatible con NinjaTrader 7 sin adaptar namespaces y firmas.
- Usa `AddDataSeries` para añadir la serie de timeframe superior (HTF):
  `BarsInProgress == 1` es esa serie; `BarsInProgress == 0` es el
  gráfico principal (ejecución).
- El cálculo de pérdida diaria (`GetTodayRealizedPnL`) agrupa las
  operaciones cerradas por fecha de calendario del cierre; en sesiones
  de futuros que cruzan medianoche puede diferir levemente del día de
  sesión de trading — ajusta si tu bróker/instrumento lo requiere.

## Parámetros principales

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

## Aviso de riesgo

Operar futuros implica riesgo real de pérdida de capital. Esta
estrategia es una plantilla educativa/de partida: valida su
rendimiento con backtesting y simulación antes de usarla con dinero
real, y ajusta los parámetros de riesgo a tu propia tolerancia y al
tamaño de tu cuenta. Esto no constituye asesoría financiera.
