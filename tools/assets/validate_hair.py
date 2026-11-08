"""Check OBJ integrity and manifest counts; does not certify visual quality."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "assets" / "hair"


def main():
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    assert len(manifest) == 12
    for asset in manifest:
        path = ROOT / (asset["id"] + ".obj")
        vertices = []
        faces = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("v "):
                vertices.append(tuple(float(v) for v in line.split()[1:]))
            elif line.startswith("f "):
                faces.append(tuple(int(v.split("/")[0]) for v in line.split()[1:]))
        assert len(vertices) == asset["vertices"], path
        assert len(faces) == asset["triangles"], path
        assert all(len(v) == 3 and all(math.isfinite(x) for x in v) for v in vertices), path
        assert all(len(f) == 3 and all(1 <= i <= len(vertices) for i in f) for f in faces), path
        bounds = [(min(v[i] for v in vertices), max(v[i] for v in vertices)) for i in range(3)]
        assert bounds[0][0] > -1.5 and bounds[0][1] < 1.5, (path, bounds)
        assert bounds[1][0] > -2 and bounds[1][1] < 1.5, (path, bounds)
        assert bounds[2][0] > -.85 and bounds[2][1] < 1.1, (path, bounds)
        print(f"{asset['id']}: {len(vertices)} vertices, {len(faces)} triangles, bounds {bounds}")
    print("PASS: OBJ syntax, counts, finite coordinates, and broad scale bounds")


if __name__ == "__main__":
    main()
