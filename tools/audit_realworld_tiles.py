#!/usr/bin/env python3
import json
from pathlib import Path
ROOT=Path(r"E:\ChesterWorld")
TILES=ROOT/'Data'/'17_RegionalTiles_RealWorld'/'Tiles'
SOURCE_BUILDINGS=ROOT/'Data'/'14_RegionalGeneratorPrep_v2'/'regional_generator_buildings_v2.geojson'
if not TILES.exists(): raise SystemExit(f'Missing staged tiles: {TILES}')
source=json.loads(SOURCE_BUILDINGS.read_text(encoding='utf-8')); source_count=len(source.get('features',[]))
tile_files=sorted(TILES.glob('*.json')); btotal=0; rtotal=0; withb=0
for p in tile_files:
    d=json.loads(p.read_text(encoding='utf-8')); layers=d.get('layers',{}); b=len(layers.get('buildings',[])); r=len(layers.get('roads',[])); btotal+=b; rtotal+=r; withb+=1 if b else 0
print('='*84); print('CHESTERWORLD REAL-WORLD TILE AUDIT'); print('='*84)
print(f'Tile JSON files:              {len(tile_files):,}')
print(f'Source real buildings:        {source_count:,}')
print(f'Tiled building records:       {btotal:,}')
print(f'Tiled road segments:          {rtotal:,}')
print(f'Tiles containing buildings:   {withb:,}'); print()
if btotal==source_count:
    print('WHOLE-BUILDING OWNERSHIP: PASS'); print('No extra building pieces were created by tile-boundary clipping.')
else:
    print('WHOLE-BUILDING OWNERSHIP: REVIEW'); print(f'Difference: {btotal-source_count:+,}')
print('='*84)
