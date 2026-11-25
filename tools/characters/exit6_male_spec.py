"""Measured proportions for the Exit 6 male base character.

Every number here is read off the approved body turnaround
(assets/characters/reference/male_body_turnaround.png, 1122x1402):

* front panel: body centre at x=166, character's right is image-left
* side panel: character faces image-left; x=700 is the depth origin
* y is the image row; soles sit on row 1140, top of skull on row 216

The builder works in this "reference pixel" space (X = x-166,
Y = side_x-700 so the face is -Y, Z = 1140-y) and scales to studs at
the end, so a render with the same camera scale lines up with the
reference pixel for pixel.
"""

SOLE = 1140.0
SKULL_TOP = 216.0
CX = 166.0          # front-panel centre line
CS = 700.0          # side-panel depth origin
HEIGHT_STUDS = 5.6  # sole to top of skull (hair adds ~0.08)

# ---------------------------------------------------------------- torso
# row: (y, half_width, front_x, back_x). Front is the skin plane without
# the pec / abs relief, which the builder adds as displacement.
TORSO = [
    (360, 42, 684, 752),
    (372, 53, 680, 759),
    (384, 64, 673, 765),
    (396, 74, 664, 769),
    (408, 81, 656, 771),
    (420, 86, 650, 771),
    (440, 88, 645, 769),
    (460, 87, 643, 766),
    (480, 84, 641, 762),
    (500, 78, 639, 756),
    (520, 71, 638, 749),
    (540, 65, 638, 742),
    (560, 64, 638, 736),
    (580, 66, 638, 734),
    (600, 69, 639, 738),
    (620, 75, 639, 749),
    (640, 81, 639, 761),
    (660, 87, 637, 767),
    (680, 90, 635, 764),
    (700, 91, 637, 755),
    (715, 87, 638, 748),
    (728, 70, 643, 740),
    (738, 40, 655, 726),
]

NECK = [
    (298, 32, 692, 738),
    (320, 33.5, 680, 742),
    (335, 34.5, 676, 744),
    (345, 35, 676, 746),
    (356, 38, 678, 750),
    (368, 42, 680, 756),
    (380, 50, 682, 762),
    (396, 56, 680, 765),
]

# head slices: (y, half_width, face_plane_front_x, back_x). The face plane
# excludes nose and lips (added as relief); below the ears "back" is the
# jaw line, the neck fills behind it.
HEAD = [
    (216.0, 3, 705, 725),
    (218, 15, 690, 745),
    (222, 26, 677, 757),
    (228, 35, 667, 765),
    (235, 40.5, 660, 770),
    (245, 44, 655, 773),
    (255, 45, 652, 774),
    (262, 45.5, 651, 774),
    (270, 45.5, 656, 772),
    (280, 44.5, 659, 768),
    (290, 43, 660, 762),
    (298, 41.5, 657, 754),
    (305, 38.5, 654, 745),
    (312, 35, 653, 738),
    (318, 31.5, 651, 730),
    (324, 27, 649, 716),
    (330, 20, 649, 699),
    (335, 12, 654, 682),
    (338.5, 4, 663, 672),
]

# ----------------------------------------------------------------- arms
# character's RIGHT arm (image-left). Control points (front_x, side_x, y).
ARM_PATH = [(66, 714, 432), (57, 718, 490), (49, 723, 540), (43, 729, 578),
            (34, 712, 630), (28, 690, 682)]
# (y, lateral_half, depth_half, roll_deg); the shoulder end is closed with a dome
ARM_RADII = [
    (432, 31, 42, 0),
    (455, 31, 40, 0),
    (480, 29, 36, 0),
    (510, 28, 34, 0),
    (545, 25, 30, 0),
    (575, 22, 25, 0),
    (600, 26, 26, 10),
    (625, 25, 24, 22),
    (655, 20, 18, 35),
    (682, 11, 15, 40),
]
# muscle relief on the arm: (y, angle_deg, sigma_y, sigma_angle, height)
# angle: 0 = outward, 90 = front, 180 = toward body, 270 = back
ARM_BUMPS = [
    (440, 0, 26, 70, 5),      # lateral deltoid
    (430, 70, 24, 40, 4),     # front deltoid
    (432, 290, 24, 40, 4),    # rear deltoid
    (512, 105, 22, 45, 9),    # biceps
    (498, 255, 30, 50, 7),    # triceps
    (602, 40, 20, 50, 7.5),   # brachioradialis / forearm extensors
    (612, 150, 22, 45, 2.5),  # forearm flexors
]

# ----------------------------------------------------------------- legs
LEG_PATH = [(123, 698, 688), (118, 697, 745), (115, 697, 790), (111, 700, 866),
            (102, 716, 940), (97, 722, 1050), (97, 724, 1092)]
LEG_RADII = [
    (688, 42, 52, 0),
    (715, 46, 55, 0),
    (745, 48, 56, 0),
    (790, 41, 50, 0),
    (830, 35, 44, 0),
    (866, 30, 39, 0),
    (895, 33, 41, 0),
    (935, 38, 43, 0),
    (975, 33, 37, 0),
    (1015, 25, 31, 0),
    (1050, 21, 26, 0),
    (1092, 21, 28, 0),
]
LEG_BUMPS = [
    (785, 40, 40, 50, 3),     # vastus lateralis
    (842, 140, 18, 35, 5),    # vastus medialis teardrop
    (770, 90, 40, 40, 3),     # rectus femoris
    (868, 90, 9, 40, 3),      # patella
    (928, 220, 28, 45, 6),    # gastrocnemius, inner head
    (915, 310, 25, 40, 4),    # gastrocnemius, outer head
    (780, 270, 35, 50, 3),    # hamstrings
    (745, 180, 25, 40, 2),    # adductors
]

# ----------------------------------------------------------------- feet
# (side_x along foot, half_width, top_y, bottom_y); right foot
FOOT = [
    (765, 12, 1100, 1135),
    (759, 18, 1084, 1140),
    (746, 21, 1068, 1141),
    (728, 22, 1060, 1141),
    (710, 24, 1074, 1141),
    (690, 27, 1092, 1141),
    (670, 31, 1104, 1141),
    (655, 33, 1111, 1141),
    (644, 33, 1116, 1140),
    (637, 31, 1120, 1139),
]
FOOT_X_HEEL = 97.0   # front-panel x of the heel (right foot)
FOOT_X_TOE = 93.0
# toes: (offset across from foot centre toward the big-toe side, tip side_x, radius)
TOES = [(23, 620, 8.0), (9.5, 624, 5.8), (-2, 629, 5.4), (-12.5, 635, 5.0), (-21.5, 641, 4.4)]

# ---------------------------------------------------------------- hands
HAND = {
    "palm_len": 50.0,
    "palm": [(-14, 13.5, 10.0), (0, 16, 11.0), (14, 20.5, 10.5), (32, 23.5, 9.5), (50, 23, 8.4)],  # (along, half_w, half_t)
    # fingers: (across offset, knuckle along, radius, length, spread_deg)
    "fingers": [(13.8, 49, 5.5, 38, 0.5), (4.6, 51, 5.7, 42, 0),
                (-4.6, 49, 5.4, 39, -0.5), (-13.0, 45, 4.8, 31, -1.5)],
    "curl": (20, 38, 26),      # MCP, PIP, DIP flexion in degrees
    "thumb_len": 33.0,
    "palm_normal_back_deg": 32.0,  # how far the palm turns from facing the thigh toward the back
    "bend_forward_deg": 8.0,
}

# ----------------------------------------------------------------- face
HEAD_CX = 0.0
EYE_X = 18.5
EYE_Y_PX = 276.0
EYE_FRONT_SIDE_X = 662.0
EYE_RADIUS = 7.5
EYE_OPEN_HALF_W = 8.7
EYE_OPEN_HALF_H = 3.2

EAR = {"x": 48.5, "side_x": 733.0, "y": 292.0, "half_h": 17.0, "half_d": 10.5, "half_t": 4.2,
       "tilt_back_deg": 14.0, "flare_deg": 18.0}

# R15 joints in reference pixels (front_x, side_x, y), character's right side.
JOINTS_R = {
    "shoulder": (64, 714, 425),
    "elbow": (43, 729, 578),
    "wrist": (28, 690, 682),
    "hand_tip": (33, 676, 765),
    "hip": (120, 698, 690),
    "knee": (111, 700, 866),
    "ankle": (97, 722, 1050),
    "toe": (95, 648, 1128),
}
JOINTS_C = {
    "root": (166, 700, 650),
    "waist": (166, 700, 590),
    "neck": (166, 716, 372),
    "head_top": (166, 712, 216),
}

DELTOID = {"x": 95.0, "side_x": 714.0, "y": 430.0, "r_lat": 35.0, "r_depth": 46.0, "r_up": 42.0,
           "tilt_deg": 32.0}

SKIN_SRGB = (152, 87, 47)
SKIN_LIPS_SRGB = (128, 72, 52)
HAIR_SRGB = (20, 15, 12)
BRIEFS_SRGB = (30, 29, 31)
