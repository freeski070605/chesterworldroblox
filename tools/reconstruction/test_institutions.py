"""Rules for the photo-reviewed school / church reconstructions
(src/server/World/InstitutionReconstruction.lua).

  * every entry is a real county building in the world tiles (stable id)
  * every entry cites a local reference photograph that exists, with a date
  * a religious or school feature (tower, steeple, spire, cupola, onion dome,
    cross, stained glass, rose window, portico, sign ...) is only built when
    the entry's `seen` field records it from that photograph
  * dated imagery (before 2019) cannot be "high" confidence
  * the builder module has no hard-coded religious feature defaults

    py -3 -m unittest tools/reconstruction/test_institutions.py -v

Photo-existence checks are skipped on a machine without the E: archive.
"""
import re
from pathlib import Path

import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "src" / "server" / "World" / "InstitutionReconstruction.lua"
BUILDER = ROOT / "src" / "server" / "World" / "InstitutionArchitecture.lua"
TILES = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"
PHOTOS = Path(r"E:\ChesterWorld\Data")

KINDS = {"church", "school", "campus", "ruin", "demolished", "rename", "reclassified"}


def entries():
    text = SPEC.read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'\n\["(\d+)"\]=\{(.*?)(?=\n\["|\n-{6}|\n\}\s*$)', text, re.S):
        out[m.group(1)] = m.group(2)
    return out


ENTRIES = entries()


def tile_ids():
    ids = set()
    for f in TILES.glob("tile_*.lua"):
        ids.update(re.findall(r'\["(\d+)"\]=\{style=', f.read_text(encoding="utf-8")))
    return ids


def seen(body):
    m = re.search(r'seen="([^"]*)"', body)
    return set(filter(None, (m.group(1) if m else "").split(",")))


# spec pattern -> the `seen` token the photo must have recorded
FEATURES = [
    (r"\btowers?=", "tower"),
    (r'top="spire"', "spire"),
    (r'top="colonial"', "steeple"),
    (r'top="pinnacles"', "pinnacles"),
    (r'top="crenel"', "crenel"),
    (r'top="cupola"', "cupola"),
    (r'top="onion"', "onion"),
    (r"\bcupola=", "cupola"),
    (r"clock=true", "clock"),
    (r"belfry=", "belfry"),
    (r"\bcross=", "cross"),
    (r"stained=true", "stained"),
    (r"\brose=", "rose"),
    (r'style="lancet"', "lancets"),
    (r"\bportico=", "portico"),
    (r"\bporch=", "porch"),
    (r"\bpavilion=", "pavilion"),
    (r"\bsign=", "sign"),
    (r"\bcurtain=", "curtain"),
    (r"\bbigWindow=", "bigwindow"),
    (r'roof="none"', "ruin"),
    (r'kind="demolished"', "demolished"),
    (r'roof="(front_gable|side_gable)"', "gable"),
    (r'roof="hip"', "hip"),
    (r'roof="castellated"', "castellated"),
    (r'roof="stepped"', "stepped"),
    (r'roof="parapet"', "parapet"),
    (r'style="ribbon"', "ribbon"),
    (r"\bfascia=", "fascia"),
    (r"\bcanopy=", "canopy"),
    (r"\bplinth=", "plinth"),
    (r"\bband=", "band"),
    (r"\bchimneys=", "chimneys"),
    (r"steps=\d", "steps"),
    (r"\bdoor=", "door"),
]


TILE_IDS = tile_ids()


class InstitutionRules(unittest.TestCase):
    def test_entries_parsed(self):
        self.assertGreaterEqual(len(ENTRIES), 10)

    def test_entries_are_world_buildings(self):
        for bid in ENTRIES:
            with self.subTest(bid=bid):
                self.assertIn(bid, TILE_IDS, f"{bid} is not a county building in the world tiles")

    @unittest.skipUnless(PHOTOS.exists(), "private photo archive not mounted")
    def test_entries_cite_existing_photo(self):
        for bid, body in ENTRIES.items():
            with self.subTest(bid=bid):
                m = re.search(r'ph\("(\d+)","([^"]+)","(\d{4}-\d{2})"\)', body)
                self.assertTrue(m, f"{bid}: no photo citation")
                self.assertEqual(m.group(1), bid)
                path = PHOTOS / "25_GoogleStreetView_Buildings" / "images" / bid / f"front_{m.group(2)}.jpg"
                self.assertTrue(path.exists(), f"{bid}: missing {path}")

    def test_features_are_photo_evidenced(self):
        for bid, body in ENTRIES.items():
            have = seen(body)
            for pattern, token in FEATURES:
                if re.search(pattern, body):
                    with self.subTest(bid=bid, feature=token):
                        self.assertIn(token, have, f"{bid}: builds '{token}' but the photo review did not record it")

    def test_kind_and_confidence(self):
        for bid, body in ENTRIES.items():
            with self.subTest(bid=bid):
                self.assertIn(re.search(r'kind="(\w+)"', body).group(1), KINDS)
                conf = re.search(r'confidence="(\w+)"', body).group(1)
                self.assertIn(conf, ("high", "medium", "low"))
                year = int(re.search(r'"(\d{4})-\d{2}"\)', body).group(1))
                if year < 2019:
                    self.assertNotEqual(conf, "high", f"{bid}: {year} imagery cannot be high confidence")

    def test_varied_architecture(self):
        """Chester's churches are not one template: many distinct archetypes."""
        archs = {re.search(r'arch="([^"]+)"', b).group(1) for b in ENTRIES.values() if 'arch="' in b}
        churches = [b for b in ENTRIES.values() if 'kind="church"' in b]
        steepled = [b for b in churches if re.search(r'top="(colonial|spire)"', b) or re.search(r'cupola=\{top="colonial"', b)]
        self.assertGreaterEqual(len(archs), len(ENTRIES) * 0.3)
        self.assertLess(len(steepled), len(churches) * 0.25, "most real Chester churches have no steeple")

    def test_custom_models_exist(self):
        """A bespoke photo-matched model (custom=...) must exist as a module."""
        for bid, body in ENTRIES.items():
            m = re.search(r'custom="(\w+)"', body)
            if m:
                with self.subTest(bid=bid):
                    path = BUILDER.parent / "Institutions" / f"{m.group(1)}.lua"
                    self.assertTrue(path.exists(), f"{bid}: missing {path}")
                    self.assertIn("ChesterHigh.Build" if m.group(1) == "ChesterHigh" else ".Build", path.read_text(encoding="utf-8"))

    def test_builder_has_no_feature_defaults(self):
        src = BUILDER.read_text(encoding="utf-8")
        for key in ("tower", "towers", "cupola", "cross", "rose", "portico", "sign"):
            self.assertRegex(src, rf"spec\.{key}\b")


if __name__ == "__main__":
    unittest.main()
