local A={scene=false,sources={},sounds={},muted=false,last=0}
function A.init()
 A.scene=Scene()
 for _,name in ipairs({"command","build","ambient"}) do
  local sound=cache:GetResource("Sound","audio/"..name..".wav")
  if sound then if name=="ambient" then sound.looped=true end;A.sounds[name]=sound;A.sources[name]=A.scene:CreateChild(name):CreateComponent("SoundSource") end
 end
end
function A.play(name)
 if A.muted or not A.sounds[name] then return end
 A.sources[name]:Play(A.sounds[name],0,name=="ambient" and .4 or .25)
end
function A.stop() for _,source in pairs(A.sources) do source:Stop() end;if A.scene then A.scene:Dispose();A.scene=false end end
return A
