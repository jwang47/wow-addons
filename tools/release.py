#!/usr/bin/env python3
"""Build the release files for LootValue, Omni and UpgradeFinder.

  python3 tools/release.py build [--tag release-YYYY-MM-DD]
      zips, addons.json, update.ps1 and update.cmd in logs/wow-addons/
  python3 tools/release.py check
      read-only: refuse an addon whose files changed since the latest GitHub
      release while its ## Version stayed the same

Run from the repo root (or anywhere; paths are found from this file).

The release workflow (.github/workflows/release.yml) runs both for a pushed
release-* tag and attaches the files to the GitHub release. update.cmd and
update.ps1 read addons.json from the latest release; each entry names its
zip in that release and its SHA-256.
"""
import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                     # the repo root
OUT = ROOT / "logs" / "wow-addons"
REPO_URL = "https://github.com/jwang47/wow-addons"
LATEST = REPO_URL + "/releases/latest/download/"
# Folders shipped, in install order. A folder that does not exist is skipped.
ADDONS = ["LootValue", "Omni", "UpgradeFinder", "QuestBoard"]
# Files that stay the player's own: shipped as a default, never overwritten.
KEEP = {}
# Addons that must be installed for an addon to load (its .toc
# "## Dependencies:"). The updater says so when one is missing.
REQUIRES = {"LootValue": ["Auctionator"]}
UA = "wow-addons-release (github.com/jwang47/wow-addons)"
TEXT = {".lua", ".toc", ".xml", ".txt"}
ZIP_TIME = (2020, 1, 1, 0, 0, 0)  # fixed, so the same files give the same zip


def toc_version(folder: Path) -> str:
    toc = folder / (folder.name + ".toc")
    m = re.search(r"^## Version:\s*(\S+)", toc.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else "0"


def addon_files(folder: Path):
    files = []
    for p in sorted(folder.rglob("*")):
        if p.is_file() and not p.name.startswith(".") and p.suffix != ".md":
            files.append(p)
    return files


def build_zip(folder: Path) -> bytes:
    """A zip with the addon folder at the top level (Omni/Omni.toc).
    Forward slashes, fixed times and sorted names make it reproducible."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for p in addon_files(folder):
            rel = folder.name + "/" + p.relative_to(folder).as_posix()
            info = zipfile.ZipInfo(rel, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            data = p.read_bytes()
            # Windows line endings for text, as a Windows git checkout gives
            # them; images and fonts stay as they are.
            if p.suffix.lower() in TEXT:
                data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            z.writestr(info, data)
    return buf.getvalue()


def git_commit() -> str:
    try:
        return subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--short=10", "HEAD"],
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def build(root: Path = ROOT, out: Path = OUT, tag: str = "local"):
    """Writes the release files to out/ and returns (manifest, {name: bytes})."""
    out.mkdir(parents=True, exist_ok=True)
    entries, files = [], {}
    for name in ADDONS:
        folder = root / name
        if not (folder / (name + ".toc")).is_file():
            continue
        data = build_zip(folder)
        version = toc_version(folder)
        zname = f"{name}-{version}.zip"
        files[zname] = data
        entries.append({"name": name, "version": version, "sha256": hashlib.sha256(data).hexdigest(),
                        "size": len(data), "url": f"{REPO_URL}/releases/download/{tag}/{zname}",
                        "keep": KEEP.get(name, []), "requires": REQUIRES.get(name, [])})
    manifest = {"schema": 1, "tag": tag, "commit": git_commit(),
                "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "updater": LATEST + "update.ps1", "addons": entries}
    files["addons.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    for small in ("update.ps1", "update.cmd"):
        files[small] = (ROOT / small).read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    for fname, data in files.items():
        (out / fname).write_bytes(data)
    return manifest, files


def same_version_changes(manifest, live):
    """Addons whose files changed since the live manifest but whose
    ## Version did not: friends would see one version number for two builds."""
    old = {a["name"]: a for a in (json.loads(live)["addons"] if live else [])}
    return [a["name"] + " " + a["version"] for a in manifest["addons"]
            if a["name"] in old and old[a["name"]]["version"] == a["version"]
            and old[a["name"]]["sha256"] != a["sha256"]]


def fetch_live():
    """The latest release's addons.json, or None before the first release."""
    req = urllib.request.Request(LATEST + "addons.json", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["build", "check"])
    ap.add_argument("--tag", default="local", help="build: the release tag the zip URLs point at")
    ap.add_argument("--root", help="build only: take the addon folders from here (for a test build)")
    args = ap.parse_args(argv)
    if args.root and args.command != "build":
        sys.exit("--root is for test builds only")
    manifest, _ = build(Path(args.root) if args.root else ROOT, OUT, args.tag)
    for a in manifest["addons"]:
        print(f"{a['name']} {a['version']}  sha256 {a['sha256'][:12]}  {a['size']} bytes")
    print("built in", OUT)
    if args.command == "check":
        stale = same_version_changes(manifest, fetch_live())
        if stale:
            sys.exit("changed since the latest release without a version bump (edit ## Version "
                     "in the .toc and add a CHANGELOG.md section): " + ", ".join(stale))
        print("versions OK against the latest release")


if __name__ == "__main__":
    main()
