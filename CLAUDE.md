# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository status

The repository holds TradingView Pine Script (v6) files. There is no build system or test
suite: scripts are validated by pasting them into the TradingView Pine Editor.

- `indicators/fvg_ifvg.pine` — FVG/IFVG indicator with session highs/lows.
- `strategies/ifvg_personal.pine` — IFVG strategy for 1-minute charts that grades every
  inversion A+..C (Dodgy's iFVG setup rating), checks CISD confirmation, and only trades
  grades >= a chosen minimum.

## What to do until real code exists

- Don't assume a language, framework, or project layout that hasn't been established yet.
- If asked to scaffold a new project here, confirm with the user what kind of project `bot` is
  meant to be (e.g. a Slack/Discord bot, a CLI tool, a web service) before generating files,
  since the repo name alone doesn't specify this.
- Once the first real commit(s) land, update every section below from what's actually in the
  tree — do not leave speculative content in place.

## Sections to fill in once code exists

Replace this section with the real details as soon as there's something to describe:

- **Codebase structure** — top-level directories/packages and what each contains.
- **Development workflow** — how to install dependencies, run the project locally, run the test
  suite, and lint/format the code (exact commands, not generic advice).
- **Architecture notes** — key modules, entry points, data flow, and any non-obvious design
  decisions worth preserving.
- **Conventions** — naming, file organization, commit/PR style, and anything else contributors
  (human or AI) should follow consistently.
- **Branching / CI** — default branch name, required checks, and how PRs get merged.

## Keeping this file up to date

When you add the first meaningful code to this repository, regenerate this file (the `init`
Claude Code skill does this automatically by scanning the repo) rather than editing this
placeholder piecemeal. Keep CLAUDE.md in sync with the codebase going forward — update it
whenever structure, workflows, or conventions change materially.
