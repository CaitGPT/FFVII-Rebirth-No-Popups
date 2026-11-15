# Changelog

## 1.0.0 - 2026-11-15

First public release. The mod removes the world intel completion banner and the Results panel with it, turns 82 of
Chadley's video calls into earpiece calls, removes the calls inside completion sequences, and stops the map opening
by itself. Verified in game on four kinds of world intel - a combat assignment, a lifespring, a tower and a Titan
sanctuary - each read back from its own completion flag.

Known trade-off: combat assignments lose their in-fight objective checklist, which the same switch hides.

Earlier, unreleased:

- 0.3: Chadley's calls inside completion sequences are removed (25 calls, flags and triggers kept); the map that opens
  by itself after new intel unlocks is removed. Experimental, off by default: silencing 119 first-time tutorial tips.
- 0.2: 82 of Chadley's video calls play as earpiece calls (same lines, no camera cut). The call after the first
  Lifespring is removed, because the game holds Cloud until it ends. Region Intel entries open through flag-only
  actions (the banner itself still shows). A Junon Colosseum-compatible build.
- 0.1: removes the "World Intel — Completed" banner (`HubConfig.DisableWorldReportNotify` on the 13 world intel
  configs). Tested on a Grasslands Lifespring.
