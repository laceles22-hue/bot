# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository status

This repo hosts TradingView **Pine Script (v6) indicators**, focused on ICT-style price-action
concepts (Fair Value Gaps, liquidity sweeps, SMT divergence, session levels, etc.). There is no
package manager, build system, or test suite — Pine scripts are plain `.pine` text files that get
pasted/synced into TradingView's Pine Editor.

## Codebase structure

- `indicators/` — one `.pine` file per indicator.
  - `fvg_ifvg.pine` — Fair Value Gap / Inverse Fair Value Gap indicator, plus PDH/PDL and previous
    NY/London session high-low levels.
  - `setup_grade_checklist.pine` — "Setup Grade" panel: scores the current setup against a
    6-item ICT checklist (Liquidity Sweep, HTF PDA Delivery, Delta Imbalance, IFVG, Clear
    Targets, SMT w/ E3), shows a letter grade in a table (mimicking the "Setup Grade" panel
    style), and optionally draws an entry/SL/TP trade plan with position size based on account
    risk %.

## Development workflow

- There's no local runner for Pine Script; scripts are validated by pasting them into
  TradingView's Pine Editor (Add indicator → Pine Editor → paste → "Add to chart") and checking
  the compiler output there.
- No linter/formatter is configured — follow the indentation-sensitive Pine syntax carefully
  (4-space indents per nesting level) and match the style of existing files.

## Conventions

- Scripts target `//@version=6`.
- UI text, input labels, and code comments are written in **Spanish**, matching the existing
  indicators — keep new indicators consistent with this unless the user asks otherwise.
- Reusable zone/box tracking uses a small `type` (e.g. `Zone`) plus `var array<Zone>` so drawn
  objects (boxes/lines/labels) can be trimmed and mitigated across bars without leaking.
- Multi-timeframe or multi-symbol logic (`request.security`, `request.security_lower_tf`) is an
  approximation where Pine has no equivalent native data (e.g. there is no real order-flow delta
  or object-level HTF FVG tracking) — such limitations are documented in a comment block at the
  top of the file that uses them.
- Avoid scaffolding an unrelated language/framework here; this repo is Pine Script only unless
  the user explicitly asks for something else.

## Branching / CI

No CI is configured. There's no fixed default-branch convention documented yet beyond what's used
for active work — check `git branch -a` / the remote's default branch before assuming one.

## Keeping this file up to date

Update this file whenever a new indicator is added or an existing one's scope changes materially
— add it to "Codebase structure" above rather than leaving this file describing an empty repo.
