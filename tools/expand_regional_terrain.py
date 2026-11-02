#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import os
import shutil
import time
from pathlib import Path
from urllib.parse import urlparse, unquote

import numpy as np
import requests
import rasterio
from pyproj import Transformer
from rasterio.features import geometry_mask
from rasterio.warp import (
    Resampling,
    reproject,
    transform_bounds,
)
from rasterio.transform import from_bounds
from shapely.geometry import box, mapping, shape
from shapely.ops import unary_union, transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")

REGION_DIR = ROOT / "Data" / "00_Boundary" / "RegionalExpansion"
BOUNDARY = REGION_DIR / "chester_region_boundary.geojson"

OLD_TERRAIN_DIR = ROOT / "Data" / "09_Terrain"
OLD_METADATA = OLD_TERRAIN_DIR / "chester_3dep_tiles_metadata.json"

LEGACY_TERRAIN_DIR = (
    ROOT / "ChesterWorldMapData" / "Data" / "09_Terrain"
)

OUT_DIR = ROOT / "Data" / "09_RegionalTerrain"
SOURCE_CACHE = OUT_DIR / "TNM_Source"
PRODUCT_CACHE = SOURCE_CACHE / "tnm_1m_products.json"

OUT_METADATA = OUT_DIR / "regional_3dep_tiles_metadata.json"
REPORT = REGION_DIR / "regional_terrain_expansion_report.json"

TNM_PRODUCTS = "https://tnmaccess.nationalmap.gov/api/v1/products"
TNM_DATASET = "Digital Elevation Model (DEM) 1 meter"

SOURCE_CRS = "EPSG:4326"
METRIC_CRS = "EPSG:3857"

TO_3857 = Transformer.from_crs(
    SOURCE_CRS, METRIC_CRS, always_xy=True
).transform

PIXEL_SIZE_M = 1.0
FILL_TILE_M = 1000.0
BOUNDARY_PAD_M = 60.0
NODATA = -9999.0

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": "ChesterWorld/1.0 TNM terrain builder"
})


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2),
        encoding="utf-8",
    )


def boundary_geometries():
    if not BOUNDARY.exists():
        raise SystemExit(
            f"Missing regional boundary: {BOUNDARY}\n"
            "Run build_regional_expansion.py first."
        )

    data = load_json(BOUNDARY)
    geoms = [
        shape(f["geometry"])
        for f in data.get("features", [])
        if f.get("geometry")
    ]

    if not geoms:
        raise SystemExit("Regional boundary contains no valid geometry.")

    region_wgs84 = unary_union(geoms)
    region_3857 = shp_transform(
        TO_3857,
        region_wgs84,
    ).buffer(BOUNDARY_PAD_M)

    return region_wgs84, region_3857


def old_filename(tile):
    for field in (
        "filename",
        "file",
        "path",
        "relative_path",
        "filepath",
        "source_file",
    ):
        value = tile.get(field)
        if value:
            return Path(
                str(value).replace("\\", "/")
            ).name

    row = tile.get("row")
    col = tile.get("column")

    if row is None or col is None:
        return None

    return (
        f"chester_dem_"
        f"r{int(row):02d}_"
        f"c{int(col):02d}.tif"
    )


def tile_bounds(tile):
    b = tile.get("bounds") or {}

    try:
        return box(
            float(b["xmin"]),
            float(b["ymin"]),
            float(b["xmax"]),
            float(b["ymax"]),
        )
    except Exception:
        return None


def resolve_existing_dem(tile):
    filename = old_filename(tile)

    if not filename:
        return None

    known_roots = [
        OLD_TERRAIN_DIR,
        LEGACY_TERRAIN_DIR,
    ]

    common_subdirs = [
        Path("."),
        Path("Tiles"),
        Path("tiles"),
        Path("DEM"),
        Path("dem"),
        Path("GeoTIFF"),
        Path("GeoTIFFs"),
        Path("TIF"),
        Path("Tiffs"),
        Path("Source"),
        Path("Raw"),
    ]

    candidates = []

    for field in (
        "filename",
        "file",
        "path",
        "relative_path",
        "filepath",
        "source_file",
    ):
        value = tile.get(field)
        if not value:
            continue

        p = Path(str(value).replace("\\", "/"))

        if p.is_absolute():
            candidates.append(p)
        else:
            for root in known_roots:
                candidates.append(root / p)

    for root in known_roots:
        for subdir in common_subdirs:
            candidates.append(
                root / subdir / filename
            )

    seen = set()

    for path in candidates:
        key = str(path).lower()

        if key in seen:
            continue

        seen.add(key)

        if path.is_file():
            return path

    matches = []

    for match in ROOT.rglob(filename):
        if not match.is_file():
            continue

        try:
            match.relative_to(OUT_DIR)
            continue
        except ValueError:
            pass

        matches.append(match)

    if not matches:
        return None

    matches.sort(
        key=lambda p: (
            0 if "09_terrain" in str(p).lower() else 1,
            0 if "chesterworldmapdata" in str(p).lower() else 1,
            len(str(p)),
            str(p).lower(),
        )
    )

    return matches[0]


def copy_existing_terrain():
    metadata_path = OLD_METADATA

    if not metadata_path.exists():
        legacy = (
            LEGACY_TERRAIN_DIR
            / "chester_3dep_tiles_metadata.json"
        )

        if legacy.exists():
            metadata_path = legacy
        else:
            raise SystemExit(
                "Missing Chester terrain metadata in both "
                "known locations."
            )

    print(f"Using terrain metadata: {metadata_path}")

    old = load_json(metadata_path)
    old_tiles = old.get("tiles") or []

    if not old_tiles:
        raise SystemExit(
            "Old terrain metadata contains no tiles."
        )

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    copied_entries = []
    coverage_boxes = []
    source_roots = {}
    missing_files = []

    for index, tile in enumerate(
        old_tiles,
        start=1,
    ):
        filename = old_filename(tile)
        bounds_geom = tile_bounds(tile)

        if not filename or bounds_geom is None:
            continue

        src = resolve_existing_dem(tile)

        if src is None:
            missing_files.append(filename)
            continue

        dst = OUT_DIR / filename

        if (
            not dst.exists()
            or dst.stat().st_size != src.stat().st_size
        ):
            shutil.copy2(src, dst)

        source_roots[str(src.parent)] = (
            source_roots.get(
                str(src.parent),
                0,
            )
            + 1
        )

        entry = dict(tile)
        entry["filename"] = filename
        entry["source_kind"] = (
            "existing_chester_terrain"
        )
        entry["original_source_path"] = str(src)

        copied_entries.append(entry)
        coverage_boxes.append(bounds_geom)

    if missing_files:
        print(
            "\nCould not locate these existing Chester DEMs:"
        )
        for filename in missing_files:
            print(f"  - {filename}")

        raise SystemExit(
            "Existing Chester terrain is incomplete. "
            "No substitution was attempted."
        )

    print("\nExisting Chester DEM source locations:")
    for source_root, count in sorted(
        source_roots.items(),
        key=lambda item: (-item[1], item[0]),
    ):
        print(
            f"  {count:>2} tile(s): {source_root}"
        )

    return (
        old,
        copied_entries,
        unary_union(coverage_boxes),
    )


def aligned_gap_cells(region_3857, missing):
    minx, miny, maxx, maxy = (
        region_3857.bounds
    )

    gx0 = (
        math.floor(minx / FILL_TILE_M)
        * FILL_TILE_M
    )
    gy0 = (
        math.floor(miny / FILL_TILE_M)
        * FILL_TILE_M
    )
    gx1 = (
        math.ceil(maxx / FILL_TILE_M)
        * FILL_TILE_M
    )
    gy1 = (
        math.ceil(maxy / FILL_TILE_M)
        * FILL_TILE_M
    )

    cols = int(
        round((gx1 - gx0) / FILL_TILE_M)
    )
    rows = int(
        round((gy1 - gy0) / FILL_TILE_M)
    )

    output = []

    for row in range(rows):
        ymin = gy0 + row * FILL_TILE_M
        ymax = ymin + FILL_TILE_M

        for col in range(cols):
            xmin = gx0 + col * FILL_TILE_M
            xmax = xmin + FILL_TILE_M

            cell = box(
                xmin,
                ymin,
                xmax,
                ymax,
            )

            gap = (
                cell
                .intersection(missing)
                .intersection(region_3857)
            )

            if gap.is_empty or gap.area < 4.0:
                continue

            output.append(
                (row, col, cell, gap)
            )

    return output


def tnm_query(region_wgs84):
    SOURCE_CACHE.mkdir(
        parents=True,
        exist_ok=True,
    )

    if PRODUCT_CACHE.exists():
        cached = load_json(PRODUCT_CACHE)

        items = cached.get("items") or []

        if items:
            print(
                f"Using cached TNM product list: "
                f"{len(items)} product(s)"
            )
            return items

    minx, miny, maxx, maxy = (
        region_wgs84.bounds
    )

    bbox_value = (
        f"{minx:.8f},{miny:.8f},"
        f"{maxx:.8f},{maxy:.8f}"
    )

    print(
        "Querying TNMAccess for pre-staged "
        "1 meter DEM products..."
    )
    print(f"TNM bbox: {bbox_value}")

    all_items = []
    offset = 0
    page_size = 100

    while True:
        params = {
            "bbox": bbox_value,
            "datasets": TNM_DATASET,
            "prodFormats": "GeoTIFF",
            "max": page_size,
            "offset": offset,
        }

        last_error = None

        for attempt in range(1, 6):
            try:
                response = SESSION.get(
                    TNM_PRODUCTS,
                    params=params,
                    timeout=90,
                )
                response.raise_for_status()
                data = response.json()
                last_error = None
                break
            except Exception as exc:
                last_error = exc

                if attempt == 5:
                    raise RuntimeError(
                        "TNMAccess product query failed: "
                        f"{exc}"
                    ) from exc

                wait = min(30, attempt * 4)
                print(
                    f"  query retry {attempt}/4 "
                    f"after error: {exc}"
                )
                time.sleep(wait)

        items = data.get("items") or []

        if not items:
            break

        all_items.extend(items)

        total = data.get("total")

        print(
            f"  product records: "
            f"{len(all_items)}"
            + (
                f"/{int(total)}"
                if total is not None
                else ""
            )
        )

        offset += len(items)

        if len(items) < page_size:
            break

        if (
            total is not None
            and offset >= int(total)
        ):
            break

    # Keep only products that expose a GeoTIFF download URL.
    cleaned = []
    seen_urls = set()

    for item in all_items:
        urls = []

        direct = item.get("downloadURL")
        if direct:
            urls.append(direct)

        for file_info in item.get("files") or []:
            url = (
                file_info.get("url")
                or file_info.get("downloadURL")
            )
            if url:
                urls.append(url)

        chosen = None

        for url in urls:
            lower = url.lower().split("?")[0]

            if lower.endswith(
                (".tif", ".tiff")
            ):
                chosen = url
                break

        if not chosen:
            continue

        if chosen in seen_urls:
            continue

        seen_urls.add(chosen)

        record = dict(item)
        record["_resolved_download_url"] = chosen
        cleaned.append(record)

    if not cleaned:
        raise RuntimeError(
            "TNMAccess returned no downloadable GeoTIFF "
            f"products for dataset '{TNM_DATASET}'."
        )

    # Newest products first where publicationDate exists.
    cleaned.sort(
        key=lambda item: str(
            item.get("publicationDate")
            or item.get("dateCreated")
            or item.get("lastUpdated")
            or ""
        ),
        reverse=True,
    )

    save_json(
        PRODUCT_CACHE,
        {
            "dataset": TNM_DATASET,
            "bbox": bbox_value,
            "items": cleaned,
        },
    )

    print(
        f"TNM downloadable 1 m DEM products: "
        f"{len(cleaned)}"
    )

    return cleaned


def safe_source_filename(item, index):
    url = item["_resolved_download_url"]

    name = Path(
        unquote(urlparse(url).path)
    ).name

    if not name.lower().endswith(
        (".tif", ".tiff")
    ):
        name = f"tnm_1m_{index:03d}.tif"

    return name


def validate_raster(path):
    try:
        with rasterio.open(path) as src:
            return (
                src.count >= 1
                and src.width > 0
                and src.height > 0
                and src.crs is not None
            )
    except Exception:
        return False


def resumable_download(url, path):
    if path.exists() and validate_raster(path):
        print(f"  cached: {path.name}")
        return

    part = path.with_suffix(
        path.suffix + ".part"
    )

    for attempt in range(1, 8):
        existing = (
            part.stat().st_size
            if part.exists()
            else 0
        )

        headers = {}

        if existing > 0:
            headers["Range"] = (
                f"bytes={existing}-"
            )

        try:
            with SESSION.get(
                url,
                headers=headers,
                stream=True,
                timeout=(30, 300),
            ) as response:
                response.raise_for_status()

                if (
                    existing > 0
                    and response.status_code == 206
                ):
                    mode = "ab"
                else:
                    mode = "wb"
                    existing = 0

                total_header = (
                    response.headers.get(
                        "Content-Length"
                    )
                )

                expected = (
                    int(total_header)
                    if total_header
                    else None
                )

                downloaded = 0

                with part.open(mode) as f:
                    for chunk in response.iter_content(
                        chunk_size=4 * 1024 * 1024
                    ):
                        if not chunk:
                            continue

                        f.write(chunk)
                        downloaded += len(chunk)

                if (
                    expected is not None
                    and downloaded < expected
                ):
                    raise IOError(
                        "download ended early: "
                        f"{downloaded} < {expected}"
                    )

            part.replace(path)

            if not validate_raster(path):
                path.unlink(missing_ok=True)
                raise IOError(
                    "downloaded file is not a readable "
                    "georeferenced raster"
                )

            return

        except Exception as exc:
            print(
                f"    direct download retry "
                f"{attempt}/6 after error: {exc}"
            )

            if attempt == 7:
                raise

            time.sleep(
                min(45, 4 * attempt)
            )


def download_products(items):
    SOURCE_CACHE.mkdir(
        parents=True,
        exist_ok=True,
    )

    paths = []

    for index, item in enumerate(
        items,
        start=1,
    ):
        url = item[
            "_resolved_download_url"
        ]

        filename = safe_source_filename(
            item,
            index,
        )

        path = SOURCE_CACHE / filename

        title = (
            item.get("title")
            or item.get("productName")
            or filename
        )

        print(
            f"[TNM {index:02d}/{len(items):02d}] "
            f"{title}"
        )

        resumable_download(
            url,
            path,
        )

        paths.append(path)

    return paths


def source_records(paths):
    records = []

    for path in paths:
        src = rasterio.open(path)

        try:
            bounds_3857 = transform_bounds(
                src.crs,
                METRIC_CRS,
                *src.bounds,
                densify_pts=21,
            )
        except Exception:
            src.close()
            raise

        records.append({
            "path": path,
            "src": src,
            "bounds_3857": box(
                *bounds_3857
            ),
        })

    return records


def stable_gap_filename(cell):
    xmin, ymin, xmax, ymax = (
        cell.bounds
    )

    width = int(round(xmax - xmin))
    height = int(round(ymax - ymin))

    sx = str(int(round(xmin))).replace(
        "-", "m"
    )
    sy = str(int(round(ymin))).replace(
        "-", "m"
    )

    return (
        f"regional_dem_x{sx}_y{sy}_"
        f"{width}x{height}.tif"
    )


def raster_metadata(
    path,
    row,
    col,
    source_kind,
):
    with rasterio.open(path) as src:
        bounds = src.bounds
        arr = src.read(1, masked=True)

        if arr.count():
            minimum = float(arr.min())
            maximum = float(arr.max())
        else:
            minimum = None
            maximum = None

        return {
            "row": int(row),
            "column": int(col),
            "filename": path.name,
            "source_kind": source_kind,
            "bounds": {
                "xmin": float(bounds.left),
                "ymin": float(bounds.bottom),
                "xmax": float(bounds.right),
                "ymax": float(bounds.top),
            },
            "width": int(src.width),
            "height": int(src.height),
            "pixel_size_x": abs(
                float(src.transform.a)
            ),
            "pixel_size_y": abs(
                float(src.transform.e)
            ),
            "min_elevation_m": minimum,
            "max_elevation_m": maximum,
        }


def build_gap_tile(
    cell,
    gap,
    row,
    col,
    sources,
):
    filename = stable_gap_filename(cell)
    path = OUT_DIR / filename

    width = int(
        round(
            (cell.bounds[2] - cell.bounds[0])
            / PIXEL_SIZE_M
        )
    )
    height = int(
        round(
            (cell.bounds[3] - cell.bounds[1])
            / PIXEL_SIZE_M
        )
    )

    # Reuse valid output from the earlier exportImage attempt.
    if path.exists() and validate_raster(path):
        with rasterio.open(path) as src:
            reusable = (
                src.crs is not None
                and src.width == width
                and src.height == height
                and str(src.crs).upper()
                in {"EPSG:3857", "ESRI:102100"}
            )

        if reusable:
            print(
                f"    reusing existing gap TIFF: "
                f"{filename}"
            )
            return raster_metadata(
                path,
                1000 + row,
                1000 + col,
                "regional_gap_cached_or_tnm",
            )

    xmin, ymin, xmax, ymax = (
        cell.bounds
    )

    transform = from_bounds(
        xmin,
        ymin,
        xmax,
        ymax,
        width,
        height,
    )

    destination = np.full(
        (height, width),
        NODATA,
        dtype="float32",
    )

    hit_count = 0

    for record in sources:
        if not record[
            "bounds_3857"
        ].intersects(cell):
            continue

        src = record["src"]

        temp = np.full(
            (height, width),
            NODATA,
            dtype="float32",
        )

        reproject(
            source=rasterio.band(src, 1),
            destination=temp,
            src_transform=src.transform,
            src_crs=src.crs,
            src_nodata=src.nodata,
            dst_transform=transform,
            dst_crs=METRIC_CRS,
            dst_nodata=NODATA,
            resampling=Resampling.bilinear,
            num_threads=2,
        )

        valid = (
            np.isfinite(temp)
            & (temp != NODATA)
        )

        write_mask = (
            valid
            & (destination == NODATA)
        )

        if np.any(write_mask):
            destination[write_mask] = (
                temp[write_mask]
            )
            hit_count += 1

    allowed = geometry_mask(
        [mapping(gap)],
        out_shape=destination.shape,
        transform=transform,
        invert=True,
        all_touched=True,
    )

    destination[~allowed] = NODATA

    valid_final = (
        np.isfinite(destination)
        & (destination != NODATA)
    )

    valid_count = int(
        np.count_nonzero(valid_final)
    )

    gap_pixels = int(
        np.count_nonzero(allowed)
    )

    if gap_pixels == 0:
        return None

    coverage = (
        valid_count
        / gap_pixels
        if gap_pixels
        else 0.0
    )

    if coverage < 0.98:
        raise RuntimeError(
            f"TNM source coverage incomplete for "
            f"{filename}: "
            f"{coverage * 100:.2f}% of required "
            f"gap pixels filled."
        )

    profile = {
        "driver": "GTiff",
        "height": height,
        "width": width,
        "count": 1,
        "dtype": "float32",
        "crs": METRIC_CRS,
        "transform": transform,
        "nodata": NODATA,
        "compress": "lzw",
        "tiled": True,
        "blockxsize": 256,
        "blockysize": 256,
    }

    temp_path = path.with_suffix(
        ".working.tif"
    )

    with rasterio.open(
        temp_path,
        "w",
        **profile,
    ) as dst:
        dst.write(destination, 1)

    temp_path.replace(path)

    entry = raster_metadata(
        path,
        1000 + row,
        1000 + col,
        "tnm_1m_regional_gap",
    )

    entry["valid_gap_pixels"] = (
        valid_count
    )
    entry["required_gap_pixels"] = (
        gap_pixels
    )
    entry["gap_fill_percent"] = round(
        coverage * 100.0,
        4,
    )
    entry["tnm_sources_used"] = hit_count

    return entry


def coverage_percent(
    region,
    entries,
):
    geoms = []

    for tile in entries:
        b = tile_bounds(tile)

        if b is not None:
            geoms.append(b)

    if not geoms or region.area <= 0:
        return 0.0

    coverage = unary_union(geoms)

    return (
        100.0
        * region.intersection(coverage).area
        / region.area
    )


def close_sources(records):
    for record in records:
        try:
            record["src"].close()
        except Exception:
            pass


def main():
    print("=" * 88)
    print("CHESTERWORLD REGIONAL TERRAIN — TNM DIRECT DOWNLOAD")
    print("=" * 88)

    region_wgs84, region_3857 = (
        boundary_geometries()
    )

    print(
        "Preserving existing Chester DEM tiles..."
    )

    (
        old_metadata,
        existing_entries,
        old_coverage,
    ) = copy_existing_terrain()

    missing = region_3857.difference(
        old_coverage
    )

    existing_pct = (
        100.0
        * region_3857
        .intersection(old_coverage)
        .area
        / region_3857.area
    )

    print()
    print(
        f"Existing Chester terrain covers "
        f"{existing_pct:.2f}% of padded "
        f"regional boundary."
    )

    if missing.is_empty:
        gap_cells = []
    else:
        gap_cells = aligned_gap_cells(
            region_3857,
            missing,
        )

    print(
        f"Regional 1 km gap cells required: "
        f"{len(gap_cells)}"
    )

    if not gap_cells:
        new_entries = []
        source_paths = []
        source_records_list = []
    else:
        items = tnm_query(
            region_wgs84
        )

        source_paths = download_products(
            items
        )

        print()
        print(
            "Opening TNM DEM source rasters..."
        )

        source_records_list = (
            source_records(source_paths)
        )

        print(
            f"TNM source rasters ready: "
            f"{len(source_records_list)}"
        )

        new_entries = []

        try:
            for index, (
                row,
                col,
                cell,
                gap,
            ) in enumerate(
                gap_cells,
                start=1,
            ):
                print(
                    f"[{index:03d}/"
                    f"{len(gap_cells):03d}] "
                    f"{stable_gap_filename(cell)}"
                )

                entry = build_gap_tile(
                    cell,
                    gap,
                    row,
                    col,
                    source_records_list,
                )

                if entry is not None:
                    new_entries.append(entry)

                    print(
                        f"    gap fill: "
                        f"{entry.get('gap_fill_percent', 100):.2f}%"
                    )
        finally:
            close_sources(
                source_records_list
            )

    all_entries = (
        existing_entries
        + new_entries
    )

    final_pct = coverage_percent(
        region_3857,
        all_entries,
    )

    metadata = {
        "source": (
            "Existing Chester 3DEP terrain + "
            "USGS TNMAccess pre-staged 1 meter "
            "DEM products clipped locally"
        ),
        "source_api": TNM_PRODUCTS,
        "dataset": TNM_DATASET,
        "coordinate_system": METRIC_CRS,
        "pixel_size": PIXEL_SIZE_M,
        "regional_boundary_pad_m": (
            BOUNDARY_PAD_M
        ),
        "preserves_existing_chester_dem": True,
        "nodata": NODATA,
        "source_product_cache": str(
            PRODUCT_CACHE
        ),
        "source_raster_directory": str(
            SOURCE_CACHE
        ),
        "tiles": all_entries,
    }

    save_json(
        OUT_METADATA,
        metadata,
    )

    report = {
        "existing_tile_count": len(
            existing_entries
        ),
        "new_gap_tile_count": len(
            new_entries
        ),
        "total_tile_count": len(
            all_entries
        ),
        "tnm_source_product_count": len(
            source_paths
        ),
        "existing_coverage_percent": round(
            existing_pct,
            4,
        ),
        "final_coverage_percent": round(
            final_pct,
            4,
        ),
        "output_directory": str(OUT_DIR),
        "metadata": str(OUT_METADATA),
    }

    save_json(
        REPORT,
        report,
    )

    print()
    print("=" * 88)
    print("REGIONAL TERRAIN DIRECT BUILD COMPLETE")
    print("=" * 88)
    print(
        f"Existing Chester DEM tiles: "
        f"{len(existing_entries):,}"
    )
    print(
        f"TNM source products cached: "
        f"{len(source_paths):,}"
    )
    print(
        f"Regional 1 km gap tiles: "
        f"{len(new_entries):,}"
    )
    print(
        f"Combined terrain tiles: "
        f"{len(all_entries):,}"
    )
    print(
        f"Combined rectangular coverage: "
        f"{final_pct:.2f}%"
    )
    print(f"Metadata: {OUT_METADATA}")
    print("=" * 88)
    print()
    print(
        "Now run audit_regional_ready.py. "
        "The PowerShell runner does this "
        "automatically."
    )


if __name__ == "__main__":
    main()
