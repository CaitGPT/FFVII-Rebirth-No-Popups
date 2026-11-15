# No Popups for FINAL FANTASY VII REBIRTH

A mod that removes on-screen elements and scenes that interrupt play. An AI (Claude, working with our game-playing
harness) built and tested it.

## What it changes

| Element | Change | Tested |
| --- | --- | --- |
| The "World Intel — *name* — Completed" banner after each world intel activity, and the Results panel with it | Removed | A combat assignment, a lifespring, a tower and a Titan sanctuary |
| Chadley's video calls (he appears on Cloud's communicator and the camera cuts to it) | 82 calls play as earpiece calls: the same voiced lines and subtitles over normal play | Lifespring and Titan Sanctuary calls |
| Chadley's calls inside completion sequences (after Lifesprings, the "Excavation" unlock, fiend intel, towers) | Removed: the game holds Cloud until they end, even as earpiece calls. Their flags and triggers still fire | Lifesprings 1 and 4 |
| The map that opens by itself to show newly unlocked intel | Removed | Lifespring 4 |

Rewards and progress are unchanged: completion flags, data points, party EXP, VR course and intel unlocks all still
happen. One line of the reward list, "Intel has been relayed to Chadley.", no longer appears.

Measured on a combat assignment, from the end of the fight: about **2.4 seconds** before the player can move, against
about **12.7 seconds** without the mod. After the second Grasslands Lifespring, about 10 seconds against about 30.
After the first one, which also unlocks Region Intel, about 16 against about 31.

Each of the four activity types was verified from the game's own completion flag rather than from the screen; the
table is in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

### What you give up

Combat assignments show a checklist of their objectives in the top left while you fight, and the same switch hides
it: it is part of the same display. We tried twice to keep it and could not do it without bringing the banner back
with it. The objectives are still listed in the intel menu. The attempt, and the UE4SS panel we built and did not
ship, are written up in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

### Not changed yet

- The Region Intel banner after the 1st, 3rd and 5th Lifespring of a region, and the short "new intel" banner when an
  activity unlocks. Both are drawn by the engine as part of the completion sequence; switching the "new intel" one off
  in data froze the sequence, so it was reverted.
- First-time tutorial panels. A data change that silences 119 of them exists (`tools/tips_spec.py`, build with
  `-WithTips`), but with it a Lifespring's completion sequence stalled, so it is off.
- Chadley scenes that do more than talk (the Gilgamesh scenes, some Chadley's Request quest steps, the card game
  calls): 29 in all.

## Download

[**No Popups 1.0.0**](https://github.com/CaitGPT/FFVII-Rebirth-No-Popups/releases/tag/v1.0.0) — the zip has
both builds, a README and the licence.

## Install

Copy the three `NoPopups_P` files (`.pak`, `.ucas`, `.utoc`) into
`FINAL FANTASY VII REBIRTH\End\Content\Paks\~mods\` (create `~mods` if it doesn't exist). No UE4SS needed.

**With Junon Colosseum installed**, use the `NoPopups_JunonCompat_9999_P` files instead. Both mods replace the
`Action` and `PlannerEvent` tables, and this version carries Junon Colosseum's rows as well as ours.

To uninstall, delete the three files.

## Compatibility

The mod replaces three tables: `DataObject/Resident/HubConfig`, `Action` and `PlannerEvent` (and `WorldCondition` with `-WithTips`). Another mod that replaces
any of them conflicts with it: whichever loads last wins.

## How it works

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md), which also covers how we found it and what didn't work.

## Build

Needs the .NET 8 SDK, UnrealReZen, an FModel export of the game's DataObject tables and CSV exports of `Action`,
`PlannerEvent` and `AreaReport`. Copy `tools/build-config.example.json` to `tools/build-config.local.json`, set the
paths, then:

```powershell
python tools/make_spec.py                         # writes data/generated.json from the game's tables
.\tools\Build-NoPopups.ps1 -Mode Build            # add -Variant JunonCompat for the Junon Colosseum version
.\tools\Build-NoPopups.ps1 -Mode Install          # the game must be closed
```

`tools/DataBuilder` is our MIT table reader and writer, copied from the shared copy in our FFVII-Modding repository
(`Tools/ff7r-databuilder`, commit `ea38b023`).

## Licence

MIT. No game files are included in this repository.
