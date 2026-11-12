# How it works

## The world intel banner

Each world intel activity on the map (Lifesprings, Remnawave Towers, Combat Assignments and others) is a row of the
`Hub` table. Its `ConfigID` names a row of `HubConfig`, which holds a set of switches for how that hub behaves. One of
them is `DisableWorldReportNotify`.

The game already sets it to 1 on the configs used by hubs that never announce world intel (chocobo stops, treasure
spots, level hubs, `HubConfig_World_DisableNotification`). It is 0 on the configs world intel uses:
`HubConfig_WorldNormal` and the `HubConfig_WorldReport_*` rows, plus their `_Demo` and `_Media` variants.

The mod sets it to 1 on those 13 rows (`data/no-popups.json`). Nothing else changes.

## What we observed

Tested on 2026-11-12 on Grasslands Lifespring 1 (Cragshade Lifespring, hub `Area_1200_Hub_1_2`), from one save made
in front of it, once without the mod and once with it. Our harness played the Lifespring's minigame, then tried to move
Cloud every second.

| | Without the mod | With the mod |
| --- | --- | --- |
| "World Intel — Expedition Intel 1: Cragshade Lifespring — Completed" banner | shown, about 6 s | not shown |
| `stfArea1200_Hub1_02_Clear`, `stfWorldReport_Finish_GRASA_003` | set | set |
| "Received 10 data points for the grasslands", "5 party EXP gained" | listed | listed |
| "Intel has been relayed to Chadley." | listed | not listed |
| Time before Cloud could be moved | about 26 s | about 20 s |

In both runs the rest of the wait is the Lifespring's own sequence: the Region Intel banner and Chadley's call
("Confirmed—data received."), which this version doesn't touch. Only a Lifespring has been tested; the other world
intel types use the same configs, so they should behave the same, but that hasn't been seen yet.

## Packaging

DataBuilder writes the changed table; UnrealReZen packs it into `NoPopups_P.pak/.ucas/.utoc`. The build then writes the
10 bytes every Rebirth `.ucas` starts with over the start of UnrealReZen's `.ucas`, as Training Dummy does. In
UnrealReZen's output the first compressed block is its 44-byte container header chunk, and the table is the second
block, so this spoils only the header chunk. The build script checks that before writing.

UnrealReZen gives each build a new container ID, so two builds of the same table aren't byte-identical. The table
inside is.

## How we found it

1. The game's source headers list `EEndMenuReportNotifyKind` (WorldReport, BattleMission, Colosseum, ChadleyReport,
   Hub) and a `ReportProgressWidget` (`Report_Content_Window`). That widget turned out to be the map journal's page,
   not the banner.
2. A search for the notify flag found `DisableWorldReportNotify` in the `HubConfig` row struct. The table's values
   (1 on hubs that never announce, 0 on world intel) suggested it was the switch, so we built that first.
3. We tested it in the game before writing anything else.

## Dead ends

- **Container with Rebirth's 16-byte prefix.** Prepending the prefix to UnrealReZen's `.ucas` and shifting its block
  offsets (the step Junon Colosseum uses for its own containers) crashed the game at start-up, three times, with an
  access violation at `ff7rebirth_+0x884281`. The table block read back byte-identical, so the crash comes from the
  container header UnrealReZen writes, which retoc can't parse either.
- **A Lua script logging every widget the game shows.** `RegisterHook` on `/Script/UMG.UserWidget:AddToViewport` and
  `/Script/EndGame.EndUserWidget:AddToViewportEx` / `AddToPlayerScreenEx` at mod load registered fine, then crashed
  the game at start-up on every launch (seven launches). With the hooks off it loaded normally. The table change made
  the script unnecessary, so the mod has no Lua.
