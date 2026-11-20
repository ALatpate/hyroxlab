// Glimm's reference renderer.
//
// Glimm is drawn from one description (spec.js): a small skeleton, the shapes that hang off each
// bone, the clothes, and the poses and gestures of each mood. This file turns that description into
// a flat list of parts (a shape, a place, a paint) and draws them on a canvas. The app's renderer
// (Packages/LumaUI/Sources/LumaKit/Glimm*.swift) follows it function for function, so a change to the
// art or the motion can be looked at here, in seconds, before it is built into the app.

export const D2R = Math.PI / 180;

function rotv(x, y, deg) {
  const r = deg * D2R, c = Math.cos(r), s = Math.sin(r);
  return [x * c - y * s, x * s + y * c];
}
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const smooth = (x) => { const t = clamp(x, 0, 1); return t * t * (3 - 2 * t); };
/// A repeatable number in 0..<1 for a whole number: the same slot of time always gives the same choice.
export function hash(n) { const v = Math.sin(n * 12.9898 + 4.1414) * 43758.5453; return v - Math.floor(v); }

// MARK: Colour

export function hex(c) { return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)]; }
function shade(rgb, pct) {
  return rgb.map((v) => clamp(Math.round(pct >= 0 ? v + (255 - v) * pct / 100 : v * (1 + pct / 100)), 0, 255));
}
/// A colour token: a name from the palette in force or "#RRGGBB", then an optional shade ("+12" lighter,
/// "-20" darker, in percent) and an optional opacity ("@55", in percent).
export function color(token, env) {
  const m = /^(#[0-9A-Fa-f]{6}|[A-Za-z][A-Za-z0-9]*)([+-]\d+)?(@\d+)?$/.exec(token);
  if (!m) return { rgb: [255, 0, 255], a: 1 };
  let rgb = m[1][0] === '#' ? hex(m[1]) : (env[m[1]] || [255, 0, 255]);
  if (m[2]) rgb = shade(rgb, parseInt(m[2], 10));
  const a = m[3] ? parseInt(m[3].slice(1), 10) / 100 : 1;
  if (env.$mono) {
    // The Lock Screen keeps only light and dark: skin is the light, everything else keeps its own
    // lightness, pulled apart a little so clothes still read against skin.
    const l = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255;
    const g = Math.round(255 * clamp(env.$skinLike && env.$skinLike(m[1]) ? 0.97 : 0.1 + 0.72 * l, 0, 1));
    rgb = [g, g, g];
  }
  return { rgb, a };
}
/// A paint: one token, or ["lin", from, to, degrees] (0 runs left to right, 90 top to bottom), or
/// ["rad", centre, edge, cx, cy, radius] with the centre in the shape's own box (0..1).
export function paint(spec, env) {
  if (spec == null) return null;
  if (typeof spec === 'string') return { k: 'solid', a: color(spec, env) };
  if (spec[0] === 'lin') {
    const r = (spec[3] ?? 90) * D2R, dx = Math.cos(r) / 2, dy = Math.sin(r) / 2;
    return { k: 'lin', a: color(spec[1], env), b: color(spec[2], env), x0: 0.5 - dx, y0: 0.5 - dy, x1: 0.5 + dx, y1: 0.5 + dy };
  }
  return { k: 'rad', a: color(spec[1], env), b: color(spec[2], env), cx: spec[3] ?? 0.5, cy: spec[4] ?? 0.5, r: spec[5] ?? 0.5 };
}

// MARK: Paths

const pathCache = new Map();
/// "M x y L x y Q cx cy x y C ax ay bx by x y Z", in the shape's own box (0..1).
export function parsePath(d) {
  let ops = pathCache.get(d);
  if (ops) return ops;
  ops = [];
  const t = d.trim().split(/[\s,]+/);
  let i = 0;
  const take = (n) => { const v = t.slice(i, i + n).map(Number); i += n; return v; };
  while (i < t.length) {
    const c = t[i++];
    if (c === 'Z') ops.push(['Z']);
    else if (c === 'M' || c === 'L') ops.push([c, ...take(2)]);
    else if (c === 'Q') ops.push([c, ...take(4)]);
    else if (c === 'C') ops.push([c, ...take(6)]);
  }
  pathCache.set(d, ops);
  return ops;
}

// MARK: Channels: the pose at one moment

/// One gesture laid over a pose. A gesture is a list of keys [when 0..1, {channel: value}]; a channel
/// starts and ends at the pose's own value unless the gesture keys it there. Numbers ease from key to
/// key; words (a mouth shape, a prop) switch at their key.
export function applyGesture(ch, g, phase) {
  const base = { ...ch };
  const names = new Set();
  for (const [, set] of g.keys) for (const k of Object.keys(set)) names.add(k);
  for (const name of names) {
    const keys = [];
    for (const [at, set] of g.keys) if (name in set) keys.push([at, set[name]]);
    if (typeof keys[0][1] !== 'number') {
      let v = base[name];
      for (const [at, value] of keys) if (phase >= at && phase < 1) v = value;
      ch[name] = v;
      continue;
    }
    if (keys[0][0] > 0) keys.unshift([0, base[name] ?? 0]);
    if (keys[keys.length - 1][0] < 1) keys.push([1, base[name] ?? 0]);
    let v = keys[keys.length - 1][1];
    for (let i = 0; i + 1 < keys.length; i++) {
      const [a, va] = keys[i], [b, vb] = keys[i + 1];
      if (phase >= a && phase <= b) { v = va + (vb - va) * smooth(b > a ? (phase - a) / (b - a) : 1); break; }
    }
    ch[name] = v;
  }
}

/// The pose of a mood. `beat` picks one of the mood's stills, which a widget moves between; `t`, in
/// seconds, moves it continuously for the app; `tap` is a reaction under way ({kind, phase}).
export function channels(spec, mood, { t = null, beat = 0, energy = 0.6, tap = null, play = null } = {}) {
  const M = spec.moods[mood] || spec.moods.steady;
  const ch = { ...spec.defaults, ...M.base };
  if (beat >= 10) {
    const g = spec.taps[beat >= 20 ? 'leaf' : 'head'];
    applyGesture(ch, g, beat % 10 === 0 ? 0.3 : 0.62);
  } else if (beat > 0 && M.stills && M.stills.length) {
    const still = M.stills[(beat - 1) % M.stills.length];
    if (still.g) applyGesture(ch, spec.gestures[still.g], still.at ?? 0.5);
    if (still.set) Object.assign(ch, still.set);
  }
  if (t != null) {
    const live = 0.5 + 0.5 * energy;
    // What the mood holds differently while it moves, and the marks about it drifting on.
    Object.assign(ch, M.live || {});
    ch.propPhase = t * 0.45;
    for (const [name, amp, hz, ph = 0, mode = 'sin'] of [...spec.breath, ...(M.osc || [])]) {
      let v = Math.sin(2 * Math.PI * (hz * t + ph));
      if (mode === 'abs') v = Math.abs(v);
      if (mode === 'pos') v = Math.max(0, v);
      ch[name] = (ch[name] ?? 0) + amp * v * (mode === 'calm' ? 1 : live);
    }
    // Blinks: uneven, now and then two together, and none while the eyes are shut or smiling.
    if (ch.eyeOpen > 0.5 && ch.eyeSmile < 0.5) {
      const slot = Math.floor(t / 3.7), at = slot * 3.7 + hash(slot) * 2.2, dt = t - at;
      if ((dt >= 0 && dt < 0.13) || (hash(slot + 91) < 0.28 && dt >= 0.3 && dt < 0.42)) ch.eyeOpen = 0.04;
    }
    // A small thing done of its own accord, every few seconds.
    const list = M.gestures || [];
    if (list.length && !tap && !play) {
      const every = M.every || 7, slot = Math.floor(t / every);
      const g = spec.gestures[list[Math.floor(hash(slot * 7 + 3) * list.length) % list.length]];
      const start = slot * every + 0.6 + hash(slot * 13 + 5) * Math.max(0, every - g.dur - 1.2);
      if (t >= start && t < start + g.dur) applyGesture(ch, g, (t - start) / g.dur);
    }
  }
  if (play && spec.gestures[play.name]) applyGesture(ch, spec.gestures[play.name], clamp(play.phase, 0, 1));
  if (tap && spec.taps[tap.kind]) applyGesture(ch, spec.taps[tap.kind], clamp(tap.phase, 0, 1));
  return ch;
}

// MARK: Bones

/// Where each bone is: its joint, and the turn of everything hung from it. A limb at rest points
/// straight down; angles open outwards, and an elbow or a knee adds to the joint above it. A planted
/// foot stays where it stands and the knee bends to suit, so a bob or a shift of weight flexes the legs.
export function bones(spec, ch) {
  const R = spec.rig, B = {};
  const rootX = R.root[0] + ch.sway, rootY = R.root[1] + ch.bob - ch.lift;
  const lean = ch.lean;
  B.ground = { x: R.root[0], y: R.ground, rot: 0, side: 1 };
  B.torso = { x: rootX, y: rootY, rot: lean, side: 1 };
  const T = (x, y) => { const [dx, dy] = rotv(x, y, lean); return [rootX + dx, rootY + dy]; };
  const neck = T(0, -R.torsoLen);
  const hrot = lean * 0.6 + ch.headTilt;
  const up = rotv(0, -R.neckUp, hrot);
  B.head = { x: neck[0] + up[0] + ch.headDX, y: neck[1] + up[1] + ch.headDY, rot: hrot, side: 1 };
  const lf = rotv(R.leaf[0], R.leaf[1], hrot);
  B.leaf = { x: B.head.x + lf[0], y: B.head.y + lf[1], rot: hrot + ch.leaf + ch.leafDroop * R.leafDroop, side: 1 };
  for (const [s, n] of [[-1, 'L'], [1, 'R']]) {
    const j = T(s * R.shoulder[0], R.shoulder[1]);
    const r1 = lean - s * ch['sh' + n], r2 = lean - s * (ch['sh' + n] + ch['el' + n]);
    B['upper' + n] = { x: j[0], y: j[1], rot: r1, side: s };
    const e = rotv(0, R.upper, r1), ex = j[0] + e[0], ey = j[1] + e[1];
    B['fore' + n] = { x: ex, y: ey, rot: r2, side: s };
    const h = rotv(0, R.fore, r2);
    B['hand' + n] = { x: ex + h[0], y: ey + h[1], rot: r2, side: s };

    const jx = rootX + s * R.hip[0], jy = rootY + R.hip[1];
    let phi1, phi2;   // degrees from straight down, towards the right of the picture
    if (ch['plant' + n] >= 0.5) {
      const ax = R.root[0] + s * ch.stance + ch['step' + n], ay = R.ankle - ch['raise' + n];
      const dx = ax - jx, dy = ay - jy, d = Math.hypot(dx, dy);
      const a = clamp(d, Math.abs(R.thigh - R.shin) + 0.01, R.thigh + R.shin - 0.001);
      const theta = Math.atan2(dx, dy);
      const alpha = Math.acos(clamp((R.thigh * R.thigh + a * a - R.shin * R.shin) / (2 * R.thigh * a), -1, 1));
      phi1 = (theta + s * alpha) / D2R;
      const kx = jx + R.thigh * Math.sin(phi1 * D2R), ky = jy + R.thigh * Math.cos(phi1 * D2R);
      phi2 = Math.atan2(jx + Math.sin(theta) * a - kx, jy + Math.cos(theta) * a - ky) / D2R;
    } else {
      phi1 = s * ch['hip' + n];
      phi2 = s * (ch['hip' + n] + ch['kn' + n]);
    }
    B['thigh' + n] = { x: jx, y: jy, rot: -phi1, side: s };
    const kx = jx + R.thigh * Math.sin(phi1 * D2R), ky = jy + R.thigh * Math.cos(phi1 * D2R);
    B['shin' + n] = { x: kx, y: ky, rot: -phi2, side: s };
    const fx = kx + R.shin * Math.sin(phi2 * D2R), fy = ky + R.shin * Math.cos(phi2 * D2R);
    const planted = ch['plant' + n] >= 0.5;
    B['foot' + n] = { x: fx, y: fy, rot: (planted ? 0 : -phi2 * R.footFollow) - s * ch['foot' + n], side: s };
  }
  return B;
}

// MARK: Parts

/// An element of the description, [bone, shape, x, y, w, h, turn, fill, options], placed in the picture.
/// "upper", "fore", "hand", "thigh", "shin" and "foot" stand for both sides, mirrored.
function place(el, B, env, z, id, out) {
  const [bone, sh, x, y, w, h, rot, fill, o = {}] = el;
  const both = !B[bone];
  const names = both ? [bone + 'L', bone + 'R'] : [bone];
  for (const name of names) {
    const b = B[name];
    if (!b) continue;
    // Mirrored: once for each side of a limb, or, with "mir", once on each side of the bone's own axis.
    for (const m of o.mir ? [1, -1] : [1]) {
      const s = (both ? b.side : 1) * m;
      const [dx, dy] = rotv(s * x, y, b.rot);
      const tag = /^(upper|fore|hand|thigh|shin|foot)[LR]$/.test(name) ? name.slice(-1) : (o.mir ? (m > 0 ? 'a' : 'b') : '');
      out.push({
        id: id + tag, sh, x: b.x + dx, y: b.y + dy, w, h, rot: b.rot + s * rot,
        flip: s < 0 && sh === 'path', r: o.r ?? 0, ops: o.d ? parsePath(o.d) : null, fill: paint(fill, env),
        stroke: o.s ? [color(o.s[0], env), o.s[1]] : null,
        ol: o.ol === 0 || !fill ? null : (o.ol ? [color(o.ol[0], env), o.ol[1]] : env.$ol ? [color(env.$ol, env), env.$olw] : null),
        o: o.o ?? 1, z: (o.z ?? z) + (o.dz ?? 0), txt: o.t ?? null,
        kids: (o.kids || []).map((k, i) => kid(k, env, id + tag + '.' + i, s < 0 && sh !== 'path' ? -1 : 1)),
      });
    }
  }
}
/// Something drawn inside a part and cut to its outline: [shape, x, y, w, h, turn, fill, options],
/// measured from the part's own middle. `side` mirrors it for the left of a pair.
function kid(k, env, id, side = 1) {
  const [sh, x, y, w, h, rot, fill, o = {}] = k;
  return { id, sh, x: side * x, y, w, h, rot: side * rot, r: o.r ?? 0, ops: o.d ? parsePath(o.d) : null, fill: paint(fill, env),
           stroke: o.s ? [color(o.s[0], env), o.s[1]] : null, o: o.o ?? 1, txt: o.t ?? null, kids: [] };
}

/// The colours an item of clothing is drawn in: its own colour as "c", a companion as "c2".
function clothEnv(env, hexColor, companion) {
  const c = hex('#' + hexColor);
  return { ...env, c, c2: companion ? hex(companion) : shade(c, 55), $ol: 'c-38', $olw: env.$mono ? 0.9 : 0.5 };
}

/// "top|bottom|feet|head|accessory", each "shape:RRGGBB:pattern" or "-".
export function parseOutfit(code) {
  const slots = (code || '').split('|');
  const one = (i) => {
    const p = (slots[i] || '').split(':');
    return p.length >= 2 && p[0] !== '-' && p[0] !== '' ? { shape: p[0], hex: p[1], pattern: p[2] || 'plain' } : null;
  };
  return { top: one(0), bottom: one(1), feet: one(2), head: one(3), acc: one(4) };
}

/// Marks of a pattern over a box w by h: kids of the garment's body, so its outline cuts them.
function patternKids(pattern, w, h, seedText) {
  const out = [];
  let seed = 0;
  for (const c of seedText) seed = (seed * 31 + c.charCodeAt(0)) % 9973;
  if (pattern === 'stripes') {
    for (let y = -h / 2 + 4.2; y < h / 2; y += 6.4) out.push(['rr', 0, y, w + 4, 2.6, 0, 'c2']);
  } else if (pattern === 'dots') {
    let row = 0;
    for (let y = -h / 2 + 4; y < h / 2 - 1; y += 5.6, row++)
      for (let x = -w / 2 + 3 + (row % 2) * 2.8; x < w / 2; x += 5.6) out.push(['el', x, y, 2.1, 2.1, 0, 'c2']);
  } else if (pattern === 'checks') {
    for (let y = -h / 2 + 3.5; y < h / 2; y += 6.6) out.push(['rr', 0, y, w + 4, 2.7, 0, 'c2@55']);
    for (let x = -w / 2 + 3.3; x < w / 2; x += 6.6) out.push(['rr', x, 0, 2.7, h + 4, 0, 'c2@55']);
  } else if (pattern === 'stars') {
    for (let i = 0; i < 6; i++) {
      const x = (hash(seed + i * 3) - 0.5) * (w - 6), y = (hash(seed + i * 3 + 1) - 0.5) * (h - 7);
      out.push(['path', x, y, 4.4, 4.4, hash(seed + i) * 40 - 20, 'c2', { d: STAR }]);
    }
  } else if (pattern === 'flowers') {
    for (let i = 0; i < 7; i++) {
      const x = (hash(seed + i * 7) - 0.5) * (w - 5), y = (hash(seed + i * 7 + 1) - 0.5) * (h - 6);
      for (let k = 0; k < 5; k++) {
        const a = (k * 72 + i * 20) * D2R;
        out.push(['el', x + Math.cos(a) * 1.5, y + Math.sin(a) * 1.5, 2, 2, 0, '#FFFFFF@92']);
      }
      out.push(['el', x, y, 1.5, 1.5, 0, 'gold']);
    }
  } else if (pattern === 'sprinkles') {
    const tints = ['c2', '#FFFFFF', 'c-30', 'c2-25'];
    for (let i = 0; i < 13; i++) {
      const x = (hash(seed + i * 5) - 0.5) * (w - 4), y = (hash(seed + i * 5 + 2) - 0.5) * (h - 5);
      out.push(['cap', x, y, 1.1, 3.4, hash(seed + i * 5 + 3) * 180, tints[i % tints.length]]);
    }
  }
  return out;
}
export const STAR = 'M 0.5 0 L 0.62 0.36 L 1 0.38 L 0.7 0.61 L 0.81 0.98 L 0.5 0.76 L 0.19 0.98 L 0.3 0.61 L 0 0.38 L 0.38 0.36 Z';

/// Every part of the picture, back to front.
export function parts(spec, ch, outfitCode, { style = 'color' } = {}) {
  const B = bones(spec, ch);
  const mono = style === 'mono';
  const env = {};
  for (const [k, v] of Object.entries(spec.colors)) env[k] = hex(v);
  if (mono) { env.$mono = true; env.$skinLike = (n) => n === 'skin' || n === 'skinHi' || n === 'skinLo' || n === 'white' || n === 'sole'; }
  const skin = { ...env, $ol: 'skinLine', $olw: mono ? 0.9 : 0.5 };
  const out = [];
  const R = spec.rig, Z = spec.z;
  const outfit = parseOutfit(outfitCode);
  const frontL = ch.frontL >= 0.5 ? Z.front : 0, frontR = ch.frontR >= 0.5 ? Z.front : 0;
  // A bone's parts move in front of the head when its arm is raised across it.
  const lift = (list, from) => {
    for (let i = from; i < list.length; i++) {
      const p = list[i];
      if (/L$/.test(p.id) && frontL && p.z >= Z.arm && p.z < Z.neck) p.z += frontL;
      if (/R$/.test(p.id) && frontR && p.z >= Z.arm && p.z < Z.neck) p.z += frontR;
    }
  };

  // The ground under it, smaller as it leaves the ground.
  if (!mono) out.push({ id: 'ground', sh: 'el', x: R.root[0] + ch.sway * 0.5, y: R.ground, w: Math.max(12, 33 - ch.lift * 1.3), h: 5.2, rot: 0, r: 0, ops: null,
                        fill: paint('#000000@' + Math.round(clamp(30 - ch.lift, 8, 30)), env), stroke: null, ol: null, o: 1, z: Z.ground, kids: [] });

  // Skin.
  spec.body.forEach((el, i) => place(el, B, skin, 0, 'b' + i, out));
  lift(out, 0);

  // Clothes.
  const wear = (slot, item, table) => {
    if (!item) return;
    const G = table[item.shape] || table[spec.fallback[slot]];
    if (!G) return;
    const e = clothEnv(env, item.hex, G.c2 ? (G.c2[0] === '#' ? G.c2 : null) : null);
    if (G.c2 && G.c2[0] !== '#') e.c2 = color(G.c2, e).rgb;
    const from = out.length;
    if (slot === 'top') {
      const S = spec.sil[G.sil || 'trunk'];
      // A cut with a pattern of its own (a rugby shirt's stripes) wears it when it is plain.
      const pattern = item.pattern !== 'plain' ? item.pattern : (G.pattern || 'plain');
      const kids = [...patternKids(pattern, S.box[2], S.box[3], item.shape + item.hex), ...(G.kids || [])];
      if (G.inner) place(['torso', 'path', spec.sil.trunk.box[0], spec.sil.trunk.box[1], spec.sil.trunk.box[2], spec.sil.trunk.box[3], 0,
                          ['lin', G.inner, G.inner + '-10', 90], { d: spec.sil.trunk.d, z: Z.top - 0.6, ol: [G.inner + '-38', 0.5] }], B, e, 0, 'ti', out);
      place(['torso', 'path', S.box[0], S.box[1], S.box[2], S.box[3], 0, ['lin', 'c+7', 'c-9', 90], { d: S.d, z: Z.top, kids }], B, e, 0, 'tb', out);
      (G.over || []).forEach((el, i) => place(el, B, e, Z.top + 2, 'to' + i, out));
      const sc = { ...e };
      if (G.sc) { sc.c = color(G.sc, e).rgb; sc.c2 = e.c; }
      const aw = R.armW + 2.6;
      const band = pattern === 'stripes' ? [['rr', 0, 0.6, aw + 2, 2.2, 0, 'c2']] : [];
      if (G.sleeve === 'long' || G.sleeve === 'short') {
        const len = G.sleeve === 'long' ? R.upper + aw : R.upper * 0.62 + aw;
        place(['upper', 'cap', 0, len / 2 - aw / 2, aw, len, 0, ['lin', 'c+7', 'c-7', 0], { z: Z.sleeve, kids: band }], B, sc, 0, 'su', out);
      }
      if (G.sleeve === 'long') {
        const len = R.fore + aw * 0.5;
        place(['fore', 'cap', 0, len / 2 - aw / 2 + 0.3, aw - 0.3, len, 0, ['lin', 'c+7', 'c-7', 0], { z: Z.sleeve + 0.01, kids: band }], B, sc, 0, 'sf', out);
        if (G.cuff) place(['fore', 'rr', 0, R.fore - 1.3, aw + 0.4, 2.6, 0, G.cuff === 1 ? 'c-14' : G.cuff, { z: Z.sleeve + 0.6, r: 1.2 }], B, sc, 0, 'sc', out);
      }
    } else if (slot === 'bottom') {
      const lw = R.legW + 2 + (G.wide || 0);
      place(['torso', 'rr', 0, -2.6, 35 + (G.wide || 0) * 0.6, 10.6, 0, ['lin', 'c+5', 'c-8', 90], { z: Z.hip, r: 5 }], B, e, 0, 'ph', out);
      if (G.skirt) {
        place(['torso', 'path', 0, 1.2, 39, 12.5, 0, ['lin', 'c+5', 'c-10', 90], { z: Z.hip + 0.6, d: 'M 0.14 0 L 0.86 0 L 1 0.86 Q 0.5 1.08 0 0.86 Z', kids: G.kids || [] }], B, e, 0, 'ps', out);
      } else {
        const tl = G.leg === 'short' ? R.thigh * 0.74 + lw : R.thigh + lw;
        place(['thigh', 'cap', 0, tl / 2 - lw / 2, lw, tl, 0, ['lin', 'c+5', 'c-8', 0], { z: Z.pant, kids: G.thighKids || [] }], B, e, 0, 'pt', out);
        if (G.leg !== 'short') {
          const sl = R.shin + lw * 0.5 - 0.6;
          place(['shin', 'cap', 0, sl / 2 - lw / 2 + 0.2, lw - 0.2 + (G.flare || 0), sl, 0, ['lin', 'c+5', 'c-8', 0], { z: Z.pant + 0.01, kids: G.shinKids || [] }], B, e, 0, 'pl', out);
          if (G.cuff) place(['shin', 'rr', 0, R.shin - 1.5, lw + 0.5, 2.6, 0, G.cuff === 1 ? 'c-14' : G.cuff, { z: Z.pant + 0.6, r: 1.2 }], B, e, 0, 'pc', out);
        }
      }
      (G.over || []).forEach((el, i) => place(el, B, e, Z.hip + 1, 'po' + i, out));
    } else {
      const zs = { feet: Z.shoe, head: Z.hat, acc: Z.acc }[slot];
      (G.parts || []).forEach((el, i) => place(el, B, e, zs, slot[0] + 'x' + i, out));
    }
    lift(out, from);
  };
  wear('bottom', outfit.bottom, spec.bottoms);
  wear('feet', outfit.feet, spec.feet);
  wear('top', outfit.top, spec.tops);
  wear('acc', outfit.acc, spec.accs);
  // A hood worn up takes the place of a hat.
  const hooded = outfit.top && (spec.tops[outfit.top.shape] || {}).hood;
  if (!hooded) wear('head', outfit.head, spec.heads);

  // The leaf, the face, and whatever it is holding or whatever floats about it.
  spec.leaf.forEach((el, i) => place(el, B, { ...env, $ol: 'leafLine', $olw: mono ? 0.9 : 0.5 }, Z.leaf, 'lf' + i, out));
  face(spec, ch, B, env, out, outfit.acc && outfit.acc.shape === 'glasses');
  const from = out.length;
  const held = spec.held[ch.hold];
  if (held) held.forEach((el, i) => place(el, B, env, Z.held, 'h' + i, out));
  lift(out, from);
  const prop = spec.props[ch.prop];
  if (prop) propParts(prop, ch, B, env, out);

  // One outline about each group of parts that touch: every part is first drawn wide in the line
  // colour, just beneath itself, so joints inside a limb show no seam.
  const all = [];
  for (const p of out) {
    if (p.ol && p.fill) all.push({ ...p, id: 'o-' + p.id, fill: { k: 'solid', a: p.ol[0] }, stroke: [p.ol[0], p.ol[1] * 2], kids: [], z: p.z - 0.4, ol: null });
    all.push(p);
  }
  return all.map((p, i) => [p, i]).sort((a, b) => a[0].z - b[0].z || a[1] - b[1]).map((e) => e[0]);
}

/// A part made in the code, from points measured in figure units about its own middle.
function made(id, b, x, y, w, h, rot, z, sh, fill, env, extra = {}) {
  const [dx, dy] = rotv(x, y, b.rot);
  const conv = (ops) => ops.map((op) => [op[0], ...op.slice(1).map((v, i) => (i % 2 === 0 ? v / w + 0.5 : v / h + 0.5))]);
  return { id, sh, x: b.x + dx, y: b.y + dy, w, h, rot: b.rot + rot, r: extra.r ?? 0, ops: extra.ops ? conv(extra.ops) : null,
           fill: paint(fill, env), stroke: extra.s ? [color(extra.s[0], env), extra.s[1]] : null, ol: null, o: extra.o ?? 1, z,
           txt: extra.t ?? null, kids: (extra.kids || []).map((k, i) => {
             const q = kid(k, env, id + '.' + i);
             if (k[7] && k[7].ops) q.ops = k[7].ops.map((op) => [op[0], ...op.slice(1).map((v, j) => (j % 2 === 0 ? v / k[3] + 0.5 : v / k[4] + 0.5))]);
             return q;
           }) };
}

/// The face: brows, eyes with their lids and lights, cheeks, freckles and the mouth, from the pose.
function face(spec, ch, B, env, out, glasses) {
  const b = B.head, F = spec.face, z = spec.z.face;
  const wide = ch.eyeWide;
  for (const s of [-1, 1]) {
    const n = s < 0 ? 'L' : 'R';
    const ex = s * F.eyeX + ch.lookX * 1.3, ey = F.eyeY + ch.lookY * 1.1;
    const closedSmile = ch.eyeSmile >= 0.5 || (ch.wink >= 0.5 && s > 0);
    const open = ch.eyeOpen;
    if (closedSmile) {
      out.push(made('eye' + n, b, ex, ey + 0.6, 11, 7, 0, z, 'path', null, env, { ops: [['M', -4.9, 2.2], ['Q', 0, -5.6, 4.9, 2.2]], s: ['eye', 2.1] }));
    } else if (open < 0.12) {
      out.push(made('eye' + n, b, ex, ey + 1.6, 11, 6, 0, z, 'path', null, env, { ops: [['M', -4.7, -1.2], ['Q', 0, 3.6, 4.7, -1.2]], s: ['eye', 1.9] }));
    } else {
      const w = F.eyeW * (1 + 0.16 * wide), h = F.eyeH * (1 + 0.16 * wide);
      const kids = [['el', 0, h * 0.36, w * 0.8, h * 0.42, 0, 'eyeRing@70'],
                    ['el', -w * 0.2 + ch.lookX * 0.5, -h * 0.23 + ch.lookY * 0.4, w * 0.42, w * 0.42, 0, 'white'],
                    ['el', w * 0.2 + ch.lookX * 0.5, h * 0.22 + ch.lookY * 0.4, w * 0.19, w * 0.19, 0, 'white@92']];
      if (open < 0.97) {
        const cover = (1 - open) * h, tilt = -s * ch.lid;
        kids.push(['rr', 0, -h / 2 + cover / 2 - 3, w * 2, cover + 6, tilt, 'skin']);
        kids.push(['rr', 0, -h / 2 + cover, w * 2, 1.5, tilt, 'eye']);
      }
      out.push(made('eye' + n, b, ex, ey, w, h, 0, z, 'el', 'eye', env, { kids }));
    }
    // Brows: the inner end down is intent, the inner end up is worry; one raised is a question.
    const by = F.browY - ch.browY - (s > 0 ? ch.browAsym * 1.8 : -ch.browAsym * 0.7) - 1.2 * wide;
    out.push(made('brow' + n, b, s * F.eyeX, by, 6.4, 1.7, -s * ch.brow, z + 0.2, 'cap', 'brow', env));
    out.push(made('cheek' + n, b, s * F.cheekX, F.cheekY, 11, 7.2, 0, z - 0.3, 'el', ['rad', 'blush@' + Math.round(clamp(52 * ch.blush, 0, 100)), 'blush@0', 0.5, 0.5, 0.5], env));
    for (const [i, [fx, fy]] of [[-3.6, -1.9], [0, -3.2], [2.7, -0.7]].entries())
      out.push(made('fr' + n + i, b, s * (F.cheekX + fx), F.cheekY + fy, 1.5, 1.5, 0, z - 0.2, 'el', 'freckle@90', env));
  }
  const mx = ch.mouthX, my = F.mouthY + ch.mouthY, mo = clamp(ch.mouthOpen, 0.2, 1.4), mw = ch.mouthW;
  const line = ['mouthLine', 1.8];
  const m = (id, w, h, ops, fill, extra = {}) => out.push(made(id, b, mx, my, w, h, 0, z + 0.4, 'path', fill, env, { ops, ...extra }));
  switch (ch.mouth) {
    case 'grin': {
      const hw = 6.3 * mw, d = 6.6 * mo;
      m('mouth', 14, 12, [['M', -hw, -2.3], ['Q', 0, -0.4, hw, -2.3], ['C', hw - 0.4, d * 0.75, hw * 0.45, d, 0, d], ['C', -hw * 0.45, d, -hw + 0.4, d * 0.75, -hw, -2.3], ['Z']], 'mouthIn',
        { s: ['mouthLine', 0.9], kids: [['el', 0, d + 0.4, hw * 1.5, d * 0.95, 0, 'tongue']] });
      break;
    }
    case 'teeth': {
      const hw = 6 * mw, d = 4.6 * mo;
      m('mouth', 14, 10, [['M', -hw, -1.9], ['Q', 0, -0.9, hw, -1.9], ['C', hw - 0.3, d * 0.8, hw * 0.5, d, 0, d], ['C', -hw * 0.5, d, -hw + 0.3, d * 0.8, -hw, -1.9], ['Z']], 'mouthIn',
        { s: ['mouthLine', 0.9], kids: [['rr', 0, -1.7, hw * 2, 2.9, 0, 'tooth', { r: 0.8 }]] });
      break;
    }
    case 'open': out.push(made('mouth', b, mx, my + 0.6, 4.6 * mw, 5.4 * mo, 0, z + 0.4, 'el', 'mouthIn', env, { s: ['mouthLine', 0.7] })); break;
    case 'yawn': out.push(made('mouth', b, mx, my + 1.4, 8.6 * mw, 10.8 * mo, 0, z + 0.4, 'el', 'mouthIn', env,
                           { s: ['mouthLine', 0.8], kids: [['el', 0, 10.8 * mo * 0.42, 7, 5.5, 0, 'tongue']] })); break;
    case 'flat': m('mouth', 9, 3, [['M', -3.1 * mw, 0.4], ['L', 3.1 * mw, 0.4]], null, { s: line }); break;
    case 'smirk': m('mouth', 11, 6, [['M', -4.1 * mw, 0.9], ['Q', 0.8, 2.9, 4.5 * mw, -1.9]], null, { s: line }); break;
    case 'wavy': m('mouth', 11, 6, [['M', -4.6, 0.8], ['Q', -2.3, -2, 0, 0.8], ['Q', 2.3, 3.6, 4.6, 0.8]], null, { s: line }); break;
    case 'pout': m('mouth', 8, 5, [['M', -2.9, 1.5], ['Q', 0, -1.5, 2.9, 1.5]], null, { s: line }); break;
    case 'tongue':
      m('mouth', 11, 7, [['M', -4.6 * mw, -1.2], ['Q', 0, 3.6, 4.6 * mw, -1.2]], null, { s: line });
      out.push(made('tongue', b, mx + 1.5, my + 3.1, 4.4, 5, 0, z + 0.5, 'el', 'tongue', env, { s: ['mouthLine', 0.6] }));
      break;
    default: m('mouth', 11, 7, [['M', -4.6 * mw, -1.2], ['Q', 0, 3.6, 4.6 * mw, -1.2]], null, { s: line });
  }
}

/// What floats about it: each mark is [shape, x, y, size, fill, options] from the head's middle, with
/// "rise" lifting and fading it over the loop, and "tw" making it come and go.
function propParts(prop, ch, B, env, out) {
  const b = { ...B.head, rot: 0 };
  const ph = ((ch.propPhase % 1) + 1) % 1;
  prop.forEach((mk, i) => {
    const [sh, x, y, size, fill, o = {}] = mk;
    const p = ((ph + (o.off ?? 0)) % 1 + 1) % 1;
    let dy = 0, alpha = 1, k = 1;
    if (o.rise) { dy = -o.rise * p; alpha = p < 0.15 ? p / 0.15 : 1 - smooth((p - 0.55) / 0.45); k = 0.8 + 0.3 * p; }
    if (o.fall) { dy = o.fall * p; alpha = p < 0.1 ? p / 0.1 : 1 - smooth((p - 0.6) / 0.4); }
    if (o.tw) { k = 0.75 + 0.35 * Math.abs(Math.sin(Math.PI * (p + (o.off ?? 0)))); }
    const w = size * k, h = (o.h ?? size) * k;
    out.push({ id: 'p' + i, sh, x: b.x + x, y: b.y + y + dy, w, h, rot: o.rot ?? 0, r: o.r ?? 0, ops: o.d ? parsePath(o.d) : null,
               fill: paint(fill, env), stroke: o.s ? [color(o.s[0], env), o.s[1]] : null, ol: null, o: alpha * (o.o ?? 1), z: 90 + i * 0.01, txt: o.t ?? null, kids: [] });
  });
}

// MARK: Drawing on a canvas

function trace(ctx, p, w, h) {
  ctx.beginPath();
  if (p.sh === 'el') ctx.ellipse(0, 0, w / 2, h / 2, 0, 0, Math.PI * 2);
  else if (p.sh === 'cap' || p.sh === 'rr') {
    const r = p.sh === 'cap' ? Math.min(w, h) / 2 : Math.min(p.r * (w / p.w), w / 2, h / 2);
    ctx.roundRect(-w / 2, -h / 2, w, h, r);
  } else if (p.sh === 'path' && p.ops) {
    for (const op of p.ops) {
      const v = op.slice(1).map((n, i) => (i % 2 === 0 ? (n - 0.5) * w : (n - 0.5) * h));
      if (op[0] === 'M') ctx.moveTo(v[0], v[1]);
      else if (op[0] === 'L') ctx.lineTo(v[0], v[1]);
      else if (op[0] === 'Q') ctx.quadraticCurveTo(v[0], v[1], v[2], v[3]);
      else if (op[0] === 'C') ctx.bezierCurveTo(v[0], v[1], v[2], v[3], v[4], v[5]);
      else ctx.closePath();
    }
  }
}
const css = (c) => `rgba(${c.rgb[0]},${c.rgb[1]},${c.rgb[2]},${c.a})`;
function fillStyle(ctx, f, w, h) {
  if (f.k === 'solid') return css(f.a);
  let g;
  if (f.k === 'lin') g = ctx.createLinearGradient((f.x0 - 0.5) * w, (f.y0 - 0.5) * h, (f.x1 - 0.5) * w, (f.y1 - 0.5) * h);
  else g = ctx.createRadialGradient((f.cx - 0.5) * w, (f.cy - 0.5) * h, 0, (f.cx - 0.5) * w, (f.cy - 0.5) * h, f.r * Math.max(w, h));
  g.addColorStop(0, css(f.a)); g.addColorStop(1, css(f.b));
  return g;
}
function drawPart(ctx, p, s) {
  if (p.o <= 0.001) return;
  ctx.save();
  ctx.translate(p.x * s, p.y * s);
  ctx.rotate(p.rot * D2R);
  if (p.flip) ctx.scale(-1, 1);
  ctx.globalAlpha *= p.o;
  const w = p.w * s, h = p.h * s;
  if (p.sh === 'txt') {
    ctx.font = `800 ${h}px ui-rounded, "SF Pro Rounded", "Arial Rounded MT Bold", system-ui, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = fillStyle(ctx, p.fill, w, h);
    ctx.fillText(p.txt, 0, 0);
    ctx.restore();
    return;
  }
  trace(ctx, p, w, h);
  if (p.fill) { ctx.fillStyle = fillStyle(ctx, p.fill, w, h); ctx.fill(); }
  if (p.kids && p.kids.length) {
    ctx.save();
    ctx.clip();
    for (const k of p.kids) drawPart(ctx, k, s);
    ctx.restore();
    trace(ctx, p, w, h);
  }
  if (p.stroke) {
    ctx.lineWidth = p.stroke[1] * s; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.strokeStyle = css(p.stroke[0]); ctx.stroke();
  }
  ctx.restore();
}
/// Draws the parts into a box `scale` times the figure's 100 by 120, with its corner at (x, y).
/// `turn` is how far through a spin it is (0…1): the picture narrows to nothing and opens again.
export function draw(ctx, list, x, y, scale, turn = 0) {
  ctx.save();
  ctx.translate(x, y);
  if (turn > 0) {
    const k = Math.abs(Math.cos(turn * Math.PI));
    ctx.translate(50 * scale, 0); ctx.scale(Math.max(0.04, k), 1); ctx.translate(-50 * scale, 0);
  }
  for (const p of list) drawPart(ctx, p, scale);
  ctx.restore();
}
