"""Generate data/generated.json: the table changes worked out from the game's own data.

Two changes:

1. Chadley's video calls become earpiece calls. A video call is an Action (exclusion eclTypePlanEvent...) whose
   PlannerEvent chain opens with command 55 (the call camera, oblCmn_Camera_ChadoryCall) plus command 15 (the
   communicator, with a lip-sync asset and the movie screen) and closes with 63 + 14. Chadley's earpiece calls
   (exclusion eclTypePlanLiveWin, e.g. actCmn_Chadley_PV0510) open with command 15 alone, in its "Ch02" form, and
   close with 14. Their voiced lines are the same rows, except that video-call lines can be skipped. So for each
   plain video call this sets the action's exclusion to eclTypePlanLiveWin, rewrites the opening step as the
   earpiece one, drops 63 from the closing step, drops the face-swap steps (64) and makes the lines unskippable.
   "Plain" means the chain uses no command beyond 55/15/63/14/64 and the branch, random and trigger commands
   (29, 38, 25), only Chadley, the VR announcer (SysVoiceGuide) and Cloud speak, and no step of it is shared with a
   chain left alone. Branches may open and close the call separately; each opening and closing is rewritten. Calls that move characters, fade or play
   effects (the Gilgamesh scenes, some Chadley's Request steps) are left alone.

2. Region Intel opens without its banner. Each actHub_AreaReport_*_open action is type 205, which opens an
   AreaReport row and shows "New region intel is now available.". It becomes type 12, which does nothing itself
   (the game uses it for 284 flag-only actions), and sets the AreaReport's open and unread flags at its end.

Reads the CSV exports of the game's tables (DataTableIndex). Usage:
    python tools/make_spec.py [--csv D:/FF7RebirthModding/DataTableIndex/Input/Resident] [--report build/report.json]
"""
import argparse, collections, csv, json, sys
from pathlib import Path

PLAIN_COMMANDS = {"55", "15", "63", "14", "64", "29", "38", "25"}
EARPIECE_OPEN = {
    "CommandArgumentList_Array": ["", "TEMP_Communicator_Actor", "Ch02"],
    "CommandTypeList_Array": ["15"],
    "CommandArgumentInteger_Array": ["0", "0", "5000", "0", "0", "0", "1", "1"],
    "Time": "0",
    "OutputType": "0",
}
EARPIECE_EXCLUSION = "eclTypePlanLiveWin"
# Chadley calls inside a completion group that holds Cloud until the group ends (see 3. below).
SILENCE = ("actHub_LifeSpot_Clear_1st_Chadlie",)


def load(path):
    rows = list(csv.reader(open(path, encoding="utf-8")))
    header = rows[0]
    names, last = [], None
    for column in header:
        if column.isdigit():
            names.append(f"{last}[{column}]")
        else:
            names.append(column); last = column
    out = {}
    for row in rows[1:]:
        if len(row) != len(header):
            continue
        out[row[1]] = {names[i]: v for i, v in enumerate(row) if v and v != "0    | "}
    return out


def array(row, field):
    """A CSV row's array field as a list, by column position (CSV exports pad arrays with empty columns)."""
    items = sorted(((int(k.split("[")[1][:-1]), v) for k, v in row.items() if k.startswith(field + "[")))
    return [v for _, v in items]


ARG_BLOCK, INT_BLOCK = 32, 16  # each command's slice of CommandArgumentList_Array / CommandArgumentInteger_Array


def without_commands(row, drop):
    """The step's three command arrays with the commands in ``drop`` removed and the others' blocks repacked."""
    types = array(row, "CommandTypeList_Array")
    args = array_padded(row, "CommandArgumentList_Array")
    ints = array_padded(row, "CommandArgumentInteger_Array")
    keep_types, keep_args, keep_ints = [], [], []
    for i, command in enumerate(types):
        if command in drop:
            continue
        keep_types.append(command)
        keep_args += (args[i * ARG_BLOCK:(i + 1) * ARG_BLOCK] + [""] * ARG_BLOCK)[:ARG_BLOCK]
        keep_ints += (ints[i * INT_BLOCK:(i + 1) * INT_BLOCK] + ["0"] * INT_BLOCK)[:INT_BLOCK]
    while keep_args and keep_args[-1] == "":
        keep_args.pop()
    while keep_ints and keep_ints[-1] == "0":
        keep_ints.pop()
    return {"CommandArgumentList_Array": keep_args, "CommandTypeList_Array": keep_types,
            "CommandArgumentInteger_Array": keep_ints}


def array_padded(row, field):
    """An array field with its CSV positions kept: missing positions become "" (or "0" for integers)."""
    items = {int(k.split("[")[1][:-1]): v for k, v in row.items() if k.startswith(field + "[")}
    if not items:
        return []
    blank = "0" if "Integer" in field else ""
    return [items.get(i, blank) for i in range(1, max(items) + 1)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", default=r"D:/FF7RebirthModding/DataTableIndex/Input/Resident")
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "data" / "generated.json"))
    parser.add_argument("--report", default=None)
    args = parser.parse_args()
    base = Path(args.csv)
    actions = load(base / "Action.csv")
    events = load(base / "PlannerEvent.csv")
    reports = load(base / "AreaReport.csv")

    def children(name):
        row = events.get(name, {})
        out = [v for k, v in row.items() if k.startswith("CommandArgumentList_Array") and v in events]
        if row.get("NextPE") in events:
            out.append(row["NextPE"])
        return out

    def chain(head):
        seen, todo = [], [head]
        while todo:
            name = todo.pop()
            if name in seen or name not in events:
                continue
            seen.append(name)
            todo.extend(children(name))
        return seen

    def commands(name):
        return array(events.get(name, {}), "CommandTypeList_Array")

    # Who refers to each PlannerEvent: other PlannerEvents, and actions.
    parents = collections.defaultdict(set)
    for name in events:
        for child in children(name):
            parents[child].add(name)
    heads_of = collections.defaultdict(list)
    for action, row in actions.items():
        head = row.get("StringArgumentList_Array[1]")
        if head in events:
            heads_of[head].append(action)

    report = {"converted": [], "skipped": []}
    convert_heads = {}
    for head, users in heads_of.items():
        nodes = chain(head)
        types = collections.Counter(t for n in nodes for t in commands(n))
        talkers = {events[n].get("Talker") for n in nodes} - {None}
        video = any("ChadoryCall" in v for n in nodes for k, v in events[n].items() if k.startswith("CommandArgumentList"))
        if not video:
            continue
        reason = None
        if set(types) - PLAIN_COMMANDS:
            reason = "commands " + ",".join(sorted(set(types) - PLAIN_COMMANDS))
        elif not talkers <= {"ComChadley", "SysChadley", "SysVoiceGuide", "Cloud"}:
            reason = "talkers " + ",".join(sorted(talkers))
        if reason:
            report["skipped"].append({"head": head, "actions": users, "reason": reason})
            continue
        convert_heads[head] = (users, nodes)

    # A step reached from a chain left alone must stay as it is, so drop candidates until none shares one.
    while True:
        covered = {n for _, nodes in convert_heads.values() for n in nodes}
        dropped = []
        for head, (users, nodes) in convert_heads.items():
            shared = [n for n in nodes if n != head and parents[n] - covered]
            if shared:
                dropped.append(head)
                report["skipped"].append({"head": head, "actions": users, "reason": "shares " + ",".join(shared[:3])})
        if not dropped:
            break
        for head in dropped:
            del convert_heads[head]

    event_rows, action_rows = {}, {}
    for head, (users, nodes) in sorted(convert_heads.items()):
        for name in nodes:
            row, types = events[name], commands(name)
            if "55" in types:
                if set(types) - {"55", "15", "64"}:
                    raise SystemExit(f"{name}: call opening is {types}, expected 55 with 15 or 64")
                event_rows[name] = dict(EARPIECE_OPEN)
            elif "63" in types or "64" in types:
                event_rows[name] = without_commands(row, {"63", "64"})
            if row.get("Talker") and row.get("CanSkip") == "1":
                event_rows.setdefault(name, {})["CanSkip"] = "0"
        for action in users:
            if actions[action].get("ExclusionID") != EARPIECE_EXCLUSION:
                action_rows[action] = {"ExclusionID": EARPIECE_EXCLUSION}
        report["converted"].append({"head": head, "actions": users})

    area_rows = {}
    for action, row in sorted(actions.items()):
        if row.get("Type") != "205":
            continue
        target = row.get("StringArgumentList_Array[1]")
        report_row = reports.get(target)
        if not report_row or not report_row.get("OpenStoryFlagID"):
            raise SystemExit(f"{action}: no AreaReport {target}")
        if array(row, "EndStoryFlag_Array"):
            raise SystemExit(f"{action}: already sets flags")
        flags = [report_row["OpenStoryFlagID"]] + ([report_row["UnreadStoryFlagID"]] if report_row.get("UnreadStoryFlagID") else [])
        area_rows[action] = {"Type": "12", "StringArgumentList_Array": [], "EndStoryFlag_Array": flags}
    report["region_intel"] = sorted(area_rows)

    # 3. Calls that hold Cloud even as earpiece calls. A hub group runs its "after notification" actions as part of the
    #    completion sequence and gives control back only when they end (live 2026-11-12: the first Lifespring's call,
    #    as an earpiece call, still held Cloud for its 16 s). Every converted call a hub group runs that way becomes a
    #    type-12 action that keeps its own end flags and triggers, as if it had played. Calls whose chains do anything
    #    but talk and branch (a trigger, 25) keep playing, as earpiece calls.
    hub_groups = load(base / "HubGroup.csv")
    action_groups = load(base / "ActionGroup.csv")
    world_reports = load(base / "WorldReport.csv")

    def members(name):
        return [name] if name in actions else array(action_groups.get(name, {}), "ActionGroupLIst_Array")

    # Everything a completion sequence runs: all four hub-group action lists, the world reports' notify actions
    # (live: act1200_Chadley_Talk runs before Excavation Intel 1 completes), and every action group that releases
    # Cloud's Lifespring pose (live: acg1200_LifeSpot_..._Craft_1 runs Chadley's call PV0502 after the release, and
    # it still held Cloud for 12 s as an earpiece call).
    after = set()
    for row in hub_groups.values():
        for field in ("ActiveStateActionOrActionGroupID_Array", "AfterNotificationInActivateActionOrActionGroupID_Array",
                      "CompleteStateActionOrActionGroupID_Array", "AfterNotificationInCompleteActionOrActionGroupID_Array"):
            for name in array(row, field):
                after.update(members(name))
    for row in world_reports.values():
        for field in ("PreOpenNotifyActionOrActionGroupID", "PostOpenNotifyActionOrActionGroupID",
                      "PreCompleteNotifyActionOrActionGroupID", "PostCompleteNotifyActionOrActionGroupID"):
            if row.get(field):
                after.update(members(row[field]))
    for name, row in action_groups.items():
        listed = array(row, "ActionGroupLIst_Array")
        if "actCmn_LifeSpot_Analysis_MotionOff" in listed:
            after.update(listed)
    converted = {a for c in report["converted"] for a in c["actions"]}
    silence = set(SILENCE)
    for action in sorted(after & converted):
        head = actions[action].get("StringArgumentList_Array[1]")
        if not {t for n in chain(head) for t in commands(n)} & {"25"}:
            silence.add(action)
    for action in sorted(silence):
        row = actions[action]
        flags = array(row, "EndStoryFlag_Array")
        if not flags and action in SILENCE:
            raise SystemExit(f"{action}: silencing it would lose no flag; check it is still the call it was")
        area_rows[action] = {"Type": "12", "StringArgumentList_Array": [], "ExclusionID": "eclNone", "EndStoryFlag_Array": flags}
    report["silenced"] = sorted(silence)
    for action in silence:
        action_rows.pop(action, None)

    # 4. The map that opens by itself to show new intel (live: after the second Grasslands Lifespring, actHub_ShowNaviMap
    #    opened the area map and paused the game). These type-43 actions become type 12, keeping any trigger they fire.
    for action, row in sorted(actions.items()):
        if row.get("Type") == "43" and (action == "actHub_ShowNaviMap" or action.startswith("actCmn_ShowNaviMap_")):
            area_rows[action] = {"Type": "12", "StringArgumentList_Array": [], "IntegerArgumentList_Array": [],
                                 "ExclusionID": "eclNone"}
    report["map_popups"] = sorted(a for a in area_rows if "ShowNaviMap" in a)

    # Not done: Hub.NotifyOnActivated = 0 (the "new intel" banner). Live 2026-11-12 it froze Cloud in the Lifespring pose
    # for good: the hub group runs its after-notification actions, which release him, only once that notice has shown.


    overlap = set(action_rows) & set(area_rows)
    if overlap:
        raise SystemExit(f"actions changed twice: {sorted(overlap)}")
    action_rows.update(area_rows)
    spec = {"tables": [
        {"asset": "DataObject/Resident/Action.uasset",
         "rows": [{"name": n, "set": s} for n, s in sorted(action_rows.items())]},
        {"asset": "DataObject/Resident/PlannerEvent.uasset",
         "rows": [{"name": n, "set": s} for n, s in sorted(event_rows.items())]},
    ]}
    Path(args.out).write_text(json.dumps(spec, indent=1) + "\n", encoding="utf-8")
    print(f"{len(report['converted'])} video calls converted ({sum(len(c['actions']) for c in report['converted'])} actions, "
          f"{len(event_rows)} PlannerEvent rows); {len(report['skipped'])} left alone; "
          f"{len(area_rows)} flag-only actions ({len(silence)} silenced calls, {len(report['map_popups'])} map pop-ups), "
          f"-> {args.out}")
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
