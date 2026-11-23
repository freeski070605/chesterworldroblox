"""Regression checks for the W 9th / Kerlin / Lincoln neighborhood.

Run from the repository root: py -3 tools/reconstruction/test_9th_kerlin_scene.py
These validate the authored production code, not Roblox Studio visuals.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

class NeighborhoodSceneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scope = read("src/server/World/NeighborhoodScope.lua")
        cls.tile = read("src/server/World/TileBuilderV2.lua")
        cls.review = read("src/server/World/BuildingReviewOverrides.lua")
        cls.houses = read("src/shared/HouseKit.lua")
        cls.store = read("src/server/World/RealBuildings.lua")
        cls.gas = read("src/server/World/GasStationBuilder.server.lua")
        cls.inspector = read("src/server/World/ReconstructionInspector.lua")
        cls.tile6 = read("src/shared/WorldData/BuildingTiles/tile_r06_c06.lua")
        cls.tile7 = read("src/shared/WorldData/BuildingTiles/tile_r06_c07.lua")

    def test_all_neighborhood_ids_are_scoped(self):
        ids = re.findall(r'\["(\d+)"\]=true', self.scope)
        self.assertEqual(len(ids), 68)
        self.assertEqual(len(set(ids)), 68)
        for important in ("147448", "93584", "97558", "37959", "153497"):
            self.assertIn(important, ids)

    def test_777_market_uses_correct_tile_and_storefront(self):
        self.assertIn('["147448"]', self.tile6)
        self.assertIn('"777 Food Market"', self.tile6)
        self.assertIn('forceShop=true', self.review)
        self.assertIn('photoFacade="777"', self.review)
        self.assertIn('copy.ss = { { "777 Food Market", 0, 64', self.tile)
        self.assertIn('777PhotoShopFascia', self.store)
        self.assertIn('777CornerEntranceLanding', self.store)
        self.assertIn('777WindowSafetyRail', self.store)
        self.assertIn('777LowBlueExtension', self.tile)
        self.assertIn('777RoofDormerBody', self.tile)
        self.assertIn('777PhotoPartCount', self.tile)

    def test_reviewed_houses_use_photo_based_housekit(self):
        self.assertIn('NeighborhoodScope[tostring(building.id)]', self.tile)
        self.assertIn('HouseKitSpec.ParseSpec(review.spec)', self.tile)
        self.assertIn('LincolnFrontFenceRail', self.houses)
        self.assertIn('ctx.buildingId == "37959"', self.houses)
        self.assertIn('ctx.buildingId == "153497"', self.houses)

    def test_verified_property_does_not_inherit_wrong_902_storefront(self):
        self.assertRegex(self.review, r'\["164928"\]=\{style="house"')
        self.assertNotRegex(self.review, r'\["164928"\]=\{[^\n]*manualPriority=true')
        self.assertIn('if old and old.manualPriority then', self.tile)

    def test_916_kerlin_is_shared_no_duplicate_retail(self):
        self.assertIn('["133692"]', self.tile7)
        self.assertRegex(self.review, r'\["133692"\]=\{[^\n]*suppressShops=true')
        self.assertIn('if correction.suppressShops then', self.tile)
        self.assertIn('cw_ab912b6f80', self.gas)
        self.assertIn('Krispy Krunchy Chicken - 916 Kerlin', self.gas)
        self.assertIn('916PartyWall', self.gas)
        self.assertIn('CollectionService:AddTag(chicken,"Exit6Store")', self.gas)

    def test_uninvented_crosswalk_and_inspector(self):
        self.assertIn('local near777 =', self.tile)
        self.assertIn('if lincoln and ninth then return end', self.tile)
        self.assertIn('if options.neighborhood then', self.inspector)
        self.assertIn('log("9TH_KERLIN"', self.inspector)

if __name__ == "__main__":
    unittest.main(verbosity=2)
