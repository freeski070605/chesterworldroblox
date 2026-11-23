"""Build execute_luau chunks that bring Studio's PropertyReconstruction in line
with the disk file when the Rojo plugin is disconnected.

    py -3 tools/harness/studio_recon_patch.py [max_chars]
Writes build/studio_patch/recon_NN.luau; each chunk replaces or inserts the
given entries (exact lines from the disk module) inside the Studio Source.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = "src/server/World/PropertyReconstruction.lua"
OUT = ROOT / "build" / "studio_patch"
LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 24000
BASE = sys.argv[2] if len(sys.argv) > 2 else None   # diff from this rev (default: working tree vs HEAD)

diff = subprocess.run(["git", "diff", "-U0"] + ([BASE, "HEAD"] if BASE else []) + ["--", MOD], cwd=ROOT, capture_output=True, text=True,
                      encoding="utf-8").stdout
added = [l[1:].rstrip("\r") for l in diff.splitlines() if l.startswith("+\t[")]
OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("recon_*.luau"):
    old.unlink()
chunks, cur = [], []
for line in added:
    if sum(len(x) for x in cur) + len(line) > LIMIT and cur:
        chunks.append(cur)
        cur = []
    cur.append(line)
if cur:
    chunks.append(cur)
HEAD = '''local m = game.ServerScriptService.Server.World.PropertyReconstruction
local s = m.Source
local E = {
'''
TAIL = '''}
local replaced, inserted = 0, 0
local add = {}
for _, raw in ipairs(E) do
  local line = '\\t' .. raw
  local id = line:match('^\\t%["(%d+)"%]=')
  local a, b = s:find('\\n\\t%["' .. id .. '"%]=[^\\n]*', 1)
  if a then
    s = s:sub(1, a) .. line .. s:sub(b + 1)
    replaced += 1
  else
    table.insert(add, line)
  end
end
if #add > 0 then
  local close = s:find("\\n}%s*$")
  s = s:sub(1, close) .. table.concat(add, "\\n") .. s:sub(close)
  inserted = #add
end
game:GetService("ScriptEditorService"):UpdateSourceAsync(m, function() return s end)
local _, n = s:gsub('status="reconstructed"', '')
return ("replaced %d inserted %d reconstructed-now %d"):format(replaced, inserted, n)
'''
for i, chunk in enumerate(chunks, 1):
    body = "".join("  " + repr_line + ",\n" for repr_line in
                   ("[==[" + l.lstrip("\t") + "]==]" for l in chunk))
    (OUT / f"recon_{i:02d}.luau").write_text(HEAD + body + TAIL, encoding="utf-8")
print(len(added), "entries in", len(chunks), "chunks ->", OUT)
