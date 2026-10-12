-- Matched anatomy is supplemental art; face, mouth, tablet and marks reuse the pack.
---@class BrainRigAsset
---@field path string
---@field w number
---@field h number
---@field crop number[]
---@class BrainRigPart
---@field pivot number[]
---@field polygon number[][]
---@field phase number
---@class BrainRigDefinition
---@field width number
---@field height number
---@field assets table<string, BrainRigAsset>
---@field arms BrainRigPart[]
---@field core number[][]
---@type BrainRigDefinition
local D={width=390,height=380,assets={},arms={},core={}}
local function asset(key,path,w,h,crop)
 D.assets[key]={path=path,w=w,h=h,crop=crop or {0,0,w,h}}
end
asset("anatomy","image/brain-advisor/rig-v2/anatomy.png",1271,1238)
asset("glasses","image/brain-advisor/rig-v2/glasses.png",1552,1013,{242,234,1126,649})
asset("pupil","image/brain-advisor/production-v1/eyes/pupil_l.png",95,90,{9,5,36,60})
asset("closed","image/brain-advisor/production-v1/eyes/eye_l_closed.png",110,105,{15,6,81,84})
asset("neutral","image/brain-advisor/production-v1/mouth/neutral.png",86,48,{5,6,78,34})
asset("talkA","image/brain-advisor/production-v1/mouth/talk_a.png",89,82,{27,8,58,67})
asset("talkB","image/brain-advisor/production-v1/mouth/talk_b.png",99,64,{5,10,63,49})
asset("talkO","image/brain-advisor/production-v1/mouth/talk_o.png",95,69,{1,7,48,52})
asset("happy","image/brain-advisor/production-v1/mouth/happy.png",90,66,{8,8,65,49})
asset("tabletBase","image/brain-advisor/production-v1/tablet/tablet_base.png",155,110,{0,0,131,108})
asset("tabletOutline","image/brain-advisor/production-v1/tablet/tablet_outline.png",145,110,{0,0,128,108})
asset("tablet","image/brain-advisor/production-v1/tablet/tablet_screen.png",150,110,{0,0,112,110})
asset("alert","image/brain-advisor/production-v1/fx/alert.png",75,87,{9,3,51,79})
asset("question","image/brain-advisor/production-v1/fx/question.png",90,85,{13,3,56,76})
-- Source-space partitions overlap under the central body so rotating roots stay covered.
D.core={{119,169},{154,149},{180,134},{228,127},{270,143},{295,169},{303,197},{313,219},{310,246},{292,273},{273,293},{239,309},{202,313},{164,306},{137,292},{121,270},{108,260},{103,251},{106,237},{105,208}}
D.arms={
 {pivot={200,145},phase=0,polygon={{164,0},{240,0},{240,158},{164,158}}},
 {pivot={141,168},phase=1.1,polygon={{72,72},{115,72},{169,144},{165,190},{124,197},{101,156},{71,115}}},
 {pivot={117,220},phase=2.2,polygon={{0,179},{122,182},{147,212},{140,266},{0,266}}},
 {pivot={137,284},phase=3.3,polygon={{100,247},{156,256},{172,306},{109,356},{50,356},{58,314}}},
 {pivot={186,302},phase=4.4,polygon={{155,284},{227,296},{222,380},{146,380}}},
 {pivot={295,187},phase=5.5,polygon={{274,154},{309,129},{371,126},{372,185},{306,220},{278,206}}},
}
return D
