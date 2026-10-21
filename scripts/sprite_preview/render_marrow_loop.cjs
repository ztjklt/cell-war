#!/usr/bin/env node
/* GPT paints the layers. This renderer animates those fixed layers on a closed curve.
 * Requires @napi-rs/canvas. No network calls, image generation, or per-frame redrawing.
 * Usage: node render_marrow_loop.cjs SOURCE_COMPONENTS.png NEW_OUTPUT_DIRECTORY
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {createCanvas, loadImage} = require('@napi-rs/canvas');

function components(image) {
  const width = image.width, height = image.height;
  const canvas = createCanvas(width, height), context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  const pixels = context.getImageData(0, 0, width, height).data;
  const visited = new Uint8Array(width * height), queue = new Int32Array(width * height), found = [];
  for (let start = 0; start < visited.length; start++) {
    if (visited[start] || pixels[start * 4 + 3] < 96) continue;
    let head = 0, tail = 1, left = width, top = height, right = 0, bottom = 0;
    queue[0] = start; visited[start] = 1;
    while (head < tail) {
      const point = queue[head++], x = point % width, y = Math.floor(point / width);
      left = Math.min(left, x); top = Math.min(top, y);
      right = Math.max(right, x + 1); bottom = Math.max(bottom, y + 1);
      const next = [];
      if (x) next.push(point - 1);
      if (x + 1 < width) next.push(point + 1);
      if (y) next.push(point - width);
      if (y + 1 < height) next.push(point + width);
      for (const neighbor of next) {
        if (!visited[neighbor] && pixels[neighbor * 4 + 3] >= 96) {
          visited[neighbor] = 1; queue[tail++] = neighbor;
        }
      }
    }
    if (tail > 1000) found.push({left, top, right, bottom, area: tail});
  }
  const largest = found.sort((a, b) => b.area - a.area).slice(0, 6);
  if (largest.length !== 6) throw new Error('Expected a reference, bone, marrow and three separate cell layers');
  return largest.sort((a, b) => Math.floor((a.top + a.bottom) / height) - Math.floor((b.top + b.bottom) / height) || a.left - b.left)
    .map(box => ({...box, left: Math.max(0, box.left - 3), top: Math.max(0, box.top - 3),
      right: Math.min(width, box.right + 3), bottom: Math.min(height, box.bottom + 3)}));
}

function render(image, layers, phase) {
  const canvas = createCanvas(512, 512), ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  const breath = (1 - Math.cos(phase)) / 2;
  const scaleX = .992 + .016 * breath, scaleY = .988 + .024 * breath;
  const pivot = {x: 256, y: 403};
  function layer(index, x, y, width, height) {
    const source = layers[index];
    ctx.drawImage(image, source.left, source.top, source.right - source.left, source.bottom - source.top,
      x, y, width, height);
  }
  ctx.save();
  ctx.translate(pivot.x, pivot.y); ctx.scale(scaleX, scaleY); ctx.translate(-pivot.x, -pivot.y);
  layer(2, 88, 88, 336, 315);
  const cells = [
    {index: 3, x: 192, y: 190, size: 82, phase: .4},
    {index: 4, x: 309, y: 224, size: 78, phase: 2.5},
    {index: 5, x: 242, y: 292, size: 83, phase: 4.2},
  ];
  for (const cell of cells) {
    const x = cell.x + .8 * Math.sin(phase + cell.phase);
    const y = cell.y + 1.6 * Math.sin(phase + cell.phase);
    const size = cell.size * (1 + .006 * Math.sin(phase + cell.phase));
    layer(cell.index, x - size / 2, y - size / 2, size, size);
  }
  ctx.restore();
  // The complete bone housing is painted last, at exactly the same coordinates.
  const bone = layers[1], boneWidth = 436;
  const boneHeight = boneWidth * (bone.bottom - bone.top) / (bone.right - bone.left);
  layer(1, 256 - boneWidth / 2, 440 - boneHeight, boneWidth, boneHeight);
  return canvas;
}

async function main() {
  const [source, output] = process.argv.slice(2);
  if (!source || !output) throw new Error('Provide source image and a new output directory');
  if (fs.existsSync(output)) throw new Error('Output already exists; use a new version directory');
  const image = await loadImage(source), layers = components(image);
  fs.mkdirSync(output, {recursive: true});
  fs.copyFileSync(source, path.join(output, 'gpt-source-components.png'));
  fs.writeFileSync(path.join(output, 'layer-bounds.json'), JSON.stringify(layers, null, 2) + '\n');
  const names = ['reference', 'bone', 'marrow', 'white-cell-1', 'white-cell-2', 'white-cell-3'];
  layers.forEach((box, index) => {
    const canvas = createCanvas(box.right - box.left, box.bottom - box.top);
    canvas.getContext('2d').drawImage(image, box.left, box.top, canvas.width, canvas.height, 0, 0, canvas.width, canvas.height);
    fs.writeFileSync(path.join(output, names[index] + '.png'), canvas.toBuffer('image/png'));
  });
  const atlas = createCanvas(5 * 512, 4 * 512), atlasContext = atlas.getContext('2d');
  const frames = [], hashes = [];
  for (let i = 0; i < 20; i++) {
    const canvas = render(image, layers, 2 * Math.PI * i / 20);
    const name = `frame-${String(i + 1).padStart(3, '0')}.png`;
    const buffer = canvas.toBuffer('image/png');
    fs.writeFileSync(path.join(output, name), buffer);
    hashes.push(crypto.createHash('sha256').update(buffer).digest('hex'));
    atlasContext.drawImage(canvas, i % 5 * 512, Math.floor(i / 5) * 512);
    frames.push({name, duration: 100, rect: {x: i % 5 * 512, y: Math.floor(i / 5) * 512, w: 512, h: 512},
      anchor: {x: .5, y: 440 / 512}, phase: 2 * Math.PI * i / 20});
  }
  fs.writeFileSync(path.join(output, 'spritesheet.png'), atlas.toBuffer('image/png'));
  const initial = render(image, layers, 0).getContext('2d').getImageData(0, 0, 512, 512).data;
  const wrapped = render(image, layers, 2 * Math.PI).getContext('2d').getImageData(0, 0, 512, 512).data;
  if (!Buffer.from(initial).equals(Buffer.from(wrapped))) throw new Error('Curve does not close exactly');
  const metadata = {name: '骨髓造血巢 · 三白细胞版', animation: 'idle', frameCount: 20, fps: 10, loop: true,
    durationMs: 2000, width: 512, height: 512, columns: 5, rows: 4,
    spritesheet: 'spritesheet.png', preview: 'preview.webp',
    generatedBy: 'OpenAI image generation for revised artwork; deterministic layer animation for twenty frames.',
    processing: 'The same bone, marrow and three white-cell drawings are reused in all frames; no pose redrawing, morphing or crossfading.',
    loopCurve: 'periodic sine/cosine; phase 2π is pixel-identical to phase 0; the duplicate endpoint is not exported.',
    sourceSHA256: crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex'), frames};
  fs.writeFileSync(path.join(output, 'animation.json'), JSON.stringify(metadata, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'render-checks.json'), JSON.stringify({frames: 20, uniqueFrames: new Set(hashes).size,
    exactCycleClosure: true, boneTransformFixed: true, whiteCellCount: 3, durationMs: 2000}, null, 2) + '\n');
  console.log(JSON.stringify({output, frames: 20, durationMs: 2000, exactCycleClosure: true, layers}));
}
module.exports = {components};
if (require.main === module) main().catch(error => {console.error(error.message); process.exit(1);});
