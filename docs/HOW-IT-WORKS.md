# How it works

## The world intel banner

Each world intel activity on the map (Lifesprings, Remnawave Towers, Combat Assignments and others) is a row of the
`Hub` table. Its `ConfigID` names a row of `HubConfig`, which holds a set of switches for how that hub behaves. One of
them is `DisableWorldReportNotify`.

The game already sets it to 1 on the configs used by hubs that never announce world intel (chocobo stops, treasure
spots, level hubs, `HubConfig_World_DisableNotification`). It is 0 on the configs world intel uses:
`HubConfig_WorldNormal` and the `HubConfig_WorldReport_*` rows, plus their `_Demo` and `_Media` variants.

The mod sets it to 1 on those 13 rows (`data/no-popups.json`).

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

## Chadley's video calls

A Chadley call is an `Action` row (type 1) naming a chain of `PlannerEvent` steps: each step is one voiced line or a
few commands, linked by `NextPE`. Two kinds exist, and the voiced lines are the same in both (talker `ComChadley`):

| | Video call | Earpiece call |
| --- | --- | --- |
| Action exclusion | `eclTypePlanEvent` | `eclTypePlanLiveWin` (e.g. `actCmn_Chadley_PV0510`) |
| Opening step | command 55 (camera `oblCmn_Camera_ChadoryCall`) + 15 (communicator with a lip-sync asset, the movie screen `FA2200_01_MovieDisplay` and the talker) | command 15 alone: `["", "TEMP_Communicator_Actor", "Ch02"]`, integers `0,0,5000,0,0,0,1,1` |
| Closing step | 63 + 14 | 14 |
| Lines | skippable | not skippable |

Command arguments come in blocks of 32 strings and 16 integers per command. Some calls also swap the face on the screen
(64) or fire a game trigger (25, e.g. `trg1200_COL30_GRASA_01_Free_vr`, which unlocks a VR course).

`tools/make_spec.py` finds every action whose chain opens a video call and rewrites it as an earpiece call: exclusion
`eclTypePlanLiveWin`, the earpiece opening, 63 and 64 dropped (the commands around them kept), lines unskippable. It
only touches chains that do nothing but talk, branch (29, 38) and fire triggers (25), where only Chadley, the VR
announcer and Cloud speak, and none of whose steps another chain uses. That is 82 chains (95 actions, 522 steps);
29 that move characters, fade or play effects are left alone and listed in the generator's report.

Tested on the first Lifespring's call (`PV_COMON_9510`): the lines played as subtitles over normal play, with no camera
cut and no communicator screen.

## Why one call is removed

A Lifespring runs an action group: photo mode off, Cloud's analysis pose (`PV_LSCMN_0015`, an event), the minigame,
the reward list and the hub clear (type 200). Cloud's pose is released by `actCmn_LifeSpot_Analysis_MotionOff`, which
the region's `HubGroup` row runs after its notification, in `acgCmn_LifeSpot_Clear_1st_Chadlie` together with
Chadley's call, or in `acgCmn_LifeSpot_Analysis_Motionoff_PhotoModeRelease` without it. The game gives control back
only when that group ends. As an earpiece call, the first Lifespring's call still held Cloud for its 16 seconds. So
`actHub_LifeSpot_Clear_1st_Chadlie` becomes a type-12 action (the game's own flag-only type, used by 284 actions) that
sets the call's end flag `stfWorldMap_FirstClear_LifeSpot_Chadlie`, as if it had played. No other hub group has a
Chadley call in it.

## The Region Intel banner (not removed yet)

"New region intel is now available." appears when a region's Lifespring hub group reaches a new state (1, 3 and 5
Lifesprings in the Grasslands). The group then runs `actHub_AreaReport_*_open` (type 205, which opens an `AreaReport`
entry). We turned those into type-12 actions that set the entry's open and unread flags directly; the entry still
opens, but the banner still showed, so the engine draws it from the group's state change itself. The hub group has no
switch for it, and removing its states would leave Cloud held for good. Hiding it needs a runtime script. The type-12
change is kept: it's harmless and shows the flags the 205 action sets.

## Measured control

Same save, Lifespring 1. Times from the minigame's end are read off the OBS recording (one frame a second); times from
the Region Intel tutorial pause come from the harness's telemetry file, sampled every 0.2 s.

| Build | Minigame end to control | Tutorial pause to control |
| --- | --- | --- |
| Unmodded | about 31 s (Completed banner, Region Intel banner, tutorial, Chadley video call) | |
| Banner removed, call as earpiece | | about 30 s (the call held Cloud to its last line) |
| 0.2: the first-Lifespring call removed | about 16 s (Region Intel banner, tutorial, the end of Cloud's pose) | about 10 s |

## Completion sequences (0.3)

A completion sequence gives control back only when every action it runs has ended. Besides the first Lifespring's
call, these run Chadley calls: all four action lists of `HubGroup` rows, the four notify fields of `WorldReport` rows,
and every action group that contains `actCmn_LifeSpot_Analysis_MotionOff` (for example
`acg1200_LifeSpot_Analysis_Motionoff_PhotoModeRelease_Craft_1`, which runs `actCmn_Chadley_PV0502` after the second
Grasslands Lifespring). `tools/make_spec.py` makes every converted call found there a type-12 action that keeps its
end flags and triggers (25 calls). Calls whose chains fire a trigger (command 25) keep playing, as earpiece calls.

The map that opens by itself to show new intel is `actHub_ShowNaviMap` / `actCmn_ShowNaviMap_<area>` (type 43). They
become type 12 too.

Tested on Grasslands Lifespring 4, same save, telemetry sampled every 0.2 s: from the Check press to control, 50 s
with 0.2 (Chadley's "transmuter chip" call, the "Excavation Intel 1" banner, the map) and 25.6 s with 0.3, of which
about 15 s is the minigame. What remains after the minigame: the reward list, a ~3 s "new intel" banner, the end of
Cloud's pose.

### Tried and reverted

- **`Hub.NotifyOnActivated = 0`** on the 55 hubs that announce their activation. The "new intel" banner went, and
  Cloud stayed frozen in the Lifespring pose for good: the hub group runs its after-notification actions, which
  release him, only once that notice has shown.
- **`HubGroup.Usage` 1 → 0** on the Lifespring groups (they are the only Usage-1 groups): the Region Intel banner
  still showed.
- **First-time tutorial tips** (`tools/tips_spec.py`, 119 tips: their Type-37 actions become Type 12 that set the
  tips' view flags and fire their close trigger; WorldCondition tip steps become close-trigger steps). With it, a
  Lifespring's minigame never started once and its completion sequence stalled once. Built with `-WithTips` only.
- **A UE4SS hook on `EndUserWidget:AddToViewportEx`** to name the Region Intel banner's widget: it loads (with an empty
  pre-callback, Junon Colosseum's pattern), but none of these widgets go through it.

## The combat assignment checklist (0.4)

The notify switch is one switch for the whole world-report display, so turning it off also took away the objective
list a combat assignment shows at the top left while it runs (`EventProgress_Mission_Cell`). The owner missed one
of three objectives without it, and asked for it back while the tick-box results pop-up at the end stays gone.

`HubConfig` has no separate switch for the two: its fields are the notify switch, `DisplayCompleteMessageForce`,
icon and route options, and a few flags about battle and fast travel. The hubs are what can be told apart. Combat
assignments are `Hub.Type` 3 (42 rows), and they share `HubConfig_WorldNormal` with the Lifesprings (type 4) and
the Divine Intel shrines (type 6), so the switch cannot simply be turned back on in that row.

So the mod adds three copies of those config rows with the switch left off -- `HubConfig_NoPopups_Mission`, and
its `_Demo` and `_Media` twins -- and points the 42 combat assignment hubs at them. Everything else keeps the
silent config. This is the first change that adds rows rather than only setting fields, and the first that
replaces the `Hub` table as well, which widens the conflict surface with other mods by one table.

What this does not do by itself: the completion banner for a combat assignment comes from the same display, so it
is expected back for those 42 hubs. Whether that is acceptable, or whether the banner needs removing another way,
is the open question for this feature.

## Side effects (audit, 0.3)

What each change reaches beyond what it was meant for, from the game's tables (2026-11-13). "Seen" means observed in
play; the rest is from the data and still needs a test.

**The notify switch (`DisableWorldReportNotify`).** The 13 configs cover every kind of world intel: towers (type 0),
Chocobo Intel (1), Fiend Intel (3), Lifesprings (4), Phenomenon Intel (5), Divine Intel shrines (6), Excavations (7),
Classified Intel (10) and Moogle Intel (11). Besides the completion banner it also removes:

- the combat assignment checklist at the top left (`EventProgress_Mission_Cell`). Seen by the owner: with no
  checklist, they missed one of three objectives without knowing until afterwards;
- the "Intel has been relayed to Chadley." message log line. Seen;
- possibly the same progress display in the other activities that have one (Moogle Intel, Excavations, Chocobo Intel,
  Phenomenon and Classified Intel). Not tested.

The owner wants the tick-box results popup at the end of a combat assignment (`MissionResult`) to stay gone, and the
checklist back.

**The 25 silenced calls (type 12).** These lines never play now, not even over the earpiece. What the player no longer
hears:

- after a region's Lifesprings (`..._Craft_1/2` groups): Chadley announcing new Transmuter chips. The recipes still
  unlock;
- after a region's combat assignments (`HubGroup_Area_*_ExSubjugation`): Chadley's call about the region's last
  challenge;
- the region-completion reports (`WorldReport_GRASA_31`, `JUNOA_26`, `CORLA_31`, `GONGA_26`, `CSMOA_31`,
  `NIBLA_25`);
- Chadley's tower calls in Junon, Gongaga and Cosmo Canyon (`HubGroup_Area_*_Tower`);
- the first Lifespring's call.

Flags and triggers are kept, so the unlocks still happen, but the player isn't told about them.

**The 82 earpiece calls.** Their lines can no longer be skipped. They now play during free movement, so a fight,
another conversation or a cutscene can start mid-call. Some of these calls unlock a VR course with a trigger at the
end (command 25). Whether that trigger still fires when a call is cut short hasn't been tested.

**The map pop-ups (type 43 to 12).** `actHub_ShowNaviMap` runs from 99 places: tower start-ups, Region Intel tiers and
others. Six `actCmn_ShowNaviMap_<area>` run when a place is discovered. The map no longer shows where the new intel
is; the icons are still on the map.

**Region Intel (type 205 to 12).** The entry opens and Classified Intel unlocks (seen in Junon and the Grasslands).
Anything else the 205 action does on top of the two flags would be missing. Nothing has been noticed so far.

**Not changed:** first-time tutorial panels still pause the game, and the "new intel" banner when a hub activates
still shows (it can't be removed by table without freezing Cloud).

**Compatibility.** The pak replaces whole tables: `Action`, `PlannerEvent` and `HubConfig`. Another mod that changes
any of them conflicts, and whichever pak loads last wins outright. The JunonCompat build carries Junon Colosseum's
version of those tables as it was at build time. After a Junon Colosseum update, the compat build must be rebuilt, or
it will undo that update's changes to those tables.

## Junon Colosseum

Junon Colosseum also replaces `Action` and `PlannerEvent`, and pak `JunonColosseum_999_P` loads after `NoPopups_P`
(a pak's number before `_P` sets its order). `-Variant JunonCompat` applies the same changes to Junon Colosseum's
tables and names the pak `NoPopups_JunonCompat_9999_P` so it loads last. The two mods change no rows in common. Tested
with Junon Colosseum enabled: the Lifespring behaved as with the standard pak. Junon Colosseum's own content was not
played in that test.

## Packaging

DataBuilder writes the changed tables; UnrealReZen packs them into `NoPopups_P.pak/.ucas/.utoc`. The build then writes the
10 bytes every Rebirth `.ucas` starts with over the start of UnrealReZen's `.ucas`, as Training Dummy does. In
UnrealReZen's output the first compressed block is its 44-byte container header chunk, and the table is the second
block, so this spoils only the header chunk. The build script checks that before writing.

UnrealReZen gives each build a new container ID, so two builds of the same tables aren't byte-identical. The table
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
