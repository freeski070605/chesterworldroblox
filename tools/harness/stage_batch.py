"""Write the generated review files as they stand after a given batch, so each
geographic batch can be committed on its own.

    py -3 tools/harness/stage_batch.py b01_r06c07
Rewrites pose_reviews.csv, docs/batch_review_log.csv and
PropertyReconstruction.lua to HEAD + every batch up to and including the one
named (batch order = order of first appearance in the current log).
"""
import csv
import io
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POSE = "tools/reconstruction/pose_reviews.csv"
LOG = "docs/batch_review_log.csv"
LUA = "src/server/World/PropertyReconstruction.lua"
ENTRY = re.compile(r'^\t\["(\d+)"\]=(\{.*\}),$', re.M)


def head(path):
    r = subprocess.run(["git", "show", f"HEAD:{path}"], cwd=ROOT, capture_output=True)
    return r.stdout.decode("utf-8") if r.returncode == 0 else None


def main(upto):
    log = list(csv.DictReader((ROOT / LOG).open(encoding="utf-8", newline="")))
    order = list(dict.fromkeys(r["batch"] for r in log))
    keep = set(order[: order.index(upto) + 1])
    ids = {r["building_id"] for r in log if r["batch"] in keep and r["verdict"] != "SKIP"}

    # pose reviews: HEAD rows + the kept batches' rows, in current order
    cur = (ROOT / POSE).read_text(encoding="utf-8").splitlines(keepends=True)
    base = head(POSE).splitlines(keepends=True)
    base_ids = {l.split(",", 1)[0] for l in base[1:]}
    rows = [l for l in cur[1:] if l.split(",", 1)[0] in base_ids or l.split(",", 1)[0] in ids]
    (ROOT / POSE).write_text(cur[0] + "".join(rows), encoding="utf-8", newline="")

    with (ROOT / LOG).open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(log[0]))
        w.writeheader()
        w.writerows(r for r in log if r["batch"] in keep)

    text = (ROOT / LUA).read_text(encoding="utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    now = dict(ENTRY.findall(text.replace("\r\n", "\n")))
    old_text = head(LUA).replace("\r\n", "\n")
    entries = dict(ENTRY.findall(old_text))
    for bid in ids:
        entries[bid] = now[bid]
    preamble = old_text.split("return {\n", 1)[0] + "return {\n"
    body = "".join(f'\t["{k}"]={v},\n' for k, v in sorted(entries.items(), key=lambda kv: int(kv[0])))
    (ROOT / LUA).write_text((preamble + body + "}\n").replace("\n", nl), encoding="utf-8", newline="")
    print(f"staged through {upto}: {len(ids)} batch IDs, {len(entries)} runtime entries")


if __name__ == "__main__":
    main(sys.argv[1])
