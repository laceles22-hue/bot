# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repository holds trading tools for two platforms:

- **TradingView Pine Script v6 indicators** — plain `.pine` text files, no build system.
- **MetaTrader 5 (MQL5) Expert Advisors** — plain `.mq5` text files, no build system.

Neither language has a package manager or CLI test runner here; each is compiled/run inside its
own vendor IDE (Pine Editor for TradingView, MetaEditor for MT5).

## Codebase structure

- `indicators/` — Pine Script indicator source files (`.pine`). Currently contains:
  - `fvg_ifvg.pine` — "FVG & IFVG" indicator (overlay). Detects Fair Value Gaps and Inverse Fair
    Value Gaps, and additionally plots previous-day high/low (PDH/PDL) and previous-session
    high/low for the New York and London sessions.
- `experts/` — MQL5 Expert Advisor source files (`.mq5`). Currently contains:
  - `range_breakout_atr_ea.mq5` — Opening Range Breakout EA, symbol-agnostic (gold/indices/forex).
    Marks the high/low between two configurable server-time hours, enters on a close-confirmed
    breakout of that range, sizes SL by ATR and TP by a configurable R:R, sizes the lot from a
    risk-% over a configurable reference balance (for prop-firm/funded accounts), and applies a
    weekday filter, a one-trade-per-day cap, and a configurable forced-close time.

There is no separate strategy/, lib/, or test directory yet — everything lives as single
self-contained files under `indicators/` or `experts/`.

## Development workflow

### Pine Script (`indicators/`)
- **Editing**: Edit `.pine` files directly; there is no local compiler.
- **Validate/run**: Paste the file contents into TradingView's Pine Editor (Pine Script v6) and
  click "Add to Chart" — this is the only way to check for compile errors or see the indicator
  render, since there is no CLI or headless Pine runtime.
- **Version pragma**: Every script starts with `//@version=6`; keep new/edited scripts on v6
  unless there's a specific reason to target another version.

### MQL5 (`experts/`)
- **Editing**: Edit `.mq5` files directly; there is no local compiler.
- **Validate/run**: Compile via MetaEditor (F7) against MT5's `<Trade\Trade.mqh>` standard
  library, then backtest in the Strategy Tester before attaching to a live/funded chart — there is
  no CLI or headless MQL5 compiler available here.
- EAs use the `CTrade` class from `<Trade\Trade.mqh>` for order execution rather than raw
  `OrderSend` calls.

No linting, formatting, or automated test tooling exists in this repo for either language.

## Architecture notes (`indicators/fvg_ifvg.pine`)

This file is representative of how indicators in this repo are structured, and future indicators
should likely follow the same shape:

- **Inputs are grouped** with `group=` into logical sections (`grpFvg`, `grpIfvg`, `grpFilter`,
  `grpDisplay`, `grpMit`, `grpPdhl`, `grpSess`, `grpLdn`). Input labels/tooltips are written in
  **Spanish** — match this convention for new inputs in this file, and check whether new files
  should follow suit.
- **Zone tracking pattern**: a `type Zone` (box + optional midline + optional label + top/bottom
  floats) is stored in `array<Zone>` per category (`bullFvgZones`, `bearFvgZones`,
  `bullIfvgZones`, `bearIfvgZones`). Each bar, these arrays are walked in reverse (`for i = size-1
  to 0`) so `array.remove(i)` during iteration is safe. New zone types should follow this same
  create → track-in-array → walk-in-reverse-and-mitigate → delete-or-convert lifecycle.
  `maxZonesPerSide` caps growth by shifting/deleting the oldest zone (FIFO) when exceeded, since
  Pine Script's `box`/`line`/`label` drawing objects are a limited, mutable resource that must be
  explicitly deleted (`box.delete`, `line.delete`, `label.delete`) — never just dereferenced.
- **FVG detection** uses the classic 3-candle pattern (`low > high[2]` for bullish, `high <
  low[2]` for bearish), gated by `minGapAtrMult * ta.atr(atrLen)` as an optional minimum-size
  filter.
- **Mitigation** (`closedThrough`) supports two modes via `mitigationMode`: wick-touch vs.
  candle-close-through, applied identically to FVG and IFVG zones (the "Cierre"/close mode is the
  documented default/recommended one, especially for IFVG).
- **FVG → IFVG conversion**: when a bull FVG is mitigated, a new *bearish* IFVG zone is created at
  the same top/bottom (and vice versa for bear FVG → bullish IFVG) — this is the core
  "inverse" mechanic, not just deletion.
- **Session high/low blocks** (PDH/PDL, NY session, London session) all follow the same pattern:
  a running high/low accumulator (`runSessHigh`/`runSessLow` etc.) reset on session start,
  finalized into a `prevSessHigh`/`prevSessLow` snapshot on session end, and rendered as a pair of
  `line`/`label` objects that get redrawn (deleted + recreated) at the start of each new period
  and extended (`line.set_x2`) every bar until then. Session boundaries are computed from
  `time(timeframe.period, session, timezone)` plus a day-id (`year*10000 + month*100 + day` in the
  session's own timezone) so a session is correctly closed even across territory like futures
  overnight data — see the inline comments around `sessionStart`/`sessionEnd` for why the day-id
  check exists (it forces a reset if the "in session" flag never cleanly dropped).
- Session high/low for a period is finalized and drawn **at session end**, not at the next
  session's start, so the line appears immediately after close instead of staying blank through
  the gap — this is called out explicitly in a code comment and is easy to regress if refactored.

## Architecture notes (`experts/range_breakout_atr_ea.mq5`)

- **Daily state machine**: a small set of module-level globals (`m_currentDay`, `m_rangeHigh/Low`,
  `m_rangeReady`, `m_tradedToday`, `m_closedToday`) is reset every time the server-time date
  changes (`UpdateDailyState`, called every tick). All other logic branches off these flags rather
  than tracking bar counts.
- **Range is computed from history, not accumulated tick-by-tick**: once server time passes the
  configured range-end, `UpdateRange` locates the start/end bars with `iBarShift` and scans
  between them with `iHighest`/`iLowest` on `InpTimeframe`. This means the range is correctly
  recomputed even if the terminal/EA restarts mid-day, as long as history is loaded — prefer this
  pattern over incrementally updating a running high/low on each tick.
- **Entry is close-confirmed, not a pending order**: `CheckBreakoutEntry` runs only on new-bar
  events (`IsNewBar`) and compares the *previous closed bar's* close (`iClose(..., 1)`) against the
  range, opening a market order via `CTrade::Buy/Sell` — it deliberately does not use
  `BuyStop`/`SellStop` pending orders.
- **One trade per day is enforced by `m_tradedToday`**, set only after a successful `CTrade` send;
  a failed send leaves it `false` so the next new bar can retry the same breakout check — this is
  intentional (transient broker errors shouldn't burn the day's one trade) and should be preserved
  if this logic is touched.
- **Lot sizing** (`CalcLots`) converts a risk-% of a *reference balance* (fixed input, for
  prop-firm/funded accounts, or the live `ACCOUNT_BALANCE`) into a volume using
  `SYMBOL_TRADE_TICK_SIZE`/`SYMBOL_TRADE_TICK_VALUE_LOSS` (falling back to `SYMBOL_TRADE_TICK_VALUE`)
  so it's correct for any symbol/quote currency, then floors to `SYMBOL_VOLUME_STEP` and clamps to
  `SYMBOL_VOLUME_MIN/MAX`.
- **SL/TP**: SL distance = `ATR(InpATRPeriod) * InpATRMultiplier` (read from the last *closed* bar,
  shift 1), widened up to the broker's `SYMBOL_TRADE_STOPS_LEVEL` if needed; TP distance = SL
  distance × `InpRewardRiskRatio`. There is no independent TP input — changing the R:R is the only
  way to move it.
- **Forced close** (`CheckForceClose`) runs every tick (not just on new bars) so it fires at the
  exact configured minute, and is guarded by `m_closedToday` to avoid repeated close attempts.
- The range window is assumed **not** to cross midnight (`OnInit` rejects `start >= end`); if a
  session that wraps past 00:00 is ever needed, this validation and the day-key math both need
  rework.

## Conventions

- Keep new indicators as single self-contained `.pine` files under `indicators/`, and new EAs as
  single self-contained `.mq5` files under `experts/`.
- Follow the existing input-grouping and Spanish-label convention (`group=` in Pine, `input group`
  in MQL5) used in `fvg_ifvg.pine` and `range_breakout_atr_ea.mq5` unless the user asks for a
  different language/style.
- Always explicitly delete Pine drawing objects (`box`/`line`/`label`) when removing them from a
  tracking array — leaked drawing objects will hit TradingView's per-indicator object limits
  (this file declares `max_boxes_count=500`, `max_lines_count=500`, `max_labels_count=500`).
- In MQL5, filter positions/orders by `InpMagicNumber` (and `_Symbol`) before acting on them, so an
  EA never touches trades opened manually or by another EA on the same chart/account.
