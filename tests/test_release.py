"""Offline tests for tools/release.py (no network).
Run from the repo root: python3 -m unittest tests/test_release.py"""
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
import release as pub  # noqa: E402


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        root = self.tmp / "wow-addons"
        for name, ver in (("LootValue", "0.1.0"), ("Omni", "0.2.0")):
            d = root / name
            d.mkdir(parents=True)
            (d / f"{name}.toc").write_text(f"## Interface: 16001\n## Version: {ver}\n\n{name}.lua\n", newline="\n")
            (d / f"{name}.lua").write_text("local x = 1\nreturn x\n", newline="\n")
            (d / "README.md").write_text("not shipped\n")
        (root / "Other").mkdir()
        (root / "Other" / "Other.toc").write_text("## Version: 9\n")
        self.root, self.out = root, self.tmp / "out"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_manifest_and_zips(self):
        m, files = pub.build(self.root, self.out, "release-2026-11-09")
        self.assertEqual([a["name"] for a in m["addons"]], ["LootValue", "Omni"])  # only ADDONS ship
        lv = m["addons"][0]
        self.assertEqual(lv["requires"], ["Auctionator"])
        self.assertEqual(m["addons"][1]["version"], "0.2.0")
        data = files["LootValue-0.1.0.zip"]
        self.assertEqual(hashlib.sha256(data).hexdigest(), lv["sha256"])
        self.assertEqual(lv["url"], "https://github.com/jwang47/wow-addons/releases/download/"
                         "release-2026-11-09/LootValue-0.1.0.zip")
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            self.assertEqual(sorted(z.namelist()), ["LootValue/LootValue.lua", "LootValue/LootValue.toc"])
            self.assertIn(b"\r\n", z.read("LootValue/LootValue.lua"))
        man = json.loads(files["addons.json"])
        self.assertEqual((man["schema"], man["tag"]), (1, "release-2026-11-09"))
        self.assertEqual(man["updater"], "https://github.com/jwang47/wow-addons/releases/latest/download/update.ps1")
        self.assertEqual(sorted(p.name for p in self.out.iterdir()),
                         ["LootValue-0.1.0.zip", "Omni-0.2.0.zip", "addons.json", "update.cmd", "update.ps1"])
        self.assertIn(b"\r\n", files["update.ps1"])

    def test_zip_is_reproducible(self):
        a = pub.build_zip(self.root / "Omni")
        b = pub.build_zip(self.root / "Omni")
        self.assertEqual(a, b)
        # CRLF sources give the same zip as LF sources.
        p = self.root / "Omni" / "Omni.lua"
        p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
        self.assertEqual(pub.build_zip(self.root / "Omni"), a)

    def test_binary_files_are_not_changed(self):
        blob = bytes(range(256)) * 4  # holds \n and \r\n bytes
        (self.root / "Omni" / "icon.tga").write_bytes(blob)
        with zipfile.ZipFile(io.BytesIO(pub.build_zip(self.root / "Omni"))) as z:
            self.assertEqual(z.read("Omni/icon.tga"), blob)

    def test_version_guard(self):
        m, files = pub.build(self.root, self.out)
        self.assertEqual(pub.same_version_changes(m, None), [])  # first release
        live = json.loads(files["addons.json"])
        self.assertEqual(pub.same_version_changes(m, json.dumps(live)), [])  # unchanged
        live["addons"][1]["sha256"] = "0" * 64  # Omni 0.2.0 was released with other files
        self.assertEqual(pub.same_version_changes(m, json.dumps(live)), ["Omni 0.2.0"])
        live["addons"][1]["version"] = "0.1.0"  # the bump makes it fine
        self.assertEqual(pub.same_version_changes(m, json.dumps(live)), [])
        live["addons"] = live["addons"][:1]  # a new addon next to a released one
        self.assertEqual(pub.same_version_changes(m, json.dumps(live)), [])


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
        self.assertIn(b"releases/latest/download/update.ps1", site)
        page = (HERE.parent / "site" / "index.html").read_text()
        self.assertIn('href="update.cmd" download', page)


class SpareFilesTest(unittest.TestCase):
    """Each addon's .toc ends with empty SpareN.lua files, so a new file
    loads with /reload instead of a game restart (AGENTS.md)."""

    def test_every_addon_has_spares(self):
        root = HERE.parent
        for toc in sorted(root.glob("*/*.toc")):
            if toc.stem != toc.parent.name:
                continue
            files = [l.strip() for l in toc.read_text(encoding="utf-8").splitlines()
                     if l.strip() and not l.startswith("#")]
            spares = [f for f in files if f.startswith("Spare")]
            with self.subTest(addon=toc.stem):
                self.assertGreaterEqual(len(spares), 1, "no SpareN.lua left in the .toc")
                self.assertEqual(files[-len(spares):], spares, "spares go at the end of the .toc")
                for f in spares:
                    self.assertTrue((toc.parent / f).exists(), f)


if __name__ == "__main__":
    unittest.main()
