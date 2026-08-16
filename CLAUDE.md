# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A collection of Pine Script (TradingView) indicators. Currently a single indicator:
`indicators/fvg_ifvg.pine` — an overlay indicator that detects Fair Value Gaps (FVG) and
Inverse Fair Value Gaps (IFVG), plus session high/low reference lines (previous day,
previous NY session, previous London session).

There is no build system, package manager, or test suite — Pine Script is TradingView's
proprietary scripting language and only runs inside the TradingView chart editor. "Running"
a script means pasting/loading it into TradingView's Pine Editor and applying it to a chart.

## Development workflow

- Edit `.pine` files directly; there is nothing to install or compile locally.
- To verify a change, copy the script into TradingView's Pine Editor (Pine Script v6) and
  check for compiler errors, then apply it to a chart to confirm the visual behavior
  (boxes, lines, labels render as expected, no runtime errors in the console).
- There are no automated tests. Validate logic changes by reasoning through bar-by-bar
  behavior (this is how the existing session-tracking bugs in the git history were fixed —
  see `git log --oneline` for examples of the reasoning trail) and, where possible, by
  visually confirming on a chart across a session boundary or weekend gap.

## Code conventions specific to this repo

- Comments and UI-facing strings (input labels, tooltips, group names, plot labels) are
  written in **Spanish**. Keep new code consistent with this — don't switch to English labels
  mid-file.
- Script header uses a boxed `// ===...===` banner comment style to separate major sections
  (INPUTS, TIPOS, HELPERS, DETECCIÓN, GESTIÓN + MITIGACIÓN, ALERTAS, etc.). Follow this when
  adding new sections.
- Inputs are grouped with the `group=` parameter into named sections (`grpFvg`, `grpIfvg`,
  `grpFilter`, `grpDisplay`, `grpMit`, `grpPdhl`, `grpSess`, `grpLdn`). When adding a new
  feature with user-configurable options, add a new `grp*` group rather than dropping inputs
  into an existing unrelated group.

## Architecture: `indicators/fvg_ifvg.pine`

The script is one large `indicator()` body organized into independent feature blocks that
share only the drawing/mitigation pattern below. When modifying one block, the others are
generally unaffected.

**Zone lifecycle pattern (FVG/IFVG):**
- A `Zone` user-defined type bundles a `box`, an optional midline `line`, an optional
  `label`, and the zone's `top`/`bottom` prices.
- Four parallel arrays hold live zones: `bullFvgZones`, `bearFvgZones`, `bullIfvgZones`,
  `bearIfvgZones`. Each array is capped at `maxZonesPerSide`; oldest zones are shifted out
  and their drawing objects explicitly deleted (Pine has no garbage collection for
  boxes/lines/labels — every `box.new`/`line.new`/`label.new` needs a matching `.delete`
  when the zone is discarded).
- Detection: a new FVG is the classic 3-candle gap (`low > high[2]` for bullish,
  `high < low[2]` for bearish), optionally filtered by `minGapAtrMult` against `ta.atr`.
- Mitigation: `closedThrough()` centralizes the "has price invalidated this zone" check,
  branching on `mitigationMode` ("Cierre" = candle close must cross fully through; "Mecha" =
  a wick touch is enough). When an FVG is mitigated it is removed and — if `showIfvg` is on —
  immediately spawns an opposite-direction IFVG zone in the corresponding IFVG array (bullish
  FVG mitigation → bearish IFVG, and vice versa). IFVG zones follow the same mitigation check
  but just get deleted (no further inversion) when `deleteIfvgOnFill` is true.
- Each of the four zone arrays is walked and managed in its own loop block (right-edge
  extension via `extendRight`, then mitigation check), iterating **backwards** (`size-1 to 0`)
  since `array.remove` shifts subsequent indices.

**Session/reference-line pattern (PDH/PDL, NY session, London session):**
- Three near-identical blocks (previous-day high/low, previous-NY-session high/low,
  previous-London-session high/low) each follow the same shape: a running high/low
  accumulator (`runSessHigh`/`runSessLow` etc.) updated while `inSession` is true, reset on
  `sessionStart`, and snapshotted into `prevSessHigh`/`prevSessLow` on `sessionEnd`. A single
  persistent `line`/`label` pair is moved (`line.set_x2`, `label.set_x`) rather than recreated
  every bar, and only fully recreated (`.delete` + `.new`) when a new session's range is
  captured.
- `sessionStart`/`sessionEnd` are edge-triggered off `inSession` (derived from
  `time(timeframe.period, session, timezone)`) combined with a day-ID check
  (`year*10000+month*100+day` in the session's timezone) — the day-ID check exists
  specifically to force a reset if a session `wasInSession` flag ever fails to toggle cleanly
  (e.g. gaps in continuous futures data spanning multiple sessions). See the git history
  (`e1b1e33`, `a0ec250`) for the bugs this pattern was written to fix — don't regress the
  day-ID fallback when touching this logic.
- The previous session's range is snapshotted at `sessionEnd` (not when the *next* session
  starts), so the reference line appears immediately after the session closes instead of
  staying blank through the gap.
- The NY and London blocks are structurally identical; if fixing a bug in one, check whether
  the same bug exists in the other (and in PDH/PDL, which uses a simpler daily reset instead
  of a session window).

## Adding a new indicator

Place new `.pine` files under `indicators/`. There's no shared library/import mechanism in
use yet — each indicator file is self-contained.
