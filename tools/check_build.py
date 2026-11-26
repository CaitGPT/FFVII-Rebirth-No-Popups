"""Offline row checks for a built No Popups pak (1.0.1 layout).

    python tools/check_build.py <build root> <variant folder> [--classified-panel]

Exports HubConfig and Hub from the variant's Base (the tables it started from) and Staging (what it packed) with
DataBuilder, then checks:
  - the 13 world intel configs have the notice switch on, and no other config changed;
  - the Fiend Intel copies exist, equal their source config except the switch (off), and every Hub.Type 3 row points
    at the copy matching its own config (plain, _Demo, _Media);
  - the chocobo capture copies (1.0.4) exist the same way, and the Junon, Cosmo Canyon and Nibelheim capture hubs point
    at them;
  - the Classified Intel rows (Hub.Type 10) keep their own config (or, with --classified-panel, point at the
    Classified copies);
  - no other Hub row changed.
Exits 1 on the first list of failures.
"""
import csv
import os
import subprocess
import sys
import tempfile

SWITCHED = [
    "HubConfig_WorldNormal", "HubConfig_WorldNormal_Demo", "HubConfig_WorldNormal_Media",
    "HubConfig_WorldReport_SysOpen", "HubConfig_WorldReport_SysOpen_BattleOFF",
    "HubConfig_WorldReport_SysOpen_AllowNotify_OutOfArea", "HubConfig_WorldReport_SysOpen_Demo",
    "HubConfig_WorldReport_SysOpen_Media", "HubConfig_WorldReport_getoffChocobo",
    "HubConfig_WorldReport_getoffChocobo_Demo", "HubConfig_WorldReport_getoffChocobo_Media",
    "HubConfig_WorldReport_moogleShop", "HubConfig_WorldReport_moogleShop_Demo",
]
COPIES = {"HubConfig_NoPopups_FiendIntel": "HubConfig_WorldNormal",
          "HubConfig_NoPopups_FiendIntel_Demo": "HubConfig_WorldNormal_Demo",
          "HubConfig_NoPopups_FiendIntel_Media": "HubConfig_WorldNormal_Media"}
CHOCOBO_COPIES = {"HubConfig_NoPopups_ChocoboCapture": "HubConfig_WorldNormal",
                  "HubConfig_NoPopups_ChocoboCapture_Demo": "HubConfig_WorldNormal_Demo"}
CHOCOBO_HUBS = {"Area_1300_Hub_1_1": "HubConfig_NoPopups_ChocoboCapture",
                "Area_1300_Hub_1_1_Demo": "HubConfig_NoPopups_ChocoboCapture_Demo",
                "Area_2500_Hub_1_1": "HubConfig_NoPopups_ChocoboCapture",
                "Area_2600_Hub_1_1": "HubConfig_NoPopups_ChocoboCapture"}
CLASSIFIED_COPIES = {"HubConfig_NoPopups_Classified": "HubConfig_WorldReport_SysOpen",
                     "HubConfig_NoPopups_Classified_Demo": "HubConfig_WorldReport_SysOpen_Demo",
                     "HubConfig_NoPopups_Classified_Media": "HubConfig_WorldReport_SysOpen_Media"}
# The VR course notices' calls (Colosseum Pre/PostNotify) and the calls they branch to, left as video calls in 1.0.2.
VR_NOTICE_CALLS = ["0550", "3500", "4500", "5500", "6500", "7500", "0505", "0506", "0507", "3100", "3101",
                   "4200", "4201", "4202", "5100", "5101", "5102", "6100", "6101", "6102", "7100", "7101"]
SWITCH = "DisableWorldReportNotify"
# Fields a cloned row is allowed to differ in besides the switch (its own key).
OWN = {"UniqueIndex"}


def export(builder, uasset):
    out = tempfile.NamedTemporaryFile(suffix=".csv", delete=False).name
    subprocess.run(["dotnet", builder, "export", uasset, out], check=True, capture_output=True)
    rows = {}
    with open(out, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.setdefault(r["Name"], {})[r["Property"]] = r["Value"]
    os.unlink(out)
    return rows


def suffix(name):
    return "_Demo" if name.endswith("_Demo") else "_Media" if name.endswith("_Media") else ""


def main():
    root, variant = sys.argv[1], sys.argv[2]
    panel = "--classified-panel" in sys.argv
    video = "--vr-video" in sys.argv
    builder = os.path.join(root, "DataBuilderBin", "DataBuilder.dll")
    rel = os.path.join("End", "Content", "DataObject", "Resident")
    base_dir = os.path.join(root, variant, "Base", rel)
    out_dir = os.path.join(root, variant, "Staging", "End", "Content", "DataObject", "Resident")
    fails = []
    bc, oc = export(builder, os.path.join(base_dir, "HubConfig.uasset")), export(builder, os.path.join(out_dir, "HubConfig.uasset"))
    bh, oh = export(builder, os.path.join(base_dir, "Hub.uasset")), export(builder, os.path.join(out_dir, "Hub.uasset"))

    copies = dict(COPIES, **CHOCOBO_COPIES)
    if panel:
        copies.update(CLASSIFIED_COPIES)
    for name, row in oc.items():
        if name in copies:
            source = oc[copies[name]]
            for k, v in row.items():
                if k == SWITCH:
                    if v != "0":
                        fails.append(f"{name}.{SWITCH} is {v}, want 0")
                elif k not in OWN and v != source.get(k):
                    fails.append(f"{name}.{k} is {v!r}, its source {copies[name]} has {source.get(k)!r}")
        elif name in SWITCHED:
            if row.get(SWITCH) != "1":
                fails.append(f"{name}.{SWITCH} is {row.get(SWITCH)}, want 1")
        elif name not in bc:
            fails.append(f"unexpected new config {name}")
        elif row != bc[name]:
            fails.append(f"config {name} changed")
    for name in copies:
        if name not in oc:
            fails.append(f"missing config {name}")

    types = {"3": 0, "10": 0}
    for name, row in oh.items():
        before = bh.get(name)
        if before is None:
            fails.append(f"unexpected new hub {name}")
            continue
        kind = row.get("Type", "").split()[0] if row.get("Type") else ""
        changed = {k for k in row if row[k] != before.get(k)}
        if name in CHOCOBO_HUBS:
            if row["ConfigID"] != CHOCOBO_HUBS[name]:
                fails.append(f"{name}.ConfigID is {row['ConfigID']}, want {CHOCOBO_HUBS[name]}")
            if changed - {"ConfigID"}:
                fails.append(f"{name} also changed {sorted(changed - {'ConfigID'})}")
        elif kind == "3":
            types["3"] += 1
            want = "HubConfig_NoPopups_FiendIntel" + suffix(before["ConfigID"])
            if row["ConfigID"] != want:
                fails.append(f"{name}.ConfigID is {row['ConfigID']}, want {want}")
            if changed - {"ConfigID"}:
                fails.append(f"{name} also changed {sorted(changed - {'ConfigID'})}")
        elif kind == "10":
            types["10"] += 1
            want = ("HubConfig_NoPopups_Classified" + suffix(before["ConfigID"])) if panel else before["ConfigID"]
            if row["ConfigID"] != want:
                fails.append(f"{name}.ConfigID is {row['ConfigID']}, want {want}")
            if changed - {"ConfigID"}:
                fails.append(f"{name} also changed {sorted(changed - {'ConfigID'})}")
        elif changed:
            fails.append(f"hub {name} (type {kind}) changed {sorted(changed)}")
    if types["3"] != 42 or types["10"] != 8:
        fails.append(f"found {types['3']} Fiend Intel and {types['10']} Classified Intel hubs, want 42 and 8")

    # 1.0.2 (issue #2): the VR course notices' calls stay as the game has them, every action and every step of their
    # chains, because a combat assignment's completion waits for them.
    ba, oa = export(builder, os.path.join(base_dir, "Action.uasset")), export(builder, os.path.join(out_dir, "Action.uasset"))
    bp, op = export(builder, os.path.join(base_dir, "PlannerEvent.uasset")), export(builder, os.path.join(out_dir, "PlannerEvent.uasset"))
    notice = [f"actCmn_Chadley_PV{n}" for n in VR_NOTICE_CALLS]
    steps = set()
    for action in notice:
        if action not in ba or oa.get(action) != ba[action]:
            fails.append(f"VR course call {action} changed or missing")
        todo = ba.get(action, {}).get("StringArgumentList_Array", "").split("|")[:1]
        while todo:
            name = todo.pop()
            if not name or name in steps or name not in bp:
                continue
            steps.add(name)
            todo.append(bp[name].get("NextPE", ""))
            todo += bp[name].get("CommandArgumentList_Array", "").split("|")
    # Unless the build keeps the video call (--vr-video), each course call's opening step (the one with command 55)
    # fires the course trigger its chain fires (25) and ends the chain; every other step stays as it was.
    rewritten = 0
    for name in sorted(steps):
        before, after = bp[name], op.get(name)
        if not video and "55" in before.get("CommandTypeList_Array", "").split("|"):
            head = name.rsplit("_", 1)[0]
            fired = []
            for n in sorted(steps):
                kinds = bp[n].get("CommandTypeList_Array", "").split("|")
                if n.startswith(head + "_") and "25" in kinds:
                    # Each command has a block of 32 arguments; the trigger's name is the first of its block.
                    fired.append(bp[n]["CommandArgumentList_Array"].split("|")[32 * kinds.index("25")])
            want = dict(before, CommandTypeList_Array="25", CommandArgumentList_Array="|".join(fired),
                        CommandArgumentInteger_Array="", NextPE="")
            if len(fired) != 1 or after != want:
                fails.append(f"VR course call step {name} is not the trigger-only step for {fired}")
            rewritten += 1
        elif after != before:
            fails.append(f"VR course call step {name} changed")
    if not video and rewritten != 16:
        fails.append(f"{rewritten} VR course call openings rewritten, want 16")
    if len(steps) < 60:
        fails.append(f"only {len(steps)} VR course call steps found; the chain walk is not reading the export")

    print(f"{variant}: {len(oc)} configs, {len(oh)} hubs, {types['3']} Fiend Intel, {types['10']} Classified Intel, "
          f"{len(notice)} VR course calls with {len(steps)} steps")
    if fails:
        print("\n".join("FAIL " + f for f in fails))
        return 1
    print("all row checks pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
