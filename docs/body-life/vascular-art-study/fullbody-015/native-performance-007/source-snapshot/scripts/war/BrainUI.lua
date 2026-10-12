-- Free-standing advisor; speech arrives as short, quiet strips over the map.
local UI=require("urhox-libs/UI")
local T,B,Rig=require("war.UITheme"),require("war.BrainAdvisor"),require("war.BrainRig")
local A={}
local CHAT={16,18,23,244}
local topics={{"body","人体情况"},{"defense","守卫建议"},{"supply","援军补给"}}
local function weight(char) return utf8.codepoint(char)<128 and .6 or 1 end
local function textWeight(text)
 local total=0;for _,code in utf8.codes(text) do total=total+weight(utf8.char(code)) end;return total
end
-- Preserve every character, prefer punctuation, and cap each strip to one line.
function A.split(text,limit)
 local chunks,chars,used={}, {},0;limit=math.max(6,limit or 20)
 local function flush() if #chars>0 then chunks[#chunks+1]=table.concat(chars);chars={};used=0 end end
 for _,code in utf8.codes(text) do
  local char=utf8.char(code);local width=weight(char)
  if char=="\n" then flush()
  else
   if used+width>limit then flush() end
   chars[#chars+1]=char;used=used+width
   if (char=="。" or char=="！" or char=="？" or char=="；" or char=="，") and used>=4 then flush() end
  end
 end
 flush();return chunks
end
function A.speaking(g,H)
 local d=H.refs.brainDialogue
 return g.started and not g.modal and not g.tab and (g.brainChatOpen or g.brainBubble) and d~=nil and d.active and d.voiceActive or false
end
local function portrait(g,H,size)
 local widget=UI.Panel{width=size,height=size,flexShrink=0,backgroundImage=B.portrait,backgroundFit="contain",pointerEvents="none"}
 ---@param vg NVGContextWrapper
 function widget:Render(vg)
  local a=g.brainAnim or {time=0,lookX=0,lookY=0}
  if not Rig.draw(vg,self:GetAbsoluteLayout(),Rig.pose(a.time,a.lookX,a.lookY,A.speaking(g,H),Rig.mood(g,H),a),true)
   and self.RenderFullBackground then self:RenderFullBackground(vg) end
 end
 return widget
end
local function chatButton(text,action,width)
 return T.button(text,action,width,false,{height=28,fontSize=10,paddingHorizontal=4,
  backgroundColor={30,32,37,245},hoverBackgroundColor={46,49,55,255},pressedBackgroundColor={24,27,34,255},borderColor={255,255,255,18},textColor={226,230,234,255},borderRadius=12})
end
function A.close(g,H)
 g.brainChatOpen=false;g.brainBubble=false;g.brainBubbleTime=0
 local d=H.refs.brainDialogue;d.active=false;d.topic=nil;d.voiceActive=false
 H.refs.brainBubble:SetVisible(false)
end
local function append(H,sender,text)
 local d=H.refs.brainDialogue;d.history[#d.history+1]={sender=sender,text=text}
 while #d.history>6 do table.remove(d.history,1) end
 return d.history[#d.history]
end
local function build(H)
 local d=H.refs.brainDialogue;d.messages:RemoveAllChildren();d.strips={}
 local clock=0
 local function add(text,user)
  local label=T.label(text,11,{235,238,245,255},{maxLines=1,lineHeight=1.1})
  local chip=UI.Panel{position="absolute",left=0,top=0,height=32,paddingHorizontal=12,justifyContent="center",
   width=math.min(H.brainWidth or 356,math.ceil(textWeight(text)*15+26)),borderRadius=12,
   backgroundColor=user and {43,52,69,244} or CHAT,pointerEvents="none",opacity=0,visible=false,children={label}}
  d.messages:AddChild(chip)
  local duration=user and .65 or math.max(1.65,textWeight(text)*.09+.65)
  d.strips[#d.strips+1]={widget=chip,label=label,text=text,user=user,start=clock,duration=duration,y=0}
  clock=clock+duration
 end
 if d.question then add(d.question,true) end
 local limit=math.min(20,((H.brainWidth or 356)-26)/15)
 for _,chunk in ipairs(A.split(d.full,limit)) do add(chunk,false) end
 d.duration=clock;d.elapsed=0;d.lastShown=0
end
function A.say(g,H,text,topic)
 local d=H.refs.brainDialogue
 if d.current then d.current.text=d.full end
 d.current=append(H,"brain","");d.full=text;d.topic=topic;d.active=true
 if not topic then d.question=nil end
 build(H);A.type(g,H,0)
 -- Long automatic reports must finish before their final reading/fade time.
 if not g.brainChatOpen then g.brainBubbleTime=math.max(g.brainBubbleTime or 0,d.duration+3.5) end
end
function A.open(g,H)
 g.drag=false;g.brainChatOpen=true
 if not H.refs.brainDialogue.active then A.answer(g,H,"body") end
 A.fit(g,H)
end
function A.answer(g,H,topic)
 local d=H.refs.brainDialogue;g.brainChatOpen=true;g.drag=false
 d.question=topic=="defense" and "现在应该怎样守卫？" or topic=="supply" and "援军和补给准备好了吗？" or "人体现在怎么样？"
 append(H,"you",d.question);A.say(g,H,B.reply(g.state,topic).text,topic);A.fit(g,H)
end
function A.type(g,H,dt)
 local d=H.refs.brainDialogue;if not d or not d.active then return end
 d.elapsed=d.elapsed+math.max(0,dt);d.voiceActive=false
 local latest=0;local shown={}
 for i,strip in ipairs(d.strips) do
  if d.elapsed>=strip.start then
   latest=i
   if not strip.user then
    shown[#shown+1]=strip.text
    if d.elapsed<strip.start+strip.duration-.25 then d.voiceActive=true end
   end
  end
 end
 d.current.text=table.concat(shown);d.lastShown=utf8.len(d.current.text) or 0
 local capacity=math.max(1,math.min(3,math.floor(((H.brainAvailable or 200)-(g.brainChatOpen and 38 or 0))/40)))
 local first=math.max(1,latest-capacity+1)
 for i,strip in ipairs(d.strips) do
  local fade=g.brainChatOpen and 1 or math.max(0,math.min(1,(d.duration+3.1+(i-first)*.16-d.elapsed)/.45))
  if i==first and latest>=capacity and d.strips[latest+1] then
   fade=fade*math.max(0,math.min(1,(d.strips[latest+1].start-d.elapsed)/.22))
  end
  local visible=i>=first and i<=latest and fade>0
  strip.widget:SetVisible(visible)
  if visible then
   local age=d.elapsed-strip.start;local enter=math.min(1,age/.32);local eased=1-(1-enter)^3
   local target=(i-first)*40
   strip.y=(dt==0 or age<=dt) and target or strip.y+(target-strip.y)*(1-math.exp(-14*dt))
   strip.widget:SetStyle{top=strip.y,translateX=-24*(1-eased),opacity=math.min(1,age/.22)*fade}
  end
 end
 d.show:SetVisible(g.brainChatOpen and d.elapsed<d.duration)
 H.brainFeedHeight=math.min(capacity,latest)*40
 H.refs.brainControls:SetStyle{top=H.brainFeedHeight+4}
end
function A.attach(g,H,_top,play)
 Rig.init(UI.GetNVGContext())
 local character=portrait(g,H,176);H.refs.brainCharacter=character
 local avatar=UI.Panel{id="brainAdvisor",position="absolute",left=12,top=8,width=176,height=176,zIndex=8,padding=0,
  onTap=function() if g.brainChatOpen then A.close(g,H) else A.open(g,H) end end,children={character}}
 H.refs.brainAvatar=avatar;play:AddChild(avatar)
 local messages=UI.Panel{position="absolute",left=0,top=0,width="100%",height="100%",pointerEvents="none"}
 local show=chatButton("»",function() local d=H.refs.brainDialogue;d.elapsed=d.duration;A.type(g,H,0) end,28)
 local quick=UI.Panel{flexDirection="row",gap=5,flexGrow=1,flexBasis=0};local buttons={}
 for _,spec in ipairs(topics) do local key=spec[1]
  local button=chatButton(spec[2],function() A.answer(g,H,key) end,nil)
  button:SetStyle{flexGrow=1,flexBasis=0};buttons[key]=button;quick:AddChild(button)
 end
 local controls=UI.Panel{position="absolute",left=0,top=124,width="100%",flexDirection="row",gap=5,
  children={quick,show,chatButton("×",function() A.close(g,H) end,28)}}
 local bubble=UI.Panel{id="brainChat",position="absolute",left=12,top=194,width=356,height=160,zIndex=9,
  visible=false,pointerEvents="box-none",children={messages,controls}}
 H.refs.brainBubble=bubble;H.refs.brainControls=controls
 H.refs.brainDialogue={state=g.state,character=character,messages=messages,show=show,quick=quick,buttons=buttons,
  strips={},history={},full="",elapsed=0,lastShown=0,active=false,voiceActive=false,autoSeen=false,duration=0}
 play:AddChild(bubble);g.closeBrain=function() A.close(g,H) end
end
---@param battle table|nil UIModel.battle layout in campaign (advisor rect, chatWidth, chatBottom); nil in the sandbox
function A.layout(H,l,w,h,battle)
 local size,left,top
 if battle then
  size,left,top=battle.advisor.w,battle.advisor.x,battle.advisor.y
  H.brainWidth=math.min(battle.chatWidth,w-24);H.brainChatTop=top+size+battle.gap
  H.brainAvailable=math.max(94,battle.chatBottom-H.brainChatTop)
 else
  size,left,top=l.short and 88 or l.narrow and (w<400 and 104 or 116) or 176,12,8
  H.brainWidth=math.min(l.short and 304 or 356,w-24)
  H.brainChatTop=l.narrow and math.max(size+18,l.toolbarY+86) or size+18
  H.brainAvailable=math.max(94,h-l.dock-24-H.brainChatTop)
 end
 H.brainSize=size;H.brainBattle=battle~=nil
 H.refs.brainAvatar:SetStyle{width=size,height=size,left=left,top=top};H.refs.brainCharacter:SetStyle{width=size,height=size}
 H.refs.brainBubble:SetStyle{left=left,top=H.brainChatTop,width=H.brainWidth,height=math.min(160,H.brainAvailable)}
 local d=H.refs.brainDialogue
 if d.active then local elapsed=d.elapsed;build(H);d.elapsed=elapsed end
end
function A.fit(g,H)
 local d=H.refs.brainDialogue
 local visible=g.started and not g.modal and not g.tab and d.active and (g.brainChatOpen or g.brainBubble~=false and g.brainBubble~=nil)
 H.refs.brainBubble:SetVisible(visible);H.refs.brainControls:SetVisible(g.brainChatOpen==true)
 if H.metrics.narrow and not H.brainBattle then H.refs.goalBox:SetVisible(not H.metrics.short and not g.tab and not visible) end
end
function A.update(g,H,dt)
 local d=H.refs.brainDialogue
 if d.state~=g.state then
  d.state=g.state;d.history={};d.messages:RemoveAllChildren();d.strips={};d.full="";d.current=nil;d.lastShown=0
  d.active=false;d.voiceActive=false;d.topic=nil;d.autoSeen=false;g.brainChatOpen=false
 end
 Rig.update(g,H,dt);B.poll(g,dt)
 if g.brainBubble and g.brainBubble~=d.autoSeen then d.autoSeen=g.brainBubble;A.say(g,H,g.brainBubble,nil)
 elseif not g.brainBubble then d.autoSeen=false end
 if not g.modal and not g.tab then A.type(g,H,dt) end
 A.fit(g,H)
end
return A
