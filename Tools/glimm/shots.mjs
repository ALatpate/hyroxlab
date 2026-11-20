// Contact sheets of Glimm, drawn by the reference renderer in a headless browser.
//
//   node Tools/glimm/shots.mjs <sheet> [out.png]
//
// Sheets: moods, stills:<mood>, film:<mood>[:seconds], gesture:<name>, tap:<kind>, tops, bottoms,
// feet, heads, accs, patterns, looks, mono, or cells:<json list of {mood, outfit, beat, t, style, tap, label}>.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { spec } from './spec.js';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

export const SIGNATURE = 'zip:FF766B:plain|joggers:36BFB0:plain|chunky:B5A0EF:plain|-|bag:B5A0EF:plain';
const P = { coral: 'FF766B', teal: '36BFB0', lilac: 'B5A0EF', butter: 'F5D77A', sky: '7DBFEA', rose: 'EE96BD', cobalt: '6375E7', sage: '9ABB91',
            tangerine: 'F6A05A', plum: 'A778BB', cream: 'F4E6C8', navy: '344968', mint: 'A6DEC7', cherry: 'D75C76', ochre: 'CFA050', charcoal: '566274' };
const names = Object.keys(P);
const swap = (code, slot, value) => { const s = code.split('|'); s[slot] = value; return s.join('|'); };

function sheet(name) {
  const [kind, arg, arg2] = name.split(':');
  const moods = Object.keys(spec.moods);
  switch (kind) {
    case 'moods': return moods.map((m) => ({ mood: m, outfit: SIGNATURE, label: m }));
    case 'stills': return [0, 1, 2, 3, 10, 11].map((b) => ({ mood: arg, outfit: SIGNATURE, beat: b, label: `${arg} beat ${b}` }));
    case 'film': { const n = 12, span = Number(arg2 || 6); return Array.from({ length: n }, (_, i) => ({ mood: arg, outfit: SIGNATURE, t: 40 + (i * span) / n, label: `t+${((i * span) / n).toFixed(1)}` })); }
    case 'gesture': return Array.from({ length: 10 }, (_, i) => ({ mood: arg2 || 'steady', outfit: SIGNATURE, play: { name: arg, phase: i / 9 }, label: `${arg} ${(i / 9).toFixed(2)}` }));
    case 'tap': return Array.from({ length: 10 }, (_, i) => ({ mood: arg2 || 'steady', outfit: SIGNATURE, tap: { kind: arg, phase: i / 9 }, label: `${arg} ${(i / 9).toFixed(2)}` }));
    case 'tops': return Object.keys(spec.tops).map((k, i) => ({ mood: 'steady', outfit: swap(SIGNATURE, 0, `${k}:${P[names[i % 16]]}:plain`), label: k }));
    case 'bottoms': return Object.keys(spec.bottoms).map((k, i) => ({ mood: 'steady', outfit: swap(swap(SIGNATURE, 0, 'tee:F4E6C8:plain'), 1, `${k}:${P[names[(i + 5) % 16]]}`), label: k }));
    case 'feet': return Object.keys(spec.feet).map((k, i) => ({ mood: 'steady', outfit: swap(swap(SIGNATURE, 1, 'shorts:344968'), 2, `${k}:${P[names[(i + 2) % 16]]}`), label: k }));
    case 'heads': return Object.keys(spec.heads).map((k, i) => ({ mood: 'steady', outfit: swap(swap(SIGNATURE, 4, '-'), 3, `${k}:${P[names[(i + 3) % 16]]}`), label: k }));
    case 'accs': return Object.keys(spec.accs).map((k, i) => ({ mood: 'steady', outfit: swap(swap(SIGNATURE, 0, 'tee:F4E6C8:plain'), 4, `${k}:${P[names[(i + 6) % 16]]}`), label: k }));
    case 'patterns': return ['plain', 'stripes', 'dots', 'checks', 'stars', 'sprinkles'].flatMap((p, i) =>
      ['tee', 'zip'].map((t, j) => ({ mood: 'steady', outfit: swap(SIGNATURE, 0, `${t}:${P[names[(i * 2 + j) % 16]]}:${p}`), label: `${t} ${p}` })));
    case 'wear': return ['bottoms', 'feet', 'heads', 'accs'].flatMap((k) => sheet(k));
    case 'review': {
      const g = (n, phases, mood = 'steady') => phases.map((ph) => ({ mood, outfit: SIGNATURE, play: { name: n, phase: ph }, label: `${n} ${ph}` }));
      const t = (k, phases) => phases.map((ph) => ({ mood: 'steady', outfit: SIGNATURE, tap: { kind: k, phase: ph }, label: `tap ${k} ${ph}` }));
      return [...g('wave', [0.2, 0.35, 0.5]), ...g('leafTouch', [0.25, 0.5]), ...g('bow', [0.15, 0.45, 0.88], 'proud'), ...g('yawn', [0.2, 0.5], 'sleepy'),
              ...g('checkShoes', [0.3, 0.5]), ...g('stretch', [0.4]), ...g('shy', [0.5]), ...g('twirl', [0.25, 0.42]), ...g('flex', [0.4], 'proud'), ...g('sip', [0.5], 'resting'),
              ...g('drink', [0.5], 'thirsty'), ...g('rubEye', [0.4], 'sleepy'), ...g('nod', [0.55], 'sleepy'), ...g('wiggle', [0.2, 0.45], 'cheeky'),
              ...t('head', [0.3]), ...t('leaf', [0.12, 0.3]), ...t('belly', [0.3]), ...t('feet', [0.3]), ...t('cheek', [0.15, 0.6]), ...t('hug', [0.5]),
              ...[0, 0.2, 0.4, 0.6].map((d) => ({ mood: 'focused', outfit: SIGNATURE, t: 40 + d, label: `run +${d}` })),
              ...[0, 0.21, 0.42].map((d) => ({ mood: 'celebrating', outfit: SIGNATURE, t: 40 + d, label: `party +${d}` }))];
    }
    case 'mono': return moods.map((m) => ({ mood: m, outfit: SIGNATURE, style: 'mono', label: m }));
    case 'cells': return JSON.parse(name.slice(6));
    default: throw new Error('unknown sheet ' + name);
  }
}

export async function shoot(cells, out, { cols = 6, cell = 200, bare = false } = {}) {
  const strip = (f) => readFileSync(join(here, f), 'utf8').replace(/^export /gm, '').replace(/^import .*$/gm, '');
  const html = `<canvas id="c"></canvas><script>${strip('render.js')}\nvar spec = (function () { ${strip('spec.js')}\n return spec; })();</script>`;
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  page.on('pageerror', (e) => { console.error('page error:', e.message); });
  await page.setContent(html);
  const data = await page.evaluate(({ cells, cols, cell, bare }) => {
    const c = document.getElementById('c');
    const rows = Math.ceil(cells.length / cols), ch = Math.round(cell * 1.2) + (bare ? 0 : 18);
    c.width = Math.min(cols, cells.length) * cell; c.height = rows * ch;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#0A0D14'; ctx.fillRect(0, 0, c.width, c.height);
    cells.forEach((q, i) => {
      const x = (i % cols) * cell, y = Math.floor(i / cols) * ch;
      if (q.style === 'mono') { ctx.fillStyle = '#3A4658'; ctx.fillRect(x, y, cell, ch); }
      ctx.strokeStyle = '#1B2230'; ctx.strokeRect(x + 0.5, y + 0.5, cell - 1, ch - 1);
      const chn = channels(spec, q.mood || 'steady', { t: q.t ?? null, beat: q.beat ?? 0, energy: q.energy ?? 0.7, tap: q.tap ?? null, play: q.play ?? null });
      if (q.set) Object.assign(chn, q.set);
      draw(ctx, parts(spec, chn, q.outfit, { style: q.style || 'color' }), x, y, cell / 100, chn.turn || 0);
      if (!bare) { ctx.fillStyle = '#A7B1C4'; ctx.font = '12px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.fillText(q.label || '', x + cell / 2, y + ch - 6); }
    });
    return c.toDataURL('image/png').slice(22);
  }, { cells, cols, cell, bare });
  await browser.close();
  writeFileSync(out, Buffer.from(data, 'base64'));
  return out;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const name = process.argv[2] || 'moods';
  const out = process.argv[3] || join(here, 'out-' + name.split(':').slice(0, 2).join('-') + '.png');
  const cols = Number(process.env.COLS || 6), cell = Number(process.env.CELL || 200);
  await shoot(sheet(name), out, { cols, cell });
  console.log(out);
}
