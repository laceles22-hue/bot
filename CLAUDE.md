# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository overview

`bot` is a small collection of **TradingView Pine Script indicators**, not a bot in the
traditional sense (no runtime process, no build system, no package manager). There is currently
one indicator:

- `indicators/fvg_ifvg.pine` — a Pine Script v6 `indicator()` that plots Fair Value Gaps (FVG),
  Inverse Fair Value Gaps (IFVG), previous-day high/low (PDH/PDL), and previous NY/London session
  high/low, all as overlay boxes/lines/labels on a TradingView chart.

There is no server, CLI, or application code — everything here is authored to be pasted into the
TradingView Pine Editor and run against live/historical chart data on tradingview.com.

## Codebase structure

```
indicators/
  fvg_ifvg.pine    # FVG & IFVG indicator (Pine Script v6)
```

As more indicators/strategies are added, keep each one in its own `.pine` file under
`indicators/` (or a `strategies/` directory if a `strategy()`-type script is added, since Pine
Script strategies and indicators are distinct script types).

## `indicators/fvg_ifvg.pine` — what it does

Single-file Pine Script v6 indicator, `overlay=true`. Source comments and all UI input labels are
in **Spanish** — keep new comments/inputs in that file consistent with that (Spanish), unless the
user asks otherwise.

Major sections, in file order:
1. **Inputs** (grouped via `group=` into Pine's input panel): FVG display/colors, IFVG
   display/colors, gap-size filter (ATR-based), general display options, mitigation mode
   (wick-touch vs. candle-close-through), PDH/PDL display, previous NY session H/L, previous
   London session H/L.
2. **`type Zone`** — a UDT bundling a `box`, optional midline `line`, optional `label`, and the
   zone's `top`/`bottom` price levels. Used for FVG and IFVG zones alike.
3. **Zone arrays** (`bullFvgZones`, `bearFvgZones`, `bullIfvgZones`, `bearIfvgZones`) — `var
   array<Zone>` that persist across bars and are capped at `maxZonesPerSide` (oldest zone
   `array.shift()`-ed and its drawing objects deleted when the cap is exceeded).
4. **FVG detection** — classic 3-candle pattern: bullish gap when `low > high[2]`, bearish gap
   when `high < low[2]`. Optionally filtered by a minimum gap size in ATR multiples
   (`minGapAtrMult`, `atrLen`).
5. **Zone creation/management/mitigation loops** — one block per zone type (bull FVG, bear FVG,
   bull IFVG, bear IFVG). Each bar: optionally extend the box's right edge to the current bar
   (`extendRight`), then check `closedThrough()` to decide if the zone is mitigated. Mitigating a
   FVG deletes (or grays out, if `keepMitigatedFvg`) the FVG box and spawns an opposite-direction
   IFVG zone in its place. Mitigating an IFVG (when `deleteIfvgOnFill`) just deletes it.
6. **PDH/PDL** — previous day's high/low via `request.security(..., "D", high[1]/low[1], ...)`,
   redrawn once per new daily bar.
7. **Previous NY session H/L** and **previous London session H/L** — near-identical blocks that
   track a running high/low while `time(timeframe.period, <session>, <timezone>)` is non-`na`,
   and "close" (freeze + draw) the range the bar after the session ends. Each session's day
   boundary is tracked separately (`sessDayId`/`ldnDayId`) so a session that doesn't cleanly close
   on non-24h data (e.g. overnight futures) still resets instead of accumulating multiple days'
   range into one line — see the fix history below.
8. **Alerts** — `alertcondition()` for new bullish/bearish FVG formation.

### Key conventions in this file
- Every drawable zone/level is deleted and recreated rather than mutated in place when it needs to
  disappear (standard Pine Script pattern — there's no "hide" for `box`/`line`/`label`).
- `var` is used for anything that must persist its value across bars (running highs/lows, the
  latest PDH/session line/label references, session-tracking state).
- Session/PDHL/mitigation line styles are chosen via `input.string(... options=[...])` with Spanish
  option labels ("Sólida"/"Discontinua"/"Punteada", "Mecha (toque)"/"Cierre") mapped to
  `line.style_*` / behavior through small helper functions (`lineStyleFromInput`,
  `closedThrough`) — extend those helpers rather than branching on the raw input string elsewhere.
- `max_boxes_count=500, max_lines_count=500, max_labels_count=500` are set on the `indicator()`
  call to accommodate the number of drawing objects this script can accumulate; raise these
  together if adding more drawn object types.

## Development workflow

There is no build, package manager, or automated test suite — Pine Script only runs inside
TradingView.

- **Editing**: edit `.pine` files directly as text.
- **Testing a change**: paste the file's contents into the TradingView Pine Editor
  (tradingview.com → Pine Editor tab), click "Add to chart", and visually verify behavior on a
  chart (check both FVG/IFVG formation and the PDH/PDL/session lines across a day/session
  boundary, including on non-24h and continuous-futures symbols since session-boundary bugs have
  been the main source of past fixes here).
- **Linting/formatting**: none is configured. Follow the existing 4-space indentation, section
  banner comments (`// ===== ... =====`), and Spanish naming/labels used throughout the file.
- **Versioning**: the script targets Pine Script **v6** (`//@version=6` at the top) — don't
  silently downgrade syntax to v5 or earlier.

## Conventions

- Keep new indicators as self-contained single `.pine` files under `indicators/` (or
  `strategies/` for `strategy()`-type scripts), matching the structure of `fvg_ifvg.pine`
  (grouped inputs → types/state → detection logic → drawing/management → alerts).
- User-facing input labels, tooltips, and on-chart labels are in **Spanish**; code comments in
  this repo are also in Spanish. Match that for consistency within a given file.
- Commit messages so far are short, imperative, and describe the specific behavior fixed or added
  (e.g. "Fix session high/low: lock to NY session, capture at session end not next start") —
  follow that style, especially for bug fixes, since session/mitigation logic here is subtle and
  the commit message is often the only record of *why* a change was made.

## Branching / CI

- Default branch: `main`.
- No CI is configured (no `.github/workflows/`) — changes are verified manually in TradingView as
  described above.

## Keeping this file up to date

Update this file whenever indicators are added/removed, the directory structure changes, or a new
convention is established (e.g. a `strategies/` directory, a README, or any tooling/CI gets
added). Since there's no automated test suite, call out in commit messages and here how a change
was manually verified.
