#!/bin/sh
# eye / mouth / chin close-ups of a face-lab blend next to the reference: closeups_v3.sh <tag>
cd "$(dirname "$0")/../.."
BL="/c/Program Files/Blender Foundation/Blender 4.5/blender.exe"
O=$(pwd)/build/exit6_v3; T=$1
"$BL" -b --factory-startup build/exit6_v3/face_lab$T.blend -P tools/characters/debug_closeup_v2.py -- $O/eye$T.png 0 262 290 -15 50 >/dev/null 2>&1
"$BL" -b --factory-startup build/exit6_v3/face_lab$T.blend -P tools/characters/debug_closeup_v2.py -- $O/mouth$T.png 0 284 322 0 50 >/dev/null 2>&1
python - "$T" <<'PY'
import sys
from PIL import Image
T=sys.argv[1]
ref=Image.open('assets/characters/reference/male_body_turnaround.png').convert('RGB')
fc=170.3; rows=[]
for nm,(t,b,xc,w) in {'eye':(262,290,-15,50),'mouth':(284,322,0,50)}.items():
  r=ref.crop((int(fc+xc-w/2),t,int(fc+xc+w/2),b)).resize((int(400*w/(b-t)),400),Image.LANCZOS)
  m=Image.open('build/exit6_v3/%s%s.png'%(nm,T)).convert('RGBA'); bg=Image.new('RGBA',m.size,(232,226,235,255)); m=Image.alpha_composite(bg,m).convert('RGB').resize(r.size)
  rows.append((r,m))
W=max(r.width*2+10 for r,m in rows); s=Image.new('RGB',(W,820),(255,255,255)); y=0
for r,m in rows: s.paste(r,(0,y)); s.paste(m,(r.width+10,y)); y+=410
s.save('build/exit6_v3/cmp_detail%s.png'%T); print('build/exit6_v3/cmp_detail%s.png'%T)
PY
