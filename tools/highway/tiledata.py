"""Read generated ChesterWorld tile modules (src/shared/WorldData/Tiles/*.lua)
without a Lua runtime. The modules are machine-written table literals."""
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TILE_DIR = ROOT / "src" / "shared" / "WorldData" / "Tiles"
S = 3.0
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973

_ROAD_LINE = re.compile(r"^\s*\{(name=.*)\},?\s*$")
_FIELD = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|true|false|nil|-?[0-9.eE+-]+)')


def _value(text: str):
    if text.startswith('"'):
        return bytes(text[1:-1], "utf-8").decode("unicode_escape")
    if text == "true":
        return True
    if text == "false":
        return False
    if text == "nil":
        return None
    try:
        return float(text) if any(c in text for c in ".eE") else int(text)
    except ValueError:
        return text


def to_studs(xm: float, zm: float):
    return (xm - CENTER_X_M) * S, -(zm - CENTER_Z_M) * S


def load_roads(tile_dir: Path = TILE_DIR):
    roads = []
    for path in sorted(tile_dir.glob("tile_r*_c*.lua")):
        section = None
        road_index = 0
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("roads = {"):
                section = "roads"
                continue
            if stripped.startswith(("buildings = {", "grade_separations = {")):
                section = None
            if section != "roads":
                continue
            m = _ROAD_LINE.match(line)
            if not m:
                continue
            rec = {k: _value(v) for k, v in _FIELD.findall(m.group(1))}
            rec["tile"] = path.stem
            road_index += 1
            rec["index"] = road_index
            roads.append(rec)
    return roads
