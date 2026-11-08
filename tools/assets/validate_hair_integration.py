"""Static checks for the 12-style test catalog and install contract."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = (ROOT / "src/shared/Exit6Catalog.luau").read_text(encoding="utf-8")
PROFILE = (ROOT / "src/server/Exit6Profile.luau").read_text(encoding="utf-8")
STYLE = (ROOT / "src/server/Exit6Style.luau").read_text(encoding="utf-8")
SERVER = (ROOT / "src/server/Exit6HairTest.server.luau").read_text(encoding="utf-8")
PHONE = (ROOT / "src/client/Exit6Phone.client.luau").read_text(encoding="utf-8")
INSTALLER = (ROOT / "tools/studio/install_exit6_hair_candidates.luau").read_text(encoding="utf-8")


def main():
    manifest = json.loads((ROOT / "assets/hair/manifest.json").read_text(encoding="utf-8"))
    ids = [entry["id"] for entry in manifest]
    assert len(ids) == len(set(ids)) == 12
    block = CATALOG.split("Catalog.HairTest = {", 1)[1].split("\n}\nfor _, asset", 1)[0]
    catalog_ids = re.findall(r'\{ id = "([a-z0-9_]+)"', block)
    assert catalog_ids == ids, (catalog_ids, ids)
    assert 'testOnly = true' in CATALOG
    assert '"test_hair_" .. asset.id' in CATALOG
    assert '"hair", "top", "bottom", "hat"' in PROFILE
    assert 'Catalog.Items[id]' in PROFILE
    assert 'ServerStorage:FindFirstChild("Exit6ProductionAssets")' in STYLE
    assert 'handle:IsA("MeshPart")' in STYLE and 'handle.MeshId ~= ""' in STYLE
    assert 'humanoid:AddAccessory(clone)' in STYLE
    assert 'clearTestHair(char)' in STYLE
    assert 'Style.RestoreOwnHair(player)' in SERVER
    assert 'Style.PreviewTestHair(player, assetId)' in SERVER
    assert 'HairTestAction:InvokeServer("list")' in PHONE
    assert 'Enum.KeyCode.ButtonSelect' in PHONE and 'Enum.KeyCode.ButtonB' in PHONE
    for asset_id in ids:
        assert re.search(r'\b' + re.escape(asset_id) + r'\s*=\s*true\b', INSTALLER), asset_id
    print("PASS: exactly 12 catalog/OBJ/install IDs; guarded MeshPart path; profile and controller hooks")


if __name__ == "__main__":
    main()
