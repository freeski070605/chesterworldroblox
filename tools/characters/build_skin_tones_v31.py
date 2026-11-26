"""Recolour the approved V3.1 body ColorMap without changing geometry or relief."""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/characters/exit6_male/textures_v3_1/Exit6V31_Body_Color.png"
OUTPUT = SOURCE.parent / "skin_tones"
TONES = (
    (58, 36, 26), (86, 56, 40), (110, 72, 50), (132, 90, 62),
    (160, 112, 78), (186, 136, 96), (204, 156, 116),
    (222, 184, 148), (238, 206, 176), (248, 224, 204),
)
BASE = np.array((152, 87, 47), dtype=np.float32)

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    src = np.asarray(Image.open(SOURCE).convert("RGB"), dtype=np.float32)
    shade = np.clip(src / BASE, 0, 3)
    for index, rgb in enumerate(TONES, 1):
        out = np.clip(shade * np.array(rgb, dtype=np.float32), 0, 255).astype(np.uint8)
        path = OUTPUT / f"Exit6V31_Skin_{index:02d}.png"
        Image.fromarray(out).save(path, optimize=True)
        print(path.relative_to(ROOT))

if __name__ == "__main__":
    main()
