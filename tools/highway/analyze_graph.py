"""Offline replica of TileBuilderV2's endpoint graph, focused on the highway corridor."""
import sys, math, collections, json
sys.path.insert(0, __file__.rsplit('/',1)[0])
import tiledata as T

HW_CLASSES = {"motorway","motorway_link","trunk","trunk_link"}
import re
HW_NAME = re.compile(r"^(i|us|pa)[\s\-]*\d+$")
def norm(n): return re.sub(r"\s+"," ",re.sub(r"[^a-z0-9 ]"," ",str(n or "").lower())).strip()
def is_hw(r):
    return r["road_class"] in HW_CLASSES or bool(HW_NAME.match(norm(r["name"])))
def truthy(v):
    if v is True: return True
    t=str(v or "").lower(); return t not in ("","0","false","no","none","nil")
def level(r):
    l=int(r.get("layer") or 0)
    if truthy(r.get("bridge")) and l<=0: l=1
    elif truthy(r.get("tunnel")) and l>=0: l=-1
    return max(-5,min(5,l))
def key(xm,zm,r,i):
    x,z=T.to_studs(xm,zm); q=3.0
    k=f"{math.floor(x/q+0.5)}:{math.floor(z/q+0.5)}:g{level(r)}"
    cg=r.get("node1_connection_group" if i==1 else "node2_connection_group")
    return k+(f":c{cg}" if cg else "")

def build():
    R=T.load_roads()
    nodes=collections.defaultdict(lambda:{"arms":[], "names":set()})
    for r in R:
        for i,(x,z,ox,oz) in ((1,(r["x1"],r["z1"],r["x2"],r["z2"])),(2,(r["x2"],r["z2"],r["x1"],r["z1"]))):
            k=key(x,z,r,i); n=nodes[k]; n["arms"].append(r)
            nm=str(r.get("junction_name") or r["name"] or "")
            if nm and nm!="Road": n["names"].add(nm)
    return R,nodes
if __name__=="__main__":
    R,nodes=build()
    hw=[r for r in R if is_hw(r)]
    print("highway segments",len(hw), "bridge",sum(level(r)>0 for r in hw))
    st=collections.Counter()
    for k,n in nodes.items():
        arms=n["arms"]; h=[a for a in arms if is_hw(a)]
        if not h: continue
        # V2 dedupes arms by name+dir; approx by count
        isI = k.split(":")[2]=="g0" and (len(arms)>=3 or len(n["names"])>=2)
        allhw=len(h)==len(arms)
        st[("allhw" if allhw else "mixed", "pad" if isI else "nopad")]+=1
    print(st)
    # highway segment lengths
    L=[math.dist(T.to_studs(r["x1"],r["z1"]),T.to_studs(r["x2"],r["z2"])) for r in hw]
    print("len studs: min %.1f median %.1f max %.1f"%(min(L),sorted(L)[len(L)//2],max(L)))
    print("width_m",collections.Counter(r["width_m"] for r in hw).most_common(8))
