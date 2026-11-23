"""Guard the bridge deck build against stale late-conformer road geometry."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
conformer = (ROOT / 'src/server/World/RoadTerrainConformer.server.lua').read_text()
highway = (ROOT / 'src/server/World/HighwayInfrastructure.server.lua').read_text()
signals = [i for i in range(len(conformer)) if conformer.startswith('Workspace:SetAttribute("CW_RoadConformComplete", true)', i)]
assert len(signals) == 1, 'road conformer must signal completion once'
assert signals[0] > conformer.index('vDipsSmoothed='), 'V-dip seam repairs must complete before the highway stage'
assert signals[0] > conformer.index('BridgeFinalAudit]'), 'late bridge geometry must finish before the highway stage'
assert highway.index('while Workspace:GetAttribute("CW_RoadConformComplete")') < highway.index('local profiled = {}')
print('PASS: physical highway deck build waits for final conformed road geometry')
