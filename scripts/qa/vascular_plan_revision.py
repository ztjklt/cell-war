"""V2 design constraints for the source-locked circulation drawing.

Widths and layers below are explicit GAME AUTHORING decisions, not measurements
of human vessels. Runtime navigation and anatomy illustration are unchanged.
"""
import math


def distance(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1];den=dx*dx+dy*dy
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den)) if den else 0
    q=(a[0]+dx*t,a[1]+dy*t)
    return math.dist(p,q),q


def intersect(a,b,c,d):
    rx,ry=b[0]-a[0],b[1]-a[1];sx,sy=d[0]-c[0],d[1]-c[1]
    cross=rx*sy-ry*sx
    if abs(cross)<1e-9:return None
    qx,qy=c[0]-a[0],c[1]-a[1]
    t=(qx*sy-qy*sx)/cross;u=(qx*ry-qy*rx)/cross
    return (a[0]+rx*t,a[1]+ry*t) if -1e-8<=t<=1+1e-8 and -1e-8<=u<=1+1e-8 else None


def revise(nodes,edges,organs,source_organs):
    regions={o['id']:[(p[0]/2,(p[1]-512)/2) for p in o['points']] for o in source_organs}
    def xy(k):return [nodes[k]['x'],nodes[k]['y']]
    def add_node(k,p,label,role='junction',**kw):
        nodes[k]=dict(id=k,x=p[0],y=p[1],label=label,role=role,**kw)
    def add(a,b,kind,via=(),group='systemic',label=''):
        e=dict(a=a,b=b,kind=kind,points=[xy(a),*[list(p) for p in via],xy(b)],
               status='revise',group=group,label=label or a+' → '+b)
        edges.append(e);return e
    def delete(a,b):
        edges[:]=[e for e in edges if not(e['a']==a and e['b']==b)]
    def move(k,p):
        nodes[k]['x'],nodes[k]['y']=p
        for e in edges:
            if e['a']==k:e['points'][0]=list(p)
            if e['b']==k:e['points'][-1]=list(p)
    def rewrite(a,b,via):
        e=next(e for e in edges if e['a']==a and e['b']==b)
        e.update(points=[xy(a),*[list(p) for p in via],xy(b)],status='revise')

    # Separate common root and neck-root branch hierarchy from shoulder routes.
    add_node('aortic_root',(533,375),'主动脉根部')
    delete('left_heart','arch');delete('left_heart','coronary.a')
    add('left_heart','aortic_root','artery',[(548,397)],group='heart')
    add('aortic_root','arch','artery',[(529,353)],group='heart')
    add('aortic_root','coronary.a','artery',[(540,390)],group='heart')
    add_node('brachiocephalic',(495,300),'头臂干分叉')
    add_node('carotid_l',(525,291),'左颈总动脉根')
    add_node('subclavian_l',(549,291),'左锁骨下动脉根')
    for side in ['r','l']:
        delete('arch',f'shoulder_{side}.a');delete(f'shoulder_{side}.a',f'head_{side}.a')
    add('arch','brachiocephalic','artery',[(503,325)],group='head')
    add('brachiocephalic','head_r.a','artery',[(479,254),(480,191)],group='head')
    add('brachiocephalic','shoulder_r.a','artery',[(467,280),(442,278)],group='head')
    add('arch','carotid_l','artery',[(518,319)],group='head')
    add('carotid_l','head_l.a','artery',[(539,253),(539,191)],group='head')
    add('arch','subclavian_l','artery',[(534,321)],group='head')
    add('subclavian_l','shoulder_l.a','artery',[(577,278)],group='head')

    # Resolve non-junction paths passing exactly through other vessel nodes.
    for side,old,new in [('r',[292,555],[305,551]),('l',[726,555],[713,551])]:
        e=next(e for e in edges if e['a']==f'shoulder_{side}.a' and e['b']==f'wrist_{side}.a')
        e['points']=[new if p==old else p for p in e['points']];e['status']='revise'
    rewrite('bladder.a','bladder.v',[(525,775),(505,780)])
    # The source graph puts the right lower-leg vein exactly on the artery for
    # 45 source pixels. Give the return its own explicit corridor in this plan.
    calf=next(e for e in edges if e['a']=='foot_r.v' and e['b']=='calffork_r.v')
    calf['points']=[[393,p[1]] if p in ([399,1210],[399,1265]) else p for p in calf['points']]
    calf['status']='revise'

    # Separate cerebral internal venules from neck return endpoints.
    for side,p in [('r',(486,103)),('l',(537,103))]:
        old_out=f'head_{side}.v';new_out=f'brain_{side}.v'
        add_node(new_out,p,'脑内回流区','exchange_out')
        delete('brain_'+side,old_out)
        add('brain_'+side,new_out,'exchange',group='head')
        add(new_out,old_out,'vein',group='head')
        next(o for o in organs if o['id']=='brain_'+side)['outlet']=new_out

    # Protected stomach outlet stays clear of the portal confluence.
    move('portal',(523,561));nodes['portal']['label']='肝门静脉汇流'
    add_node('mesenteric_vein',(530,620),'肠系膜上静脉汇流')
    add_node('hindgut_vein',(555,632),'肠系膜下静脉汇流')
    add_node('pancreatic_venous_group',(528,571),'胰/胃周静脉汇流组（合并）')
    for a,target,via in [
        ('stomach.v','portal',[(552,547),(537,553)]),
        ('pancreas.v','pancreatic_venous_group',[(512,573)]),
        ('small_intestine.v','mesenteric_vein',[(548,663)]),
        ('colon_proximal.v','mesenteric_vein',[(475,719),(484,664),(508,637)]),
        ('colon_distal.v','hindgut_vein',[(586,718),(596,678),(577,646)]),
    ]:
        delete(a,'portal');add(a,target,'portal',via,group='portal')
    add('mesenteric_vein','portal','portal',[(533,589)],group='portal')
    add('hindgut_vein','pancreatic_venous_group','portal',[(563,607),(544,587)],group='portal')
    add('pancreatic_venous_group','portal','portal',group='portal')
    rewrite('portal','liver.p',[(523,540)])

    # These hints are projected to the CURRENT map's exact authoring polygon.
    # They are fixed game design ports, not medical pixel coordinates or final masks.
    hints={
      'lung_r':('lung_r',(475,374),(472,411)),
      'lung_l':('lung_l',(542,374),(545,414)),
      'kidney_r':('kidney_r',(440,605),(435,618)),
      'kidney_l':('kidney_l',(586,610),(584,619)),
      'stomach':('stomach',(548,502),(539,520)),
      'pancreas':('pancreas',(550,575),(505,601)),
      'small_intestine':('small_intestine',(483,656),(546,666)),
      'colon_proximal':('large_intestine',(458,674),(464,706)),
      'colon_distal':('large_intestine',(559,665),(552,709)),
      'bladder':('bladder',(536,751),(480,755)),
      'coronary':('heart',(542,384),(488,434)),
      'brain_r':('brain',(485,113),(499,106)),
      'brain_l':('brain',(534,113),(551,114)),
      'liver':('liver',(521,510),(474,476)),
    }
    def gate(key,region,hint,flow):
        p=regions[region]
        _,q=min((distance(hint,a,b) for a,b in zip(p,p[1:]+p[:1])),key=lambda v:v[0])
        add_node(key,q,region+('供血设计口' if flow=='in' else '回流设计口'),
                 'organ_gate',region=region,flow=flow,placementBasis='projected to v4 authored contour',
                 anatomicalPrecision='game abstraction',junctionPolicy='same node id only')
        return key
    for o in organs:
        k=o['id'];inlet=o['inlet'];outlet=o['outlet']
        nodes[inlet]['role']='exchange_in';nodes[outlet]['role']='exchange_out'
        if k not in hints:
            # Arms/legs/trunk are regional tissue beds, not standalone organ walls.
            o['entryGate']=inlet;o['exitGate']=outlet
            o['interfaceType']='regional_tissue_bed'
        else:
            region,ah,vh=hints[k]
            ent=gate(k+'.entry',region,ah,'in');ext=gate(k+'.exit',region,vh,'out')
            incoming=[e for e in edges if e['b']==inlet and e['kind'] in {'artery','pulmonary_artery'}]
            outgoing=[e for e in edges if e['a']==outlet and e['kind'] in {'vein','portal','pulmonary_vein'}]
            for e in incoming:e.update(b=ent,points=e['points'][:-1]+[xy(ent)],status='revise')
            for e in outgoing:e.update(a=ext,points=[xy(ext)]+e['points'][1:],status='revise')
            if incoming:add(ent,inlet,incoming[0]['kind'],group='organ_internal')
            if outgoing:add(outlet,ext,outgoing[0]['kind'],group='organ_internal')
            o.update(entryGate=ent,exitGate=ext,interfaceType='organ_boundary',region=region)
            if k=='liver':
                g=gate('liver.portal_entry',region,(510,521),'in')
                e=next(e for e in edges if e['a']=='portal' and e['b']=='liver.p')
                e.update(b=g,points=e['points'][:-1]+[xy(g)])
                add(g,'liver.p','portal',group='organ_internal')
                o['secondaryEntryGate']=g
        # Explicit blood-to-tissue access declaration, independent of vessel mouth.
        p=xy(inlet)
        o['tissueAccess']=dict(id=k+'.tissue_access',source=p,region=o.get('region',k),
            lumenNode=inlet,kind='controlled_extravasation',designWidthSource=1.5,
            allowedAgents=['immune_cell'],nutrientExchange=True,
            foodPassage=False,automaticBloodCellEscape=False,runtimeStatus='not implemented')

    # Local routing at the hilum avoids drawing a peripheral organ point as the mouth.
    for a,b,via in [
        ('pulmonary_trunk','lung_r.entry',[(493,359)]),
        ('pulmonary_trunk','lung_l.entry',[(531,359)]),
        ('lung_r.exit','left_heart',[(488,435),(521,446)]),
        ('lung_l.exit','left_heart',[(551,435)]),
        ('aorta_mid','kidney_r.entry',[(476,597)]),
        ('aorta_mid','kidney_l.entry',[(559,599)]),
        ('kidney_r.exit','cava_abdominal',[(456,621)]),
        ('kidney_l.exit','cava_abdominal',[(542,632)]),
        ('brain_r.exit','head_r.v',[(495,127)]),
        ('brain_l.exit','head_l.v',[(530,131)]),
    ]:rewrite(a,b,via)

    # Design widths are full luminal widths in original-source pixels. They do
    # not claim that unchanged runtime navigation now has these corridors.
    for i,e in enumerate(edges,1):
        e['id']=f'e{i:03}'
        if e['group']=='systemic':width,layer=7.0,10 if e['kind']=='artery' else 20
        elif e['group']=='pulmonary':width,layer=4.0,30
        elif e['group']=='portal':width,layer=3.0,15
        elif e['group']=='limbs':width,layer=3.0,50 if e['kind']=='artery' else 55
        elif e['group']=='organ_internal' or e['kind']=='exchange':width,layer=2.0,60
        else:width,layer=3.0,25
        if 'finger' in e['a'] or 'toe' in e['a']:width=1.5
        e.update(lumenWidthSource=width,layer=layer,drawOrder=layer*1000+i,
            depth='designed projection layer',visibilityPolicy='xray_schematic' if layer<40 else 'local_tissue_schematic',
            widthBasis='game authoring proposal, not measured anatomy',
            movementPolicy=dict(bloodDirection='a_to_b',immuneCells='bidirectional_in_lumen',
                leaveVessel='declared_tissue_access_only',food=False),
            renderingWidthSource=1.6 if width<3 else 2.2)
    crossings=[];junction_regions=[]
    for i,e in enumerate(edges):
        for f in edges[i+1:]:
            shared={e['a'],e['b']}&{f['a'],f['b']};points=set()
            for a,b in zip(e['points'],e['points'][1:]):
                for c,d in zip(f['points'],f['points'][1:]):
                    p=intersect(a,b,c,d)
                    if p and not any(math.dist(p,xy(k))<1e-5 for k in shared):points.add(tuple(round(v,4) for v in p))
            over,under=(e,f) if e['drawOrder']>f['drawOrder'] else (f,e)
            for p in sorted(points):
                # Match the production join neighbourhood in SOURCE coordinates:
                # world radius=max(full world lumen width)/2+1, then divide by 2.
                radius=max(e['lumenWidthSource'],f['lumenWidthSource'])/2+.5
                joint=next((k for k in sorted(shared) if math.dist(p,xy(k))<radius),None)
                if joint:
                    junction_regions.append(dict(edges=[e['id'],f['id']],point=p,node=joint,
                        radiusSource=radius,connected=True,basis='shared node within runtime junction radius'))
                else:
                    crossings.append(dict(over=over['id'],under=under['id'],point=p,
                        gapRadius=over['renderingWidthSource']/2+1.5,connected=False,
                        basis='explicit schematic overpass; not anatomical depth measurement'))
    protected=[dict(id='gastric_entry',center=[543,464],radius=6,system='digestive'),
               dict(id='gastric_exit',center=[495,552],radius=6,system='digestive'),
               dict(id='urinary_outlet',center=[508,810],radius=5,system='urinary')]
    protected_cross=[]
    for e in edges:
        for z in protected:
            if any(distance(z['center'],a,b)[0] < z['radius']+e['lumenWidthSource']/2 for a,b in zip(e['points'],e['points'][1:])):
                protected_cross.append(dict(edge=e['id'],zone=z['id'],mode='behind_protected_nonvascular_space',
                    connected=False,clipCenter=z['center'],clipRadius=z['radius']+e['renderingWidthSource']/2+1,
                    nodePlacement='no junction inside protected zone'))
    # Gate glyphs replace indiscriminate circles at internal bed points.
    for k,n in nodes.items():
        n.setdefault('role','junction')
        n['junctionPolicy']='same node id only'
    return dict(crossings=crossings,junctionRegions=junction_regions,protectedZones=protected,protectedCrossings=protected_cross,
        sourceCoordinateSystem='original 1024x1536; world=(2*x,2*y+512)',
        scope='circulation and organ-interface design baseline; not runtime implementation',
        layerPolicy='larger drawOrder is above; lower path clipped at every listed crossing',
        organOcclusion='deep paths are shown as xray only; final organ masks belong to local battlefield rendering',
        gameplayAcceptance='requires later integration and real-unit tests; no native claim')
