"""V2 tuning for the Exit 6 male: MPFB macro settings, face targets, fit knobs.

The body and face start from the MPFB / MakeHuman hm08 base mesh (CC0),
then get fitted onto the v1 R15 joints and reference landmarks in
exit6_male_spec.py. Everything a reviewer may want to nudge lives here.
"""

# MPFB macro sliders (0..1)
MACRO = {"gender": 1.0, "age": 0.42, "muscle": 0.96, "weight": 0.42, "proportions": 0.9,
         "height": 0.6, "cupsize": 0.5, "firmness": 0.5,
         "race": {"african": 1.0, "asian": 0.0, "caucasian": 0.0}}

# MPFB modelling targets: "folder/name" -> weight. "lr:" expands to l- and r-.
FACE_TARGETS = {
    # nose: short bridge, broad soft tip, wide alar base (reference midface is short)
    "nose/nose-scale-vert-decr": 1.0,
    "nose/nose-trans-up": 0.7,
    "nose/nose-hump-decr": 0.7,
    "nose/nose-width1-incr": 0.5,
    "nose/nose-width2-incr": 0.6,
    "nose/nose-width3-incr": 0.6,
    "nose/nose-point-width-incr": 0.7,
    "nose/nose-flaring-incr": 0.6,
    "nose/nose-nostrils-width-incr": 0.6,
    "nose/nose-scale-depth-decr": 0.35,
    "nose/nose-volume-incr": 0.3,
    "nose/nose-point-up": 0.2,
    # mouth: wide, defined lips, moved up under the short nose
    "mouth/mouth-trans-up": 0.8,
    "mouth/mouth-upperlip-volume-incr": 0.8,
    "mouth/mouth-upperlip-height-incr": 0.3,
    "mouth/mouth-lowerlip-volume-incr": 0.45,
    "mouth/mouth-cupidsbow-incr": 0.6,
    "mouth/mouth-scale-horiz-incr": 0.45,
    "mouth/mouth-scale-depth-decr": 0.3,
    "mouth/mouth-philtrum-volume-incr": 0.3,
    # eyes: larger, open almond eyes
    "lr:eyes/eye-scale-incr": 0.5,
    "lr:eyes/eye-height2-incr": 0.5,
    "lr:eyes/eye-height1-incr": 0.2,
    "lr:eyes/eye-corner1-up": 0.15,
    "lr:eyes/eye-bag-decr": 0.7,
    "lr:eyes/eye-trans-up": 0.3,
    # cheeks / jaw / chin: soft cheeks, square jaw, long broad chin
    "lr:cheek/cheek-volume-incr": 0.6,
    "lr:cheek/cheek-inner-incr": 0.4,
    "lr:cheek/cheek-bones-incr": 0.2,
    "chin/chin-width-incr": 0.6,
    "chin/chin-height-incr": 0.7,
    "chin/chin-prominent-incr": 0.2,
    "chin/chin-bones-incr": 0.5,
    "head/head-square": 0.5,
    "head/head-fat-decr": 0.15,
    "neck/neck-scale-horiz-decr": 0.1,
    "lr:ears/ear-flap-decr": 0.3,
}

# Head fit (multipliers on the landmark-derived scale)
HEAD_DEPTH_MULT = 1.0
HEAD_WIDTH_MULT = 1.0

# Landmarks read off the reference front face (rows, reference px)
LM = {"brow": 263.0, "eye": 276.0, "nose_base": 292.0, "mouth": 305.0, "chin": 338.5}

# Hand pose: palm normal turned this far from facing the thigh toward the back,
# finger curl per joint (MCP, PIP, DIP) and thumb curl
PALM_BACK_DEG = 28.0
FINGER_CURL = (14.0, 26.0, 16.0)
FINGER_CURL_SCALE = {"index": 0.8, "middle": 1.0, "ring": 1.15, "pinky": 1.3}
THUMB_CURL = (0.0, 8.0, 10.0)

# Low-frequency body fit onto the v1 silhouette body, per MPFB bone (0 = keep MPFB shape)
BODY_FIT = {"pelvis": 1.0, "spine_01": 1.0, "spine_02": 1.0, "spine_03": 1.0, "Root": 1.0,
            "clavicle_l": 0.6, "clavicle_r": 0.6, "neck_01": 0.6,
            "upperarm_l": 1.0, "upperarm_r": 1.0, "lowerarm_l": 1.0, "lowerarm_r": 1.0,
            "thigh_l": 1.0, "thigh_r": 1.0, "calf_l": 1.0, "calf_r": 1.0}
BODY_FIT_SMOOTH_ITERS = 1
BODY_FIT_MAX = 0.22   # studs
# muscle relief projected from the v1 sculpt after subdivision (render) / baked to normals (game)
DETAIL_STRENGTH = 0.8
DETAIL_LIMIT = 0.045   # studs
# (x, Y, row) centres in reference px and radius where the v1 relief is faded out:
# shoulder caps (v1 "shoulder pads"), armpits (projection fins), crotch (under the briefs)
FIT_FADE = [((100, 14, 425), 60), ((88, 22, 490), 44)]   # keep MPFB's rounded deltoid / armpit
DETAIL_FADE = [((100, 14, 432), 48), ((88, 22, 490), 40), ((0, 0, 712), 34)]

SKIN_SRGB = (152, 87, 47)
LIP_SRGB = (118, 64, 46)

# ------------------------------------------------- head fit targets (ref px)
# rows of the landmarks on the reference front face
HEAD_ROWS = {"top": 216.0, "eye": 276.0, "nose": 288.0, "mouth": 305.0, "chin": 336.0}
# front silhouette half width without ears / hair (row, half width)
HEAD_HALF_WIDTH = [(228, 33), (234, 39), (240, 42), (246, 44), (254, 45), (262, 45.5), (270, 45.5),
                   (278, 45), (286, 44), (294, 42.5), (302, 41), (310, 39.5), (314, 38.5), (318, 37),
                   (322, 35)]
# side silhouette front edge, skin (row, side-panel x); goatee rows estimated under the beard
HEAD_FRONT_PROFILE = [(256, 652), (262, 650), (266, 651), (270, 652), (274, 651), (278, 648), (282, 642),
                      (286, 640), (290, 641), (294, 645), (298, 643), (302, 641), (306, 643), (310, 641),
                      (314, 644), (318, 646), (322, 647), (326, 646), (330, 647), (334, 650)]
# back of the skull under the hair (from the v1 head table)
HEAD_BACK_PROFILE = [(222, 757), (228, 765), (235, 770), (245, 773), (255, 774), (262, 774), (270, 772),
                     (280, 768), (290, 762), (298, 754)]
EYE_REGION_HALF = 6.0   # px above/below the eye centre that keep the global head scale

# ------------------------------------------- face landmarks (thin-plate warp)
# (x from the face centre, row, side-panel depth Y = side_x - 700); None keeps the
# fitted mesh value. Read off 8x zooms of the reference (front face centre x=170.3).
LANDMARKS = {
    "eye_c":        (19.9, 274.3, -30.0),
    "eye_in":       (10.6, 274.6, -37.5),
    "eye_out":      (29.1, 274.0, -28.5),
    "lid_up":       (19.5, 269.6, -37.0),
    "lid_lo":       (19.5, 278.6, -35.5),
    "glabella":     (0.0, 262.0, -50.5),
    "sellion":      (0.0, 275.0, -48.5),
    "nose_tip":     (0.0, 287.0, -60.0),
    "subnasale":    (0.0, 295.0, -54.5),
    "alar":         (11.2, 290.5, -45.0),
    "lip_up_top":   (0.0, 299.2, -57.0),
    "lip_up_front": (0.0, 302.5, -58.5),
    "mouth_corner": (19.0, 305.5, -41.0),
    "lip_lo_front": (0.0, 309.0, -58.0),
    "lip_lo_bot":   (0.0, 313.0, -55.5),
    "pogonion":     (0.0, 325.0, -52.5),
    "menton":       (0.0, 334.0, -44.0),
    "jaw":          (36.5, 320.0, None),
    "zygion":       (41.0, 284.0, None),
    "ear":          (47.0, 292.0, 33.0),
    "chin_lat":     (14.0, 331.0, -47.0),
    "forehead_lo":  (0.0, 246.0, -46.0),
    "forehead_hi":  (0.0, 232.0, -36.5),
    "skull_top":    (0.0, 216.0, None),
    "occiput":      (0.0, 262.0, 74.0),
}
TPS_SMOOTH = 0.02

DETAIL_SIDE_X = 72.0          # px: no projected relief outside this half-width between rows 400 and 600
SHOULDER_RELAX = ((98, 14, 428), 52)
SHOULDER_RELAX_ITERS = 25
