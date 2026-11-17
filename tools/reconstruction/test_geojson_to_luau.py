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

if __name__ == "__main__":
    unittest.main()
