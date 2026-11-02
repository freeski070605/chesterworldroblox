import csv
import json
import math
import os
from collections import Counter

from pyproj import Transformer
from shapely.geometry import shape, mapping
from shapely.ops import transform as shapely_transform
from shapely.strtree import STRtree


# ============================================================
# CHESTER REGIONAL ROAD NETWORK PREP
#
# County centerlines = authoritative base geometry for normal
# streets/roads.
#
# OSM = semantic enrichment + service roads + alleys +
# pedestrian/foot/cycle detail + any motor roads missing from
# the county layer.
#
# Output is generator-ready road centerline GeoJSON with
# normalized road classes and estimated physical widths.
# ============================================================


# ============================================================
# PATHS
# ============================================================

ROOT = r"E:\ChesterWorld"

COUNTY_ROADS_FILE = os.path.join(
    ROOT,
    "Data",
    "02_RegionalRoads",
    "delco_roads_202601_regional.geojson"
)

OSM_ROADS_FILE = os.path.join(
    ROOT,
    "Data",
    "03_RegionalOSM",
    "osm_transport_lines_regional.geojson"
)

OUTPUT_DIR = os.path.join(
    ROOT,
    "Data",
    "15_RegionalRoadGeneratorPrep"
)

OUTPUT_FILE = os.path.join(
    OUTPUT_DIR,
    "regional_generator_roads.geojson"
)

STATS_FILE = os.path.join(
    OUTPUT_DIR,
    "regional_generator_roads_stats.json"
)

REVIEW_FILE = os.path.join(
    OUTPUT_DIR,
    "regional_generator_roads_review.csv"
)

os.makedirs(
    OUTPUT_DIR,
    exist_ok=True
)


# ============================================================
# CONFIG
# ============================================================

PROJECTED_CRS = "EPSG:32618"

# County road and OSM road are considered the same corridor
# when their centerlines are within this distance.
OSM_MATCH_DISTANCE_M = 10.0

# OSM-only motor roads farther than this from a county road are
# retained as missing county geometry.
OSM_MOTOR_KEEP_DISTANCE_M = 10.0


# ============================================================
# LOADERS
# ============================================================

def load_geojson(path):

    with open(
        path,
        "r",
        encoding="utf-8"
    ) as f:

        data = json.load(f)

    return data.get(
        "features",
        []
    )


print("")
print("============================================")
print("CHESTER ROAD GENERATOR PREP")
print("============================================")
print("")

print("Loading county roads...")

county_features = load_geojson(
    COUNTY_ROADS_FILE
)

print(
    f"County segments: "
    f"{len(county_features):,}"
)

print("Loading OSM transport lines...")

osm_features = load_geojson(
    OSM_ROADS_FILE
)

print(
    f"OSM transport lines: "
    f"{len(osm_features):,}"
)


# ============================================================
# PROJECTION
# ============================================================

transformer = Transformer.from_crs(
    "EPSG:4326",
    PROJECTED_CRS,
    always_xy=True
)

project = transformer.transform


# ============================================================
# BASIC HELPERS
# ============================================================

def clean(value):

    if value is None:
        return ""

    text = str(value).strip()

    if text.lower() in {
        "",
        "none",
        "null",
        "nan"
    }:
        return ""

    return text


def to_float(value):

    try:

        if value is None or value == "":
            return None

        text = str(value).strip().lower()

        # OSM sometimes has "25 mph".
        text = (
            text
            .replace(
                "mph",
                ""
            )
            .replace(
                "km/h",
                ""
            )
            .strip()
        )

        return float(text)

    except Exception:

        return None


def to_int(value):

    number = to_float(
        value
    )

    if number is None:
        return None

    try:
        return int(
            round(
                number
            )
        )

    except Exception:
        return None


def properties_lower(properties):

    return {
        str(key).lower():
            value

        for key, value
        in (properties or {}).items()
    }


def get_any(properties, names):

    lower = properties_lower(
        properties
    )

    for name in names:

        value = lower.get(
            name.lower()
        )

        text = clean(
            value
        )

        if text:
            return value

    return None


# ============================================================
# ROAD CLASSIFICATION
# ============================================================

OSM_MOTOR_CLASSES = {
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
    "tertiary",
    "tertiary_link",
    "residential",
    "unclassified",
    "living_street",
    "service",
    "road",
}

OSM_NON_MOTOR_CLASSES = {
    "pedestrian",
    "footway",
    "path",
    "cycleway",
    "steps",
    "bridleway",
    "track",
    "corridor",
}


def normalize_osm_highway(value):

    return clean(
        value
    ).lower()


def classify_osm(properties):

    highway = normalize_osm_highway(
        properties.get(
            "highway"
        )
    )

    service = clean(
        properties.get(
            "service"
        )
    ).lower()


    if highway == "motorway":
        return "motorway"

    if highway == "motorway_link":
        return "motorway_link"

    if highway == "trunk":
        return "trunk"

    if highway == "trunk_link":
        return "trunk_link"

    if highway == "primary":
        return "primary"

    if highway == "primary_link":
        return "primary_link"

    if highway == "secondary":
        return "secondary"

    if highway == "secondary_link":
        return "secondary_link"

    if highway == "tertiary":
        return "tertiary"

    if highway == "tertiary_link":
        return "tertiary_link"

    if highway == "residential":
        return "residential"

    if highway == "living_street":
        return "living_street"

    if highway == "unclassified":
        return "local"

    if highway == "service":

        if service == "alley":
            return "alley"

        if service == "driveway":
            return "driveway"

        if service == "parking_aisle":
            return "parking_aisle"

        return "service"

    if highway == "pedestrian":
        return "pedestrian"

    if highway == "footway":
        return "footway"

    if highway == "path":
        return "path"

    if highway == "cycleway":
        return "cycleway"

    if highway == "steps":
        return "steps"

    if highway == "track":
        return "track"

    if highway:
        return highway

    return "unknown"


def classify_county(
    properties,
    matched_osm_class=""
):

    # If OSM gives us a strong recognized road hierarchy,
    # use that semantic classification while keeping county
    # geometry authoritative.
    if matched_osm_class in {
        "motorway",
        "motorway_link",
        "trunk",
        "trunk_link",
        "primary",
        "primary_link",
        "secondary",
        "secondary_link",
        "tertiary",
        "tertiary_link",
        "residential",
        "living_street",
        "local",
    }:

        return matched_osm_class


    road_class = clean(
        get_any(
            properties,
            [
                "RoadClass",
                "Road_Class",
                "ROADCLASS",
                "CLASS",
                "FunctionalClass",
                "FuncClass",
                "FC",
            ]
        )
    ).lower()


    street_name = clean(
        get_any(
            properties,
            [
                "St_Name",
                "StreetName",
                "STREET",
                "FULLNAME",
                "NAME",
            ]
        )
    ).lower()


    combined = (
        road_class
        +
        " "
        +
        street_name
    )


    # Text-based class values.
    if any(
        token in combined
        for token in [
            "interstate",
            "expressway",
            "freeway",
            "motorway",
        ]
    ):
        return "motorway"

    if "trunk" in combined:
        return "trunk"

    if any(
        token in combined
        for token in [
            "principal arterial",
            "major arterial",
            "primary",
        ]
    ):
        return "primary"

    if any(
        token in combined
        for token in [
            "minor arterial",
            "secondary",
        ]
    ):
        return "secondary"

    if any(
        token in combined
        for token in [
            "collector",
            "tertiary",
        ]
    ):
        return "tertiary"

    if any(
        token in combined
        for token in [
            "local",
            "residential",
            "street",
        ]
    ):
        return "residential"


    # Name heuristics for major corridors.
    if any(
        token in street_name
        for token in [
            "interstate",
            "i-95",
            "i 95",
        ]
    ):
        return "motorway"

    if any(
        token in street_name
        for token in [
            "route 13",
            "us 13",
            "route 320",
            "pa 320",
            "macdade",
        ]
    ):
        return "primary"


    # County centerline fallback.
    return "local"


# ============================================================
# WIDTH ESTIMATION
# ============================================================

BASE_WIDTHS = {
    "motorway":
        25.0,

    "motorway_link":
        9.0,

    "trunk":
        18.0,

    "trunk_link":
        8.0,

    "primary":
        14.0,

    "primary_link":
        8.0,

    "secondary":
        12.0,

    "secondary_link":
        7.5,

    "tertiary":
        10.0,

    "tertiary_link":
        7.0,

    "residential":
        7.5,

    "living_street":
        6.0,

    "local":
        7.0,

    "service":
        5.0,

    "alley":
        3.8,

    "driveway":
        3.5,

    "parking_aisle":
        3.5,

    "pedestrian":
        5.0,

    "footway":
        1.8,

    "path":
        1.5,

    "cycleway":
        2.2,

    "steps":
        2.0,

    "track":
        3.0,

    "unknown":
        6.0,
}


def estimate_width(
    road_class,
    lanes=None,
    osm_width=None
):

    explicit_width = to_float(
        osm_width
    )

    if (
        explicit_width is not None
        and
        1.0
        <=
        explicit_width
        <=
        80.0
    ):

        return (
            explicit_width,
            "osm_width"
        )


    base = BASE_WIDTHS.get(
        road_class,
        6.0
    )


    lane_count = to_int(
        lanes
    )


    if (
        lane_count is not None
        and
        1
        <=
        lane_count
        <=
        12
        and
        road_class
        not in {
            "footway",
            "path",
            "cycleway",
            "steps",
        }
    ):

        # Approximate drivable lane envelope plus margin.
        lane_width = (
            lane_count
            *
            3.2
        )

        width = max(
            base,
            lane_width
            +
            0.8
        )

        return (
            round(
                width,
                2
            ),
            "osm_lanes"
        )


    return (
        base,
        "class_default"
    )


# ============================================================
# PROJECT OSM + COUNTY GEOMETRIES
# ============================================================

def prepare_records(
    features,
    source_name
):

    records = []

    for index, feature in enumerate(
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


        records.append({
            "source":
                source_name,

            "source_index":
                index,

            "feature":
                feature,

            "properties":
                dict(
                    feature.get(
                        "properties",
                        {}
                    )
                ),

            "geometry_wgs":
                geometry_wgs,

            "geometry_m":
                geometry_m,
        })


    return records


county_records = prepare_records(
    county_features,
    "county"
)

osm_records = prepare_records(
    osm_features,
    "osm"
)


print("")
print(
    f"Valid county geometries: "
    f"{len(county_records):,}"
)

print(
    f"Valid OSM geometries: "
    f"{len(osm_records):,}"
)


# ============================================================
# OSM SPATIAL INDEX
# ============================================================

osm_geometries = [
    record[
        "geometry_m"
    ]
    for record in osm_records
]

osm_tree = STRtree(
    osm_geometries
)


def osm_query_indices(
    geometry
):

    raw = osm_tree.query(
        geometry
    )

    indices = []


    for item in raw:

        try:

            value = int(
                item
            )

            if (
                0
                <=
                value
                <
                len(osm_records)
            ):

                indices.append(
                    value
                )

                continue

        except Exception:
            pass


        # Shapely 1.x fallback.
        for idx, candidate in enumerate(
            osm_geometries
        ):

            if candidate is item:

                indices.append(
                    idx
                )

                break


    return indices


# ============================================================
# MATCH COUNTY -> OSM
# ============================================================

print("")
print("Matching county roads to OSM semantics...")


osm_matched_to_county = set()

county_output = []

county_match_count = 0

county_unmatched_count = 0


for county_index, record in enumerate(
    county_records
):

    county_geom = record[
        "geometry_m"
    ]


    candidates = osm_query_indices(
        county_geom.buffer(
            OSM_MATCH_DISTANCE_M
        )
    )


    best = None


    for osm_index in candidates:

        osm_record = osm_records[
            osm_index
        ]

        osm_props = osm_record[
            "properties"
        ]

        highway = normalize_osm_highway(
            osm_props.get(
                "highway"
            )
        )


        if highway not in OSM_MOTOR_CLASSES:
            continue


        try:

            distance = county_geom.distance(
                osm_record[
                    "geometry_m"
                ]
            )

        except Exception:
            continue


        if distance > OSM_MATCH_DISTANCE_M:
            continue


        # Name agreement helps when available.
        county_name = clean(
            get_any(
                record[
                    "properties"
                ],
                [
                    "St_Name",
                    "StreetName",
                    "NAME",
                    "FULLNAME",
                ]
            )
        ).lower()


        osm_name = clean(
            osm_props.get(
                "name"
            )
        ).lower()


        name_bonus = 0.0


        if (
            county_name
            and
            osm_name
        ):

            if (
                county_name
                in
                osm_name
                or
                osm_name
                in
                county_name
            ):

                name_bonus = 4.0


        score = (
            distance
            -
            name_bonus
        )


        if (
            best is None
            or
            score
            <
            best[
                "score"
            ]
        ):

            best = {
                "osm_index":
                    osm_index,

                "distance":
                    distance,

                "score":
                    score,
            }


    county_props = dict(
        record[
            "properties"
        ]
    )


    matched_osm_props = {}
    matched_osm_class = ""
    match_distance = None


    if best is not None:

        osm_index = best[
            "osm_index"
        ]

        osm_record = osm_records[
            osm_index
        ]

        matched_osm_props = dict(
            osm_record[
                "properties"
            ]
        )

        matched_osm_class = classify_osm(
            matched_osm_props
        )

        match_distance = best[
            "distance"
        ]

        osm_matched_to_county.add(
            osm_index
        )

        county_match_count += 1


    else:

        county_unmatched_count += 1


    road_class = classify_county(
        county_props,
        matched_osm_class
    )


    lanes = (
        matched_osm_props.get(
            "lanes"
        )
        or
        get_any(
            county_props,
            [
                "Lanes",
                "LANES",
            ]
        )
    )


    osm_width = matched_osm_props.get(
        "width"
    )


    width_m, width_source = estimate_width(
        road_class,
        lanes,
        osm_width
    )


    road_name = (
        clean(
            get_any(
                county_props,
                [
                    "St_Name",
                    "StreetName",
                    "NAME",
                    "FULLNAME",
                ]
            )
        )
        or
        clean(
            matched_osm_props.get(
                "name"
            )
        )
    )


    one_way = (
        clean(
            matched_osm_props.get(
                "oneway"
            )
        )
        or
        clean(
            get_any(
                county_props,
                [
                    "OneWay",
                    "ONEWAY",
                    "ONE_WAY",
                ]
            )
        )
    )


    speed_limit = (
        clean(
            matched_osm_props.get(
                "maxspeed"
            )
        )
        or
        clean(
            get_any(
                county_props,
                [
                    "SpeedLimit",
                    "SPEEDLIMIT",
                    "SPEED",
                ]
            )
        )
    )


    properties = dict(
        county_props
    )


    properties.update({
        "generator_source":
            "county",

        "generator_source_priority":
            1,

        "generator_road_class":
            road_class,

        "generator_width_m":
            round(
                width_m,
                2
            ),

        "generator_width_source":
            width_source,

        "generator_name":
            road_name,

        "generator_lanes":
            clean(
                lanes
            ),

        "generator_oneway":
            one_way,

        "generator_speed_limit":
            speed_limit,

        "osm_matched":
            bool(
                best
            ),

        "osm_match_distance_m":
            (
                round(
                    match_distance,
                    2
                )
                if match_distance
                is not None
                else None
            ),

        "osm_highway":
            clean(
                matched_osm_props.get(
                    "highway"
                )
            ),

        "osm_service":
            clean(
                matched_osm_props.get(
                    "service"
                )
            ),

        "osm_surface":
            clean(
                matched_osm_props.get(
                    "surface"
                )
            ),

        "osm_bridge":
            clean(
                matched_osm_props.get(
                    "bridge"
                )
            ),

        "osm_tunnel":
            clean(
                matched_osm_props.get(
                    "tunnel"
                )
            ),

        "osm_sidewalk":
            clean(
                matched_osm_props.get(
                    "sidewalk"
                )
            ),

        "osm_cycleway":
            clean(
                matched_osm_props.get(
                    "cycleway"
                )
            ),
    })


    county_output.append({
        "type":
            "Feature",

        "properties":
            properties,

        "geometry":
            record[
                "feature"
            ].get(
                "geometry"
            )
    })


print(
    f"County segments with OSM match: "
    f"{county_match_count:,}"
)

print(
    f"County segments without OSM match: "
    f"{county_unmatched_count:,}"
)


# ============================================================
# COUNTY SPATIAL INDEX FOR OSM-ONLY CHECK
# ============================================================

county_geometries = [
    record[
        "geometry_m"
    ]
    for record in county_records
]

county_tree = STRtree(
    county_geometries
)


def county_query_indices(
    geometry
):

    raw = county_tree.query(
        geometry
    )

    indices = []


    for item in raw:

        try:

            value = int(
                item
            )

            if (
                0
                <=
                value
                <
                len(county_records)
            ):

                indices.append(
                    value
                )

                continue

        except Exception:
            pass


        for idx, candidate in enumerate(
            county_geometries
        ):

            if candidate is item:

                indices.append(
                    idx
                )

                break


    return indices


# ============================================================
# KEEP OSM-ONLY DETAIL
# ============================================================

print("")
print("Adding OSM-only roads/paths/service detail...")


osm_output = []

osm_detail_count = 0
osm_motor_missing_count = 0
osm_motor_duplicate_skipped = 0


for osm_index, record in enumerate(
    osm_records
):

    properties = dict(
        record[
            "properties"
        ]
    )


    highway = normalize_osm_highway(
        properties.get(
            "highway"
        )
    )


    if not highway:
        continue


    road_class = classify_osm(
        properties
    )


    is_motor = (
        highway
        in
        OSM_MOTOR_CLASSES
    )


    is_non_motor = (
        highway
        in
        OSM_NON_MOTOR_CLASSES
        or
        road_class
        in {
            "pedestrian",
            "footway",
            "path",
            "cycleway",
            "steps",
            "track",
        }
    )


    keep = False
    source_priority = 3


    if is_non_motor:

        # Always retain pedestrian/cycle/track detail.
        keep = True
        source_priority = 3
        osm_detail_count += 1


    elif is_motor:

        # If already directly matched to county, skip.
        if osm_index in osm_matched_to_county:

            osm_motor_duplicate_skipped += 1
            continue


        # Otherwise test actual proximity to ANY county road.
        nearby_county = county_query_indices(
            record[
                "geometry_m"
            ].buffer(
                OSM_MOTOR_KEEP_DISTANCE_M
            )
        )


        min_distance = None


        for county_index in nearby_county:

            try:

                distance = (
                    record[
                        "geometry_m"
                    ]
                    .distance(
                        county_records[
                            county_index
                        ][
                            "geometry_m"
                        ]
                    )
                )

            except Exception:
                continue


            if (
                min_distance is None
                or
                distance
                <
                min_distance
            ):

                min_distance = distance


        if (
            min_distance is None
            or
            min_distance
            >
            OSM_MOTOR_KEEP_DISTANCE_M
        ):

            keep = True
            source_priority = 2
            osm_motor_missing_count += 1


        else:

            osm_motor_duplicate_skipped += 1


    else:

        # Unknown highway value: preserve it as low-priority
        # detail rather than silently throwing it away.
        keep = True
        source_priority = 4
        osm_detail_count += 1


    if not keep:
        continue


    width_m, width_source = estimate_width(
        road_class,
        properties.get(
            "lanes"
        ),
        properties.get(
            "width"
        )
    )


    output_properties = dict(
        properties
    )


    output_properties.update({
        "generator_source":
            "osm",

        "generator_source_priority":
            source_priority,

        "generator_road_class":
            road_class,

        "generator_width_m":
            round(
                width_m,
                2
            ),

        "generator_width_source":
            width_source,

        "generator_name":
            clean(
                properties.get(
                    "name"
                )
            ),

        "generator_lanes":
            clean(
                properties.get(
                    "lanes"
                )
            ),

        "generator_oneway":
            clean(
                properties.get(
                    "oneway"
                )
            ),

        "generator_speed_limit":
            clean(
                properties.get(
                    "maxspeed"
                )
            ),

        "osm_highway":
            highway,

        "osm_service":
            clean(
                properties.get(
                    "service"
                )
            ),

        "osm_surface":
            clean(
                properties.get(
                    "surface"
                )
            ),

        "osm_bridge":
            clean(
                properties.get(
                    "bridge"
                )
            ),

        "osm_tunnel":
            clean(
                properties.get(
                    "tunnel"
                )
            ),

        "osm_sidewalk":
            clean(
                properties.get(
                    "sidewalk"
                )
            ),

        "osm_cycleway":
            clean(
                properties.get(
                    "cycleway"
                )
            ),
    })


    osm_output.append({
        "type":
            "Feature",

        "properties":
            output_properties,

        "geometry":
            record[
                "feature"
            ].get(
                "geometry"
            )
    })


print(
    f"OSM detail segments retained: "
    f"{osm_detail_count:,}"
)

print(
    f"OSM motor roads missing from county: "
    f"{osm_motor_missing_count:,}"
)

print(
    f"OSM motor duplicates skipped: "
    f"{osm_motor_duplicate_skipped:,}"
)


# ============================================================
# COMBINED OUTPUT
# ============================================================

all_output = (
    county_output
    +
    osm_output
)


# ============================================================
# STATS
# ============================================================

class_counts = Counter()

source_counts = Counter()

width_source_counts = Counter()

surface_counts = Counter()


for feature in all_output:

    properties = feature[
        "properties"
    ]


    class_counts[
        properties.get(
            "generator_road_class",
            "unknown"
        )
    ] += 1


    source_counts[
        properties.get(
            "generator_source",
            "unknown"
        )
    ] += 1


    width_source_counts[
        properties.get(
            "generator_width_source",
            "unknown"
        )
    ] += 1


    surface = clean(
        properties.get(
            "osm_surface"
        )
    )


    if surface:

        surface_counts[
            surface
        ] += 1


# ============================================================
# REVIEW QUEUE
# ============================================================

review_rows = []


for feature in all_output:

    properties = feature[
        "properties"
    ]


    road_class = clean(
        properties.get(
            "generator_road_class"
        )
    )


    needs_review = (
        road_class
        in {
            "",
            "unknown",
            "road",
        }
        or
        (
            properties.get(
                "generator_source"
            )
            ==
            "county"
            and
            not properties.get(
                "osm_matched"
            )
        )
    )


    if not needs_review:
        continue


    review_rows.append({
        "source":
            properties.get(
                "generator_source",
                ""
            ),

        "name":
            properties.get(
                "generator_name",
                ""
            ),

        "road_class":
            road_class,

        "width_m":
            properties.get(
                "generator_width_m",
                ""
            ),

        "width_source":
            properties.get(
                "generator_width_source",
                ""
            ),

        "osm_highway":
            properties.get(
                "osm_highway",
                ""
            ),

        "osm_service":
            properties.get(
                "osm_service",
                ""
            ),

        "osm_matched":
            properties.get(
                "osm_matched",
                ""
            ),

        "osm_match_distance_m":
            properties.get(
                "osm_match_distance_m",
                ""
            ),
    })


# ============================================================
# SAVE GEOJSON
# ============================================================

output = {
    "type":
        "FeatureCollection",

    "name":
        "ChesterWorld_Generator_Roads",

    "crs": {
        "type":
            "name",

        "properties": {
            "name":
                "EPSG:4326"
        }
    },

    "features":
        all_output
}


with open(
    OUTPUT_FILE,
    "w",
    encoding="utf-8"
) as f:

    json.dump(
        output,
        f,
        ensure_ascii=False,
        separators=(",", ":")
    )


# ============================================================
# SAVE STATS
# ============================================================

stats = {
    "county_input_segments":
        len(
            county_records
        ),

    "osm_input_segments":
        len(
            osm_records
        ),

    "county_osm_matches":
        county_match_count,

    "county_unmatched":
        county_unmatched_count,

    "osm_detail_retained":
        osm_detail_count,

    "osm_motor_missing_from_county":
        osm_motor_missing_count,

    "osm_motor_duplicates_skipped":
        osm_motor_duplicate_skipped,

    "generator_segments":
        len(
            all_output
        ),

    "source_counts":
        dict(
            source_counts
        ),

    "road_class_counts":
        dict(
            class_counts
        ),

    "width_source_counts":
        dict(
            width_source_counts
        ),

    "surface_counts":
        dict(
            surface_counts
        ),

    "review_queue":
        len(
            review_rows
        ),

    "notes": [
        "County road geometry is authoritative for normal roads.",
        "OSM provides road hierarchy/tags where matched.",
        "OSM pedestrian/service detail is preserved.",
        "OSM motor roads are kept only when they appear to be missing from the county geometry.",
        "generator_width_m is an estimated procedural mesh width, not surveyed curb-to-curb width.",
    ],
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
# SAVE REVIEW CSV
# ============================================================

review_fields = [
    "source",
    "name",
    "road_class",
    "width_m",
    "width_source",
    "osm_highway",
    "osm_service",
    "osm_matched",
    "osm_match_distance_m",
]


with open(
    REVIEW_FILE,
    "w",
    encoding="utf-8",
    newline=""
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=review_fields
    )

    writer.writeheader()

    writer.writerows(
        review_rows
    )


# ============================================================
# SUMMARY
# ============================================================

geojson_size_mb = (
    os.path.getsize(
        OUTPUT_FILE
    )
    /
    (
        1024
        *
        1024
    )
)


print("")
print("")
print("============================================")
print("DONE")
print("============================================")

print(
    f"Generator road segments: "
    f"{len(all_output):,}"
)

print(
    f"County/OSM matches:      "
    f"{county_match_count:,}"
)

print(
    f"OSM-only motor roads:    "
    f"{osm_motor_missing_count:,}"
)

print(
    f"OSM detail segments:     "
    f"{osm_detail_count:,}"
)

print(
    f"Review queue:            "
    f"{len(review_rows):,}"
)


print("")
print("Road classes:")


for road_class, count in (
    class_counts
    .most_common()
):

    print(
        f"  {road_class}: "
        f"{count:,}"
    )


print("")
print("Sources:")


for source, count in (
    source_counts
    .most_common()
):

    print(
        f"  {source}: "
        f"{count:,}"
    )


print("")
print("Width sources:")


for source, count in (
    width_source_counts
    .most_common()
):

    print(
        f"  {source}: "
        f"{count:,}"
    )


print("")
print(
    f"Generator GeoJSON size: "
    f"{geojson_size_mb:.2f} MB"
)


print("")
print("Generator roads:")
print(
    OUTPUT_FILE
)

print("")
print("Stats:")
print(
    STATS_FILE
)

print("")
print("Review CSV:")
print(
    REVIEW_FILE
)

print("============================================")
