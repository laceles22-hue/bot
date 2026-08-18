// =====================================================================
// NWOG / NDOG — New Week / New Day Opening Gap  (puerto para ATAS)
// ---------------------------------------------------------------------
// Adaptación a C# / ATAS del indicador Pine Script v5 "NWOG/NDOG
// (cryptonnnite)" de © cryptonnnite, publicado bajo Mozilla Public
// License 2.0 (https://mozilla.org/MPL/2.0/). Este archivo conserva el
// mismo espíritu de licencia: es una obra derivada, así que si lo
// redistribuís mantené este aviso y el crédito al autor original.
//
// Qué dibuja:
//   NWOG: el "gap" entre el cierre de la última vela de la semana
//         anterior y la apertura de la primera vela de la semana nueva.
//   NDOG: lo mismo pero entre el cierre del día anterior y la apertura
//         del día nuevo.
//
// Diferencia clave frente al original de TradingView:
//   Pine puede pedir datos de otro timeframe con request.security()
//   (por eso el script original arma el gap "5pm-6pm" consultando 1D/1W
//   aunque estés parado en un gráfico intradiario). ATAS no tiene un
//   equivalente directo a eso dentro de un único indicador, así que este
//   puerto calcula el gap directamente con las velas del propio gráfico
//   en el instante en que cambia el día/semana (equivalente al modo
//   "5pm to 6pm GAP" del original, que es el que se usa en la práctica
//   para futuros/forex). Para que el cálculo sea correcto, usalo en un
//   gráfico intradiario (M1–H1); en un gráfico diario o semanal no hay
//   granularidad suficiente para detectar el gap.
//
// Nota sobre compatibilidad de SDK:
//   Los nombres de tipos de dibujo (RenderPen, RenderFont,
//   RenderDashStyle, los overloads de FillRectangle/DrawString) siguen
//   el patrón estándar que usan los indicadores custom de ATAS
//   (namespaces ATAS.Indicators + OFT.Rendering.*). Puede que tu versión
//   exacta del SDK tenga algún overload levemente distinto: compilá este
//   archivo dentro del editor de indicadores de ATAS (botón "Compilar")
//   y si marca algún error de firma, normalmente es un cambio de una
//   sola línea. Pegámelo y lo ajusto.
//
// Instalación:
//   1. Abrí ATAS → Indicadores personalizados (Custom indicators) →
//      "Nuevo" / "New".
//   2. Pegá todo este archivo, compilá.
//   3. Agregalo al gráfico desde la lista de indicadores como
//      "NWOG/NDOG (cryptonnnite)".
// =====================================================================

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Drawing;
using System.Globalization;
using System.Windows.Media;
using ATAS.Indicators;
using OFT.Rendering.Context;
using OFT.Rendering.Tools;

namespace ATAS.Indicators.Custom
{
    public enum GapLineStyle
    {
        Solid,
        Dashed,
        Dotted
    }

    public enum GapLabelSize
    {
        Small,
        Medium,
        Large
    }

    [DisplayName("NWOG/NDOG (cryptonnnite)")]
    [Category("Mis indicadores")]
    public class NwogNdogIndicator : Indicator
    {
        #region Nested types

        private class Gap
        {
            public decimal High;
            public decimal Low;
            public DateTime Start;
            public int StartBar;
            public int EndBar;
        }

        #endregion

        #region Fields

        private readonly List<Gap> _nwogGaps = new List<Gap>();
        private readonly List<Gap> _ndogGaps = new List<Gap>();

        private int _lastWeekKey = int.MinValue;

        private decimal? _eventHorizonLevel;
        private int _eventHorizonStartBar;

        private RenderFont _labelFont = new RenderFont("Arial", 9);
        private RenderFont _priceLabelFont = new RenderFont("Arial", 8);

        #endregion

        #region NWOG settings

        [Display(Name = "Mostrar NWOG", GroupName = "NWOG - Nueva Semana", Order = 100)]
        public bool ShowNwog { get; set; } = true;

        [Display(Name = "Etiqueta", GroupName = "NWOG - Nueva Semana", Order = 101)]
        public string NwogLabel { get; set; } = "NWOG";

        [Display(Name = "Color de relleno", GroupName = "NWOG - Nueva Semana", Order = 102)]
        public Color NwogBg { get; set; } = Color.FromArgb(85, 164, 249, 73);

        [Display(Name = "Color de relleno (gaps previos)", GroupName = "NWOG - Nueva Semana", Order = 103)]
        public Color PreviousNwogBg { get; set; } = Color.FromArgb(90, 0, 0, 0);

        [Display(Name = "Cantidad de NWOG previos", GroupName = "NWOG - Nueva Semana", Order = 104)]
        [Range(1, 100)]
        public int NwogsAmount { get; set; } = 4;

        [Display(Name = "Extender todos los NWOG previos", GroupName = "NWOG - Nueva Semana", Order = 105)]
        public bool ExtendAllNwogs { get; set; } = false;

        [Display(Name = "Extender el NWOG actual hasta la última vela", GroupName = "NWOG - Nueva Semana", Order = 106)]
        public bool ExtendCurrentNwog { get; set; } = true;

        [Display(Name = "Mostrar C.E. (punto medio)", GroupName = "NWOG - Nueva Semana", Order = 107)]
        public bool ShowNwogCe { get; set; } = false;

        [Display(Name = "Estilo de línea C.E.", GroupName = "NWOG - Nueva Semana", Order = 108)]
        public GapLineStyle NwogCeStyle { get; set; } = GapLineStyle.Dotted;

        [Display(Name = "Color de línea C.E.", GroupName = "NWOG - Nueva Semana", Order = 109)]
        public Color NwogCeColor { get; set; } = Colors.Blue;

        [Display(Name = "Color de etiqueta", GroupName = "NWOG - Nueva Semana", Order = 110)]
        public Color NwogLabelColor { get; set; } = Colors.Black;

        #endregion

        #region NDOG settings

        [Display(Name = "Mostrar NDOG", GroupName = "NDOG - Nuevo Día", Order = 200)]
        public bool ShowNdog { get; set; } = true;

        [Display(Name = "Etiqueta", GroupName = "NDOG - Nuevo Día", Order = 201)]
        public string NdogLabel { get; set; } = "NDOG";

        [Display(Name = "Color de relleno", GroupName = "NDOG - Nuevo Día", Order = 202)]
        public Color NdogBg { get; set; } = Color.FromArgb(85, 255, 235, 59);

        [Display(Name = "Color de relleno (gaps previos)", GroupName = "NDOG - Nuevo Día", Order = 203)]
        public Color PreviousNdogBg { get; set; } = Color.FromArgb(90, 0, 0, 0);

        [Display(Name = "Cantidad de NDOG previos", GroupName = "NDOG - Nuevo Día", Order = 204)]
        [Range(1, 100)]
        public int NdogsAmount { get; set; } = 4;

        [Display(Name = "Extender todos los NDOG previos", GroupName = "NDOG - Nuevo Día", Order = 205)]
        public bool ExtendAllNdogs { get; set; } = false;

        [Display(Name = "Extender el NDOG actual hasta la última vela", GroupName = "NDOG - Nuevo Día", Order = 206)]
        public bool ExtendCurrentNdog { get; set; } = true;

        [Display(Name = "Mostrar C.E. (punto medio)", GroupName = "NDOG - Nuevo Día", Order = 207)]
        public bool ShowNdogCe { get; set; } = false;

        [Display(Name = "Estilo de línea C.E.", GroupName = "NDOG - Nuevo Día", Order = 208)]
        public GapLineStyle NdogCeStyle { get; set; } = GapLineStyle.Dotted;

        [Display(Name = "Color de línea C.E.", GroupName = "NDOG - Nuevo Día", Order = 209)]
        public Color NdogCeColor { get; set; } = Colors.Blue;

        [Display(Name = "Color de etiqueta", GroupName = "NDOG - Nuevo Día", Order = 210)]
        public Color NdogLabelColor { get; set; } = Colors.Black;

        #endregion

        #region General settings

        [Display(Name = "Event Horizon", GroupName = "General", Order = 300,
            Description = "Punto medio entre dos NWOG consecutivos cuando queda un hueco entre ellos.")]
        public bool EventHorizon { get; set; } = false;

        [Display(Name = "Estilo de línea Event Horizon", GroupName = "General", Order = 301)]
        public GapLineStyle EventHorizonStyle { get; set; } = GapLineStyle.Dashed;

        [Display(Name = "Color Event Horizon", GroupName = "General", Order = 302)]
        public Color EventHorizonColor { get; set; } = Colors.Red;

        [Display(Name = "Mostrar etiquetas de precio", GroupName = "General", Order = 303)]
        public bool ShowPriceLabels { get; set; } = false;

        [Display(Name = "Color de etiquetas de precio", GroupName = "General", Order = 304)]
        public Color PriceLabelColor { get; set; } = Colors.Black;

        [Display(Name = "Mostrar fecha en la etiqueta", GroupName = "General", Order = 305)]
        public bool ShowDateLabel { get; set; } = true;

        [Display(Name = "Formato de fecha", GroupName = "General", Order = 306)]
        public string DateLabelFormat { get; set; } = "dd.MM";

        #endregion

        public NwogNdogIndicator()
            : base(true)
        {
            ((ValueDataSeries)DataSeries[0]).VisualType = VisualMode.Hide;
        }

        protected override void OnCalculate(int bar, decimal value)
        {
            if (bar == 0)
            {
                _nwogGaps.Clear();
                _ndogGaps.Clear();
                _lastWeekKey = int.MinValue;
                _eventHorizonLevel = null;
                return;
            }

            var candle = GetCandle(bar);
            var prevCandle = GetCandle(bar - 1);

            var isNewDay = candle.Time.Date != prevCandle.Time.Date;
            var weekKey = GetWeekKey(candle.Time);
            var isNewWeek = weekKey != _lastWeekKey;
            _lastWeekKey = weekKey;

            if (isNewWeek && ShowNwog)
            {
                CreateGap(_nwogGaps, bar, candle, prevCandle, NwogsAmount);
                UpdateEventHorizon();
            }

            // Evita duplicar el mismo hueco como NDOG cuando ya se dibujó
            // como NWOG (equivalente al chequeo "dayofweek != sunday" del
            // original).
            if (isNewDay && ShowNdog && !(isNewWeek && ShowNwog))
                CreateGap(_ndogGaps, bar, candle, prevCandle, NdogsAmount);

            if (ExtendCurrentNwog && _nwogGaps.Count > 0)
                _nwogGaps[_nwogGaps.Count - 1].EndBar = bar;

            if (ExtendCurrentNdog && _ndogGaps.Count > 0)
                _ndogGaps[_ndogGaps.Count - 1].EndBar = bar;

            if (ExtendAllNwogs)
                foreach (var gap in _nwogGaps)
                    gap.EndBar = bar;

            if (ExtendAllNdogs)
                foreach (var gap in _ndogGaps)
                    gap.EndBar = bar;
        }

        protected override void OnRender(RenderContext context, DrawingLayouts layout)
        {
            if (layout != DrawingLayouts.Final || ChartInfo == null)
                return;

            if (ShowNwog)
                RenderGaps(context, _nwogGaps, NwogBg, PreviousNwogBg, NwogLabel, ShowNwogCe, NwogCeColor,
                    NwogCeStyle, NwogLabelColor, ExtendAllNwogs);

            if (ShowNdog)
                RenderGaps(context, _ndogGaps, NdogBg, PreviousNdogBg, NdogLabel, ShowNdogCe, NdogCeColor,
                    NdogCeStyle, NdogLabelColor, ExtendAllNdogs);

            if (EventHorizon && _eventHorizonLevel.HasValue)
                RenderEventHorizon(context);
        }

        #region Helpers

        private static void CreateGap(List<Gap> gaps, int bar, IndicatorCandle candle, IndicatorCandle prevCandle,
            int keepAmount)
        {
            var gap = new Gap
            {
                High = Math.Max(prevCandle.Close, candle.Open),
                Low = Math.Min(prevCandle.Close, candle.Open),
                Start = candle.Time,
                StartBar = bar,
                EndBar = bar
            };

            gaps.Add(gap);

            while (gaps.Count > keepAmount)
                gaps.RemoveAt(0);
        }

        private void UpdateEventHorizon()
        {
            _eventHorizonLevel = null;

            if (!EventHorizon || _nwogGaps.Count < 2)
                return;

            var current = _nwogGaps[_nwogGaps.Count - 1];
            var previous = _nwogGaps[_nwogGaps.Count - 2];

            if (current.Low > previous.High)
                _eventHorizonLevel = (current.Low + previous.High) / 2m;
            else if (previous.Low > current.High)
                _eventHorizonLevel = (previous.Low + current.High) / 2m;

            _eventHorizonStartBar = current.StartBar;
        }

        private void RenderGaps(RenderContext context, List<Gap> gaps, Color bgColor, Color previousBgColor,
            string label, bool showCe, Color ceColor, GapLineStyle ceStyle, Color labelColor, bool dimPrevious)
        {
            for (var i = 0; i < gaps.Count; i++)
            {
                var gap = gaps[i];
                var isPrevious = dimPrevious && i < gaps.Count - 1;

                var x1 = ChartInfo.GetXByBar(gap.StartBar, false);
                var x2 = ChartInfo.GetXByBar(gap.EndBar + 1, false);
                var yHigh = ChartInfo.GetYByPrice(gap.High, false);
                var yLow = ChartInfo.GetYByPrice(gap.Low, false);

                if (x2 <= x1)
                    x2 = x1 + 1;

                var rect = new Rectangle(x1, yHigh, x2 - x1, Math.Max(1, yLow - yHigh));
                context.FillRectangle(ToDrawingColor(isPrevious ? previousBgColor : bgColor), rect);

                var text = ShowDateLabel
                    ? string.Format("{0} | {1}", gap.Start.ToString(DateLabelFormat, CultureInfo.InvariantCulture), label)
                    : label;

                if (!string.IsNullOrEmpty(text))
                    context.DrawString(text, _labelFont, ToDrawingColor(labelColor), x1 + 4, yHigh + 2);

                if (showCe)
                {
                    var ceY = ChartInfo.GetYByPrice((gap.High + gap.Low) / 2m, false);
                    using (var pen = new RenderPen(ToDrawingColor(ceColor), 1, ToDashStyle(ceStyle)))
                        context.DrawLine(pen, x1, ceY, x2, ceY);
                }

                if (ShowPriceLabels)
                {
                    context.DrawString(FormatPrice(gap.High), _priceLabelFont, ToDrawingColor(PriceLabelColor), x2 + 2, yHigh - 8);
                    context.DrawString(FormatPrice(gap.Low), _priceLabelFont, ToDrawingColor(PriceLabelColor), x2 + 2, yLow - 8);
                }
            }
        }

        private void RenderEventHorizon(RenderContext context)
        {
            var x1 = ChartInfo.GetXByBar(_eventHorizonStartBar, false);
            var x2 = ChartInfo.GetXByBar(CurrentBar, false);
            var y = ChartInfo.GetYByPrice(_eventHorizonLevel.Value, false);

            using (var pen = new RenderPen(ToDrawingColor(EventHorizonColor), 1, ToDashStyle(EventHorizonStyle)))
                context.DrawLine(pen, x1, y, x2, y);
        }

        private static string FormatPrice(decimal price)
        {
            return price.ToString("0.#####", CultureInfo.InvariantCulture);
        }

        private static System.Drawing.Color ToDrawingColor(Color color)
        {
            return System.Drawing.Color.FromArgb(color.A, color.R, color.G, color.B);
        }

        private static RenderDashStyle ToDashStyle(GapLineStyle style)
        {
            switch (style)
            {
                case GapLineStyle.Dashed:
                    return RenderDashStyle.Dash;
                case GapLineStyle.Dotted:
                    return RenderDashStyle.Dot;
                default:
                    return RenderDashStyle.Solid;
            }
        }

        private static int GetWeekKey(DateTime time)
        {
            var calendar = CultureInfo.InvariantCulture.Calendar;
            var week = calendar.GetWeekOfYear(time, CalendarWeekRule.FirstFourDayWeek, DayOfWeek.Monday);
            return time.Year * 100 + week;
        }

        #endregion
    }
}
