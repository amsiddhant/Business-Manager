// Smoke test for web/smart/1/bm_worker.js (protocol 1). Not part of
// `flutter test`. Run: node tool/smart_worker_smoke.mjs
//
// Loads the worker in a vm context that stands in for a Web Worker scope
// (self, postMessage, importScripts) with no indexedDB, so the IndexedDB
// fallback (session only) is what gets exercised. Exits non-zero on failure.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'web', 'smart', '1');

const replies = new Map();
const ctx = vm.createContext({ console: { log() {}, warn() {}, error() {} }, setTimeout, clearTimeout });
ctx.self = ctx;
// What a browser Web Worker scope has that TensorFlow.js looks for.
ctx.WorkerGlobalScope = function WorkerGlobalScope() {};
ctx.TextEncoder = TextEncoder;
ctx.TextDecoder = TextDecoder;
ctx.navigator = { userAgent: 'node-smoke' };
ctx.postMessage = (m) => {
  const w = replies.get(m.id);
  if (w) {
    replies.delete(m.id);
    w(m);
  }
};
ctx.importScripts = (...files) => {
  for (const f of files) {
    const p = path.resolve(dir, f);
    vm.runInContext(fs.readFileSync(p, 'utf8'), ctx, { filename: p });
  }
};
vm.runInContext(fs.readFileSync(path.join(dir, 'bm_worker.js'), 'utf8'), ctx, { filename: 'bm_worker.js' });

let nextId = 0;
// Typed arrays must come from the worker's realm (as they do over postMessage).
const WorkerInt32 = vm.runInContext('Int32Array', ctx);
const realm = (v) => (v instanceof Int32Array ? WorkerInt32.from(v) : v);
const call = (op, body = {}) =>
  new Promise((resolve) => {
    const id = ++nextId;
    replies.set(id, resolve);
    const data = { id, op, ...Object.fromEntries(Object.entries(body).map(([k, v]) => [k, realm(v)])) };
    ctx.self.onmessage({ data });
  });

let failures = 0;
const check = (ok, what) => {
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`);
};
const ok = async (op, body) => {
  const t0 = Date.now();
  const r = await call(op, body);
  if (!r.ok) check(false, `${op} replied error: ${r.error}`);
  r.ms = Date.now() - t0;
  return r;
};
const live = async () => (await call('hello')).ok ? ctx.tf.memory().numTensors : -1;

// --- hello -------------------------------------------------------------
const hello = await ok('hello');
check(hello.protocol === 1 && hello.version === '4.22.0' && hello.backend === 'cpu', `hello ${hello.protocol}/${hello.version}/${hello.backend}`);
const baseline = await live();

// --- unknown op / error text ---------------------------------------------
const bad = await call('nope');
check(bad.ok === false && typeof bad.error === 'string', `unknown op rejected: ${bad.error}`);
const noModel = await call('predict', { key: 'zzz', x: new Int32Array(8), n: 1, k: 1 });
check(noModel.ok === false && noModel.error === 'No model', `predict without a model: ${noModel.error}`);

// --- selftest ------------------------------------------------------------
const st = await ok('selftest');
console.log(
  `selftest: version ${st.version} backend ${st.backend} accuracy ${st.accuracy} forecastError ${st.forecastError?.toFixed(4)} ` +
    `storage ${st.storage} tensors ${st.before} -> ${st.after} (${st.ms} ms)`,
);
check(st.version === '4.22.0', 'selftest version');
check(st.accuracy >= 0.9, 'selftest accuracy >= 0.9');
check(st.forecastError <= 0.2, 'selftest forecastError <= 0.2');
check(st.storage === false, 'selftest storage false without IndexedDB');
check(st.after <= st.before, 'selftest tensors not leaked');

// --- forecast ------------------------------------------------------------
function seasonal(n, noise = 0) {
  const y = new Float64Array(n);
  const m = new Int32Array(n);
  for (let t = 0; t < n; t++) {
    m[t] = ((t + 3) % 12) + 1; // starts in April
    const a = (2 * Math.PI * m[t]) / 12;
    y[t] = 50000 + 400 * t + 8000 * Math.sin(a) + 3000 * Math.cos(a) + noise * Math.sin(t * 7.3);
  }
  return { y, m };
}
{
  const { y, m } = seasonal(36, 300);
  const f = await ok('forecast', { y, m, h: 12 });
  console.log(`forecast 36mo: error ${f.error?.toFixed(4)} first mean ${f.mean?.[0]?.toFixed(0)} (${f.ms} ms)`);
  check(f.mean?.length === 12 && f.lower?.length === 12 && f.upper?.length === 12, 'forecast shapes (h=12)');
  let order = true;
  let finite = true;
  for (let k = 0; k < 12; k++) {
    if (!(f.lower[k] <= f.mean[k] && f.mean[k] <= f.upper[k])) order = false;
    if (![f.mean[k], f.lower[k], f.upper[k]].every(Number.isFinite)) finite = false;
  }
  check(order && finite, 'forecast lower <= mean <= upper, finite');
  check(f.upper[11] - f.lower[11] > f.upper[0] - f.lower[0], 'band widens with the step');
  check(f.error < 0.1, 'forecast 36mo error small');
  // truth for the next month
  const tn = 36;
  const mn = ((tn + 3) % 12) + 1;
  const a = (2 * Math.PI * mn) / 12;
  const truth = 50000 + 400 * tn + 8000 * Math.sin(a) + 3000 * Math.cos(a);
  check(Math.abs(f.mean[0] - truth) / truth < 0.1, `forecast next month within 10% (${f.mean[0].toFixed(0)} vs ${truth.toFixed(0)})`);
}
{
  const n = 24;
  const y = new Float64Array(n);
  const m = new Int32Array(n);
  for (let t = 0; t < n; t++) {
    m[t] = (t % 12) + 1;
    y[t] = 1000 + 50 * t;
  }
  const f = await ok('forecast', { y, m, h: 6 });
  console.log(`forecast 24mo linear: error ${f.error?.toFixed(4)} mean ${Array.from(f.mean ?? []).map((v) => v.toFixed(0)).join(',')} (${f.ms} ms)`);
  check(f.mean?.length === 6 && f.error < 0.15, 'forecast 24mo linear shapes and error');
  check(f.mean[0] > y[n - 1] * 0.9 && f.mean[0] < y[n - 1] * 1.2, 'forecast 24mo continues near the last value');
  const zero = await call('forecast', { y: new Float64Array(12), m: new Int32Array(12).fill(1), h: 3 });
  check(zero.ok === false, `forecast rejects an all-zero series: ${zero.error}`);
}

// --- anomaly -------------------------------------------------------------
{
  const k = 4;
  const n = 13;
  const x = new Float64Array(k * n);
  const m = new Int32Array(n);
  for (let t = 0; t < n; t++) m[t] = ((t + 3) % 12) + 1;
  const wob = [0.03, -0.04, 0.05, -0.02, 0.04, -0.05, 0.02, -0.03, 0.05, -0.04, 0.03, -0.02, 0.04];
  for (let i = 0; i < k; i++) {
    const base = 1000 * (i + 1);
    for (let t = 0; t < n; t++) {
      const a = (2 * Math.PI * m[t]) / 12;
      x[i * n + t] = base * (1 + 0.1 * Math.sin(a) + wob[(t + 3 * i) % 13]);
    }
  }
  x[2 * n + n - 1] *= 4; // series 2 spikes this month
  const a = await ok('anomaly', { x, m, k, n });
  const s = Array.from(a.scores ?? []);
  console.log(`anomaly scores: ${s.map((v) => v.toFixed(2)).join(', ')} (${a.ms} ms)`);
  check(s.length === k && s.every(Number.isFinite), 'anomaly shape, no NaN');
  check(s[2] > 4 && [0, 1, 3].every((i) => Math.abs(s[i]) < 3), 'anomaly: spiked series high, others low');
  // a dead series comes back NaN without hurting the rest
  const x2 = Float64Array.from(x);
  for (let t = 0; t < n; t++) x2[t] = 0;
  const b = await ok('anomaly', { x: x2, m, k, n });
  check(Number.isNaN(b.scores[0]) && Number.isFinite(b.scores[2]), 'anomaly: all-zero series is NaN, others scored');
}

// --- classifier: train / predict / save / load / drop -----------------------
{
  const L = 8;
  const B = 256;
  const D = 8;
  const rnd = (() => {
    let s = 99;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  })();
  // class a: tokens 10..15 (+ noise), class b: tokens 100..105; head 2 = parity of a
  const make = (n) => {
    const x = new Int32Array(n * L);
    const ya = new Int32Array(n);
    const yb = new Int32Array(n);
    for (let i = 0; i < n; i++) {
      const c = Math.floor(rnd() * 3);
      ya[i] = c;
      yb[i] = c === 2 ? 1 : 0;
      for (let j = 0; j < L; j++) x[i * L + j] = c * 50 + 10 + Math.floor(rnd() * 6);
    }
    return { x, ya, yb };
  };
  const tr = make(120);
  const ho = make(30);
  const spec = {
    key: 'toy',
    L, B, D,
    heads: [{ name: 'cat', classes: 3 }, { name: 'kind', classes: 2 }],
    n: 120, x: tr.x, y: { cat: tr.ya, kind: tr.yb },
    hn: 30, hx: ho.x, epochs: 40, batch: 16, lr: 0.05,
  };
  const t = await ok('train', spec);
  const acc = (r, y) => {
    let right = 0;
    for (let i = 0; i < y.length; i++) if (r.top[i] === y[i]) right++;
    return right / y.length;
  };
  const ha = acc(t.heads.cat, ho.ya);
  const hb = acc(t.heads.kind, ho.yb);
  console.log(`train: ${t.ms} ms, holdout accuracy cat ${ha.toFixed(2)} kind ${hb.toFixed(2)}`);
  check(t.heads.cat.k === 1 && t.heads.cat.top.length === 30 && t.heads.cat.p.length === 30, 'train holdout shapes');
  check(ha >= 0.9 && hb >= 0.9, 'train holdout accuracy >= 0.9');
  const t0 = await ok('train', { ...spec, key: 'toy0', hn: 0, hx: null, epochs: 2 });
  check(Object.keys(t0.heads).length === 0, 'train without holdout gives {}');

  const p1 = await ok('predict', { key: 'toy', x: ho.x, n: 30, k: 3 });
  check(p1.heads.cat.k === 3 && p1.heads.kind.k === 2, 'predict k clipped to classes');
  check(acc({ top: p1.heads.cat.top.filter((_, i) => i % 3 === 0) }, ho.ya) === ha, 'predict best == holdout');
  const sorted = Array.from({ length: 30 }, (_, i) => p1.heads.cat.p[i * 3] >= p1.heads.cat.p[i * 3 + 1]).every(Boolean);
  check(sorted, 'predict best first');

  const sv = await ok('save', { key: 'toy', meta: 'meta-1' });
  check(sv.persisted === false, 'save falls back to the session without IndexedDB');
  await ok('drop', { key: 'toy0' });
  // evict from memory by training 6 other models, then load from the session
  for (let i = 0; i < 6; i++) await ok('train', { ...spec, key: `fill${i}`, hn: 0, hx: null, epochs: 1 });
  const gone = await call('predict', { key: 'toy', x: ho.x, n: 30, k: 1 });
  check(gone.ok === false && gone.error === 'No model', 'oldest model evicted beyond 6');
  const ld = await ok('load', { key: 'toy' });
  check(ld.meta === 'meta-1', `load returns meta (${ld.meta})`);
  const p2 = await ok('predict', { key: 'toy', x: ho.x, n: 30, k: 3 });
  const same = p1.heads.cat.top.every((v, i) => v === p2.heads.cat.top[i]) && p1.heads.cat.p.every((v, i) => v === p2.heads.cat.p[i]);
  check(same, 'predict after save/load identical');
  check((await ok('load', { key: 'nothing' })).meta === null, 'load of a missing key gives null');
  await ok('drop', { key: 'toy' });
  const afterDrop = await call('predict', { key: 'toy', x: ho.x, n: 30, k: 1 });
  check(afterDrop.ok === false, 'predict after drop fails');
  check((await ok('load', { key: 'toy' })).meta === null, 'load after drop gives null');
}

// --- wipe + leak check -----------------------------------------------------
await ok('wipe');
const end = await live();
check(end === baseline, `no tensor leak across ops (${baseline} -> ${end})`);
check((await call('predict', { key: 'fill5', x: new Int32Array(8), n: 1, k: 1 })).ok === false, 'wipe cleared models');

console.log(failures ? `\n${failures} check(s) FAILED` : '\nall checks passed');
process.exit(failures ? 1 : 0);
