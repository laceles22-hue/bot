# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository status

This repo (`bot`) holds trading tools: Pine Script indicators for TradingView and MQL5 Expert
Advisors for MetaTrader 5. There is no build system, package manager, or test suite — these are
single-file scripts consumed directly by their respective platforms.

## Codebase structure

- `indicators/` — Pine Script (`.pine`) indicators for TradingView.
  - `fvg_ifvg.pine` — FVG/IFVG indicator with session high/low tracking.
- `experts/` — MQL5 (`.mq5`) Expert Advisors for MetaTrader 5.
  - `RangeBreakoutEA.mq5` — Symbol-agnostic range breakout EA (configurable time window,
    ATR-based stop loss, R:R take profit, risk-% position sizing off a reference balance,
    weekday filter, one trade per day, forced close time). Defaults are tuned for prop-firm
    style risk management on gold (XAUUSD) and USTEC.

## Development workflow

- Pine Script: paste into TradingView's Pine Editor and "Add to chart" to verify it compiles;
  there's no local compiler/CLI for Pine.
- MQL5: open the file in MetaEditor (bundled with MetaTrader 5) and compile with F7, or drop it
  into `MQL5/Experts/` in a MetaTrader 5 data folder and compile from there. No local MQL5
  compiler is available in this environment, so changes should be reviewed carefully for
  MQL5-syntax correctness since they can't be compiled in-session.

## Conventions

- One file per indicator/EA, named after what it does (e.g. `RangeBreakoutEA.mq5`).
- MQL5 EAs: use `input group "..."` to organize parameters in the input dialog, prefix inputs
  with `Inp`, and default values should make sense for a prop-firm funded-account context
  (conservative risk %, sane ATR-based stops) unless the user specifies otherwise.
- Comments/messages in EA `Print()` output follow the language the user requested the code in
  (Spanish so far).

## Branching / CI

- No CI configured. Default branch: `main`. Feature work happens on `claude/*` branches.

## Keeping this file up to date

Update this file whenever a new indicator/EA is added or workflow/conventions change — keep it
reflecting what's actually in the tree rather than speculative content.
