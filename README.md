# No Popups for FINAL FANTASY VII REBIRTH

A mod that removes on-screen elements and scenes that interrupt play. An AI (Claude, working with our game-playing
harness) built and tested it.

## What it changes

| Element | Change | Tested |
| --- | --- | --- |
| The "World Intel — *name* — Completed" banner after each world intel activity, and the Results panel with it | Removed, except after combat assignments (Fiend Intel), which keep the game's panel since 1.0.1 | A lifespring, a tower and a Titan sanctuary (and a combat assignment, in 1.0.0) |
| Region boss fights (Classified Intel), whose start is in the panel the mod hides | Started from the game's own "Hold" icon over Cloud in the boss's area (UE4SS part, 1.0.1) | All six bosses, first fight and rematch, controller and keyboard |
| Chadley's video calls (he appears on Cloud's communicator and the camera cuts to it) | 60 calls play as earpiece calls: the same voiced lines and subtitles over normal play | Lifespring and Titan Sanctuary calls |
| Chadley's calls inside completion sequences (after Lifesprings, the "Excavation" unlock, fiend intel, towers) | Removed: the game holds Cloud until they end, even as earpiece calls. Their flags and triggers still fire | Lifesprings 1 and 4 |
| MAI and Chadley's call when a combat assignment opens a new VR course (the second assignment of each pair) | Removed (1.0.2): the course still opens and the game's "Combat Simulator Updated" notice still shows | All six Grasslands assignments, first clears and Retry |
| The map that opens by itself to show newly unlocked intel | Removed | Lifespring 4 |

Rewards and progress are unchanged: completion flags, data points, party EXP, VR course and intel unlocks all still
happen. One line of the reward list, "Intel has been relayed to Chadley.", no longer appears.

Measured with 1.0.0 on a combat assignment, from the end of the fight: about **2.4 seconds** before the player can
move, against about **12.7 seconds** without the mod (since 1.0.1 combat assignments keep their banner, so this one is
back to the game's time). After the second Grasslands Lifespring, about 10 seconds against about 30. After the first
one, which also unlocks Region Intel, about 16 against about 31.

Each of the four activity types was verified from the game's own completion flag rather than from the screen; the
table is in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

### What you give up

The banner, the objective checklist and the buttons that start or retry a fight are one display in the top left, and
the game has no setting between them. Since 1.0.1:

- **Combat assignments (Fiend Intel)** keep that display, because its Retry is the only way to fight a finished one
  again. Their checklist and Retry are there, and so is their completion banner.
- **Region boss fights (Classified Intel)** keep it hidden; the UE4SS part gives them their own start instead. Without
  UE4SS, the "Without UE4SS" builds give them the display back, banner included.

In 1.0.0 combat assignments lost their checklist and, as players found (issue #1), their Retry, and the bosses could
not be started at all. The attempts to keep the checklist without the banner, and the UE4SS panel we built and did not
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

- [**Nexus Mods**](https://www.nexusmods.com/finalfantasy7rebirth/mods/2525)
- [**GitHub release 1.0.2**](https://github.com/CaitGPT/FFVII-Rebirth-No-Popups/releases/tag/v1.0.2) — the
  zip has the builds with and without UE4SS, each also for Junon Colosseum, a README and the licence.

The video shows it working on four kinds of world intel, then how it was built:
[Building a No Popups Mod](https://www.youtube.com/watch?v=-dFbxNe-hLc).

## Install

The zip's `Install` folder goes into the game folder (`FINAL FANTASY VII REBIRTH\`): the three `NoPopups_P` files
(`.pak`, `.ucas`, `.utoc`) land in `End\Content\Paks\~mods\` (create `~mods` if it doesn't exist), and the `NoPopups`
folder in `End\Binaries\Win64\ue4ss\Mods\`. The UE4SS part needs
[RE-UE4SS FF7R](https://www.nexusmods.com/finalfantasy7rebirth/mods/267).

**With Junon Colosseum installed**, use `Install - with Junon Colosseum` instead (the `NoPopups_JunonCompat_9999_P`
pak). Both mods replace the `Action`, `PlannerEvent` and `Hub` tables, and this version carries Junon Colosseum's rows
as well as ours.

**Which folder:** with UE4SS, `Install` (the Lua start; the bosses' panel and banner stay hidden). Without UE4SS,
`Without UE4SS` (the pak alone; the bosses keep the game's panel, "Engage Enemy", and their banner comes back). With
Junon Colosseum, take the "with Junon Colosseum" version of either.

To uninstall, delete the three pak files and the `NoPopups` folder.

To start a region boss fight, stand in the boss's area and hold Y (controller) or the right mouse button while the
"Hold" icon over Cloud fills. `boss_start = 0` in the `NoPopups\settings.txt` turns it off.

## Compatibility

The mod replaces four tables: `DataObject/Resident/HubConfig`, `Hub`, `Action` and `PlannerEvent` (and
`WorldCondition` with `-WithTips`). Another mod that replaces any of them conflicts with it: whichever loads last wins.
Tested on the Epic build (1.005) with UE4SS 3.0.1, both with our other mods and with nothing else installed.

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

`-ClassifiedPanel` builds the "Without UE4SS" pak (into `build\<Variant>-Panel`). `python tools/check_build.py <build
root> <variant folder>` checks a built pak's `HubConfig` and `Hub` rows and the VR course calls offline (add
`--classified-panel` for those). `make_spec.py --vr-calls video` keeps the game's own VR course call instead of
removing it (check that build with `--vr-video`). And `python tools/make_release.py <version> <build root>` makes the zip from all four builds and `ue4ss/NoPopups`.

`tools/DataBuilder` is our MIT table reader and writer, copied from the shared copy in our FFVII-Modding repository
(`Tools/ff7r-databuilder`, commit `ea38b023`).

## Requests

We take requests: changes to this mod, or ideas for new Rebirth mods. Open an issue here, or post on the [Nexus page](https://www.nexusmods.com/finalfantasy7rebirth/mods/2525?tab=posts).

## Licence

MIT. No game files are included in this repository.
