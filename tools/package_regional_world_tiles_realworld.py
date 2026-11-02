import csv
import json
import math
import os
from collections import Counter, defaultdict

from pyproj import Transformer
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union, transform as shapely_transform
from shapely.strtree import STRtree


# ============================================================
# CHESTER REGION -> UNITY TILE PACKAGER
#
# Produces streamable 1 km tiles using Chester-local meters.
#
# Unity coordinate convention:
#   X = east
#   Y = elevation (added later from DEM)
#   Z = north
#
# All vector geometry is converted from WGS84 to EPSG:3857,
# then shifted by a local Chester origin so coordinates stay
# near zero and Unity floating-point precision remains stable.
# ============================================================


# ============================================================
# PATHS
# ============================================================

ROOT = r"E:\ChesterWorld"

BOUNDARY_FILE = os.path.join(
    ROOT,
    "Data",
    "00_Boundary",
    "RegionalExpansion",
    "chester_region_boundary.geojson"
)

BUILDINGS_FILE = os.path.join(
    ROOT,
    "Data",
    "14_RegionalGeneratorPrep_v2",
    "regional_generator_buildings_v2.geojson"
)

ROADS_FILE = os.path.join(
    ROOT,
    "Data",
    "17_RealWorldCleanup",
    "regional_generator_roads_render_v2.geojson"
)

POI_POINTS_FILE = os.path.join(
    ROOT,
    "Data",
    "04_POI",
    "osm_poi_points.geojson"
)

POI_AREAS_FILE = os.path.join(
    ROOT,
    "Data",
    "04_POI",
    "osm_poi_areas.geojson"
)

SCHOOLS_FILE = os.path.join(
    ROOT,
    "Data",
    "05_Official_POI",
    "delco_public_schools.geojson"
)

PARKS_FILE = os.path.join(
    ROOT,
    "Data",
    "05_Official_POI",
    "delco_parks.geojson"
)

STREAMS_FILE = os.path.join(
    ROOT,
    "Data",
    "06_Water",
    "delco_streams.geojson"
)

WATER_AREAS_FILE = os.path.join(
    ROOT,
    "Data",
    "06_Water",
    "delco_water_polygons.geojson"
)

RAIL_FILE = os.path.join(
    ROOT,
    "Data",
    "07_Rail",
    "penndot_railroads.geojson"
)

ZONING_FILE = os.path.join(
    ROOT,
    "Data",
    "08_Zoning",
    "delco_zoning.geojson"
)

LANDUSE_FILE = os.path.join(
    ROOT,
    "Data",
    "11_LandUse",
    "osm_landuse_areas.geojson"
)

TERRAIN_METADATA = os.path.join(
    ROOT,
    "Data",
    "09_RegionalTerrain",
    "regional_3dep_tiles_metadata.json"
)

CANOPY_METADATA = os.path.join(
    ROOT,
    "Data",
    "12_Vegetation",
    "Canopy_2013",
    "chester_tree_canopy_metadata.json"
)


OUTPUT_DIR = os.path.join(
    ROOT,
    "Data",
    "17_RegionalTiles_RealWorld"
)

TILES_DIR = os.path.join(
    OUTPUT_DIR,
    "Tiles"
)

MANIFEST_FILE = os.path.join(
    OUTPUT_DIR,
    "chester_world_manifest.json"
)

INDEX_FILE = os.path.join(
    OUTPUT_DIR,
    "chester_tile_index.csv"
)

STATS_FILE = os.path.join(
    OUTPUT_DIR,
    "chester_world_tile_stats.json"
)

os.makedirs(
    TILES_DIR,
    exist_ok=True
)


# ============================================================
# CONFIG
# ============================================================

TILE_SIZE_M = 1000.0

SOURCE_CRS = "EPSG:4326"
METRIC_CRS = "EPSG:3857"

# Small tolerance prevents precision cracks during clipping.
CLIP_EPSILON_M = 0.01


# ============================================================
# SOURCE LAYERS
# ============================================================

SOURCE_LAYERS = {
    "buildings":
        BUILDINGS_FILE,

    "roads":
        ROADS_FILE,

    "poi_points":
        POI_POINTS_FILE,

    "poi_areas":
        POI_AREAS_FILE,

    "schools":
        SCHOOLS_FILE,

    "parks":
        PARKS_FILE,

    "streams":
        STREAMS_FILE,

    "water_areas":
        WATER_AREAS_FILE,

    "rail":
        RAIL_FILE,

    "zoning":
        ZONING_FILE,

    "landuse":
        LANDUSE_FILE,
}


# ============================================================
# PROJECTION
# ============================================================

transformer = Transformer.from_crs(
    SOURCE_CRS,
    METRIC_CRS,
    always_xy=True
)

project = transformer.transform


# ============================================================
# JSON HELPERS
# ============================================================

def load_json(path):

    with open(
        path,
        "r",
        encoding="utf-8"
    ) as f:

        return json.load(f)


def load_features(path):

    data = load_json(
        path
    )

    return data.get(
        "features",
        []
    )


# ============================================================
# LOAD WORLD BOUNDARY
# ============================================================

print("")
print("============================================")
print("CHESTER REGIONAL UNITY TILE PACKAGER")
print("============================================")
print("")

print("Loading world boundary...")


boundary_data = load_json(
    BOUNDARY_FILE
)


boundary_geometries = []


for feature in boundary_data.get(
    "features",
    []
):

    try:

        geometry = shape(
            feature[
                "geometry"
            ]
        )

        if geometry.is_empty:
            continue

        boundary_geometries.append(
            geometry
        )

    except Exception:
        continue


if not boundary_geometries:

    raise RuntimeError(
        "World boundary contains no valid geometry."
    )


world_boundary_wgs84 = unary_union(
    boundary_geometries
)


world_boundary_m = shapely_transform(
    project,
    world_boundary_wgs84
)


minx, miny, maxx, maxy = (
    world_boundary_m.bounds
)


# Local Chester origin is the southwest corner of the exact
# world bounding box in EPSG:3857.
ORIGIN_X = math.floor(
    minx
)

ORIGIN_Z = math.floor(
    miny
)


WORLD_WIDTH_M = (
    maxx
    -
    ORIGIN_X
)

WORLD_DEPTH_M = (
    maxy
    -
    ORIGIN_Z
)


print(
    f"World local size: "
    f"{WORLD_WIDTH_M:,.1f} m x "
    f"{WORLD_DEPTH_M:,.1f} m"
)

print(
    f"Local origin EPSG:3857: "
    f"X={ORIGIN_X:.3f}, "
    f"Z={ORIGIN_Z:.3f}"
)


# ============================================================
# LOCAL COORDINATE CONVERSION
# ============================================================

def localize_geometry(geometry):

    def localize(
        x,
        y,
        z=None
    ):

        return (
            x - ORIGIN_X,
            y - ORIGIN_Z
        )

    return shapely_transform(
        localize,
        geometry
    )


# ============================================================
# PREP SOURCE LAYERS + SPATIAL INDEXES
# ============================================================

class LayerIndex:

    def __init__(
        self,
        name,
        path
    ):

        self.name = name
        self.path = path
        self.records = []
        self.geometries = []
        self.tree = None
        self.id_lookup = {}


    def load(self):

        if not os.path.exists(
            self.path
        ):

            print(
                f"WARNING: Missing layer "
                f"{self.name}: "
                f"{self.path}"
            )

            return


        features = load_features(
            self.path
        )


        for source_index, feature in enumerate(
            features
        ):

            geometry_json = feature.get(
                "geometry"
            )

            if not geometry_json:
                continue


            try:

                geometry_wgs = shape(
                    geometry_json
                )


                if geometry_wgs.is_empty:
                    continue


                geometry_m = shapely_transform(
                    project,
                    geometry_wgs
                )


            except Exception:
                continue


            if not geometry_m.intersects(
                world_boundary_m
            ):
                continue


            record_index = len(
                self.records
            )


            self.records.append({
                "source_index":
                    source_index,

                "properties":
                    dict(
                        feature.get(
                            "properties",
                            {}
                        )
                    ),

                "geometry_m":
                    geometry_m,
            })


            self.geometries.append(
                geometry_m
            )


        if self.geometries:

            self.tree = STRtree(
                self.geometries
            )

            self.id_lookup = {
                id(geometry):
                    index

                for index, geometry
                in enumerate(
                    self.geometries
                )
            }


    def query_indices(
        self,
        query_geometry
    ):

        if self.tree is None:
            return []


        try:

            raw = self.tree.query(
                query_geometry
            )

        except Exception:

            return []


        result = []


        for item in raw:

            # Shapely 2.x.
            try:

                value = int(
                    item
                )


                if (
                    0
                    <=
                    value
                    <
                    len(
                        self.records
                    )
                ):

                    result.append(
                        value
                    )

                    continue


            except Exception:
                pass


            # Shapely 1.x.
            index = self.id_lookup.get(
                id(item)
            )


            if index is not None:

                result.append(
                    index
                )


        return result


layer_indexes = {}


print("")
print("Loading vector layers...")


for layer_name, path in (
    SOURCE_LAYERS.items()
):

    index = LayerIndex(
        layer_name,
        path
    )

    index.load()

    layer_indexes[
        layer_name
    ] = index


    print(
        f"  {layer_name}: "
        f"{len(index.records):,}"
    )


# ============================================================
# GEOMETRY CLEANUP
# ============================================================

def clean_clipped_geometry(
    geometry
):

    if geometry is None:
        return None


    if geometry.is_empty:
        return None


    geometry_type = geometry.geom_type


    if geometry_type in {
        "Point",
        "MultiPoint",
        "LineString",
        "MultiLineString",
        "Polygon",
        "MultiPolygon",
    }:

        return geometry


    # GeometryCollection: keep useful components.
    if geometry_type == (
        "GeometryCollection"
    ):

        polygons = []
        lines = []
        points = []


        for part in geometry.geoms:

            if part.is_empty:
                continue


            if part.geom_type == "Polygon":

                polygons.append(
                    part
                )


            elif part.geom_type == (
                "MultiPolygon"
            ):

                polygons.extend(
                    list(
                        part.geoms
                    )
                )


            elif part.geom_type == (
                "LineString"
            ):

                lines.append(
                    part
                )


            elif part.geom_type == (
                "MultiLineString"
            ):

                lines.extend(
                    list(
                        part.geoms
                    )
                )


            elif part.geom_type == "Point":

                points.append(
                    part
                )


            elif part.geom_type == (
                "MultiPoint"
            ):

                points.extend(
                    list(
                        part.geoms
                    )
                )


        if polygons:

            merged = unary_union(
                polygons
            )

            return merged


        if lines:

            merged = unary_union(
                lines
            )

            return merged


        if points:

            merged = unary_union(
                points
            )

            return merged


    return None


# ============================================================
# TILE GRID
# ============================================================

tile_columns = int(
    math.ceil(
        WORLD_WIDTH_M
        /
        TILE_SIZE_M
    )
)

tile_rows = int(
    math.ceil(
        WORLD_DEPTH_M
        /
        TILE_SIZE_M
    )
)


print("")
print(
    f"Tile grid: "
    f"{tile_columns} columns x "
    f"{tile_rows} rows "
    f"@ {TILE_SIZE_M:.0f} m"
)


# ============================================================
# LOAD TERRAIN / CANOPY METADATA
# ============================================================

terrain_metadata = (
    load_json(
        TERRAIN_METADATA
    )
    if os.path.exists(
        TERRAIN_METADATA
    )
    else {}
)

canopy_metadata = (
    load_json(
        CANOPY_METADATA
    )
    if os.path.exists(
        CANOPY_METADATA
    )
    else {}
)


terrain_tiles = terrain_metadata.get(
    "tiles",
    []
)

canopy_tiles = canopy_metadata.get(
    "tiles",
    []
)


def metadata_tile_box(
    tile
):

    bounds = tile.get(
        "bounds",
        {}
    )


    try:

        return box(
            float(
                bounds["xmin"]
            ),
            float(
                bounds["ymin"]
            ),
            float(
                bounds["xmax"]
            ),
            float(
                bounds["ymax"]
            ),
        )

    except Exception:

        return None


def overlapping_raster_tiles(
    world_tile_box,
    metadata_tiles,
    kind
):

    overlaps = []


    for raster_tile in metadata_tiles:

        raster_box = metadata_tile_box(
            raster_tile
        )


        if raster_box is None:
            continue


        if not raster_box.intersects(
            world_tile_box
        ):
            continue


        row = raster_tile.get(
            "row"
        )

        column = raster_tile.get(
            "column"
        )


        if row is None or column is None:
            continue


        if kind == "terrain":

            filename = (
                f"chester_dem_"
                f"r{int(row):02d}_"
                f"c{int(column):02d}.tif"
            )


        else:

            filename = (
                f"canopy_"
                f"r{int(row):02d}_"
                f"c{int(column):02d}_mask.png"
            )


        overlaps.append({
            "row":
                int(row),

            "column":
                int(column),

            "filename":
                filename,

            "bounds_epsg3857":
                raster_tile.get(
                    "bounds",
                    {}
                ),
        })


    return overlaps


# ============================================================
# TILE EXTRACTION
# ============================================================

def extract_layer_for_tile(
    layer_index,
    tile_clip_geometry
):

    results = []


    candidate_indices = (
        layer_index
        .query_indices(
            tile_clip_geometry
        )
    )


    for index in candidate_indices:

        record = (
            layer_index
            .records[
                index
            ]
        )


        geometry = record[
            "geometry_m"
        ]


        if not geometry.intersects(
            tile_clip_geometry
        ):

            continue


        try:

            clipped = geometry.intersection(
                tile_clip_geometry
            )


        except Exception:

            try:

                clipped = (
                    geometry
                    .buffer(0)
                    .intersection(
                        tile_clip_geometry
                    )
                )

            except Exception:

                continue


        clipped = clean_clipped_geometry(
            clipped
        )


        if clipped is None:
            continue


        local_geometry = localize_geometry(
            clipped
        )


        results.append({
            "properties":
                record[
                    "properties"
                ],

            "geometry":
                mapping(
                    local_geometry
                ),
        })


    return results


# ============================================================
# WHOLE-BUILDING TILE OWNERSHIP
# ============================================================
def extract_buildings_for_tile(layer_index, tile_world_box, row, column):
    results = []
    candidate_indices = layer_index.query_indices(tile_world_box)
    for index in candidate_indices:
        record = layer_index.records[index]
        geometry = record["geometry_m"]
        if geometry is None or geometry.is_empty:
            continue
        try:
            point = geometry.representative_point()
        except Exception:
            continue
        owner_column = int(math.floor((point.x - ORIGIN_X) / TILE_SIZE_M))
        owner_row = int(math.floor((point.y - ORIGIN_Z) / TILE_SIZE_M))
        owner_column = max(0, min(tile_columns - 1, owner_column))
        owner_row = max(0, min(tile_rows - 1, owner_row))
        if owner_row != row or owner_column != column:
            continue
        if not geometry.intersects(world_boundary_m):
            continue
        results.append({
            "properties": record["properties"],
            "geometry": mapping(localize_geometry(geometry)),
        })
    return results


# ============================================================
# BUILD TILES
# ============================================================

tile_index_rows = []
world_manifest_tiles = []
layer_totals = Counter()

active_tile_count = 0
empty_tile_count = 0


print("")
print("Building Unity world tiles...")


for row in range(
    tile_rows
):

    for column in range(
        tile_columns
    ):

        tile_minx = (
            ORIGIN_X
            +
            column
            *
            TILE_SIZE_M
        )

        tile_miny = (
            ORIGIN_Z
            +
            row
            *
            TILE_SIZE_M
        )

        tile_maxx = (
            tile_minx
            +
            TILE_SIZE_M
        )

        tile_maxy = (
            tile_miny
            +
            TILE_SIZE_M
        )


        tile_world_box = box(
            tile_minx,
            tile_miny,
            tile_maxx,
            tile_maxy
        )


        if not tile_world_box.intersects(
            world_boundary_m
        ):

            empty_tile_count += 1
            continue


        tile_clip = (
            tile_world_box
            .intersection(
                world_boundary_m
            )
        )


        if tile_clip.is_empty:

            empty_tile_count += 1
            continue


        active_tile_count += 1


        tile_id = (
            f"tile_"
            f"r{row:02d}_"
            f"c{column:02d}"
        )


        tile_layers = {}
        tile_counts = {}


        for layer_name, layer_index in (
            layer_indexes.items()
        ):

            layer_features = (
                extract_buildings_for_tile(
                    layer_index,
                    tile_world_box,
                    row,
                    column
                )
                if layer_name == "buildings"
                else extract_layer_for_tile(
                    layer_index,
                    tile_clip
                )
            )


            tile_layers[
                layer_name
            ] = layer_features


            count = len(
                layer_features
            )


            tile_counts[
                layer_name
            ] = count


            layer_totals[
                layer_name
            ] += count


        terrain_refs = (
            overlapping_raster_tiles(
                tile_world_box,
                terrain_tiles,
                "terrain"
            )
        )


        canopy_refs = (
            overlapping_raster_tiles(
                tile_world_box,
                canopy_tiles,
                "canopy"
            )
        )


        playable_local = localize_geometry(
            tile_clip
        )


        tile_payload = {
            "tile_id":
                tile_id,

            "row":
                row,

            "column":
                column,

            "tile_size_m":
                TILE_SIZE_M,

            "local_bounds_m": {
                "min_x":
                    tile_minx
                    -
                    ORIGIN_X,

                "min_z":
                    tile_miny
                    -
                    ORIGIN_Z,

                "max_x":
                    tile_maxx
                    -
                    ORIGIN_X,

                "max_z":
                    tile_maxy
                    -
                    ORIGIN_Z,
            },

            "playable_geometry":
                mapping(
                    playable_local
                ),

            "feature_counts":
                tile_counts,

            "terrain_sources":
                terrain_refs,

            "canopy_sources":
                canopy_refs,

            "layers":
                tile_layers,
        }


        tile_filename = (
            tile_id
            +
            ".json"
        )


        tile_path = os.path.join(
            TILES_DIR,
            tile_filename
        )


        with open(
            tile_path,
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                tile_payload,
                f,
                ensure_ascii=False,
                separators=(",", ":")
            )


        tile_size_mb = (
            os.path.getsize(
                tile_path
            )
            /
            (
                1024
                *
                1024
            )
        )


        world_manifest_tiles.append({
            "tile_id":
                tile_id,

            "row":
                row,

            "column":
                column,

            "file":
                os.path.join(
                    "Tiles",
                    tile_filename
                ).replace(
                    "\\",
                    "/"
                ),

            "local_bounds_m":
                tile_payload[
                    "local_bounds_m"
                ],

            "feature_counts":
                tile_counts,

            "terrain_sources":
                [
                    item[
                        "filename"
                    ]
                    for item in terrain_refs
                ],

            "canopy_sources":
                [
                    item[
                        "filename"
                    ]
                    for item in canopy_refs
                ],

            "file_size_mb":
                round(
                    tile_size_mb,
                    3
                ),
        })


        tile_index_rows.append({
            "tile_id":
                tile_id,

            "row":
                row,

            "column":
                column,

            "min_x":
                round(
                    tile_payload[
                        "local_bounds_m"
                    ][
                        "min_x"
                    ],
                    3
                ),

            "min_z":
                round(
                    tile_payload[
                        "local_bounds_m"
                    ][
                        "min_z"
                    ],
                    3
                ),

            "max_x":
                round(
                    tile_payload[
                        "local_bounds_m"
                    ][
                        "max_x"
                    ],
                    3
                ),

            "max_z":
                round(
                    tile_payload[
                        "local_bounds_m"
                    ][
                        "max_z"
                    ],
                    3
                ),

            "buildings":
                tile_counts.get(
                    "buildings",
                    0
                ),

            "roads":
                tile_counts.get(
                    "roads",
                    0
                ),

            "rail":
                tile_counts.get(
                    "rail",
                    0
                ),

            "streams":
                tile_counts.get(
                    "streams",
                    0
                ),

            "water_areas":
                tile_counts.get(
                    "water_areas",
                    0
                ),

            "landuse":
                tile_counts.get(
                    "landuse",
                    0
                ),

            "parks":
                tile_counts.get(
                    "parks",
                    0
                ),

            "poi_points":
                tile_counts.get(
                    "poi_points",
                    0
                ),

            "poi_areas":
                tile_counts.get(
                    "poi_areas",
                    0
                ),

            "terrain_tile_count":
                len(
                    terrain_refs
                ),

            "canopy_tile_count":
                len(
                    canopy_refs
                ),

            "file_size_mb":
                round(
                    tile_size_mb,
                    3
                ),
        })


        print(
            f"  {tile_id}: "
            f"{tile_counts.get('buildings', 0):,} buildings, "
            f"{tile_counts.get('roads', 0):,} roads, "
            f"{tile_size_mb:.2f} MB"
        )


# ============================================================
# WORLD MANIFEST
# ============================================================

world_manifest = {
    "world_name":
        "ChesterRegionWorld",

    "version":
        1,

    "source_crs":
        SOURCE_CRS,

    "metric_source_crs":
        METRIC_CRS,

    "unity_coordinate_system": {
        "x":
            "east_meters_from_origin",

        "y":
            "elevation_meters_from_dem",

        "z":
            "north_meters_from_origin",
    },

    "origin_epsg3857": {
        "x":
            ORIGIN_X,

        "z":
            ORIGIN_Z,
    },

    "world_size_m": {
        "width":
            WORLD_WIDTH_M,

        "depth":
            WORLD_DEPTH_M,
    },

    "tile_size_m":
        TILE_SIZE_M,

    "tile_grid": {
        "columns":
            tile_columns,

        "rows":
            tile_rows,

        "active_tiles":
            active_tile_count,
    },

    "source_files": {
        key:
            os.path.relpath(
                value,
                ROOT
            ).replace(
                "\\",
                "/"
            )

        for key, value
        in SOURCE_LAYERS.items()
    },

    "terrain": {
        "metadata":
            os.path.relpath(
                TERRAIN_METADATA,
                ROOT
            ).replace(
                "\\",
                "/"
            )
            if os.path.exists(
                TERRAIN_METADATA
            )
            else None,

        "pixel_size_m":
            terrain_metadata.get(
                "pixel_size"
            ),

        "source_tile_count":
            len(
                terrain_tiles
            ),
    },

    "canopy": {
        "metadata":
            os.path.relpath(
                CANOPY_METADATA,
                ROOT
            ).replace(
                "\\",
                "/"
            )
            if os.path.exists(
                CANOPY_METADATA
            )
            else None,

        "pixel_size_m":
            canopy_metadata.get(
                "pixel_size"
            ),

        "overall_coverage_percent":
            canopy_metadata.get(
                "overall_canopy_coverage_percent"
            ),

        "source_tile_count":
            len(
                canopy_tiles
            ),
    },

    "tiles":
        world_manifest_tiles,

    "notes": [
        "Tile vector geometry is already converted to Chester-local meters.",
        "Unity should interpret local geometry coordinate 0 as X and coordinate 1 as Z.",
        "Do not treat generator building archetypes as verified architectural truth.",
        "Terrain elevation should become Unity Y.",
        "Terrain and canopy source tiles remain separate raster assets and are referenced by each world tile.",
        "Features crossing a 1 km tile boundary are clipped into each relevant tile.",
    ],
}


with open(
    MANIFEST_FILE,
    "w",
    encoding="utf-8"
) as f:

    json.dump(
        world_manifest,
        f,
        indent=2
    )


# ============================================================
# TILE CSV INDEX
# ============================================================

index_fields = [
    "tile_id",
    "row",
    "column",
    "min_x",
    "min_z",
    "max_x",
    "max_z",
    "buildings",
    "roads",
    "rail",
    "streams",
    "water_areas",
    "landuse",
    "parks",
    "poi_points",
    "poi_areas",
    "terrain_tile_count",
    "canopy_tile_count",
    "file_size_mb",
]


with open(
    INDEX_FILE,
    "w",
    encoding="utf-8",
    newline=""
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=index_fields
    )

    writer.writeheader()

    writer.writerows(
        tile_index_rows
    )


# ============================================================
# STATS
# ============================================================

total_tile_bytes = 0


for item in world_manifest_tiles:

    path = os.path.join(
        OUTPUT_DIR,
        item[
            "file"
        ]
    )


    if os.path.isfile(
        path
    ):

        total_tile_bytes += (
            os.path.getsize(
                path
            )
        )


total_tile_mb = (
    total_tile_bytes
    /
    (
        1024
        *
        1024
    )
)


building_counts_per_tile = [
    tile[
        "feature_counts"
    ].get(
        "buildings",
        0
    )

    for tile
    in world_manifest_tiles
]


road_counts_per_tile = [
    tile[
        "feature_counts"
    ].get(
        "roads",
        0
    )

    for tile
    in world_manifest_tiles
]


stats = {
    "tile_size_m":
        TILE_SIZE_M,

    "tile_grid_columns":
        tile_columns,

    "tile_grid_rows":
        tile_rows,

    "active_tiles":
        active_tile_count,

    "inactive_grid_tiles":
        empty_tile_count,

    "world_width_m":
        WORLD_WIDTH_M,

    "world_depth_m":
        WORLD_DEPTH_M,

    "layer_feature_counts_across_tiles":
        dict(
            layer_totals
        ),

    "buildings_per_tile": {
        "min":
            min(
                building_counts_per_tile
            )
            if building_counts_per_tile
            else 0,

        "max":
            max(
                building_counts_per_tile
            )
            if building_counts_per_tile
            else 0,

        "average":
            (
                sum(
                    building_counts_per_tile
                )
                /
                len(
                    building_counts_per_tile
                )
            )
            if building_counts_per_tile
            else 0,
    },

    "roads_per_tile": {
        "min":
            min(
                road_counts_per_tile
            )
            if road_counts_per_tile
            else 0,

        "max":
            max(
                road_counts_per_tile
            )
            if road_counts_per_tile
            else 0,

        "average":
            (
                sum(
                    road_counts_per_tile
                )
                /
                len(
                    road_counts_per_tile
                )
            )
            if road_counts_per_tile
            else 0,
    },

    "tile_json_size_mb":
        total_tile_mb,
}


with open(
    STATS_FILE,
    "w",
    encoding="utf-8"
) as f:

    json.dump(
        stats,
        f,
        indent=2
    )


# ============================================================
# DONE
# ============================================================

print("")
print("")
print("============================================")
print("DONE")
print("============================================")

print(
    f"Tile grid:          "
    f"{tile_columns} x {tile_rows}"
)

print(
    f"Active tiles:       "
    f"{active_tile_count:,}"
)

print(
    f"Inactive tiles:     "
    f"{empty_tile_count:,}"
)

print(
    f"World width:        "
    f"{WORLD_WIDTH_M:,.1f} m"
)

print(
    f"World depth:        "
    f"{WORLD_DEPTH_M:,.1f} m"
)

print(
    f"Tile JSON size:     "
    f"{total_tile_mb:.1f} MB"
)

print("")
print("Features across output tiles:")


for layer_name, count in (
    layer_totals.most_common()
):

    print(
        f"  {layer_name}: "
        f"{count:,}"
    )


if building_counts_per_tile:

    print("")
    print(
        f"Buildings/tile: "
        f"min {min(building_counts_per_tile):,}, "
        f"max {max(building_counts_per_tile):,}, "
        f"avg "
        f"{sum(building_counts_per_tile) / len(building_counts_per_tile):.1f}"
    )


if road_counts_per_tile:

    print(
        f"Roads/tile:     "
        f"min {min(road_counts_per_tile):,}, "
        f"max {max(road_counts_per_tile):,}, "
        f"avg "
        f"{sum(road_counts_per_tile) / len(road_counts_per_tile):.1f}"
    )


print("")
print("Manifest:")
print(
    MANIFEST_FILE
)

print("")
print("Tile index:")
print(
    INDEX_FILE
)

print("")
print("Stats:")
print(
    STATS_FILE
)

print("")
print("Tiles:")
print(
    TILES_DIR
)

print("============================================")
