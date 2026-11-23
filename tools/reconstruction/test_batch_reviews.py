"""Regression tests for geographic batch reviews and their geometry mapping.

    py -3 -m unittest discover -s tools/reconstruction -p "test_*.py" -v

The photo checks need the private image archive on E:; they are skipped on a
machine without it. The mapping checks only read repository files.
"""
import csv
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "reconstruction"))
import batch_review  # noqa: E402

POSE = ROOT / "tools/reconstruction/pose_reviews.csv"
LOG = ROOT / "docs/batch_review_log.csv"
LUA = ROOT / "src/server/World/PropertyReconstruction.lua"
DATA = Path(r"E:\ChesterWorld\Data")


def rows(path):
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


class BatchReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pose = rows(POSE)
        cls.log = rows(LOG)
        cls.lua = LUA.read_text(encoding="utf-8")
        cls.entries = dict(re.findall(r'^\t\["(\d+)"\]=(\{.*\}),$', cls.lua, re.M))

    def test_pose_reviews_have_unique_ids(self):
        ids = [r["building_id"] for r in self.pose]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_logged_verdict_became_exactly_one_review(self):
        reviewed = {r["building_id"]: r for r in self.pose}
        for entry in self.log:
            if entry["verdict"] == "SKIP":
                continue
            self.assertIn(entry["building_id"], reviewed, entry)
            self.assertEqual(reviewed[entry["building_id"]]["style"], entry["verdict"])

    def test_skipped_photos_never_become_batch_evidence(self):
        batch_notes = {r["building_id"] for r in self.pose if r["notes"].startswith("batch ")}
        for entry in self.log:
            if entry["verdict"] == "SKIP":
                self.assertNotIn(entry["building_id"], batch_notes, entry)

    def test_batch_reviews_cite_full_size_photo_and_ray_share(self):
        for r in self.pose:
            if r["notes"].startswith("batch "):
                self.assertIn("full-size", r["notes"])
                share = float(re.search(r"front share ([\d.]+)", r["notes"]).group(1))
                self.assertGreaterEqual(share, 0.25, r["building_id"])

    def test_every_review_reaches_the_runtime_module(self):
        for r in self.pose:
            if not r["style"]:
                continue
            body = self.entries.get(r["building_id"], "")
            self.assertRegex(body, r'^\{status="(reconstructed|finish_verified)"', r["building_id"])

    @unittest.skipUnless(DATA.exists(), "private image archive not mounted")
    def test_cited_photos_exist(self):
        for r in self.pose:
            self.assertTrue((DATA / "25_GoogleStreetView_Buildings/images" / r["photo"]).is_file(), r["photo"])

    # -- geometry mapping regressions from batch b01 (tile r06_c07) ---------
    def entry(self, bid):
        return self.entries[bid]

    def test_industrial_building_is_not_a_church(self):
        self.assertIn('style="garage"', self.entry("93490"))
        self.assertIn("garageBays=1", self.entry("93490"))

    def test_corner_deli_is_one_storey_storefront(self):
        self.assertIn('style="storefront"', self.entry("179346"))
        self.assertIn("floors=1", self.entry("179346"))

    def test_butler_street_crow_step_pairs_are_two_storey_twins(self):
        for bid in ("175127", "180597", "52098", "25995", "4721", "53168", "66617", "27898", "157068"):
            self.assertIn('style="twin"', self.entry(bid), bid)
            self.assertIn("floors=2", self.entry(bid), bid)

    def test_aarons_way_townhouses_are_gabled_and_sided(self):
        for bid in ("204018", "25435", "79542", "102725"):
            self.assertIn("roof=front_gable", self.entry(bid), bid)
            self.assertIn('material="WoodPlanks"', self.entry(bid), bid)

    def test_foursquare_is_detached_hipped_house(self):
        self.assertIn('style="house"', self.entry("185804"))
        self.assertIn("roof=hip", self.entry("185804"))

    def test_storey_count_reaches_non_residential_builders(self):
        tile = (ROOT / "src/server/World/TileBuilderV2.lua").read_text(encoding="utf-8")
        self.assertIn("copy.floors = parsed.floors", tile)

    def test_916_kerlin_unit_order_matches_photo(self):
        # Eagle Fuel 58063 photo from Kerlin (heading 356): KRISPY KRUNCHY
        # sign on the left, EAGLE on the right. Front-frame +X = viewer left.
        gas = (ROOT / "src/server/World/GasStationBuilder.server.lua").read_text(encoding="utf-8")
        self.assertRegex(gas, r'\{x=unitW/2,name="KRISPY KRUNCHY CHICKEN"')
        self.assertRegex(gas, r'\{x=-unitW/2,name="EAGLE SAVE MART"')


class VerdictParserTests(unittest.TestCase):
    def write(self, text):
        d = Path(tempfile.mkdtemp())
        (d / "index.csv").write_text("cell,building_id,photo,share,heading,street,address,tile,tile_style,"
                                     "tile_floors,attachment,front_bearing\n"
                                     "1.1,111,111/front_x.jpg,0.5,90,A St,1 A St,r00_c00,rowhouse,3,detached,90\n",
                                     encoding="utf-8")
        (d / "verdicts.txt").write_text(text, encoding="utf-8")
        return d / "verdicts.txt"

    def test_rejects_wrong_building_for_cell(self):
        path = self.write("1.1 222 twin colonial_twin 2 flat 1 2 - - - high | x\n")
        with self.assertRaises(ValueError):
            batch_review.cmd_apply(type("A", (), {"verdicts": str(path)}))

    def test_rejects_unknown_style_and_short_lines(self):
        with self.assertRaises(ValueError):
            list(batch_review.parse_verdicts(self.write("1.1 111 twin flat | too short\n")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
