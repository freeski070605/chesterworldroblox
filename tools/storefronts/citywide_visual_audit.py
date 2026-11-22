"""Local-only inventory and evidence join for the ChesterWorld visual audit.

Reads existing tiles, county footprints, and image manifests.  Visual findings
are deliberately hand recorded below; an image match is not visual proof.
"""
import csv
import json
import math
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path('E:/ChesterWorld/Data')
TILES = ROOT / 'src/shared/WorldData/BuildingTiles'
OUT = ROOT / 'build/citywide_storefront_review.csv'
DOC = ROOT / 'docs/CHESTER_CITYWIDE_VISUAL_AUDIT.md'
LINE = re.compile(r'^\s*\["(\d+)"\]=\{(.*)\}\s*,?\s*$')
SHOP = re.compile(r'\{"((?:[^"\\]|\\.)*)",(\d+),(-?\d+),0x[0-9a-fA-F]+,0x[0-9a-fA-F]+,"([^"]*)"\}')
RECT = re.compile(r'\{(-?[\d.]+),(-?[\d.]+),([\d.]+),([\d.]+)\}')

# Full-resolution inspection, distinct from the overview screening of the
# matched Google images. Leave all unsupported fields empty.
FINDINGS = {
    '93584': dict(confidence='conflicting', visual_review='full_size',
        observed_identity='Corner market signage visible; individual tenant signs unreadable',
        verified_frontage='Concord-facing glazed run visible; corner return visible',
        verified_door='', corner_entrance='', storefront_glass='Concord-facing glazed run',
        sign_location='Above glazed run near corner', facade='White painted side wall; brick corner; dark storefront',
        visible_shape='Long low single-story strip with corner return',
        evidence='2020-11 Google photo shows corner strip and side wall; does not prove J&S front-lot location or current tenant identity.',
        recommended_fix='Hold tenant and door changes; obtain/inspect direct W 9th front-lot view and parcel evidence before separating J&S.'),
    '50221': dict(confidence='conflicting', visual_review='full_size',
        observed_identity='US GAS on canopy; D & D Laundry on separate blue fascia at left',
        verified_frontage='Gas forecourt faces street in image; laundry facade left of canopy',
        verified_door='', corner_entrance='', storefront_glass='',
        sign_location='US GAS on canopy; laundry sign over left storefront',
        facade='White/red canopy; light-colored low attached structures',
        visible_shape='Large forecourt canopy with small structures behind',
        evidence='2024-09 Google photo visibly separates canopy branding from laundry fascia; tile assigns D & D Laundry section to US Gas OBJECTID.',
        recommended_fix='Review separate county footprint/parcel for gas shop and laundry; do not move door or split ID from this photo alone.'),
    '189198': dict(confidence='conflicting', visual_review='full_size',
        observed_identity='No legible Check Cashing sign in linked image',
        verified_frontage='', verified_door='', corner_entrance='', storefront_glass='',
        sign_location='', facade='Brick upper story; pale painted ground floor on visible corner',
        visible_shape='Two-story corner row building',
        evidence='2026-04 Google photo shows corner row building; visible ground floor does not establish an active Check Cashing entrance.',
        recommended_fix='Check source identity and direct W 9th frontage view before implementing independently interactive Check Cashing.'),
}


def read_csv(path):
    if not path.is_file():
        return []
    with path.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def field(body, key):
    m = re.search(r'(?<!\w)' + re.escape(key) + r'=(?:"([^"]*)"|(-?[\d.]+))', body)
    return (m.group(1) or m.group(2)) if m else ''


def source_xy(lon, lat):
    mx = lon * 20037508.34 / 180
    my = math.log(math.tan((90 + lat) * math.pi / 360)) * 6378137
    return mx + 8397592, my - 4837229


def main():
    # These are the 138 distinct photos manually screened in overview sheets
    # for this audit. Other manifest photos are linked but not visually read.
    screened = {r['image_local_path'] for r in read_csv(ROOT / 'build/city_frontage_review.csv')
                if r.get('image_local_path') and Path(r['image_local_path']).is_file()}
    google_dir = DATA / '25_GoogleStreetView_Buildings'
    map_dir = DATA / '24_BuildingImagery_Mapillary'
    pano_dir = DATA / '10_StorefrontPanoramas'
    google = {r['objectid']: r for r in read_csv(google_dir / 'manifest.csv')}
    mapillary = {r['objectid']: r for r in read_csv(map_dir / 'manifest.csv')}
    places = {r['building_objectid']: r for r in read_csv(pano_dir / 'places.csv') if r['building_objectid']}
    photos = {}
    for r in read_csv(pano_dir / 'photo_metadata.csv'):
        photos.setdefault(r['site_id'], []).append(r)
    for r in read_csv(pano_dir / 'existing_archive_matches.csv'):
        photos.setdefault(r['site_id'], []).append(r)
    geo = json.loads((DATA / '13_RegionalMaster/regional_buildings_base.geojson').read_text(encoding='utf-8'))
    footprints = {str(f['properties']['OBJECTID']): f['properties'] for f in geo['features']}
    rows = []
    for tile in sorted(TILES.glob('tile_*.lua')):
        for raw in tile.read_text(encoding='utf-8').splitlines():
            m = LINE.match(raw)
            if not m:
                continue
            bid, body = m.groups()
            shops = SHOP.findall(body)
            # One building record even when there is no individual shop section.
            entries = [(n, s, bearing, pid) for n, s, bearing, pid in shops] or [('', '', '', '')]
            fp = footprints.get(bid, {})
            rects = [(float(x), float(z), float(w), float(h)) for x, z, w, h in RECT.findall(body)]
            if rects:
                weight = sum(w*h for _, _, w, h in rects)
                cx = sum(x*w*h for x, _, w, h in rects)/weight
                cz = sum(z*w*h for _, z, w, h in rects)/weight
            else:
                cx = cz = None
            sx = sz = delta = ''
            if fp.get('center_lon') and fp.get('center_lat'):
                sx, sz = source_xy(fp['center_lon'], fp['center_lat'])
                if cx is not None:
                    delta = round(math.hypot(cx-sx, cz-sz), 1)
            refs = []
            for label, folder, manifest in [('GoogleStreetView', google_dir, google), ('Mapillary', map_dir, mapillary)]:
                rec = manifest.get(bid)
                if rec and rec.get('path') and (folder / rec['path']).is_file():
                    refs.append((label, str(folder / rec['path']), rec))
            place = places.get(bid, {})
            pano_refs = []
            for rec in photos.get(place.get('id', ''), []):
                p = pano_dir / (rec.get('path') or '')
                if rec.get('path') and p.is_file():
                    pano_refs.append(str(p))
            primary = refs[0] if refs else ('', '', {})
            finding = FINDINGS.get(bid, {})
            for name, section, bearing, place_id in entries:
                visual = finding.get('visual_review', 'overview_screened' if primary[1] in screened else 'not_inspected')
                confidence = finding.get('confidence', 'probable' if visual == 'overview_screened' and delta != '' and delta <= 10 else 'imagery_missing' if not primary[1] and not pano_refs else 'unresolved')
                rows.append(dict(
                    building_id=bid, master_id=fp.get('master_id', ''), tile=tile.name,
                    record_type='storefront_section' if shops else 'building', section=section,
                    business_name=name or field(body, 'name'), business_place_id=place_id,
                    current_style=field(body, 'style'), current_placement_x=round(cx, 2) if cx is not None else '',
                    current_placement_z=round(cz, 2) if cz is not None else '',
                    current_rotation_deg=field(body, 'a'), current_frontage_deg=bearing or field(body, 'fb'),
                    current_door='not encoded in BuildingTiles', current_facade_color=field(body, 'wc') or field(body, 'rc'),
                    source_address=fp.get('address') or fp.get('site_address') or place.get('address', ''),
                    source_lat=fp.get('center_lat', ''), source_lon=fp.get('center_lon', ''),
                    source_footprint_x=round(sx, 2) if sx != '' else '', source_footprint_z=round(sz, 2) if sz != '' else '',
                    placement_delta_m=delta, source_footprint_axis_deg=fp.get('footprint_orientation_deg', ''),
                    verified_placement='', verified_rotation_deg='',
                    verified_frontage=finding.get('verified_frontage', ''), verified_door=finding.get('verified_door', ''),
                    corner_entrance=finding.get('corner_entrance', ''), storefront_glass=finding.get('storefront_glass', ''),
                    sign_location=finding.get('sign_location', ''), facade=finding.get('facade', ''),
                    visible_shape=finding.get('visible_shape', ''), observed_identity=finding.get('observed_identity', ''),
                    image_reference=primary[1], image_source=primary[0], image_capture_date=primary[2].get('capture_date', ''),
                    image_recorded_road=primary[2].get('road', ''), panorama_references=' | '.join(pano_refs[:8]),
                    visual_review=visual, evidence=finding.get('evidence', 'Overview screened; image does not establish tenant, entrance, facade details or frontage.' if visual == 'overview_screened' else 'No visually inspected image establishing this building.'),
                    confidence=confidence, recommended_fix=finding.get('recommended_fix', 'Inspect full-size frontage and parcel before any placement/facade edit.'),
                ))
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    write_report(rows)
    print('rows', len(rows), 'buildings', len({r['building_id'] for r in rows}), 'tiles', len({r['tile'] for r in rows}))
    print('section rows', sum(r['record_type'] == 'storefront_section' for r in rows))
    print('confidence', dict(Counter(r['confidence'] for r in rows)))
    print('visual', dict(Counter(r['visual_review'] for r in rows)))


def write_report(rows):
    sections = [r for r in rows if r['record_type'] == 'storefront_section']
    commercial = [r for r in rows if r['record_type'] == 'building' and r['current_style'] in {'storefront', 'commercial'}]
    tiles = sorted({r['tile'] for r in rows})
    by_tile = {t: [r for r in sections if r['tile'] == t] for t in sorted({r['tile'] for r in sections})}
    linked = sum(bool(r['image_reference']) for r in sections)
    overview = sum(r['visual_review'] == 'overview_screened' for r in sections)
    full = sum(r['visual_review'] == 'full_size' for r in sections)
    delta = sum(bool(r['placement_delta_m']) and float(r['placement_delta_m']) > 5 for r in sections)
    lines = [
        '# Chester citywide visual audit', '',
        '## Scope and limits', '',
        f'- {len(rows):,} building/storefront rows represent {len({r["building_id"] for r in rows}):,} stable ChesterBuildingId/OBJECTID records across {len(tiles)} nonempty BuildingTiles files. The game world has 102 tiles; 16 have no BuildingTiles file in this checkout.',
        f'- {len(sections)} storefront sections on {len({r["building_id"] for r in sections})} buildings across {len(by_tile)} building tiles; {len(commercial):,} storefront/commercial building-level records across {len({r["tile"] for r in commercial})} tiles.',
        f'- {linked} storefront sections link to a local street image; {len(sections)-linked} have no matched image. {overview} were screened only as overview contact-sheet images, and {full} were examined full size. Overview screening cannot verify small signs, exact doors, colors or tenant identity.',
        '- The 2025 aerial index and county GIS footprints are local references. Footprint centers, source orientations and projected game coordinates were joined by OBJECTID. A footprint match or nearest road is not facade proof. Three cropped aerial examples were visually checked; the rest of the city aerial coverage remains uninspected.',
        f'- {delta} storefront sections have a tile centroid more than 5 m from the county footprint center; {sum(not r["source_lat"] for r in sections)} have no matched county footprint. These are review flags, not certified placement errors.',
        '- `confidence=probable` means an overview image and footprint position support a structure at the ID, **not** a verified frontage or facade. `unresolved` means an image exists but its view or geometry cannot support even that limited conclusion. `conflicting` records an observed source mismatch. All empty verified fields remain unknown.',
        '', '## Source-grounded priority findings', '',
        '- **93584, 9th / Kerlin / Concord:** A 2020-11 Google view shows a long low corner strip, glazed Concord-facing storefront and white painted side wall. It does not prove which unit is Boost Mobile, 5 Points Deli or J&S, nor the J&S front-lot position. The current tile combines Boost Mobile and J & S sections under one ID. Resolve separate parcel/building association and obtain a direct W 9th view before facade or door edits.',
        '- **50221, US Gas:** A 2024-09 Google view visibly shows the US GAS canopy and a separate D & D Laundry fascia to its left. The tile assigns the laundry shop section to the US Gas building ID. Review the attached structures and separate footprints before any split or door placement.',
        '- **189198, Shad Check Cashing & Wireless:** The 2026-04 Google view shows a two-story corner row building with brick upper story and pale painted ground floor. No legible Check Cashing sign or exact entrance is visible. The county address is 1200 W 9th Street, while US Gas 50221 is 610 W 9th Street; the supplied IDs do not establish that these two are attached.',
        '- **Sherylynn at 9th & Lincoln:** No Sherylynn storefront name or stable ID appears in the current BuildingTiles or the matched local places CSV. The existing identity script records owner-provided W 9th frontage, but this audit cannot associate a current tile section or verify a door/image. Resolve source identity before placing it.',
        '- **All corner stores:** Corner geometry was screened in available overview images. Exact corner entrances, two-face glazing, sign locations and unit boundaries remain open except the limited full-size observations above. Do not apply a nearest-road rule to them.',
        '', '## Coverage by building tile', '',
        '| Tile | Storefront sections | Linked images | Full-size reviews | Missing images | >5 m footprint flags |',
        '|---|---:|---:|---:|---:|---:|',
    ]
    for tile, group in by_tile.items():
        lines.append(f'| {tile} | {len(group)} | {sum(bool(r["image_reference"]) for r in group)} | {sum(r["visual_review"] == "full_size" for r in group)} | {sum(not r["image_reference"] for r in group)} | {sum(bool(r["placement_delta_m"]) and float(r["placement_delta_m"]) > 5 for r in group)} |')
    lines += ['', '## Reconstruction queue', '',
              '1. Resolve the named 9th Street and Kerlin source-ID/tenant conflicts with direct photos and parcel boundaries.',
              '2. Review storefront sections with >5 m centroid differences and any missing county footprint.',
              '3. Inspect each linked full-size photo plus aerial/footprint before entering a verified frontage, door, sign or facade correction.',
              '4. Keep imagery-missing sections and uninspected building photos as unknown until local evidence exists.',
              '', 'This pass changed no BuildingTiles, runtime placement, doors, signs, roads, player data or gameplay. Images remain on the local E: drive and are not committed.', '']
    DOC.parent.mkdir(exist_ok=True)
    DOC.write_text('\n'.join(lines), encoding='utf-8')


if __name__ == '__main__':
    main()
