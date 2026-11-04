"""swap.py BUNDLE_IN BUNDLE_OUT KEY=SRCFILE... [--extra probe.luau]
Replace SRC[KEY] long strings in a harness bundle with current file contents."""
import re, sys

args = sys.argv[1:]
extra = None
if "--extra" in args:
    i = args.index("--extra")
    extra = args[i + 1]
    del args[i:i + 2]
src, dst, *pairs = args
text = open(src, encoding="utf-8").read()
for pair in pairs:
    key, path = pair.split("=", 1)
    body = open(path, encoding="utf-8").read()
    m = re.search(r'SRC\["' + re.escape(key) + r'"\] = \[(=+)\[\n', text)
    if not m:
        sys.exit("missing " + key)
    close = "]" + m.group(1) + "]"
    end = text.index(close, m.end())
    level = 1
    while ("]" + "=" * level + "]") in body:
        level += 1
    eq = "=" * level
    text = text[:m.start()] + f'SRC["{key}"] = [{eq}[\n{body}]{eq}]' + text[end + len(close):]
if extra:
    text += "\n" + open(extra, encoding="utf-8").read()
open(dst, "w", encoding="utf-8").write(text)
