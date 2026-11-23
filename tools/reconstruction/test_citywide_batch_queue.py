"""Unit tests for the citywide geo-batch pipeline. No GIS downloads needed."""
from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

from citywide_batch_queue import build_queue, index_tiles, write_report, score


class CitywideQueueTests(unittest.TestCase):
    def test_keeps_stable_ids_and_groups_by_tile(self):
        tiles = {"147448": "tile_r06_c06.lua", "111566": "tile_r06_c07.lua",
                 "37959": "tile_r06_c06.lua"}
        stores = [
            {"building_id": "147448", "business_name": "777 Food Market",
             "placement_delta_m": "9.1", "confidence": "conflicting",
             "source_lat": "39.8477", "source_lon": "-75.374",
             "image_reference": "ref-777.jpg", "visual_review": "full_size"},
            {"building_id": "111566", "business_name": "NY Fried Chicken",
             "placement_delta_m": "", "confidence": "unresolved",
             "source_lat": "", "source_lon": "", "visual_review": "not_inspected"},
        ]
        homes = [{"building_id": "37959", "photo_review": "full_size",
                  "review_flags": "", "source_address": "Lincoln Street"}]
        result = build_queue(stores, homes, [], tiles)
        self.assertEqual(result["building_ids"], 3)
        self.assertEqual(result["tile_count"], 2)
        self.assertEqual(len(result["batches"]), 2)
        all_ids = [item["building_id"] for batch in result["batches"]
                   for item in batch["properties"]]
        self.assertEqual(set(all_ids), set(tiles))
        self.assertTrue(next(item for batch in result["batches"]
                             for item in batch["properties"]
                             if item["building_id"] == "111566")["requires_review"])

    def test_two_business_sections_stay_one_property(self):
        result = build_queue(
            [{"building_id": "50221", "business_name": "US Gas"},
             {"building_id": "50221", "business_name": "D & D Laundry"}],
            [], [], {"50221": "tile_r06_c07.lua"})
        item = result["batches"][0]["properties"][0]
        self.assertEqual(item["businesses"], ["D & D Laundry", "US Gas"])
        self.assertIn("multi_tenant_parcel_check", item["flags"])
        self.assertEqual(result["building_ids"], 1)

    def test_missing_source_id_is_not_auto_placed(self):
        result = build_queue([{"building_id": "999999",
                               "business_name": "unmatched shop"}],
                             [], [], {"123": "tile_r01_c01.lua"})
        self.assertIn("999999", result["unmatched_source_ids"])
        entry = next(item for batch in result["batches"]
                     for item in batch["properties"]
                     if item["building_id"] == "999999")
        self.assertIn("building_id_not_in_source_tile", entry["flags"])
        self.assertTrue(result["safe_review_only"])

    def test_output_is_written_with_provenance(self):
        result = build_queue([{"building_id": "147448",
                               "business_name": "777 Food Market",
                               "image_reference": "ref.jpg"}],
                             [], [], {"147448": "tile_r06_c06.lua"})
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "queue"
            write_report(result, output)
            data = json.loads(output.with_suffix(".json").read_text())
            self.assertTrue(data["safe_review_only"])
            with output.with_suffix(".csv").open(newline="") as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(rows[0]["building_id"], "147448")
            self.assertIn("ref.jpg", rows[0]["image_references"])
            self.assertIn("Approval gates", output.with_suffix(".md").read_text())

    def test_source_tile_indexing_keeps_footprint_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "tile_r06_c06.lua").write_text(
                'return { ["147448"]={style="storefront"}, ["37959"]={style="rowhouse"} }')
            idx = index_tiles(Path(tmp))
            self.assertEqual(idx["147448"], "tile_r06_c06.lua")
            self.assertEqual(len(idx), 2)

    def test_batch_size_applies_per_tile(self):
        ids = {str(i): "tile_r06_c06.lua" for i in range(1, 7)}
        report = build_queue([], [], [], ids, batch_size=2)
        self.assertEqual(len(report["batches"]), 3)
        self.assertEqual([b["count"] for b in report["batches"]], [2,2,2])

if __name__ == "__main__":
    unittest.main()
