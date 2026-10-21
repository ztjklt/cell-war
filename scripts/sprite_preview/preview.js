/* Read-only animation review. No remote APIs, build step, or third-party libraries. */
'use strict';
const $ = id => document.getElementById(id);
const natural = new Intl.Collator('zh-CN', {numeric: true, sensitivity: 'base'});
const state = {clips: [], selected: -1, frame: 0, elapsed: 0, playing: false, lastTick: 0, generation: 0, gridImage: null};
const ctx = $('canvas').getContext('2d');
const imageFile = name => /\.(png|webp|jpe?g|gif|avif|bmp)$/i.test(name);
const jsonFile = name => /\.json$/i.test(name);
const current = () => state.clips[state.selected];
const viewParams = new URLSearchParams(location.search);
const requestedGroup = viewParams.get('group');
const galleryMode = viewParams.get('view') === 'gallery';
let galleryCards = [];
if (requestedGroup) document.body.classList.add('group-view');
if (galleryMode) {
  document.body.classList.add('gallery-view');
  $('gallery').hidden = false;
  document.querySelector('h1').textContent = requestedGroup ? `${requestedGroup} · 全部动作` : '全部动作预览';
  document.title = requestedGroup ? `${requestedGroup} · 全部动作预览` : '细胞战争 · 全部动作预览';
}

function renderGallery() {
  $('gallery-cards').replaceChildren();
  $('gallery-nav').replaceChildren();
  galleryCards = [];
  $('gallery-summary').textContent = `${state.clips.length} 个动作 · ${state.clips.reduce((sum, clip) => sum + clip.frames.length, 0)} 帧 · 点击动作名跳转，支持单独暂停和逐帧查看`;
  state.clips.forEach((clip, index) => {
    const card = document.createElement('article');
    card.className = 'animation-card'; card.id = `action-${index}`;
    const heading = document.createElement('div'); heading.className = 'animation-card-heading';
    const title = document.createElement('h2'); title.textContent = clip.name;
    const count = document.createElement('span'); count.className = 'frame-count'; count.textContent = `${clip.frames.length} 帧`;
    heading.append(title, count);
    const stage = document.createElement('div'); stage.className = 'gallery-stage checker';
    const canvas = document.createElement('canvas'); canvas.setAttribute('aria-label', `${clip.name}动画`);
    stage.append(canvas);
    const footer = document.createElement('div'); footer.className = 'animation-card-footer';
    const label = document.createElement('span'); label.className = 'gallery-frame-label';
    const pause = document.createElement('button'); pause.textContent = '暂停'; pause.setAttribute('aria-label', `暂停${clip.name}`);
    const detail = document.createElement('a'); detail.className = 'detail-link'; detail.textContent = '逐帧查看';
    detail.href = `/?${new URLSearchParams({group: clip.group, action: clip.name})}`;
    detail.setAttribute('aria-label', `逐帧查看${clip.name}`);
    footer.append(label, pause, detail);
    card.append(heading, stage, footer); $('gallery-cards').append(card);
    const jump = document.createElement('a'); jump.href = `#${card.id}`; jump.textContent = clip.name;
    $('gallery-nav').append(jump);
    const entry = {clip, canvas, label, pause, elapsed: 0, lastTick: performance.now(), playing: true, frame: -1};
    pause.onclick = () => {
      entry.playing = !entry.playing; entry.lastTick = performance.now();
      updateGalleryButtons();
    };
    galleryCards.push(entry);
  });
  updateGalleryButtons();
  $('gallery-status').textContent = state.clips.length ? '各动作循环预览，单次动作结束后会短暂停留，再从头重播。' : '没有找到该角色的动作。';
}
function updateGalleryButtons() {
  galleryCards.forEach(entry => {
    entry.pause.textContent = entry.playing ? '暂停' : '播放';
    entry.pause.setAttribute('aria-label', `${entry.playing ? '暂停' : '播放'}${entry.clip.name}`);
    entry.pause.setAttribute('aria-pressed', String(entry.playing));
  });
  $('gallery-toggle').textContent = galleryCards.some(entry => entry.playing) ? '全部暂停' : '全部播放';
}
function drawGallery(now) {
  galleryCards.forEach(entry => {
    if (entry.playing) entry.elapsed += Math.max(0, now - entry.lastTick);
    entry.lastTick = now;
    const {clip, canvas} = entry;
    const total = clip.frames.reduce((sum, frame) => sum + frame.duration, 0);
    // One-shot actions hold their first/last poses briefly before review replay.
    let time = clip.loop ? entry.elapsed % total : Math.max(0, entry.elapsed % (total + 650) - 250);
    const clipTime = time;
    let index = clip.frames.length - 1;
    for (let i = 0; i < clip.frames.length; i++) {
      if (time < clip.frames[i].duration) { index = i; break; }
      time -= clip.frames[i].duration;
    }
    const box = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(box.width * dpr)), height = Math.max(1, Math.round(box.height * dpr));
    const resized = canvas.width !== width || canvas.height !== height;
    if (entry.frame === index && !resized && !clip.motionPreview) return;
    if (resized) { canvas.width = width; canvas.height = height; }
    const context = canvas.getContext('2d'); context.setTransform(dpr, 0, 0, dpr, 0, 0);
    context.clearRect(0, 0, box.width, box.height);
    paint(context, clip, index, box.width, box.height, 1, 1, clipTime);
    entry.frame = index; entry.label.textContent = `${index + 1} / ${clip.frames.length}`;
  });
}
$('gallery-toggle').onclick = () => {
  const play = !galleryCards.some(entry => entry.playing);
  galleryCards.forEach(entry => { entry.playing = play; entry.lastTick = performance.now(); });
  updateGalleryButtons();
};

function status(message, error = false) {
  $('status').textContent = message;
  $('status').classList.toggle('error', error);
}
function positive(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}
function join(base, reference) {
  if (typeof reference !== 'string' || /^(?:[a-z]+:|\/\/)/i.test(reference)) throw new Error('只支持本地相对资源路径');
  const parts = (reference.startsWith('/') ? reference : base.slice(0, base.lastIndexOf('/') + 1) + reference).split('/');
  const result = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') { if (!result.length) throw new Error('资源路径超出导入目录'); result.pop(); }
    else result.push(part);
  }
  return (base.startsWith('/') ? '/' : '') + result.join('/');
}
async function decodedImage(url) {
  const image = new Image();
  image.src = url;
  await image.decode();
  return image;
}
function networkSource() {
  const images = new Map();
  const allowed = path => {
    if (!path.startsWith('/assets/')) throw new Error('资源必须位于本地项目 assets 目录');
    return path.split('/').map(encodeURIComponent).join('/');
  };
  return {
    async json(path) {
      const response = await fetch(allowed(path));
      if (!response.ok) throw new Error(`读取失败：${path}`);
      return response.json();
    },
    image(path) {
      if (!images.has(path)) images.set(path, decodedImage(allowed(path)));
      return images.get(path);
    }
  };
}
function fileSource(files) {
  const entries = new Map(files.map(file => [file.webkitRelativePath || file.name, file]));
  const images = new Map();
  function find(path) {
    if (entries.has(path)) return entries.get(path);
    const basename = path.split('/').pop();
    const matches = [...entries].filter(([key]) => key.split('/').pop() === basename);
    if (matches.length === 1) return matches[0][1];
    throw new Error(matches.length ? `同名资源无法区分：${path}，请导入整个文件夹` : `缺少资源：${path}，请同时选择 JSON 和对应图片`);
  }
  return {
    entries,
    async json(path) { return JSON.parse(await find(path).text()); },
    image(path) {
      if (!images.has(path)) images.set(path, (async () => {
        const url = URL.createObjectURL(find(path));
        try { return await decodedImage(url); } finally { URL.revokeObjectURL(url); }
      })());
      return images.get(path);
    }
  };
}
function rect(value, fallback) {
  const input = value || fallback;
  if (!input) throw new Error('缺少帧的矩形信息');
  const output = {x: Number(input.x ?? 0), y: Number(input.y ?? 0), w: Number(input.w ?? input.width), h: Number(input.h ?? input.height)};
  if (!Object.values(output).every(Number.isFinite) || output.x < 0 || output.y < 0 || output.w <= 0 || output.h <= 0) throw new Error('帧矩形无效');
  return output;
}
function makeFrame(image, data, document, name, index, pivot, fps = 8) {
  if (data.rotated) throw new Error('暂不支持旋转打包的帧，请导出未旋转的图集');
  const fallback = {x: 0, y: 0, w: image.naturalWidth, h: image.naturalHeight};
  const crop = rect(data.rect || data.frame, fallback);
  if (crop.x + crop.w > image.naturalWidth || crop.y + crop.h > image.naturalHeight) throw new Error(`第 ${index + 1} 帧超出图集边界`);
  const width = positive(data.sourceSize?.w, positive(document.width, crop.w));
  const height = positive(data.sourceSize?.h, positive(document.height, crop.h));
  const trim = rect(data.spriteSourceSize, {x: 0, y: 0, w: crop.w, h: crop.h});
  if (trim.x + trim.w > width || trim.y + trim.h > height) throw new Error(`第 ${index + 1} 帧裁剪位置超出原始画布`);
  const anchor = pivot || data.anchor || document.anchor || {x: .5, y: .5};
  const ax = Number(anchor.x), ay = Number(anchor.y);
  if (!Number.isFinite(ax) || !Number.isFinite(ay)) throw new Error('帧支点无效');
  const duration = positive(data.duration, positive(document.durationsMs?.[index], 1000 / positive(document.fps, fps)));
  return {image, crop, width, height, trim, ax: ax * width, ay: ay * height, duration, name};
}
function finishClip(name, group, frames, loop = true) {
  if (!frames.length) throw new Error(`${name} 没有可播放的帧`);
  const bounds = {left: 0, top: 0, right: 0, bottom: 0};
  for (const frame of frames) {
    bounds.left = Math.min(bounds.left, -frame.ax);
    bounds.top = Math.min(bounds.top, -frame.ay);
    bounds.right = Math.max(bounds.right, frame.width - frame.ax);
    bounds.bottom = Math.max(bounds.bottom, frame.height - frame.ay);
  }
  return {name, group, frames, loop, bounds};
}

async function loadJSON(path, source, label = '', group = '导入的动作', visited = new Set()) {
  if (visited.has(path)) return [];
  visited.add(path);
  const data = await source.json(path);
  if (!data || typeof data !== 'object') throw new Error(`不是有效的动作 JSON：${path}`);
  // Existing project manifests list each action as a relative animation.json path.
  if (!data.frames && !data.meta) {
    const references = Object.entries(data).filter(([key, value]) => key !== 'idle' && typeof value === 'string' && jsonFile(value));
    if (!references.length) throw new Error(`未识别的动作格式：${path}`);
    const clips = [];
    for (const [key, reference] of references) clips.push(...await loadJSON(join(path, reference), source, key, label || data.character || group, visited));
    return clips;
  }
  // Project grid atlas: explicit ordered frames and millisecond durations.
  if (Array.isArray(data.frames)) {
    if (!data.spritesheet) throw new Error('动作配置缺少 spritesheet 图片路径');
    const image = await source.image(join(path, data.spritesheet));
    const frames = data.frames.map((frame, index) => makeFrame(image, frame, data, frame.name || String(index + 1), index));
    const clip = finishClip(label || data.animation || data.name || path, group, frames, data.loop !== false);
    if (data.motionPreview) {
      const motion = data.motionPreview;
      if (motion.kind !== 'blink' || !positive(motion.bodyDiameter) ||
          !Number.isInteger(motion.launchFrame) || !Number.isInteger(motion.arriveFrame) ||
          motion.launchFrame < 2 || motion.arriveFrame <= motion.launchFrame || motion.arriveFrame > frames.length ||
          !positive(motion.distanceInBodies) || !positive(motion.trailMs) ||
          !Number.isInteger(motion.ghosts) || motion.ghosts < 1 || motion.ghosts > 16 ||
          !Array.isArray(motion.hideFrames) || !motion.hideFrames.every(i => Number.isInteger(i) && i >= 1 && i <= frames.length)) {
        throw new Error('瞬身位移的预览配置无效');
      }
      clip.motionPreview = motion;
    }
    if (data.reviewProjectile) {
      const preview = data.reviewProjectile;
      const [effect] = await loadJSON(join(path, preview.animation), source, '', group, new Set(visited));
      if (!effect || !Array.isArray(preview.frameMap) || !preview.frameMap.length ||
          !Number.isInteger(preview.startFrame) || preview.startFrame < 1 ||
          !Number.isInteger(preview.endFlightFrame) || preview.endFlightFrame <= preview.startFrame ||
          preview.startFrame + preview.frameMap.length - 1 > frames.length ||
          !preview.frameMap.every(index => Number.isInteger(index) && index >= 1 && index <= effect.frames.length) ||
          ![preview.from, preview.to].every(point => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite)) ||
          !positive(preview.drawSize)) throw new Error('独立弹体的预览配置无效');
      clip.reviewProjectile = {...preview, effect};
      // Leave room beside the character for the independently drawn projectile.
      const radius = preview.drawSize / 2, first = frames[0];
      clip.bounds.left = Math.min(clip.bounds.left, Math.min(preview.from[0], preview.to[0]) - radius - first.ax);
      clip.bounds.right = Math.max(clip.bounds.right, Math.max(preview.from[0], preview.to[0]) + radius - first.ax);
      clip.bounds.top = Math.min(clip.bounds.top, Math.min(preview.from[1], preview.to[1]) - radius - first.ay);
      clip.bounds.bottom = Math.max(clip.bounds.bottom, Math.max(preview.from[1], preview.to[1]) + radius - first.ay);
    }
    return [clip];
  }
  // TexturePacker / sprite-gen: explicit animation order, trim, pivot and multipacks.
  const pages = new Map([[path, data]]);
  async function collect(pagePath, page) {
    for (const related of page.meta?.relatedMultiPacks || []) {
      const next = join(pagePath, related);
      if (pages.has(next)) continue;
      const nextData = await source.json(next);
      pages.set(next, nextData);
      await collect(next, nextData);
    }
  }
  await collect(path, data);
  const table = new Map(), definitions = [];
  for (const [pagePath, page] of pages) {
    const entries = Object.entries(page.frames || {});
    if (entries.length && !page.meta?.image) throw new Error('图集 JSON 缺少 meta.image');
    const image = entries.length ? await source.image(join(pagePath, page.meta.image)) : null;
    for (const [name, frame] of entries) {
      if (table.has(name)) throw new Error(`分页图集存在重名帧：${name}`);
      table.set(name, {image, frame, page});
    }
    if (Array.isArray(page.animations)) {
      for (const definition of page.animations) definitions.push({...definition, pivot: definition.pivot || page.meta?.pivot});
    } else if (page.animations) {
      for (const [name, frames] of Object.entries(page.animations)) definitions.push({name, frames, pivot: page.meta?.pivot});
    }
  }
  if (!definitions.length) definitions.push({name: label || path.split('/').slice(-2, -1)[0] || '动画', frames: [...table.keys()].sort(natural.compare), pivot: data.meta?.pivot});
  return definitions.map(definition => {
    if (!Array.isArray(definition.frames)) throw new Error('动画缺少有序帧列表');
    let names = definition.frames.slice();
    if (definition.direction === 'reverse') names.reverse();
    if (definition.direction === 'pingpong') names = names.concat(names.slice(1, -1).reverse());
    const frames = names.map((name, index) => {
      const record = table.get(name);
      if (!record) throw new Error(`找不到动画引用的帧：${name}`);
      return makeFrame(record.image, record.frame, record.page, name, index, definition.pivot, positive(definition.fps, 8));
    });
    return finishClip(definitions.length === 1 && label ? label : definition.name, group, frames, !(Number(definition.repeat) > 0));
  });
}

function durations() {
  return current()?.frames.map(frame => $('fixed-fps').checked ? 1000 / positive($('fps').value, 8) : frame.duration) || [];
}
function order() {
  const frames = current()?.frames || [];
  const sequence = frames.map((_, index) => index);
  return $('mode').value === 'pingpong' ? sequence.concat(sequence.slice(1, -1).reverse()) : sequence;
}
function syncClock() {
  const times = durations();
  state.elapsed = order().slice(0, order().indexOf(state.frame)).reduce((sum, index) => sum + times[index], 0);
  state.lastTick = performance.now();
}
function playing(value) {
  state.playing = !!value && !!current();
  state.lastTick = performance.now();
  $('play').textContent = state.playing ? '暂停' : '播放';
  $('play').setAttribute('aria-pressed', String(state.playing));
}
function step(direction) {
  if (!current()) return;
  playing(false);
  state.frame = (state.frame + direction + current().frames.length) % current().frames.length;
  syncClock(); draw();
}
function selectClip(index) {
  if (!state.clips[index]) return;
  state.selected = index; state.frame = 0; state.elapsed = 0;
  const clip = current();
  $('mode').value = clip.loop ? 'loop' : 'once';
  $('clip-name').textContent = `${clip.group} · ${clip.name}`;
  $('scrub').max = clip.frames.length - 1;
  $('clip-info').textContent = `${clip.frames.length} 帧 · ${clip.frames[0].width} × ${clip.frames[0].height} 画布 · 保留原始帧间时长`;
  $('empty').hidden = true;
  renderList(); renderStrip(); playing(true); draw();
}
function renderList() {
  $('clips').replaceChildren();
  let group = null;
  state.clips.forEach((clip, index) => {
    if (clip.group !== group) {
      const heading = document.createElement('div'); heading.className = 'group-name'; heading.textContent = clip.group;
      $('clips').append(heading); group = clip.group;
    }
    const button = document.createElement('button');
    button.className = 'clip' + (index === state.selected ? ' active' : '');
    button.textContent = clip.name; button.title = `${clip.group} · ${clip.name}`;
    button.setAttribute('aria-pressed', String(index === state.selected));
    button.onclick = () => { selectClip(index); status('按原始帧顺序播放；更改预览参数不会修改素材。'); };
    $('clips').append(button);
  });
}
function frameStart(clip, index) {
  return clip.frames.slice(0, index).reduce((sum, frame) => sum + frame.duration, 0);
}
function frameAt(clip, time) {
  let elapsed = Math.max(0, time);
  for (let i = 0; i < clip.frames.length; i++) {
    if (elapsed < clip.frames[i].duration) return i;
    elapsed -= clip.frames[i].duration;
  }
  return clip.frames.length - 1;
}
function paintBlink(context, clip, index, width, height, alpha, zoom, elapsed) {
  const motion = clip.motionPreview;
  const time = Number.isFinite(elapsed) ? elapsed : frameStart(clip, index) + clip.frames[index].duration / 2;
  const launch = frameStart(clip, motion.launchFrame - 1), arrive = frameStart(clip, motion.arriveFrame - 1);
  const distanceInBodies = Math.min(8, Math.max(2, motion.distanceInBodies));
  const body = Math.min(height * .34, (width - 32) / (distanceInBodies + 2.4)) * Math.min(1.15, zoom);
  const distance = Math.min(width - body * 2.4, body * distanceInBodies);
  const from = (width - distance) / 2, to = (width + distance) / 2, y = height * .52;
  const mirrored = $('mirror').checked;
  const root = at => {
    const progress = Math.max(0, Math.min(1, (at - launch) / (arrive - launch)));
    const x = from + distance * progress;
    return mirrored ? width - x : x;
  };
  const drawPose = (frameIndex, x, opacity) => {
    if (opacity <= 0) return;
    const frame = clip.frames[frameIndex], r = frame.crop, trim = frame.trim;
    const scale = body / motion.bodyDiameter;
    context.save(); context.globalAlpha = alpha * opacity;
    context.translate(x, y); context.scale(mirrored ? -scale : scale, scale);
    context.drawImage(frame.image, r.x, r.y, r.w, r.h,
      trim.x - frame.ax, trim.y - frame.ay, trim.w, trim.h);
    context.restore();
  };
  // This lane demonstrates displacement; it never changes map/navigation data.
  context.save(); context.globalAlpha = alpha * .5;
  context.strokeStyle = '#65877c'; context.lineWidth = 1;
  context.setLineDash([4, 5]); context.beginPath(); context.moveTo(from, height * .79); context.lineTo(to, height * .79); context.stroke();
  context.setLineDash([]); context.fillStyle = '#294e44'; context.font = '11px sans-serif'; context.textAlign = 'center';
  context.fillText(mirrored ? '落点' : '起步', from, height * .79 + 20);
  context.fillText(mirrored ? '起步' : '落点', to, height * .79 + 20); context.restore();
  // Sample prior positions so the afterimages stay behind the moving body.
  for (let ghost = motion.ghosts; ghost >= 1; ghost--) {
    const age = motion.trailMs * ghost / (motion.ghosts + 1), past = time - age;
    if (past < launch || past > arrive) continue;
    drawPose(frameAt(clip, past), root(past), .4 * (1 - age / motion.trailMs));
  }
  const travel = time >= launch && time < arrive;
  const opacity = motion.hideFrames.includes(index + 1) && travel ? .06 : travel ? .38 : 1;
  drawPose(index, root(time), opacity);
}
function paint(context, clip, frameIndex, width, height, alpha = 1, zoom = 1, elapsed) {
  if (clip.motionPreview) { paintBlink(context, clip, frameIndex, width, height, alpha, zoom, elapsed); return; }
  const frame = clip.frames[frameIndex], b = clip.bounds;
  const scale = Math.min((width - 24) / (b.right - b.left), (height - 24) / (b.bottom - b.top)) * zoom;
  const mirrored = $('mirror').checked;
  context.save();
  context.globalAlpha = alpha;
  context.translate(width / 2, height / 2);
  context.scale(mirrored ? -scale : scale, scale);
  context.translate(-(b.left + b.right) / 2, -(b.top + b.bottom) / 2);
  const r = frame.crop, t = frame.trim;
  context.drawImage(frame.image, r.x, r.y, r.w, r.h, t.x - frame.ax, t.y - frame.ay, t.w, t.h);
  const preview = clip.reviewProjectile;
  if (preview) {
    const offset = frameIndex + 1 - preview.startFrame;
    if (offset >= 0 && offset < preview.frameMap.length) {
      const effect = preview.effect.frames[preview.frameMap[offset] - 1];
      const progress = Math.min(1, offset / (preview.endFlightFrame - preview.startFrame));
      const x = preview.from[0] + (preview.to[0] - preview.from[0]) * progress - frame.ax;
      const y = preview.from[1] + (preview.to[1] - preview.from[1]) * progress - frame.ay;
      const effectScale = preview.drawSize / effect.width;
      const e = effect.crop, trim = effect.trim;
      context.drawImage(effect.image, e.x, e.y, e.w, e.h,
        x + (trim.x - effect.ax) * effectScale, y + (trim.y - effect.ay) * effectScale,
        trim.w * effectScale, trim.h * effectScale);
    }
  }
  context.restore();
}
function renderStrip() {
  $('strip').replaceChildren();
  if (!current()) return;
  const times = durations();
  current().frames.forEach((frame, index) => {
    const button = document.createElement('button'); button.className = 'thumb';
    button.title = `${frame.name} · ${Math.round(times[index])} ms`;
    button.setAttribute('aria-label', `查看第 ${index + 1} 帧`);
    const canvas = document.createElement('canvas'); canvas.width = 170; canvas.height = 150;
    paint(canvas.getContext('2d'), current(), index, 170, 150);
    const text = document.createElement('span'); text.textContent = `${index + 1} / ${Math.round(times[index])} ms`;
    button.append(canvas, text);
    button.onclick = () => { playing(false); state.frame = index; syncClock(); draw(); };
    $('strip').append(button);
  });
}
function draw() {
  if (galleryMode) return;
  const canvas = $('canvas'), box = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.round(box.width * dpr)), height = Math.max(1, Math.round(box.height * dpr));
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, box.width, box.height);
  const clip = current();
  if (!clip) return;
  const zoom = Number($('zoom').value);
  if ($('onion').checked && state.frame > 0) paint(ctx, clip, state.frame - 1, box.width, box.height, .25, zoom);
  let motionTime;
  if (clip.motionPreview && !$('fixed-fps').checked && $('mode').value !== 'pingpong') {
    const total = clip.frames.reduce((sum, frame) => sum + frame.duration, 0);
    motionTime = $('mode').value === 'once' ? Math.min(state.elapsed, total) : state.elapsed % total;
  }
  paint(ctx, clip, state.frame, box.width, box.height, 1, zoom, motionTime);
  const times = durations();
  $('frame-label').textContent = `第 ${state.frame + 1} / ${clip.frames.length} 帧`;
  $('clip-info').textContent = `${clip.frames.length} 帧 · ${clip.frames[0].width} × ${clip.frames[0].height} 画布 · ${$('fixed-fps').checked ? '统一帧率预览' : '保留原始帧间时长'}`;
  $('duration-label').textContent = `${Math.round(times[state.frame])} ms / 帧 · ${(times.reduce((a, b) => a + b, 0) / 1000).toFixed(2)} s`;
  $('scrub').value = state.frame;
  [...$('strip').children].forEach((element, index) => element.classList.toggle('active', index === state.frame));
}
function tick(now) {
  if (galleryMode) { drawGallery(now); requestAnimationFrame(tick); return; }
  if (state.playing && current()) {
    const delta = Math.max(0, now - (state.lastTick || now));
    state.elapsed += delta * Number($('speed').value);
    const times = durations(), sequence = order(), total = sequence.reduce((sum, index) => sum + times[index], 0);
    let time = state.elapsed;
    if ($('mode').value === 'once' && time >= total) {
      state.frame = current().frames.length - 1; state.elapsed = total; playing(false); draw();
    } else {
      time %= total;
      for (const index of sequence) {
        if (time < times[index]) { if (state.frame !== index) { state.frame = index; draw(); } else if (current().motionPreview) draw(); break; }
        time -= times[index];
      }
    }
  }
  state.lastTick = now;
  requestAnimationFrame(tick);
}

async function loadCatalog() {
  const token = ++state.generation;
  status('正在读取项目动作…');
  try {
    const response = await fetch('/api/catalog');
    if (!response.ok) throw new Error('无法读取项目动作');
    const {entries} = await response.json(), source = networkSource(), clips = [], errors = [];
    const visibleEntries = requestedGroup ? entries.filter(entry => entry.group === requestedGroup) : entries;
    for (const entry of visibleEntries) {
      try { clips.push(...await loadJSON(entry.url, source, entry.name, entry.group)); }
      catch (error) { errors.push(`${entry.name}：${error.message}`); }
    }
    if (token !== state.generation) return;
    state.clips = clips; state.selected = -1; state.gridImage = null;
    if (galleryMode) renderGallery();
    else if (clips.length) selectClip(Math.max(0, clips.findIndex(clip => clip.name === viewParams.get('action'))));
    else { playing(false); $('clip-name').textContent = '导入一个动作'; $('empty').hidden = false; renderList(); renderStrip(); draw(); }
    status(`已载入 ${clips.length} 组项目动作。${errors.length ? ' ' + errors.join('；') : '可直接选择动作，或拖入新生成的图片。'}`, !!errors.length);
  } catch (error) {
    if (token !== state.generation) return;
    $('clip-name').textContent = '导入一个动作'; $('empty').hidden = false;
    status('可离线导入图片。要自动读取项目动作，请运行 serve.py 后打开本地地址。');
  }
}
async function importFiles(input) {
  const files = [...input].filter(file => imageFile(file.name) || jsonFile(file.name));
  if (!files.length) { status('请选择图片，或 JSON 与对应图片。', true); return; }
  const token = ++state.generation;
  status('正在读取导入的动作…');
  playing(false);
  state.gridImage = null;
  try {
    const source = fileSource(files), jsonPaths = [...source.entries.keys()].filter(jsonFile), clips = [];
    let gridImage = null;
    if (jsonPaths.length) {
      // A full generated-asset folder may also contain prompts, reports and old takes.
      // Prefer its declared entry rather than treating every JSON as an animation.
      const manifests = jsonPaths.filter(path => /(?:^|\/)(?:animations|sprite)\.json$/i.test(path));
      const sheets = jsonPaths.filter(path => /(?:^|\/)(?:animation|spritesheet(?:-\d+)?)\.json$/i.test(path));
      const candidates = manifests.length ? manifests : sheets.length ? sheets : jsonPaths;
      const references = new Set();
      for (const path of candidates) {
        const data = await source.json(path);
        for (const reference of data.meta?.relatedMultiPacks || []) references.add(join(path, reference));
        if (!data.frames && !data.meta) for (const value of Object.values(data)) if (typeof value === 'string' && jsonFile(value)) references.add(join(path, value));
      }
      const roots = candidates.filter(path => !references.has(path));
      if (!roots.length) throw new Error('图集入口相互循环引用，请检查 JSON');
      const visited = new Set();
      for (const path of roots.sort(natural.compare)) clips.push(...await loadJSON(path, source, '', '导入的动作', visited));
    } else {
      const paths = [...source.entries.keys()].filter(imageFile).sort(natural.compare);
      if (paths.length === 1) {
        gridImage = {image: await source.image(paths[0]), name: paths[0].split('/').pop()};
        if (token !== state.generation) return;
        state.gridImage = gridImage;
        $('grid-options').open = true;
        clips.push(gridClip(gridImage));
      } else {
        const frames = [];
        for (const path of paths) {
          const image = await source.image(path);
          frames.push(makeFrame(image, {}, {}, path.split('/').pop(), frames.length));
        }
        clips.push(finishClip('散帧序列（按文件名排序）', '导入的动作', frames));
      }
    }
    if (token !== state.generation) return;
    if (!clips.length) throw new Error('没有找到可播放的动作');
    state.clips = clips; state.selected = -1; state.gridImage = gridImage;
    $('grid-options').open = !!gridImage;
    selectClip(0);
    status(gridImage ? '已按网格拆分；请核对列数、行数和帧数。只读取原图，不会上传文件。' : `已导入 ${clips.length} 组动作。图片只在本机浏览器内读取。`);
  } catch (error) { if (token === state.generation) status(error.message, true); }
}
function gridClip(record) {
  const columns = positive($('columns').value), rows = positive($('rows').value), count = positive($('count').value);
  if (![columns, rows, count].every(Number.isInteger) || count > columns * rows || columns > 128 || rows > 128) throw new Error('网格参数无效：帧数必须不大于列数 × 行数');
  const width = record.image.naturalWidth / columns, height = record.image.naturalHeight / rows;
  if (!Number.isInteger(width) || !Number.isInteger(height)) throw new Error('图片尺寸不能被当前网格整除，请修改列数和行数');
  const frames = Array.from({length: count}, (_, index) => makeFrame(record.image, {rect: {x: index % columns * width, y: Math.floor(index / columns) * height, w: width, h: height}}, {width, height}, `${index + 1}`, index));
  return finishClip(record.name, '导入的图集', frames);
}

$('play').onclick = () => {
  if (!state.playing && current() && $('mode').value === 'once' && state.elapsed >= durations().reduce((sum, duration) => sum + duration, 0)) { state.frame = 0; syncClock(); draw(); }
  playing(!state.playing);
};
$('previous').onclick = () => step(-1);
$('next').onclick = () => step(1);
$('restart').onclick = () => { state.frame = 0; syncClock(); draw(); };
$('scrub').oninput = () => { playing(false); state.frame = Number($('scrub').value); syncClock(); draw(); };
$('mode').onchange = () => { syncClock(); draw(); };
$('speed').onchange = () => { state.lastTick = performance.now(); };
for (const id of ['fixed-fps', 'fps']) {
  const update = () => { syncClock(); renderStrip(); draw(); };
  $(id).onchange = update;
  $(id).oninput = update;
}
for (const id of ['zoom', 'onion', 'mirror']) $(id).onchange = () => { if (id === 'mirror') renderStrip(); draw(); };
$('background').onchange = () => { $('stage').className = 'stage ' + $('background').value; };
$('import-button').onclick = () => $('files').click();
$('folder-button').onclick = () => $('folder').click();
$('files').onchange = () => { importFiles($('files').files); $('files').value = ''; };
$('folder').onchange = () => { importFiles($('folder').files); $('folder').value = ''; };
$('reload').onclick = loadCatalog;
$('apply-grid').onclick = () => {
  if (!state.gridImage) { status('请先选择一张没有 JSON 的图集图片。', true); return; }
  try { const clip = gridClip(state.gridImage); state.clips = [clip]; selectClip(0); status('网格已更新。'); }
  catch (error) { status(error.message, true); }
};
document.addEventListener('keydown', event => {
  if (/INPUT|SELECT|TEXTAREA/.test(event.target.tagName) || event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.code === 'Space') { event.preventDefault(); $('play').click(); }
  if (event.code === 'ArrowLeft') { event.preventDefault(); step(-1); }
  if (event.code === 'ArrowRight') { event.preventDefault(); step(1); }
  if (event.code === 'Home') { event.preventDefault(); $('restart').click(); }
});
document.addEventListener('dragover', event => { event.preventDefault(); document.body.classList.add('dragging'); });
document.addEventListener('dragleave', event => { if (!event.relatedTarget) document.body.classList.remove('dragging'); });
document.addEventListener('drop', event => { event.preventDefault(); document.body.classList.remove('dragging'); importFiles(event.dataTransfer.files); });
document.addEventListener('visibilitychange', () => { state.lastTick = performance.now(); });
new ResizeObserver(draw).observe($('stage'));
requestAnimationFrame(tick);
loadCatalog();
