"""List every place a highway-corridor segment crosses another road segment
in plan without a shared at-grade graph node (offline, source data only)."""
import sys, math, collections, json
sys.path.insert(0, __file__.rsplit('/',1)[0])
import tiledata as T
from analyze_graph import is_hw, level, key, norm

def seg_int(a,b,c,d):
    rx,rz=b[0]-a[0],b[1]-a[1]; sx,sz=d[0]-c[0],d[1]-c[1]
    det=rx*sz-rz*sx
    if abs(det)<1e-9: return None
    dx,dz=c[0]-a[0],c[1]-a[1]
    t=(dx*sz-dz*sx)/det; u=(dx*rz-dz*rx)/det
    e=1e-6
    if -e<=t<=1+e and -e<=u<=1+e:
        L1=math.hypot(rx,rz); L2=math.hypot(sx,sz)
        return t,u,abs(det)/(L1*L2)
    return None

def find():
    R=T.load_roads()
    seps={}
    for p in T.TILE_DIR.glob("tile_*.lua"):
        txt=p.read_text()
        import re
        for m in re.finditer(r'\{id="([^"]+)",upper_source_ids=\{([^}]*)\},lower_source_ids=\{([^}]*)\}',txt):
            ups=re.findall(r'"([^"]+)"',m.group(2)); los=re.findall(r'"([^"]+)"',m.group(3))
            for u in ups:
                for l in los: seps[(u,l)]=m.group(1)
    for r in R:
        r["a"]=T.to_studs(r["x1"],r["z1"]); r["b"]=T.to_studs(r["x2"],r["z2"])
        r["k1"]=key(r["x1"],r["z1"],r,1); r["k2"]=key(r["x2"],r["z2"],r,2)
        r["src"]=":".join(r["grade_group"].split(":")[:2])
    grid=collections.defaultdict(list); C=60
    for i,r in enumerate(R):
        for gx in range(int(math.floor(min(r["a"][0],r["b"][0])/C)),int(math.floor(max(r["a"][0],r["b"][0])/C))+1):
            for gz in range(int(math.floor(min(r["a"][1],r["b"][1])/C)),int(math.floor(max(r["a"][1],r["b"][1])/C))+1):
                grid[(gx,gz)].append(i)
    out=[]; seen=set()
    for i,h in enumerate(R):
        if not is_hw(h): continue
        cand=set()
        for gx in range(int(math.floor(min(h["a"][0],h["b"][0])/C)),int(math.floor(max(h["a"][0],h["b"][0])/C))+1):
            for gz in range(int(math.floor(min(h["a"][1],h["b"][1])/C)),int(math.floor(max(h["a"][1],h["b"][1])/C))+1):
                cand.update(grid[(gx,gz)])
        for j in cand:
            if j==i: continue
            o=R[j]
            if is_hw(o) and j<i: continue  # each hw pair once
            if {h["k1"],h["k2"]}&{o["k1"],o["k2"]}: continue  # real junction
            # same physical vertex but different level/group, collinear continuation? skip near-parallel
            r=seg_int(h["a"],h["b"],o["a"],o["b"])
            if not r: continue
            t,u,sin=r
            if sin<0.26: continue
            x=h["a"][0]+(h["b"][0]-h["a"][0])*t; z=h["a"][1]+(h["b"][1]-h["a"][1])*t
            ck=(round(x/8),round(z/8),h["name"],o["name"])
            if ck in seen: continue
            seen.add(ck)
            lh,lo=level(h),level(o)
            rel="unknown"
            if (h["src"],o["src"]) in seps: rel="highway_over:registry"
            elif (o["src"],h["src"]) in seps: rel="other_over:registry"
            elif lh>lo: rel="highway_over:layer"
            elif lo>lh: rel="other_over:layer"
            out.append(dict(x=round(x,1),z=round(z,1),hw=h["name"],hw_class=h["road_class"],hw_level=lh,hw_src=h["src"],
                other=o["name"],other_class=o["road_class"],other_level=lo,other_src=o["src"],relation=rel,
                other_is_hw=is_hw(o),endpoint_touch=(t<1e-3 or t>1-1e-3 or u<1e-3 or u>1-1e-3)))
    return out
if __name__=="__main__":
    X=find()
    print(len(X), collections.Counter(c["relation"] for c in X))
    json.dump(X,open(sys.argv[1] if len(sys.argv)>1 else "/dev/null","w"),indent=1)
    for c in X:
        if any(s in norm(c["other"]) for s in ["kerlin","upland","potter","chestnut","edgmont","melrose","highland"]) and not c["other_is_hw"]:
            print(c)
