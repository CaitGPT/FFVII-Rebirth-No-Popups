"""Make the release zip from the built paks and the UE4SS part.

    python tools/make_release.py <version> <build root> [--no-panel-builds]

Expects Build-NoPopups.ps1 to have built Standard and JunonCompat (and, unless --no-panel-builds, the same with
-ClassifiedPanel), and build/zip-readme-<version>.txt. Writes build/NoPopups-v<version>.zip and prints its files
with their SHA-256.
"""
import hashlib
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAKS = "End/Content/Paks/~mods"
UE4SS = "End/Binaries/Win64/ue4ss/Mods/NoPopups"
# The UE4SS files that ship. The other scripts in ue4ss/NoPopups/Scripts are development work, off by default.
SCRIPTS = ["main.lua", "boss_start.lua", "repair.lua"]
SETTINGS = """# No Popups, UE4SS side. 1 turns a switch on, 0 off.

# The region boss fights (Classified Intel) are started from the world intel panel, which the pak hides. This shows
# the game's hold-to-engage icon over Cloud in a boss's area: hold Y (controller) or the right mouse button to bring
# the boss out.
boss_start = 1
# Write what it does to boss-log.txt beside this file (for bug reports).
boss_log = 0
# Up to 1.0.2 sanctuaries (Divine Intel) gave no crystal with this mod, so summons did not level up. This gives saves
# played with those versions their missing crystals back, and Cosmo Canyon's chocobo its side-quest step. It checks the
# save itself and does nothing on a save that is not missing anything. What it did goes to repair-log.txt.
repair = 1
"""


def pak(build_root, folder, name):
    package = os.path.join(build_root, folder, "Package")
    files = [os.path.join(package, name + ext) for ext in (".pak", ".ucas", ".utoc")]
    for f in files:
        if not os.path.isfile(f):
            sys.exit(f"missing {f}: build it first")
    return files


def main():
    version, build_root = sys.argv[1], sys.argv[2]
    panel = "--no-panel-builds" not in sys.argv
    readme = os.path.join(ROOT, "build", f"zip-readme-{version}.txt")
    out = os.path.join(ROOT, "build", f"NoPopups-v{version}.zip")
    entries = []  # (path in zip, source file or None, text)
    installs = [("Install", "Standard", "NoPopups_P", True),
                ("Install - with Junon Colosseum", "JunonCompat", "NoPopups_JunonCompat_9999_P", True)]
    if panel:
        installs += [("Without UE4SS", "Standard-Panel", "NoPopups_P", False),
                     ("Without UE4SS - with Junon Colosseum", "JunonCompat-Panel", "NoPopups_JunonCompat_9999_P", False)]
    for top, folder, name, with_ue4ss in installs:
        for f in pak(build_root, folder, name):
            entries.append((f"{top}/{PAKS}/{os.path.basename(f)}", f, None))
        if with_ue4ss:
            for s in SCRIPTS:
                entries.append((f"{top}/{UE4SS}/Scripts/{s}", os.path.join(ROOT, "ue4ss", "NoPopups", "Scripts", s), None))
            entries.append((f"{top}/{UE4SS}/settings.txt", None, SETTINGS))
            entries.append((f"{top}/{UE4SS}/enabled.txt", None, ""))
    entries.append(("README.txt", readme, None))
    entries.append(("LICENSE.txt", os.path.join(ROOT, "LICENSE"), None))

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for arc, src, text in entries:
            if src is not None:
                data = open(src, "rb").read()
                if arc.endswith((".txt", ".lua")):
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            else:
                data = text.replace("\n", "\r\n").encode("ascii")
            z.writestr(arc, data)
            print(f"{hashlib.sha256(data).hexdigest()[:12]}  {len(data):>9}  {arc}")
    print(f"wrote {out} ({os.path.getsize(out)} bytes), sha256 {hashlib.sha256(open(out, 'rb').read()).hexdigest()}")


if __name__ == "__main__":
    main()
