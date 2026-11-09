"""Offline tests for tools/publish_addons.py (no network).
Run from the repo root: python -m unittest tests/test_publish_addons.py"""
import hashlib
import io
import json
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
import publish_addons as pub  # noqa: E402


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        root = self.tmp / "wow-addons"
        for name, ver in (("LootValue", "0.1.0"), ("Omni", "0.2.0")):
            d = root / name
            d.mkdir(parents=True)
            (d / f"{name}.toc").write_text(f"## Interface: 16001\n## Version: {ver}\n\n{name}.lua\n", newline="\n")
            (d / f"{name}.lua").write_text("local x = 1\nreturn x\n", newline="\n")
            (d / "README.md").write_text("not shipped\n")
        (root / "MageMentor").mkdir()
        (root / "MageMentor" / "MageMentor.toc").write_text("## Version: 9\n")
        for f in ("update.ps1", "update.cmd"):
            shutil.copy(HERE.parent / f, root / f)
        self.root, self.out = root, self.tmp / "out"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_manifest_and_zips(self):
        m, files = pub.build(self.root, self.out)
        names = [a["name"] for a in m["addons"]]
        self.assertEqual(names, ["LootValue", "Omni"])  # MageMentor is not shared
        lv = m["addons"][0]
        self.assertEqual(lv["requires"], ["Auctionator"])
        self.assertEqual(m["addons"][1]["version"], "0.2.0")
        data = files[f"wow/LootValue/{lv['sha256']}.zip"]
        self.assertEqual(hashlib.sha256(data).hexdigest(), lv["sha256"])
        self.assertEqual(lv["url"], f"https://dl.jwhex.dev/wow/LootValue/{lv['sha256']}.zip")
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            self.assertEqual(sorted(z.namelist()), ["LootValue/LootValue.lua", "LootValue/LootValue.toc"])
            self.assertIn(b"\r\n", z.read("LootValue/LootValue.lua"))
        self.assertTrue(all(k.startswith("wow/") for k in files))
        self.assertEqual(json.loads(files["wow/addons.json"])["schema"], 1)
        self.assertTrue((self.out / "LootValue" / f"{lv['sha256']}.zip").is_file())

    def test_zip_is_reproducible(self):
        a = pub.build_zip(self.root / "Omni")
        b = pub.build_zip(self.root / "Omni")
        self.assertEqual(a, b)
        # CRLF sources give the same zip as LF sources.
        p = self.root / "Omni" / "Omni.lua"
        p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(pub.build_zip(self.root / "Omni"), a)

    def test_plan_uploads_zips_first_and_manifest_last(self):
        _, files = pub.build(self.root, self.out)
        remote = {"wow/update.cmd": files["wow/update.cmd"]}
        pub.remote_get = lambda acct, key: remote.get(key)
        keys = [k for k, _ in pub.plan(files, "acct")]
        self.assertNotIn("wow/update.cmd", keys)  # unchanged
        self.assertTrue(keys[0].endswith(".zip") and keys[1].endswith(".zip"))
        self.assertEqual(keys[-1], "wow/addons.json")

    def test_plan_refuses_a_changed_zip(self):
        _, files = pub.build(self.root, self.out)
        zkey = next(k for k in files if k.endswith(".zip"))
        pub.remote_get = lambda acct, key: b"other" if key == zkey else None
        with self.assertRaises(SystemExit):
            pub.plan(files, "acct")


    def test_plan_refuses_new_files_under_an_old_version(self):
        m, files = pub.build(self.root, self.out)
        live = json.loads(files["wow/addons.json"])
        live["addons"][1]["sha256"] = "0" * 64  # Omni 0.2.0 was live with other files
        live_bytes = json.dumps(live).encode()
        pub.remote_get = lambda acct, key: live_bytes if key == "wow/addons.json" else None
        with self.assertRaises(SystemExit) as cm:
            pub.plan(files, "acct")
        self.assertIn("Omni 0.2.0", str(cm.exception))
        live["addons"][1]["version"] = "0.1.0"  # the bump makes it fine
        live_bytes = json.dumps(live).encode()
        self.assertTrue(pub.plan(files, "acct"))

    def test_plan_allows_a_new_addon_next_to_a_live_one(self):
        _, files = pub.build(self.root, self.out)
        live = json.loads(files["wow/addons.json"])
        live["addons"] = live["addons"][:1]  # only LootValue was live
        live_bytes = json.dumps(live).encode()
        pub.remote_get = lambda acct, key: live_bytes if key == "wow/addons.json" else None
        self.assertTrue(pub.plan(files, "acct"))


class ChangelogTest(unittest.TestCase):
    def test_every_shared_version_has_an_entry(self):
        log = (HERE.parent / "CHANGELOG.md").read_text(encoding="utf-8")
        for name in pub.ADDONS:
            ver = pub.toc_version(HERE.parent / name)
            self.assertIn(f"## {name} {ver}", log)


class SiteTest(unittest.TestCase):
    def test_site_serves_the_same_update_cmd(self):
        # The page links its own copy (same origin, so the download works).
        site = (HERE.parent / "site" / "update.cmd").read_bytes()
        self.assertEqual(site, (HERE.parent / "update.cmd").read_bytes())
        page = (HERE.parent / "site" / "index.html").read_text()
        self.assertNotIn('href="https://dl.jwhex.dev/wow/update.cmd"', page)


if __name__ == "__main__":
    unittest.main()
