"""V3 tuning for the Exit 6 male: visual-quality pass on top of V2.

Starts from every V2 value (exit6_male_v2_spec) and overrides:
  * FACE_TARGETS: V2 padded cheeks, lips and nose (volume-incr targets) and
    read as swollen. V3 uses the artist-made MPFB targets in the other
    direction: lean cheeks, high cheekbones, square angular jaw, less lip /
    nose projection, bigger eyes.
  * head fit: least-squares pre-alignment, then a smoothed thin-plate warp on
    the residual with per-landmark trust (estimated landmarks under the goatee
    and on the jaw edge are soft or dropped).
  * FACE_SCULPT / BODY_SCULPT: named sculpt strokes (exit6_sculpt_v3.py),
    judged on neutral-light renders, not on 2D metrics.
  * hair, goatee, hands.
"""
from exit6_male_v2_spec import *          # noqa: F401,F403
import numpy as np

import exit6_male_v2_spec as _V2
FACE_TARGETS_V3A = {
    # nose: short bridge, broad tip, wide alar base, less projection than V2
    "nose/nose-scale-vert-decr": 0.8,
    "nose/nose-trans-up": 0.5,
    "nose/nose-hump-decr": 0.6,
    "nose/nose-width1-incr": 0.2,
    "nose/nose-width2-incr": 0.4,
    "nose/nose-width3-incr": 0.6,
    "nose/nose-point-width-incr": 0.4,
    "nose/nose-flaring-incr": 0.5,
    "nose/nose-nostrils-width-incr": 0.5,
    "nose/nose-scale-depth-decr": 0.7,
    "nose/nose-volume-decr": 0.3,
    "nose/nose-point-up": 0.2,
    # mouth: wide, firm lips that sit back under the nose
    "mouth/mouth-trans-up": 0.6,
    "mouth/mouth-upperlip-volume-decr": 0.2,
    "mouth/mouth-upperlip-height-decr": 0.1,
    "mouth/mouth-lowerlip-volume-incr": 0.15,
    "mouth/mouth-cupidsbow-incr": 0.5,
    "mouth/mouth-scale-horiz-incr": 0.5,
    "mouth/mouth-scale-depth-decr": 0.7,
    "mouth/mouth-trans-backward": 0.3,
    # eyes: open almond eyes, no bags
    "lr:eyes/eye-scale-incr": 0.8,
    "lr:eyes/eye-height2-incr": 0.8,
    "lr:eyes/eye-height1-incr": 0.3,
    "lr:eyes/eye-corner1-up": 0.15,
    "lr:eyes/eye-bag-decr": 0.9,
    "lr:eyes/eye-trans-up": 0.2,
    # lean cheeks, high cheekbones, angular jaw, square chin
    "lr:cheek/cheek-volume-decr": 0.7,
    "lr:cheek/cheek-inner-decr": 0.5,
    "lr:cheek/cheek-bones-incr": 0.9,
    "lr:cheek/cheek-trans-up": 0.3,
    "chin/chin-width-incr": 0.4,
    "chin/chin-height-incr": 0.5,
    "chin/chin-prominent-incr": 0.3,
    "chin/chin-bones-incr": 1.0,
    "chin/chin-jaw-drop-incr": 0.3,
    "head/head-square": 0.7,
    "head/head-fat-decr": 0.9,
    "neck/neck-scale-horiz-decr": 0.1,
    "neck/neck-double-decr": 1.0,
    "lr:ears/ear-flap-decr": 0.3,
}

import os as _os
TARGET_SET = _os.environ.get("EXIT6_TARGETS", "v3b")
# v3b: v3a made younger (fuller, smoother cheeks over the cheekbones), calmer eyes,
# thinner upper lip, jaw tapering to a narrower chin, a little more nose projection
FACE_TARGETS_V3B = dict(FACE_TARGETS_V3A)
FACE_TARGETS_V3B.update({
    "lr:cheek/cheek-volume-decr": 0.25, "lr:cheek/cheek-inner-decr": 0.0, "lr:cheek/cheek-bones-incr": 0.7,
    "head/head-fat-decr": 0.4, "head/head-age-decr": 0.5, "head/head-square": 0.3,
    "head/head-invertedtriangular": 0.35,
    "chin/chin-width-incr": 0.0, "chin/chin-width-decr": 0.2, "chin/chin-bones-incr": 0.7,
    "lr:eyes/eye-scale-incr": 0.35, "lr:eyes/eye-height2-incr": 0.6, "lr:eyes/eye-push1-in": 0.0,
    "mouth/mouth-upperlip-volume-decr": 0.5, "mouth/mouth-upperlip-height-decr": 0.3,
    "mouth/mouth-lowerlip-volume-incr": 0.0, "mouth/mouth-scale-horiz-incr": 0.6,
    "mouth/mouth-laugh-lines-in": 0.6,
    "nose/nose-scale-depth-decr": 0.3, "nose/nose-point-width-incr": 0.6, "nose/nose-width2-incr": 0.5,
})
FACE_TARGETS_V3B.update({
    "mouth/mouth-upperlip-volume-decr": 0.7, "mouth/mouth-upperlip-height-decr": 0.6,
    "mouth/mouth-cupidsbow-incr": 1.0,
    "nose/nose-point-up": 0.5, "nose/nose-nostrils-angle-up": 0.4, "nose/nose-flaring-incr": 0.7,
})
FACE_TARGETS_V3B.update({
    "mouth/mouth-laugh-lines-in": 0.0,
    "lr:eyes/eye-scale-incr": 0.3, "lr:eyes/eye-height2-incr": 0.2, "lr:eyes/eye-eyefold-down": 0.4,
})
FACE_TARGETS_V3B.update({
    "nose/nose-width3-incr": 0.0, "nose/nose-width3-decr": 0.25, "nose/nose-width2-incr": 0.1,
    "nose/nose-flaring-incr": 0.3, "nose/nose-point-up": 0.9, "nose/nose-nostrils-angle-up": 0.8,
    "nose/nose-point-width-incr": 0.3,
})
FACE_TARGETS_V3B = {k: v for k, v in FACE_TARGETS_V3B.items() if v}
FACE_TARGETS = {"v2": dict(_V2.FACE_TARGETS), "v3a": FACE_TARGETS_V3A, "v3b": FACE_TARGETS_V3B}[TARGET_SET]
# "v2" = V2 warp + relax, "v3" = prealign + soft warp, "affine" = smooth affine only (no pinning)
HEAD_FIT = _os.environ.get("EXIT6_HEADFIT", "affine")

# --------------------------------------------------- head fit, V3
# landmark trust: TPS regulariser per landmark (0 = exact, larger = softer, None = dropped)
LANDMARK_SOFT = {
    "eye_c": 0.0, "eye_in": 0.5, "eye_out": 0.5, "lid_up": None, "lid_lo": None,
    "glabella": 1.0, "sellion": 1.0, "nose_tip": 0.5, "subnasale": 1.0, "alar": 1.0,
    "lip_up_top": 2.0, "lip_up_front": 1.0, "mouth_corner": 0.5, "lip_lo_front": 2.0,
    "lip_lo_bot": None, "pogonion": 3.0, "menton": None, "jaw": None, "zygion": 2.0,
    "ear": 1.0, "chin_lat": None, "forehead_lo": 1.0, "forehead_hi": 1.0, "skull_top": 0.5,
    "occiput": 1.0,
}
PREALIGN = "affine"        # least-squares affine of the head before the residual warp
TPS_SMOOTH_BASE = 0.5      # added to every landmark's regulariser

# ------------------------------------------------------------ face sculpt
# reference-pixel strokes, applied after the head fit. c = (x, Y, row), r = radius
# (scalar or (rx, rY, rrow)); x mirrored. Y is negative in front of the face.
FACE_SCULPT = [
    # crisp mandible: hollow the soft tissue under the jaw so the edge catches light / casts shadow
    dict(name="under_jaw_hollow", kind="push", c=(22, -12, 341), r=(18, 18, 8), amount=-2.2),
    dict(name="gonial_angle", kind="push", c=(37, 6, 325), r=(8, 9, 9), amount=0.9),
    # heavier upper lid: the margin comes down over the top of the iris
    dict(name="upper_lid_lower", kind="move", c=(19.5, -38, 270.0), r=(9, 6, 3.2), d=(0, -0.5, 2.2),
         mask=lambda Q, s: (Q[:, 1] < -33).astype(float)),
    dict(name="lower_lid_raise", kind="move", c=(19.5, -36, 278.8), r=(8, 6, 2.6), d=(0, -0.2, -0.7),
         mask=lambda Q, s: (Q[:, 1] < -32).astype(float)),
    # soften the deep nasolabial fold (reads older than the reference)
    dict(name="nasolabial_soften", kind="taubin", c=(17, -44, 300), r=(8, 10, 11), iters=6),
    dict(name="jaw_line_relax", kind="taubin", c=(26, -6, 333), r=(22, 20, 12), iters=3),
]
BROW_RELIEF = 0.5          # scale on the v1 brow thickness (V2 brows stood 3 px proud)
# joints (x, Y, row): shoulder (102, 14, 425), elbow (123, 29, 578), wrist (138, -10, 682),
# hip (46, -2, 690), knee (55, 0, 866), ankle (69, 22, 1050)
def _front(Q, s):
    return np.clip((-Q[:, 1] - 10) / 12, 0, 1)


def _back(Q, s):
    return np.clip((Q[:, 1] - 4) / 10, 0, 1)


def _arm(Q, s):
    return np.clip((np.abs(Q[:, 0]) - 86) / 6, 0, 1)


def _leg(Q, s):
    return np.clip((Q[:, 2] - 700) / 10, 0, 1)


# measured on the fitted body (ref px): chest front Y -50..-58 (rows 470-490); upper arm axis
# ~(110, 15) radius 22-25; forearm axis (123, 10) -> (136, -6); thigh axis x ~50, radius ~34
BODY_SCULPT = [
    # the sagging lat "fins" at the torso sides (x ~78, rows 505-530) and the step below them
    dict(name="lat_fin_relax", kind="taubin", c=(78, 0, 520), r=(14, 70, 30), iters=14),
    dict(name="lat_fin_trim", kind="push", c=(80, 0, 518), r=(9, 60, 18), amount=-1.8),
    dict(name="waist_taper_blend", kind="taubin", c=(72, 0, 548), r=(12, 70, 24), iters=8),
    # broad square pecs from the sternum out to the deltoid, crisp lower border
    dict(name="pec_mass", kind="push", c=(38, -54, 466), r=(34, 26, 24), amount=6.0, mask=_front),
    dict(name="pec_outer", kind="push", c=(66, -42, 456), r=(18, 24, 22), amount=2.6, mask=_front),
    dict(name="pec_shelf", kind="push", c=(40, -58, 480), r=(30, 14, 10), amount=2.0, mask=_front),
    dict(name="pec_lower_border", kind="push_seg", a=(8, -58, 491), b=(72, -40, 481), r=6.0, amount=-3.0,
         mask=_front),
    # round deltoid caps and fuller arms (reference arms are 4-8 px wider each side)
    dict(name="deltoid_cap", kind="push", c=(126, 14, 452), r=(18, 40, 32), amount=5.0, power=1.0, mask=_arm),
    dict(name="deltoid_front", kind="push", c=(116, -12, 450), r=(16, 18, 26), amount=2.2, mask=_arm),
    dict(name="upper_arm_mass", kind="push_seg", a=(110, 16, 468), b=(118, 20, 562), r=36.0, amount=8.5,
         power=1.0, profile=[0.5, 1.0, 1.0, 0.5], mask=_arm),
    dict(name="biceps_peak", kind="push", c=(112, -6, 512), r=(14, 14, 24), amount=2.2, mask=_arm),
    dict(name="forearm_mass", kind="push_seg", a=(121, 14, 588), b=(136, -6, 672), r=28.0, amount=4.0,
         power=1.0, profile=[0.9, 1.0, 0.5, 0.1], mask=_arm),
    # fuller quads and calves
    dict(name="quad_mass", kind="push_seg", a=(48, -4, 730), b=(54, -2, 850), r=50.0, amount=3.4,
         power=1.0, profile=[0.3, 1.0, 1.0, 0.4], mask=_leg),
    dict(name="calf_mass", kind="push_seg", a=(58, 12, 900), b=(66, 18, 990), r=36.0, amount=3.0,
         power=1.0, profile=[0.6, 1.0, 0.3], mask=lambda Q, s: _back(Q, s) * _leg(Q, s)),
]

# --------------------------------------------------------------- hands
HAND_SCALE = 1.22          # uniform scale about the wrist (after the v1 wrist->tip fit)
FINGER_CLOSE = 0.65
THUMB_CLOSE = 0.55         # 0..1: swing the thumb toward the hand axis
FINGER_CURL = (6.0, 14.0, 10.0)   # V2: (14, 26, 16); reference fingers hang nearly straight        # 0..1: rotate each finger toward the middle finger in the palm plane

# ------------------------------------------------------------- eyes / skin colour
EYE_IRIS_DEG = 43.0        # iris radius as an angle from the gaze axis
EYE_PUPIL_DEG = 15.0
EYE_SCLERA_SRGB = (226, 216, 206)
EYE_IRIS_SRGB = (30, 18, 11)
EYE_IRIS_INNER_SRGB = (48, 28, 17)
UPPER_LIP_SRGB = (96, 52, 37)
LOWER_LIP_SRGB = (150, 90, 66)
LASH_UPPER = (1.0, 2.8)    # strength, radius px around MPFB's upper lash strip
LASH_LOWER = (0.25, 0.8)

# ------------------------------------------------------------------- hair
HAIR = dict(SPACING=16.5, R_TWIST=4.7, PITCH=9.0, PART_GAP=3.0)
# twist tip rows by |angle from the face|: fringe at the brows, sides to the jaw, shorter at the back than V2
HAIR_TIP_ANG = [0.0, 0.45, 0.8, 1.2, 1.7, 2.2, 3.1416]
HAIR_TIP_ROWS = [258, 263, 280, 294, 298, 306, 312]
