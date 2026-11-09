#!/usr/bin/env python3
"""Build and publish LootValue and Omni.

  python tools/publish_addons.py build            # zips + addons.json in logs/wow-addons/
                                                  # (and release/<Addon>-<version>.zip for GitHub)
  python tools/publish_addons.py plan             # read-only: what publish would upload
  python tools/publish_addons.py publish --yes    # upload to R2 (needs Jiahua's OK)

Run from the repo root (or anywhere; paths are found from this file).

The files go to the R2 bucket that serves https://dl.jwhex.dev/, under the
"wow/" prefix only (the KartDrift feeds use channels/, installers/, notes/
and objects/). Zips are content-addressed (wow/<Addon>/<sha256>.zip) and are
never replaced or deleted; addons.json, update.ps1 and update.cmd are
replaced on each publish, after every zip is uploaded and read back.

Upload uses the Cloudflare API (api.cloudflare.com) with CLOUDFLARE_API_TOKEN
and CLOUDFLARE_ACCOUNT_ID from the environment (the account is looked up when
only one is visible). In the cloud container the proxy adds the token.
"""
import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
WOW = HERE.parent                      # the repo root
REPO = WOW
OUT = REPO / "logs" / "wow-addons"
BUCKET = "kartdrift-miami-updates"
PREFIX = "wow/"
BASE_URL = "https://dl.jwhex.dev/" + PREFIX
API = "https://api.cloudflare.com/client/v4"
# Folders shipped, in install order. A folder that does not exist yet is skipped.
ADDONS = ["LootValue", "Omni"]
# Files that stay the player's own: shipped as a default, never overwritten.
KEEP = {}
# Addons that must be installed for an addon to load (its .toc
# "## Dependencies:"). The updater says so when one is missing.
REQUIRES = {"LootValue": ["Auctionator"]}
UA = "wow-addons-publisher (github.com/jwang47/wow-addons)"
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
            # Windows line endings, as a Windows git checkout gives them.
            data = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            z.writestr(info, data)
    return buf.getvalue()


def git_commit() -> str:
    try:
        return subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "--short=10", "HEAD"],
                                       text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def build(root: Path = WOW, out: Path = OUT):
    out.mkdir(parents=True, exist_ok=True)
    entries, blobs = [], {}
    for name in ADDONS:
        folder = root / name
        if not (folder / (name + ".toc")).is_file():
            continue
        data = build_zip(folder)
        sha = hashlib.sha256(data).hexdigest()
        key = f"{PREFIX}{name}/{sha}.zip"
        # Same layout as the bucket, so update.ps1 -Manifest can test a local build.
        (out / name).mkdir(exist_ok=True)
        (out / name / f"{sha}.zip").write_bytes(data)
        blobs[key] = data
        # The same bytes under a readable name, for the GitHub release.
        (out / "release").mkdir(exist_ok=True)
        (out / "release" / f"{name}-{toc_version(folder)}.zip").write_bytes(data)
        entries.append({"name": name, "version": toc_version(folder), "sha256": sha, "size": len(data),
                        "url": BASE_URL + f"{name}/{sha}.zip", "keep": KEEP.get(name, []),
                        "requires": REQUIRES.get(name, [])})
    manifest = {"schema": 1, "commit": git_commit(),
                "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "updater": BASE_URL + "update.ps1", "addons": entries}
    text = json.dumps(manifest, indent=2) + "\n"
    (out / "addons.json").write_text(text, encoding="utf-8")
    files = {key: data for key, data in blobs.items()}
    for small in ("update.ps1", "update.cmd"):
        raw = (WOW / small).read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        files[PREFIX + small] = raw
        (out / small).write_bytes(raw)
    files[PREFIX + "addons.json"] = text.encode("utf-8")
    return manifest, files


# --- Cloudflare R2 through the REST API -------------------------------------
def _request(method, url, data=None, ctype=None):
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "proxy-injected")
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "User-Agent": UA})
    if ctype:
        req.add_header("Content-Type", ctype)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.status, r.read()


def account_id():
    if os.environ.get("CLOUDFLARE_ACCOUNT_ID"):
        return os.environ["CLOUDFLARE_ACCOUNT_ID"]
    _, body = _request("GET", API + "/accounts")
    accounts = json.loads(body)["result"]
    if len(accounts) != 1:
        sys.exit("set CLOUDFLARE_ACCOUNT_ID: %d accounts are visible" % len(accounts))
    return accounts[0]["id"]


def object_url(acct, key):
    return f"{API}/accounts/{acct}/r2/buckets/{BUCKET}/objects/{urllib.parse.quote(key, safe='/')}"


def remote_get(acct, key):
    try:
        _, body = _request("GET", object_url(acct, key))
        return body
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def ctype_for(key):
    if key.endswith(".json"):
        return "application/json"
    if key.endswith(".zip"):
        return "application/zip"
    return "text/plain; charset=utf-8"


def same_version_changes(files, live):
    """Addons whose files changed since the live manifest but whose
    ## Version did not: friends would see one version number for two builds."""
    new = json.loads(files[PREFIX + "addons.json"])
    old = {a["name"]: a for a in (json.loads(live)["addons"] if live else [])}
    return [a["name"] + " " + a["version"] for a in new["addons"]
            if a["name"] in old and old[a["name"]]["version"] == a["version"]
            and old[a["name"]]["sha256"] != a["sha256"]]


def plan(files, acct):
    """(key, reason) for every file publish would upload. Read-only."""
    stale = same_version_changes(files, remote_get(acct, PREFIX + "addons.json"))
    if stale:
        raise SystemExit("changed since the live release without a version bump (edit ## Version "
                         "in the .toc and add a CHANGELOG.md entry): " + ", ".join(stale))
    todo = []
    for key, data in files.items():
        if not key.startswith(PREFIX):
            raise AssertionError("refusing a key outside " + PREFIX + ": " + key)
        old = remote_get(acct, key)
        if old is None:
            todo.append((key, "new"))
        elif old != data:
            if key.endswith(".zip"):
                raise SystemExit("remote zip differs from its own hash name: " + key)
            todo.append((key, "changed"))
    # Immutable zips first, the files that point at them last.
    todo.sort(key=lambda t: (not t[0].endswith(".zip"), t[0].endswith("addons.json"), t[0]))
    return todo


def publish(files, acct):
    for key, why in plan(files, acct):
        data = files[key]
        _request("PUT", object_url(acct, key), data, ctype_for(key))
        back = remote_get(acct, key)
        if back != data:
            raise SystemExit("read-back mismatch after upload: " + key)
        print(f"uploaded {key} ({why}, {len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()[:12]})")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["build", "plan", "publish"])
    ap.add_argument("--yes", action="store_true", help="publish: confirm the upload")
    ap.add_argument("--root", help="build only: take the addon folders from here (for a test build)")
    args = ap.parse_args(argv)
    if args.root and args.command != "build":
        sys.exit("--root is for test builds only; plan and publish use the repo's folders")
    manifest, files = build(Path(args.root) if args.root else WOW)
    for a in manifest["addons"]:
        print(f"{a['name']} {a['version']}  sha256 {a['sha256'][:12]}  {a['size']} bytes")
    print("built in", OUT)
    if args.command == "build":
        return
    acct = account_id()
    if args.command == "plan":
        todo = plan(files, acct)
        for key, why in todo:
            print(f"would upload {key} ({why})")
        print("nothing to upload" if not todo else f"{len(todo)} file(s) to upload to {BUCKET}")
        return
    if not args.yes:
        sys.exit("publish uploads to the live download site; run it with --yes once Jiahua has said OK")
    publish(files, acct)
    print("published", BASE_URL + "addons.json")


if __name__ == "__main__":
    main()
