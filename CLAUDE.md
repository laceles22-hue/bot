# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository overview

`bot` is a small collection of TradingView **Pine Script v6** indicators. There is no build
system, package manager, or test suite — Pine Script indicators are plain-text scripts loaded
directly into TradingView's Pine Editor and run there.

## Codebase structure

- `indicators/` — Pine Script indicator source files.
  - `fvg_ifvg.pine` — "FVG & IFVG (Fair Value Gap / Inverse FVG)", an `overlay=true` indicator
    that detects and draws:
    - **FVG (Fair Value Gap)**: the classic 3-candle imbalance pattern (bullish: `low[0] >
      high[2]`; bearish: `high[0] < low[2]`), drawn as colored boxes with optional midline (CE
      50%) and labels.
    - **IFVG (Inverse FVG)**: when an FVG is fully mitigated (price closes/wicks through it,
      depending on the "Mitigación" setting), the same zone flips and is redrawn as a
      support/resistance zone in the opposite direction.
    - **PDH/PDL**: previous day's high/low, drawn via `request.security(..., "D", ...)`.
    - **Previous NY session high/low** and **previous London session high/low**: computed with
      running accumulators keyed off `input.session(...)` windows and their respective time
      zones (`America/New_York`, `Europe/London`), with guards against the accumulator getting
      stuck across multiple sessions on continuous futures data.
    - Alert conditions for new bullish/bearish FVGs.
    - All user-facing inputs, tooltips, and labels are in **Spanish**.

## Development workflow

There is nothing to install, build, run, or lint from the command line:

- To use/test a script: open [TradingView](https://www.tradingview.com), open the Pine Editor,
  paste the contents of the `.pine` file, and click "Add to chart." Pine Script's own editor
  reports compile errors.
- There is no automated test suite. Verify changes by visually inspecting the indicator on a
  chart (check FVG/IFVG box placement, mitigation behavior, and session H/L lines) across a few
  symbols/timeframes, including continuous futures contracts (the session H/L logic has explicit
  handling for those).

## Conventions

- Indicator files live under `indicators/`, one file per indicator, named
  `snake_case.pine`.
- Follow the existing structure within a `.pine` file: header comment block explaining the
  indicator, then `// ============================= SECTION =============================`
  banners grouping inputs, types, helpers, detection logic, zone management, and alerts.
- Inputs are grouped with `group=` into logical sections (e.g. `grpFvg`, `grpIfvg`, `grpFilter`,
  `grpDisplay`, `grpMit`, `grpPdhl`, `grpSess`, `grpLdn`) and given Spanish labels/tooltips —
  match this when adding new inputs.
- Keep new comments and user-facing strings in Spanish, consistent with the rest of the file.
- Commit messages are short, imperative, and describe the behavioral change (see `git log`).

## Branching / CI

- Default branch: `main`.
- No CI is configured in this repository.

## Keeping this file up to date

Update this file whenever a new indicator is added under `indicators/`, or when the structure,
workflow, or conventions described above change materially.
