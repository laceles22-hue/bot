# CLAUDE.md

Guía para Claude Code (y otros asistentes de IA) al trabajar en este repositorio.

## Qué es este repositorio

`bot` es una estrategia de trading automático para **NinjaTrader 8**,
orientada a futuros micro E-mini (**MES**, **MNQ**), basada en conceptos
de la metodología ICT: **CRT (Candle Range Theory)** para el sesgo
direccional en un timeframe superior, y **FVG/IFVG (Fair Value Gap /
Inverse FVG)** como gatillo de entrada en el timeframe de ejecución.

Ver [README.md](README.md) para la explicación funcional completa,
instrucciones de instalación en NinjaTrader y tabla de parámetros.

## Codebase structure

```
bot/
├── indicators/
│   └── fvg_ifvg.pine              # Indicador visual FVG/IFVG (Pine Script v6, TradingView), solo visualización
├── ninjatrader/
│   └── Strategies/
│       └── IctCrtFvgStrategy.cs   # Estrategia NinjaScript (C#) para NinjaTrader 8: CRT + FVG/IFVG, con gestión de riesgo
├── README.md
└── CLAUDE.md
```

- **`indicators/fvg_ifvg.pine`**: indicador Pine Script v6 para
  TradingView. Dibuja zonas FVG/IFVG, PDH/PDL y rangos de sesión
  NY/Londres. No ejecuta órdenes; es la referencia visual de la lógica
  FVG/IFVG que la estrategia de NinjaTrader reimplementa en C#.
- **`ninjatrader/Strategies/IctCrtFvgStrategy.cs`**: estrategia
  NinjaScript. Usa `AddDataSeries` para una serie de timeframe superior
  (Diario por defecto) donde calcula el sesgo CRT, y opera en el
  timeframe del gráfico usando FVG/IFVG como entrada, con stop/target
  basados en R-múltiplo y controles de riesgo (contratos, operaciones
  por día, pérdida diaria máxima, ventana horaria).

## Development workflow

Este repo no tiene build system tradicional (no hay `package.json`,
`pyproject.toml`, etc.) porque NinjaScript se compila **dentro de
NinjaTrader 8**, no con una toolchain externa:

- **Editar**: modifica directamente `ninjatrader/Strategies/*.cs`.
- **Compilar/probar**: copia (o enlaza) el `.cs` a
  `Documentos\NinjaTrader 8\bin\Custom\Strategies\` y compila desde el
  **NinjaScript Editor** (F5) dentro de NinjaTrader 8. No hay forma de
  compilar NinjaScript fuera de la aplicación NinjaTrader.
- **Backtest**: usar **Strategy Analyzer** en NinjaTrader 8 antes de
  cualquier cambio de lógica de entradas/salidas.
- **Indicador Pine**: `indicators/fvg_ifvg.pine` se pega directamente en
  el Pine Editor de TradingView; no requiere build.
- No hay linter/formatter configurado. Sigue el estilo ya presente en
  el `.cs` (regiones `#region`, comentarios en español, convención
  `PascalCase` para propiedades públicas de NinjaScript).

## Conventions

- Comentarios y nombres de parámetros visibles en la UI de NinjaTrader:
  en **español**, siguiendo el estilo del indicador Pine original.
- Nombres de señales de entrada/salida (`EnterLong`/`EnterShort`) usan
  constantes de clase (`LongSignal`, `ShortSignal`), no strings sueltos.
- Toda entrada calcula stop/target en **precio** y los redondea al tick
  del instrumento (`Instrument.MasterInstrument.RoundToTickSize`) para
  que la lógica funcione igual en MES, MNQ u otro instrumento.
- Cambios de riesgo (contratos, pérdida diaria máxima, ventana horaria)
  deben mantenerse como `NinjaScriptProperty` configurables, no
  hardcodeados.

## Branching / CI

- Rama de trabajo actual: `claude/awesome-hamilton-qwdtdy`.
- No hay CI configurado (no hay `.github/workflows`). La validación es
  manual: compilar en NinjaScript Editor + Strategy Analyzer antes de
  mergear cambios a la estrategia.

## Keeping this file up to date

Actualiza este archivo cuando cambie la estructura de carpetas, se
añadan nuevas estrategias/indicadores, o cambie el flujo de
compilación/backtest.
