# Changelog

## 1.0.1 - 2026-11-24

- Fixed: Classified Intel (each region's boss fight, e.g. Jabberwock in Cosmo Canyon) could not be started (issue #1).
  The game starts it from the world intel panel ("Engage Enemy"), which the mod hid along with the banner. A new UE4SS
  part shows the game's own "Hold" icon over Cloud in the boss's area: hold Y or the right mouse button and the boss
  comes out, for the first fight and for rematches. The panel and the banner stay hidden. Checked on all six bosses,
  with a controller and with keyboard and mouse.
- Fixed: a finished combat assignment (Fiend Intel) could not be retried, for the same reason. Fiend Intel keeps the
  game's panel now: its checklist and Retry are back, and so is its completion banner.
- New: the UE4SS part needs RE-UE4SS FF7R. Without UE4SS, the "Without UE4SS" builds give the region bosses the game's
  panel back instead (and their banner with it).
- The pak now also replaces the `Hub` table. Players with Junon Colosseum still use the JunonCompat build, which is
  built on Junon Colosseum 1.2.1's tables.

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
