"""Apply a JSON list of [old, new] exact replacements to a source file (each must
match once) - the same list is sent to Studio with multi_edit when the Rojo
plugin is disconnected.   apply_edits.py <file> <edits.json>"""
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text(encoding="utf-8")
crlf = "\r\n" in s
s = s.replace("\r\n", "\n")
for old, new in json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")):
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"{n} matches for: {old[:80]!r}")
    s = s.replace(old, new)
p.write_text(s.replace("\n", "\r\n") if crlf else s, encoding="utf-8", newline="")
print("ok", p)
