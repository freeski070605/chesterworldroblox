"""Create a local-only, ID-preserving residential evidence register.

Run after tools/storefronts/citywide_visual_audit.py. No network access, image
download, tile modification, or inferred visual detail is performed here.
"""
import csv
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path('E:/ChesterWorld/Data')
IN = ROOT / 'build/citywide_storefront_review.csv'
OUT = ROOT / 'build/citywide_residential_review.csv'
DOC = ROOT / 'docs/CHESTER_NEIGHBORHOOD_VISUAL_AUDIT.md'
TILES = ROOT / 'src/shared/WorldData/BuildingTiles'
RECT = re.compile(r'\{(-?[\d.]+),(-?[\d.]+),([\d.]+),([\d.]+)\}')

# Full-size street-photo findings. The remaining archive photos are linked,
# but their doors, roof forms, colors, and other details are unverified.
OBSERVED = {
    '13452': dict(type='garage', stories='1', roof='gable; shingled', facade='light painted wall',
        garage='Single garage door facing paved lane', fence='chain link gate at side',
        evidence='Full-size Google photo shows a small one-story garage and lane; 2025 aerial shows a small detached footprint.',
        confidence='verified', fix='Correct twin classification after parcel/garage association review.'),
    '8154': dict(type='rowhouse', stories='2', roof='flat or very low pitch from street', facade='painted masonry and exposed brick along row',
        porch='covered entries along row', windows='second-story paired windows visible',
        evidence='Full-size Google photo shows continuous two-story row with individual porches; aerial footprint spans part of the row.',
        confidence='conflicting', fix='Resolve building ID extent and individual rowhouse segmentation before replacing apartment form.'),
    '20770': dict(type='twin or attached house', stories='2', roof='pitched; dark shingles', facade='light painted facade',
        door='Two separate front doors visible', porch='small roofed front entries', yard='front lawn and walkways',
        windows='multiple front windows visible',
        evidence='Full-size Google photo shows two front entrances and shared massing; county footprint label remains detached_house.',
        confidence='conflicting', fix='Review twin/attached boundary and individual entrances; preserve source ID.'),
    '4066': dict(type='attached row or small multifamily', stories='2', roof='pitched', facade='light painted facade',
        door='Three front entry doors visible across connected mass', porch='small front porch/entry roofs',
        yard='front lawn', fence='chain link and white picket sections',
        evidence='Full-size Google photo shows connected two-story mass with several entries; exact county ID extent is unresolved.',
        confidence='probable', fix='Check parcel/footprint division and entrance count before HouseKit changes.'),
    '18556': dict(type='corner rowhouse or twin', stories='2', roof='flat or low pitch', facade='brick with white painted bay',
        door='Stoop entry on photographed street', porch='masonry stoop', windows='two-story bay windows',
        evidence='Full-size Google photo shows corner two-story masonry home and street-side stoop; other side not visible.',
        confidence='probable', fix='Check both street faces and footprint before labeling corner entrance.'),
}
OVERVIEW_SCREENED = {'20770', '2598', '683', '4066', '1988', '11940',
                     '13452', '18556', '54272', '46827', '8154', '29168'}


def merc(lon, lat):
    return lon * 20037508.34 / 180, math.log(math.tan((90 + lat) * math.pi / 360)) * 6378137


def aerial_for(lon, lat, aerial):
    if lon is None or lat is None:
        return ''
    x, y = merc(lon, lat)
    for a in aerial:
        if a['xmin'] <= x < a['xmax'] and a['ymin'] <= y < a['ymax']:
            p = DATA / '19_Aerial' / a['file']
            return str(p) if p.is_file() else ''
    return ''


def type_estimate(style, fp):
    archetype = fp.get('generator_archetype') or ''
    if style == 'garage':
        return 'garage'
    return {'house': 'detached', 'rowhouse': 'rowhouse', 'twin': 'twin', 'apartment': 'apartment',
            'storefront': 'mixed-use possible', 'commercial': 'mixed-use possible'}.get(style, 'unknown')


def load_pose():
    path = ROOT / 'tools/reconstruction/pose_reviews.csv'
    with path.open(encoding='utf-8', newline='') as f:
        return {r['building_id']: r for r in csv.DictReader(f)}


POSE = {}


def main():
    POSE.update(load_pose())
    with IN.open(encoding='utf-8-sig', newline='') as f:
        all_rows = list(csv.DictReader(f))
    features = json.loads((DATA / '13_RegionalMaster/regional_buildings_base.geojson').read_text(encoding='utf-8'))['features']
    footprints = {str(x['properties']['OBJECTID']): x['properties'] for x in features}
    aerial = json.loads((DATA / '19_Aerial/index.json').read_text(encoding='utf-8'))
    tile_lines = {}
    for p in TILES.glob('tile_*.lua'):
        tile_lines[p.name] = {m.group(1): line for line in p.read_text(encoding='utf-8').splitlines()
                              if (m := re.match(r'^\s*\["(\d+)"\]=', line))}
    result = []
    for r in all_rows:
        if r['record_type'] != 'building':
            continue
        bid, style = r['building_id'], r['current_style']
        fp = footprints.get(bid, {})
        raw = tile_lines.get(r['tile'], {}).get(bid, '')
        floors_match = re.search(r'\bfloors=(\d+)', raw)
        floors = int(floors_match.group(1)) if floors_match else 0
        residential_style = style in {'house', 'rowhouse', 'twin', 'apartment'}
        ancillary = style == 'garage'
        mixed_candidate = style in {'storefront', 'commercial'} and floors >= 2
        if not (residential_style or ancillary or mixed_candidate or fp.get('generator_use') == 'residential'):
            continue
        scope = 'residential' if residential_style else 'garage_outbuilding' if ancillary else 'mixed_use_candidate' if mixed_candidate else 'GIS_residential_candidate'
        dims = [(float(w), float(d)) for _, _, w, d in RECT.findall(raw)]
        obs = OBSERVED.get(bid, {})
        photo = r['image_reference']
        aerial_path = aerial_for(fp.get('center_lon'), fp.get('center_lat'), aerial)
        delta = float(r['placement_delta_m']) if r['placement_delta_m'] else None
        flags = []
        if delta is not None and delta > 5:
            flags.append('placement delta >5m: geometry review')
        if obs.get('type') and type_estimate(style, fp) not in obs['type']:
            flags.append('type conflict: photo versus tile')
        if style == 'garage':
            flags.append('garage access and parent parcel unverified')
        if not photo:
            flags.append('no matched street photo')
        if not aerial_path:
            flags.append('no local aerial tile')
        pose = POSE.get(bid)
        if pose and not obs:
            # ray-verified full-size review (tools/reconstruction/pose_reviews.csv)
            obs = dict(type=pose['style'], stories=pose['floors'], roof=pose['roof'],
                       porch='porch' if pose['porch'] == '1' else 'no porch' if pose['porch'] == '0' else '',
                       garage=f"{pose['garage_bays']} bay(s)" if pose['garage_bays'] else '',
                       evidence='Full-size ray-verified photo ' + pose['photo'] + '; ' + pose['notes'][:160],
                       confidence='verified' if pose['confidence'] == 'high' else 'probable',
                       fix='Applied via PropertyReconstruction.lua (pose_reviews.csv).')
            photo = photo or str(DATA / '25_GoogleStreetView_Buildings/images' / pose['photo'])
            flags = [f for f in flags if f != 'no matched street photo']
        visual = 'full_size' if obs else 'overview_screened' if bid in OVERVIEW_SCREENED else 'not_inspected'
        result.append(dict(
            building_id=bid, master_id=r['master_id'], tile=r['tile'], residential_scope=scope,
            coverage_unit=r['tile'].removesuffix('.lua'), municipality=fp.get('municipality', 'unknown'),
            source_address=r['source_address'], source_lat=r['source_lat'], source_lon=r['source_lon'],
            current_style=style, current_stories=floors if floors_match else '',
            current_placement_x=r['current_placement_x'], current_placement_z=r['current_placement_z'],
            current_rotation_deg=r['current_rotation_deg'], current_frontage_deg=r['current_frontage_deg'],
            current_rect_count=len(dims), current_rect_dimensions_m=' | '.join(f'{w:.2f}x{d:.2f}' for w, d in dims),
            footprint_x=r['source_footprint_x'], footprint_z=r['source_footprint_z'],
            placement_delta_m=r['placement_delta_m'], footprint_width_m=fp.get('footprint_width_m', ''),
            footprint_depth_m=fp.get('footprint_depth_m', ''), footprint_axis_deg=fp.get('footprint_orientation_deg', ''),
            gis_type_estimate=fp.get('generator_archetype', ''), gis_use_estimate=fp.get('generator_use', ''),
            gis_row_cluster_size=fp.get('row_cluster_size', ''), gis_neighbor_count=fp.get('row_neighbor_count', ''),
            type_estimate_from_tile=type_estimate(style, fp),
            observed_type=obs.get('type', ''), observed_stories=obs.get('stories', ''),
            observed_roof=obs.get('roof', ''), observed_facade=obs.get('facade', ''),
            observed_door=obs.get('door', ''), observed_porch=obs.get('porch', ''),
            observed_stoop=obs.get('stoop', ''), observed_windows=obs.get('windows', ''),
            observed_yard=obs.get('yard', ''), observed_garage_access=obs.get('garage', ''),
            observed_fence=obs.get('fence', ''), observed_corner_home='',
            observed_vacant_parcel='', observed_entrance_road='',
            verified_setback_m='', verified_rotation_deg='', verified_dimensions_m='',
            image_path=photo, image_source=r['image_source'], image_capture_date=r['image_capture_date'],
            aerial_path=aerial_path, aerial_review='visually_checked' if bid == '13452' or bid == '8154' else 'not_inspected',
            photo_review=visual, evidence=obs.get('evidence', 'GIS and tile geometry compared; matched street/aerial image is a reference only, not visually verified.'),
            confidence=obs.get('confidence', 'imagery_missing' if not photo else 'unverified'),
            review_flags='; '.join(flags), recommended_fix=obs.get('fix', 'Review full-size street and aerial evidence before correcting type, entrance, roof or facade.'),
        ))
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(result[0])); w.writeheader(); w.writerows(result)
    write_report(result, all_rows)


def write_report(rows, all_rows):
    by_tile = defaultdict(list)
    by_muni = defaultdict(list)
    for r in rows:
        by_tile[r['tile']].append(r)
        by_muni[r['municipality']].append(r)
    photos = sum(bool(r['image_path']) for r in rows)
    full = sum(r['photo_review'] == 'full_size' for r in rows)
    overview = sum(r['photo_review'] == 'overview_screened' for r in rows)
    missing = len(rows) - photos
    flagged = sum('placement delta >5m' in r['review_flags'] for r in rows)
    style = Counter(r['current_style'] for r in rows)
    lines = [
        '# Chester neighborhood visual audit', '',
        '## Scope and evidence limits', '',
        f'- {len(rows):,} residential, garage and possible mixed-use records in {len(by_tile)} BuildingTiles files; {len(all_rows):,} total building/storefront report rows.',
        f'- {photos:,} records have a linked local street photo; {missing:,} do not. {full} photos were examined full size and have observation fields; {overview} more were screened only in an overview sheet. All other photo links are **unverified**.',
        '- Local 2025 aerial tiles and county footprints were joined by stable OBJECTID. Aerial tile availability is not a claim of visual inspection. Only two example footprints (13452 and 8154) were visually checked against cropped aerials.',
        '- The 102-tile world has 86 nonempty BuildingTiles files in this checkout. Tile cells are coverage units; no authoritative neighborhood boundary file was found in the supplied sources, so municipal and tile counts below are used rather than invented neighborhood names.',
        '- GIS archetypes, story estimates, row clusters, footprint dimensions and tile styles are **estimates or existing game data**, not visually confirmed facts. Blank observation fields mean unknown.',
        '- Vacant parcels cannot be enumerated from a building-footprint dataset. Alley access, setbacks, yards, fences, corner entrances and road-facing doors are unknown except where a cited full-size photo states a visible fact.',
        '', '## Counts', '',
        f'- Existing styles: {dict(style)}. Scope: {dict(Counter(r["residential_scope"] for r in rows))}. Mixed-use is a candidate class, not a verified dwelling.',
        f'- {flagged:,} records have a tile centroid more than 5 m from the county footprint center; these are geometric review flags, not verified errors.',
        '- Source IDs are unchanged. No tiles, HouseKit, runtime placement, doors or gameplay were edited.',
        '', '## Image-supported priorities', '',
        '- **13452:** a one-story lane-facing garage with a gabled shingle roof and chain-link side gate is represented as a twin. The aerial shows a small detached footprint. Resolve parcel association before changing the type.',
        '- **8154:** street imagery shows a continuous two-story porch-front row, while the game uses an apartment form and the county footprint spans part of the run. Resolve per-house extent and entrances.',
        '- **20770:** two front doors and a shared two-story mass are visible; county archetype says detached house. Review twin/attached segmentation.',
        '- **4066:** several front entrances in a connected mass call for parcel and entrance review.',
        '- **18556:** photographed corner masonry home has a stoop and bay windows; the other street face is unseen, so corner-entry direction remains unknown.',
        '', '## Municipality coverage', '',
        '| Municipality | Records | Linked photos | Full-size reviews | Missing photos | Placement flags >5m |',
        '|---|---:|---:|---:|---:|---:|',
    ]
    for name, group in sorted(by_muni.items()):
        n = len(group); img = sum(bool(x['image_path']) for x in group)
        lines.append(f'| {name} | {n} | {img} | {sum(x["photo_review"] == "full_size" for x in group)} | {n-img} | {sum("placement delta >5m" in x["review_flags"] for x in group)} |')
    lines += ['', '## Tile coverage (neighborhood proxy)', '',
              '| Building tile | Records | Linked photos | Full-size reviews | Missing photos | Placement flags >5m |',
              '|---|---:|---:|---:|---:|---:|']
    for tile, group in sorted(by_tile.items()):
        n = len(group); img = sum(bool(x['image_path']) for x in group)
        lines.append(f'| {tile} | {n} | {img} | {sum(x["photo_review"] == "full_size" for x in group)} | {n-img} | {sum("placement delta >5m" in x["review_flags"] for x in group)} |')
    lines += ['', '## Staged reconstruction use', '',
              'Work from full-size image and aerial citations in the CSV. Review type conflicts and large position deltas first, then fill entrance, roof, facade, garage, yard, fence and setback fields only where visible. Missing or obscured facts remain unknown. Preserve ChesterBuildingId/OBJECTID while resolving conflicts.', '']
    DOC.parent.mkdir(exist_ok=True)
    DOC.write_text('\n'.join(lines), encoding='utf-8')
    print('residential',len(rows),'photo linked',photos,'full-size',full,'missing',missing,'tiles',len(by_tile))


if __name__ == '__main__':
    main()
