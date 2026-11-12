# No Popups for FINAL FANTASY VII REBIRTH

A mod that removes on-screen elements that interrupt play. An AI (Claude, working with our game-playing harness) built
and tested it.

## What it removes

| Element | State |
| --- | --- |
| The "World Intel — *name* — Completed" banner shown each time a world intel activity is finished | Removed; tested on a Grasslands Lifespring |

Rewards are unchanged: completion still sets the activity's flags, and the data points and party EXP are still granted
and listed. One line of the reward list, "Intel has been relayed to Chadley.", no longer appears.

Not changed: the Region Intel banner after a Lifespring, first-time tutorials, and Chadley's call after a Lifespring
analysis (a short scene that holds control for about 20 seconds).

## Install

Copy `NoPopups_P.pak`, `NoPopups_P.ucas` and `NoPopups_P.utoc` into
`FINAL FANTASY VII REBIRTH\End\Content\Paks\~mods\` (create `~mods` if it doesn't exist). No UE4SS needed.

To uninstall, delete the three files.

## Compatibility

The mod replaces one table, `DataObject/Resident/HubConfig`. Another mod that replaces the same table will conflict
with it; whichever loads last wins.

## How it works

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md), which also covers how we found it and what didn't work.

## Build

Needs the .NET 8 SDK, UnrealReZen, and an FModel export of the game's DataObject tables. Copy
`tools/build-config.example.json` to `tools/build-config.local.json`, set the paths, then:

```powershell
.\tools\Build-NoPopups.ps1 -Mode Build
.\tools\Build-NoPopups.ps1 -Mode Install    # the game must be closed
```

`tools/DataBuilder` is our MIT table reader and writer, copied from the shared copy in our FFVII-Modding repository
(`Tools/ff7r-databuilder`, commit `ea38b023`).

## Licence

MIT. No game files are included in this repository.
