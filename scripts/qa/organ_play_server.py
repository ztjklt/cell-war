"""Local visual adapter for the production organ atlas, with no JS movement model."""
from pathlib import Path
import sys,json,time,threading,secrets,argparse,math
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,'/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
sessions={};guard=threading.RLock()
def new_session(ids=None):
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='"+str(ROOT)+"/scripts/?.lua;'..package.path")
    l.globals().requestedIds=l.table_from(ids) if ids else None
    l.execute("T=require('war.OrganTrial');Sim=require('war.Simulation');C=require('war.Commands');G=require('war.OrganBattlefield');K=require('war.CellCollision');W=require('war.World');S=T.new(72026,requestedIds)")
    l.execute('''
    function targetLane(ids,x,y,plane)
     local proxy={kind='scout'}
     for _,id in ipairs(ids)do local e=S.entities[id];if e and K.radius(e)>K.radius(proxy)then proxy=e end end
     if plane~='blood' then return G.pointAllowed(S,proxy,x,y,0) and 0 or nil end
     local best,dd;local net=G.net(S)
     for lane in pairs(G.trafficData(S).bloodLanes.siege)do
      if G.pointAllowed(S,proxy,x,y,lane)then
       local d=net.distance(lane,x,y)
       if not best or d<dd or d==dd and lane<best then best,dd=lane,d end
      end
     end
     return best
    end
    ''')
    token=secrets.token_urlsafe(18);sessions[token]={'lua':l,'last':time.monotonic()}
    for key in list(sessions):
        if key!=token and (len(sessions)>8 or time.monotonic()-sessions[key]['last']>1800):del sessions[key]
    return token
def snapshot(token):
    g=sessions[token]['lua'].globals();s=g.S;units=[]
    for _,e in g.K.units(s).items():
        u={k:e[k] for k in ['id','kind','x','y','vesselLane','pathFailed','pathIndex','contactStall']}
        u.update(radius=g.K.radius(e),moving=len(e.orders)>0,
                 path=[{'x':p.x,'y':p.y,'lane':p.lane}for _,p in e.path.items()],transit=bool(e.gastricTransit))
        units.append(u)
    return dict(session=token,time=s.time,units=units,message=s.message,
                routeStats=dict(g.G.stats().items()),networkEdges=len(g.W.vessels(s).edges),
                organs=[v for _,v in g.G.activeOrgans(s).items()],
                engine='production Lua 5.4 · Commands + Simulation + CellCollision',native=False)
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(ROOT/'docs/body-life/previews/visible-life'),**kwargs)
    def log_message(self,format,*args):
        if args and str(args[0]).startswith('POST'):return
        super().log_message(format,*args)
    def respond(self,value,status=200):
        b=json.dumps(value,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def do_POST(self):
        if self.path!='/api/organs':self.respond({'error':'unknown endpoint'},404);return
        try:
            n=int(self.headers.get('Content-Length','0'));assert 0<n<=16384;d=json.loads(self.rfile.read(n))
            with guard:
                action=d.get('action','tick');token=d.get('session')
                if action=='reset' or token not in sessions:token=new_session(d.get('organs'))
                entry=sessions[token];entry['last']=time.monotonic();l=entry['lua'];g=l.globals();accepted=None
                if action=='command':
                    kind=d.get('kind','move');assert kind in ['move','stop','attackmove']
                    ids=l.table_from([int(i)for i in d.get('ids',[])][:40]);c=dict(kind=kind,faction=1,ids=ids)
                    lane=0
                    if kind!='stop':
                        x,y=float(d['x']),float(d['y']);assert math.isfinite(x)and math.isfinite(y)
                        lane=g.targetLane(ids,x,y,d.get('plane'));c.update(x=x,y=y,lane=lane)
                    if lane is None:
                        accepted=False;g.S.message='这里没有足够净空的可通行地面，请选择组织地面或管内通道'
                    else:accepted=g.C.execute(g.S,l.table_from(c))
                elif action=='tick':
                    dt=float(d.get('dt',.1));assert math.isfinite(dt)
                    for _ in range(round(max(0,min(.5,dt))/.1)):g.Sim.step(g.S,.1)
                elif action=='save_restore':
                    l.execute("S=require('war.Save').restore(require('war.Save').snapshot(S))")
                out=snapshot(token);out['accepted']=accepted;self.respond(out)
        except Exception as ex:
            import traceback;traceback.print_exc();self.respond({'error':str(ex)},400)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=57918);a=p.parse_args()
    ThreadingHTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
