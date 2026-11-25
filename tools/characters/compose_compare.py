"""Compose reference-vs-render comparison sheets for the Exit 6 male base.

    python tools/characters/compose_compare.py [prefix]

Renders come from build_exit6_male.py with an orthographic camera at the
reference's own pixel scale (render column 300 = reference body centre, rows
match 1:1), so the front and side views overlay without any fitting. The
3/4 and back panels are aligned on the silhouette's horizontal centroid.

Writes renders/compare_<view>.png (reference | render | silhouette overlay)
and renders/compare_metrics.json (silhouette IoU per view).
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")
REN = os.path.join(REPO, "assets", "characters", "exit6_male", "renders")
BG = np.array([232, 226, 235], float)
PANELS = {"front": (8, 324), "three_quarter": (324, 600), "side": (606, 804), "back": (808, 1120)}
CENTERS = {"front": 166, "side": 700}
ROW0, ROW1 = 180, 1175
HALF = 175


def ref_mask(a):
    return np.abs(a - BG).sum(2) > 40


def centroid_x(mask, rows=(380, 1100)):
    m = mask[rows[0]:rows[1]]
    ys, xs = np.nonzero(m)
    return xs.mean() if len(xs) else mask.shape[1] / 2


def main(prefix="render"):
    ref = np.asarray(Image.open(REF).convert("RGB")).astype(float)
    try:
        font = ImageFont.truetype("arial.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    metrics = {}
    for view, (x0, x1) in PANELS.items():
        path = os.path.join(REN, "%s_%s.png" % (prefix, view))
        if not os.path.exists(path):
            continue
        rgba = np.asarray(Image.open(path).convert("RGBA")).astype(float)
        a = rgba[..., 3:4] / 255.0
        comp = rgba[..., :3] * a + BG * (1 - a)
        rmask = (rgba[..., 3] > 140)
        rmask[1133:] = False
        # reference panel isolated
        panel = np.tile(BG, (ref.shape[0], ref.shape[1], 1))
        panel[:, x0:x1] = ref[:, x0:x1]
        pmask = ref_mask(panel); pmask[1133:] = False
        if view in CENTERS:
            rc = CENTERS[view]; cc = 300
        else:
            rc = centroid_x(pmask); cc = centroid_x(rmask)
        def crop(img, c, fill):
            c = int(round(c))
            out = np.empty((ROW1 - ROW0, 2 * HALF) + img.shape[2:], img.dtype); out[...] = fill
            lo, hi = c - HALF, c + HALF
            s0, s1 = max(lo, 0), min(hi, img.shape[1])
            out[:, s0 - lo:s1 - lo] = img[ROW0:ROW1, s0:s1]
            return out
        A = crop(panel, rc, BG); B = crop(comp, cc, BG)
        MA = crop(pmask, rc, False); MB = crop(rmask, cc, False)
        inter = (MA & MB).sum(); union = (MA | MB).sum()
        iou = float(inter / max(union, 1))
        # row-wise width error (px) where both have figure
        wa, wb = MA.sum(1), MB.sum(1)
        both = (wa > 0) & (wb > 0)
        width_err = float(np.mean(np.abs(wa[both] - wb[both]))) if both.any() else None
        metrics[view] = {"silhouette_iou": round(iou, 4), "mean_row_width_err_px": round(width_err, 2),
                         "ref_height_px": int(np.ptp(np.nonzero(wa)[0])) if wa.any() else 0,
                         "render_height_px": int(np.ptp(np.nonzero(wb)[0])) if wb.any() else 0}
        ov = np.tile(BG, (MA.shape[0], MA.shape[1], 1))
        ov[MA & MB] = (150, 150, 150)
        ov[MA & ~MB] = (220, 40, 40)
        ov[~MA & MB] = (30, 170, 220)
        sheet = np.concatenate([A, B, ov], 1).clip(0, 255).astype(np.uint8)
        im = Image.fromarray(sheet)
        d = ImageDraw.Draw(im)
        for i, t in enumerate(("Reference", "Blender render", "Overlay  IoU %.3f" % iou)):
            d.text((i * 2 * HALF + 10, 8), t, fill=(30, 30, 30), font=font)
        d.text((4 * HALF + 10, 36), "red = reference only", fill=(200, 30, 30), font=font)
        d.text((4 * HALF + 10, 62), "blue = model only", fill=(20, 140, 200), font=font)
        out = os.path.join(REN, "compare_%s.png" % view)
        im.save(out)
        print(view, metrics[view], "->", out)
    with open(os.path.join(REN, "compare_metrics.json"), "w") as fh:
        json.dump(metrics, fh, indent=1)


if __name__ == "__main__":
    # python compose_compare.py [prefix] [render subdir]
    if len(sys.argv) > 2:
        REN = os.path.join(REPO, "assets", "characters", "exit6_male", sys.argv[2])
    main(*(sys.argv[1:2] or []))
