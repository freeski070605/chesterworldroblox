#!/usr/bin/env python3
"""Offline smoke tests for the Chester footprint converter; run: py -m unittest discover -s tools/reconstruction -p 'test_*.py'"""
import importlib.util
import json
import math
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("geojson_to_luau", HERE / "geojson_to_luau.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class FootprintTests(unittest.TestCase):
    def test_polygon_and_multipolygon(self):
        self.assertEqual(len(module.rings_from_geometry({
            "type": "Polygon",
            "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 0]]]})), 1)
        self.assertEqual(len(module.rings_from_geometry({
            "type": "MultiPolygon",
            "coordinates": [[[[0, 0], [1, 0], [1, 1], [0, 0]]],
                            [[[2, 2], [3, 2], [3, 3], [2, 2]]]]})), 2)

    def test_generated_module_luau_and_orientation(self):
        from pyproj import Transformer
        lat, lon = 39.85, -75.37
        project = Transformer.from_crs("EPSG:4326", "EPSG:32618", always_xy=True)
        e, n = project.transform(lon, lat)
        # 10 metres east and 10 metres north of an anchor become +30X, -30Z.
        verts = [(e, n), (e + 10, n), (e + 10, n + 10), (e, n + 10)]
        points = [(100 + (x-e) * 3, 200 - (z-n) * 3) for x,z in verts]
        self.assertAlmostEqual(points[1][0], 130, places=5)
        self.assertAlmostEqual(points[2][1], 170, places=5)
        result = module.output_module(
            [{"id": "building_1", "height": 27, "points": points}],
            {"studsPerMeter": 3.0, "count": 1, "defaultHeightCount": 1,
             "source": "test.geojson", "anchorLat": lat, "anchorLon": lon})
        self.assertIn('metadata = { studsPerMeter = 3.0', result)
        self.assertIn('id = "building_1"', result)
        self.assertIn('height = 27', result)
        self.assertNotIn('"metadata":', result)


compare_spec = importlib.util.spec_from_file_location("compare_building_alignment", HERE / "compare_building_alignment.py")
comparison = importlib.util.module_from_spec(compare_spec)
compare_spec.loader.exec_module(comparison)

class AlignmentTests(unittest.TestCase):
    def test_generated_candidate_parser(self):
        module_text = module.output_module(
            [{"id": "test", "height": 27, "points": [(100.0,200.0),(130.0,200.0),(130.0,170.0)]}],
            {"studsPerMeter": 3.0, "count": 1, "defaultHeightCount": 0,
             "source": "test.geojson", "anchorLat": 39.85, "anchorLon": -75.37})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "generated.lua"
            path.write_text(module_text, encoding="utf-8")
            candidates = comparison.candidates(path)
            self.assertEqual(len(candidates), 1)
            self.assertEqual(candidates[0]["vertices"], 3)
            self.assertAlmostEqual(candidates[0]["x"], 120.0)
            self.assertAlmostEqual(candidates[0]["z"], 190.0)

    def test_nearest_distance_review_not_automatic_replacement(self):
        rows = comparison.compare(
            [{"id": "old", "tile": "tile_r06_c07", "world_x": "100", "world_z": "200"}],
            [{"id": "new", "x": 105.0, "z": 200.0, "vertices": 4}])
        self.assertEqual(rows[0]["status"], "REVIEW_NEARBY")
        self.assertEqual(rows[0]["distance_studs"], 5.0)

if __name__ == "__main__":
    unittest.main()
