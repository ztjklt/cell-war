local D=require("war.Data")
local U={}
function U.clamp(x,a,b) return math.max(a,math.min(b,x)) end
function U.dist(a,b) local x,y=a.x-b.x,a.y-b.y return math.sqrt(x*x+y*y) end
function U.key(x,y) return (math.floor(y)-1)*D.MAP+math.floor(x) end
function U.xy(k) return ((k-1)%D.MAP)+1,math.floor((k-1)/D.MAP)+1 end
function U.noise(x,y,seed)
 local ix,iy=math.floor(x),math.floor(y);local fx,fy=x-ix,y-iy
 fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
 local a=U.hash(ix,iy,seed);local b=U.hash(ix+1,iy,seed)
 local c=U.hash(ix,iy+1,seed);local d=U.hash(ix+1,iy+1,seed)
 return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy
end
function U.hash(x,y,s) local h=(x*374761393+y*668265263+s*144269)&0x7fffffff;h=((h~(h>>13))*1274126177)&0x7fffffff;return (h~(h>>16))/2147483647 end
function U.rand(s) s.rng=(1664525*s.rng+1013904223)&0xffffffff return s.rng/4294967296 end
function U.copy(v) if type(v)~="table" then return v end local t={} for k,x in pairs(v) do t[k]=U.copy(x) end return t end
function U.costText(c) local D=require("war.Data") local out={} for _,k in ipairs(D.resources) do if c[k] then out[#out+1]=D.names[k]..c[k] end end return table.concat(out," / ") end
function U.message(s,text,f) if not f or f==1 then s.message=text;s.messageTime=8;print("[荒野] "..text) end end
function U.find(s,id) return s.entities[id] end
function U.alive(e) return e and e.hp>0 end
function U.nearest(s,x,y,predicate) local best,dd=false,math.huge for _,e in pairs(s.entities) do if U.alive(e) and predicate(e) then local d=(e.x-x)^2+(e.y-y)^2;if d<dd then best,dd=e,d end end end return best,math.sqrt(dd) end
return U
