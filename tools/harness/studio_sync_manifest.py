"""Manifest of src/ for checking / patching Studio when the Rojo plugin is
disconnected: instance path, class, LF length and byte sum per script."""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
MOUNTS = {"src/shared": ["ReplicatedStorage", "Shared"], "src/server": ["ServerScriptService", "Server"],
          "src/client": ["StarterPlayer", "StarterPlayerScripts", "Client"]}

def entries():
    for mount, base in MOUNTS.items():
        for f in sorted((ROOT / mount).rglob("*")):
            if f.suffix not in (".lua", ".luau") or not f.is_file():
                continue
            rel = f.relative_to(ROOT / mount).parts
            name = rel[-1].rsplit(".", 1)[0]
            cls = "ModuleScript"
            if name.endswith(".server"): cls, name = "Script", name[:-7]
            elif name.endswith(".client"): cls, name = "LocalScript", name[:-7]
            path = base + list(rel[:-1]) + ([] if name == "init" else [name])
            b = f.read_bytes().replace(b"\r\n", b"\n")
            yield {"file": str(f.relative_to(ROOT)).replace("\\", "/"), "path": path, "cls": cls, "len": len(b), "sum": sum(b)}

if __name__ == "__main__":
    data = list(entries())
    Path(sys.argv[1]).write_text(json.dumps(data), encoding="utf-8")
    print(len(data))
