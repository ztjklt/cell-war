"""Local browser adapter to the real Lua commands/simulation, never a JS nav model."""
from pathlib import Path
import sys,json,time,threading,secrets,argparse,math
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,'/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
sessions={};guard=threading.RLock()
def new_session():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='"+str(ROOT)+"/scripts/?.lua;'..package.path")
 l.execute("T=require('war.GastricTrial');Sim=require('war.Simulation');C=require('war.Commands');G=require('war.GastricBattlefield');K=require('war.CellCollision');W=require('war.World');S=T.new(72026)")
 l.execute("""
 function bloodTarget(ids,x,y)
  local proxy={kind='scout'}
  for _,id in ipairs(ids)do local e=S.entities[id];if e and K.radius(e)>K.radius(proxy)then proxy=e end end
  local net=W.vessels(S);local best,distance
  for lane in pairs(G.data.bloodLanes.siege)do
   if G.pointAllowed(S,proxy,x,y,lane)then
    local d=net.distance(lane,x,y)
    if not best or d<distance or d==distance and lane<best then best,distance=lane,d end
   end
  end
  return best
 end
 function tissueTarget(ids,x,y)
  local proxy={kind='scout'}
  for _,id in ipairs(ids)do local e=S.entities[id];if e and K.radius(e)>K.radius(proxy)then proxy={kind=e.kind}end end
  return G.pointAllowed(S,proxy,x,y,0)
 end
 """)
 token=secrets.token_urlsafe(18)
 sessions[token]={'lua':l,'born':time.monotonic(),'last':time.monotonic()}
 # Repeated resets and forgotten tabs cannot keep unbounded simulation states.
 for key in list(sessions):
  if key!=token and (len(sessions)>8 or time.monotonic()-sessions[key]['last']>1800):del sessions[key]
 return token

def snapshot(token):
 l=sessions[token]['lua'];g=l.globals();s=g.S
 units=[]
 for _,e in g.K.units(s).items():
  units.append({k:e[k]for k in ['id','kind','x','y','vesselLane','pathFailed','pathIndex','contactStall']})
  units[-1]['radius']=g.K.radius(e)
  units[-1]['moving']=len(e.orders)>0
  units[-1]['path']=[{'x':p.x,'y':p.y,'lane':p.lane}for _,p in e.path.items()]
  units[-1]['transit']=bool(e.gastricTransit)
  units[-1]['traffic']=e.gastricTrafficState
 return {'session':token,'time':s.time,'units':units,'message':s.message,'routeStats':dict(g.G.stats().items()),'networkEdges':len(g.W.vessels(s).edges),'engine':'production Lua 5.4 · Commands + Simulation + CellCollision','native':False}

class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(ROOT/'docs/body-life/previews/visible-life'),**kwargs)
 def log_message(self,format,*args):
  if args and str(args[0]).startswith('POST'):return
  super().log_message(format,*args)
 def respond(self,value,status=200):
  b=json.dumps(value,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
 def do_POST(self):
  if self.path!='/api/gastric':self.respond({'error':'unknown endpoint'},404);return
  try:
   n=int(self.headers.get('Content-Length','0'));assert 0<n<=16384
   d=json.loads(self.rfile.read(n))
   with guard:
    action=d.get('action','tick');token=d.get('session')
    if action=='reset' or token not in sessions:token=new_session()
    entry=sessions[token];entry['last']=time.monotonic();l=entry['lua'];g=l.globals()
    if action=='command':
     kind=d.get('kind','move');assert kind in ['move','stop','attackmove']
     ids=[int(i)for i in d.get('ids',[])][:40]
     c={'kind':kind,'faction':1,'ids':l.table_from(ids)}
     if kind!='stop':
      x,y=float(d['x']),float(d['y']);assert math.isfinite(x) and math.isfinite(y)
      lane=g.bloodTarget(c['ids'],x,y) if d.get('plane')=='blood' else int(d.get('lane',0))
      c.update(x=x,y=y,lane=lane)
     if kind!='stop' and d.get('plane')!='blood' and not g.tissueTarget(c['ids'],x,y):
      accepted=False;g.S.message='这里是食物通路或墙面，请点击可通行的组织地面'
     elif kind!='stop' and lane is None:
      accepted=False;g.S.message='这里没有足够净空的可通行血管，请点击管内地面'
     else:accepted=g.C.execute(g.S,l.table_from(c))
    else:accepted=None
    if action=='tick':
     dt=max(0,min(.5,float(d.get('dt',.1))))
     for i in range(int(round(dt/.1))):g.Sim.step(g.S,.1)
    out=snapshot(token);out['accepted']=accepted
    self.respond(out)
  except Exception as ex:
   import traceback;traceback.print_exc();self.respond({'error':str(ex)},400)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=57917);a=p.parse_args()
 ThreadingHTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
