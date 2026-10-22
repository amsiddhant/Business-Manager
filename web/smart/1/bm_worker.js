/*
 * Business Manager on-device AI worker, protocol 1.
 *
 * Fits small forecast and anomaly models and trains small classifiers on this
 * device, and keeps trained classifiers in this browser's IndexedDB
 * ("bm-smart"). Loads the vendored TensorFlow.js 4.22.0 (core + cpu backend
 * only, ../../tfjs/4.22.0/) from this site only, and only on its first
 * request. The cpu backend leaves the page's WebGL (Flutter's CanvasKit)
 * alone and needs no extra files or headers. Models are written directly with
 * core ops (no tfjs-layers); tf-core ships no autodiff rules, so the
 * gradients are written out by hand and fed to Adam.
 *
 * The app does the feature hashing: this file only sees numbers: token ids,
 * class numbers and monthly figures, never text. Nothing here is logged: not
 * the inputs, the labels or the predictions.
 *
 * This folder is served with "immutable" caching: never edit it after a
 * deploy. A changed worker goes in web/smart/2/.
 *
 * Requests: {id, op, ...}. Replies: {id, ok: true, ...} or {id, ok: false,
 * error}. Requests run one at a time, in order. Ops: hello, forecast,
 * anomaly, train, save, load, predict, drop, wipe, selftest.
 */
'use strict';

var PROTOCOL = 1;
var TFJS = '../../tfjs/4.22.0/';
var DB = 'bm-smart';
var STORE = 'models';
var MAX_MODELS = 6;
var BAND_Z = 1.2816;

var tf = null;
var booting = null;
var models = new Map(); // key -> model, oldest first
var session = new Map(); // key -> saved record, when IndexedDB isn't available
var queue = Promise.resolve();

self.onmessage = function (e) {
  var msg = e.data || {};
  queue = queue
    .then(function () {
      return handle(msg);
    })
    .then(
      function (out) {
        out = out || {};
        out.id = msg.id;
        out.ok = true;
        self.postMessage(out);
      },
      function (err) {
        self.postMessage({ id: msg.id, ok: false, error: describe(err) });
      }
    );
};

function withTf(fn) {
  return boot().then(fn);
}

function handle(m) {
  switch (m.op) {
    case 'hello':
      return withTf(function () {
        return { protocol: PROTOCOL, version: tf.version_core, backend: tf.getBackend() };
      });
    case 'forecast':
      return withTf(function () {
        return forecast(m);
      });
    case 'anomaly':
      return withTf(function () {
        return anomaly(m);
      });
    case 'train':
      return withTf(function () {
        return train(m);
      });
    case 'save':
      return withTf(function () {
        return save(m.key, m.meta);
      });
    case 'load':
      return withTf(function () {
        return load(m.key);
      });
    case 'predict':
      return withTf(function () {
        return predict(m);
      });
    case 'drop':
      return drop(m.key);
    case 'wipe':
      return wipe();
    case 'selftest':
      return withTf(selfTest);
    default:
      return Promise.reject(new Error('Unknown request'));
  }
}

// Short, input-free error text.
function describe(err) {
  var s = err && (err.message || err.name) ? String(err.message || err.name) : 'Error';
  return s.length > 200 ? s.substring(0, 200) : s;
}

function boot() {
  if (!booting) {
    booting = new Promise(function (resolve) {
      importScripts(TFJS + 'tf-core.min.js', TFJS + 'tf-backend-cpu.min.js');
      tf = self.tf;
      resolve(tf.setBackend('cpu'));
    })
      .then(function (ok) {
        if (!ok) throw new Error('The cpu backend is not available');
        return tf.ready();
      })
      .then(registerBagMean)
      .catch(function (e) {
        booting = null;
        tf = null;
        throw e;
      });
  }
  return booting;
}

// ---------------------------------------------------------------------------
// Bag of tokens: each row's average token embedding (fastText).
//
// General gather/mean ops run many cpu kernels per token and make training
// ~20x slower; these two kernels do the same sums in one pass each way.
// ---------------------------------------------------------------------------

var BAG = 'BmBagMean';

function registerBagMean() {
  if (!tf.getKernel(BAG, 'cpu')) {
    tf.registerKernel({ kernelName: BAG, backendName: 'cpu', kernelFunc: bagForward });
  }
  if (!tf.getKernel(BAG + 'Grad', 'cpu')) {
    tf.registerKernel({ kernelName: BAG + 'Grad', backendName: 'cpu', kernelFunc: bagBackward });
  }
}

function bag(embeddings, ids) {
  return tf.engine().runKernel(BAG, { x: embeddings, ids: ids }, {});
}

// d(embeddings) from d(bag output): the backward kernel.
function bagGrad(dy, ids, rows) {
  return tf.engine().runKernel(BAG + 'Grad', { dy: dy, ids: ids }, { rows: rows });
}

// x: [rows, D] embeddings, ids: [n, L] -> [n, D] row means.
function bagForward(a) {
  var e = a.inputs.x;
  var ids = a.inputs.ids;
  var ev = a.backend.readSync(e.dataId);
  var iv = a.backend.readSync(ids.dataId);
  var rows = e.shape[0];
  var D = e.shape[1];
  var n = ids.shape[0];
  var L = ids.shape[1];
  var out = new Float32Array(n * D);
  for (var r = 0; r < n; r++) {
    var o = r * D;
    for (var t = 0; t < L; t++) {
      var id = iv[r * L + t];
      if (id < 0 || id >= rows) continue;
      var p = id * D;
      for (var d = 0; d < D; d++) out[o + d] += ev[p + d];
    }
    for (var j = 0; j < D; j++) out[o + j] /= L;
  }
  return a.backend.makeTensorInfo([n, D], 'float32', out);
}

// dy: [n, D], ids: [n, L] -> [rows, D] embedding gradient.
function bagBackward(a) {
  var dyv = a.backend.readSync(a.inputs.dy.dataId);
  var ids = a.inputs.ids;
  var iv = a.backend.readSync(ids.dataId);
  var rows = a.attrs.rows;
  var D = a.inputs.dy.shape[1];
  var n = ids.shape[0];
  var L = ids.shape[1];
  var out = new Float32Array(rows * D);
  for (var r = 0; r < n; r++) {
    var o = r * D;
    for (var t = 0; t < L; t++) {
      var id = iv[r * L + t];
      if (id < 0 || id >= rows) continue;
      var p = id * D;
      for (var d = 0; d < D; d++) out[p + d] += dyv[o + d] / L;
    }
  }
  return a.backend.makeTensorInfo([rows, D], 'float32', out);
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function mulberry32(seed) {
  var a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    var t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function median(a) {
  var s = Array.prototype.slice.call(a).sort(function (x, y) {
    return x - y;
  });
  var n = s.length;
  if (n === 0) return NaN;
  return n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
}

// A variable that owns its initial value (the source tensor is freed).
function makeVar(t) {
  var v = tf.variable(t);
  t.dispose();
  return v;
}

function disposeAll(named) {
  Object.keys(named).forEach(function (k) {
    named[k].dispose();
  });
}

function sdOf(a) {
  var n = a.length;
  if (n < 2) return 0;
  var mean = 0;
  for (var i = 0; i < n; i++) mean += a[i];
  mean /= n;
  var ss = 0;
  for (var j = 0; j < n; j++) ss += (a[j] - mean) * (a[j] - mean);
  return Math.sqrt(ss / (n - 1));
}

// ---------------------------------------------------------------------------
// Linear models (forecast and anomaly)
// ---------------------------------------------------------------------------

// Full-batch Adam on mean squared error + L2 on the first nPen weights.
// X: Float32Array N*F, Y: Float32Array N. Zero start: deterministic.
function fitLinear(X, Y, N, F, nPen, epochs) {
  var xt = null;
  var yt = null;
  var mask = null;
  var w = null;
  var opt = null;
  try {
    var pen = new Float32Array(F);
    for (var i = 0; i < nPen; i++) pen[i] = 1;
    xt = tf.tensor2d(X, [N, F], 'float32');
    yt = tf.tensor2d(Y, [N, 1], 'float32');
    mask = tf.tensor2d(pen, [F, 1], 'float32');
    w = makeVar(tf.zeros([F, 1]));
    opt = tf.train.adam(0.05);
    // Gradients are written out by hand: tf-core ships no autodiff rules.
    // loss = mean((xw - y)^2) + 1e-3 * sum(mask * w^2)
    var grads = function () {
      var g = {};
      g[w.name] = tf.tidy(function () {
        var d = tf.sub(tf.matMul(xt, w), yt);
        var data = tf.mul(tf.matMul(xt, d, true, false), 2 / N);
        return tf.add(data, tf.mul(tf.mul(mask, w), 2e-3));
      });
      return g;
    };
    for (var e = 0; e < epochs; e++) {
      var g = grads();
      try {
        opt.applyGradients(g);
      } finally {
        disposeAll(g);
      }
    }
    return Float64Array.from(w.dataSync());
  } finally {
    if (opt) opt.dispose();
    if (w) w.dispose();
    if (mask) mask.dispose();
    if (yt) yt.dispose();
    if (xt) xt.dispose();
  }
}

// One feature row: p lags (newest first, already scaled), month sin/cos, 1.
function putFeatures(row, off, lags, p, month) {
  for (var j = 0; j < p; j++) row[off + j] = lags[j];
  var ang = (2 * Math.PI * month) / 12;
  row[off + p] = Math.sin(ang);
  row[off + p + 1] = Math.cos(ang);
  row[off + p + 2] = 1;
}

function dot(w, row, off, F) {
  var s = 0;
  for (var j = 0; j < F; j++) s += w[j] * row[off + j];
  return s;
}

// Trains on the first `len` values of y (months mo), returns {w, p, s, sigma}.
// sigma: sd of the in-sample one-step residuals, in y's units.
function fitSeries(y, mo, len) {
  var s = 0;
  for (var i = 0; i < len; i++) s += Math.abs(y[i]);
  s /= len;
  if (!(s > 0) || !isFinite(s)) throw new Error('Flat series');
  var p = Math.max(2, Math.min(12, Math.floor(len / 2)));
  var N = len - p;
  if (N < 3) throw new Error('Too few points');
  var F = p + 3;
  var X = new Float32Array(N * F);
  var Y = new Float32Array(N);
  var lags = new Float64Array(p);
  for (var t = p; t < len; t++) {
    for (var j = 0; j < p; j++) lags[j] = y[t - 1 - j] / s;
    putFeatures(X, (t - p) * F, lags, p, mo[t]);
    Y[t - p] = y[t] / s;
  }
  var w = fitLinear(X, Y, N, F, p, 300);
  var res = new Float64Array(N);
  for (var r = 0; r < N; r++) res[r] = (Y[r] - dot(w, X, r * F, F)) * s;
  return { w: w, p: p, s: s, sigma: sdOf(res) };
}

// Recursive forecast of `h` values after the first `len` of y.
function rollForward(fit, y, len, firstMonth, h) {
  var p = fit.p;
  var F = p + 3;
  var hist = new Float64Array(len + h);
  for (var i = 0; i < len; i++) hist[i] = y[i] / fit.s;
  var row = new Float64Array(F);
  var lags = new Float64Array(p);
  var out = new Float64Array(h);
  for (var k = 0; k < h; k++) {
    var at = len + k;
    for (var j = 0; j < p; j++) lags[j] = hist[at - 1 - j];
    putFeatures(row, 0, lags, p, ((firstMonth - 1 + k) % 12) + 1);
    var v = dot(fit.w, row, 0, F);
    hist[at] = v;
    out[k] = v * fit.s;
  }
  return out;
}

// Backtest on the last `hold` values, then refit on everything.
function forecastSeries(y, mo, n, h) {
  if (n < 6) throw new Error('Too few points');
  for (var i = 0; i < n; i++) {
    if (!isFinite(y[i])) throw new Error('Bad value');
  }
  var hold = Math.min(6, Math.max(3, Math.floor(n / 4)));
  var nTrain = n - hold;
  var bt = fitSeries(y, mo, nTrain);
  var pred = rollForward(bt, y, nTrain, mo[nTrain], hold);
  var num = 0;
  var den = 0;
  for (var j = 0; j < hold; j++) {
    num += Math.abs(y[nTrain + j] - pred[j]);
    den += Math.abs(y[nTrain + j]);
  }
  var error = den === 0 ? Infinity : num / den;

  var fit = fitSeries(y, mo, n);
  var mean = rollForward(fit, y, n, (mo[n - 1] % 12) + 1, h);
  var lower = new Float64Array(h);
  var upper = new Float64Array(h);
  for (var k = 0; k < h; k++) {
    var band = BAND_Z * fit.sigma * Math.sqrt(k + 1);
    lower[k] = mean[k] - band;
    upper[k] = mean[k] + band;
  }
  return { mean: mean, lower: lower, upper: upper, error: error };
}

function forecast(m) {
  var h = m.h | 0;
  if (h < 1) throw new Error('Bad horizon');
  return forecastSeries(m.y, m.m, m.y.length, h);
}

// Shared linear model over k series: how far each series' last value sits
// above what its own history predicts, in robust standard deviations.
function anomaly(m) {
  var k = m.k | 0;
  var n = m.n | 0;
  var x = m.x;
  var mo = m.m;
  var scores = new Float64Array(k).fill(NaN);
  var p = Math.max(1, Math.min(3, n - 4));
  var F = p + 3;
  var per = n - 1 - p; // windows per series (targets p..n-2)
  if (k < 1 || per < 6) return { scores: scores };

  var scale = new Float64Array(k);
  var live = [];
  for (var i = 0; i < k; i++) {
    var head = Array.prototype.slice.call(x, i * n, i * n + n - 1);
    var s = median(head);
    if (!(s > 0)) {
      var sum = 0;
      var cnt = 0;
      for (var a = 0; a < head.length; a++) {
        if (head[a] > 0) {
          sum += head[a];
          cnt++;
        }
      }
      s = cnt ? sum / cnt : 0;
    }
    if (s > 0 && isFinite(s)) {
      scale[i] = s;
      live.push(i);
    }
  }
  if (!live.length) return { scores: scores };

  var N = live.length * per;
  var X = new Float32Array(N * F);
  var Y = new Float32Array(N);
  var lags = new Float64Array(p);
  var row = 0;
  for (var q = 0; q < live.length; q++) {
    var si = live[q];
    for (var t = p; t <= n - 2; t++) {
      for (var j = 0; j < p; j++) lags[j] = x[si * n + t - 1 - j] / scale[si];
      putFeatures(X, row * F, lags, p, mo[t]);
      Y[row] = x[si * n + t] / scale[si];
      row++;
    }
  }
  var w = fitLinear(X, Y, N, F, p, 300);

  var last = new Float64Array(F);
  for (var u = 0; u < live.length; u++) {
    var idx = live[u];
    var r = new Float64Array(per);
    for (var z = 0; z < per; z++) r[z] = Y[u * per + z] - dot(w, X, (u * per + z) * F, F);
    for (var j2 = 0; j2 < p; j2++) lags[j2] = x[idx * n + n - 2 - j2] / scale[idx];
    putFeatures(last, 0, lags, p, mo[n - 1]);
    var rLast = x[idx * n + n - 1] / scale[idx] - dot(w, last, 0, F);
    var med = median(r);
    var dev = new Float64Array(per);
    for (var d = 0; d < per; d++) dev[d] = Math.abs(r[d] - med);
    var sd = 1.4826 * median(dev);
    if (!(sd > 1e-9) || !isFinite(rLast)) continue;
    scores[idx] = (rLast - med) / sd;
  }
  return { scores: scores };
}

// ---------------------------------------------------------------------------
// Classifier: hashed token ids -> BagMean -> dropout -> one softmax per head.
// Rows are filled cyclically by the app, so the average needs no mask.
// ---------------------------------------------------------------------------

function disposeModel(model) {
  if (model.E) model.E.dispose();
  model.heads.forEach(function (h) {
    h.W.dispose();
    h.b.dispose();
  });
}

function keep(key, model) {
  var old = models.get(key);
  if (old && old !== model) disposeModel(old);
  models.delete(key);
  models.set(key, model);
  while (models.size > MAX_MODELS) {
    var first = models.keys().next().value;
    disposeModel(models.get(first));
    models.delete(first);
  }
}

function trainClassifier(m) {
  var L = m.L;
  var n = m.n;
  var rnd = mulberry32(20260101);
  var model = { L: L, B: m.B, D: m.D, E: null, heads: [] };
  var opt = null;
  try {
    model.E = makeVar(tf.randomUniform([m.B, m.D], -0.05, 0.05, 'float32', 1234));
    m.heads.forEach(function (h, i) {
      var W = makeVar(tf.randomUniform([m.D, h.classes], -0.1, 0.1, 'float32', 4321 + i));
      var b = makeVar(tf.zeros([h.classes]));
      model.heads.push({ name: h.name, classes: h.classes, W: W, b: b });
    });
    opt = tf.train.adam(m.lr || 0.01);
    var order = new Int32Array(n);
    for (var i = 0; i < n; i++) order[i] = i;
    var batch = Math.max(1, Math.min(m.batch || 32, n));
    for (var ep = 0; ep < m.epochs; ep++) {
      for (var a = n - 1; a > 0; a--) {
        var b2 = Math.floor(rnd() * (a + 1));
        var tmp = order[a];
        order[a] = order[b2];
        order[b2] = tmp;
      }
      for (var s0 = 0; s0 < n; s0 += batch) {
        var bs = Math.min(batch, n - s0);
        var ids = new Int32Array(bs * L);
        var labs = m.heads.map(function () {
          return new Int32Array(bs);
        });
        for (var r = 0; r < bs; r++) {
          var src = order[s0 + r];
          for (var t = 0; t < L; t++) ids[r * L + t] = m.x[src * L + t];
          for (var hi = 0; hi < m.heads.length; hi++) labs[hi][r] = m.y[m.heads[hi].name][src];
        }
        // Inverted dropout (rate 0.2) on the bag output, drawn here so a
        // run is repeatable.
        var keepMask = new Float32Array(bs * m.D);
        for (var q = 0; q < keepMask.length; q++) keepMask[q] = rnd() < 0.2 ? 0 : 1 / 0.8;
        var grads = tf.tidy(function () {
          var idt = tf.tensor2d(ids, [bs, L], 'int32');
          var mask = tf.tensor2d(keepMask, [bs, m.D], 'float32');
          var h = tf.mul(bag(model.E, idt), mask);
          var dh = null;
          var g = {};
          model.heads.forEach(function (hd, k) {
            var probs = tf.softmax(tf.add(tf.matMul(h, hd.W), hd.b));
            var oh = tf.oneHot(tf.tensor1d(labs[k], 'int32'), hd.classes);
            // d(mean softmax cross-entropy)/d(logits)
            var dl = tf.mul(tf.sub(probs, oh), 1 / bs);
            g[hd.W.name] = tf.matMul(h, dl, true, false);
            g[hd.b.name] = tf.sum(dl, 0);
            var back = tf.matMul(dl, hd.W, false, true);
            dh = dh ? tf.add(dh, back) : back;
          });
          g[model.E.name] = bagGrad(tf.mul(dh, mask), idt, model.B);
          return g;
        });
        try {
          opt.applyGradients(grads);
        } finally {
          disposeAll(grads);
        }
      }
    }
    return model;
  } catch (e) {
    disposeModel(model);
    throw e;
  } finally {
    if (opt) opt.dispose();
  }
}

// Top-k class numbers and probabilities per head, row by row.
function runModel(model, xs, n, k) {
  var L = model.L;
  var res = {};
  var kks = {};
  model.heads.forEach(function (h) {
    var kk = Math.max(1, Math.min(k, h.classes));
    kks[h.name] = kk;
    res[h.name] = { top: new Int32Array(n * kk), p: new Float32Array(n * kk), k: kk };
  });
  for (var s0 = 0; s0 < n; s0 += 512) {
    var bs = Math.min(512, n - s0);
    tf.tidy(function () {
      var ids = tf.tensor2d(xs.subarray(s0 * L, (s0 + bs) * L), [bs, L], 'int32');
      var emb = bag(model.E, ids);
      model.heads.forEach(function (h) {
        var probs = tf.softmax(tf.add(tf.matMul(emb, h.W), h.b));
        var t = tf.topk(probs, kks[h.name]);
        res[h.name].top.set(t.indices.dataSync(), s0 * kks[h.name]);
        res[h.name].p.set(t.values.dataSync(), s0 * kks[h.name]);
      });
    });
  }
  return res;
}

function train(m) {
  var t0 = Date.now();
  var model = trainClassifier(m);
  var heads = {};
  try {
    if (m.hn > 0 && m.hx) heads = runModel(model, m.hx, m.hn, 1);
  } catch (e) {
    disposeModel(model);
    throw e;
  }
  keep(m.key, model);
  return { ms: Date.now() - t0, heads: heads };
}

function predict(m) {
  var model = models.get(m.key);
  if (!model) throw new Error('No model');
  return { heads: runModel(model, m.x, m.n, m.k || 2) };
}

function dataOf(t) {
  return Float32Array.from(t.dataSync());
}

function save(key, meta) {
  var model = models.get(key);
  if (!model) return Promise.reject(new Error('No model'));
  var rec = {
    key: key,
    protocol: PROTOCOL,
    at: Date.now(),
    meta: meta,
    L: model.L,
    B: model.B,
    D: model.D,
    E: dataOf(model.E),
    heads: model.heads.map(function (h) {
      return { name: h.name, classes: h.classes, W: dataOf(h.W), b: dataOf(h.b) };
    }),
  };
  return idbPut(key, rec)
    .then(function () {
      session.delete(key);
      return idbTrim().catch(function () {});
    })
    .then(
      function () {
        return { persisted: true };
      },
      function () {
        // Private windows and some browsers: keep it for this session.
        session.set(key, rec);
        while (session.size > MAX_MODELS) {
          var oldest = null;
          session.forEach(function (v, k) {
            if (oldest === null || v.at < session.get(oldest).at) oldest = k;
          });
          session.delete(oldest);
        }
        return { persisted: false };
      }
    );
}

function load(key) {
  var mem = session.get(key);
  var got = mem
    ? Promise.resolve(mem)
    : idbGet(key).catch(function () {
        return null;
      });
  return got.then(function (rec) {
    if (!rec || rec.protocol !== PROTOCOL || !rec.E || !rec.heads) return { meta: null };
    var model = { L: rec.L, B: rec.B, D: rec.D, E: null, heads: [] };
    try {
      model.E = tf.tensor2d(rec.E, [rec.B, rec.D], 'float32');
      rec.heads.forEach(function (h) {
        model.heads.push({
          name: h.name,
          classes: h.classes,
          W: tf.tensor2d(h.W, [rec.D, h.classes], 'float32'),
          b: tf.tensor1d(h.b, 'float32'),
        });
      });
    } catch (e) {
      disposeModel(model);
      throw e;
    }
    keep(key, model);
    return { meta: typeof rec.meta === 'string' ? rec.meta : '' };
  });
}

function drop(key) {
  var model = models.get(key);
  if (model) {
    disposeModel(model);
    models.delete(key);
  }
  session.delete(key);
  return idbDelete(key).then(
    function () {
      return {};
    },
    function () {
      return {};
    }
  );
}

function wipe() {
  models.forEach(disposeModel);
  models.clear();
  session.clear();
  return new Promise(function (resolve) {
    if (typeof indexedDB === 'undefined' || !indexedDB) {
      resolve({});
      return;
    }
    try {
      var r = indexedDB.deleteDatabase(DB);
      r.onsuccess = r.onerror = r.onblocked = function () {
        resolve({});
      };
    } catch (e) {
      resolve({});
    }
  });
}

// ---------------------------------------------------------------------------
// Self-test
// ---------------------------------------------------------------------------

// Trains a toy classifier and a toy forecast, round-trips IndexedDB, and
// checks every tensor was freed.
function selfTest() {
  var t0 = Date.now();
  var before = tf.memory().numTensors;
  var L = 8;
  var n = 64;
  var x = new Int32Array(n * L);
  var y = new Int32Array(n);
  for (var i = 0; i < n; i++) {
    y[i] = i % 2;
    for (var j = 0; j < L; j++) x[i * L + j] = 1 + y[i] * 10 + (j % 4);
  }
  var model = trainClassifier({
    L: L,
    B: 64,
    D: 8,
    heads: [{ name: 't', classes: 2 }],
    n: n,
    x: x,
    y: { t: y },
    epochs: 30,
    batch: 16,
    lr: 0.05,
  });
  var r;
  try {
    r = runModel(model, x, n, 1).t;
  } finally {
    disposeModel(model);
  }
  var right = 0;
  for (var q = 0; q < n; q++) if (r.top[q] === y[q]) right++;

  // 36 months: trend + yearly seasonality + tiny (deterministic) noise.
  var ys = new Float64Array(36);
  var ms = new Int32Array(36);
  var rnd = mulberry32(7);
  for (var t = 0; t < 36; t++) {
    ms[t] = (t % 12) + 1;
    var ang = (2 * Math.PI * ms[t]) / 12;
    ys[t] = 1000 + 12 * t + 150 * Math.sin(ang) + 80 * Math.cos(ang) + (rnd() - 0.5) * 10;
  }
  var fc = forecastSeries(ys, ms, 36, 3);

  var probe = { at: t0 };
  return idbPut('selftest', probe)
    .then(function () {
      return idbGet('selftest');
    })
    .then(function (v) {
      return idbDelete('selftest').then(function () {
        return !!v && v.at === probe.at;
      });
    })
    .catch(function () {
      return false;
    })
    .then(function (ok) {
      return {
        version: tf.version_core,
        backend: tf.getBackend(),
        accuracy: right / n,
        forecastError: fc.error,
        storage: ok,
        before: before,
        after: tf.memory().numTensors,
        ms: Date.now() - t0,
      };
    });
}

// ---------------------------------------------------------------------------
// IndexedDB, opened per request and closed after, so the app can delete the
// database at sign-out.
// ---------------------------------------------------------------------------

function idb() {
  return new Promise(function (resolve, reject) {
    if (typeof indexedDB === 'undefined' || !indexedDB) {
      reject(new Error('No IndexedDB'));
      return;
    }
    var r;
    try {
      r = indexedDB.open(DB, 1);
    } catch (e) {
      reject(e);
      return;
    }
    r.onupgradeneeded = function () {
      r.result.createObjectStore(STORE);
    };
    r.onsuccess = function () {
      var db = r.result;
      db.onversionchange = function () {
        db.close();
      };
      resolve(db);
    };
    r.onerror = function () {
      reject(r.error || new Error('IndexedDB'));
    };
    r.onblocked = function () {
      reject(new Error('IndexedDB blocked'));
    };
  });
}

function tx(mode, fn) {
  return idb().then(function (db) {
    return new Promise(function (resolve, reject) {
      var req = null;
      var t;
      try {
        t = db.transaction(STORE, mode);
        req = fn(t.objectStore(STORE));
      } catch (e) {
        db.close();
        reject(e);
        return;
      }
      t.oncomplete = function () {
        db.close();
        resolve(req ? req.result : undefined);
      };
      t.onerror = t.onabort = function () {
        db.close();
        reject(t.error || new Error('IndexedDB'));
      };
    });
  });
}

function idbPut(key, value) {
  return tx('readwrite', function (s) {
    return s.put(value, key);
  });
}

function idbGet(key) {
  return tx('readonly', function (s) {
    return s.get(key);
  });
}

function idbDelete(key) {
  return tx('readwrite', function (s) {
    return s.delete(key);
  });
}

// Keeps the newest MAX_MODELS records.
function idbTrim() {
  return tx('readonly', function (s) {
    return s.getAll();
  }).then(function (all) {
    var recs = (all || []).filter(function (r) {
      return r && typeof r.key === 'string';
    });
    if (recs.length <= MAX_MODELS) return null;
    recs.sort(function (a, b) {
      return b.at - a.at;
    });
    return tx('readwrite', function (s) {
      recs.slice(MAX_MODELS).forEach(function (r) {
        s.delete(r.key);
      });
      return null;
    });
  });
}
