-- Optional controlled membrane additions on unchanged existing vascular edges.
-- Retains every reviewed node, edge and original gate, including rejected exits.
local U=require('war.Util')
local function create(base)
local L=U.copy(base)
L.bodyRegionStudy=true;L.bodyRegionAccessAdditions={}
local function gate(id,edgeId,p,nx,ny,reason)
 local edge=assert(L.edgeIndexById[edgeId],edgeId)
 L.gates[#L.gates+1]={edge=edge,x=p[1]*2,y=p[2]*2+512,nx=nx,ny=ny,name=id}
 L.bodyRegionAccessAdditions[#L.bodyRegionAccessAdditions+1]={id=id,edgeId=edgeId,gateIndex=#L.gates,lumenAnchorSource=p,normal={nx,ny},reason=reason,originalGatePreserved=true}
end
-- The original arm exit overlaps an adjacent same-layer vessel for siege cells.
-- Move along the existing service lumen to an independent, controlled aperture.
gate('body.arm_r.clear_bank','access.arm_r',{332,465},0,1,'Avoid adjacent e061 membrane without changing that wall or the original exit')
-- The original medial thigh exit leaves insufficient clearance to the femur.
-- The opposite bank is served by this same fixed lumen; the femur remains solid.
gate('body.leg_r.clear_bank','e064',{430.1764705882353,891.4705882352941},1,0,'Opposite vascular bank avoids the original femur clearance deficit')
return L
end
local L=create(require('war.StomachConnectivityStudy'));L.create=create
return L
