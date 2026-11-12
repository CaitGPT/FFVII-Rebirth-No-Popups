# No Popups for FINAL FANTASY VII REBIRTH

A mod that removes on-screen elements and scenes that interrupt play. An AI (Claude, working with our game-playing
harness) built and tested it.

## What it changes

| Element | Change | Tested |
| --- | --- | --- |
| The "World Intel — *name* — Completed" banner after each world intel activity | Removed | Grasslands Lifespring |
| Chadley's video calls (he appears on Cloud's communicator and the camera cuts to it) | 82 calls play as earpiece calls instead: the same voiced lines and subtitles over normal play | Lifespring call |
| Chadley's call after the first Lifespring | Removed: the game holds Cloud until it ends, so even as an earpiece call it took control | Lifespring |

Rewards and progress are unchanged: completion flags, data points, party EXP and VR course unlocks all still happen.
One line of the reward list, "Intel has been relayed to Chadley.", no longer appears.

After a Lifespring, Cloud could move about 16 seconds after the minigame, against about 31 seconds without the mod.

### Not changed yet

- The Region Intel banner ("New region intel is now available.") after the 1st, 3rd and 5th Lifespring of a region.
  The engine shows it, and Cloud stays held until it ends (about 8 seconds).
- First-time tutorial panels.
- Chadley scenes that do more than talk (the Gilgamesh scenes, some Chadley's Request quest steps, the card game
  calls): 29 in all.
- Only Lifesprings have been tested in the game. Other world intel uses the same tables, so it should behave the same.

## Install

Copy the three `NoPopups_P` files (`.pak`, `.ucas`, `.utoc`) into
`FINAL FANTASY VII REBIRTH\End\Content\Paks\~mods\` (create `~mods` if it doesn't exist). No UE4SS needed.

**With Junon Colosseum installed**, use the `NoPopups_JunonCompat_9999_P` files instead. Both mods replace the
`Action` and `PlannerEvent` tables, and this version carries Junon Colosseum's rows as well as ours.

To uninstall, delete the three files.

## Compatibility

The mod replaces three tables: `DataObject/Resident/HubConfig`, `Action` and `PlannerEvent`. Another mod that replaces
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
