"""Source checks for the sports mesh and aerial-verified facility pipeline.

    python -m unittest tools.test_sports_facilities -v      (from the repo root)
"""
import json
import math
import re
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARKS = (ROOT / "src/shared/WorldData/Parks.lua").read_text(encoding="utf-8")
BUILDER = (ROOT / "src/server/World/ParkBuilder.server.lua").read_text(encoding="utf-8")
VERIFIED = (ROOT / "src/shared/Exit6VerifiedSports.luau").read_text(encoding="utf-8")
MESHES = (ROOT / "src/shared/Exit6SportsMeshIds.luau").read_text(encoding="utf-8")


def glb(path):
    data = path.read_bytes()
    assert data[:4] == b"glTF"
    length = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + length])


def boxes(text, sport):
    return [[float(v) for v in m.group(1).split(",")]
            for m in re.finditer(r'sport\s*=\s*"' + sport + r'"[^}]*?box\s*=\s*\{([^}]*)\}', text)]


def local(box, x, z):
    a = math.radians(box[4])
    dx, dz = x - box[0], z - box[1]
    return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)


class SportsAssets(unittest.TestCase):
    def test_each_mesh_is_one_importable_textured_primitive(self):
        for name in ("street_hoop", "court_paint_100x60", "football_paint_360x160",
                     "six_lane_oval_560x260", "bleacher_section_60"):
            with self.subTest(name=name):
                scene = glb(ROOT / "assets/sports" / f"{name}.glb")
                self.assertEqual(len(scene["meshes"]), 1)
                primitive, = scene["meshes"][0]["primitives"]
                self.assertIn("TEXCOORD_0", primitive["attributes"])
                self.assertEqual(len(scene["textures"]), 1)

    def test_hoop_calibration_matches_glb(self):
        # GLB: pole base at origin, rim centre at x=-2.4, y=10; Roblox turns it
        # 180 deg about Y and centres it on its bounds.
        hoop = glb(ROOT / "assets/sports/street_hoop.glb")
        pos = hoop["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
        lo, hi = (hoop["accessors"][pos][k] for k in ("min", "max"))
        cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
        rim_x, rim_y = -(-2.4 - cx), 10 - cy
        self.assertIn(f"rimOffset = Vector3.new({rim_x:.4f}, {rim_y:.3f}, 0)", MESHES)
        self.assertGreater(rim_x, 0, "rim must face +X in the uploaded mesh")

    def test_hoops_face_the_court(self):
        # the +X hoop is turned pi so its +X-facing rim points back to centre
        self.assertIn("CFrame.Angles(0, facing == 1 and math.pi or 0, 0)", BUILDER)
        self.assertIn("hoop(model, frame, rimX, 1, true)", BUILDER)
        self.assertIn("hoop(model, frame, -rimX, -1, true)", BUILDER)
        self.assertIn("frame * CFrame.new(rimX, HOOP.rimHeight, 0)", BUILDER)


class SportsPlacement(unittest.TestCase):
    def test_no_highest_sample_or_blanket_skirt_for_sports(self):
        sports = BUILDER.split("-- Restored non-sports builders")[0]
        self.assertNotIn("legacySlab(model", sports)
        self.assertIn("levelOf(item.box, grade)", BUILDER)
        self.assertIn("return median(r), b, s", BUILDER)

    def test_terrain_conform_is_bounded_and_reversible(self):
        self.assertIn("CONFORM_MAX_DELTA", BUILDER)
        self.assertIn("blockParams", BUILDER)
        self.assertIn('terrainControl.Name = "Exit6SportsTerrain"', BUILDER)
        self.assertIn("Terrain:WriteVoxels(s.region, VOXEL, s.materials, s.occupancy)", BUILDER)
        self.assertNotIn("FillBlock", BUILDER)

    def test_memorial_courts_match_aerial(self):
        # painted centre circles measured at (-3438.3, 5800) and (-3378.2, 5757.5)
        courts = boxes(PARKS, "basketball")
        for x, z in ((-3437.8, 5798.5), (-3378.8, 5758.4)):
            self.assertTrue(any(abs(b[0] - x) < 0.2 and abs(b[1] - z) < 0.2 and abs(b[4] - 124.1) < 0.2 for b in courts))
        self.assertIn("memorial_courts = { box = { -3406.2, 5776.9, 159.1, 122.2, 33.7 }", VERIFIED)

    def test_memorial_field_shares_court_axis_and_fits_lit_rectangle(self):
        field, = [b for b in boxes(VERIFIED, "american_football") if b[0] < -3000]
        self.assertAlmostEqual(field[4] % 180, 124.1 % 180, delta=0.5)
        poles = [(-3552, 5931), (-3739, 6056), (-3433, 6106), (-3621, 6231)]
        for x, z in poles:
            lx, lz = local(field, x, z)
            self.assertLess(abs(lx), field[2] / 2)          # inside the field ends
            self.assertGreater(abs(lz), field[3] / 2)       # just beyond the sidelines
            self.assertLess(abs(lz), field[3] / 2 + 25)

    def test_a_field_and_track_share_one_axis(self):
        field, = [b for b in boxes(VERIFIED, "american_football") if b[0] > -100]
        track_yaw = float(re.search(r"track = \{.*?yaw = (-?[\d.]+)", VERIFIED, re.S).group(1))
        self.assertEqual(field[4], track_yaw)
        self.assertAlmostEqual(field[2], 431.4, delta=0.5)  # 120 yd at 17.98 studs / 5 yd
        self.assertIn('{ at = { 17.3, 1541.6 }, drop', VERIFIED)

    def test_ghost_features_are_dropped(self):
        for at in ("-3745.6, -13188.7", "-3855.5, -13146.3", "-3801.6, -13167.6",
                   "-3690.9, -13210.3", "5285.3, 4459.1", "9645.6, -5766.6"):
            self.assertIn("{ at = { " + at + " }, drop", VERIFIED)

    def test_every_correction_matches_a_source_feature(self):
        src = [[float(v) for v in m.group(1).split(",")[:2]] for m in re.finditer(r"box=\{([^}]*)\}", PARKS)]
        corrections = VERIFIED.split("corrections = {")[1].split("facilities = {")[0]
        for m in re.finditer(r"\{ at = \{ (-?[\d.]+), (-?[\d.]+) \}", corrections):
            x, z = float(m.group(1)), float(m.group(2))
            self.assertTrue(any(abs(s[0] - x) < 1 and abs(s[1] - z) < 1 for s in src), (x, z))

    def test_every_baseball_field_has_a_home_corner(self):
        for b in boxes(PARKS, "baseball"):
            key = f"{b[0]}, {b[1]}"
            with self.subTest(at=key):
                self.assertRegex(VERIFIED, r"\{ at = \{ " + re.escape(key) + r" \}, (set = \{ home|drop|replace)")


if __name__ == "__main__":
    unittest.main()
