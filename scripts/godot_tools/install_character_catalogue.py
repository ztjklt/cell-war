#!/usr/bin/env python3
"""Install the authored character gallery, without changing battle configuration.

Copies selected original PNGs byte-for-byte and freezes frame rectangles/timing.
The game consumes only resources inside godot/. Run again after approved art edits.
"""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

from install_medicine_catalogue import build_entries as build_medicine_entries

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'godot'


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def dendritic_copy():
    """Project current reconnaissance balance into gallery copy, not battle rules."""
    scan = read(GAME / 'data/dendritic_cell.json')['scan']
    movement_reduction = (1 - scan['moveMultiplier']) * 100
    attack_reduction = (1 - scan['attackSpeedMultiplier']) * 100
    return dict(
        status='现役单位', kind='dendritic_cell',
        runtimeDefinition='res://data/dendritic_cell.json',
        note='半径与减速幅度为当前首轮平衡值。标记地下目标不会强制出土；疱疹自动埋伏仍待接入。',
        mechanics=[
            '静止侦察可标记同通行层、无遮挡的敌方单位，包括带有地下或隐蔽状态的目标。',
            f"当前侦察半径为 {scan['radius']:g} 地图单位；被标记敌人的移动速度降低 {movement_reduction:g}%、攻击速度降低 {attack_reduction:g}%，多只不叠乘。",
            '自身不攻击；移动、受击或死亡会中断侦察。保留 6 帧依次亮灯技能。'])


def t_cell_copy():
    """Reflect reviewed runtime activation while retaining the approved actions."""
    runtime = read(GAME / 'data/t_cell.json')
    registered = 't_cell' in read(GAME / 'data/config.json')['Data']['units']
    if not runtime.get('runtimeIntegrated') or not registered:
        return dict(status='动作预览', kind='',
                    summary='戴着忍者面罩的绿色细胞，瞬身前进、投掷小刀。',
                    mechanics=['已制作带长残影的瞬身前进、投刀、受击和侧倒死亡动作。',
                               '瞬身距离、投刀伤害、攻击间隔与目标规则尚未接入战斗。'],
                    note='这里展示已制作动作，尚无可部署的 T细胞单位。')
    unit, weapon = runtime['unitDefinition'], runtime['weapon']
    return dict(status='现役单位', kind='t_cell',
                runtimeDefinition='res://data/t_cell.json',
                summary='沿合法通路瞬身前进，以独立飞行的小刀攻击敌人。',
                mechanics=[
                    f"升至 {unit['tier']} 级后，可由骨髓造血巢训练；瞬身替代行走，地图中的残影记录真实经过位置。",
                    '每轮按普通移动速度分配瞬身距离；遵守组织墙、落点净空及真实关口，投影交叉不连通。',
                    f"小刀前摇 {weapon['windup']:g} 秒后出手，射程 {weapon['range']:g}、伤害 {weapon['damage']:g}；按固定方向飞行。",
                    '受击打断未出手攻击，已出手的小刀继续飞行；B细胞、脑指挥和侦查双减速作用于实际节奏。'],
                note='当前数值为首轮平衡值；瞬身、投刀与死亡状态随本地存档恢复。')


def main():
    config = read(GAME / 'data/config.json')
    manifest = {r['path']: r for r in read(GAME / 'data/asset_manifest.json')}
    entries = []

    def install(source):
        assert source.is_file(), source
        relative = source.relative_to(ROOT).as_posix()
        target = GAME / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != source.read_bytes():
            shutil.copy2(source, target)
        manifest[relative] = dict(source=relative, path=relative,
                                  bytes=target.stat().st_size,
                                  sha256=hashlib.sha256(target.read_bytes()).hexdigest())
        return 'res://' + relative

    def add(id, name, category, role, folder='', portrait='', status='现役单位',
            summary='', mechanics=(), note='', kind='', actions=None):
        base = ROOT / 'assets/image' / folder
        e = dict(id=id, name=name, category=category, role=role, status=status,
                 summary=summary, mechanics=list(mechanics), note=note,
                 kind=kind, actions=[], sources=[])
        if folder and (base / 'animations.json').exists():
            document = read(base / 'animations.json')
            e['sources'].append((base / 'animations.json').relative_to(ROOT).as_posix())
            if not portrait:
                portrait = document.get('portrait', document.get('baseCharacter', ''))
            if actions is None:
                actions = [(label, value) for label, value in document.items()
                           if isinstance(value, str) and value.endswith('.json')
                           and (base / value).exists() and 'frames' in read(base / value)]
        e['portrait'] = install(base / portrait)
        aliases = {'walk': '空载行走', 'oxygen': '携氧行走', 'glucose': '携糖行走',
                   'build': '建造', 'hit': '受击', 'death': '死亡', 'move': '移动',
                   'shoot': '发射颗粒', 'projectileFlight': '独立颗粒弹'}
        for label, relative in actions or []:
            doc_path = base / relative
            doc = read(doc_path)
            # Portrait-only references are deliberately excluded from the animation list.
            frames = [dict(rect=[f['rect'][k] for k in ['x', 'y', 'w', 'h']],
                           duration=f['duration'] / 1000.0) for f in doc['frames']]
            assert frames and all(f['duration'] > 0 for f in frames)
            e['actions'].append(dict(name=aliases.get(label, label).split(' · ')[0],
                                     path=install(doc_path.parent / doc['spritesheet']),
                                     frames=frames, duration=sum(f['duration'] for f in frames),
                                     sourceLoop=doc.get('loop', False)))
            e['sources'].append(doc_path.relative_to(ROOT).as_posix())
        entries.append(e)
        return e

    add('worker', '红细胞', 'cells', '运输 / 建造', 'red-cell-backpack-20261016', 'walk/frame-001.png',
        summary='背起氧气与葡萄糖，让前线保持运转。', kind='worker',
        mechanics=['循环防线中往返肺部与心脏，携氧、换糖、交付补给。',
                   '可采集资源和施工；背包与动作随空载、携氧、携糖、建造状态切换。',
                   '在有方向的血管内，顺流移动为基础速度的 3 倍，逆流为 0.4 倍。'],
        actions=[(k, v) for k, v in read(ROOT/'assets/image/red-cell-backpack-20261016/animations.json').items()
                 if k in ['walk', 'oxygen', 'glucose', 'build', 'hit', 'death']])
    add('spear', '中性粒白细胞', 'cells', '前线 / 颗粒射击', 'neutrophil-cartoon-v2-20261016',
        summary='锁定敌人，发射独立飞行的颗粒弹。', kind='spear',
        mechanics=['瞄准后经过 0.35 秒前摇发射颗粒；弹丸按发射方向飞行并检查命中。',
                   '攻击、受击、移动与死亡使用各自的原有动作。'])
    add('neutrophil', '普通中性粒细胞', 'cells', '轻型 / 颗粒射击', 'neutrophil-cartoon-v2-20261016',
        summary='与中性粒白细胞共用形象，使用独立的轻型作战数值。', kind='neutrophil',
        mechanics=['使用相同的颗粒射击方式，生命与伤害按普通中性粒细胞配置。',
                   '疱疹弹丸会识别这一单位；需要前排掩护。'])
    add('scout', '血小板', 'cells', '防御 / 牵手成墙', 'platelet-cartoon-v2-20261021',
        summary='停下牵手，连接成一条稳定的防线。', kind='scout',
        mechanics=['静止进入防御，同阵营、同通行层的邻居可从左右两端连接。',
                   '单体防御承受普通击退的 22%，牵手后为 5%，移动时为 45%。',
                   '移动时松手，死亡立即断链；连接必须通过地形与建筑检查。'])
    add('b_cell', 'B细胞', 'cells', '支援 / 攻速增益', 'b-cell-cartoon-20261021',
        summary='摇动花束，为身边的作战细胞加速。', kind='b_cell',
        mechanics=['停下自动摇花，不射击，也不追击敌人。',
                   '6 地图单位内，同阵营、同通行层且无遮挡的作战单位攻速变为 2 倍。',
                   '多只 B细胞不叠乘；移动、死亡或离开覆盖范围后增益失效。'])
    add('siege', '巨噬细胞', 'cells', '重型 / 吞噬动作', 'macrophage-cartoon-v2-20261020',
        status='现役单位 · 新动作预览', kind='siege',
        summary='厚重的伪足、张口吞噬与连续咀嚼。',
        mechanics=['现役巨噬细胞仍使用原有重型远程攻击配置，下方数值来自当前战斗规则。',
                   '新版美术已制作伪足移动、吞噬 → 咀嚼 → 恢复，以及受击和死亡动作。'],
        note='吞噬连段为动作展示，尚未替换现役攻击机制。')
    t_copy = t_cell_copy()
    # runtimeDefinition is descriptive metadata, not an add() argument.
    definition = t_copy.pop('runtimeDefinition', None)
    add('t_cell', 'T细胞', 'cells', '瞬身 / 投刀', 't-cell-cartoon-20261021', **t_copy)
    if definition:
        entries[-1]['runtimeDefinition'] = definition
        entries[-1]['sources'].extend(['godot/data/t_cell.json', 'godot/data/config.json'])
    add('dendritic_cell', '树突状细胞', 'cells', '侦察 / 标记减速', 'dendritic-cell-cartoon-20261021', kind='dendritic_cell',
        summary='停下侦察，标出敌人位置并降低其移动与攻击速度。',
        mechanics=['静止侦察可标记同通行层、无遮挡的敌方单位，包括带有地下或隐蔽状态的目标。',
                   '当前侦察半径为 8 地图单位；被标记敌人的移动速度与攻击速度均降至 70%，多只不叠乘。',
                   '自身不攻击；移动、受击或死亡会中断侦察。保留 6 帧依次亮灯技能。'],
        note='半径与减速幅度为当前首轮平衡值。')
    entries[-1].update(dendritic_copy())
    entries[-1]['sources'].extend(['godot/data/dendritic_cell.json', 'godot/data/config.json'])
    for id, role, summary in [
        ('archer', '远程 / 火力', '以较远射程提供持续火力。'),
        ('heavy', '前排 / 承伤', '高生命、近距离攻击，适合支撑前线。')]:
        add(id, config['Data']['units'][id]['name'], 'cells', role, 'cells-v3', 'white-cell.png',
            kind=id, summary=summary, mechanics=['可在沙盒对应建筑中训练，解锁条件与数值沿用当前单位配置。'],
            note='当前共用原有白细胞立绘，暂无独立动作图集。')
    entries[-1]['mechanics'].append('甲壳使普通攻击承伤降至 65%；持续状态伤害不使用这项减伤。')

    add('virus', '流感病毒', 'pathogens', '病毒 / 群体扩张', 'influenza-cartoon-v2-20261020',
        summary='成群入侵，在组织内施工并孵化新的病毒。', kind='virus',
        mechanics=['近距离啃咬敌人；移动、攻击、受击、死亡与电钻施工各有 20 帧。',
                   '每 10 个存活病毒提供 1 个要塞名额，由 10 名病毒共同施工。',
                   '建成要塞每 30 秒孵化 1 个病毒；遇敌先作战，安全后恢复施工。'])
    add('herpes', '单纯疱疹病毒', 'pathogens', '病毒 / 埋伏形态', 'herpes-ambusher-20261020',
        status='现役单位 · 新动作预览', kind='herpes', summary='可缩成低矮膜囊，再恢复并爆发。',
        mechanics=['现役规则：远程弹丸针对中性粒细胞，接触造成伤害与击退。',
                   '埋伏方案：移动 → 缩成膜囊 → 休眠 → 恢复 → 范围爆发。',
                   '埋伏触发距离、范围伤害、冷却及膜囊阻挡规则尚未接入。'],
        note='新版埋伏动作在此展示，不代表战斗已经使用该方案。')
    add('helicobacter', '幽门螺杆菌', 'pathogens', '细菌 / 鞭毛攻击', 'helicobacter-cartoon-v2-20261020',
        status='现役单位 · 新动作预览', kind='helicobacter', summary='挥动鞭毛，并展示独立的尿素酶区域。',
        mechanics=['现役单位使用近距离鞭毛攻击规则。',
                   '新动作包含移动、鞭毛普攻、布置尿素酶、受击与死亡。',
                   '尿素酶区域已绘制冒泡循环，其地面效果与持续规则尚未接入。'])
    add('adenovirus', '腺病毒', 'pathogens', '病毒 / 蓄力重砸', 'adenovirus-cartoon-v2-20261021', status='动作预览',
        summary='多面体病毒，跳跃移动并蓄力重砸。',
        mechanics=['包含跳跃、重砸、左右来袭受击与消散死亡，共 5 组动作。',
                   '重砸伤害、范围与冷却尚未确定，当前不能在战场部署。'])
    add('pneumococcus', '肺炎链球菌', 'pathogens', '细菌 / 吐核射击', 'pneumococcus-cartoon-v2-20261021', status='动作预览',
        summary='前后相连的紫色双球，鼓起脸颊发射弹丸。',
        mechanics=['鼓腮射击与独立吐核弹丸分别展示；保留左右受击和死亡动作。',
                   '弹丸碰撞、伤害、射程与攻击间隔尚未接入战斗。'])
    for id, file, role in [('wolf', 'red-cell.png', '细菌 / 近战侵袭'), ('shadow', 'platelet.png', '病原 / 快速近战')]:
        add(id, config['Data']['units'][id]['name'], 'pathogens', role, 'cells-v3', file,
            kind=id, summary='保留既有战役中的敌方单位。',
            mechanics=['近距离攻击敌对单位，生命、攻击间隔与移动速度沿用当前配置。'],
            note='使用原有共用立绘，尚无独立新版动作。')
        asset = config['CellFrames']['assets'][config['CellFrames']['kinds'][id]]
        entries[-1]['portrait'] = install(ROOT/'assets'/asset['path'])

    # Original parasite references are part of the existing character library.
    # Extract only named PNG/JSON members, never the archived Lua or preview code.
    for id, name, parameter, atlas, portrait, move in [
        ('roundworm', '蛔虫', 'frame-parameters.json', 'spritesheet.png', 'frames/001.png', '缠绕收紧'),
        ('tapeworm', '猪带绦虫', '帧参数.json', '猪带绦虫技能1.png', 'png/吞噬/001.png', '吞噬')]:
        archive = ROOT/(name+'json+动画.zip')
        folder = 'parasite-prototypes-20261021/'+id
        destination = ROOT/'assets/image'/folder
        destination.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            prefix = name+'json+动画/'
            doc = json.loads(z.read(prefix+parameter))
            (destination/'spritesheet.png').write_bytes(z.read(prefix+atlas))
            (destination/'portrait.png').write_bytes(z.read(prefix+portrait))
        frames = [dict(rect=dict(x=f.get('x', f.get('sheetX')), y=f.get('y', f.get('sheetY')),
                                 w=f['width'], h=f['height']), duration=1000/doc['fps']) for f in doc['frames']]
        write(destination/'animation.json', dict(spritesheet='spritesheet.png', frames=frames, loop=True,
              sourceArchive=archive.name, sourceSHA256=hashlib.sha256(archive.read_bytes()).hexdigest(),
              sourceMembers=[prefix+parameter, prefix+atlas, prefix+portrait]))
        add(id, name, 'pathogens', '寄生虫 / '+move, folder, 'portrait.png', status='原型预览',
            summary='原始角色素材中的'+move+'技能。',
            mechanics=['保留原始图集与逐帧节奏，展示完整的'+move+'动作。',
                       '技能目标、伤害、控制效果与部署规则尚未接入战斗。'],
            note='现有原型素材，仅在角色图鉴中预览。', actions=[(move, 'animation.json')])

    # One medicine authority supplies confirmation boundaries and gallery copy.
    entries.extend(build_medicine_entries(install))

    write(GAME/'data/character_catalogue.json', dict(schema=1, entries=entries,
          actionCount=sum(len(e['actions']) for e in entries),
          scope='Read-only cover gallery; no changes to unit deployment or battle mechanics.'))
    write(GAME/'data/asset_manifest.json', list(manifest.values()))
    source = read(GAME/'data/source_manifest.json')
    source.update(assets=len(manifest), assetBytes=sum(r['bytes'] for r in manifest.values()))
    write(GAME/'data/source_manifest.json', source)
    print(json.dumps(dict(characters=len(entries), actions=sum(len(e['actions']) for e in entries),
                          categories={c: sum(e['category']==c for e in entries)
                                      for c in ['cells','pathogens','medicines']}), ensure_ascii=False))


if __name__ == '__main__':
    main()
