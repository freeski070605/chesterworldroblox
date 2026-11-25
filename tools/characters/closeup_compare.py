"""Head / hand close-ups of the saved .blend next to the reference (debug aid).

python tools/characters/closeup_compare.py <name> <view:front|side|three_quarter> <cy> <h> [cx]
"""
import os, subprocess, sys
from PIL import Image
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLENDER = r"C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
name, view, cy, h = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
cx = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
az = {"front": 0, "three_quarter": 35, "side": 90, "back": 180}[view]
refc = {"front": 166, "side": 700, "three_quarter": 461, "back": 964}[view]
out = os.path.join(REPO, "build", "characters", "cu_%s_render.png" % name)
subprocess.run([BLENDER, "-b", "--factory-startup",
                os.path.join(REPO, "assets", "characters", "exit6_male", "Exit6_Male_Base.blend"),
                "-P", os.path.join(REPO, "tools", "characters", "debug_view.py"), "--", out,
                "az=%s" % az, "cy=%s" % cy, "h=%s" % h, "cx=%s" % cx, "cycles", "samples=48"],
               check=True, capture_output=True)
ref = Image.open(os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")).convert("RGB")
rx = refc + (cx if view != "back" else -cx)
r = ref.crop((int(rx - h / 2), int(cy - h / 2), int(rx + h / 2), int(cy + h / 2))).resize((600, 600))
im = Image.open(out).convert("RGBA")
bg = Image.new("RGBA", im.size, (232, 226, 235, 255)); bg.alpha_composite(im)
o = Image.new("RGB", (1200, 600)); o.paste(r, (0, 0)); o.paste(bg.convert("RGB").resize((600, 600)), (600, 0))
dst = os.path.join(REPO, "build", "characters", "cu_%s.png" % name)
o.save(dst); print(dst)
