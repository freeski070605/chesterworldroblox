#!/usr/bin/env python3
from __future__ import annotations
import re, shutil
from pathlib import Path
PROJECT=Path(r"E:\code\chesterworld-roblox")
SOURCE=PROJECT/'tools'/'package_regional_world_tiles.py'
TARGET=PROJECT/'tools'/'package_regional_world_tiles_realworld.py'
if not SOURCE.exists(): raise SystemExit(f'Missing regional packager: {SOURCE}')
text=SOURCE.read_text(encoding='utf-8')
for old,new,label in [
    ('15_RegionalRoadGeneratorPrep','17_RealWorldCleanup','road directory'),
    ('regional_generator_roads.geojson','regional_generator_roads_render_v2.geojson','road file'),
    ('16_RegionalTiles','17_RegionalTiles_RealWorld','output directory')]:
    if old not in text: raise SystemExit(f'Could not find {label} token: {old}')
    text=text.replace(old,new)
marker='# ============================================================\n# BUILD TILES\n# ============================================================'
func='''# ============================================================\n# WHOLE-BUILDING TILE OWNERSHIP\n# ============================================================\ndef extract_buildings_for_tile(layer_index, tile_world_box, row, column):\n    results = []\n    candidate_indices = layer_index.query_indices(tile_world_box)\n    for index in candidate_indices:\n        record = layer_index.records[index]\n        geometry = record["geometry_m"]\n        if geometry is None or geometry.is_empty:\n            continue\n        try:\n            point = geometry.representative_point()\n        except Exception:\n            continue\n        owner_column = int(math.floor((point.x - ORIGIN_X) / TILE_SIZE_M))\n        owner_row = int(math.floor((point.y - ORIGIN_Z) / TILE_SIZE_M))\n        owner_column = max(0, min(tile_columns - 1, owner_column))\n        owner_row = max(0, min(tile_rows - 1, owner_row))\n        if owner_row != row or owner_column != column:\n            continue\n        if not geometry.intersects(world_boundary_m):\n            continue\n        results.append({\n            "properties": record["properties"],\n            "geometry": mapping(localize_geometry(geometry)),\n        })\n    return results\n\n\n'''
if marker not in text: raise SystemExit('Could not find BUILD TILES marker.')
if 'def extract_buildings_for_tile(' not in text: text=text.replace(marker,func+marker,1)
old_call='''layer_features = (\n                extract_layer_for_tile(\n                    layer_index,\n                    tile_clip\n                )\n            )'''
new_call='''layer_features = (\n                extract_buildings_for_tile(\n                    layer_index,\n                    tile_world_box,\n                    row,\n                    column\n                )\n                if layer_name == "buildings"\n                else extract_layer_for_tile(\n                    layer_index,\n                    tile_clip\n                )\n            )'''
if old_call not in text: raise SystemExit('Could not patch tile extraction loop safely; structure differs.')
text=text.replace(old_call,new_call,1)
TARGET.write_text(text,encoding='utf-8')
backup=PROJECT/'tools'/'backups'/'realworld_pass2'; backup.mkdir(parents=True,exist_ok=True)
shutil.copy2(SOURCE,backup/'package_regional_world_tiles.before_pass2.py')
print('='*80); print('REAL-WORLD REGIONAL PACKAGER PREPARED'); print('='*80)
print(f'Source preserved: {SOURCE}'); print(f'New packager:     {TARGET}'); print(r'Output folder:    E:\ChesterWorld\Data\17_RegionalTiles_RealWorld'); print('Building policy:  WHOLE / ONE TILE / NO CLIPPING'); print('Road policy:      clipped normally, adjusted render widths'); print('='*80)
