import csv
import json
import math
import os
from collections import Counter, defaultdict, deque

from pyproj import Transformer
from shapely.geometry import shape
from shapely.ops import transform as shapely_transform
from shapely.strtree import STRtree


# ============================================================
# CHESTER REGIONAL BUILDING ARCHETYPE CLASSIFIER V2
#
# Goal:
# - Preserve the enriched master building database.
# - Fix the original rowhouse/twin under-detection.
# - Infer procedural archetypes using footprint geometry,
#   height, semantics, and neighborhood relationships.
#
# IMPORTANT:
# These are GENERATOR HINTS, not verified architectural facts.
# ============================================================


# ============================================================
# PATHS
# ============================================================

ROOT = r"E:\ChesterWorld"

INPUT_FILE = os.path.join(
    ROOT,
    "Data",
    "13_RegionalMaster",
    "regional_buildings_base.geojson"
)

OUTPUT_DIR = os.path.join(
    ROOT,
    "Data",
    "14_RegionalGeneratorPrep_v2"
)

OUTPUT_GEOJSON = os.path.join(
    OUTPUT_DIR,
    "regional_generator_buildings_v2.geojson"
)

OUTPUT_STATS = os.path.join(
    OUTPUT_DIR,
    "regional_generator_buildings_v2_stats.json"
)

OUTPUT_REVIEW = os.path.join(
    OUTPUT_DIR,
    "regional_generator_buildings_v2_review.csv"
)

OUTPUT_CLUSTERS = os.path.join(
    OUTPUT_DIR,
    "regional_residential_clusters_v2.csv"
)

os.makedirs(
    OUTPUT_DIR,
    exist_ok=True
)


# ============================================================
# CONFIG
# ============================================================

PROJECTED_CRS = "EPSG:32618"

# Search radius for neighboring residential footprints.
NEIGHBOR_SEARCH_M = 4.0

# Strong attached/rowhouse relationship.
ROW_MAX_GAP_M = 2.75

# Twin/semi-detached can tolerate slightly more separation.
TWIN_MAX_GAP_M = 3.25

# Footprint shape limits.
ROW_MAX_WIDTH_M = 15.5
ROW_MIN_DEPTH_M = 6.0
ROW_MAX_DEPTH_M = 32.0
ROW_MAX_AREA_M2 = 360.0

TWIN_MAX_WIDTH_M = 19.0
TWIN_MAX_AREA_M2 = 480.0

# Geometry similarity.
MAX_ORIENTATION_DIFF_DEG = 24.0
MAX_SIDE_ALIGNMENT_ERROR_DEG = 38.0

MIN_AREA_RATIO = 0.38
MAX_AREA_RATIO = 2.65

MIN_DEPTH_RATIO = 0.52
MAX_DEPTH_RATIO = 1.92

# Height mismatch allowed for likely attached housing.
MAX_HEIGHT_DIFF_M = 9.0

# Multifamily fallback.
SMALL_MULTI_AREA_M2 = 325.0
APARTMENT_AREA_M2 = 650.0


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

        return float(value)

    except Exception:
        return None


def normalize_angle_180(angle):
    angle = angle % 180.0

    if angle < 0:
        angle += 180.0

    return angle


def angle_difference_180(a, b):
    diff = abs(
        normalize_angle_180(a)
        -
        normalize_angle_180(b)
    )

    return min(
        diff,
        180.0 - diff
    )


def angle_difference_90(a, b):
    """
    Difference where 0 and 180 are equivalent and
    perpendicular relation is measured against 90 degrees.
    """

    diff = angle_difference_180(
        a,
        b
    )

    return abs(
        90.0 - diff
    )


# ============================================================
# LOAD MASTER BUILDINGS
# ============================================================

print("")
print("============================================")
print("CHESTER ARCHETYPE CLASSIFIER V2")
print("============================================")
print("")

print("Loading master buildings...")


with open(
    INPUT_FILE,
    "r",
    encoding="utf-8"
) as f:

    data = json.load(f)


features = data.get(
    "features",
    []
)


if not features:

    raise RuntimeError(
        "No buildings found in master file."
    )


print(
    f"Master buildings: "
    f"{len(features):,}"
)


# ============================================================
# PROJECT TO METERS
# ============================================================

transformer = Transformer.from_crs(
    "EPSG:4326",
    PROJECTED_CRS,
    always_xy=True
)

project = transformer.transform


records = []


# ============================================================
# SEMANTIC BUILDING USE
# ============================================================

def derive_generator_use(properties):

    original_use = clean(
        properties.get(
            "building_use"
        )
    ).lower()

    original_source = clean(
        properties.get(
            "building_use_source"
        )
    ).lower()

    zoning = clean(
        properties.get(
            "zoning_category"
        )
    ).lower()

    landuse = clean(
        properties.get(
            "landuse_primary"
        )
    ).lower()

    poi_class = clean(
        properties.get(
            "poi_class"
        )
    ).lower()

    poi_type = clean(
        properties.get(
            "poi_type"
        )
    ).lower()

    school_name = clean(
        properties.get(
            "official_school_name"
        )
    )


    if school_name:

        return (
            "education",
            "official_school",
            "high"
        )


    # Preserve semantic POI / official classifications first.
    strong_uses = {
        "education",
        "commercial",
        "industrial",
        "residential",
        "religious",
        "civic",
        "institutional",
        "office",
        "healthcare",
        "hospital",
        "lodging",
        "recreation",
        "retail",
    }


    if (
        original_use in strong_uses
        and
        original_source in {
            "official_school",
            "osm_poi",
            "osm_site",
            "osm_landuse",
        }
    ):

        confidence = (
            "high"
            if original_source
            in {
                "official_school",
                "osm_poi"
            }
            else
            "medium"
        )

        return (
            original_use,
            original_source,
            confidence
        )


    # Physical land use before zoning.
    if landuse in {
        "residential",
        "commercial",
        "industrial",
        "institutional",
    }:

        return (
            landuse,
            "osm_landuse",
            "medium"
        )


    # Zoning context.
    if zoning in {
        "residential",
        "commercial",
        "industrial",
        "institutional",
        "office",
    }:

        return (
            zoning,
            "zoning_context",
            "low"
        )


    # These are context, not physical building types.
    if zoning in {
        "waterfront",
        "open_space",
        "mixed_use",
    }:

        return (
            "unknown",
            "zoning_context_only",
            "low"
        )


    if original_use in strong_uses:

        return (
            original_use,
            "master_building_use",
            "low"
        )


    return (
        "unknown",
        "none",
        "unknown"
    )


# ============================================================
# FOOTPRINT METRICS
# ============================================================

def rectangle_metrics(geometry):

    try:

        rectangle = (
            geometry
            .minimum_rotated_rectangle
        )

        coords = list(
            rectangle.exterior.coords
        )


        edges = []


        for i in range(4):

            x1, y1 = coords[i]
            x2, y2 = coords[i + 1]

            dx = x2 - x1
            dy = y2 - y1

            length = math.hypot(
                dx,
                dy
            )

            if length < 0.01:
                continue

            angle = normalize_angle_180(
                math.degrees(
                    math.atan2(
                        dy,
                        dx
                    )
                )
            )

            edges.append(
                (
                    length,
                    angle
                )
            )


        if len(edges) < 2:

            return (
                None,
                None,
                None
            )


        edges.sort(
            key=lambda item:
                item[0]
        )


        width = (
            edges[0][0]
            +
            edges[1][0]
        ) / 2.0


        depth = (
            edges[-1][0]
            +
            edges[-2][0]
        ) / 2.0


        long_angle = (
            edges[-1][1]
        )


        return (
            float(width),
            float(depth),
            float(long_angle)
        )


    except Exception:

        return (
            None,
            None,
            None
        )


def estimate_floors(
    properties,
    height_m
):

    explicit_fields = [
        "stories",
        "story_count",
        "buildingstories",
        "building_stories",
        "numberofstories",
        "numstories",
        "floors",
    ]


    lower = {
        str(k).lower():
            v

        for k, v
        in properties.items()
    }


    for field in explicit_fields:

        value = to_float(
            lower.get(
                field
            )
        )


        if (
            value is not None
            and
            1
            <=
            value
            <=
            100
        ):

            return (
                int(
                    round(
                        value
                    )
                ),
                "county_story_field"
            )


    if (
        height_m is not None
        and
        height_m > 2.0
    ):

        floors = int(
            round(
                height_m / 3.05
            )
        )

        floors = max(
            1,
            min(
                floors,
                60
            )
        )


        return (
            floors,
            "height_estimate"
        )


    return (
        None,
        "unknown"
    )


# ============================================================
# BUILD RECORDS
# ============================================================

print("")
print("Calculating building metrics...")


for index, feature in enumerate(
    features
):

    geometry_json = feature.get(
        "geometry"
    )


    if not geometry_json:
        continue


    try:

        wgs_geometry = shape(
            geometry_json
        )


        if wgs_geometry.is_empty:
            continue


        geometry = shapely_transform(
            project,
            wgs_geometry
        )


    except Exception:
        continue


    properties = dict(
        feature.get(
            "properties",
            {}
        )
    )


    area_m2 = float(
        geometry.area
    )

    perimeter_m = float(
        geometry.length
    )


    width_m, depth_m, orientation_deg = (
        rectangle_metrics(
            geometry
        )
    )


    height_m = to_float(
        properties.get(
            "height_m"
        )
    )


    if height_m is None:

        height_ft = to_float(
            properties.get(
                "height_ft"
            )
        )


        if height_ft is not None:

            height_m = (
                height_ft
                *
                0.3048
            )


    floors, floors_source = (
        estimate_floors(
            properties,
            height_m
        )
    )


    generator_use, use_source, use_confidence = (
        derive_generator_use(
            properties
        )
    )


    centroid = geometry.centroid


    records.append({
        "original_index":
            index,

        "feature":
            feature,

        "properties":
            properties,

        "geometry":
            geometry,

        "centroid":
            centroid,

        "area_m2":
            area_m2,

        "perimeter_m":
            perimeter_m,

        "width_m":
            width_m,

        "depth_m":
            depth_m,

        "orientation_deg":
            orientation_deg,

        "height_m":
            height_m,

        "estimated_floors":
            floors,

        "estimated_floors_source":
            floors_source,

        "generator_use":
            generator_use,

        "generator_use_source":
            use_source,

        "generator_use_confidence":
            use_confidence,
    })


print(
    f"Valid building records: "
    f"{len(records):,}"
)


# ============================================================
# SPATIAL INDEX
# ============================================================

geometries = [
    record[
        "geometry"
    ]
    for record in records
]


tree = STRtree(
    geometries
)


def query_indices(
    geometry
):

    raw = tree.query(
        geometry
    )

    result = []


    for item in raw:

        # Shapely 2.x returns integer indices.
        try:

            value = int(
                item
            )

            if (
                0
                <=
                value
                <
                len(records)
            ):

                result.append(
                    value
                )

                continue

        except Exception:
            pass


        # Shapely 1.x fallback.
        for idx, candidate in enumerate(
            geometries
        ):

            if candidate is item:

                result.append(
                    idx
                )

                break


    return result


# ============================================================
# ROWHOUSE CANDIDATE SHAPE
# ============================================================

def row_shape_candidate(record):

    if (
        record[
            "generator_use"
        ]
        !=
        "residential"
    ):

        return False


    area = record[
        "area_m2"
    ]

    width = record[
        "width_m"
    ]

    depth = record[
        "depth_m"
    ]


    if (
        width is None
        or
        depth is None
    ):

        return False


    if area > ROW_MAX_AREA_M2:

        return False


    if width > ROW_MAX_WIDTH_M:

        return False


    if not (
        ROW_MIN_DEPTH_M
        <=
        depth
        <=
        ROW_MAX_DEPTH_M
    ):

        return False


    return True


# ============================================================
# PAIR RELATIONSHIP SCORE
# ============================================================

def pair_relationship(
    a,
    b
):

    if (
        a[
            "generator_use"
        ]
        !=
        "residential"
        or
        b[
            "generator_use"
        ]
        !=
        "residential"
    ):

        return None


    area_a = a[
        "area_m2"
    ]

    area_b = b[
        "area_m2"
    ]


    if (
        area_a <= 0
        or
        area_b <= 0
    ):

        return None


    area_ratio = (
        area_a
        /
        area_b
    )


    if not (
        MIN_AREA_RATIO
        <=
        area_ratio
        <=
        MAX_AREA_RATIO
    ):

        return None


    width_a = a[
        "width_m"
    ]

    width_b = b[
        "width_m"
    ]

    depth_a = a[
        "depth_m"
    ]

    depth_b = b[
        "depth_m"
    ]

    orientation_a = a[
        "orientation_deg"
    ]

    orientation_b = b[
        "orientation_deg"
    ]


    if (
        width_a is None
        or
        width_b is None
        or
        depth_a is None
        or
        depth_b is None
        or
        orientation_a is None
        or
        orientation_b is None
    ):

        return None


    depth_ratio = (
        depth_a
        /
        depth_b
    )


    if not (
        MIN_DEPTH_RATIO
        <=
        depth_ratio
        <=
        MAX_DEPTH_RATIO
    ):

        return None


    orientation_diff = (
        angle_difference_180(
            orientation_a,
            orientation_b
        )
    )


    if (
        orientation_diff
        >
        MAX_ORIENTATION_DIFF_DEG
    ):

        return None


    height_a = a[
        "height_m"
    ]

    height_b = b[
        "height_m"
    ]


    if (
        height_a is not None
        and
        height_b is not None
        and
        abs(
            height_a
            -
            height_b
        )
        >
        MAX_HEIGHT_DIFF_M
    ):

        return None


    try:

        gap = a[
            "geometry"
        ].distance(
            b[
                "geometry"
            ]
        )

    except Exception:

        return None


    if gap > TWIN_MAX_GAP_M:

        return None


    # --------------------------------------------------------
    # CENTROID ALIGNMENT
    #
    # Rowhouses/twins should generally sit SIDE-BY-SIDE.
    # Their centroid connection should therefore be roughly
    # perpendicular to the long/depth axis.
    # --------------------------------------------------------

    ax = a[
        "centroid"
    ].x

    ay = a[
        "centroid"
    ].y

    bx = b[
        "centroid"
    ].x

    by = b[
        "centroid"
    ].y


    centroid_angle = normalize_angle_180(
        math.degrees(
            math.atan2(
                by - ay,
                bx - ax
            )
        )
    )


    side_error = angle_difference_90(
        orientation_a,
        centroid_angle
    )


    if (
        side_error
        >
        MAX_SIDE_ALIGNMENT_ERROR_DEG
    ):

        return None


    # --------------------------------------------------------
    # RELATION QUALITY
    # --------------------------------------------------------

    row_like = (
        gap
        <=
        ROW_MAX_GAP_M
        and
        row_shape_candidate(
            a
        )
        and
        row_shape_candidate(
            b
        )
    )


    if row_like:

        relationship = (
            "row_neighbor"
        )

    else:

        relationship = (
            "twin_neighbor"
        )


    # Score for diagnostics / later confidence.
    gap_score = max(
        0.0,
        1.0
        -
        (
            gap
            /
            TWIN_MAX_GAP_M
        )
    )


    orientation_score = max(
        0.0,
        1.0
        -
        (
            orientation_diff
            /
            MAX_ORIENTATION_DIFF_DEG
        )
    )


    alignment_score = max(
        0.0,
        1.0
        -
        (
            side_error
            /
            MAX_SIDE_ALIGNMENT_ERROR_DEG
        )
    )


    score = (
        gap_score
        *
        0.45
        +
        orientation_score
        *
        0.25
        +
        alignment_score
        *
        0.30
    )


    return {
        "relationship":
            relationship,

        "gap_m":
            gap,

        "orientation_diff":
            orientation_diff,

        "side_alignment_error":
            side_error,

        "score":
            score,
    }


# ============================================================
# BUILD RESIDENTIAL NEIGHBOR GRAPH
# ============================================================

print("")
print("Detecting attached residential relationships...")


row_adjacency = defaultdict(
    set
)

twin_adjacency = defaultdict(
    set
)

pair_data = {}


residential_indices = [
    index
    for index, record in enumerate(
        records
    )
    if record[
        "generator_use"
    ]
    ==
    "residential"
]


pair_count = 0
row_pair_count = 0
twin_pair_count = 0


for i in residential_indices:

    a = records[i]


    nearby = query_indices(
        a[
            "geometry"
        ].buffer(
            NEIGHBOR_SEARCH_M
        )
    )


    for j in nearby:

        if j <= i:
            continue


        b = records[j]


        relation = pair_relationship(
            a,
            b
        )


        if relation is None:
            continue


        pair_count += 1


        pair_data[
            (
                i,
                j
            )
        ] = relation


        if (
            relation[
                "relationship"
            ]
            ==
            "row_neighbor"
        ):

            row_adjacency[i].add(
                j
            )

            row_adjacency[j].add(
                i
            )

            row_pair_count += 1


        else:

            twin_adjacency[i].add(
                j
            )

            twin_adjacency[j].add(
                i
            )

            twin_pair_count += 1


print(
    f"Residential pair relationships: "
    f"{pair_count:,}"
)

print(
    f"  row-neighbor pairs: "
    f"{row_pair_count:,}"
)

print(
    f"  twin-neighbor pairs: "
    f"{twin_pair_count:,}"
)


# ============================================================
# ROWHOUSE CONNECTED COMPONENTS
# ============================================================

row_cluster_id = {}
row_cluster_size = {}
row_cluster_members = {}

visited = set()
row_cluster_counter = 0


row_candidate_nodes = set(
    row_adjacency.keys()
)


for start in sorted(
    row_candidate_nodes
):

    if start in visited:
        continue


    queue = deque([
        start
    ])

    visited.add(
        start
    )

    component = []


    while queue:

        current = queue.popleft()

        component.append(
            current
        )


        for neighbor in (
            row_adjacency.get(
                current,
                set()
            )
        ):

            if neighbor in visited:
                continue

            visited.add(
                neighbor
            )

            queue.append(
                neighbor
            )


    # A true rowhouse cluster needs at least 3 buildings.
    if len(component) < 3:

        continue


    row_cluster_counter += 1


    cluster_name = (
        f"ROW_CLUSTER_"
        f"{row_cluster_counter:05d}"
    )


    row_cluster_members[
        cluster_name
    ] = component


    for index in component:

        row_cluster_id[
            index
        ] = cluster_name

        row_cluster_size[
            index
        ] = len(
            component
        )


print(
    f"Rowhouse clusters (3+): "
    f"{row_cluster_counter:,}"
)


# ============================================================
# TWIN PAIRS
#
# Only use twin relationship if building isn't already in a
# 3+ rowhouse cluster.
# ============================================================

twin_partner = {}


for i in residential_indices:

    if i in row_cluster_id:
        continue


    candidates = []


    neighbors = (
        row_adjacency.get(
            i,
            set()
        )
        |
        twin_adjacency.get(
            i,
            set()
        )
    )


    for j in neighbors:

        if j in row_cluster_id:
            continue


        key = (
            min(
                i,
                j
            ),
            max(
                i,
                j
            )
        )


        relation = pair_data.get(
            key
        )


        if relation is None:
            continue


        candidates.append(
            (
                relation[
                    "score"
                ],
                relation[
                    "gap_m"
                ],
                j
            )
        )


    if not candidates:
        continue


    candidates.sort(
        reverse=True
    )


    best = candidates[0]


    twin_partner[
        i
    ] = best[2]


# Keep only mutual pairings.
mutual_twins = {}


for i, j in twin_partner.items():

    if (
        twin_partner.get(
            j
        )
        ==
        i
    ):

        mutual_twins[
            i
        ] = j


print(
    f"Mutual twin buildings: "
    f"{len(mutual_twins):,}"
)


# ============================================================
# ARCHETYPE CLASSIFICATION
# ============================================================

def classify_archetype(
    index,
    record
):

    use = record[
        "generator_use"
    ]

    area = record[
        "area_m2"
    ]

    floors = record[
        "estimated_floors"
    ]


    # --------------------------------------------------------
    # RESIDENTIAL
    # --------------------------------------------------------

    if use == "residential":

        if index in row_cluster_id:

            degree = len(
                row_adjacency.get(
                    index,
                    set()
                )
            )


            if degree >= 2:

                return (
                    "rowhouse_middle",
                    "high",
                    "v2_row_cluster"
                )


            return (
                "rowhouse_end",
                "high",
                "v2_row_cluster"
            )


        if index in mutual_twins:

            return (
                "twin_semi_detached",
                "high",
                "v2_mutual_pair"
            )


        # A 2-building row-like relationship that did not
        # resolve into a mutual twin remains likely attached,
        # but not confidently enough for "rowhouse".
        row_neighbors = (
            row_adjacency.get(
                index,
                set()
            )
        )


        if row_neighbors:

            return (
                "attached_residential_pair_or_short_row",
                "medium",
                "v2_short_attachment"
            )


        if (
            floors is not None
            and
            floors >= 4
        ):

            return (
                "apartment_multifamily",
                "medium",
                "height_inference"
            )


        if area >= APARTMENT_AREA_M2:

            return (
                "apartment_multifamily",
                "medium",
                "large_footprint"
            )


        if area >= SMALL_MULTI_AREA_M2:

            return (
                "small_multifamily",
                "medium",
                "footprint_size"
            )


        return (
            "detached_house",
            "medium",
            "isolated_residential"
        )


    # --------------------------------------------------------
    # COMMERCIAL
    # --------------------------------------------------------

    if use in {
        "commercial",
        "retail",
    }:

        if area <= 325:

            return (
                "small_commercial_storefront",
                "medium",
                "use_plus_footprint"
            )


        if (
            floors is not None
            and
            floors >= 4
        ):

            return (
                "commercial_midrise",
                "medium",
                "use_plus_height"
            )


        if area >= 1800:

            return (
                "large_commercial",
                "medium",
                "use_plus_footprint"
            )


        return (
            "commercial_lowrise",
            "medium",
            "use_plus_footprint"
        )


    # --------------------------------------------------------
    # INDUSTRIAL
    # --------------------------------------------------------

    if use == "industrial":

        if area >= 1200:

            return (
                "warehouse_industrial",
                "medium",
                "use_plus_footprint"
            )


        return (
            "small_industrial",
            "medium",
            "use_plus_footprint"
        )


    # --------------------------------------------------------
    # EDUCATION
    # --------------------------------------------------------

    if use == "education":

        if area >= 2500:

            return (
                "school_large",
                "high",
                "education_identity"
            )


        return (
            "school_building",
            "high",
            "education_identity"
        )


    # --------------------------------------------------------
    # RELIGIOUS
    # --------------------------------------------------------

    if use == "religious":

        return (
            "religious_building",
            "high",
            "religious_identity"
        )


    # --------------------------------------------------------
    # HEALTHCARE
    # --------------------------------------------------------

    if use in {
        "healthcare",
        "hospital",
    }:

        if area >= 3000:

            return (
                "hospital_healthcare_large",
                "high",
                "healthcare_identity"
            )


        return (
            "healthcare_facility",
            "high",
            "healthcare_identity"
        )


    # --------------------------------------------------------
    # CIVIC / OFFICE / INSTITUTIONAL / ETC.
    # --------------------------------------------------------

    if use == "civic":

        return (
            "civic_building",
            "high",
            "civic_identity"
        )


    if use == "office":

        if (
            floors is not None
            and
            floors >= 5
        ):

            return (
                "office_midrise",
                "medium",
                "use_plus_height"
            )


        return (
            "office_lowrise",
            "medium",
            "use_plus_height"
        )


    if use == "institutional":

        return (
            "institutional_building",
            "medium",
            "institutional_context"
        )


    if use == "lodging":

        return (
            "lodging_building",
            "high",
            "lodging_identity"
        )


    if use == "recreation":

        return (
            "recreation_building",
            "medium",
            "recreation_identity"
        )


    # --------------------------------------------------------
    # UNKNOWN
    # --------------------------------------------------------

    if area >= 2500:

        return (
            "large_unknown_building",
            "low",
            "footprint_only"
        )


    if (
        floors is not None
        and
        floors >= 5
    ):

        return (
            "midrise_unknown",
            "low",
            "height_only"
        )


    return (
        "generic_unknown_building",
        "low",
        "insufficient_semantics"
    )


# ============================================================
# BUILD OUTPUT
# ============================================================

archetype_counts = Counter()
generator_use_counts = Counter()
confidence_counts = Counter()

rowhouse_count = 0
twin_count = 0

review_rows = []
output_features = []


for index, record in enumerate(
    records
):

    properties = dict(
        record[
            "properties"
        ]
    )


    archetype, confidence, source = (
        classify_archetype(
            index,
            record
        )
    )


    if archetype.startswith(
        "rowhouse_"
    ):

        rowhouse_count += 1


    if archetype == (
        "twin_semi_detached"
    ):

        twin_count += 1


    properties.update({

        "generator_version":
            "v2",

        "generator_use":
            record[
                "generator_use"
            ],

        "generator_use_source":
            record[
                "generator_use_source"
            ],

        "generator_use_confidence":
            record[
                "generator_use_confidence"
            ],

        "generator_archetype":
            archetype,

        "generator_archetype_confidence":
            confidence,

        "generator_archetype_source":
            source,

        "footprint_area_m2":
            round(
                record[
                    "area_m2"
                ],
                2
            ),

        "footprint_perimeter_m":
            round(
                record[
                    "perimeter_m"
                ],
                2
            ),

        "footprint_width_m":
            (
                round(
                    record[
                        "width_m"
                    ],
                    2
                )
                if record[
                    "width_m"
                ]
                is not None
                else None
            ),

        "footprint_depth_m":
            (
                round(
                    record[
                        "depth_m"
                    ],
                    2
                )
                if record[
                    "depth_m"
                ]
                is not None
                else None
            ),

        "footprint_orientation_deg":
            (
                round(
                    record[
                        "orientation_deg"
                    ],
                    2
                )
                if record[
                    "orientation_deg"
                ]
                is not None
                else None
            ),

        "estimated_floors":
            record[
                "estimated_floors"
            ],

        "estimated_floors_source":
            record[
                "estimated_floors_source"
            ],

        "row_cluster_id":
            row_cluster_id.get(
                index,
                ""
            ),

        "row_cluster_size":
            row_cluster_size.get(
                index,
                0
            ),

        "row_neighbor_count":
            len(
                row_adjacency.get(
                    index,
                    set()
                )
            ),

        "twin_neighbor_count":
            len(
                twin_adjacency.get(
                    index,
                    set()
                )
            ),

        "twin_partner_master_id":
            (
                records[
                    mutual_twins[
                        index
                    ]
                ][
                    "properties"
                ].get(
                    "master_id",
                    ""
                )
                if index in mutual_twins
                else ""
            ),
    })


    archetype_counts[
        archetype
    ] += 1

    generator_use_counts[
        record[
            "generator_use"
        ]
    ] += 1

    confidence_counts[
        confidence
    ] += 1


    if (
        confidence == "low"
        or
        record[
            "generator_use"
        ]
        ==
        "unknown"
    ):

        review_rows.append({

            "master_id":
                properties.get(
                    "master_id",
                    ""
                ),

            "municipality":
                properties.get(
                    "municipality",
                    ""
                ),

            "address":
                properties.get(
                    "address",
                    ""
                ),

            "poi_name":
                properties.get(
                    "poi_name",
                    ""
                ),

            "generator_use":
                properties.get(
                    "generator_use",
                    ""
                ),

            "generator_archetype":
                archetype,

            "confidence":
                confidence,

            "area_m2":
                properties.get(
                    "footprint_area_m2",
                    ""
                ),

            "width_m":
                properties.get(
                    "footprint_width_m",
                    ""
                ),

            "depth_m":
                properties.get(
                    "footprint_depth_m",
                    ""
                ),

            "height_m":
                properties.get(
                    "height_m",
                    ""
                ),

            "estimated_floors":
                properties.get(
                    "estimated_floors",
                    ""
                ),

            "row_cluster_size":
                properties.get(
                    "row_cluster_size",
                    0
                ),

            "row_neighbors":
                properties.get(
                    "row_neighbor_count",
                    0
                ),

            "twin_neighbors":
                properties.get(
                    "twin_neighbor_count",
                    0
                ),
        })


    output_features.append({

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


# ============================================================
# SAVE GEOJSON
# ============================================================

output = {

    "type":
        "FeatureCollection",

    "name":
        "ChesterWorld_Generator_Buildings_V2",

    "crs": {
        "type":
            "name",

        "properties": {
            "name":
                "EPSG:4326"
        }
    },

    "features":
        output_features
}


with open(
    OUTPUT_GEOJSON,
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
# SAVE REVIEW CSV
# ============================================================

review_fields = [
    "master_id",
    "municipality",
    "address",
    "poi_name",
    "generator_use",
    "generator_archetype",
    "confidence",
    "area_m2",
    "width_m",
    "depth_m",
    "height_m",
    "estimated_floors",
    "row_cluster_size",
    "row_neighbors",
    "twin_neighbors",
]


with open(
    OUTPUT_REVIEW,
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
# SAVE CLUSTER CSV
# ============================================================

cluster_rows = []


for cluster_name, members in (
    row_cluster_members.items()
):

    municipality_counter = Counter()

    areas = []
    widths = []
    depths = []
    heights = []
    addresses = []


    for index in members:

        record = records[
            index
        ]

        props = record[
            "properties"
        ]


        municipality_counter[
            clean(
                props.get(
                    "municipality"
                )
            )
            or
            "Unknown"
        ] += 1


        areas.append(
            record[
                "area_m2"
            ]
        )


        if (
            record[
                "width_m"
            ]
            is not None
        ):

            widths.append(
                record[
                    "width_m"
                ]
            )


        if (
            record[
                "depth_m"
            ]
            is not None
        ):

            depths.append(
                record[
                    "depth_m"
                ]
            )


        if (
            record[
                "height_m"
            ]
            is not None
        ):

            heights.append(
                record[
                    "height_m"
                ]
            )


        address = clean(
            props.get(
                "address"
            )
        )


        if address:

            addresses.append(
                address
            )


    cluster_rows.append({

        "cluster_id":
            cluster_name,

        "size":
            len(
                members
            ),

        "municipality":
            municipality_counter
            .most_common(
                1
            )[0][0],

        "avg_area_m2":
            round(
                sum(areas)
                /
                len(areas),
                2
            ),

        "avg_width_m":
            (
                round(
                    sum(widths)
                    /
                    len(widths),
                    2
                )
                if widths
                else ""
            ),

        "avg_depth_m":
            (
                round(
                    sum(depths)
                    /
                    len(depths),
                    2
                )
                if depths
                else ""
            ),

        "avg_height_m":
            (
                round(
                    sum(heights)
                    /
                    len(heights),
                    2
                )
                if heights
                else ""
            ),

        "sample_address":
            (
                addresses[0]
                if addresses
                else ""
            ),
    })


cluster_fields = [
    "cluster_id",
    "size",
    "municipality",
    "avg_area_m2",
    "avg_width_m",
    "avg_depth_m",
    "avg_height_m",
    "sample_address",
]


with open(
    OUTPUT_CLUSTERS,
    "w",
    encoding="utf-8",
    newline=""
) as f:

    writer = csv.DictWriter(
        f,
        fieldnames=cluster_fields
    )

    writer.writeheader()

    writer.writerows(
        cluster_rows
    )


# ============================================================
# STATS
# ============================================================

cluster_size_counts = Counter(
    len(
        members
    )
    for members
    in row_cluster_members.values()
)


stats = {

    "version":
        "v2",

    "master_buildings":
        len(
            output_features
        ),

    "generator_use_counts":
        dict(
            generator_use_counts
        ),

    "generator_archetype_counts":
        dict(
            archetype_counts
        ),

    "archetype_confidence_counts":
        dict(
            confidence_counts
        ),

    "residential_pair_relationships":
        pair_count,

    "row_neighbor_pairs":
        row_pair_count,

    "twin_neighbor_pairs":
        twin_pair_count,

    "rowhouse_clusters":
        row_cluster_counter,

    "rowhouse_cluster_sizes":
        {
            str(size):
                count

            for size, count
            in sorted(
                cluster_size_counts.items()
            )
        },

    "rowhouses_inferred":
        rowhouse_count,

    "twin_buildings_inferred":
        twin_count,

    "review_queue":
        len(
            review_rows
        ),

    "configuration": {
        "neighbor_search_m":
            NEIGHBOR_SEARCH_M,

        "row_max_gap_m":
            ROW_MAX_GAP_M,

        "twin_max_gap_m":
            TWIN_MAX_GAP_M,

        "row_max_width_m":
            ROW_MAX_WIDTH_M,

        "row_max_area_m2":
            ROW_MAX_AREA_M2,

        "max_orientation_diff_deg":
            MAX_ORIENTATION_DIFF_DEG,

        "max_side_alignment_error_deg":
            MAX_SIDE_ALIGNMENT_ERROR_DEG,
    }
}


with open(
    OUTPUT_STATS,
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

geojson_size_mb = (
    os.path.getsize(
        OUTPUT_GEOJSON
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
    f"Generator buildings: "
    f"{len(output_features):,}"
)

print(
    f"Review queue:        "
    f"{len(review_rows):,}"
)

print(
    f"Residential pairs:   "
    f"{pair_count:,}"
)

print(
    f"Row-neighbor pairs:  "
    f"{row_pair_count:,}"
)

print(
    f"Twin-neighbor pairs: "
    f"{twin_pair_count:,}"
)

print(
    f"Rowhouse clusters:   "
    f"{row_cluster_counter:,}"
)

print(
    f"Rowhouses inferred:  "
    f"{rowhouse_count:,}"
)

print(
    f"Twin buildings:      "
    f"{twin_count:,}"
)


print("")
print("Generator archetypes:")


for archetype, count in (
    archetype_counts
    .most_common()
):

    print(
        f"  {archetype}: "
        f"{count:,}"
    )


print("")
print("Archetype confidence:")


for confidence, count in (
    confidence_counts
    .most_common()
):

    print(
        f"  {confidence}: "
        f"{count:,}"
    )


print("")
print("Rowhouse cluster sizes:")


for size, count in sorted(
    cluster_size_counts.items()
):

    print(
        f"  size {size}: "
        f"{count:,}"
    )


print("")
print(
    f"Generator GeoJSON size: "
    f"{geojson_size_mb:.1f} MB"
)


print("")
print("Generator buildings:")
print(
    OUTPUT_GEOJSON
)

print("")
print("Stats:")
print(
    OUTPUT_STATS
)

print("")
print("Review CSV:")
print(
    OUTPUT_REVIEW
)

print("")
print("Residential clusters:")
print(
    OUTPUT_CLUSTERS
)

print("============================================")
