-- Pearl, ice blue and lavender echo the advisor's painted membrane.
local UI=require("urhox-libs/UI")
local Motion=require("war.UIMotion")
local T={
 ink={250,252,255,232},surface={240,245,255,235},raised={232,240,253,248},
 paper={44,57,82,255},muted={98,116,143,255},quiet={123,139,163,255},
 gold={157,105,36,255},teal={30,132,133,255},blue={56,117,187,255},
 violet={132,102,186,255},danger={189,64,91,255},border={174,192,223,105},
 shadow={{x=0,y=8,blur=28,color={63,88,136,22}}},
}
function T.init()
 local theme=UI.Theme.ExtendTheme(UI.Theme.defaultTheme,{
  fonts={{family="sans",weights={normal="Fonts/MiSans-Regular.ttf",bold="Fonts/MiSans-Bold.ttf"}}},
  colors={background=T.ink,surface=T.surface,surfaceHover=T.raised,text=T.paper,textSecondary=T.muted,
   primary=T.blue,primaryHover={99,155,215,255},secondary=T.violet,success=T.teal,
   warning=T.gold,error=T.danger,border=T.border,disabled={233,236,244,255},disabledText=T.quiet},
  components={Button={borderRadius=10,height=44,fontSize=12,transition="backgroundColor 0.14s easeOut"},
   ScrollView={scrollbarColor={136,156,196,130},scrollbarWidth=4},
   ProgressBar={height=5,borderRadius=9999},Tooltip={fontSize=11,tooltipBgColor=T.raised}},
 })
 UI.Init{theme=theme,scale=UI.Scale.DEFAULT}
end
function T.label(text,size,color,props)
 local p={text=text,fontSize=size or 12,fontColor=color or T.paper,maxLines=1,pointerEvents="none"}
 for k,v in pairs(props or {}) do p[k]=v end
 return UI.Label(p)
end
function T.panel(props)
 local p={backgroundColor=T.ink,borderWidth=1,borderColor=T.border,borderRadius=18,boxShadow=T.shadow}
 for k,v in pairs(props or {}) do p[k]=v end
 if not p.backgroundImage and not p.backgroundGradient then
  local c=p.backgroundColor
  p.backgroundGradient={direction="to-bottom",from={255,255,255,c[4]},to=c}
 end
 return UI.Panel(p)
end
function T.button(text,action,width,accent,props)
 local p={text=text,height=44,width=width or 76,paddingHorizontal=8,fontSize=12,
  borderRadius=12,backgroundColor=accent and {57,94,145,255} or {248,251,255,230},
  backgroundGradient=accent and {direction="to-bottom",from={79,123,178,255},to={49,83,135,255}} or nil,
  textColor=accent and {250,253,255,255} or T.paper,hoverBackgroundColor={230,241,255,255},
  pressedBackgroundColor={211,227,248,255},disabledBackgroundColor={233,236,244,255},disabledTextColor=T.quiet,
  disabledBackgroundGradient={direction="to-bottom",from={245,247,251,255},to={230,236,245,255}},
  borderWidth=1,borderColor=accent and {126,174,227,160} or {164,186,220,100},
  transition="backgroundColor 0.16s easeOut, borderColor 0.16s easeOut",
  onClick=action}
 for k,v in pairs(props or {}) do p[k]=v end
 return Motion.spotlight(UI.Button(p),accent)
end
function T.active(button,active)
 button:SetStyle{backgroundColor=active and {213,231,253,255} or {248,251,255,230},
  borderColor=active and {115,155,209,190} or T.border,textColor=active and {43,93,155,255} or T.paper}
end
-- Battle HUD only: same pearl palette with firmer edges, so panels hold against the
-- saturated anatomy map. Semantic colors are shared by the zone gauge and pads.
T.hud={border={142,163,201,175},shadow={{x=0,y=6,blur=18,color={38,56,96,48}}},
 friendly=T.teal,hostile=T.danger,contested=T.gold,neutral=T.quiet,
 accentFrom={79,123,178,255},accentTo={49,83,135,255},onAccent={250,253,255,255}}
function T.hudPanel(props)
 local p={backgroundColor={250,252,255,244},borderColor=T.hud.border,borderRadius=14,boxShadow=T.hud.shadow}
 for k,v in pairs(props or {}) do p[k]=v end
 return T.panel(p)
end
-- "armed": waiting for a map target or switched on; solid accent with white text.
function T.tone(button,armed)
 button:SetStyle{backgroundColor=armed and {57,94,145,255} or {248,251,255,236},
  backgroundGradient=armed and {direction="to-bottom",from=T.hud.accentFrom,to=T.hud.accentTo} or false,
  borderColor=armed and {126,174,227,200} or T.hud.border,textColor=armed and T.hud.onAccent or T.paper}
end
return T
