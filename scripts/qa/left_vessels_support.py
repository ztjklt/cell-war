from pathlib import Path
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/left-vessels-v11'
MODULES=['HeartBattlefieldData','HeartBattlefield','HeartVisualData','HeartDisplayTransform','FullBodyMapArt','BodyLifeFlow','Input']
def load(l,baseline=False):
 for name in MODULES:
  l.globals().qaSource=(OUT/(('baseline-'if baseline else'')+name+'.lua')).read_text();l.globals().qaName='war.'+name
  l.execute('package.loaded[qaName]=assert(load(qaSource))()')
 return l
def runtime(baseline=False):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 return load(l,baseline)
def to_lua(l,value):
 if isinstance(value,list):return l.table_from([to_lua(l,v)for v in value])
 if isinstance(value,dict):return l.table_from({k:to_lua(l,v)for k,v in value.items()})
 return value
