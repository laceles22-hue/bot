# IMG Model — indicador para ATAS

Puerto a C# (SDK de indicadores de ATAS) del indicador Pine Script **IMG Model**
(`indicators/img_model.pine` si lo guardaste en el repo — FVG Inversion Model +
Setup Checklist, estilo @DodgysDD) que originalmente corre en TradingView.

## Contenido

- `ImgModel.cs` — el indicador completo.
- `ImgModel.Atas.csproj` — proyecto de compilación (mismo patrón que
  `Samples/Indicators.Samples.csproj` del repo oficial
  [AtasPlatform/Indicators](https://github.com/AtasPlatform/Indicators)).

## Cómo compilarlo

1. Instala [ATAS Platform](https://atas.net/Setup/ATASPlatform.exe) (trae las DLL
   del SDK en `C:\Program Files (x86)\ATAS Platform\`).
2. Instala el .NET SDK que pida tu versión de ATAS (revisa la versión exacta en
   la documentación de tu instalación; el repo oficial de indicadores usa .NET 10
   a fecha de este puerto).
3. Abre `indicators/atas/ImgModel.Atas.csproj` con Visual Studio o Rider, o compílalo
   por línea de comandos:
   ```
   dotnet build indicators/atas/ImgModel.Atas.csproj
   ```
4. Copia el `.dll` resultante a la carpeta de indicadores personalizados de ATAS
   (o usa el mecanismo de carga de indicadores externos de la plataforma) y
   añade "IMG Model" desde el listado de indicadores del gráfico.

Si `ATAS_BASE` en el `.csproj` no coincide con tu ruta de instalación, edítalo.

**Importante**: este código no se ha podido compilar en este entorno porque no
hay una instalación de ATAS disponible (las DLL del SDK no son redistribuibles).
Está escrito y revisado a mano contra el código fuente real de los indicadores
oficiales de ATAS (`FairValueGap.cs`, `OrderBlock.cs`, `DailyLines.cs`,
`Fractals.cs`, `ATR.cs`, etc. de https://github.com/AtasPlatform/Indicators),
pero puede necesitar ajustes menores al compilar contra tu versión exacta del
SDK. Si te da errores de compilación, pégamelos y los corrijo.

## Qué incluye (mapeo 1:1 con las secciones del Pine original)

- **Killzones** (Asia, London, NY AM, NY Lunch, NY PM) con cajas + generación de
  liquidez BSL/SSL al cierre de cada sesión.
- **Sweep de liquidez** (BSL/SSL, PDH/PDL, 4H High/Low, EQH/EQL simple) que activa
  la búsqueda de FVG.
- **FVG → IFVG** (patrón de 3 velas, inversión al cierre o a mecha, configurable).
- **Modelo de entrada base** (sweep + IFVG → señal LONG/SHORT con SL/TP sugeridos).
- **Checklist de 6 condiciones** con grado A+…C y reset N velas tras la IFVG.
- **FVG multi-timeframe** (5m/15m/1H/4H) calculado agregando las propias velas del
  gráfico (igual que hace el indicador oficial `FairValueGap.cs` de ATAS) — sólo
  se dibuja la más cercana al precio por timeframe.
- **Modelo PD Array Delivery** (touch de FVG HTF + IFVG en el TF actual → señal
  BUY/SELL con SL/TP por Risk:Reward).
- **BOS / CHoCH** (estructura de mercado por pivotes).
- **Zonas EQH/EQL** con filtro RSI, tolerancia configurable y mitigación por
  mecha/cuerpo (con opción de "rechazo" de 2 cierres).
- **Líneas CPI/News Buy Stop y Sell Stop** (pad/TP/SL alrededor del precio).
- **Alertas** vía el sistema de alertas nativo de ATAS (`AddAlert`).

## Limitaciones respecto al Pine original (leer antes de usar)

1. **SMT Divergence** (comparar pivotes contra otro símbolo, ej. MES vs ES): el
   SDK público de indicadores de ATAS no expone una forma de leer datos de OTRO
   instrumento desde dentro de un indicador normal (no existe nada equivalente a
   `request.security(otroSimbolo, ...)` de Pine en los indicadores oficiales de
   referencia). Por eso el check de SMT del checklist es un **interruptor manual**
   (`SmtManualConfirm`): lo marcas tú a mano al ver la divergencia en el símbolo
   correlacionado en otro gráfico.

2. **Zonas horarias**: ATAS no maneja zonas con nombre (`America/New_York`,
   `Europe/London`), sólo un offset UTC fijo. Las killzones usan un único offset
   configurable (`KillzoneUtcOffset`, igual que el `gmt_tz` compartido del script
   original). Hay que ajustarlo ±1h a mano en el cambio de horario de
   verano/invierno — la misma limitación que tienen los indicadores de sesión
   oficiales de ATAS (`DailyLines.cs` hace exactamente lo mismo con
   `InstrumentInfo.TimeZone`).

3. El script original tenía **dos bloques redundantes** de "FVG de timeframe
   mayor" (uno con un único TF seleccionable que alimentaba unas cajas que en la
   práctica ya no se usaban para nada, y otro con 5m/15m/1H/4H fijos que sí
   alimentaba las señales reales del modelo PD Array Delivery). Aquí sólo se
   implementó una vez ese concepto.

4. Todo el dibujo se hace con render personalizado (`OnRender` +
   `EnableCustomDrawing`), el mismo patrón que usan los indicadores oficiales
   `FairValueGap.cs` y `OrderBlock.cs` — no existe un equivalente directo a
   `box.new()`/`line.new()`/`label.new()` de Pine.
