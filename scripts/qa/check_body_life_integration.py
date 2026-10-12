"""Offline render/state contracts. No native window, seam or frame-time claim."""
import argparse
import io
import json
import tempfile
from pathlib import Path
from PIL import Image
import body_life_backend as b
from render_body_life import initialise


def pixel(x=4, y=4, dpr=1):
    return Image.open(io.BytesIO(b.png(16, 16, dpr))).convert('RGBA').getpixel((x*dpr, y*dpr))


def square(paint):
    b.begin(); b.rect(None, 0, 0, 16, 16); b.setfill(None, paint); b.fill_path()


def backdrop():
    b.reset(); square(b.color(255, 255, 255))


def near(actual, expected, tolerance=2):
    assert all(abs(a-e) <= tolerance for a, e in zip(actual, expected)), (actual, expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='docs/body-life/integration-results.json')
    args = parser.parse_args()
    results = []
    def check(name, function):
        try:
            function(); results.append({'name': name, 'pass': True})
        except Exception as error:
            results.append({'name': name, 'pass': False, 'error': str(error)})

    def alpha_check():
        backdrop(); b.global_alpha(None, .5); square(b.color(255, 0, 0, 128))
        near(pixel(), (255, 191, 191, 255))
        b.save(); b.global_alpha(None, 0); b.restore()
        assert b.alpha == .5
    check('RGBA alpha multiplies global alpha, saved state restores alpha', alpha_check)

    def texture_check():
        with tempfile.TemporaryDirectory() as folder:
            a, c = Path(folder)/'a.png', Path(folder)/'c.png'
            Image.new('RGBA', (2, 2), (200, 100, 50, 128)).save(a)
            Image.new('RGBA', (2, 2), (0, 220, 0, 255)).save(c)
            before = len(b.decoded_images)
            i, j, k = b.create_image(None, str(a)), b.create_image(None, str(c)), b.create_image(None, str(a))
            assert len({i, j, k}) == 3 and len(b.decoded_images) == before+2
            backdrop(); b.global_alpha(None, .5)
            square(b.tinted_pattern(None, 0, 0, 16, 16, 0, i, b.color(128, 255, 255, 128)))
            near(pixel(), (235, 235, 229, 255), 3)
            square(b.image_pattern(None, 0, 0, 16, 16, 0, k, 1))
            square(b.image_pattern(None, 0, 0, 16, 16, 0, k, 1))
            assert sum(item.startswith('<image') for item in b.defs) == 2
            backdrop(); b.global_alpha(None, .5)
            b.G.qaTintHandle = i
            b.l.execute('local c=nvgRGBA(128,255,255,128);nvgBeginPath(nil);nvgRect(nil,0,0,16,16);nvgFillPaint(nil,nvgImagePatternTinted(nil,0,0,16,16,0,qaTintHandle,c));nvgFill(nil)')
            near(pixel(), (235, 235, 229, 255), 3)
            b.delete_image(None, i); b.delete_image(None, j); b.delete_image(None, k)
            assert all(handle not in b.image_handles for handle in (i, j, k))
            assert b.create_image(None, str(a)+'.missing') == 0
    check('Multiple image handles, decoded image reuse, tint alpha and deletion', texture_check)

    def matrix_check():
        for dpr in (1, 2, 3):
            backdrop(); b.save(); b.transform('matrix', 1, 0, .5, 1, 4, 2)
            b.begin(); b.rect(None, 0, 0, 4, 4); b.setfill(None, b.color(255, 0, 0)); b.fill_path(); b.restore()
            near(pixel(7, 4, dpr), (255, 0, 0, 255))
            near(pixel(2, 4, dpr), (255, 255, 255, 255))
    check('Affine translation/shear use logical coordinates at DPR 1/2/3', matrix_check)

    def hole_check():
        backdrop(); b.begin(); b.rect(None, 1, 1, 14, 14)
        b.path_winding(None, b.G.NVG_SOLID)
        b.rect(None, 5, 5, 6, 6); b.path_winding(None, b.G.NVG_HOLE)
        b.setfill(None, b.color(255, 0, 0)); b.fill_path()
        near(pixel(3, 3), (255, 0, 0, 255))
        near(pixel(8, 8), (255, 255, 255, 255))
        backdrop(); square(b.G.nvgRGBAf(1, 0, 0, .02))
        near(pixel(), (255, 250, 250, 255))
    check('Nested mask holes stay empty and RGBAf retains low-amplitude alpha', hole_check)

    initialise()
    b.l.execute('''
    function deepEqual(a,b)
      if type(a)~=type(b) then return false end
      if type(a)~='table' then return a==b end
      for k,v in pairs(a) do if not deepEqual(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    Save=require('war.Save');U=require('war.Util');B=require('war.BodyLife')
    beforeSnapshot=Save.snapshot(state); beforeVisible=U.copy(state.factions[1].visible)
    ''')
    def render_contract():
        for dpr in (1, 2, 3):
            for enabled in ('false', 'true'):
                b.reset()
                b.l.execute(f'''graphics={{GetWidth=function() return {720*dpr} end,GetHeight=function() return {600*dpr} end,GetDPR=function() return {dpr} end}}
                game.bodyLifeEnabled={enabled};game.camera={{x=1024,y=1300}};game.zoom=.027;game.realTime=1.92;R.draw(game)
                assert(R.w==720 and R.h==600)
                local x,y=R.project(game,1024,1300);local wx,wy=R.unproject(game,x,y)
                assert(math.abs(wx-1024)<1e-8 and math.abs(wy-1300)<1e-8)
                assert(deepEqual(beforeSnapshot,Save.snapshot(state)))
                assert(deepEqual(beforeVisible,state.factions[1].visible))
                assert(B.last.triangles<=384)
                ''')
        # Advance only visual time, as paused/modal views do; no simulation update is called.
        for t in (0, .13, 1.92, 8, 15):
            b.reset()
            b.l.execute(f'''game.realTime={t};game.zoom=.11;R.draw(game)
                require('war.SmoothTerrain').overview(R,state,0,0,720,600,true,{t})
                assert(deepEqual(beforeSnapshot,Save.snapshot(state)))
                assert(deepEqual(beforeVisible,state.factions[1].visible))''')
    check('World/overview browsing leaves Save snapshot, RNG, visibility and projection unchanged', render_contract)

    def pause_and_phase_check():
        b.reset()
        b.l.execute("""
        local draw=B.draw;local observations={};local times={}
        B.draw=function(renderer,g,s,...)
          observations[#observations+1]=B.sample(g.realTime,'heart')
          times[#times+1]=g.realTime
          return draw(renderer,g,s,...)
        end
        local ok,err=pcall(function()
          game.paused=true;local simulationTime=state.time
          for _,speed in ipairs({1,2}) do
            game.speed=speed
            for _,t in ipairs({0,.13,1.92,4.8}) do
              game.realTime=t;game.zoom=.027
              observations={};times={};R.draw(game)
              assert(#observations>0 and times[1]==t)
              local worldPhase=observations[1]
              observations={};times={}
              require('war.SmoothTerrain').overview(R,state,0,0,720,600,true,t)
              assert(#observations>0 and times[1]==t)
              assert(worldPhase.beat==observations[1].beat and worldPhase.breath==observations[1].breath)
              assert(state.time==simulationTime and deepEqual(beforeSnapshot,Save.snapshot(state)))
            end
          end
          assert(B.sample(0,'heart').beat~=B.sample(.13,'heart').beat)
        end)
        B.draw=draw;game.paused=false;game.speed=1
        assert(ok,err)
        """)
    check('Paused visual draws preserve simulation; world/map phase agrees at 1x/2x', pause_and_phase_check)

    def sandbox_map_check():
        b.reset()
        b.l.execute("""
        assert(not state.campaign and state.anatomyVersion==4,'sandbox fixture required')
        local UI=require('urhox-libs/UI');local oldUi={}
        local keys={'Panel','Label','Button','ScrollView','GetViewportSize'}
        for _,k in ipairs(keys)do oldUi[k]=UI[k]end
        local function widget(props)
          local w={props=props or {},children={}}
          function w:GetAbsoluteLayout()return {x=0,y=0,w=720,h=600}end
          function w:AddChild(child)self.children[#self.children+1]=child end
          function w:RemoveAllChildren()self.children={}end
          function w:SetVisible(value)self.visible=value end
          function w:SetText(value)self.props.text=value end
          function w:SetStyle(value)end
          function w:Animate(value)end
          return w
        end
        UI.Panel=widget;UI.Label=widget;UI.Button=widget;UI.ScrollView=widget;UI.GetViewportSize=function()return 720,600 end
        local H=require('war.HUD');local oldRefs=H.refs;H.refs={modal=widget()}
        local art=require('war.ReferenceArt');local detail,draw=art.details,art.draw
        local S=require('war.SmoothTerrain');local overview=S.overview;local minimap=R.minimap
        local details,miniObserved,allObserved,argsSeen=0,nil,nil,nil
        art.details=function(...)details=details+1;return detail(...)end
        art.draw=function(renderer,g,...)miniObserved=g.bodyLifeMini;return draw(renderer,g,...)end
        S.overview=function(renderer,s,x,y,w,h,all,t,mini)allObserved=all;return overview(renderer,s,x,y,w,h,all,t,mini)end
        R.minimap=function(vg,g,l,all,mini)argsSeen={all=all,mini=mini};return minimap(vg,g,l,all,mini)end
        local snap=Save.snapshot(state);local visible=U.copy(state.factions[1].visible);local seen=U.copy(state.factions[1].seen);local oldFog=game.fogDisabled
        local ok,err=pcall(function()
          game.fogDisabled=false;H.mapMenu(game);H.refs.fullMap:Render(R.vg)
          assert(argsSeen.all==false and argsSeen.mini==false,'HUD sandbox fullMap lost explicit full-detail flag')
          assert(details==1 and miniObserved==false and allObserved==false,'sandbox fullMap used mini detail or revealed map')
          local layout={x=0,y=0,w=720,h=600}
          for _,case in ipairs({{overview='nil',mini=true},{overview=false,mini=false},{overview=true,mini=false}})do
            details=0;miniObserved=nil;allObserved=nil
            if case.overview=='nil'then minimap(R.vg,game,layout)else minimap(R.vg,game,layout,case.overview)end
            assert(miniObserved==case.mini,'legacy/explicit overview detail compatibility')
            assert(details==(case.mini and 0 or 1),'full details entry was skipped')
            assert(allObserved==(case.overview==true),'fog mode coupled to detail selection')
          end
          assert(deepEqual(snap,Save.snapshot(state)) and deepEqual(visible,state.factions[1].visible) and deepEqual(seen,state.factions[1].seen))
          assert(game.fogDisabled==false,'full map changed fog preference')
        end)
        R.minimap=minimap;S.overview=overview;art.details=detail;art.draw=draw;H.closeModal(game);H.refs=oldRefs;game.fogDisabled=oldFog
        for _,k in ipairs(keys)do UI[k]=oldUi[k]end
        assert(ok,err)
        """)
    check('Actual sandbox HUD fullMap uses full anatomy while keeping fog/visibility and legacy mini defaults', sandbox_map_check)

    def legacy_check():
        b.reset()
        b.l.execute("""
        local old=game.state;local oldvg=R.vg;local prepare=B.prepare
        local create=nvgCreateImage;local currentReference=require('war.ReferenceMap').reference
        B.prepare=function() error('v3 requested body-life resources') end
        nvgCreateImage=function(vg,path,flags)
          assert(path~=currentReference and not path:find('body%-life'),path)
          return create(vg,path,flags)
        end
        local ok,err=pcall(function()
          local legacy=require('war.World').generate(73,false,'body','sandbox',3)
          require('war.World').rebuild(legacy)
          assert(require('war.ReferenceMaps').art(legacy)==require('war.LegacyReferenceArtV3'))
          R.vg={};game.state=legacy;game.zoom=.005;R.prepare(legacy)
          R.draw(game)
          require('war.SmoothTerrain').overview(R,legacy,0,0,720,600,true,1.92)
          require('war.LegacyReferenceArtV3').release(R.vg)
        end)
        game.state=old;R.vg=oldvg;B.prepare=prepare;nvgCreateImage=create;R.prepare(old)
        assert(ok,err)
        """)
    check('Anatomy v3 retains legacy renderer and never requests new resources', legacy_check)

    def handles_check():
        # Repeated map rendering must reuse cached images until their owning context closes.
        baseline = len(b.image_handles)
        for _ in range(6):
            b.reset(); b.l.execute("require('war.SmoothTerrain').overview(R,state,0,0,720,600,true,1.92)")
        assert len(b.image_handles) == baseline, (baseline, len(b.image_handles))
        b.l.execute('R.close()')
        assert not b.image_handles, f'Unreleased image handles: {list(b.image_handles)}'
    # R.close also tears down other renderer resources, which are irrelevant to image caching.
    b.G.nvgDelete = lambda *_: None
    check('Repeated map views do not grow live image handles', handles_check)
    report = {'nativeEvidence': False, 'passed': sum(row['pass'] for row in results), 'total': len(results), 'results': results,
              'limitations': ['Does not prove native seams, frame time, UI pause wiring or scene readability.', 'Cairo edge coverage and image filtering differ from NanoVG.']}
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    assert report['passed'] == report['total']


if __name__ == '__main__':
    main()
