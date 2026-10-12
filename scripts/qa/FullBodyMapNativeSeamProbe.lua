-- Isolated native image-quad probe. No image, route or simulation data edits.
local Q={}
function Q.start(g,R,H,opts)
 local A=require('war.FullBodyMapArt');local d=require('war.FullBodyMapArtData')
 local mode='baseline';local old=A.draw
 A.draw=function(...)
  local layer=({['no-foreground']='foregroundPatches',['no-junctions']='junctions',
   ['no-deep']='deepTiles',['no-organs']='organs'})[mode]
  local saved=layer and d[layer]
  if layer then d[layer]={}end
  nvgSave(R.vg)
  if mode=='image-aa-off'then nvgShapeAntiAlias(R.vg,0)end
  local result=table.pack(pcall(old,...))
  nvgRestore(R.vg);if layer then d[layer]=saved end
  if not result[1]then error(result[2])end
  return table.unpack(result,2,result.n)
 end
 return require('qa.FullBodyMapNativeViews').start(g,R,H,{
  outputDir=opts.outputDir,
  beforeView=function(step)mode=step.mode end,
  steps={
   {label='heart-baseline',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='baseline'},
   {label='heart-without-foreground',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='no-foreground'},
   {label='heart-image-aa-off',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='image-aa-off'},
   {label='heart-without-junctions',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='no-junctions'},
   {label='heart-without-deep',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='no-deep'},
   {label='heart-without-organs',zoom=.15,sourcePoint={516.6506939933822,396.8466032556205},mode='no-organs'},
  },
 })
end
return Q
