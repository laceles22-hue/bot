# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repository holds TradingView **Pine Script v6** indicators. There is no build system,
package manager, or test runner — Pine Script is authored as plain `.pine` text files and
executed by pasting/loading them into the TradingView Pine Editor, where TradingView compiles
and runs the script directly on a chart.

## Codebase structure

- `indicators/` — Pine Script indicator source files (`.pine`). Currently contains:
  - `fvg_ifvg.pine` — "FVG & IFVG" indicator (overlay). Detects Fair Value Gaps and Inverse Fair
    Value Gaps, and additionally plots previous-day high/low (PDH/PDL) and previous-session
    high/low for the New York and London sessions.

There is no separate strategy/, lib/, or test directory yet — everything lives as single
self-contained indicator files under `indicators/`.

## Development workflow

- **Editing**: Edit `.pine` files directly; there is no local compiler.
- **Validate/run**: Paste the file contents into TradingView's Pine Editor (Pine Script v6) and
  click "Add to Chart" — this is the only way to check for compile errors or see the indicator
  render, since there is no CLI or headless Pine runtime.
- **Version pragma**: Every script starts with `//@version=6`; keep new/edited scripts on v6
  unless there's a specific reason to target another version.
- No linting, formatting, or automated test tooling exists in this repo for Pine Script.

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

## Conventions

- Keep new indicators as single self-contained `.pine` files under `indicators/`.
- Follow the existing input-grouping and Spanish-label convention in `fvg_ifvg.pine` unless the
  user asks for a different language/style.
- Always explicitly delete Pine drawing objects (`box`/`line`/`label`) when removing them from a
  tracking array — leaked drawing objects will hit TradingView's per-indicator object limits
  (this file declares `max_boxes_count=500`, `max_lines_count=500`, `max_labels_count=500`).
