"""Encode the PASDA 2013 1 m land cover into 3 m class grids for the terrain bake.

    python tools/build_ground_cover.py

Writes build/groundcover/index.json and one run-length text file per land-cover
tile. tools/studio/bake_ground_cover.luau (run in Studio Edit through the MCP)
fetches them over a local HTTP server and repaints the surface voxels; the terrain
shape is not changed.

File format: one line per cell row (north to south); each line is comma-separated
runs "<class><length base36>", class 0 = no data.
Classes: 1 grass, 2 tree canopy, 3 other impervious, 4 road, 5 structure,
6 water, 7 barren.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(r"E:\ChesterWorld\Data\12_Vegetation\Canopy_2013")
OUT = ROOT / "build" / "groundcover"
CELL_PX = 3  # 1 m pixels -> 3 m cells (9 studs)

PALETTE = {
    (152, 230, 0): 1,
    (76, 115, 0): 2, (0, 255, 197): 2, (255, 170, 0): 2, (255, 115, 223): 2,
    (225, 225, 225): 3,
    (0, 0, 0): 4,
    (255, 85, 0): 5,
    (0, 132, 168): 6,
    (205, 137, 102): 7,
}
DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"


def base36(n):
    out = ""
    while True:
        n, r = divmod(n, 36)
        out = DIGITS[r] + out
        if n == 0:
            return out


def main():
    meta = json.loads((SRC / "chester_tree_canopy_metadata.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    index = []
    total_runs = 0
    for tile in meta["tiles"]:
        image = np.array(Image.open(SRC / "Rendered" / tile["rendered_file"]).convert("RGBA"))
        classes = np.zeros(image.shape[:2], np.uint8)
        for colour, cls in PALETTE.items():
            hit = ((image[:, :, 0] == colour[0]) & (image[:, :, 1] == colour[1])
                   & (image[:, :, 2] == colour[2]) & (image[:, :, 3] > 0))
            classes[hit] = cls
        h, w = classes.shape[0] // CELL_PX, classes.shape[1] // CELL_PX
        blocks = classes[:h * CELL_PX, :w * CELL_PX].reshape(h, CELL_PX, w, CELL_PX)
        blocks = blocks.transpose(0, 2, 1, 3).reshape(h, w, CELL_PX * CELL_PX)
        counts = np.stack([(blocks == k).sum(-1) for k in range(8)], -1)
        # no-data only wins when the whole cell is empty
        counts[:, :, 0] = np.where(counts[:, :, 1:].sum(-1) > 0, -1, counts[:, :, 0])
        mode = counts.argmax(-1)
        if not mode.any():
            continue
        lines = []
        for row in mode:
            runs, start = [], 0
            change = np.flatnonzero(np.diff(row)) + 1
            for end in list(change) + [len(row)]:
                runs.append(f"{row[start]}{base36(end - start)}")
                start = end
            total_runs += len(runs)
            lines.append(",".join(runs))
        name = f"lc_r{tile['row']:02d}_c{tile['column']:02d}.txt"
        (OUT / name).write_text("\n".join(lines), encoding="utf-8")
        b = tile["bounds"]
        index.append({"file": name, "xmin": b["xmin"], "ymax": b["ymax"], "cell_m": float(CELL_PX),
                      "w": w, "h": h})
    (OUT / "index.json").write_text(json.dumps(index), encoding="utf-8")
    size = sum(p.stat().st_size for p in OUT.glob("lc_*.txt"))
    print("tiles", len(index), "runs", total_runs, "bytes", size)


if __name__ == "__main__":
    main()
