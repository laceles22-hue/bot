# CLAUDE.md

This file gives Claude Code (and other AI assistants) guidance for working in this repository.

## Repository status

This repo holds a couple of unrelated small projects — there is no single build system or
language for the whole tree. Treat each top-level directory independently.

## Codebase structure

- `indicators/` — Pine Script (TradingView) indicators.
  - `fvg_ifvg.pine` — Fair Value Gap / Inverse Fair Value Gap overlay indicator (Pine Script v6).
    No build step; paste the file into TradingView's Pine Editor to use it.
- `web/` — Static website for **Urban Beauty**, a hair salon in Granollers (Barcelona).
  - `index.html` — single-page site (hero, servicios, sobre nosotros, horario, contacto/mapa).
  - `css/style.css` — all styling, mobile-responsive (breakpoints at 900px and 520px).
  - `js/main.js` — mobile nav toggle, scroll-reveal animations, footer year.
  - No build step or dependencies. Open `web/index.html` directly, or serve the folder with
    any static file server, e.g. `python3 -m http.server 8000` from inside `web/`.
  - Business details baked into the markup: address (Calle Josep Umbert, Granollers), phone
    (938 79 31 75 / +34938793175), and a Google Maps embed for that address. Opening hours in
    the "Horario" section are a placeholder — confirm/update them with the real schedule.
  - No real photos yet — the gallery/visual areas use icons and color only. Swap in real
    photos when available.

## Conventions

- Keep `web/` dependency-free and framework-free (plain HTML/CSS/JS) unless the user asks for
  a framework.
- Spanish is the working language for all user-facing copy in `web/`.

## Keeping this file up to date

Update this file whenever structure, workflows, or conventions change materially — e.g. if a
build tool, framework, or additional project is introduced.
