"""Generate data/generated-tips.json: first-time field tutorial panels ("tips") that open on their own stop opening.

How the game opens a field tip (FieldTips row), from the CSV exports:

1. An Action of Type 37 (ExclusionID eclTypeTutorial...). StringArgumentList_Array is
   [tip, manager object, manager state group, manager flag, title tip, close trigger, more pages...]: index 0 is the
   panel shown, 4 the tip it is filed under, 5 the trigger fired when the player closes it (trgCmn_Tutorial_End),
   6+ further pages. StateChange EnterActionList, ActionGroup, WorldReport post-notify and WorldCondition steps run
   these actions; minigame code and code-only callers run others.
2. A WorldCondition step of type 3. A row's steps are parallel arrays: Action_Array (1 fire a trigger, 2 run an
   Action, 3 show a tip), two NameArgument_Array and two IntegerArgument_Array entries per step, one
   CompleteStoryFlag_Array entry (set when the step completes) and one WaitForFinish_Array entry. A tip step's names
   are [tip, close trigger].
3. PlannerEvent command 21 inside event chains, command 68 (a "view tutorial" option in a choice menu, chosen by the
   player) and Type 309 battle-tutorial actions. Left alone.

Viewing a tip sets its FieldTips.FlagTrueOnViewWidget_Array flags (stfManual_Field_Tutorial_*); the in-menu manual
entry is the Manual row whose ViewFlag is that flag.

The change:

A. Each Type-37 action in scope becomes a Type-12 action (the game's flag-only type; actCmn_Tutorial_CloseTrigger is a
   vanilla Type-12 action that only fires trgCmn_Tutorial_End). It keeps its own EndStoryFlag_Array and gains the view
   flags of every tip it names, so the manual entries still unlock, and fires the tip's close trigger at its end
   (EndStateTriggerList_Array), so anything waiting for the panel to close carries on.
B. Each WorldCondition tip step becomes a type-2 step running actCmn_Tutorial_CloseTrigger, keeping its completion
   flag and wait. One type-2 step per view flag of the row's tips is appended (completion flag = that view flag, no
   wait), so the manual entries still unlock.

Left alone (and listed): battle tutorials, interactive "polling" tutorials, tips run by minigame code or by another
action, tips no table runs (shown from code; --include-code-invoked converts them too), and tips whose close trigger a
separate quest state waits for, where an instant close might arrive before that state starts waiting.

Refuses (exits) on any tip action, WorldCondition step or trigger wait it cannot classify.

Usage:
    python tools/tips_spec.py [--csv D:/FF7RebirthModding/DataTableIndex/Input] [--out data/generated-tips.json]
                              [--include-code-invoked] [--report build/tips-report.json]
"""
import argparse, collections, csv, json, sys
from pathlib import Path

CLOSE_ACTION = "actCmn_Tutorial_CloseTrigger"
CLOSE_TRIGGER = "trgCmn_Tutorial_End"
FIELD_EXCLUSIONS = {"eclTypeTutorial", "eclTypeTutorialFld", "eclTypeLastTutorial"}
# Columns through which the game's field data runs an action.
RUNNERS = {("StateChange", "EnterActionList_Array"), ("ActionGroup", "ActionGroupLIst_Array"),
           ("WorldReport", "PostCompleteNotifyActionOrActionGroupID"),
           ("WorldReport", "PreCompleteNotifyActionOrActionGroupID"),
           ("WorldReport", "PostOpenNotifyActionOrActionGroupID"), ("WorldReport", "PreOpenNotifyActionOrActionGroupID"),
           ("WorldCondition", "NameArgument_Array")}
# Quest states that wait for a tip's close trigger without opening the tip themselves. If the tip closed instantly it
# could fire before the state starts waiting and the quest would stall, so the tips feeding them stay.
FOREIGN_WAITS = {
    "scg1300_Quest07_Get_YamaChocobo_Wait2": "Junon Quest07: waits after the chocobo stop (Area_1300_Hub_1_1) completes",
    "scg1300_Quest10_Get_YamaChocobo_Wait2": "Junon Quest10: same chocobo stop wait",
    "scg2200_Qst17_BlackCloakReactionLight_Ini2": "Corel Qst17: waits after cinema 2010",
    "scg2200_Qst17_BlackCloakReactionLight_Log_Init2": "Corel Qst17: waits after cinema 2010",
    "scg2400_Task_Quest25_Minigame_StartWait": "Gongaga Quest25: waits before the chicken minigame",
    "scg2500_Log_Quest30_CheckMemo1_Wait": "Cosmo Quest30: waits after the tutorial kick",
    "scg2660_ActionLimit_BenchTutorial": "Nibelheim bench: fed by PlannerEvent command 21 (left alone)",
}
RACE = {
    "actCmn_Tutorial_World_Chocobo_Mountain": "scg1300_Quest07/10_Get_YamaChocobo_Wait2",
    "actCmn_Tutorial_Fld_04_0010": "scg1300_Quest07/10_Get_YamaChocobo_Wait2",
    "actCmn_Tutorial_Fld_07_0510": "scg2200_Qst17_BlackCloakReactionLight_Ini2",
    "actCmn_Tutorial_Fld_Qst25_0010": "scg2400_Task_Quest25_Minigame_StartWait",
    "actCmn_Tutorial_Fld_Qst25_0020": "scg2400_Task_Quest25_Minigame_StartWait",
    "actCmn_Tutorial_Fld_Qst25_0030": "scg2400_Task_Quest25_Minigame_StartWait",
    "actCmn_Tutorial_Fld_Qst25_1010": "scg2400_Task_Quest25_Minigame_StartWait",
    "actCmn_Tutorial_Fld_Qst30_0010": "scg2500_Log_Quest30_CheckMemo1_Wait",
    # Fires its own trg2600_MiniGame_END_Talk at its end, which Nibelheim Quest33 and WorldStory02 states wait for.
    "actCmn_Tutorial_World_Chocobo_Ocean": "scg2600_Quest33_ChocoboGet_Event_110_* and others (trg2600_MiniGame_END_Talk)",
}


def read(path):
    """CSV rows as {column: value}, array columns as "Field[i]" (1-based); padding cells dropped."""
    rows = list(csv.reader(open(path, encoding="utf-8", errors="replace")))
    if not rows:
        return {}, []
    header, names, last = rows[0], [], None
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
    return out, names


def load(path):
    return read(path)[0]


def array(row, field, blank=""):
    """An array field with its positions kept (CSV index 1 is element 0); gaps become ``blank``."""
    items = {int(k.split("[")[1][:-1]): v for k, v in row.items() if k.startswith(field + "[")}
    if not items:
        return []
    return [items.get(i, blank) for i in range(1, max(items) + 1)]


def column_base(name):
    return name.split("[")[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", default=r"D:/FF7RebirthModding/DataTableIndex/Input")
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "data" / "generated-tips.json"))
    parser.add_argument("--report", default=None)
    parser.add_argument("--include-code-invoked", action="store_true",
                        help="also convert tip actions that no table runs (the game's code opens them)")
    args = parser.parse_args()
    root = Path(args.csv)
    res = root / "Resident"

    tips = load(res / "FieldTips.csv")
    actions = load(res / "Action.csv")
    conditions = load(res / "WorldCondition.csv")
    manual_views = {r.get("ViewFlag") for r in load(res / "Manual.csv").values()} - {None}
    story_flags = set(load(res / "StoryFlag.csv"))
    triggers = set(load(res / "StateTrigger.csv")) | set(load(res / "ResidentStateTrigger.csv"))

    def view_flags(tip):
        return array(tips[tip], "FlagTrueOnViewWidget_Array")

    close = actions.get(CLOSE_ACTION)
    if not close or close.get("Type") != "12" or array(close, "EndStateTriggerList_Array") != [CLOSE_TRIGGER] \
            or array(close, "StartStateCondition_Array") or array(close, "StringArgumentList_Array"):
        raise SystemExit(f"{CLOSE_ACTION} is no longer a plain Type-12 action firing {CLOSE_TRIGGER}")

    # Every table cell naming a candidate action or a tip, and every state waiting for a close trigger.
    tip_actions = {n for n, r in actions.items()
                   if any(v in tips for k, v in r.items() if k.startswith("StringArgumentList_Array["))}
    users = collections.defaultdict(set)
    tip_users = collections.defaultdict(set)
    field_tip_actions = []
    waits = []  # (file, state, entered actions): states waiting for CLOSE_TRIGGER
    waiters = collections.defaultdict(list)  # trigger -> [(state, entered actions)]
    planner_21, planner_68 = [], []
    for path in sorted(root.rglob("*.csv")):
        rows, names = read(path)
        table = path.stem
        rel = str(path.relative_to(root))
        for row_name, row in rows.items():
            for key, value in row.items():
                if key == "Name":
                    continue
                if value in tip_actions:
                    users[value].add((table, column_base(key), rel, row_name))
                if value in tips:
                    tip_users[value].add((table, column_base(key)))
            if table == "StateChange":
                waited = array(row, "StateTriggerList_Array")
                for trigger in waited:
                    waiters[trigger].append((row_name, array(row, "EnterActionList_Array")))
                if CLOSE_TRIGGER in waited:
                    waits.append((rel, row_name, array(row, "EnterActionList_Array")))
            if table == "Action" and path.parent != res and row.get("Type") in ("37", "309"):
                field_tip_actions.append((rel, row_name))
            if table == "PlannerEvent":
                types = array(row, "CommandTypeList_Array")
                arguments = array(row, "CommandArgumentList_Array")
                for i, command in enumerate(types):
                    block = arguments[i * 32:(i + 1) * 32]
                    shown = [v for v in block if v in tips]
                    if shown and command == "21":
                        planner_21.append((rel, row_name, shown[0]))
                    elif shown and command == "68":
                        planner_68.append((rel, row_name, shown))
                    elif shown:
                        raise SystemExit(f"{rel} {row_name}: command {command} names tip {shown}; unclassified")

    # Trigger waits: a state that opens the tip itself is safe (vanilla runs Type-12 actions this way thousands of
    # times: enter an action, wait for the trigger it fires at its end). Any other wait must be one we know.
    for rel, state, entered in waits:
        if any(a in tip_actions for a in entered):
            continue
        if state not in FOREIGN_WAITS:
            raise SystemExit(f"{rel} {state} waits for {CLOSE_TRIGGER} and opens no tip itself; classify it first")

    report = collections.OrderedDict(converted=[], excluded=collections.defaultdict(list), world_condition=[],
                                     left_alone={})
    action_rows = {}
    silenced_tips = set()
    for name in sorted(tip_actions):
        row = actions[name]
        kind = row.get("Type")
        sa = array(row, "StringArgumentList_Array")
        exclusion = row.get("ExclusionID", "")
        named_tips = [v for v in sa if v in tips]

        def skip(reason):
            report["excluded"][reason].append(name)

        if kind == "309":
            skip("battle tutorial (Type 309)"); continue
        if kind != "37":
            raise SystemExit(f"{name}: Type {kind} names tips {named_tips}; unclassified")
        if exclusion.startswith("eclTypeTutorialonBattle") or any("_Btl_" in t for t in named_tips):
            skip("battle tutorial"); continue
        if any(sa[1:4]):
            skip("interactive tutorial (polling manager)"); continue
        if exclusion not in FIELD_EXCLUSIONS:
            raise SystemExit(f"{name}: Type 37 with exclusion {exclusion}; unclassified")
        if len(sa) < 5 or sa[0] not in tips or sa[4] not in tips:
            raise SystemExit(f"{name}: unexpected arguments {sa}")
        trigger = sa[5] if len(sa) > 5 else ""
        if trigger and trigger not in triggers:
            raise SystemExit(f"{name}: argument 5 {trigger} is not a trigger")
        if any(v and v not in tips for v in sa[6:]):
            raise SystemExit(f"{name}: unexpected page arguments {sa[6:]}")
        own_triggers = array(row, "EndStateTriggerList_Array")
        if name in RACE:
            skip(f"close trigger awaited by another quest state ({RACE[name]})"); continue
        runners = {(t, c) for t, c, _, _ in users[name]}
        other = runners - RUNNERS
        if other:
            skip("run by minigame code or another action (" + ", ".join(sorted(f"{t}.{c}" for t, c in other)) + ")")
            continue
        if not runners and not args.include_code_invoked:
            skip("no table runs it (opened from code; --include-code-invoked)"); continue
        # Its own end triggers now fire at once: refuse if a state that does not run this action waits for one.
        for own in own_triggers:
            stray = [s for s, entered in waiters[own] if name not in entered]
            if stray:
                raise SystemExit(f"{name}: {own} is awaited by {stray}; classify it (RACE) first")

        flags = []
        for tip in [sa[0], sa[4]] + [v for v in sa[6:] if v]:
            for flag in view_flags(tip):
                if flag not in story_flags:
                    raise SystemExit(f"{name}: view flag {flag} of {tip} is not a story flag")
                if flag not in flags:
                    flags.append(flag)
            silenced_tips.add(tip)
        end_flags = array(row, "EndStoryFlag_Array")
        action_rows[name] = {
            "Type": "12",
            "ExclusionID": "eclNone",
            "StringArgumentList_Array": [],
            "IntegerArgumentList_Array": [],
            "EndStoryFlag_Array": end_flags + [f for f in flags if f not in end_flags],
            "EndStateTriggerList_Array": own_triggers + ([trigger] if trigger and trigger not in own_triggers else []),
        }
        report["converted"].append({"action": name, "tips": named_tips, "flags": flags,
                                    "runners": sorted(f"{t}.{c}" for t, c in runners) or ["code"]})

    # B. WorldCondition tip steps.
    condition_rows = {}
    for name, row in sorted(conditions.items()):
        steps = array(row, "Action_Array", "0")
        if "3" not in steps:
            continue
        n = len(steps)
        names = (array(row, "NameArgument_Array") + [""] * 2 * n)[:2 * n]
        ints = (array(row, "IntegerArgument_Array", "0") + ["0"] * 2 * n)[:2 * n]
        done = (array(row, "CompleteStoryFlag_Array") + [""] * n)[:n]
        wait = (array(row, "WaitForFinish_Array", "0") + ["0"] * n)[:n]
        if len(array(row, "NameArgument_Array")) > 2 * n or len(array(row, "CompleteStoryFlag_Array")) > n:
            raise SystemExit(f"{name}: more step arguments than steps; layout unknown")
        flags = []
        for i, step in enumerate(steps):
            if step not in ("1", "2", "3"):
                raise SystemExit(f"{name}: step {i} type {step}; unclassified")
            if step != "3":
                continue
            tip, trigger = names[2 * i], names[2 * i + 1]
            if tip not in tips or trigger not in ("", CLOSE_TRIGGER):
                raise SystemExit(f"{name}: tip step {i} names {tip!r}, {trigger!r}")
            steps[i] = "2"
            names[2 * i:2 * i + 2] = [CLOSE_ACTION, ""]
            ints[2 * i:2 * i + 2] = ["0", "0"]
            silenced_tips.add(tip)
            for flag in view_flags(tip):
                if flag not in story_flags:
                    raise SystemExit(f"{name}: view flag {flag} of {tip} is not a story flag")
                if flag not in flags and flag not in done:
                    flags.append(flag)
        for flag in flags:
            steps.append("2"); names += [CLOSE_ACTION, ""]; ints += ["0", "0"]; done.append(flag); wait.append("0")
        condition_rows[name] = {"Action_Array": steps, "NameArgument_Array": names, "IntegerArgument_Array": ints,
                                "CompleteStoryFlag_Array": done, "WaitForFinish_Array": wait}
        report["world_condition"].append({"row": name, "flags": flags})

    # Rows other generators already change in the same tables.
    generated = Path(args.out).with_name("generated.json")
    if generated.exists():
        spec = json.loads(generated.read_text(encoding="utf-8"))
        for table in spec.get("tables", []):
            mine = action_rows if table["asset"].endswith("/Action.uasset") else \
                condition_rows if table["asset"].endswith("/WorldCondition.uasset") else {}
            overlap = sorted({r["name"] for r in table["rows"]} & set(mine))
            if overlap:
                raise SystemExit(f"{generated.name} already changes {overlap}")

    tables = []
    if action_rows:
        tables.append({"asset": "DataObject/Resident/Action.uasset",
                       "rows": [{"name": n, "set": s} for n, s in sorted(action_rows.items())]})
    if condition_rows:
        tables.append({"asset": "DataObject/Resident/WorldCondition.uasset",
                       "rows": [{"name": n, "set": s} for n, s in sorted(condition_rows.items())]})
    Path(args.out).write_text(json.dumps({"tables": tables}, indent=1) + "\n", encoding="utf-8")

    unrun_tips = sorted(t for t in tips if not tip_users[t])
    report["left_alone"] = {
        "field_polling_actions": [f"{p} {n}" for p, n in field_tip_actions],
        "planner_event_command_21": [f"{p} {n} {t}" for p, n, t in planner_21],
        "planner_event_command_68_menu_option": len(planner_68),
        "tips_named_by_no_table": unrun_tips,
    }
    report["excluded"] = dict(report["excluded"])

    unlocked = {f for c in report["converted"] for f in c["flags"]} | \
               {f for c in report["world_condition"] for f in c["flags"]}
    print(f"Tip actions: {len(tip_actions)} in Resident Action ({len(report['converted'])} -> Type 12)")
    for reason, items in sorted(report["excluded"].items(), key=lambda x: -len(x[1])):
        print(f"  left alone, {reason}: {len(items)}")
        if len(items) <= 12:
            print("    " + ", ".join(items))
    print(f"WorldCondition rows with tip steps: {len(condition_rows)} "
          f"({sum(r['Action_Array'].count('2') for r in condition_rows.values())} type-2 steps after the change)")
    print(f"Tips silenced: {len(silenced_tips)} of {len(tips)}; view flags still set: {len(unlocked)}, "
          f"{len(unlocked & manual_views)} of them unlock a Manual entry")
    print(f"Trigger waits on {CLOSE_TRIGGER}: {len(waits)} states, "
          f"{sum(1 for _, s, _ in waits if s in FOREIGN_WAITS)} fed from elsewhere (their tips left alone)")
    print(f"Not touched: {len(field_tip_actions)} Field-table polling actions, {len(planner_21)} PlannerEvent command-21 "
          f"steps, {len(planner_68)} command-68 menu options, {len(unrun_tips)} tips no table names")
    print(f"-> {args.out}")
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
