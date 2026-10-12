"""Configured anatomy image-pack lifecycle contracts with mocked NanoVG handles.

Does not validate generated pixels or native GPU uploads. The runtime and asset
configuration files are read-only; synthetic three-layer packs exist only in Lua.
"""
import argparse
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime

SETUP = """
package.path='scripts/?.lua;'..package.path
NVG_IMAGE_GENERATE_MIPMAPS=1
Assets=require('war.BodyLifeAssets')
B=require('war.BodyLife')
local keys={'source','tissue','foreground'}
function layerCount()
  local count=0
  for _,kind in ipairs(keys) do if Assets[kind] then count=count+1 end end
  return count
end
function threeLayers()
  for _,kind in ipairs(keys) do Assets[kind]='qa-fixture/'..kind..'.png' end
end
created,deleted,nextId=0,0,0
live={}
failKind=false;failContext=false;failValue=-1
function nvgCreateImage(vg,path)
  created=created+1
  if vg==failContext and path==Assets[failKind] then return failValue end
  nextId=nextId+1;live[nextId]=vg;return nextId
end
function nvgDeleteImage(vg,id)
  assert(type(id)=='number' and id>0,'invalid image handle deleted')
  assert(live[id]==vg,'image released twice or through another context')
  live[id]=nil;deleted=deleted+1
end
function liveCount()
  local count=0;for _ in pairs(live) do count=count+1 end;return count
end
function assertCleared(vg)
  assert(B.images[vg]==nil and B.packs[vg]==nil,'released pack retained')
end
function cacheAndRelease()
  local count=layerCount();assert(count>=1 and Assets.source,'source required')
  local a,b={},{}
  local first=B.prepare(a)
  assert(first>0 and B.prepare(a)==first,'same-context cache failed')
  assert(B.prepare(b)>0)
  assert(created==2*count and liveCount()==2*count,'configured layer count mismatch')
  for _,vg in ipairs({a,b}) do
    local pack=B.packs[vg]
    assert(pack.ready and #pack.ids==count)
    for _,kind in ipairs(keys) do
      if Assets[kind] then assert(pack[kind]>0 and live[pack[kind]]==vg) end
    end
  end
  B.release(a);B.release(a)
  assertCleared(a);assert(liveCount()==count,'other context was released')
  assert(B.prepare(b)>0 and created==2*count,'other context cache was lost')
  B.release(b);B.release(b)
  assertCleared(b);assert(deleted==2*count and liveCount()==0)
end
function missingLayer()
  local count=layerCount();local healthy,bad={},{}
  assert(B.prepare(healthy)>0)
  failContext=bad
  assert(B.prepare(bad)==-1,'partially loaded pack accepted')
  assert(B.images[bad]==-1 and not B.packs[bad].ready)
  assert(#B.packs[bad].ids==0,'partial successful images retained')
  assert(created==2*count and deleted==count-1)
  assert(liveCount()==count,'partial images leaked or healthy context lost')
  local g={bodyLifeEnabled=true,zoom=.03,realTime=.13}
  local state={anatomyVersion=4}
  assert(not B.ready(bad,g,state))
  assert(B.prepare(bad)==-1 and created==2*count,'failure retried during drawing')
  nvgSave=function() error('failed pack entered animated draw') end
  B.draw({vg=bad},g,state,1,2048,1,4096)
  B.perfusion({vg=bad},g,state,1,2048,1,4096)
  assert(created==2*count and liveCount()==count)
  B.release(bad);B.release(bad);assertCleared(bad)
  assert(deleted==count-1,'failed pack double-deleted partial handles')
  -- Explicit context release permits a later retry; a draw alone does not.
  failContext=false
  assert(B.prepare(bad)>0 and created==3*count)
  assert(B.prepare(healthy)>0 and created==3*count)
  B.release(bad);B.release(healthy)
  assertCleared(bad);assertCleared(healthy)
  assert(liveCount()==0 and deleted==3*count-1)
end
"""


def run():
    results = []
    def case(name, setup, action):
        lua = LuaRuntime(unpack_returned_tuples=True)
        try:
            lua.execute(SETUP)
            lua.execute(setup)
            configured = {kind: lua.globals().Assets[kind] for kind in ('source', 'tissue', 'foreground')}
            lua.execute(action)
            results.append({'name': name, 'pass': True, 'configuredLayers': sum(bool(v) for v in configured.values())})
        except Exception as error:
            results.append({'name': name, 'pass': False, 'error': str(error)})
    case('Current BodyLifeAssets count determines per-context loads and releases', '', 'cacheAndRelease()')
    case('Three-layer source/tissue/foreground packs cache and release independently', 'threeLayers()', 'cacheAndRelease()')
    for kind in ('source', 'tissue', 'foreground'):
        for value in ('nil', '0', '-1'):
            case(f'Missing {kind} ({value}) rejects pack, releases partial handles and keeps static fallback',
                 f"threeLayers();failKind='{kind}';failValue={value}", 'missingLayer()')
    return {'nativeEvidence': False, 'passed': sum(row['pass'] for row in results), 'total': len(results), 'results': results,
            'limitations': ['NanoVG image loading is mocked; generated image content and native GPU upload are not verified.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', help='Optional JSON report path; omitted means stdout only.')
    args = parser.parse_args()
    report = run()
    encoded = json.dumps(report, ensure_ascii=False, indent=2)+'\n'
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(encoded)
    print(encoded, end='')
    assert report['passed'] == report['total']


if __name__ == '__main__':
    main()
