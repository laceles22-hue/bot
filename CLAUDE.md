# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This repo holds TradingView **Pine Script v6** indicators. There is currently one script:

- `indicators/fvg_ifvg.pine` — detects Fair Value Gaps (FVG) and Inverse Fair Value Gaps (IFVG)
  using the classic 3-candle pattern, and additionally plots previous-day high/low (PDH/PDL) and
  the previous NY and London session high/low.

There is no package manager, build system, or test framework — Pine Script has none of these.
Each `.pine` file is a standalone script meant to be pasted into TradingView's Pine Editor.

## Development workflow

There are no CLI build/lint/test commands for Pine Script. To validate a change:

1. Open [TradingView](https://www.tradingview.com/) → Pine Editor.
2. Paste the contents of the `.pine` file in.
3. Compile errors/warnings appear in the editor's bottom panel — fix those before considering the
   change done.
4. Click "Add to chart" and visually verify the plotted boxes/lines/labels behave as expected
   (especially around gap creation, mitigation, and session boundaries — these are stateful and
   easy to get wrong without a live chart to eyeball).

There is no automated test suite; verification is manual, on-chart, against real price data.

## Architecture (fvg_ifvg.pine)

The script is single-file but has several interacting subsystems worth understanding before
editing:

- **Zone lifecycle via a shared `Zone` type.** FVG and IFVG boxes/midlines/labels are all
  instances of one `Zone` type (`box b`, `line ce`, `label lbl`, `top`, `bottom`), tracked in four
  parallel arrays: `bullFvgZones`, `bearFvgZones`, `bullIfvgZones`, `bearIfvgZones`. Any change to
  how a zone is drawn, extended, or deleted should go through this same create/track/prune pattern
  (push on creation, `array.shift` the oldest off when `maxZonesPerSide` is exceeded) rather than
  drawing objects ad hoc.
- **FVG → IFVG conversion.** When a bullish FVG is invalidated (mitigated), it doesn't just get
  deleted — the same price zone is re-created as a *bearish* IFVG (and vice versa). This happens
  inline in the mitigation loops (around lines 156–232), so the FVG and IFVG lifecycles are
  coupled, not independent features.
- **Mitigation is centralized in `closedThrough()`.** Both "wick touch" and "close through" modes
  (`mitigationMode` input) are decided by this one helper — don't reimplement the touch/close
  comparison elsewhere.
- **Three independent session-tracking blocks** (PDH/PDL, previous NY session, previous London
  session) share the same hand-rolled pattern: a running high/low accumulated with `var` state
  across bars, snapshotted into `prev*High`/`prev*Low` at session end, then drawn as a `line` +
  `label` pair that gets re-extended to `bar_index` every bar via `line.set_x2`. The NY/London
  blocks intentionally snapshot at **session end** (not at the next session's start) so the line
  appears immediately after the session closes instead of staying blank until the next session
  begins — preserve this timing if touching that logic.
- **Inputs are grouped by feature** (`grpFvg`, `grpIfvg`, `grpFilter`, `grpDisplay`, `grpMit`,
  `grpPdhl`, `grpSess`, `grpLdn`) using Pine's `group=` param, mirroring the sections in the script
  body. Add new inputs to the matching group rather than a new ungrouped one.

## Conventions

- All user-facing input labels/tooltips and inline comments are written in **Spanish**; keep new
  inputs and comments consistent with this rather than mixing in English.
- Naming uses `bull`/`bear` prefixes for directional state (not `up`/`down` or `long`/`short`).
- Section banners (`// === ... ===`) delimit major phases of the script (inputs, types, detection,
  zone management per direction, PDH/PDL, sessions, alerts) — keep new code inside the relevant
  banked section rather than appending at the end.
