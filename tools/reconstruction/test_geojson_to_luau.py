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
    def test_roof_triangulation_concavity_and_winding(self):
        from shapely.geometry import Polygon
        ring = [(0, 0), (8, 0), (8, 3), (3, 3), (3, 7), (0, 7)]
        for points in (ring, list(reversed(ring))):
            triangles = module.roof_triangles(points)
            self.assertAlmostEqual(sum(Polygon(t).area for t in triangles), Polygon(points).area)
            self.assertTrue(all(Polygon(points).covers(Polygon(t)) for t in triangles))
            self.assertEqual(len(triangles), len(ring) - 2)

    def test_holes_explicitly_unsupported(self):
        shell = [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]
        hole = [[3, 3], [7, 3], [7, 7], [3, 7], [3, 3]]
        self.assertEqual(module.rings_from_geometry({"type": "Polygon", "coordinates": [shell, hole]}), [])

    def test_unknown_height_and_roof_remain_estimates(self):
        text = module.output_module([{"id": "x", "height": 27,
            "points": [(0, 0), (10, 0), (10, 10), (0, 10)]}], {"count": 1})
        self.assertIn('heightSource = "estimated_default"', text)
        self.assertIn('roofSource = "procedural_estimate"', text)
        self.assertIn('roofTriangles = {', text)

    def test_source_grid_maps_verified_junction_to_spawn(self):
        from pyproj import Transformer
        inverse = Transformer.from_crs("EPSG:3857", "EPSG:4326", always_xy=True)
        forward = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        source_e = module.ORIGIN_E + module.CENTER_X + 2810.205 / 3
        source_n = module.ORIGIN_N + module.CENTER_Z - 1518.823 / 3
        lon, lat = inverse.transform(source_e, source_n)
        self.assertAlmostEqual(lat, 39.848318096, places=7)
        self.assertAlmostEqual(lon, -75.371413543, places=7)
        e, n = forward.transform(lon, lat)
        self.assertAlmostEqual((e-module.ORIGIN_E-module.CENTER_X)*3, 2810.205, places=3)
        self.assertAlmostEqual(-(n-module.ORIGIN_N-module.CENTER_Z)*3, 1518.823, places=3)

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
        lat, lon = 39.84831810, -75.37141354
        project = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        e, n = project.transform(lon, lat)
        # 10 metres east and 10 metres north of an anchor become +30X, -30Z.
        verts = [(e, n), (e + 10, n), (e + 10, n + 10), (e, n + 10)]
        points = [(100 + (x-e) * 3, 200 - (z-n) * 3) for x,z in verts]
        self.assertAlmostEqual(points[1][0], 130, places=5)
        self.assertAlmostEqual(points[2][1], 170, places=5)
        result = module.output_module(
            [{"id": "building_1", "height": 27, "points": points}],
            {"studsPerMeter": 3.0, "count": 1, "defaultHeightCount": 1,
             "source": "test.geojson", "originE": module.ORIGIN_E})
        self.assertIn('metadata = { studsPerMeter = 3.0', result)
        self.assertIn('id = "building_1"', result)
        self.assertIn('height = 27', result)
        self.assertNotIn('"metadata":', result)
        attribution = module.output_module([], {"attribution": "© OpenStreetMap contributors"})
        self.assertIn('"© OpenStreetMap contributors"', attribution)
        self.assertNotIn('\\u00a9', attribution)


compare_spec = importlib.util.spec_from_file_location("compare_building_alignment", HERE / "compare_building_alignment.py")
comparison = importlib.util.module_from_spec(compare_spec)
compare_spec.loader.exec_module(comparison)

class AlignmentTests(unittest.TestCase):
    def test_generated_candidate_parser(self):
        module_text = module.output_module(
            [{"id": "test", "height": 27, "points": [(100.0,200.0),(130.0,200.0),(130.0,170.0)]}],
            {"studsPerMeter": 3.0, "count": 1, "defaultHeightCount": 0,
             "source": "test.geojson", "originE": module.ORIGIN_E})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "generated.lua"
            path.write_text(module_text, encoding="utf-8")
            candidates = comparison.candidates(path)
            self.assertEqual(len(candidates), 1)
            self.assertEqual(candidates[0]["vertices"], 3)
            self.assertGreater(candidates[0]["x"], 100.0)
            self.assertLess(candidates[0]["z"], 200.0)

    def test_polygon_overlap_review_not_automatic_replacement(self):
        from shapely.geometry import box
        rows = comparison.compare(
            [{"id": "old", "tile": "tile_r06_c07", "world_x": "100", "world_z": "200",
              "width_m": "10", "depth_m": "10", "yaw_deg": "0"}],
            [{"id": "new", "polygon": box(95, 195, 125, 225), "vertices": 4}])
        self.assertEqual(rows[0]["status"], "REVIEW_OVERLAP")
        self.assertGreater(rows[0]["intersection_over_union"], 0)

    def test_near_centroids_without_overlap_are_unmatched(self):
        from shapely.geometry import box
        rows = comparison.compare(
            [{"id": "old", "tile": "tile", "world_x": "100", "world_z": "200",
              "width_m": "2", "depth_m": "2", "yaw_deg": "0"}],
            [{"id": "new", "polygon": box(105, 199, 108, 201), "vertices": 4}])
        self.assertEqual(rows[0]["status"], "UNMATCHED")

    def test_association_rejects_ambiguous_and_unmatched(self):
        from shapely.geometry import box
        import sys
        sys.path.insert(0, str(HERE))
        import build_associations
        legacy = [
            {"id": "one", "tile": "t", "world_x": "5", "world_z": "5", "width_m": "3.333333", "depth_m": "3.333333", "yaw_deg": "0"},
            {"id": "two", "tile": "t", "world_x": "25", "world_z": "5", "width_m": "3.333333", "depth_m": "3.333333", "yaw_deg": "0"},
        ]
        footprints = [{"id": "osm_way_1_0", "polygon": box(0, 0, 10, 10)},
                      {"id": "osm_way_2_0", "polygon": box(20, 0, 30, 10)},
                      {"id": "osm_way_3_0", "polygon": box(40, 0, 50, 10)}]
        result = build_associations.associate(legacy, footprints)
        self.assertEqual([r["gameId"] for r in result], ["one", "two", None])
        self.assertEqual(result[-1]["status"], "unmatched_manual_review")

if __name__ == "__main__":
    unittest.main()
