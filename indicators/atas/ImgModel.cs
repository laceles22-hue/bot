// =====================================================================================
// IMG Model — puerto a ATAS (C#) del indicador Pine Script "IMG Model"
// (FVG Inversion Model + Setup Checklist, estilo @DodgysDD)
// =====================================================================================
//
// ORIGEN: indicators/img_model.pine (TradingView, Pine Script v6).
//
// LIMITACIONES DEL PUERTO (a diferencia de TradingView/Pine):
//
//   1) SMT Divergence (comparación de pivotes contra otro símbolo, ej. MES vs ES):
//      El SDK público de indicadores de ATAS no ofrece un equivalente directo a
//      `request.security(otroSimbolo, ...)` dentro de un mismo indicador. No existe
//      en los indicadores oficiales de referencia (AtasPlatform/Indicators) ningún
//      ejemplo de lectura de datos de OTRO instrumento desde un indicador normal.
//      Por eso el check de SMT del checklist es un interruptor MANUAL
//      (`SmtManualConfirm`) que el operador marca a mano mirando el símbolo
//      correlacionado en otro gráfico, en vez de calcularse solo. Si tu instalación
//      de ATAS tiene módulos de correlación/spread multi-instrumento, se podría
//      sustituir por eso, pero queda fuera del alcance de un Indicator estándar.
//
//   2) Zonas horarias con nombre (America/New_York, Europe/London) no existen en
//      ATAS: sólo hay un offset UTC fijo (`InstrumentInfo.TimeZone`, o aquí un
//      offset propio configurable). El cambio de horario de verano/invierno (DST)
//      hay que ajustarlo A MANO dos veces al año moviendo el offset ±1h — exactamente
//      la misma limitación que tienen los indicadores de sesión oficiales de ATAS
//      (ver Technical/DailyLines.cs, que hace lo mismo con InstrumentInfo.TimeZone).
//
//   3) El script original tenía DOS bloques de "FVG de temporalidad mayor" que se
//      solapaban (una sección "HTF PDA Delivery" con un único TF seleccionable, y
//      otra sección posterior "Auto HTF FVG / MTF FVG display" con 5m/15m/1H/4H fijos
//      que es la que realmente alimenta las señales del modelo PD Array Delivery).
//      Aquí se implementa UNA sola vez ese concepto (temporalidades mayores
//      agregadas a partir de las propias velas del gráfico, igual que hace
//      ATAS.Indicators.Technical.FairValueGap.cs oficial), evitando duplicar lógica.
//
//   4) Todo el dibujo (cajas FVG/IFVG, líneas de liquidez, checklist, etc.) se hace
//      con render personalizado (OnRender + EnableCustomDrawing), el mismo patrón
//      que usan los indicadores oficiales FairValueGap.cs y OrderBlock.cs — no con
//      "box/line/label" (eso es exclusivo de Pine).
//
// =====================================================================================

namespace ATAS.Indicators.Technical;

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Drawing;
using System.Linq;

using ATAS.Indicators.Drawing;

using OFT.Attributes;
using OFT.Rendering.Context;
using OFT.Rendering.Settings;
using OFT.Rendering.Tools;

using Color = System.Drawing.Color;

[DisplayName("IMG Model")]
public class ImgModel : Indicator
{
	#region Enums

	public enum MitigationModeType
	{
		[Display(Name = "Mecha (toque)")] Wick,
		[Display(Name = "Cierre")] Close
	}

	public enum SlModeType
	{
		[Display(Name = "Fracaso Stop")] FailedSweepStop,
		[Display(Name = "Narrow Stop (IFVG)")] NarrowIfvgStop
	}

	public enum TablePosType
	{
		[Display(Name = "Arriba Izquierda")] TopLeft,
		[Display(Name = "Arriba Derecha")] TopRight,
		[Display(Name = "Abajo Izquierda")] BottomLeft,
		[Display(Name = "Abajo Derecha")] BottomRight
	}

	public enum SweepModeType
	{
		[Display(Name = "Mecha")] Wick,
		[Display(Name = "Cuerpo")] Body
	}

	public enum DistanceUnitType
	{
		[Display(Name = "Puntos")] Points,
		[Display(Name = "Ticks")] Ticks
	}

	#endregion

	#region Nested types

	private class Killzone
	{
		public string Name;
		public bool Enabled;
		public TimeSpan Start;
		public TimeSpan End;
		public Color Color;

		// runtime
		public bool WasInSession;
		public decimal Hi, Lo;
		public int StartBar;
	}

	private class KzBox
	{
		public string Name;
		public Color Color;
		public int LeftBar, RightBar;
		public decimal Top, Bottom;
	}

	private class LiqLevel
	{
		public decimal Price;
		public int Bar;
		public bool IsHigh;
		public bool Valid = true;
		public string Tag;
		public Color Color;
	}

	private class FvgZone
	{
		public decimal Top;
		public decimal Bottom;
		public bool IsBull;
		public int StartBar;
		public bool Active = true;
		public int EndBar = -1;          // bar en que se mitigó / invirtió
		public bool IsIfvg;
		public int InvertedOnBar = -1;    // marca genérica: en qué barra ESTA fvg se invirtió (para el modelo PD Array)
		public int InvertedDir;           // 1 = reaccionó al alza (era bajista) | -1 = reaccionó a la baja (era alcista)
	}

	// Agrega velas del gráfico actual en un timeframe mayor fijo (alineado al reloj),
	// igual que ATAS.Indicators.Technical.FairValueGap.cs (TFPeriod / TimeFrameObj).
	private class TfPeriodBucket
	{
		public decimal High, Low, Open, Close;
		public int StartBar;
		public DateTime BeginTime;
	}

	private class TfAggregator
	{
		public readonly int Minutes;
		private readonly List<TfPeriodBucket> _periods = new();

		public bool IsNewPeriod { get; private set; }
		public int Count => _periods.Count;

		public (decimal High, decimal Low, decimal Open, decimal Close, int StartBar) this[int back]
		{
			get
			{
				var p = _periods[Count - 1 - back];
				return (p.High, p.Low, p.Open, p.Close, p.StartBar);
			}
		}

		public TfAggregator(int minutes) => Minutes = minutes;

		public void AddBar(int bar, DateTime time, decimal open, decimal high, decimal low, decimal close)
		{
			IsNewPeriod = false;
			var begin = GetBeginTime(time);
			var last = _periods.Count > 0 ? _periods[^1] : null;

			if (last is null || begin > last.BeginTime)
			{
				_periods.Add(new TfPeriodBucket { High = high, Low = low, Open = open, Close = close, StartBar = bar, BeginTime = begin });
				IsNewPeriod = true;
			}
			else
			{
				last.High = Math.Max(last.High, high);
				last.Low = Math.Min(last.Low, low);
				last.Close = close;
			}
		}

		private DateTime GetBeginTime(DateTime time)
		{
			var t = time.AddMilliseconds(-time.Millisecond).AddSeconds(-time.Second);
			var minutesSinceEpoch = (t - DateTime.MinValue).TotalMinutes;
			var rem = minutesSinceEpoch % Minutes;
			return t.AddMinutes(-rem);
		}
	}

	private class MtfNearestFvg
	{
		public decimal Top;
		public decimal Bottom;
		public bool IsBull;
		public int LeftBar;
		public bool Mitigated;
	}

	private class SwingPoint
	{
		public int Bar;
		public decimal Price;
	}

	private class StructBreak
	{
		public int FromBar, ToBar;
		public decimal Price;
		public bool IsBull;
		public bool IsChoch;
	}

	private class PdaSignal
	{
		public int Bar;
		public int Dir; // 1 long, -1 short
		public decimal Entry, Sl, Tp;
	}

	private class EqZone
	{
		public int Bar;
		public decimal LevelPrice;
		public decimal BodyPrice;
		public bool IsHigh;
		public bool Mitigated;
	}

	#endregion

	#region Fields — estado runtime

	// Killzones
	private readonly List<Killzone> _killzones = new();
	private readonly List<KzBox> _kzBoxes = new();

	// Liquidez (BSL = sobre máximos / SSL = bajo mínimos)
	private readonly List<LiqLevel> _bslPool = new();
	private readonly List<LiqLevel> _sslPool = new();
	private readonly List<LiqLevel> _extraBsl = new(); // PDH / 4HH
	private readonly List<LiqLevel> _extraSsl = new(); // PDL / 4HL

	private decimal _dayHigh, _dayLow;
	private bool _dayHlInit;

	private TfAggregator _agg4h;

	// FVG timeframe actual
	private readonly List<FvgZone> _fvgZones = new();

	// Modelo de entrada (sweep -> FVG -> IFVG)
	private string _pendingSide; // "long" / "short" / null
	private int _pendingBar = -1;
	private readonly List<PdaSignal> _entrySignals = new(); // señal base (sin exigir touch de HTF), independiente de PD Array Delivery
	private const int EntrySignalsMax = 10;

	// MTF FVG (5m/15m/1H/4H) — sólo la más cercana al precio por TF
	private TfAggregator _agg5, _agg15, _agg60, _agg240b;
	private readonly List<MtfNearestFvg> _pool5 = new();
	private readonly List<MtfNearestFvg> _pool15 = new();
	private readonly List<MtfNearestFvg> _pool60 = new();
	private readonly List<MtfNearestFvg> _pool240 = new();
	private MtfNearestFvg _nearest5, _nearest15, _nearest60, _nearest240;

	// PD Array Delivery
	private int _pdaTouchBar = -1;
	private readonly List<PdaSignal> _pdaSignals = new();

	// Checklist
	private bool _checkLiquidity, _checkHtf, _checkVolume, _checkIfvg, _checkTargets, _checkSmt;
	private int _ifvgBar = -1;

	// Volumen
	private readonly Queue<decimal> _volWindow = new();
	private decimal _volSum;

	// BOS / CHoCH
	private readonly List<StructBreak> _structBreaks = new();
	private SwingPoint _swingHigh, _swingLow;
	private int _trend; // 0 inicio, 1 alcista, -1 bajista

	// EQH / EQL (con filtro RSI)
	private readonly List<EqZone> _eqZones = new();
	private decimal _rsiAvgGain, _rsiAvgLoss;
	private bool _rsiInit;
	private decimal _varSmooth;
	private bool _varInit;

	// Control de proceso "por vela cerrada" (evita duplicados en repintado intrabar)
	private int _lastSeenBar = -1;

	private readonly FontSetting _labelFont = new() { FontFamily = "Arial", Size = 10 };
	private readonly FontSetting _tableFont = new() { FontFamily = "Consolas", Size = 12 };

	#endregion

	#region Propiedades — Killzones

	// Nota: los horarios/activación de sesión SÍ disparan RecalculateValues() porque
	// alimentan el estado acumulado en OnCalculate (cajas, BSL/SSL). Los colores no,
	// porque sólo se leen en el momento de dibujar (OnRender) cada zona ya creada.

	private double _kzUtcOffset = -5;
	private bool _useAsia = true, _useLondon = true, _useNyAm = true, _useNyLunch = true, _useNyPm = true;
	private TimeSpan _asiaStart = new(20, 0, 0), _asiaEnd = new(0, 0, 0);
	private TimeSpan _londonStart = new(2, 0, 0), _londonEnd = new(5, 0, 0);
	private TimeSpan _nyAmStart = new(9, 30, 0), _nyAmEnd = new(11, 0, 0);
	private TimeSpan _nyLunchStart = new(12, 0, 0), _nyLunchEnd = new(13, 0, 0);
	private TimeSpan _nyPmStart = new(13, 30, 0), _nyPmEnd = new(16, 0, 0);

	[Display(Name = "Offset UTC de referencia (horas)", GroupName = "Killzones", Order = 0,
		Description = "Todos los horarios de las killzones se interpretan en esta zona horaria fija (igual que 'gmt_tz' en el script original). Ajusta ±1h a mano en el cambio de horario de verano/invierno: ATAS no maneja zonas con nombre, sólo offsets.")]
	public double KillzoneUtcOffset { get => _kzUtcOffset; set { _kzUtcOffset = value; RecalculateValues(); } }

	[Display(Name = "Mostrar cajas de killzone", GroupName = "Killzones", Order = 1)]
	public bool ShowKzBoxes { get; set; } = true;

	[Display(Name = "Mostrar líneas BSL/SSL", GroupName = "Killzones", Order = 2)]
	public bool ShowLiqLines { get; set; } = true;

	[Range(5, 500)]
	[Display(Name = "Máx. cajas/líneas de killzone en memoria", GroupName = "Killzones", Order = 3)]
	public int MaxKillzoneItems { get; set; } = 40;

	[Display(Name = "Asia — activar", GroupName = "Asia", Order = 10)]
	public bool UseAsia { get => _useAsia; set { _useAsia = value; RecalculateValues(); } }

	[Display(Name = "Asia — inicio", GroupName = "Asia", Order = 11)]
	public TimeSpan AsiaStart { get => _asiaStart; set { _asiaStart = value; RecalculateValues(); } }

	[Display(Name = "Asia — fin", GroupName = "Asia", Order = 12)]
	public TimeSpan AsiaEnd { get => _asiaEnd; set { _asiaEnd = value; RecalculateValues(); } }

	[Display(Name = "Asia — color", GroupName = "Asia", Order = 13)]
	public Color AsiaColor { get; set; } = DefaultColors.Blue;

	[Display(Name = "London — activar", GroupName = "London", Order = 20)]
	public bool UseLondon { get => _useLondon; set { _useLondon = value; RecalculateValues(); } }

	[Display(Name = "London — inicio", GroupName = "London", Order = 21)]
	public TimeSpan LondonStart { get => _londonStart; set { _londonStart = value; RecalculateValues(); } }

	[Display(Name = "London — fin", GroupName = "London", Order = 22)]
	public TimeSpan LondonEnd { get => _londonEnd; set { _londonEnd = value; RecalculateValues(); } }

	[Display(Name = "London — color", GroupName = "London", Order = 23)]
	public Color LondonColor { get; set; } = DefaultColors.Red;

	[Display(Name = "NY AM — activar", GroupName = "NY AM", Order = 30)]
	public bool UseNyAm { get => _useNyAm; set { _useNyAm = value; RecalculateValues(); } }

	[Display(Name = "NY AM — inicio", GroupName = "NY AM", Order = 31)]
	public TimeSpan NyAmStart { get => _nyAmStart; set { _nyAmStart = value; RecalculateValues(); } }

	[Display(Name = "NY AM — fin", GroupName = "NY AM", Order = 32)]
	public TimeSpan NyAmEnd { get => _nyAmEnd; set { _nyAmEnd = value; RecalculateValues(); } }

	[Display(Name = "NY AM — color", GroupName = "NY AM", Order = 33)]
	public Color NyAmColor { get; set; } = DefaultColors.Green;

	[Display(Name = "NY Lunch — activar", GroupName = "NY Lunch", Order = 40)]
	public bool UseNyLunch { get => _useNyLunch; set { _useNyLunch = value; RecalculateValues(); } }

	[Display(Name = "NY Lunch — inicio", GroupName = "NY Lunch", Order = 41)]
	public TimeSpan NyLunchStart { get => _nyLunchStart; set { _nyLunchStart = value; RecalculateValues(); } }

	[Display(Name = "NY Lunch — fin", GroupName = "NY Lunch", Order = 42)]
	public TimeSpan NyLunchEnd { get => _nyLunchEnd; set { _nyLunchEnd = value; RecalculateValues(); } }

	[Display(Name = "NY Lunch — color", GroupName = "NY Lunch", Order = 43)]
	public Color NyLunchColor { get; set; } = DefaultColors.Yellow;

	[Display(Name = "NY PM — activar", GroupName = "NY PM", Order = 50)]
	public bool UseNyPm { get => _useNyPm; set { _useNyPm = value; RecalculateValues(); } }

	[Display(Name = "NY PM — inicio", GroupName = "NY PM", Order = 51)]
	public TimeSpan NyPmStart { get => _nyPmStart; set { _nyPmStart = value; RecalculateValues(); } }

	[Display(Name = "NY PM — fin", GroupName = "NY PM", Order = 52)]
	public TimeSpan NyPmEnd { get => _nyPmEnd; set { _nyPmEnd = value; RecalculateValues(); } }

	[Display(Name = "NY PM — color", GroupName = "NY PM", Order = 53)]
	public Color NyPmColor { get; set; } = DefaultColors.Purple;

	#endregion

	#region Propiedades — Fair Value Gaps

	[Display(Name = "Mostrar Fair Value Gaps", GroupName = "Fair Value Gaps", Order = 0)]
	public bool ShowFvg { get; set; } = true;

	[Display(Name = "Color FVG alcista", GroupName = "Fair Value Gaps", Order = 1)]
	public Color FvgBullColor { get; set; } = DefaultColors.Teal;

	[Display(Name = "Color FVG bajista", GroupName = "Fair Value Gaps", Order = 2)]
	public Color FvgBearColor { get; set; } = DefaultColors.Red;

	[Display(Name = "Color al invertirse (IFVG)", GroupName = "Fair Value Gaps", Order = 3)]
	public Color IfvgColor { get; set; } = DefaultColors.Orange;

	[Range(5, 200)]
	[Display(Name = "Máximo de FVG activas en memoria", GroupName = "Fair Value Gaps", Order = 4)]
	public int MaxFvgTrack { get; set; } = 30;

	[Display(Name = "Invalidar/mitigar cuando", GroupName = "Fair Value Gaps", Order = 5)]
	public MitigationModeType MitigationMode { get; set; } = MitigationModeType.Close;

	#endregion

	#region Propiedades — Modelo de entrada

	[Range(5, 500)]
	[Display(Name = "Barras máximas esperando inversión tras el sweep", GroupName = "Modelo de Entrada", Order = 0)]
	public int MaxWaitBars { get; set; } = 80;

	[Display(Name = "Modo de Stop Loss sugerido", GroupName = "Modelo de Entrada", Order = 1)]
	public SlModeType SlMode { get; set; } = SlModeType.FailedSweepStop;

	[Display(Name = "Mostrar señales de entrada", GroupName = "Modelo de Entrada", Order = 2)]
	public bool ShowSignals { get; set; } = true;

	[Display(Name = "Mostrar SL/TP sugeridos", GroupName = "Modelo de Entrada", Order = 3)]
	public bool ShowSlTp { get; set; } = true;

	[Range(1, 200)]
	[Display(Name = "Extensión de líneas SL/TP (barras)", GroupName = "Modelo de Entrada", Order = 4)]
	public int SlTpExtBars { get; set; } = 15;

	#endregion

	#region Propiedades — Checklist

	[Range(1, 50)]
	[Display(Name = "Reset checklist tras IFVG (velas)", GroupName = "Checklist", Order = 0)]
	public int CheckReset { get; set; } = 5;

	[Display(Name = "Mostrar tabla de checklist", GroupName = "Checklist", Order = 1)]
	public bool ShowCheckTable { get; set; } = true;

	[Display(Name = "Posición de la tabla", GroupName = "Checklist", Order = 2)]
	public TablePosType TablePosition { get; set; } = TablePosType.TopRight;

	#endregion

	#region Propiedades — Liquidez adicional

	[Display(Name = "Detectar EQH/EQL (para checklist)", GroupName = "Liquidez Adicional", Order = 0)]
	public bool DetectLiqEqhEql { get; set; } = true;

	[Range(0.01, 5)]
	[Display(Name = "Tolerancia EQH/EQL (x ATR)", GroupName = "Liquidez Adicional", Order = 1)]
	public decimal LiqEqTolAtr { get; set; } = 0.15m;

	[Display(Name = "Detectar PDH/PDL", GroupName = "Liquidez Adicional", Order = 2)]
	public bool DetectPdhPdl { get; set; } = true;

	[Display(Name = "Detectar 4H High/Low", GroupName = "Liquidez Adicional", Order = 3)]
	public bool Detect4hHl { get; set; } = true;

	[Range(2, 200)]
	[Display(Name = "Periodo ATR", GroupName = "Liquidez Adicional", Order = 4)]
	public int AtrPeriod { get; set; } = 14;

	#endregion

	#region Propiedades — MTF FVG / PD Array Delivery

	[Display(Name = "Usar FVG 5min", GroupName = "MTF FVG / PD Array", Order = 0)]
	public bool UseFvg5m { get; set; } = true;

	[Display(Name = "Usar FVG 15min", GroupName = "MTF FVG / PD Array", Order = 1)]
	public bool UseFvg15m { get; set; } = true;

	[Display(Name = "Usar FVG 1H", GroupName = "MTF FVG / PD Array", Order = 2)]
	public bool UseFvg1h { get; set; } = true;

	[Display(Name = "Usar FVG 4H", GroupName = "MTF FVG / PD Array", Order = 3)]
	public bool UseFvg4h { get; set; } = true;

	[Display(Name = "Mostrar cajas FVG MTF (gris)", GroupName = "MTF FVG / PD Array", Order = 4)]
	public bool ShowMtfFvgBoxes { get; set; } = true;

	[Range(50, 95)]
	[Display(Name = "Transparencia de la caja", GroupName = "MTF FVG / PD Array", Order = 5)]
	public int MtfBoxTransparency { get; set; } = 85;

	[Range(3, 60)]
	[Display(Name = "Máximo de FVG por timeframe en memoria", GroupName = "MTF FVG / PD Array", Order = 6)]
	public int MtfMaxTrack { get; set; } = 15;

	[Display(Name = "Activar modelo PD Array Delivery", GroupName = "PD Array Delivery", Order = 10)]
	public bool EnablePda { get; set; } = true;

	[Range(1, 50)]
	[Display(Name = "Máximo de velas entre touch HTF e IFVG", GroupName = "PD Array Delivery", Order = 11)]
	public int PdaMaxWait { get; set; } = 7;

	[Range(0.5, 10)]
	[Display(Name = "Risk:Reward (TP)", GroupName = "PD Array Delivery", Order = 12)]
	public decimal PdaRiskReward { get; set; } = 2.0m;

	[Range(1, 30)]
	[Display(Name = "Máximo de señales visibles", GroupName = "PD Array Delivery", Order = 13)]
	public int PdaMaxSignals { get; set; } = 5;

	[Display(Name = "Marcar touch de PD Array", GroupName = "PD Array Delivery", Order = 14)]
	public bool PdaShowTouchMarker { get; set; } = true;

	[Display(Name = "Color señal BUY", GroupName = "PD Array Delivery", Order = 15)]
	public Color PdaBuyColor { get; set; } = DefaultColors.Lime;

	[Display(Name = "Color señal SELL", GroupName = "PD Array Delivery", Order = 16)]
	public Color PdaSellColor { get; set; } = DefaultColors.Red;

	#endregion

	#region Propiedades — Volumen

	[Range(5, 500)]
	[Display(Name = "Lookback volumen promedio", GroupName = "Volumen", Order = 0)]
	public int VolLookback { get; set; } = 20;

	[Range(1.0, 10)]
	[Display(Name = "Multiplicador volumen (x avg)", GroupName = "Volumen", Order = 1)]
	public decimal VolMult { get; set; } = 1.2m;

	#endregion

	#region Propiedades — SMT (manual, ver limitaciones al inicio del archivo)

	[Display(Name = "Confirmar SMT manualmente", GroupName = "SMT Divergence (manual)", Order = 0,
		Description = "ATAS no permite leer datos de otro símbolo desde este indicador (ver comentario al inicio del archivo). Marca esta casilla a mano cuando confirmes divergencia SMT en el símbolo correlacionado.")]
	public bool SmtManualConfirm { get; set; }

	#endregion

	#region Propiedades — Market Structure (BOS/CHoCH)

	[Range(1, 50)]
	[Display(Name = "Longitud del pivote", GroupName = "BOS / CHoCH", Order = 0)]
	public int StructPivotLength { get; set; } = 5;

	[Display(Name = "Mostrar etiquetas", GroupName = "BOS / CHoCH", Order = 1)]
	public bool ShowStructLabels { get; set; } = true;

	[Display(Name = "Color alcista", GroupName = "BOS / CHoCH", Order = 2)]
	public Color StructBullColor { get; set; } = Color.FromArgb(255, 8, 153, 129);

	[Display(Name = "Color bajista", GroupName = "BOS / CHoCH", Order = 3)]
	public Color StructBearColor { get; set; } = Color.FromArgb(255, 242, 54, 69);

	[Display(Name = "Alerta en BOS", GroupName = "BOS / CHoCH", Order = 4)]
	public bool AlertOnBos { get; set; } = true;

	[Display(Name = "Alerta en CHoCH", GroupName = "BOS / CHoCH", Order = 5)]
	public bool AlertOnChoch { get; set; } = true;

	#endregion

	#region Propiedades — EQH/EQL (zonas con filtro RSI)

	[Display(Name = "Activar detección EQH/EQL", GroupName = "Zonas EQH/EQL (RSI)", Order = 0)]
	public bool ShowEqZones { get; set; } = true;

	[Display(Name = "Filtrar por sobrecompra/sobreventa (RSI)", GroupName = "Zonas EQH/EQL (RSI)", Order = 1)]
	public bool EqUseRsiFilter { get; set; } = true;

	[Range(1, 30)]
	[Display(Name = "Fuerza del filtro (desviación desde RSI 50)", GroupName = "Zonas EQH/EQL (RSI)", Order = 2)]
	public int EqRsiThreshold { get; set; } = 5;

	[Range(0.001, 0.1)]
	[Display(Name = "Tolerancia de nivel igual", GroupName = "Zonas EQH/EQL (RSI)", Order = 3)]
	public decimal EqTolerance { get; set; } = 0.05m;

	[Range(1, 5000)]
	[Display(Name = "Antigüedad máxima de zona (barras)", GroupName = "Zonas EQH/EQL (RSI)", Order = 4)]
	public int EqExpiryAge { get; set; } = 1000;

	[Display(Name = "Tipo de mitigación", GroupName = "Zonas EQH/EQL (RSI)", Order = 5)]
	public SweepModeType EqMitigation { get; set; } = SweepModeType.Body;

	[Display(Name = "Permitir rechazo (2 cierres para mitigar)", GroupName = "Zonas EQH/EQL (RSI)", Order = 6)]
	public bool EqAllowRejection { get; set; }

	[Display(Name = "Color alcista (EQL)", GroupName = "Zonas EQH/EQL (RSI)", Order = 7)]
	public Color EqBullColor { get; set; } = DefaultColors.Purple;

	[Display(Name = "Color bajista (EQH)", GroupName = "Zonas EQH/EQL (RSI)", Order = 8)]
	public Color EqBearColor { get; set; } = DefaultColors.Purple;

	#endregion

	#region Propiedades — CPI / News Buy Stop y Sell Stop

	[Display(Name = "Activar líneas CPI/News", GroupName = "CPI / News Stop Lines", Order = 0)]
	public bool CpiEnabled { get; set; }

	[Display(Name = "Unidad de distancia", GroupName = "CPI / News Stop Lines", Order = 1)]
	public DistanceUnitType CpiDistanceUnit { get; set; } = DistanceUnitType.Points;

	[Range(1, 100000)]
	[Display(Name = "Protección (pad)", GroupName = "CPI / News Stop Lines", Order = 2)]
	public int CpiPad { get; set; } = 30;

	[Range(1, 100000)]
	[Display(Name = "Take Profit", GroupName = "CPI / News Stop Lines", Order = 3)]
	public int CpiTp { get; set; } = 50;

	[Range(1, 100000)]
	[Display(Name = "Stop Loss", GroupName = "CPI / News Stop Lines", Order = 4)]
	public int CpiSl { get; set; } = 30;

	[Display(Name = "Color Buy", GroupName = "CPI / News Stop Lines", Order = 5)]
	public Color CpiBuyColor { get; set; } = DefaultColors.Green;

	[Display(Name = "Color Sell", GroupName = "CPI / News Stop Lines", Order = 6)]
	public Color CpiSellColor { get; set; } = DefaultColors.Red;

	[Display(Name = "Color precio actual", GroupName = "CPI / News Stop Lines", Order = 7)]
	public Color CpiMidColor { get; set; } = DefaultColors.Blue;

	[Display(Name = "Mostrar etiquetas", GroupName = "CPI / News Stop Lines", Order = 8)]
	public bool CpiShowLabels { get; set; } = true;

	#endregion

	#region Propiedades — Alertas

	[Display(Name = "Alerta en sweep de liquidez", GroupName = "Alertas", Order = 0)]
	public bool AlertOnSweep { get; set; } = true;

	[Display(Name = "Alerta en IFVG (entrada)", GroupName = "Alertas", Order = 1)]
	public bool AlertOnIfvg { get; set; } = true;

	[Display(Name = "Alerta en setup completo (5+/6)", GroupName = "Alertas", Order = 2)]
	public bool AlertOnFullSetup { get; set; } = true;

	[Display(Name = "Alerta en señal PD Array IFVG", GroupName = "Alertas", Order = 3)]
	public bool AlertOnPda { get; set; } = true;

	[Display(Name = "Archivo de sonido de alerta", GroupName = "Alertas", Order = 4)]
	public string AlertFile { get; set; } = "alert1";

	[Display(Name = "Color de fondo de alerta", GroupName = "Alertas", Order = 5)]
	public Color AlertBgColor { get; set; } = Color.FromArgb(255, 75, 72, 72);

	[Display(Name = "Color de texto de alerta", GroupName = "Alertas", Order = 6)]
	public Color AlertForeColor { get; set; } = Color.FromArgb(255, 247, 249, 249);

	#endregion

	#region ctor

	public ImgModel() : base(true)
	{
		DenyToChangePanel = true;
		EnableCustomDrawing = true;
		SubscribeToDrawingEvents(DrawingLayouts.Final);

		DataSeries[0].IsHidden = true;
		((ValueDataSeries)DataSeries[0]).VisualType = VisualMode.Hide;

		BuildKillzoneDefs();
	}

	#endregion

	#region OnRecalculate / OnCalculate

	protected override void OnRecalculate()
	{
		_killzones.Clear();
		BuildKillzoneDefs();

		_kzBoxes.Clear();
		_bslPool.Clear();
		_sslPool.Clear();
		_extraBsl.Clear();
		_extraSsl.Clear();
		_dayHlInit = false;

		_agg4h = new TfAggregator(240);
		_agg5 = new TfAggregator(5);
		_agg15 = new TfAggregator(15);
		_agg60 = new TfAggregator(60);
		_agg240b = new TfAggregator(240);

		_pool5.Clear(); _pool15.Clear(); _pool60.Clear(); _pool240.Clear();
		_nearest5 = _nearest15 = _nearest60 = _nearest240 = null;

		_fvgZones.Clear();
		_pendingSide = null;
		_pendingBar = -1;
		_entrySignals.Clear();

		_pdaTouchBar = -1;
		_pdaSignals.Clear();

		_checkLiquidity = _checkHtf = _checkVolume = _checkIfvg = _checkTargets = _checkSmt = false;
		_ifvgBar = -1;

		_volWindow.Clear();
		_volSum = 0;

		_structBreaks.Clear();
		_swingHigh = _swingLow = null;
		_trend = 0;

		_eqZones.Clear();
		_rsiInit = false;
		_varInit = false;

		_lastSeenBar = -1;
	}

	private void BuildKillzoneDefs()
	{
		_killzones.Add(new Killzone { Name = "Asia", Enabled = UseAsia, Start = AsiaStart, End = AsiaEnd, Color = AsiaColor });
		_killzones.Add(new Killzone { Name = "London", Enabled = UseLondon, Start = LondonStart, End = LondonEnd, Color = LondonColor });
		_killzones.Add(new Killzone { Name = "NY AM", Enabled = UseNyAm, Start = NyAmStart, End = NyAmEnd, Color = NyAmColor });
		_killzones.Add(new Killzone { Name = "NY Lunch", Enabled = UseNyLunch, Start = NyLunchStart, End = NyLunchEnd, Color = NyLunchColor });
		_killzones.Add(new Killzone { Name = "NY PM", Enabled = UseNyPm, Start = NyPmStart, End = NyPmEnd, Color = NyPmColor });
	}

	protected override void OnCalculate(int bar, decimal value)
	{
		if (bar == 0)
			_lastSeenBar = -1;

		// Se procesa la barra que ACABA de cerrarse (bar - 1), igual que hace
		// ATAS.Indicators.Technical.OrderBlock.cs, para no repintar en cada tick.
		if (_lastSeenBar != bar)
		{
			ProcessClosedBar(bar - 1);
			_lastSeenBar = bar;
		}
	}

	private void ProcessClosedBar(int cb)
	{
		if (cb < 0)
			return;

		var candle = GetCandle(cb);

		StepKillzones(cb, candle);
		StepPdhPdl(cb, candle);
		Step4hHighLow(cb, candle);
		var (bslHit, sslHit) = StepSweepDetection(cb, candle);
		StepFvgDetection(cb, candle);
		StepMtfFvg(cb, candle);
		var ifvgFired = StepFvgMitigationAndIfvg(cb, candle, out var ifvgDir);
		StepVolume(cb, candle);
		StepEqZones(cb, candle);
		StepChecklist(cb, candle, bslHit || sslHit, ifvgFired, ifvgDir);
		StepStructure(cb, candle);
		StepPdaModel(cb, candle, ifvgFired, ifvgDir);
	}

	#endregion

	#region 1) Killzones

	private bool InWindow(TimeSpan t, TimeSpan start, TimeSpan end) =>
		start <= end ? (t >= start && t <= end) : (t >= start || t <= end);

	private void StepKillzones(int bar, IndicatorCandle candle)
	{
		var t = candle.Time.AddHours(KillzoneUtcOffset).TimeOfDay;

		foreach (var kz in _killzones)
		{
			if (!kz.Enabled)
				continue;

			var inSession = InWindow(t, kz.Start, kz.End);

			if (inSession && !kz.WasInSession)
			{
				kz.Hi = candle.High;
				kz.Lo = candle.Low;
				kz.StartBar = bar;
			}
			else if (inSession)
			{
				kz.Hi = Math.Max(kz.Hi, candle.High);
				kz.Lo = Math.Min(kz.Lo, candle.Low);
			}

			if (!inSession && kz.WasInSession)
			{
				if (ShowKzBoxes)
				{
					_kzBoxes.Add(new KzBox { Name = kz.Name, Color = kz.Color, LeftBar = kz.StartBar, RightBar = bar, Top = kz.Hi, Bottom = kz.Lo });

					if (_kzBoxes.Count > MaxKillzoneItems)
						_kzBoxes.RemoveAt(0);
				}

				PushLiq(_bslPool, kz.Hi, bar, true, "BSL");
				PushLiq(_sslPool, kz.Lo, bar, false, "SSL");
			}

			kz.WasInSession = inSession;
		}
	}

	private void PushLiq(List<LiqLevel> pool, decimal price, int bar, bool isHigh, string tag)
	{
		pool.Add(new LiqLevel { Price = price, Bar = bar, IsHigh = isHigh, Tag = tag });

		if (pool.Count > MaxKillzoneItems)
			pool.RemoveAt(0);
	}

	#endregion

	#region 1b) PDH/PDL y 4H High/Low

	private void StepPdhPdl(int bar, IndicatorCandle candle)
	{
		if (!DetectPdhPdl)
			return;

		if (IsNewSession(bar))
		{
			if (_dayHlInit)
				PushLiq(_extraBsl, _dayHigh, bar, true, "PDH");
			if (_dayHlInit)
				PushLiq(_extraSsl, _dayLow, bar, false, "PDL");

			_dayHigh = candle.High;
			_dayLow = candle.Low;
			_dayHlInit = true;
		}
		else
		{
			_dayHigh = _dayHlInit ? Math.Max(_dayHigh, candle.High) : candle.High;
			_dayLow = _dayHlInit ? Math.Min(_dayLow, candle.Low) : candle.Low;
			_dayHlInit = true;
		}
	}

	private void Step4hHighLow(int bar, IndicatorCandle candle)
	{
		if (!Detect4hHl)
			return;

		var hadPeriod = _agg4h.Count > 0;
		var prevTopBefore = hadPeriod ? _agg4h[0] : default;

		_agg4h.AddBar(bar, candle.Time, candle.Open, candle.High, candle.Low, candle.Close);

		if (_agg4h.IsNewPeriod && hadPeriod)
		{
			// El bucket anterior (ya cerrado) queda disponible como 4HH/4HL.
			PushLiq(_extraBsl, prevTopBefore.High, bar, true, "4HH");
			PushLiq(_extraSsl, prevTopBefore.Low, bar, false, "4HL");
		}
	}

	#endregion

	#region 2) Sweep de liquidez

	private (bool bslHit, bool sslHit) StepSweepDetection(int bar, IndicatorCandle candle)
	{
		var bslHit = CheckSweep(_bslPool, true, bar, candle) || CheckSweep(_extraBsl, true, bar, candle);
		var sslHit = CheckSweep(_sslPool, false, bar, candle) || CheckSweep(_extraSsl, false, bar, candle);

		if (bslHit)
		{
			_pendingSide = "short";
			_pendingBar = bar;

			if (AlertOnSweep)
				AddAlert(AlertFile, InstrumentInfo.Instrument, "Sweep de BSL (liquidez sobre máximos)", AlertBgColor, AlertForeColor);
		}

		if (sslHit)
		{
			_pendingSide = "long";
			_pendingBar = bar;

			if (AlertOnSweep)
				AddAlert(AlertFile, InstrumentInfo.Instrument, "Sweep de SSL (liquidez bajo mínimos)", AlertBgColor, AlertForeColor);
		}

		if (_pendingBar >= 0 && bar - _pendingBar > MaxWaitBars)
		{
			_pendingSide = null;
			_pendingBar = -1;
		}

		return (bslHit, sslHit);
	}

	private bool CheckSweep(List<LiqLevel> pool, bool isHigh, int bar, IndicatorCandle candle)
	{
		var hit = false;

		foreach (var l in pool)
		{
			if (!l.Valid)
				continue;

			if (isHigh && candle.High > l.Price)
			{
				l.Valid = false;
				hit = true;
			}
			else if (!isHigh && candle.Low < l.Price)
			{
				l.Valid = false;
				hit = true;
			}
		}

		return hit;
	}

	private bool AnySweptRecent(List<LiqLevel> pool, int bar, int maxBars) =>
		pool.Any(l => !l.Valid && bar - l.Bar <= maxBars);

	#endregion

	#region 3) Detección de FVG (timeframe actual)

	private void StepFvgDetection(int bar, IndicatorCandle candle)
	{
		if (bar < 2)
			return;

		var c2 = GetCandle(bar - 2);

		var isBull = candle.Low > c2.High;
		var isBear = candle.High < c2.Low;

		if (isBull)
			_fvgZones.Add(new FvgZone { Top = candle.Low, Bottom = c2.High, IsBull = true, StartBar = bar - 2 });

		if (isBear)
			_fvgZones.Add(new FvgZone { Top = c2.Low, Bottom = candle.High, IsBull = false, StartBar = bar - 2 });

		while (_fvgZones.Count(z => z.Active) > MaxFvgTrack)
		{
			var old = _fvgZones.First(z => z.Active);
			old.Active = false;
			old.EndBar = bar;
		}
	}

	private bool ClosedThrough(IndicatorCandle candle, decimal bottom, decimal top, bool isBullZone) =>
		isBullZone
			? (MitigationMode == MitigationModeType.Close ? candle.Close < bottom : candle.Low < bottom)
			: (MitigationMode == MitigationModeType.Close ? candle.Close > top : candle.High > top);

	private bool StepFvgMitigationAndIfvg(int bar, IndicatorCandle candle, out int dir)
	{
		dir = 0;
		var fired = false;

		foreach (var z in _fvgZones)
		{
			if (!z.Active)
				continue;

			if (ClosedThrough(candle, z.Bottom, z.Top, z.IsBull))
			{
				z.Active = false;
				z.EndBar = bar;
				z.InvertedOnBar = bar;
				z.InvertedDir = z.IsBull ? -1 : 1; // invBull => reacciona a la baja | invBear => reacciona al alza

				var invBull = z.IsBull;   // FVG alcista invertida a la baja
				var invBear = !z.IsBull;  // FVG bajista invertida al alza

				// LONG: SSL barrida + FVG bajista invertida al alza
				if (invBear && _pendingSide == "long" && z.StartBar > _pendingBar)
				{
					dir = 1;
					fired = true;
					_pendingSide = null;
					_pendingBar = -1;

					var sl = SlMode == SlModeType.NarrowIfvgStop ? z.Bottom : candle.Low;
					var tp = NearestOpposite(_bslPool, true, candle.Close) ?? NearestOpposite(_extraBsl, true, candle.Close);
					PushEntrySignal(bar, 1, candle.Close, sl, tp);

					if (AlertOnIfvg)
						AddAlert(AlertFile, InstrumentInfo.Instrument, "LONG: IFVG bajista tras sweep SSL", AlertBgColor, AlertForeColor);
				}
				// SHORT: BSL barrida + FVG alcista invertida a la baja
				else if (invBull && _pendingSide == "short" && z.StartBar > _pendingBar)
				{
					dir = -1;
					fired = true;
					_pendingSide = null;
					_pendingBar = -1;

					var sl = SlMode == SlModeType.NarrowIfvgStop ? z.Top : candle.High;
					var tp = NearestOpposite(_sslPool, false, candle.Close) ?? NearestOpposite(_extraSsl, false, candle.Close);
					PushEntrySignal(bar, -1, candle.Close, sl, tp);

					if (AlertOnIfvg)
						AddAlert(AlertFile, InstrumentInfo.Instrument, "SHORT: IFVG alcista tras sweep BSL", AlertBgColor, AlertForeColor);
				}
			}
		}

		return fired;
	}

	// Nivel de liquidez válido más cercano por encima (wantAbove=true) o por debajo del precio de referencia.
	private decimal? NearestOpposite(List<LiqLevel> pool, bool wantAbove, decimal refPrice)
	{
		decimal? best = null;

		foreach (var l in pool)
		{
			if (!l.Valid)
				continue;

			if (wantAbove && l.Price > refPrice && (best is null || l.Price < best))
				best = l.Price;
			else if (!wantAbove && l.Price < refPrice && (best is null || l.Price > best))
				best = l.Price;
		}

		return best;
	}

	private void PushEntrySignal(int bar, int dir, decimal entry, decimal sl, decimal? tp)
	{
		_entrySignals.Add(new PdaSignal { Bar = bar, Dir = dir, Entry = entry, Sl = sl, Tp = tp ?? (dir == 1 ? entry + (entry - sl) * 2 : entry - (sl - entry) * 2) });

		while (_entrySignals.Count > EntrySignalsMax)
			_entrySignals.RemoveAt(0);
	}

	#endregion

	#region 4) MTF FVG (5m / 15m / 1H / 4H) — sólo la más cercana al precio por TF

	private void StepMtfFvg(int bar, IndicatorCandle candle)
	{
		StepOneMtf(_agg5, _pool5, ref _nearest5, bar, candle, UseFvg5m);
		StepOneMtf(_agg15, _pool15, ref _nearest15, bar, candle, UseFvg15m);
		StepOneMtf(_agg60, _pool60, ref _nearest60, bar, candle, UseFvg1h);
		StepOneMtf(_agg240b, _pool240, ref _nearest240, bar, candle, UseFvg4h);
	}

	private void StepOneMtf(TfAggregator agg, List<MtfNearestFvg> pool, ref MtfNearestFvg nearest, int bar, IndicatorCandle candle, bool enabled)
	{
		agg.AddBar(bar, candle.Time, candle.Open, candle.High, candle.Low, candle.Close);

		if (!enabled)
		{
			nearest = null;
			return;
		}

		if (agg.IsNewPeriod && agg.Count >= 3)
		{
			var p0 = agg[0];
			var p2 = agg[2];

			if (p2.High < p0.Low)
				pool.Add(new MtfNearestFvg { Top = p0.Low, Bottom = p2.High, IsBull = true, LeftBar = p2.StartBar });
			else if (p2.Low > p0.High)
				pool.Add(new MtfNearestFvg { Top = p2.Low, Bottom = p0.High, IsBull = false, LeftBar = p2.StartBar });
		}

		// mitigación + límite de memoria
		foreach (var z in pool)
		{
			if (!z.Mitigated)
				z.Mitigated = z.IsBull ? candle.Close < z.Bottom : candle.Close > z.Top;
		}

		pool.RemoveAll(z => z.Mitigated);

		while (pool.Count > MtfMaxTrack)
			pool.RemoveAt(0);

		nearest = null;
		decimal bestDist = decimal.MaxValue;

		foreach (var z in pool)
		{
			var d = candle.Close > z.Top ? candle.Close - z.Top : (candle.Close < z.Bottom ? z.Bottom - candle.Close : 0m);

			if (d < bestDist)
			{
				bestDist = d;
				nearest = z;
			}
		}
	}

	#endregion

	#region 6) Volumen

	private void StepVolume(int bar, IndicatorCandle candle)
	{
		_volWindow.Enqueue(candle.Volume);
		_volSum += candle.Volume;

		if (_volWindow.Count > VolLookback)
			_volSum -= _volWindow.Dequeue();
	}

	private bool VolumeSpike(IndicatorCandle candle)
	{
		if (_volWindow.Count < VolLookback)
			return false;

		var avg = _volSum / _volWindow.Count;
		return candle.Volume > avg * VolMult;
	}

	#endregion

	#region 8) Checklist + grado

	private void StepChecklist(int bar, IndicatorCandle candle, bool anySweepThisBar, bool ifvgFired, int ifvgDir)
	{
		if (ifvgFired)
		{
			_ifvgBar = bar;
		}
		else if (_ifvgBar >= 0 && bar - _ifvgBar >= CheckReset)
		{
			_checkLiquidity = _checkHtf = _checkVolume = _checkIfvg = _checkTargets = _checkSmt = false;
			_ifvgBar = -1;
		}

		if (AnySweptRecent(_bslPool, bar, 10) || AnySweptRecent(_sslPool, bar, 10) ||
			AnySweptRecent(_extraBsl, bar, 10) || AnySweptRecent(_extraSsl, bar, 10))
			_checkLiquidity = true;

		var htfTouch = TouchesAnyMtf(candle);

		if (htfTouch)
			_checkHtf = true;

		if (VolumeSpike(candle))
			_checkVolume = true;

		if (ifvgFired)
			_checkIfvg = true;

		if (ifvgDir == 1 && _bslPool.Any(l => l.Valid && l.Price > candle.Close) || (ifvgDir == 1 && _extraBsl.Any(l => l.Valid && l.Price > candle.Close)))
			_checkTargets = true;

		if (ifvgDir == -1 && _sslPool.Any(l => l.Valid && l.Price < candle.Close) || (ifvgDir == -1 && _extraSsl.Any(l => l.Valid && l.Price < candle.Close)))
			_checkTargets = true;

		if (SmtManualConfirm)
			_checkSmt = true;

		var score = (_checkLiquidity ? 1 : 0) + (_checkHtf ? 1 : 0) + (_checkVolume ? 1 : 0) +
					(_checkIfvg ? 1 : 0) + (_checkTargets ? 1 : 0) + (_checkSmt ? 1 : 0);

		if (score >= 5 && AlertOnFullSetup)
			AddAlert(AlertFile, InstrumentInfo.Instrument, $"Setup completo — grado {GradeText(score)} ({score}/6)", AlertBgColor, AlertForeColor);
	}

	private bool TouchesAnyMtf(IndicatorCandle candle)
	{
		bool Touch(MtfNearestFvg z) => z != null && candle.High >= z.Bottom && candle.Low <= z.Top;
		return Touch(_nearest5) || Touch(_nearest15) || Touch(_nearest60) || Touch(_nearest240);
	}

	private static string GradeText(int score) => score switch
	{
		6 => "A+",
		5 => "A",
		4 => "B+",
		3 => "B",
		2 => "C+",
		_ => "C"
	};

	private static Color GradeColor(int score) =>
		score >= 5 ? Color.FromArgb(255, 0, 200, 0) : score >= 3 ? Color.FromArgb(255, 220, 190, 0) : Color.FromArgb(255, 220, 60, 60);

	#endregion

	#region 7 continuación) EQH/EQL simples (liquidez extra para checklist, sin filtro RSI)

	private void StepEqZones(int bar, IndicatorCandle candle)
	{
		// -- EQH/EQL "simple" para checklist (tolerancia por ATR, sin filtro RSI) --
		if (DetectLiqEqhEql && bar >= 1)
		{
			var atr = Atr(bar);
			var prev = GetCandle(bar - 1);

			if (Math.Abs(candle.High - prev.High) < atr * LiqEqTolAtr)
				PushLiq(_extraBsl, Math.Max(candle.High, prev.High), bar, true, "EQH");

			if (Math.Abs(candle.Low - prev.Low) < atr * LiqEqTolAtr)
				PushLiq(_extraSsl, Math.Min(candle.Low, prev.Low), bar, false, "EQL");
		}

		// -- Zonas EQH/EQL visuales con filtro RSI (bloque independiente del script original) --
		if (!ShowEqZones || bar < 1)
			return;

		var v = (Math.Abs(candle.High - GetCandle(bar - 1).High) + Math.Abs(candle.Low - GetCandle(bar - 1).Low)) / 2m;
		_varSmooth = !_varInit ? v : Ema(_varSmooth, v, 500);
		_varInit = true;

		var rsi = Rsi(bar);
		var prevC = GetCandle(bar - 1);

		var eqh = Math.Abs(candle.High - prevC.High) < _varSmooth * EqTolerance;
		var eql = Math.Abs(candle.Low - prevC.Low) < _varSmooth * EqTolerance;

		var rsiOk_h = !EqUseRsiFilter || rsi > 50 + EqRsiThreshold;
		var rsiOk_l = !EqUseRsiFilter || rsi < 50 - EqRsiThreshold;

		if (eqh && rsiOk_h)
			_eqZones.Add(new EqZone { Bar = bar, LevelPrice = Math.Max(candle.High, prevC.High), BodyPrice = Math.Max(Math.Max(candle.Open, prevC.Open), Math.Max(candle.Close, prevC.Close)), IsHigh = true });

		if (eql && rsiOk_l)
			_eqZones.Add(new EqZone { Bar = bar, LevelPrice = Math.Min(candle.Low, prevC.Low), BodyPrice = Math.Min(Math.Min(candle.Open, prevC.Open), Math.Min(candle.Close, prevC.Close)), IsHigh = false });

		foreach (var z in _eqZones)
		{
			if (z.Mitigated)
				continue;

			var age = bar - z.Bar;
			var isBody = EqMitigation == SweepModeType.Body;

			bool remove;

			if (z.IsHigh)
			{
				var crossBody = candle.Close > z.LevelPrice;
				var crossConfirmed = crossBody && prevC.Close > z.LevelPrice;
				var crossWick = candle.High > z.LevelPrice;
				remove = isBody ? (EqAllowRejection ? crossConfirmed : crossBody) : crossWick;
			}
			else
			{
				var crossBody = candle.Close < z.LevelPrice;
				var crossConfirmed = crossBody && prevC.Close < z.LevelPrice;
				var crossWick = candle.Low < z.LevelPrice;
				remove = isBody ? (EqAllowRejection ? crossConfirmed : crossBody) : crossWick;
			}

			if (remove || age > EqExpiryAge)
				z.Mitigated = true;
		}

		_eqZones.RemoveAll(z => z.Mitigated && bar - z.Bar > 2);
	}

	private decimal Atr(int bar)
	{
		var candle = GetCandle(bar);

		if (bar == 0)
			return candle.High - candle.Low;

		var prevClose = GetCandle(bar - 1).Close;
		var tr = Math.Max(candle.High - candle.Low, Math.Max(Math.Abs(candle.High - prevClose), Math.Abs(candle.Low - prevClose)));
		var n = Math.Min(bar + 1, AtrPeriod);

		// Wilder simplificado recalculado sobre la marcha (aceptable para el filtro de tolerancia).
		return ((n - 1) * (candle.High - candle.Low) + tr) / n;
	}

	private decimal Rsi(int bar)
	{
		if (bar == 0)
		{
			_rsiAvgGain = _rsiAvgLoss = 0;
			_rsiInit = true;
			return 50;
		}

		var change = GetCandle(bar).Close - GetCandle(bar - 1).Close;
		var gain = Math.Max(change, 0);
		var loss = Math.Max(-change, 0);
		const int period = 14;

		if (!_rsiInit)
		{
			_rsiAvgGain = gain;
			_rsiAvgLoss = loss;
			_rsiInit = true;
		}
		else
		{
			_rsiAvgGain = (_rsiAvgGain * (period - 1) + gain) / period;
			_rsiAvgLoss = (_rsiAvgLoss * (period - 1) + loss) / period;
		}

		if (_rsiAvgLoss == 0)
			return 100;

		var rs = _rsiAvgGain / _rsiAvgLoss;
		return 100 - 100 / (1 + rs);
	}

	private static decimal Ema(decimal prev, decimal value, int length)
	{
		var k = 2m / (length + 1);
		return prev + k * (value - prev);
	}

	#endregion

	#region BOS / CHoCH — estructura de mercado

	private void StepStructure(int bar, IndicatorCandle candle)
	{
		var len = StructPivotLength;

		if (bar >= 2 * len)
		{
			var pivotBar = bar - len;
			var pivotCandle = GetCandle(pivotBar);

			var isPh = true;
			var isPl = true;

			for (var i = pivotBar - len; i <= pivotBar + len; i++)
			{
				if (i == pivotBar || i < 0)
					continue;

				var c = GetCandle(i);

				if (c.High >= pivotCandle.High)
					isPh = false;

				if (c.Low <= pivotCandle.Low)
					isPl = false;
			}

			if (isPh)
				_swingHigh = new SwingPoint { Bar = pivotBar, Price = pivotCandle.High };

			if (isPl)
				_swingLow = new SwingPoint { Bar = pivotBar, Price = pivotCandle.Low };
		}

		if (_swingHigh != null && candle.Close > _swingHigh.Price)
		{
			var isChoch = _trend == -1;
			_structBreaks.Add(new StructBreak { FromBar = _swingHigh.Bar, ToBar = bar, Price = _swingHigh.Price, IsBull = true, IsChoch = isChoch });
			_trend = 1;

			if (isChoch && AlertOnChoch)
				AddAlert(AlertFile, InstrumentInfo.Instrument, $"CHoCH alcista @ {candle.Close}", AlertBgColor, AlertForeColor);
			else if (!isChoch && AlertOnBos)
				AddAlert(AlertFile, InstrumentInfo.Instrument, $"BOS alcista @ {candle.Close}", AlertBgColor, AlertForeColor);

			_swingHigh = null;
		}

		if (_swingLow != null && candle.Close < _swingLow.Price)
		{
			var isChoch = _trend == 1;
			_structBreaks.Add(new StructBreak { FromBar = _swingLow.Bar, ToBar = bar, Price = _swingLow.Price, IsBull = false, IsChoch = isChoch });
			_trend = -1;

			if (isChoch && AlertOnChoch)
				AddAlert(AlertFile, InstrumentInfo.Instrument, $"CHoCH bajista @ {candle.Close}", AlertBgColor, AlertForeColor);
			else if (!isChoch && AlertOnBos)
				AddAlert(AlertFile, InstrumentInfo.Instrument, $"BOS bajista @ {candle.Close}", AlertBgColor, AlertForeColor);

			_swingLow = null;
		}

		while (_structBreaks.Count > 300)
			_structBreaks.RemoveAt(0);
	}

	#endregion

	#region 12) PD Array Delivery — touch HTF FVG + IFVG del TF actual

	private void StepPdaModel(int bar, IndicatorCandle candle, bool ifvgFired, int ifvgDir)
	{
		if (!EnablePda)
			return;

		bool Touch(MtfNearestFvg z) => z != null && candle.High >= z.Bottom && candle.Low <= z.Top;

		var touched = Touch(_nearest5) || Touch(_nearest15) || Touch(_nearest60) || Touch(_nearest240);

		if (touched)
			_pdaTouchBar = bar;

		if (_pdaTouchBar >= 0 && bar - _pdaTouchBar > PdaMaxWait)
			_pdaTouchBar = -1;

		var validWindow = _pdaTouchBar >= 0 && bar - _pdaTouchBar <= PdaMaxWait;

		if (!(ifvgFired && validWindow))
			return;

		var entry = candle.Close;
		var sl = ifvgDir == 1
			? (_swingLow?.Price ?? candle.Low)
			: (_swingHigh?.Price ?? candle.High);

		var risk = Math.Abs(entry - sl);

		if (risk <= 0)
			return;

		var tp = ifvgDir == 1 ? entry + risk * PdaRiskReward : entry - risk * PdaRiskReward;

		_pdaSignals.Add(new PdaSignal { Bar = bar, Dir = ifvgDir, Entry = entry, Sl = sl, Tp = tp });

		while (_pdaSignals.Count > PdaMaxSignals)
			_pdaSignals.RemoveAt(0);

		if (AlertOnPda)
			AddAlert(AlertFile, InstrumentInfo.Instrument, (ifvgDir == 1 ? "BUY" : "SELL") + " PD Array Delivery IFVG", AlertBgColor, AlertForeColor);

		_pdaTouchBar = -1;
	}

	#endregion

	#region OnRender

	protected override void OnRender(RenderContext context, DrawingLayouts layout)
	{
		if (ChartInfo is null)
			return;

		DrawKillzones(context);
		DrawLiquidity(context, _bslPool);
		DrawLiquidity(context, _sslPool);
		DrawLiquidity(context, _extraBsl);
		DrawLiquidity(context, _extraSsl);
		DrawFvgZones(context);
		DrawMtfFvg(context);
		DrawStructure(context);
		DrawEqZones(context);
		DrawEntrySignals(context);
		DrawPdaSignals(context);
		DrawCpiLines(context);

		if (ShowCheckTable)
			DrawCheckTable(context);
	}

	private Rectangle PriceRect(int xLeft, int xRight, decimal priceTop, decimal priceBottom)
	{
		var y = ChartInfo.GetYByPrice(priceTop, false);
		var y2 = ChartInfo.GetYByPrice(priceBottom, false);
		return new Rectangle(Math.Min(xLeft, xRight), Math.Min(y, y2), Math.Abs(xRight - xLeft), Math.Abs(y2 - y));
	}

	private static Color WithAlpha(Color c, int alpha) => Color.FromArgb(alpha, c.R, c.G, c.B);

	private void DrawKillzones(RenderContext context)
	{
		if (!ShowKzBoxes)
			return;

		var pen = new RenderPen(Color.FromArgb(120, 128, 128, 128), 1);

		foreach (var b in _kzBoxes)
		{
			if (b.RightBar < FirstVisibleBarNumber || b.LeftBar > LastVisibleBarNumber)
				continue;

			var x = ChartInfo.GetXByBar(b.LeftBar);
			var x2 = ChartInfo.GetXByBar(b.RightBar);
			var rec = PriceRect(x, x2, b.Top, b.Bottom);
			context.DrawFillRectangle(pen, WithAlpha(b.Color, 38), rec);
			context.DrawString(b.Name, _labelFont.RenderObject, b.Color, rec.X, rec.Y);
		}
	}

	private void DrawLiquidity(RenderContext context, List<LiqLevel> pool)
	{
		if (!ShowLiqLines)
			return;

		var pen = new RenderPen(Color.Black, 1);

		foreach (var l in pool)
		{
			if (l.Bar > LastVisibleBarNumber)
				continue;

			var x = ChartInfo.GetXByBar(l.Bar);
			var y = ChartInfo.GetYByPrice(l.Price, false);
			var x2 = l.Valid ? ChartArea.Right : ChartInfo.GetXByBar(l.Bar);
			context.DrawLine(pen, x, y, x2, y);

			var text = l.Tag + (l.Valid ? "" : " ✕");
			context.DrawString(text, _labelFont.RenderObject, Color.Black, x, y - 12);
		}
	}

	private void DrawFvgZones(RenderContext context)
	{
		if (!ShowFvg)
			return;

		foreach (var z in _fvgZones)
		{
			if (z.StartBar > LastVisibleBarNumber)
				continue;
			if (z.EndBar > 0 && z.EndBar < FirstVisibleBarNumber)
				continue;

			var x = ChartInfo.GetXByBar(z.StartBar);
			var x2 = z.Active ? ChartArea.Right : ChartInfo.GetXByBar(Math.Max(z.EndBar, z.StartBar));
			var rec = PriceRect(x, x2, z.Top, z.Bottom);

			var color = !z.Active && z.InvertedOnBar >= 0
				? WithAlpha(IfvgColor, 110)
				: WithAlpha(z.IsBull ? FvgBullColor : FvgBearColor, 65);

			var penColor = z.IsBull ? FvgBullColor : FvgBearColor;
			context.DrawFillRectangle(new RenderPen(penColor, 1), color, rec);
			context.DrawString(z.InvertedOnBar >= 0 ? "IFVG" : "FVG", _labelFont.RenderObject, penColor, rec.X, rec.Y);
		}
	}

	private void DrawMtfFvg(RenderContext context)
	{
		if (!ShowMtfFvgBoxes)
			return;

		void DrawOne(MtfNearestFvg z, string label)
		{
			if (z is null || z.LeftBar > LastVisibleBarNumber)
				return;

			var x = ChartInfo.GetXByBar(z.LeftBar);
			var rec = PriceRect(x, ChartArea.Right, z.Top, z.Bottom);
			context.DrawFillRectangle(new RenderPen(Color.Gray, 1), WithAlpha(Color.Gray, 255 - (MtfBoxTransparency * 255 / 100)), rec);
			context.DrawString(label, _labelFont.RenderObject, Color.Gray, ChartArea.Right - 60, (rec.Top + rec.Bottom) / 2);
		}

		DrawOne(_nearest5, "5m");
		DrawOne(_nearest15, "15m");
		DrawOne(_nearest60, "1H");
		DrawOne(_nearest240, "4H");
	}

	private void DrawStructure(RenderContext context)
	{
		foreach (var s in _structBreaks)
		{
			if (s.ToBar < FirstVisibleBarNumber || s.FromBar > LastVisibleBarNumber)
				continue;

			var color = s.IsBull ? StructBullColor : StructBearColor;
			var x = ChartInfo.GetXByBar(s.FromBar);
			var x2 = ChartInfo.GetXByBar(s.ToBar);
			var y = ChartInfo.GetYByPrice(s.Price, false);
			context.DrawLine(new RenderPen(color, 1), x, y, x2, y);

			if (ShowStructLabels)
			{
				var text = s.IsChoch ? "CHoCH" : "BOS";
				var mid = (x + x2) / 2;
				context.DrawString(text, _labelFont.RenderObject, color, mid, y - 14);
			}
		}
	}

	private void DrawEqZones(RenderContext context)
	{
		if (!ShowEqZones)
			return;

		foreach (var z in _eqZones)
		{
			if (z.Bar > LastVisibleBarNumber)
				continue;

			var color = z.IsHigh ? EqBearColor : EqBullColor;
			var x = ChartInfo.GetXByBar(Math.Max(z.Bar - 1, 0));
			var x2 = z.Mitigated ? ChartInfo.GetXByBar(Math.Min(z.Bar + 1, LastVisibleBarNumber)) : ChartArea.Right;
			var rec = PriceRect(x, x2, Math.Max(z.LevelPrice, z.BodyPrice), Math.Min(z.LevelPrice, z.BodyPrice));
			context.DrawFillRectangle(new RenderPen(color, 1), WithAlpha(color, 60), rec);

			var lineY = ChartInfo.GetYByPrice(z.LevelPrice, false);
			context.DrawLine(new RenderPen(color, 1), x, lineY, x2, lineY);
		}
	}

	private void DrawPdaSignals(RenderContext context) =>
		DrawSignalList(context, _pdaSignals, PdaBuyColor, PdaSellColor, "BUY PD Array IFVG", "SELL PD Array IFVG");

	private void DrawEntrySignals(RenderContext context) =>
		DrawSignalList(context, _entrySignals, DefaultColors.Green, DefaultColors.Red, "▲ LONG (IFVG)", "▼ SHORT (IFVG)");

	private void DrawSignalList(RenderContext context, List<PdaSignal> signals, Color buyColor, Color sellColor, string buyText, string sellText)
	{
		foreach (var s in signals)
		{
			if (s.Bar > LastVisibleBarNumber)
				continue;

			var color = s.Dir == 1 ? buyColor : sellColor;
			var x = ChartInfo.GetXByBar(s.Bar);
			var x2 = ChartInfo.GetXByBar(Math.Min(s.Bar + SlTpExtBars, LastVisibleBarNumber));

			if (ShowSlTp)
			{
				var yEn = ChartInfo.GetYByPrice(s.Entry, false);
				var ySl = ChartInfo.GetYByPrice(s.Sl, false);
				var yTp = ChartInfo.GetYByPrice(s.Tp, false);
				context.DrawLine(new RenderPen(Color.FromArgb(150, 255, 255, 255), 1), x, yEn, x2, yEn);
				context.DrawLine(new RenderPen(Color.Red, 1), x, ySl, x2, ySl);
				context.DrawLine(new RenderPen(Color.Green, 1), x, yTp, x2, yTp);
			}

			if (ShowSignals)
			{
				var y = ChartInfo.GetYByPrice(s.Dir == 1 ? Math.Min(s.Entry, s.Sl) : Math.Max(s.Entry, s.Sl), false);
				context.DrawString(s.Dir == 1 ? buyText : sellText, _labelFont.RenderObject, color, x, y + (s.Dir == 1 ? 4 : -18));
			}
		}
	}

	private void DrawCpiLines(RenderContext context)
	{
		if (!CpiEnabled)
			return;

		var current = GetCandle(CurrentBar - 1).Close;
		var factor = CpiDistanceUnit == DistanceUnitType.Points ? 1m : InstrumentInfo.TickSize;

		var padDist = CpiPad * factor;
		var tpDist = CpiTp * factor;
		var slDist = CpiSl * factor;

		var buyPad = current + padDist;
		var sellPad = current - padDist;
		var buyTp = buyPad + tpDist;
		var buySl = buyPad - slDist;
		var sellTp = sellPad - tpDist;
		var sellSl = sellPad + slDist;

		var x = ChartInfo.GetXByBar(CurrentBar - 1);
		var x2 = ChartArea.Right;

		void Line(decimal price, Color color, string text)
		{
			var y = ChartInfo.GetYByPrice(price, false);
			context.DrawLine(new RenderPen(color, 2, System.Drawing.Drawing2D.DashStyle.Dot), x, y, x2, y);

			if (CpiShowLabels)
				context.DrawString(text, _labelFont.RenderObject, color, x2 - 80, y - 14);
		}

		Line(buyPad, CpiBuyColor, "Buy Stop");
		Line(buyTp, CpiBuyColor, "Sell Limit");
		Line(buySl, CpiBuyColor, "SL");
		Line(sellPad, CpiSellColor, "Sell Stop");
		Line(sellTp, CpiSellColor, "Buy Limit");
		Line(sellSl, CpiSellColor, "SL");
		Line(current, CpiMidColor, "Precio");
	}

	private void DrawCheckTable(RenderContext context)
	{
		var score = (_checkLiquidity ? 1 : 0) + (_checkHtf ? 1 : 0) + (_checkVolume ? 1 : 0) +
					(_checkIfvg ? 1 : 0) + (_checkTargets ? 1 : 0) + (_checkSmt ? 1 : 0);

		var lines = new[]
		{
			$"Grado: {GradeText(score)} ({score}/6)",
			(_checkLiquidity ? "✓" : "✕") + " Liquidez barrida",
			(_checkHtf ? "✓" : "✕") + " HTF PDA delivery",
			(_checkVolume ? "✓" : "✕") + " Volumen",
			(_checkIfvg ? "✓" : "✕") + " IFVG",
			(_checkTargets ? "✓" : "✕") + " Objetivos claros",
			(_checkSmt ? "✓" : "✕") + " SMT (manual)"
		};

		var lineHeight = 18;
		var width = 190;
		var height = lineHeight * lines.Length + 10;

		int left, top;

		switch (TablePosition)
		{
			case TablePosType.TopLeft:
				left = ChartArea.Left + 10; top = ChartArea.Top + 10; break;
			case TablePosType.BottomLeft:
				left = ChartArea.Left + 10; top = ChartArea.Bottom - height - 10; break;
			case TablePosType.BottomRight:
				left = ChartArea.Right - width - 10; top = ChartArea.Bottom - height - 10; break;
			default:
				left = ChartArea.Right - width - 10; top = ChartArea.Top + 10; break;
		}

		var bgRect = new Rectangle(left, top, width, height);
		context.DrawFillRectangle(new RenderPen(Color.FromArgb(180, 30, 30, 30), 1), Color.FromArgb(180, 20, 20, 20), bgRect);

		for (var i = 0; i < lines.Length; i++)
		{
			var color = i == 0 ? GradeColor(score) : Color.White;
			context.DrawString(lines[i], _tableFont.RenderObject, color, left + 8, top + 5 + i * lineHeight);
		}
	}

	#endregion
}
