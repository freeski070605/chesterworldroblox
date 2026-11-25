"""Source checks for the sports mesh and mapped-feature pipeline."""
import json
import re
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def glb(path):
    data = path.read_bytes()
    assert data[:4] == b"glTF"
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + length])


class SportsAssets(unittest.TestCase):
    def test_each_mesh_is_one_importable_textured_primitive(self):
        for name in ("street_hoop", "court_paint_100x60", "football_paint_360x160",
                     "six_lane_oval_560x260", "bleacher_section_60"):
            with self.subTest(name=name):
                scene = glb(ROOT / "assets/sports" / f"{name}.glb")
                self.assertEqual(len(scene["meshes"]), 1)
                primitive, = scene["meshes"][0]["primitives"]
                self.assertIn("TEXCOORD_0", primitive["attributes"])
                self.assertGreater(scene["accessors"][primitive["indices"]]["count"], 100)
                self.assertEqual(len(scene["textures"]), 1)

    def test_geometry_stays_in_expected_bounds(self):
        hoop = glb(ROOT / "assets/sports/street_hoop.glb")
        position = hoop["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
        lo, hi = (hoop["accessors"][position][k] for k in ("min", "max"))
        self.assertAlmostEqual(lo[1], 0, delta=.1)
        self.assertAlmostEqual(hi[1], 13.15, delta=.3)
        self.assertAlmostEqual(lo[0], -3.5, delta=.3)
        self.assertTrue((ROOT / "assets/sports/sports_palette.png").is_file())

    def test_all_mapped_courts_use_shared_builder(self):
        parks = (ROOT / "src/shared/WorldData/Parks.lua").read_text(encoding="utf-8")
        builder = (ROOT / "src/server/World/ParkBuilder.server.lua").read_text(encoding="utf-8")
        courts = re.findall(r'sport="basketball"', parks)
        self.assertGreaterEqual(len(courts), 20)
        self.assertIn('BUILDERS.basketball = function', builder)
        self.assertIn('Workspace.Terrain:FillBlock', builder)
        self.assertIn('AddTag(model, "Exit6Court")', builder)
        self.assertIn('CourtLength', builder)
        print(f"Mapped basketball court footprints: {len(courts)}")

    def test_field_coordinates_match_road_orientation(self):
        parks = (ROOT / "src/shared/WorldData/Parks.lua").read_text(encoding="utf-8")
        verified = (ROOT / "src/shared/Exit6VerifiedSports.luau").read_text(encoding="utf-8")
        self.assertIn('box={17.3,-1541.6,429.6,190.9', parks)
        self.assertIn('box={8364.0,7027.3,444.5,199.6', parks)
        self.assertIn('box = { -3700, -5950, 390, 165, -12 }', verified)

    def test_memorial_field_clear_of_mapped_roads_and_courts(self):
        from tools.audit_sports_placement import check
        inside, roads, courts = check(-3700, -5950)
        self.assertTrue(inside)
        self.assertEqual(roads, [])
        self.assertEqual(courts, 0)


if __name__ == "__main__":
    unittest.main()
