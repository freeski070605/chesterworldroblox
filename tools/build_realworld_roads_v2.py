#!/usr/bin/env python3
from __future__ import annotations
import csv, json
from collections import Counter
from pathlib import Path
from pyproj import Transformer
from shapely.geometry import shape
from shapely.ops import transform as shp_transform
from shapely.strtree import STRtree

ROOT=Path(r"E:\ChesterWorld")
BUILDINGS=ROOT/'Data'/'14_RegionalGeneratorPrep_v2'/'regional_generator_buildings_v2.geojson'
ROADS=ROOT/'Data'/'15_RegionalRoadGeneratorPrep'/'regional_generator_roads.geojson'
OUT=ROOT/'Data'/'17_RealWorldCleanup'; OUT.mkdir(parents=True, exist_ok=True)
ROADS_V2=OUT/'regional_generator_roads_render_v2.geojson'
REVIEW_CSV=OUT/'road_centerline_building_review.csv'
WIDTH_CSV=OUT/'road_width_adjustments.csv'
REPORT=OUT/'realworld_pass2_road_report.json'
TO_METRIC=Transformer.from_crs('EPSG:4326','EPSG:26918',always_xy=True).transform
NON_MOTOR={'pedestrian','footway','path','cycleway','steps','track'}
MAX_AUTO_SHRINK=0.70
BUILDING_CLEARANCE_M=0.35

def load(p): return json.loads(p.read_text(encoding='utf-8'))
def clean(v):
    if v is None: return ''
    t=str(v).strip(); return '' if t.lower() in {'','none','null','nan'} else t

def metric(f):
    try:
        g=shape(f.get('geometry'))
        if g.is_empty: return None
        if not g.is_valid: g=g.buffer(0)
        if g.is_empty: return None
        return shp_transform(TO_METRIC,g)
    except Exception: return None

def get_width(p):
    for k in ('generator_width_m','width_m','width'):
        try:
            v=float(p.get(k))
            if 1.0 <= v <= 80.0: return v
        except Exception: pass
    return 6.0

def get_class(p):
    return clean(p.get('generator_road_class') or p.get('road_class') or p.get('osm_highway') or 'unknown').lower()

def query_indices(tree, geoms, target):
    raw=tree.query(target); out=[]
    for item in raw:
        try:
            idx=int(item)
            if 0 <= idx < len(geoms): out.append(idx); continue
        except Exception: pass
        for idx,g in enumerate(geoms):
            if g is item: out.append(idx); break
    return out

def feature_id(f,i):
    p=f.get('properties') or {}
    for k in ('building_id','OBJECTID','ObjectID','id','osm_id','fid'):
        if clean(p.get(k)): return str(p.get(k))
    return f'building_{i}'

def main():
    print('='*88); print('CHESTERWORLD REAL-WORLD PASS 2 — ROAD WIDTH / CENTERLINE CLASSIFIER'); print('='*88)
    bd=load(BUILDINGS); rd=load(ROADS)
    brec=[]
    for i,f in enumerate(bd.get('features',[])):
        g=metric(f)
        if g is not None and g.area>0.5: brec.append((feature_id(f,i),g))
    bgeoms=[g for _,g in brec]; btree=STRtree(bgeoms)
    out_features=[]; centerline_rows=[]; width_rows=[]; counts=Counter()
    for ri,f in enumerate(rd.get('features',[])):
        props=dict(f.get('properties') or {}); g=metric(f)
        ow=get_width(props); cls=get_class(props); source=clean(props.get('generator_source')); name=clean(props.get('generator_name') or props.get('name'))
        motor=cls not in NON_MOTOR; nw=ow; min_clear=None; hits=[]
        if g is not None and motor:
            cand=query_indices(btree,bgeoms,g.buffer(ow/2+2.0))
            for bi in cand:
                bid,bg=brec[bi]
                try:
                    if g.intersects(bg): hits.append(bid); continue
                    d=float(g.distance(bg))
                except Exception: continue
                if min_clear is None or d<min_clear: min_clear=d
            if hits:
                counts['centerline']+=1; counts[f'centerline_source_{source or "unknown"}']+=1
                centerline_rows.append({'road_index':ri,'name':name,'source':source,'road_class':cls,'original_width_m':round(ow,3),'building_hit_count':len(hits),'building_ids':';'.join(hits[:30])})
            elif min_clear is not None:
                safe=max(1.0,2.0*max(0.0,min_clear-BUILDING_CLEARANCE_M))
                if safe < ow:
                    if safe >= ow*MAX_AUTO_SHRINK:
                        nw=round(safe,2); counts['adjusted']+=1
                        width_rows.append({'road_index':ri,'name':name,'source':source,'road_class':cls,'original_width_m':round(ow,3),'render_width_m':nw,'nearest_building_distance_m':round(min_clear,3),'change_percent':round((nw/ow-1.0)*100.0,2)})
                    else:
                        counts['review_only']+=1
        props['generator_source_width_m']=round(ow,2)
        props['generator_render_width_m']=round(nw,2)
        props['generator_width_m']=round(nw,2)
        props['generator_centerline_building_hits']=len(hits)
        if min_clear is not None: props['generator_nearest_building_clearance_m']=round(min_clear,3)
        nf=dict(f); nf['properties']=props; out_features.append(nf)
    output=dict(rd); output['name']='ChesterWorld_Regional_Roads_Render_v2'; output['features']=out_features
    ROADS_V2.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    with REVIEW_CSV.open('w',newline='',encoding='utf-8') as fp:
        fields=['road_index','name','source','road_class','original_width_m','building_hit_count','building_ids']; w=csv.DictWriter(fp,fieldnames=fields); w.writeheader(); w.writerows(centerline_rows)
    with WIDTH_CSV.open('w',newline='',encoding='utf-8') as fp:
        fields=['road_index','name','source','road_class','original_width_m','render_width_m','nearest_building_distance_m','change_percent']; w=csv.DictWriter(fp,fieldnames=fields); w.writeheader(); w.writerows(width_rows)
    report={'roads_input':len(rd.get('features',[])),'roads_output':len(out_features),'roads_width_adjusted':counts['adjusted'],'roads_width_review_only':counts['review_only'],'roads_centerline_through_buildings':counts['centerline'],'centerline_hits_by_source':{k.replace('centerline_source_',''):v for k,v in counts.items() if k.startswith('centerline_source_')},'policy':{'building_clearance_m':BUILDING_CLEARANCE_M,'maximum_automatic_shrink_fraction':MAX_AUTO_SHRINK,'buildings_deleted':0,'centerline_conflicts_auto_modified':False},'outputs':{'roads_v2':str(ROADS_V2),'centerline_review':str(REVIEW_CSV),'width_adjustments':str(WIDTH_CSV)}}
    REPORT.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(f'Roads output:                     {len(out_features):,}')
    print(f'Road widths safely adjusted:     {counts["adjusted"]:,}')
    print(f'Width conflicts review-only:     {counts["review_only"]:,}')
    print(f'Road centerlines through buildings: {counts["centerline"]:,}')
    print(); print(f'Road render v2: {ROADS_V2}'); print(f'Review:         {REVIEW_CSV}'); print(f'Report:         {REPORT}'); print('='*88)
if __name__=='__main__': main()
