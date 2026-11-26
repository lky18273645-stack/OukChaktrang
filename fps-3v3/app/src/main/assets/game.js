'use strict';
(function () {
const $ = id => document.getElementById(id), R = Math.random, PI = Math.PI;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v, lerp = (a, b, t) => a + (b - a) * t;
const angd = (a, b) => { let d = (b - a) % (2 * PI); if (d > PI) d -= 2 * PI; if (d < -PI) d += 2 * PI; return d; };

/* ============================ DATA ============================ */
const W = {
  glock:    { n: 'Glock-18', s: 2, k: 'pistol', dmg: 22, rate: 7, mag: 20, res: 100, spr: .018, pel: 1, auto: 0, rel: 1.5, spd: 1, price: 0 },
  deagle:   { n: 'Desert Eagle', s: 2, k: 'pistol', dmg: 56, rate: 2.3, mag: 7, res: 35, spr: .01, pel: 1, auto: 0, rel: 2, spd: 1, price: 400 },
  nova:     { n: 'Nova', s: 1, k: 'shotgun', dmg: 12, rate: 1.2, mag: 8, res: 32, spr: .055, pel: 8, auto: 0, rel: 2.2, spd: .95, price: 600 },
  xm1014:   { n: 'XM1014', s: 1, k: 'shotgun', dmg: 10, rate: 3, mag: 7, res: 35, spr: .06, pel: 7, auto: 1, rel: 2.4, spd: .95, price: 900 },
  mp5:      { n: 'MP5', s: 1, k: 'smg', dmg: 19, rate: 13, mag: 30, res: 120, spr: .04, pel: 1, auto: 1, rel: 1.8, spd: 1.02, price: 0 },
  p90:      { n: 'P90', s: 1, k: 'smg', dmg: 17, rate: 16, mag: 50, res: 150, spr: .045, pel: 1, auto: 1, rel: 2.2, spd: 1.02, price: 800 },
  ak47:     { n: 'AK-47', s: 1, k: 'rifle', dmg: 33, rate: 10, mag: 30, res: 90, spr: .032, pel: 1, auto: 1, rel: 2.3, spd: .96, price: 1000 },
  m4a1:     { n: 'M4A1', s: 1, k: 'rifle', dmg: 28, rate: 11, mag: 30, res: 90, spr: .025, pel: 1, auto: 1, rel: 2.1, spd: .97, price: 0 },
  awp:      { n: 'AWP', s: 1, k: 'sniper', dmg: 115, rate: .8, mag: 5, res: 25, spr: .07, pel: 1, auto: 0, rel: 3, spd: .9, price: 1500, scope: 1 },
  karambit: { n: 'Karambit', s: 3, k: 'knife', dmg: 52, rate: 2.2, rng: 2.5, spd: 1.15, price: 500, blade: 'curve' },
  butterfly:{ n: 'Butterfly Knife', s: 3, k: 'knife', dmg: 48, rate: 2.6, rng: 2.4, spd: 1.15, price: 600, blade: 'thin' },
  m9:       { n: 'M9 Bayonet', s: 3, k: 'knife', dmg: 50, rate: 2.2, rng: 2.6, spd: 1.15, price: 0, blade: 'bayo' },
  bowie:    { n: 'Tactical Bowie', s: 3, k: 'knife', dmg: 60, rate: 1.9, rng: 2.6, spd: 1.12, price: 700, blade: 'wide' }
};
const SK = { default: { n: 'Default', p: 0 }, lore: { n: 'Dragon Lore', p: 2500 }, asiimov: { n: 'Asiimov', p: 1800 },
  web: { n: 'Crimson Web', p: 1500 }, fade: { n: 'Fade', p: 2000 }, gold: { n: 'Gold', p: 3000 } };
const WIDS = Object.keys(W);

/* ============================ SAVE ============================ */
const SAVE_KEY = 'fps3v3_v1';
let S = { coins: 800, rp: 0, owned: ['glock', 'mp5', 'm4a1', 'm9'], skinsOwned: ['default'], skin: {}, load: { 1: 'm4a1', 2: 'glock', 3: 'm9' }, st: { w: 0, l: 0, k: 0, d: 0 }, fps: 60 };
try {
  let raw = '';
  try { if (window.Native) raw = window.Native.getSave(); } catch (e) {}
  if (!raw) raw = localStorage.getItem(SAVE_KEY) || '';
  if (raw) S = Object.assign(S, JSON.parse(raw));
} catch (e) {}
function save() {
  const j = JSON.stringify(S);
  try { localStorage.setItem(SAVE_KEY, j); } catch (e) {}
  try { if (window.Native) window.Native.putSave(j); } catch (e) {}
}

/* ============================ RANKS ============================ */
const ROM = ['', 'I', 'II', 'III', 'IV', 'V'];
const DIV = [];
[['Warrior', 3], ['Elite', 3], ['Master', 4], ['Grandmaster', 5], ['Epic', 5], ['Legend', 5]].forEach(t => { for (let i = t[1]; i >= 1; i--) DIV.push(t[0] + ' ' + ROM[i]); });
const TOP = ['Mythic', 'Mythical Honor', 'Mythical Glory', 'Mythic Immortal'];
function rankOf(rp) {
  const i = Math.floor(rp / 50);
  if (i < DIV.length) return { name: DIV[i], stars: Math.floor(rp % 50 / 10) + 1, mx: 5, idx: i };
  const m = rp - DIV.length * 50;
  return { name: TOP[Math.min(3, Math.floor(m / 250))], stars: Math.floor(m / 10), mx: 0, idx: DIV.length + Math.min(3, Math.floor(m / 250)) };
}
const rankTxt = rp => { const r = rankOf(rp); return r.name + ' ★' + r.stars; };

/* ============================ AUDIO ============================ */
let AC, NB;
function audio() {
  if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); NB = AC.createBuffer(1, AC.sampleRate >> 1, AC.sampleRate); const d = NB.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = R() * 2 - 1; } catch (e) { AC = null; } }
  if (AC && AC.state === 'suspended') AC.resume();
}
function noise(dur, f, vol, type) {
  if (!AC) return; const s = AC.createBufferSource(); s.buffer = NB; const fl = AC.createBiquadFilter(); fl.type = type || 'lowpass'; fl.frequency.value = f;
  const g = AC.createGain(), t = AC.currentTime; g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.001, t + dur);
  s.connect(fl); fl.connect(g); g.connect(AC.destination); s.start(t); s.stop(t + dur);
}
function tone(f, dur, vol, type, f2) {
  if (!AC) return; const o = AC.createOscillator(), g = AC.createGain(), t = AC.currentTime; o.type = type || 'sine'; o.frequency.setValueAtTime(f, t);
  if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + dur); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.001, t + dur);
  o.connect(g); g.connect(AC.destination); o.start(t); o.stop(t + dur);
}
function sfx(k, v) {
  v = v == null ? 1 : v; if (!AC || v < .03) return;
  switch (k) {
    case 'pistol': noise(.12, 2400, .5 * v); tone(220, .08, .2 * v, 'square', 80); break;
    case 'smg': noise(.09, 3200, .38 * v); break;
    case 'rifle': noise(.16, 1900, .6 * v); tone(110, .1, .25 * v, 'sawtooth', 50); break;
    case 'shotgun': noise(.32, 900, .9 * v); tone(80, .2, .4 * v, 'square', 40); break;
    case 'sniper': noise(.55, 650, 1 * v); tone(70, .35, .5 * v, 'sawtooth', 30); break;
    case 'knife': noise(.14, 5000, .35 * v, 'highpass'); break;
    case 'hit': tone(1100, .05, .25, 'square'); break;
    case 'head': tone(1700, .09, .3, 'square'); break;
    case 'reload': noise(.04, 5000, .4 * v, 'highpass'); setTimeout(() => noise(.05, 4200, .4 * v, 'highpass'), 450); break;
    case 'step': noise(.05, 500, .12 * v); break;
    case 'hurt': tone(160, .15, .4, 'sawtooth', 70); break;
  }
}

/* ============================ TEXTURES ============================ */
const rng = seed => () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const skinCache = {}, skinMats = {};
function skinCanvas(id) {
  if (skinCache[id]) return skinCache[id];
  const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d'), r = rng(id.length * 977 + id.charCodeAt(0)); let gr;
  if (id === 'default') { gr = g.createLinearGradient(0, 0, 128, 128); gr.addColorStop(0, '#6a6f78'); gr.addColorStop(1, '#2b2e33'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); }
  else if (id === 'lore') { g.fillStyle = '#123a22'; g.fillRect(0, 0, 128, 128); g.strokeStyle = '#e7b93a'; g.lineWidth = 3; for (let i = 0; i < 10; i++) { g.beginPath(); g.arc(r() * 128, r() * 128, 10 + r() * 30, r() * 6, r() * 6 + 3); g.stroke(); } g.fillStyle = '#c0392b'; for (let i = 0; i < 12; i++) g.fillRect(r() * 128, r() * 128, 6, 3); }
  else if (id === 'asiimov') { g.fillStyle = '#ececf0'; g.fillRect(0, 0, 128, 128); g.fillStyle = '#ff6a00'; g.fillRect(0, 30, 128, 20); g.fillStyle = '#111'; g.fillRect(0, 70, 128, 14); g.fillRect(0, 100, 128, 6); g.fillStyle = '#222'; g.font = 'bold 18px sans-serif'; g.fillText('ASIIMOV', 14, 20); }
  else if (id === 'web') { g.fillStyle = '#2a0608'; g.fillRect(0, 0, 128, 128); g.strokeStyle = '#d3202a'; g.lineWidth = 1.5; for (let i = 0; i < 14; i++) { g.beginPath(); g.moveTo(64, 64); g.lineTo(64 + Math.cos(i * .45) * 100, 64 + Math.sin(i * .45) * 100); g.stroke(); } for (let k = 1; k < 7; k++) { g.beginPath(); g.arc(64, 64, k * 14, 0, 6.3); g.stroke(); } }
  else if (id === 'fade') { gr = g.createLinearGradient(0, 0, 128, 0); gr.addColorStop(0, '#ffd23f'); gr.addColorStop(.5, '#ff5f8f'); gr.addColorStop(1, '#7a3cff'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); }
  else { gr = g.createLinearGradient(0, 0, 128, 128); gr.addColorStop(0, '#fff3a0'); gr.addColorStop(.4, '#e0a800'); gr.addColorStop(.7, '#fbe27a'); gr.addColorStop(1, '#a87400'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); }
  return (skinCache[id] = c);
}
function skinMat(id) { return skinMats[id] || (skinMats[id] = new THREE.MeshLambertMaterial({ map: new THREE.CanvasTexture(skinCanvas(id)) })); }
const envCache = {}, matCache = {};
function envTex(kind) {
  if (envCache[kind]) return envCache[kind];
  const c = document.createElement('canvas'); c.width = c.height = 64; const g = c.getContext('2d'), r = rng(kind.length * 131 + kind.charCodeAt(0));
  const base = { sand: '#d8c08c', brick: '#b87a5c', concrete: '#a8a8a8', metal: '#8a9aa8', crate: '#a67c4a', asphalt: '#44474c' }[kind];
  g.fillStyle = base; g.fillRect(0, 0, 64, 64);
  for (let i = 0; i < 160; i++) { g.fillStyle = r() < .5 ? '#0002' : '#fff2'; g.fillRect(r() * 64, r() * 64, 2, 2); }
  g.strokeStyle = '#0004'; g.lineWidth = 1;
  if (kind === 'brick') { for (let y = 0; y < 64; y += 8) { g.beginPath(); g.moveTo(0, y); g.lineTo(64, y); g.stroke(); for (let x = (y / 8) % 2 ? 0 : 8; x < 64; x += 16) { g.beginPath(); g.moveTo(x, y); g.lineTo(x, y + 8); g.stroke(); } } }
  if (kind === 'metal') { for (let x = 0; x < 64; x += 6) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, 64); g.stroke(); } }
  if (kind === 'crate') { g.strokeRect(2, 2, 60, 60); g.beginPath(); g.moveTo(2, 2); g.lineTo(62, 62); g.moveTo(62, 2); g.lineTo(2, 62); g.stroke(); }
  if (kind === 'asphalt') { g.fillStyle = '#e8d44a'; g.fillRect(0, 30, 64, 3); }
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; return (envCache[kind] = t);
}
function envMat(tex, col) { const k = tex + col; return matCache[k] || (matCache[k] = new THREE.MeshLambertMaterial({ map: envTex(tex), color: col })); }

/* ============================ MAP BUILDING ============================ */
let boxes = [], rl = [], cover = [], posts = [], spawns = { 0: [], 1: [] }, mapSize = 50;
function addBox(x0, y0, z0, x1, y1, z1, tex, col) {
  if (x1 - x0 < .01 || y1 - y0 < .01 || z1 - z0 < .01) return;
  boxes.push({ x0, y0, z0, x1, y1, z1 }); rl.push({ x0, y0, z0, x1, y1, z1, tex, col });
}
function mergeBoxes(list) {
  const groups = {};
  list.forEach(b => { const k = b.tex + '|' + b.col + '|' + Math.floor((b.x0 + b.x1) / 48) + '|' + Math.floor((b.z0 + b.z1) / 48); (groups[k] = groups[k] || []).push(b); });
  const out = new THREE.Group();
  for (const k in groups) {
    const arr = groups[k], pos = [], nor = [], uv = [], idx = []; let off = 0;
    arr.forEach(b => {
      const w = b.x1 - b.x0, h = b.y1 - b.y0, d = b.z1 - b.z0, g = new THREE.BoxGeometry(w, h, d);
      const p = g.attributes.position.array, n = g.attributes.normal.array, u = g.attributes.uv.array, ix = g.index.array;
      const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2, cz = (b.z0 + b.z1) / 2, fs = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
      for (let i = 0; i < 24; i++) { pos.push(p[i * 3] + cx, p[i * 3 + 1] + cy, p[i * 3 + 2] + cz); nor.push(n[i * 3], n[i * 3 + 1], n[i * 3 + 2]); const f = fs[i >> 2]; uv.push(u[i * 2] * f[0] / 3, u[i * 2 + 1] * f[1] / 3); }
      for (let i = 0; i < ix.length; i++) idx.push(ix[i] + off); off += 24; g.dispose();
    });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); geo.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); geo.setIndex(idx);
    geo.computeBoundingSphere(); geo.computeBoundingBox();
    const m = new THREE.Mesh(geo, envMat(arr[0].tex, arr[0].col)); m.frustumCulled = true; out.add(m);
  }
  return out;
}
// wall running along axis ax ('x' => at z=fixed), with openings [{a,b,y0,y1}]
function wall(ax, fixed, a0, a1, y0, y1, th, ops, tex, col) {
  const seg = (s0, s1, ya, yb) => { if (s1 - s0 < .01 || yb - ya < .01) return; ax === 'x' ? addBox(s0, ya, fixed - th / 2, s1, yb, fixed + th / 2, tex, col) : addBox(fixed - th / 2, ya, s0, fixed + th / 2, yb, s1, tex, col); };
  let cur = a0; ops.sort((p, q) => p.a - q.a);
  for (const o of ops) { seg(cur, o.a, y0, y1); seg(o.a, o.b, y0, o.y0); seg(o.a, o.b, o.y1, y1); cur = o.b; }
  seg(cur, a1, y0, y1);
}
function slab(x0, z0, x1, z1, y, h, tex, col) {
  const b = (a, a2, c, c2) => { if (a2 - a > .01 && c2 - c > .01) addBox(a, y - .3, c, a2, y, c2, tex, col); };
  if (!h) { b(x0, x1, z0, z1); return; }
  b(x0, h.x0, z0, z1); b(h.x1, x1, z0, z1); b(h.x0, h.x1, z0, h.z0); b(h.x0, h.x1, h.z1, z1);
}
// multi-story enterable building with windows, door (south), stairs and roof; registers bot routes
function building(cx, cz, w, d, n, tex, col) {
  const x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2, H = 3.2, T = .4, ST = tex === 'brick' ? 'concrete' : 'concrete';
  for (let f = 0; f < n; f++) {
    const y0 = f * H, y1 = y0 + H, so = [], no = [], eo = [], wo = [];
    for (let a = x0 + 2; a < x1 - 3; a += 4) {
      if (f === 0 && Math.abs(a + .9 - cx) < 2.2) continue;
      so.push({ a, b: a + 1.8, y0: y0 + 1, y1: y0 + 2.3 }); no.push({ a, b: a + 1.8, y0: y0 + 1, y1: y0 + 2.3 });
    }
    if (f === 0) { so.push({ a: cx - .9, b: cx + .9, y0: y0, y1: 2.5 }); no.push({ a: cx - .9, b: cx + .9, y0: y0, y1: 2.5 }); }
    for (let a = z0 + 3; a < z1 - 4; a += 4) { eo.push({ a, b: a + 1.6, y0: y0 + 1, y1: y0 + 2.3 }); wo.push({ a, b: a + 1.6, y0: y0 + 1, y1: y0 + 2.3 }); }
    wall('x', z1 - T / 2, x0, x1, y0, y1, T, so, tex, col); wall('x', z0 + T / 2, x0, x1, y0, y1, T, no, tex, col);
    wall('z', x1 - T / 2, z0 + T, z1 - T, y0, y1, T, eo, tex, col); wall('z', x0 + T / 2, z0 + T, z1 - T, y0, y1, T, wo, tex, col);
    // stairs f -> f+1
    const east = f % 2 === 0, sx0 = east ? x1 - 2 : x0 + .4, sx1 = east ? x1 - .4 : x0 + 2;
    for (let i = 0; i < 8; i++) {
      const za = east ? z0 + 1.2 + .8 * i : z1 - 1.2 - .8 * (i + 1);
      addBox(sx0, y0, za, sx1, y0 + (i + 1) * .4, za + .8, 'crate', 0xcccccc);
    }
    const hole = east ? { x0: sx0, x1: sx1, z0: z0 + 1.2, z1: z0 + 7.6 } : { x0: sx0, x1: sx1, z0: z1 - 7.6, z1: z1 - 1.2 };
    slab(x0, z0, x1, z1, y1, hole, ST, 0xbbbbbb);
  }
  const ry = n * H; // parapet
  addBox(x0, ry, z0, x1, ry + .9, z0 + .3, tex, col); addBox(x0, ry, z1 - .3, x1, ry + .9, z1, tex, col);
  addBox(x0, ry, z0 + .3, x0 + .3, ry + .9, z1 - .3, tex, col); addBox(x1 - .3, ry, z0 + .3, x1, ry + .9, z1 - .3, tex, col);
  // routes for bots (outside -> inside -> up stairs -> window post)
  for (let f = 0; f <= n; f++) {
    const r = [{ x: cx, z: z1 + 3 }, { x: cx, z: z1 - 1.6 }];
    for (let k = 0; k < f; k++) {
      if (k % 2 === 0) { r.push({ x: x1 - 1.2, z: z0 + .8 }, { x: x1 - 1.2, z: z0 + 8.3 }); }
      else { r.push({ x: x0 + 1.2, z: z1 - .8 }, { x: x0 + 1.2, z: z0 + 3.7 }); }
    }
    r.push({ x: x0 + 3 + R() * (w - 6), z: z1 - 1.1 });
    posts.push(r);
  }
}
function container(x, z, rot, col, lv) {
  const w = rot ? 2.5 : 6.1, d = rot ? 6.1 : 2.5;
  for (let l = 0; l < (lv || 1); l++) addBox(x - w / 2, l * 2.6, z - d / 2, x + w / 2, (l + 1) * 2.6, z + d / 2, 'metal', col);
}
function crate(x, z, s) { addBox(x - s / 2, 0, z - s / 2, x + s / 2, s, z + s / 2, 'crate', 0xffffff); }
function lowWall(x0, z0, x1, z1, h, tex, col) { addBox(x0, 0, z0, x1, h, z1, tex || 'concrete', col || 0xcccccc); }
function car(x, z, rot, col) { const w = rot ? 2 : 4.2, d = rot ? 4.2 : 2; addBox(x - w / 2, 0, z - d / 2, x + w / 2, 1.1, z + d / 2, 'metal', col); addBox(x - w / 2 * .6, 1.1, z - d / 2 * .6, x + w / 2 * .6, 1.7, z + d / 2 * .6, 'metal', col); }

const MAPS = {
  dust: { n: 'Dust Arena', sky: 0xe3c88d, ground: 'sand', gc: 0xffffff, size: 50, desc: 'Open sandy lanes, two houses with windows, crates.',
    build() {
      building(-24, -12, 16, 12, 2, 'brick', 0xd9a77a); building(24, 10, 16, 12, 3, 'brick', 0xc99765); building(-8, 22, 14, 12, 1, 'brick', 0xd9b58a);
      container(0, -26, 0, 0x3b6ea8, 1); container(2, -23, 1, 0xa8523b, 1); container(-14, 6, 1, 0x4a8a50, 2); container(14, -8, 0, 0xb08a2a, 1);
      lowWall(-4, -3, 4, -2.4, 1.3); lowWall(-4, 2.4, 4, 3, 1.3); lowWall(-1, -2.4, -.4, 2.4, 1.3);
      [[-34, 10], [-33, 12], [34, -18], [10, 28], [-12, -32], [30, -34], [6, 8], [-26, 30], [36, 34]].forEach(p => crate(p[0], p[1], 1.3 + R() * .8));
      lowWall(18, -30, 26, -29.4, 1.4); lowWall(-30, 22, -29.4, 30, 1.4);
    } },
  urban: { n: 'Urban Rooftops', sky: 0x8fb4d6, ground: 'asphalt', gc: 0xffffff, size: 50, desc: 'Tall towers, street cars, roofs for snipers.',
    build() {
      building(-27, -20, 14, 12, 4, 'brick', 0x9a6a5a); building(27, -20, 14, 12, 3, 'brick', 0x8a7a6a); building(-27, 22, 14, 12, 3, 'brick', 0x7a8a9a); building(27, 22, 14, 12, 4, 'brick', 0xa07a5a);
      building(0, 0, 12, 12, 2, 'concrete', 0xb0b0b0);
      car(-8, -26, 0, 0xb02a2a); car(8, 30, 0, 0x2a5ab0); car(-10, 12, 1, 0xd0d0d0); car(11, -12, 1, 0x2a2a2a); car(0, -14, 0, 0xc0a020); car(0, 16, 0, 0x30a050);
      lowWall(-16, -2, -12, -1, 1.2); lowWall(12, 1, 16, 2, 1.2); lowWall(-3, 30, 3, 30.6, 1.2); lowWall(-3, -30, 3, -30.6, 1.2);
      crate(-18, 0, 1.4); crate(18, 0, 1.4); crate(-6, 36, 1.2); crate(6, -36, 1.2);
    } },
  ware: { n: 'Warehouse Compound', sky: 0x7d8ea0, ground: 'concrete', gc: 0xdddddd, size: 50, desc: 'Big warehouse, container rows, crates.',
    build() {
      building(0, -6, 34, 20, 1, 'metal', 0x9aa6b2); building(26, 26, 14, 12, 2, 'brick', 0xa88a6a);
      for (let i = 0; i < 4; i++) { container(-36 + i * 6.4, 30, 0, [0x3b6ea8, 0xa8523b, 0x4a8a50, 0xb08a2a][i], 1 + (i % 2)); }
      for (let i = 0; i < 3; i++) container(-30 + i * 14, -32, 0, [0xa8523b, 0x3b6ea8, 0x777777][i], 1 + (i % 2));
      container(-38, 8, 1, 0x4a8a50, 2); container(-38, -8, 1, 0xa8523b, 1); container(40, -22, 1, 0x3b6ea8, 1); container(40, 4, 1, 0xb08a2a, 2);
      [[-16, 14], [-18, 15.5], [14, 16], [-26, -16], [26, -6], [32, 10], [12, -30], [-6, 38]].forEach(p => crate(p[0], p[1], 1.3 + R() * .9));
      lowWall(-10, 12, 10, 12.6, 1.3); lowWall(18, -14, 30, -13.4, 1.3);
    } }
};

function loadMap(id) {
  const md = MAPS[id]; boxes = []; rl = []; cover = []; posts = []; spawns = { 0: [], 1: [] }; mapSize = md.size; md.build();
  const s = mapSize, wt = 'concrete';
  addBox(-s - 1, 0, -s - 1, s + 1, 6, -s, wt, 0x999999); addBox(-s - 1, 0, s, s + 1, 6, s + 1, wt, 0x999999);
  addBox(-s - 1, 0, -s, -s, 6, s, wt, 0x999999); addBox(s, 0, -s, s + 1, 6, s, wt, 0x999999);
  for (let i = -1; i <= 1; i++) { spawns[0].push({ x: i * 7, z: s - 6 }); spawns[1].push({ x: i * 7, z: -s + 6 }); }
  // keep only spawn points that are free, then compute cover points near tall boxes
  boxes.forEach(b => {
    if (b.y0 < .3 && b.y1 - b.y0 > 1.2 && b.y1 < 7 && b.x1 < s && b.x0 > -s) {
      [[b.x0 - .9, b.z0 - .9], [b.x1 + .9, b.z0 - .9], [b.x0 - .9, b.z1 + .9], [b.x1 + .9, b.z1 + .9]].forEach(p => { if (Math.abs(p[0]) < s - 2 && Math.abs(p[1]) < s - 2 && !blocked(p[0], 0, p[1], .4, 1.8)) cover.push({ x: p[0], z: p[1] }); });
    }
  });
  if (cover.length > 160) cover = cover.filter(() => R() < 160 / cover.length);
  return md;
}

/* ============================ PHYSICS ============================ */
const STEP = .55;
function blocked(x, y, z, r, h) {
  for (let i = 0; i < boxes.length; i++) { const b = boxes[i]; if (x + r > b.x0 && x - r < b.x1 && z + r > b.z0 && z - r < b.z1 && b.y1 > y + STEP && b.y0 < y + h) return true; }
  return false;
}
function groundAt(x, z, r, y) {
  let g = 0; for (let i = 0; i < boxes.length; i++) { const b = boxes[i]; if (b.y1 <= y + STEP && b.y1 > g && x + r > b.x0 && x - r < b.x1 && z + r > b.z0 && z - r < b.z1) g = b.y1; } return g;
}
function moveEnt(e, dt) {
  const r = .35, h = e.crouch ? 1.3 : 1.8;
  let nx = e.x + e.vx * dt; if (!blocked(nx, e.y, e.z, r, h)) e.x = nx; else e.vx = 0;
  let nz = e.z + e.vz * dt; if (!blocked(e.x, e.y, nz, r, h)) e.z = nz; else e.vz = 0;
  e.vy -= 22 * dt; let ny = e.y + e.vy * dt; const g = groundAt(e.x, e.z, r, e.y);
  if (e.vy > 0) {
    for (let i = 0; i < boxes.length; i++) { const b = boxes[i]; if (b.y0 >= e.y + h - .05 && b.y0 < ny + h && e.x + r > b.x0 && e.x - r < b.x1 && e.z + r > b.z0 && e.z - r < b.z1) { e.vy = 0; ny = b.y0 - h; break; } }
    e.y = ny; e.gr = false;
  } else if (ny <= g + .001) { e.y = g; e.vy = 0; e.gr = true; }
  else if (e.gr && e.y - g <= STEP) { e.y = g; e.vy = 0; }
  else { e.y = ny; e.gr = false; }
}
function rayBox(ox, oy, oz, dx, dy, dz, b) {
  let t0 = 0, t1 = 1e9, a, c, t;
  if (Math.abs(dx) < 1e-9) { if (ox < b.x0 || ox > b.x1) return 1e9; } else { a = (b.x0 - ox) / dx; c = (b.x1 - ox) / dx; if (a > c) { t = a; a = c; c = t; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return 1e9; }
  if (Math.abs(dy) < 1e-9) { if (oy < b.y0 || oy > b.y1) return 1e9; } else { a = (b.y0 - oy) / dy; c = (b.y1 - oy) / dy; if (a > c) { t = a; a = c; c = t; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return 1e9; }
  if (Math.abs(dz) < 1e-9) { if (oz < b.z0 || oz > b.z1) return 1e9; } else { a = (b.z0 - oz) / dz; c = (b.z1 - oz) / dz; if (a > c) { t = a; a = c; c = t; } if (a > t0) t0 = a; if (c < t1) t1 = c; if (t0 > t1) return 1e9; }
  return t0;
}
function rayWorld(ox, oy, oz, dx, dy, dz, mx) {
  let best = mx; for (let i = 0; i < boxes.length; i++) { const t = rayBox(ox, oy, oz, dx, dy, dz, boxes[i]); if (t < best) best = t; }
  if (dy < 0) { const t = -oy / dy; if (t > 0 && t < best) best = t; }
  return best;
}
const hb = { x0: 0, y0: 0, z0: 0, x1: 0, y1: 0, z1: 0 };
function setBox(x0, y0, z0, x1, y1, z1) { hb.x0 = x0; hb.y0 = y0; hb.z0 = z0; hb.x1 = x1; hb.y1 = y1; hb.z1 = z1; return hb; }
const eyeH = e => e.crouch ? 1.15 : 1.65;
const eyeY = e => e.y + eyeH(e);

/* ============================ GAME STATE ============================ */
let scene, camera, renderer, vm, vmModel, flash, ents = [], pl, T = 0, state = 'menu', matchT = 0, frz = 0, mapId = 'dust', mins = 3;
let score = [0, 0], mCoins = 0, tracers = [], sparks = [], feedEl = $('feed'), fpsCap = S.fps || 60;
const inp = { jx: 0, jy: 0, dx: 0, dy: 0, fire: false, firePrev: false, jump: false, reload: false, swap: false };
const NAMES = [['You', 'Alpha', 'Bravo'], ['Charlie', 'Delta', 'Echo']];

renderer = new THREE.WebGLRenderer({ canvas: $('c'), antialias: false, powerPreference: 'high-performance', alpha: false });
camera = new THREE.PerspectiveCamera(75, 2, .05, 150);
function resize() { renderer.setPixelRatio(Math.min((window.devicePixelRatio || 1) * .75, 1.25)); renderer.setSize(innerWidth, innerHeight, false); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); }
window.addEventListener('resize', resize); resize();

// shared character geometry (low-poly)
const gTorso = new THREE.BoxGeometry(.55, .7, .3), gHead = new THREE.BoxGeometry(.3, .3, .3), gLeg = new THREE.BoxGeometry(.24, .7, .26), gGun = new THREE.BoxGeometry(.08, .1, .55);
const mHead = new THREE.MeshLambertMaterial({ color: 0xe0b48a }), mDark = new THREE.MeshLambertMaterial({ color: 0x222222 }), mHand = new THREE.MeshLambertMaterial({ color: 0xe0b48a });
const teamMat = [new THREE.MeshLambertMaterial({ color: 0x2f6fd0 }), new THREE.MeshLambertMaterial({ color: 0xc9742b })];
function charMesh(team) {
  const g = new THREE.Group(), m = teamMat[team];
  const add = (geo, mat, x, y, z) => { const o = new THREE.Mesh(geo, mat); o.position.set(x, y, z); g.add(o); };
  add(gTorso, m, 0, 1.05, 0); add(gHead, mHead, 0, 1.58, 0); add(gLeg, mDark, -.14, .35, 0); add(gLeg, mDark, .14, .35, 0); add(gGun, mDark, .3, 1.15, -.3);
  return g;
}

/* ---------- pooled effects ---------- */
function initPools() {
  tracers = []; sparks = [];
  for (let i = 0; i < 24; i++) {
    const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(6), 3));
    const l = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: 0xffe9a0 })); l.visible = false; l.frustumCulled = false; scene.add(l); tracers.push({ m: l, life: 0 });
  }
  const sg = new THREE.BoxGeometry(.07, .07, .07), sm = new THREE.MeshBasicMaterial({ color: 0xffcc66 });
  for (let i = 0; i < 40; i++) { const m = new THREE.Mesh(sg, sm); m.visible = false; scene.add(m); sparks.push({ m, life: 0, vx: 0, vy: 0, vz: 0 }); }
}
let tp = 0, sp = 0;
function tracer(ax, ay, az, bx, by, bz) {
  const t = tracers[tp++ % tracers.length], p = t.m.geometry.attributes.position; p.setXYZ(0, ax, ay, az); p.setXYZ(1, bx, by, bz); p.needsUpdate = true; t.m.visible = true; t.life = .06;
}
function spark(x, y, z, n) {
  for (let i = 0; i < n; i++) { const s = sparks[sp++ % sparks.length]; s.m.position.set(x, y, z); s.vx = (R() - .5) * 4; s.vy = R() * 3; s.vz = (R() - .5) * 4; s.life = .3; s.m.visible = true; }
}
function fxUpdate(dt) {
  for (const t of tracers) if (t.life > 0) { t.life -= dt; if (t.life <= 0) t.m.visible = false; }
  for (const s of sparks) if (s.life > 0) { s.life -= dt; s.vy -= 12 * dt; s.m.position.x += s.vx * dt; s.m.position.y += s.vy * dt; s.m.position.z += s.vz * dt; if (s.life <= 0) s.m.visible = false; }
}

/* ============================ VIEWMODEL ============================ */
function vmBuild(id) {
  const w = W[id], m = skinMat(S.skin[id] || 'default'), g = new THREE.Group();
  const add = (sx, sy, sz, x, y, z, mt, rx) => { const b = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mt || m); b.position.set(x, y, z); if (rx) b.rotation.x = rx; g.add(b); return b; };
  switch (w.k) {
    case 'pistol': add(.05, .06, .24, 0, 0, -.12); add(.045, .11, .06, 0, -.08, -.03, mDark, .2); add(.07, .07, .09, 0, -.1, -.01, mHand); break;
    case 'smg': add(.06, .08, .32, 0, 0, -.16); add(.04, .13, .05, 0, -.1, -.2, mDark); add(.03, .03, .14, 0, 0, -.38, mDark); add(.07, .07, .09, 0, -.09, -.02, mHand); break;
    case 'rifle': add(.06, .09, .42, 0, 0, -.2); add(.035, .035, .3, 0, .01, -.55, mDark); add(.05, .1, .2, 0, -.01, .1, mDark); add(.04, .14, .06, 0, -.11, -.22, mDark, .25); add(.07, .07, .09, 0, -.09, -.03, mHand); break;
    case 'shotgun': add(.06, .08, .3, 0, 0, -.1); add(.035, .035, .55, 0, .02, -.5, mDark); add(.07, .06, .16, 0, -.04, -.35); add(.05, .1, .22, 0, -.01, .15, mDark); add(.07, .07, .09, 0, -.09, -.02, mHand); break;
    case 'sniper': { add(.06, .09, .6, 0, 0, -.2); add(.03, .03, .5, 0, .01, -.7, mDark); add(.05, .1, .22, 0, -.01, .18, mDark); const sc = new THREE.Mesh(new THREE.CylinderGeometry(.03, .03, .24, 8), mDark); sc.rotation.x = PI / 2; sc.position.set(0, .085, -.2); g.add(sc); add(.07, .07, .09, 0, -.09, -.02, mHand); break; }
    default: { add(.035, .035, .14, 0, 0, 0, mDark); const bl = { curve: [.012, .06, .18, -.5], thin: [.008, .05, .2, 0], bayo: [.012, .045, .24, 0], wide: [.014, .08, .22, 0] }[w.blade];
      add(bl[0], bl[1], bl[2], 0, .02, -.16, m, bl[3]); if (w.blade === 'thin') add(.03, .03, .12, .03, 0, .02, mDark); add(.07, .07, .09, 0, -.03, .02, mHand); }
  }
  return g;
}
function vmSet(id) {
  if (vmModel) vm.remove(vmModel); vmModel = vmBuild(id); vm.add(vmModel);
  flash.position.z = { pistol: -.3, smg: -.42, rifle: -.78, shotgun: -.82, sniper: -1.05, knife: 0 }[W[id].k];
}
let vmRecoil = 0, vmSlash = 0, slashDir = 1, adsK = 0, bobT = 0, flashT = 0, camY = 0;
function vmUpdate(dt) {
  const w = W[pl.w], spd = Math.hypot(pl.vx, pl.vz); if (pl.gr) bobT += dt * spd * 1.7;
  let x = .18, y = -.2, z = -.35, rx = 0, ry = 0, rz = 0; adsK = lerp(adsK, pl.ads ? 1 : 0, clamp(dt * 14, 0, 1));
  if (spd > .5 && pl.gr) { const a = .012 * (1 - adsK * .8); x += Math.cos(bobT) * a; y -= Math.abs(Math.sin(bobT)) * a * 1.3; }
  if (pl.sprint) { rz += .35; rx += .3; ry -= .4; x -= .04; y -= .05; }
  x = lerp(x, 0, adsK); y = lerp(y, w.k === 'knife' ? -.2 : -.125, adsK);
  z += vmRecoil * .07; rx += vmRecoil * .12; vmRecoil = Math.max(0, vmRecoil - dt * 8);
  if (pl.reloading) { const p = 1 - pl.rel / w.rel, k = Math.sin(clamp(p, 0, 1) * PI); y -= k * .22; rx -= k * .9; rz += k * .3; }
  if (pl.swT > 0) { const k = pl.swT / .35; y -= k * .3; rx -= k * .6; }
  if (vmSlash > 0) { const p = 1 - vmSlash / .28; rz = lerp(-1.1, 1.3, p) * slashDir; rx = -Math.sin(p * PI) * .6; x += lerp(.15, -.35, p) * slashDir; z -= Math.sin(p * PI) * .2; vmSlash -= dt; }
  vm.position.set(x, y, z); vm.rotation.set(rx, ry, rz);
  flashT -= dt; flash.visible = flashT > 0;
}

/* ============================ ENTITIES ============================ */
function mkEnt(team, idx) {
  const e = { team, idx, name: NAMES[team][idx], isPl: team === 0 && idx === 0, ai: !(team === 0 && idx === 0), x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, yaw: 0, pitch: 0, gr: true, crouch: false, hp: 100, alive: true, prot: 0, resp: 0,
    kills: 0, deaths: 0, w: 'glock', am: {}, cd: 0, rel: 0, reloading: false, swT: 0, ads: false, zoom: 0, sprint: false, mesh: null, load: {} };
  if (e.isPl) e.load = S.load; else e.lo = { knife: ['karambit', 'butterfly', 'm9', 'bowie'][idx % 4], close: ['nova', 'xm1014', 'mp5', 'p90'][Math.floor(R() * 4)], far: ['ak47', 'm4a1', 'awp'][Math.floor(R() * 3)], sec: R() < .5 ? 'glock' : 'deagle' };
  return e;
}
function ammoFill(e) {
  const ids = e.isPl ? [S.load[1], S.load[2], S.load[3]] : [e.lo.knife, e.lo.close, e.lo.far, e.lo.sec];
  e.am = {}; ids.forEach(id => { if (W[id].mag) e.am[id] = { mag: W[id].mag, res: W[id].res }; });
}
function setWeapon(e, id) {
  if (e.w === id && e.am[id] !== undefined || e.reloading && 0) return; e.w = id; e.swT = .35; e.reloading = false; e.cd = .1; e.ads = false; e.zoom = 0;
  if (e.isPl) { vmSet(id); updAmmo(true); }
}
function respawn(e) {
  const sp = spawns[e.team], p = sp[Math.floor(R() * sp.length)];
  e.x = p.x + (R() - .5) * 2; e.z = p.z + (R() - .5) * 2; e.y = 0; e.vx = e.vy = e.vz = 0; e.hp = 100; e.alive = true; e.prot = 2; e.crouch = false;
  e.yaw = e.team === 0 ? 0 : PI; e.pitch = 0; e.reloading = false; e.cd = 0; e.rel = 0;
  ammoFill(e); e.w = ''; setWeapon(e, e.isPl ? S.load[1] : (e.lo.far)); e.swT = .2;
  if (e.ai) { e.coverDone = false; e.coverT = 0; e.tgt = null; e.vis = false; e.route = null; e.camp = 0; e.think = R() * .2; e.huntT = 0; e.seen = -9; e.side = R() < .5 ? 1 : -1; e.unst = 0; e.stT = .5; e.sx = e.x; e.sz = e.z; e.burst = 0; e.react = 0; e.swLock = 0; e.strafeT = 0; e.strafeD = 1; }
  if (e.mesh) e.mesh.visible = !e.isPl;
}
function rayDirOf(e, s) {
  const cp = Math.cos(e.pitch); let dx = -Math.sin(e.yaw) * cp + (R() - .5) * 2 * s, dy = Math.sin(e.pitch) + (R() - .5) * 2 * s, dz = -Math.cos(e.yaw) * cp + (R() - .5) * 2 * s;
  const l = Math.hypot(dx, dy, dz); return [dx / l, dy / l, dz / l];
}
function hitscan(ox, oy, oz, d, range, shooter) {
  let best = rayWorld(ox, oy, oz, d[0], d[1], d[2], range), ent = null, head = false;
  for (const en of ents) {
    if (!en.alive || en.team === shooter.team || en.prot > 0) continue; const h = en.crouch ? 1.3 : 1.8;
    let t = rayBox(ox, oy, oz, d[0], d[1], d[2], setBox(en.x - .17, en.y + h - .35, en.z - .17, en.x + .17, en.y + h + .02, en.z + .17));
    if (t < best) { best = t; ent = en; head = true; }
    t = rayBox(ox, oy, oz, d[0], d[1], d[2], setBox(en.x - .3, en.y, en.z - .3, en.x + .3, en.y + h - .35, en.z + .3));
    if (t < best) { best = t; ent = en; head = false; }
  }
  return { t: best, ent, head };
}
function startReload(e) {
  const w = W[e.w], a = e.am[e.w]; if (!a || e.reloading || a.mag >= w.mag || a.res <= 0) return;
  e.reloading = true; e.rel = w.rel; e.ads = false; if (e.isPl) { sfx('reload'); } else sfx('reload', .2);
}
function tryFire(e) {
  const w = W[e.w]; if (!e.alive || e.cd > 0 || e.reloading || e.swT > 0 || frz > 0) return false;
  if (w.k === 'knife') { e.cd = 1 / w.rate; melee(e, w); return true; }
  const a = e.am[e.w]; if (a.mag <= 0) { startReload(e); return false; }
  a.mag--; e.cd = 1 / w.rate;
  let s = w.spr;
  if (e.isPl) { const mv = Math.hypot(e.vx, e.vz) > 1; s *= (mv ? 1.8 : 1) * (e.ads ? (w.scope ? .03 : .4) : 1) * (e.gr ? 1 : 3) * (e.crouch ? .7 : 1); }
  else { const d = e.td || 20; s = s + .012 + d * .0007; }
  const ox = e.x, oy = eyeY(e), oz = e.z, dm = e.isPl ? 1 : .7;
  for (let i = 0; i < w.pel; i++) {
    const d = rayDirOf(e, s), h = hitscan(ox, oy, oz, d, 120, e), ex = ox + d[0] * h.t, ey = oy + d[1] * h.t, ez = oz + d[2] * h.t;
    if (e.isPl) { const cy = Math.cos(e.yaw), sy = Math.sin(e.yaw); tracer(ox + cy * .2 - d[0] * 0 + d[0] * .6, oy - .15 + d[1] * .6, oz - sy * .2 + d[2] * .6, ex, ey, ez); }
    else tracer(ox + d[0] * .6, oy - .3, oz + d[2] * .6, ex, ey, ez);
    if (h.ent) {
      let dmg = w.dmg * dm; if (w.k === 'shotgun') dmg *= Math.max(.2, 1 - h.t / 18); if (h.head && !w.scope) dmg *= 2.5; else if (h.head) dmg *= 1.5;
      spark(ex, ey, ez, 2); hurt(h.ent, dmg, e, h.head, w);
    } else if (h.t < 119) spark(ex, ey, ez, 2);
  }
  if (e.isPl) {
    vmRecoil = 1; flashT = .05; e.pitch += (w.k === 'sniper' ? .03 : w.k === 'shotgun' ? .035 : w.k === 'pistol' ? .014 : .009) * (1 + R() * .5); e.yaw += (R() - .5) * .006;
    sfx(w.k); if (e.am[e.w].mag === 0) setTimeout(() => { if (e.alive) startReload(e); }, 200); updAmmo(true);
  } else sfx(w.k, .9 / (1 + Math.hypot(e.x - pl.x, e.z - pl.z) / 7));
  return true;
}
function melee(e, w) {
  if (e.isPl) { vmSlash = .28; slashDir = -slashDir; sfx('knife'); }
  const d = rayDirOf(e, 0), ox = e.x, oy = eyeY(e), oz = e.z;
  // wide cone: test small offsets around the aim ray
  for (const off of [0, .25, -.25]) {
    const dd = [d[0] + Math.cos(e.yaw) * off, d[1], d[2] - Math.sin(e.yaw) * off], l = Math.hypot(dd[0], dd[1], dd[2]); dd[0] /= l; dd[1] /= l; dd[2] /= l;
    const h = hitscan(ox, oy, oz, dd, w.rng, e); if (h.ent && h.t <= w.rng) { spark(ox + dd[0] * h.t, oy + dd[1] * h.t, oz + dd[2] * h.t, 4); hurt(h.ent, w.dmg * (e.isPl ? 1 : .8), e, false, w); return; }
  }
}
function hurt(v, amt, att, head, w) {
  if (!v.alive || v.prot > 0 || state !== 'play') return; v.hp -= amt;
  if (att.isPl) { const h = $('hitm'); h.style.opacity = 1; h.style.borderColor = head ? '#ff0' : '#f33'; setTimeout(() => h.style.opacity = 0, 120); sfx(head ? 'head' : 'hit'); }
  if (v.isPl) { $('dmg').style.opacity = 1; setTimeout(() => $('dmg').style.opacity = 0, 250); sfx('hurt'); updHp(); }
  if (v.ai) { v.lx = att.x; v.lz = att.z; v.seen = T - .5; v.alert = att; }
  if (v.hp <= 0) kill(v, att, head, w);
}
function kill(v, att, head, w) {
  v.alive = false; v.hp = 0; v.deaths++; att.kills++; score[att.team]++; v.resp = 3; if (v.mesh) v.mesh.visible = false;
  const d = document.createElement('div'); d.innerHTML = `<span style="color:${att.team ? '#fa5' : '#6cf'}">${att.name}</span> [${w.n}]${head ? ' ⌖' : ''} <span style="color:${v.team ? '#fa5' : '#6cf'}">${v.name}</span>`;
  feedEl.appendChild(d); setTimeout(() => d.remove(), 5000); while (feedEl.children.length > 5) feedEl.firstChild.remove();
  if (att.isPl) mCoins += 10;
  if (v.isPl) { $('msg').textContent = 'Respawning…'; updHp(); }
  $('sCT').textContent = score[0]; $('sT').textContent = score[1];
}

/* ============================ PLAYER ============================ */
let sens = .0042, stepT = 0;
function playerUpdate(dt) {
  const p = pl;
  p.cd -= dt; p.swT -= dt;
  if (p.reloading) { p.rel -= dt; if (p.rel <= 0) { const a = p.am[p.w], w = W[p.w], need = w.mag - a.mag, t = Math.min(need, a.res); a.mag += t; a.res -= t; p.reloading = false; updAmmo(true); } }
  const zf = p.ads && W[p.w].scope ? (p.zoom === 4 ? .25 : .5) : p.ads ? .8 : 1;
  p.yaw -= inp.dx * sens * zf; p.pitch = clamp(p.pitch - inp.dy * sens * zf, -1.45, 1.45); inp.dx = inp.dy = 0;
  const w = W[p.w], mg = Math.hypot(inp.jx, inp.jy), fw = -inp.jy;
  p.sprint = mg > .9 && fw > .6 && !p.ads && !p.crouch && !p.reloading;
  let sp = 5.2 * w.spd * (p.crouch ? .5 : 1) * (p.sprint ? 1.3 : 1) * (p.ads ? .65 : 1);
  const fx = -Math.sin(p.yaw), fz = -Math.cos(p.yaw), rx = Math.cos(p.yaw), rz = -Math.sin(p.yaw);
  const wx = (fx * fw + rx * inp.jx) * sp, wz = (fz * fw + rz * inp.jx) * sp, a = clamp((p.gr ? 14 : 3) * dt, 0, 1);
  p.vx = lerp(p.vx, wx, a); p.vz = lerp(p.vz, wz, a);
  if (inp.jump && p.gr) { p.vy = 7.2; p.gr = false; } inp.jump = false;
  moveEnt(p, dt);
  if (p.gr && mg > .3) { stepT -= dt * sp; if (stepT <= 0) { stepT = 2.4; sfx('step', .8); } }
  if (inp.reload) { startReload(p); inp.reload = false; }
  if (inp.swap) { inp.swap = false; const order = [1, 2, 3], cur = W[p.w].s, nx = order[cur % 3]; setWeapon(p, S.load[nx]); }
  const trig = inp.fire && (w.auto || !inp.firePrev); inp.firePrev = inp.fire;
  if (trig) { if (p.sprint) p.sprint = false; tryFire(p); }
  // camera
  const ty = p.y + eyeH(p); camY = Math.abs(ty - camY) > 1.5 ? ty : lerp(camY, ty, clamp(dt * 16, 0, 1));
  camera.position.set(p.x, camY, p.z); camera.rotation.set(p.pitch, p.yaw, 0, 'YXZ');
  const scoped = p.ads && w.scope, tf = scoped ? (p.zoom === 4 ? 15 : 30) : p.ads ? 58 : (p.sprint ? 80 : 75);
  if (Math.abs(camera.fov - tf) > .1) { camera.fov = lerp(camera.fov, tf, clamp(dt * 14, 0, 1)); camera.updateProjectionMatrix(); }
  $('scope').style.display = scoped && adsK > .8 ? 'block' : 'none'; vm.visible = !(scoped && adsK > .8); $('cross').style.display = p.ads ? 'none' : 'block';
}
let lastAm = '';
function updAmmo(force) {
  const w = W[pl.w], a = pl.am[pl.w], s = w.n + '|' + (a ? a.mag + '/' + a.res : '∞') + (pl.reloading ? 'R' : '');
  if (s === lastAm && !force) return; lastAm = s; $('wn').textContent = w.n + (pl.reloading ? ' (reloading)' : ''); $('am').textContent = a ? a.mag + ' / ' + a.res : '—';
}
function updHp() { $('hpb').style.width = Math.max(0, pl.hp) + '%'; $('hpt').textContent = Math.max(0, Math.ceil(pl.hp)); $('hpb').style.background = pl.hp > 50 ? '#3c4' : pl.hp > 25 ? '#ea3' : '#e33'; }

/* ============================ BOT AI ============================ */
function los(a, b) {
  const ox = a.x, oy = eyeY(a), oz = a.z, dx = b.x - ox, dy = b.y + (b.crouch ? .9 : 1.2) - oy, dz = b.z - oz, l = Math.hypot(dx, dy, dz);
  return rayWorld(ox, oy, oz, dx / l, dy / l, dz / l, l) >= l - .3;
}
function pickCover(b) {
  let best = null, bd = 1e9;
  for (let i = 0; i < 14 && cover.length; i++) {
    const c = cover[Math.floor(R() * cover.length)], d = Math.hypot(c.x - b.x, c.z - b.z); if (d > 28) continue;
    const ex = b.lx || 0, ez = b.lz || 0, dx = ex - c.x, dz = ez - c.z, l = Math.hypot(dx, dz) || 1;
    if (rayWorld(c.x, 1.2, c.z, dx / l, 0, dz / l, l) < l - .5 && d < bd) { bd = d; best = c; }
  }
  b.cover = best || (cover.length ? cover[Math.floor(R() * cover.length)] : { x: b.x, z: b.z });
}
function steer(b, gx, gz) {
  let dx = gx - b.x, dz = gz - b.z; const L = Math.hypot(dx, dz); if (L < .4) { b.wx = b.wz = 0; return L; } dx /= L; dz /= L;
  if (b.unst > 0) { const a = b.side * 1.57, c = Math.cos(a), s = Math.sin(a), nx = dx * c - dz * s; dz = dx * s + dz * c; dx = nx; }
  else for (const o of [0, .6, -.6, 1.1, -1.1, 1.6, -1.6, 2.4]) {
    const a = o * b.side, c = Math.cos(a), s = Math.sin(a), rx = dx * c - dz * s, rz = dx * s + dz * c;
    if (rayWorld(b.x, b.y + .9, b.z, rx, 0, rz, 2) >= 2) { dx = rx; dz = rz; break; }
  }
  b.wx = dx; b.wz = dz; return L;
}
function botUpdate(b, dt) {
  b.cd -= dt; b.swT -= dt; b.think -= dt; b.react -= dt; b.coverT -= dt; b.swLock -= dt; b.camp -= dt; b.unst -= dt; b.burst -= dt; b.strafeT -= dt;
  if (b.reloading) { b.rel -= dt; if (b.rel <= 0) { const a = b.am[b.w], w = W[b.w], t = Math.min(w.mag - a.mag, a.res); a.mag += t; a.res -= t; b.reloading = false; } }
  if (b.think <= 0) {
    b.think = .1 + R() * .08; let best = null, bd = 1e9;
    for (const en of ents) { if (!en.alive || en.team === b.team || en.prot > 1.5) continue; const d = (en.x - b.x) ** 2 + (en.z - b.z) ** 2; if (d < bd && d < 4900 && los(b, en)) { bd = d; best = en; } }
    if (best) { if (b.tgt !== best) b.react = .3 + R() * .25; b.tgt = best; b.seen = T; b.td = Math.sqrt(bd); b.lx = best.x; b.lz = best.z; }
    else if (T - b.seen > 1.5) b.tgt = null;
    b.vis = !!best;
    if (b.vis && b.swLock <= 0) { // weapon choice by distance
      const d = b.td, lo = b.lo; let id = d < 2.4 ? lo.knife : d < 14 ? lo.close : lo.far; const a = b.am[id];
      if (a && a.mag === 0 && a.res === 0) id = lo.sec; if (id !== b.w) { setWeapon(b, id); b.swLock = 1.2; }
    }
    if (b.hp < 40 && !b.coverDone && cover.length) { b.coverDone = true; pickCover(b); b.coverT = 6; }
  }
  const w = W[b.w], tg = b.tgt; let crouch = false, sp = 4.4 * w.spd, mode = 'idle';
  b.wx = b.wz = 0;
  if (tg && b.vis) {
    const d = b.td, pref = w.k === 'sniper' ? 40 : w.k === 'rifle' ? 17 : w.k === 'knife' ? 0 : w.k === 'shotgun' ? 5 : w.k === 'smg' ? 8 : 12;
    if (b.coverT > 0 && b.cover && Math.hypot(b.cover.x - b.x, b.cover.z - b.z) > 1) { steer(b, b.cover.x, b.cover.z); sp *= 1.1; }
    else if (b.coverT > 0) crouch = true;
    else if (w.k === 'sniper') crouch = true;
    else if (d > pref + 3) steer(b, tg.x, tg.z);
    else if (d < pref - 4 && w.k !== 'knife') steer(b, b.x + (b.x - tg.x), b.z + (b.z - tg.z));
    else { if (b.strafeT <= 0) { b.strafeT = .8 + R() * 1.4; b.strafeD = R() < .5 ? -1 : 1; } const dx = tg.x - b.x, dz = tg.z - b.z, l = Math.hypot(dx, dz) || 1; steer(b, b.x - dz / l * b.strafeD * 3, b.z + dx / l * b.strafeD * 3); sp *= .7; }
    mode = 'fight';
  } else if (b.coverT > 0 && b.cover) { if (Math.hypot(b.cover.x - b.x, b.cover.z - b.z) > 1) steer(b, b.cover.x, b.cover.z); else crouch = true; }
  else if (b.route && b.ri < b.route.length) {
    const p = b.route[b.ri]; if (steer(b, p.x, p.z) < 1.1) { b.ri++; if (b.ri >= b.route.length) { b.route = null; b.camp = 7 + R() * 6; } }
  } else if (b.camp > 0) { b.yaw += Math.sin(T * .8 + b.idx) * dt * .8; crouch = R() < .01 ? !b.crouch : b.crouch; }
  else {
    if (T > b.huntT) {
      b.huntT = T + 2.5; let near = null, nd = 1e9; for (const en of ents) if (en.alive && en.team !== b.team) { const d = (en.x - b.x) ** 2 + (en.z - b.z) ** 2; if (d < nd) { nd = d; near = en; } }
      if (near) { b.hx = near.x + (R() - .5) * 8; b.hz = near.z + (R() - .5) * 8; }
      if (R() < .3 && posts.length) { b.route = posts[Math.floor(R() * posts.length)].map(p => ({ x: p.x, z: p.z })); b.ri = 0; }
    }
    if (b.hx !== undefined) steer(b, b.hx, b.hz);
  }
  // aim
  if (tg && b.vis) {
    const dx = tg.x - b.x, dz = tg.z - b.z, dy = tg.y + (tg.crouch ? .9 : 1.15) - eyeY(b), ty = Math.atan2(-dx, -dz), tp = Math.atan2(dy, Math.hypot(dx, dz));
    const dyaw = angd(b.yaw, ty); b.yaw += clamp(dyaw, -7 * dt, 7 * dt); b.pitch += clamp(tp - b.pitch, -5 * dt, 5 * dt);
    if (b.react <= 0 && Math.abs(dyaw) < .12) {
      if (b.burst < -.3) b.burst = (.5 + R() * .7) * (w.auto ? 1 : .2);
      if (b.burst > 0 || !w.auto) { if (w.k === 'sniper') { if (b.cd <= 0 && R() < dt * 2) tryFire(b); } else if (w.k === 'knife') { if (b.td < w.rng) tryFire(b); } else tryFire(b); }
    }
  } else if (b.wx || b.wz) { const ty = Math.atan2(-b.wx, -b.wz); b.yaw += clamp(angd(b.yaw, ty), -6 * dt, 6 * dt); b.pitch = lerp(b.pitch, 0, dt * 4); }
  if (b.am[b.w] && b.am[b.w].mag === 0 && !b.reloading && w.k !== 'knife') { if (b.am[b.w].res > 0) startReload(b); }
  // locomotion
  b.crouch = crouch; if (crouch) sp *= .5;
  b.vx = lerp(b.vx, b.wx * sp, clamp(12 * dt, 0, 1)); b.vz = lerp(b.vz, b.wz * sp, clamp(12 * dt, 0, 1));
  if (b.gr && R() < dt * .08 && mode === 'fight') b.vy = 6;
  moveEnt(b, dt);
  b.stT -= dt; if (b.stT <= 0) { b.stT = .6; if ((b.wx || b.wz) && Math.hypot(b.x - b.sx, b.z - b.sz) < .15) { b.unst = .7; b.side = -b.side; if (b.gr) b.vy = 6.5; } b.sx = b.x; b.sz = b.z; }
}

/* ============================ MATCH ============================ */
function startMatch(id, m) {
  audio(); mapId = id; mins = m; const md = loadMap(id);
  scene = new THREE.Scene(); scene.background = new THREE.Color(md.sky); scene.fog = new THREE.Fog(md.sky, 35, 110);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x665544, .85)); const dl = new THREE.DirectionalLight(0xffffff, .6); dl.position.set(30, 60, 20); scene.add(dl);
  const gt = envTex(md.ground).clone(); gt.needsUpdate = true; gt.wrapS = gt.wrapT = THREE.RepeatWrapping; gt.repeat.set(md.size / 2, md.size / 2);
  const gm = new THREE.Mesh(new THREE.PlaneGeometry(md.size * 2 + 2, md.size * 2 + 2), new THREE.MeshLambertMaterial({ map: gt, color: md.gc })); gm.rotation.x = -PI / 2; scene.add(gm);
  scene.add(mergeBoxes(rl));
  vm = new THREE.Group(); vm.position.set(.18, -.2, -.35); camera.add(vm); scene.add(camera);
  flash = new THREE.Mesh(new THREE.PlaneGeometry(.18, .18), new THREE.MeshBasicMaterial({ color: 0xffd060, transparent: true, opacity: .9, side: THREE.DoubleSide })); flash.visible = false; vm.add(flash); vmModel = null;
  initPools(); ents = [];
  for (let t = 0; t < 2; t++) for (let i = 0; i < 3; i++) { const e = mkEnt(t, i); e.mesh = charMesh(t); scene.add(e.mesh); ents.push(e); if (e.isPl) pl = e; }
  score = [0, 0]; mCoins = 0; T = 0; matchT = mins * 60; frz = 3; camY = 0; vmRecoil = 0; vmSlash = 0; adsK = 0; camera.fov = 75; camera.updateProjectionMatrix();
  ents.forEach(e => { e.kills = 0; e.deaths = 0; respawn(e); });
  $('sCT').textContent = 0; $('sT').textContent = 0; feedEl.innerHTML = ''; $('msg').textContent = ''; updHp(); updAmmo(true);
  $('menu').style.display = 'none'; $('hud').style.display = 'block'; state = 'play';
}
function update(dt) {
  T += dt;
  if (frz > 0) { frz -= dt; $('msg').textContent = frz > 0 ? Math.ceil(frz) : 'GO!'; if (frz <= 0) setTimeout(() => { if (state === 'play') $('msg').textContent = ''; }, 700); }
  else { matchT -= dt; if (matchT <= 0) { endMatch(); return; } }
  const tm = Math.max(0, Math.ceil(matchT)); $('tm').textContent = Math.floor(tm / 60) + ':' + ('0' + (tm % 60)).slice(-2);
  for (const e of ents) {
    if (e.prot > 0) e.prot -= dt;
    if (!e.alive) { e.resp -= dt; if (e.isPl) { $('msg').textContent = 'Respawning in ' + Math.max(1, Math.ceil(e.resp)); camera.position.y = lerp(camera.position.y, e.y + .4, dt * 4); camera.rotation.z = lerp(camera.rotation.z, .6, dt * 3); } if (e.resp <= 0) { respawn(e); if (e.isPl) { $('msg').textContent = ''; camera.rotation.z = 0; updHp(); updAmmo(true); } } continue; }
    if (frz <= 0) { if (e.isPl) playerUpdate(dt); else botUpdate(e, dt); }
    else if (e.isPl) { playerUpdate(dt); }
    if (e.mesh && !e.isPl) { e.mesh.position.set(e.x, e.y, e.z); e.mesh.rotation.y = e.yaw; e.mesh.scale.y = e.crouch ? .75 : 1; e.mesh.visible = e.prot > 0 ? Math.floor(T * 12) % 2 === 0 : true; }
  }
  if (pl.alive) { if (pl.prot > 0) pl.hp = Math.max(pl.hp, 1); vmUpdate(dt); }
  fxUpdate(dt);
}
const MS = (n) => n;
function endMatch() {
  state = 'result'; $('hud').style.display = 'none'; $('scope').style.display = 'none';
  const win = score[0] > score[1] ? 0 : score[1] > score[0] ? 1 : -1, badge = {};
  for (let t = 0; t < 2; t++) {
    const m = ents.filter(e => e.team === t).sort((a, b) => b.kills - a.kills || a.deaths - b.deaths);
    badge[m[0].name] = win === t ? 'Gold MVP' : win === -1 ? 'MVP' : 'Loss MVP'; badge[m[1].name] = 'Silver II'; badge[m[2].name] = 'Copper III';
  }
  const b = badge[pl.name], k = pl.kills, d = pl.deaths, kd = k / Math.max(1, d);
  let base = win === 0 ? 25 : win === 1 ? (b === 'Loss MVP' ? -8 : -18) : 0;
  let delta = base + k * 2 - d + Math.round(clamp(kd - 1, -1, 2) * 4) + (b === 'Gold MVP' ? 12 : b === 'Loss MVP' ? 6 : b === 'Silver II' ? 3 : 0);
  delta = clamp(delta, -25, 60); if (win === 1) delta = Math.min(delta, 0) === delta ? delta : Math.min(delta, 5);
  const before = rankOf(S.rp), oldRP = S.rp; S.rp = Math.max(0, S.rp + delta); const after = rankOf(S.rp);
  const coins = mCoins + (win === 0 ? 100 : win === 1 ? 40 : 60) + (b === 'Gold MVP' ? 30 : 0); S.coins += coins;
  S.st.k += k; S.st.d += d; if (win === 0) S.st.w++; else if (win === 1) S.st.l++; save();
  let rows = ''; ents.slice().sort((a, b2) => a.team - b2.team || b2.kills - a.kills).forEach(e => { rows += `<tr class="${e.isPl ? 'me' : ''}"><td>${e.team ? 'T' : 'CT'}</td><td>${e.name}</td><td>${e.kills}</td><td>${e.deaths}</td><td>${badge[e.name]}</td></tr>`; });
  $('menu').innerHTML = `<h1>${win === 0 ? 'VICTORY' : win === 1 ? 'DEFEAT' : 'DRAW'} — CT ${score[0]} : ${score[1]} T</h1>
  <table><tr><th>Team</th><th>Player</th><th>K</th><th>D</th><th>Badge</th></tr>${rows}</table>
  <div class="card"><div>Your badge: <b>${b}</b><small>K/D ${kd.toFixed(2)} · ${k} kills · ${d} deaths</small></div><div><b style="color:${delta >= 0 ? '#6f6' : '#f66'}">${delta >= 0 ? '+' : ''}${delta} RP</b><small>${oldRP} → ${S.rp}</small></div></div>
  <div class="card"><div>Rank: <b>${rankTxt(oldRP)}</b> → <b>${rankTxt(S.rp)}</b><small>${after.idx > before.idx ? 'RANK UP!' : after.idx < before.idx ? 'Rank down' : ''}</small></div><div>🪙 +${coins}</div></div>
  <div class="row"><button data-a="again">Play again</button><button class="g" data-a="home">Menu</button></div>`;
  $('menu').style.display = 'block';
}

/* ============================ MENUS ============================ */
const M = $('menu'); let shopTab = 'w', shopW = null, selMap = 'dust', selMin = 3;
function home() {
  state = 'menu'; $('hud').style.display = 'none'; M.style.display = 'block'; const r = rankOf(S.rp);
  M.innerHTML = `<h1>FPS 3v3 Tactical</h1><div class="rk">${r.name} ★${r.stars} · ${S.rp} RP · 🪙 ${S.coins} · W${S.st.w}/L${S.st.l}</div>
  <div class="row"><button data-a="maps">PLAY</button><button data-a="shop">SHOP</button></div>
  <div class="row">FPS limit: <select data-a="fps">${[30, 45, 60].map(f => `<option ${f === fpsCap ? 'selected' : ''}>${f}</option>`).join('')}</select></div>
  <div class="card"><div>Loadout<small>${W[S.load[1]].n} · ${W[S.load[2]].n} · ${W[S.load[3]].n}</small></div></div>
  <div class="card"><div>Controls<small>Left stick: move · Right drag: aim · FIRE/ADS/JUMP/CROUCH/RLD/SWAP buttons. AWP: tap ADS again for 2x/4x.</small></div></div>`;
}
function maps() {
  M.innerHTML = `<h1>Select Map</h1><div class="row">${Object.keys(MAPS).map(k => `<div class="map ${k === selMap ? 'on' : ''}" data-a="map" data-v="${k}"><b>${MAPS[k].n}</b><small style="display:block;opacity:.7">${MAPS[k].desc}</small></div>`).join('')}</div>
  <div class="row">Match time: ${[3, 4, 5].map(m => `<button class="${m === selMin ? 'on' : 'g'}" data-a="min" data-v="${m}">${m} min</button>`).join('')}</div>
  <div class="row"><button data-a="start">START 3v3</button><button class="g" data-a="home">Back</button></div>`;
}
function shop() {
  const own = id => S.owned.includes(id); let h = `<h1>Shop <small style="font-size:14px">🪙 ${S.coins}</small></h1><div class="row"><button class="${shopTab === 'w' ? 'on' : 'g'}" data-a="tab" data-v="w">Weapons</button><button class="${shopTab === 's' ? 'on' : 'g'}" data-a="tab" data-v="s">Skins</button><button class="g" data-a="home">Back</button></div>`;
  if (shopTab === 'w') {
    [1, 2, 3].forEach(sl => { h += `<h3>${['', 'Primary', 'Sidearm', 'Melee'][sl]}</h3>`; WIDS.filter(i => W[i].s === sl).forEach(i => { const w = W[i];
      h += `<div class="card"><div><b>${w.n}</b><small>${w.k === 'knife' ? 'DMG ' + w.dmg + ' · fast' : 'DMG ' + w.dmg + (w.pel > 1 ? '×' + w.pel : '') + ' · ' + w.rate + '/s · mag ' + w.mag}</small></div>
      ${own(i) ? (S.load[sl] === i ? '<button class="on" disabled>Equipped</button>' : `<button data-a="eq" data-v="${i}">Equip</button>`) : `<button data-a="buy" data-v="${i}" ${S.coins < w.price ? 'disabled' : ''}>🪙 ${w.price}</button>`}</div>`; }); });
  } else {
    if (!shopW || !own(shopW)) shopW = S.load[1];
    h += `<div class="row">${S.owned.map(i => `<button class="${i === shopW ? 'on' : 'g'}" data-a="sw" data-v="${i}">${W[i].n}</button>`).join('')}</div>`;
    Object.keys(SK).forEach(k => { const o = S.skinsOwned.includes(k), eq = (S.skin[shopW] || 'default') === k;
      h += `<div class="card"><img src="${skinCanvas(k).toDataURL()}"><div style="flex:1"><b>${SK[k].n}</b></div>${o ? (eq ? '<button class="on" disabled>Equipped</button>' : `<button data-a="eqs" data-v="${k}">Equip on ${W[shopW].n}</button>`) : `<button data-a="buys" data-v="${k}" ${S.coins < SK[k].p ? 'disabled' : ''}>🪙 ${SK[k].p}</button>`}</div>`; });
  }
  M.innerHTML = h;
}
M.addEventListener('click', e => {
  const t = e.target.closest('[data-a]'); if (!t) return; audio(); const a = t.dataset.a, v = t.dataset.v;
  if (a === 'home') home(); else if (a === 'maps') maps(); else if (a === 'shop') { shopTab = 'w'; shop(); }
  else if (a === 'map') { selMap = v; maps(); } else if (a === 'min') { selMin = +v; maps(); } else if (a === 'start' || a === 'again') startMatch(a === 'again' ? mapId : selMap, a === 'again' ? mins : selMin);
  else if (a === 'tab') { shopTab = v; shop(); } else if (a === 'sw') { shopW = v; shop(); }
  else if (a === 'buy') { const w = W[v]; if (S.coins >= w.price && !S.owned.includes(v)) { S.coins -= w.price; S.owned.push(v); S.load[w.s] = v; save(); } shop(); }
  else if (a === 'eq') { S.load[W[v].s] = v; save(); shop(); }
  else if (a === 'buys') { if (S.coins >= SK[v].p && !S.skinsOwned.includes(v)) { S.coins -= SK[v].p; S.skinsOwned.push(v); S.skin[shopW] = v; save(); } shop(); }
  else if (a === 'eqs') { S.skin[shopW] = v; save(); shop(); }
});
M.addEventListener('change', e => { if (e.target.dataset.a === 'fps') { fpsCap = +e.target.value; S.fps = fpsCap; save(); } });

/* ============================ INPUT ============================ */
const joy = { id: -1, ox: 0, oy: 0 }, look = { id: -1, lx: 0, ly: 0 }, jb = $('jbase'), jk = $('jknob');
document.addEventListener('touchstart', e => {
  if (state !== 'play') return; e.preventDefault();
  for (const t of e.changedTouches) {
    if (t.target.closest && t.target.closest('.btn')) continue;
    if (t.clientX < innerWidth * .45 && joy.id < 0) { joy.id = t.identifier; joy.ox = t.clientX; joy.oy = t.clientY; jb.style.display = 'block'; jb.style.left = t.clientX + 'px'; jb.style.top = t.clientY + 'px'; jk.style.left = '35px'; jk.style.top = '35px'; }
    else if (t.clientX >= innerWidth * .45 && look.id < 0) { look.id = t.identifier; look.lx = t.clientX; look.ly = t.clientY; }
  }
}, { passive: false });
document.addEventListener('touchmove', e => {
  if (state !== 'play') return; e.preventDefault();
  for (const t of e.changedTouches) {
    if (t.identifier === joy.id) { let dx = t.clientX - joy.ox, dy = t.clientY - joy.oy; const l = Math.hypot(dx, dy), mx = 50; if (l > mx) { dx *= mx / l; dy *= mx / l; } inp.jx = dx / mx; inp.jy = dy / mx; jk.style.left = 35 + dx + 'px'; jk.style.top = 35 + dy + 'px'; if (Math.hypot(inp.jx, inp.jy) < .12) inp.jx = inp.jy = 0; }
    else if (t.identifier === look.id) { inp.dx += t.clientX - look.lx; inp.dy += t.clientY - look.ly; look.lx = t.clientX; look.ly = t.clientY; }
  }
}, { passive: false });
function tend(e) { for (const t of e.changedTouches) { if (t.identifier === joy.id) { joy.id = -1; inp.jx = inp.jy = 0; jb.style.display = 'none'; } if (t.identifier === look.id) look.id = -1; } }
document.addEventListener('touchend', tend); document.addEventListener('touchcancel', tend);
function bind(id, down, up) {
  const el = $(id); el.addEventListener('touchstart', e => { e.preventDefault(); e.stopPropagation(); el.classList.add('on'); audio(); down && down(); }, { passive: false });
  const u = e => { e.preventDefault(); el.classList.remove('on'); up && up(); }; el.addEventListener('touchend', u, { passive: false }); el.addEventListener('touchcancel', u, { passive: false });
}
bind('bFire', () => inp.fire = true, () => inp.fire = false);
bind('bJump', () => inp.jump = true);
bind('bReload', () => inp.reload = true);
bind('bSwitch', () => inp.swap = true);
bind('bCrouch', () => { if (!pl.alive) return; if (pl.crouch) { if (!blocked(pl.x, pl.y, pl.z, .35, 1.8)) pl.crouch = false; } else pl.crouch = true; });
bind('bAds', () => { if (!pl.alive || pl.reloading) return; const w = W[pl.w]; if (w.k === 'knife') return; if (w.scope) { pl.zoom = pl.ads ? (pl.zoom === 2 ? 4 : 0) : 2; pl.ads = pl.zoom > 0; } else pl.ads = !pl.ads; });
bind('bPause', () => { if (state === 'play') pause(); });
function pause() {
  state = 'pause'; inp.fire = false; inp.jx = inp.jy = 0; M.style.display = 'block'; M.innerHTML = `<h1>Paused</h1><div class="row"><button data-a="resume">Resume</button><button class="g" data-a="quit">Quit match</button></div>`;
}
M.addEventListener('click', e => { const t = e.target.closest('[data-a]'); if (!t) return; if (t.dataset.a === 'resume') { M.style.display = 'none'; state = 'play'; } else if (t.dataset.a === 'quit') { state = 'menu'; $('hud').style.display = 'none'; $('scope').style.display = 'none'; home(); } });
window.onBack = () => { if (state === 'play') pause(); else if (state === 'pause') { M.style.display = 'none'; state = 'play'; } else if (state === 'menu') home(); };
window.onAppPause = () => { if (state === 'play') pause(); };
document.addEventListener('contextmenu', e => e.preventDefault());

/* ============================ MAIN LOOP ============================ */
let last = 0;
function loop(t) {
  requestAnimationFrame(loop); const iv = 1000 / fpsCap; if (t - last < iv - 1.5) return; const dt = Math.min((t - last) / 1000, .05); last = t;
  if (state === 'play') { update(dt); updAmmo(); renderer.render(scene, camera); }
  else if (state === 'pause' && scene) renderer.render(scene, camera);
}
home(); requestAnimationFrame(loop);
})();
