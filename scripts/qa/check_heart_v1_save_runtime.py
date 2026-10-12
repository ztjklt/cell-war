"""Independent production-Lua save compatibility checks for the new heart.

Runs the actual Save/World/Commands/Collision modules offline. It neither
starts a preview nor substitutes test navigation geometry, and writes only
docs/heart-v1/qa. Native rendering and traversal are separate evidence.
"""
from pathlib import Path
import hashlib
import json
import os
import sys
import time

sys.path.insert(0, '/tmp/reference-map-tools')
import check_gastric_battlefield as support

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/heart-v1/qa/save-runtime-report.json'
MODULES = ['HeartBattlefield', 'HeartBattlefieldData', 'OrganBattlefield',
           'OrganBattlefieldCore', 'FullBodyBattlefield', 'OrganTrial', 'Save',
           'World', 'Vessels', 'Commands', 'CellCollision', 'Path', 'Data']


def main():
    os.chdir(ROOT)
    before = {name: hashlib.sha256((ROOT / f'scripts/war/{name}.lua').read_bytes()).hexdigest()
              for name in MODULES}
    started = time.perf_counter()
    lua = support.runtime()
    result = support.convert(lua.execute(r'''
      local F,O,W,C,Save,H,U=require('war.FullBodyBattlefield'),require('war.OrganBattlefield'),
        require('war.World'),require('war.Commands'),require('war.Save'),require('war.HeartBattlefield'),require('war.Util')
      local checks={};local out={checks=checks}
      local function check(name,pass,detail)checks[#checks+1]={name=name,passed=not not pass,detail=detail}end
      local function point(spec)
        if spec.centerSource then return spec.centerSource end
        local a,b=spec.points[1],spec.points[#spec.points]
        return {(a[1]+b[1])*.5,(a[2]+b[2])*.5}
      end
      local s=F.new(73);s.entities={};W.rebuild(s)
      check('opted-in graph has 210 edges while global graph stays 202',#O.net(s).edges==210 and #W.vessels(s).edges==202)
      local fixtures={}
      for _,spec in ipairs(H.data.chambers)do fixtures[#fixtures+1]=spec end
      for _,spec in ipairs(H.data.valves)do fixtures[#fixtures+1]=spec end
      local saved={}
      for _,spec in ipairs(fixtures)do
        local p=point(spec);local e=assert(C.spawn(s,'unit','siege',1,p[1]*2,p[2]*2+512))
        e.vesselLane=spec.laneIndex
        check(spec.id..' siege fixture physically legal',O.pointAllowed(s,e,e.x,e.y,e.vesselLane),{id=e.id,lane=e.vesselLane,x=e.x,y=e.y})
        saved[e.id]={id=spec.id,lane=e.vesselLane,x=e.x,y=e.y}
      end
      local snap=Save.snapshot(s)
      check('new heart version serialized',snap.heartBattlefieldVersion==1 and snap.fullbodyBattlefieldVersion==1)
      local ok,restored=pcall(Save.restore,snap)
      check('all four chambers and four valves survive production restore',ok,not ok and tostring(restored)or nil)
      if ok then
        for id,record in pairs(saved)do
          local e=restored.entities[id]
          check(record.id..' lane and legal position roundtrip',e and e.vesselLane==record.lane
            and O.pointAllowed(restored,e,e.x,e.y,e.vesselLane)
            and math.abs(e.x-record.x)<1e-6 and math.abs(e.y-record.y)<1e-6,
            e and {lane=e.vesselLane,x=e.x,y=e.y}or nil)
        end
      end
      -- Use genuine old heart-floor and old right-heart coordinates, then remove
      -- only the new revision marker so Save exercises its legacy migration.
      s.entities={};W.rebuild(s)
      local oldTissue={515.5400588235294,387.3726538461538}
      local a=assert(C.spawn(s,'unit','scout',1,994,1276))
      a.x,a.y,a.vesselLane=oldTissue[1]*2,oldTissue[2]*2+512,0
      a.orders={{kind='move',x=990,y=1260}};a.path={{x=990,y=1260,lane=0}}
      local b=assert(C.spawn(s,'unit','scout',1,998,1364))
      b.x,b.y,b.vesselLane=493*2,414*2+512,2
      local lung=O.organ('lung_r').rooms[1].centerSource
      local c=assert(C.spawn(s,'unit','scout',1,lung[1]*2,lung[2]*2+512))
      local unaffected={x=c.x,y=c.y,lane=c.vesselLane}
      local old=Save.snapshot(s);old.heartBattlefieldVersion=nil;old.heartEncounterVersion=nil
      local migratedOK,migrated=pcall(Save.restore,old)
      check('earlier full-body save restores under new heart',migratedOK,not migratedOK and tostring(migrated)or nil)
      if migratedOK then
        for _,id in ipairs({a.id,b.id})do local e=migrated.entities[id]
          check('legacy heart entity '..id..' resolves to certified compartment',e and O.pointAllowed(migrated,e,e.x,e.y,e.vesselLane),
            e and {lane=e.vesselLane,x=e.x,y=e.y,orders=#e.orders}or nil)
        end
        local e=migrated.entities[c.id]
        check('unaffected lung entity position and lane retained',e and e.x==unaffected.x and e.y==unaffected.y and e.vesselLane==unaffected.lane)
      end
      for _,version in ipairs({1,2,3,4})do
        local legacy=W.generate(73,nil,nil,'sandbox',version)
        local legacySnap=Save.snapshot(legacy)
        local legacyOK,r=pcall(Save.restore,legacySnap)
        check('ordinary sandbox anatomy '..version..' remains outside new heart',legacyOK and not H.enabled(r)
          and r.heartBattlefieldVersion==nil and r.organBattlefieldVersion==nil and r.fullbodyBattlefieldVersion==nil,
          not legacyOK and tostring(r)or nil)
      end
      -- Updated lanes must project to the newly installed segments, rather than
      -- the frozen baseline path retained for non-heart anatomy states.
      local net=O.net(s)
      for lane,spec in pairs(H.data.edgeUpdates)do
        local largest=0
        for _,p in ipairs(spec.points)do
          local distance=net.distance(lane,p[1]*2,p[2]*2+512)
          largest=math.max(largest,distance)
        end
        check('local edge '..lane..' distance uses new registered path',largest<1e-8,{maxDistanceWorld=largest})
      end
      return out
    '''))
    after = {name: hashlib.sha256((ROOT / f'scripts/war/{name}.lua').read_bytes()).hexdigest()
             for name in MODULES}
    stable = before == after
    result.update(schema='heart-v1-independent-save-runtime-qa/v1', nativeEvidence=False,
                  runtimeHashes=before, productionModulesStableDuringRun=stable,
                  elapsedOfflineSeconds=round(time.perf_counter() - started, 3))
    result['passed'] = sum(row['passed'] for row in result['checks'])
    result['total'] = len(result['checks'])
    result['status'] = 'STALE' if not stable else 'PASS' if result['passed'] == result['total'] else 'FAIL'
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'passed', 'total', 'elapsedOfflineSeconds', 'productionModulesStableDuringRun']}
                     | {'failures': [row for row in result['checks'] if not row['passed']],
                        'report': str(OUT.relative_to(ROOT))}, ensure_ascii=False), flush=True)
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
