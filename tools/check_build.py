"""Offline row checks for a built No Popups pak (1.0.1 layout).

    python tools/check_build.py <build root> <variant folder> [--classified-panel]

Exports HubConfig and Hub from the variant's Base (the tables it started from) and Staging (what it packed) with
DataBuilder, then checks:
  - the 13 world intel configs have the notice switch on, and no other config changed;
  - the Fiend Intel copies exist, equal their source config except the switch (off), and every Hub.Type 3 row points
    at the copy matching its own config (plain, _Demo, _Media);
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
CLASSIFIED_COPIES = {"HubConfig_NoPopups_Classified": "HubConfig_WorldReport_SysOpen",
                     "HubConfig_NoPopups_Classified_Demo": "HubConfig_WorldReport_SysOpen_Demo",
                     "HubConfig_NoPopups_Classified_Media": "HubConfig_WorldReport_SysOpen_Media"}
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
    builder = os.path.join(root, "DataBuilderBin", "DataBuilder.dll")
    rel = os.path.join("End", "Content", "DataObject", "Resident")
    base_dir = os.path.join(root, variant, "Base", rel)
    out_dir = os.path.join(root, variant, "Staging", "End", "Content", "DataObject", "Resident")
    fails = []
    bc, oc = export(builder, os.path.join(base_dir, "HubConfig.uasset")), export(builder, os.path.join(out_dir, "HubConfig.uasset"))
    bh, oh = export(builder, os.path.join(base_dir, "Hub.uasset")), export(builder, os.path.join(out_dir, "Hub.uasset"))

    copies = dict(COPIES)
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
        if kind == "3":
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

    print(f"{variant}: {len(oc)} configs, {len(oh)} hubs, {types['3']} Fiend Intel, {types['10']} Classified Intel")
    if fails:
        print("\n".join("FAIL " + f for f in fails))
        return 1
    print("all row checks pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
