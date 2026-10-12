import 'dart:math' as math;
import 'dart:typed_data';

import 'canonical_v4.dart';

/// FiloSign v4 features - 1:1 port of
/// 2026-09-14-filosign-ai-v3-sprint/src/features_v4.py.
///
/// window (frames with >= 1 hand) -> One-Euro smoothing -> presence-aware
/// resample to L frames -> per-frame features.
///   letters head: 116 / frame (dominant hand only, no pose)
///   words head:   304 / frame (both hands + pose location + two-hand contact)
const int letterDim = 116;
const int wordDim = 304;
const double _eps = 1e-6;

const List<int> _tips = [4, 8, 12, 16, 20];
const List<int> _mcps = [5, 9, 13, 17];
const List<List<int>> _chains = [
  [0, 1, 2, 3, 4], [0, 5, 6, 7, 8], [0, 9, 10, 11, 12],
  [0, 13, 14, 15, 16], [0, 17, 18, 19, 20],
];
const List<List<int>> _fingerDirs = [[2, 4], [5, 8], [9, 12], [13, 16], [17, 20]];
// Pose subset (column order matters): nose, shoulders, elbows, eyes, ears, mouth.
const List<int> posePoints = [0, 11, 12, 13, 14, 2, 5, 7, 8, 9, 10];
const int _pNose = 0, _pLS = 1, _pRS = 2, _pLE = 3, _pRE = 4, _pLEye = 5,
    _pREye = 6, _pLEar = 7, _pREar = 8, _pML = 9, _pMR = 10;

class OneEuroParams {
  final double minCutoff, beta, dCutoff;
  const OneEuroParams({this.minCutoff = 3.0, this.beta = 1.0, this.dCutoff = 1.0});
}

// ---- small vector helpers (3D, as List<double>) ----------------------------
typedef V3 = List<double>;
V3 _sub(V3 a, V3 b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
double _dot(V3 a, V3 b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
double _norm(V3 a) => math.sqrt(_dot(a, a));
V3 _scale(V3 a, double s) => [a[0] * s, a[1] * s, a[2] * s];
V3 _unit(V3 a) => _scale(a, 1.0 / (_norm(a) + _eps));
V3 _cross(V3 a, V3 b) =>
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
double _cos(V3 a, V3 b) => _dot(_unit(a), _unit(b));
double _dist(V3 a, V3 b) => _norm(_sub(a, b));
double _dist2(V3 a, V3 b) {
  final dx = a[0] - b[0], dy = a[1] - b[1];
  return math.sqrt(dx * dx + dy * dy);
}

V3 _mean(List<V3> pts) {
  final m = [0.0, 0.0, 0.0];
  for (final p in pts) {
    m[0] += p[0];
    m[1] += p[1];
    m[2] += p[2];
  }
  return _scale(m, 1.0 / pts.length);
}

class _PalmFrame {
  final V3 u, v, n;
  final double scale;
  _PalmFrame(this.u, this.v, this.n, this.scale);
}

_PalmFrame _palmFrame(List<V3> P) {
  final w = P[0];
  var scale = 0.0;
  for (final m in _mcps) {
    scale += _norm(_sub(P[m], w));
  }
  scale = math.max(scale / _mcps.length, _eps);
  final u = _unit(_sub(P[9], w));
  var n = _unit(_cross(_sub(P[5], w), _sub(P[17], w)));
  final v = _unit(_cross(n, u));
  n = _cross(u, v);
  return _PalmFrame(u, v, n, scale);
}

class _HandShape {
  final List<double> shape; // 60
  final List<double> orient; // 6 (u, n)
  final List<double> rel; // 32
  final List<V3> local; // 21
  final double scale;
  final _PalmFrame frame;
  _HandShape(this.shape, this.orient, this.rel, this.local, this.scale, this.frame);
}

_HandShape _handShape(List<V3> P) {
  final f = _palmFrame(P);
  final local = <V3>[
    for (final p in P)
      () {
        final d = _sub(p, P[0]);
        return [_dot(d, f.u) / f.scale, _dot(d, f.v) / f.scale, _dot(d, f.n) / f.scale];
      }()
  ];
  final shape = <double>[for (var j = 1; j < kHandLm; j++) ...local[j]];
  final orient = <double>[...f.u, ...f.n];
  final L = local;
  final rel = <double>[
    for (final j in [8, 12, 16, 20]) _dist(L[4], L[j]), // 4
    _dist(L[4], L[6]), _dist(L[4], L[10]), // 2
  ];
  final centre = _mean([L[0], L[5], L[9], L[13], L[17]]);
  for (final t in _tips) {
    rel.add(_dist(L[t], centre)); // 5
  }
  rel.add(_cos(_sub(L[4], L[1]), _sub(L[5], L[0]))); // thumb abduction
  rel.add(_dist(L[4], L[5]));
  final dirs = [for (final ab in _fingerDirs) _sub(L[ab[1]], L[ab[0]])];
  for (var i = 0; i < 4; i++) {
    rel.add(_cos(dirs[i], dirs[i + 1])); // 4 spread
  }
  for (final ch in _chains) {
    for (var k = 1; k < 4; k++) {
      rel.add(_cos(_sub(L[ch[k]], L[ch[k - 1]]), _sub(L[ch[k + 1]], L[ch[k]]))); // 15
    }
  }
  return _HandShape(shape, orient, rel, local, f.scale, f);
}

/// Prepared (smoothed + resampled) window.
class WindowV4 {
  final List<List<V3>> h0, h1; // L x 21
  final List<bool> p0, p1;
  final List<List<V3>> pose; // L x posePoints
  final List<bool> poseOk;
  final List<double> t;
  WindowV4(this.h0, this.h1, this.p0, this.p1, this.pose, this.poseOk, this.t);
}

List<V3> _rowToPts(Float64List r) =>
    [for (var j = 0; j < r.length ~/ 3; j++) [r[j * 3], r[j * 3 + 1], r[j * 3 + 2]]];

/// features_v4.prepare_window: frames -> resampled window, or null if no hand.
WindowV4? prepareWindow(List<CanonFrame> frames, int length, OneEuroParams oe) {
  final kept = frames.where((f) => f.anyHand).toList();
  if (kept.isEmpty) return null;
  final t = [for (final f in kept) f.t];
  final out = <List<List<V3>>>[];
  final pres = <List<bool>>[];
  for (var s = 0; s < 2; s++) {
    final vals = [
      for (final f in kept)
        Float64List.fromList(f.hands.sublist(s * kHandLm * 3, (s + 1) * kHandLm * 3))
    ];
    final valid = [for (final f in kept) f.present[s]];
    final sm = oneEuro(vals, t, valid,
        minCutoff: oe.minCutoff, beta: oe.beta, dCutoff: oe.dCutoff);
    final (rs, rp) = resamplePresence(sm, valid, length);
    out.add([for (final r in rs) _rowToPts(r)]);
    pres.add(rp);
  }
  final poseVals = [
    for (final f in kept)
      Float64List.fromList([
        for (final k in posePoints) ...[f.pose[k * 3], f.pose[k * 3 + 1], f.pose[k * 3 + 2]]
      ])
  ];
  final pok = [for (final f in kept) f.poseOk];
  final psm = oneEuro(poseVals, t, pok,
      minCutoff: oe.minCutoff, beta: oe.beta, dCutoff: oe.dCutoff);
  final (pr, prOk) = resamplePresence(psm, pok, length);
  final (tr, _) = resamplePresence(
      [for (final x in t) Float64List.fromList([x])], List.filled(t.length, true), length);
  return WindowV4(out[0], out[1], pres[0], pres[1], [for (final r in pr) _rowToPts(r)],
      prOk, [for (final r in tr) r[0]]);
}

/// Per-second finite difference of a sequence of vectors (features_v4._velocity).
List<List<double>> _velocity(List<List<double>> x, List<double> t, List<bool> valid) {
  final n = x.length, d = n > 0 ? x[0].length : 0;
  final v = List.generate(n, (_) => List<double>.filled(d, 0.0));
  if (n < 2) return v;
  for (var i = 1; i < n; i++) {
    if (!(valid[i] && valid[i - 1])) continue;
    final dt = math.max(t[i] - t[i - 1], 1e-3);
    for (var k = 0; k < d; k++) {
      v[i][k] = (x[i][k] - x[i - 1][k]) / dt;
    }
  }
  v[0] = List<double>.of(v[1]);
  return v;
}

List<List<double>> _div(List<List<double>> x, double s) =>
    [for (final r in x) [for (final v in r) v / s]];

/// (L, 116) letters features.
List<Float32List> letterFeatures(WindowV4 w) {
  final L = w.t.length;
  final P = [for (var i = 0; i < L; i++) w.p0[i] ? w.h0[i] : w.h1[i]];
  final pres = [for (var i = 0; i < L; i++) w.p0[i] || w.p1[i]];
  final hs = [for (final p in P) _handShape(p)];
  double ms = 0;
  var cnt = 0;
  final wm = [0.0, 0.0, 0.0];
  for (var i = 0; i < L; i++) {
    if (!pres[i]) continue;
    ms += hs[i].scale;
    cnt++;
    for (var k = 0; k < 3; k++) {
      wm[k] += P[i][0][k];
    }
  }
  ms = cnt > 0 ? ms / cnt : 1.0;
  if (cnt > 0) {
    for (var k = 0; k < 3; k++) {
      wm[k] /= cnt;
    }
  }
  final wrist = [for (final p in P) p[0]];
  final vW = _div(_velocity(wrist, w.t, pres), ms);
  final vI = _div(_velocity([for (final p in P) p[8]], w.t, pres), ms);
  final vP = _div(_velocity([for (final p in P) p[20]], w.t, pres), ms);
  final vO = _velocity([for (final h in hs) h.orient], w.t, pres);
  return [
    for (var i = 0; i < L; i++)
      Float32List.fromList(pres[i]
          ? [
              ...hs[i].shape, ...hs[i].orient, ...hs[i].rel,
              for (var k = 0; k < 3; k++) (wrist[i][k] - wm[k]) / ms,
              ...vW[i], ...vI[i], ...vP[i], ...vO[i],
            ]
          : List<double>.filled(letterDim, 0.0))
  ];
}

/// (L, 304) words features.
List<Float32List> wordFeatures(WindowV4 w) {
  final L = w.t.length;
  final p0 = w.p0, p1 = w.p1;
  final hs0 = [for (final p in w.h0) _handShape(p)];
  final hs1 = [for (final p in w.h1) _handShape(p)];
  List<double> z(List<double> v, bool keep) => keep ? v : List<double>.filled(v.length, 0.0);
  final s0 = [for (var i = 0; i < L; i++) z(hs0[i].shape, p0[i])];
  final o0 = [for (var i = 0; i < L; i++) z(hs0[i].orient, p0[i])];
  final r0 = [for (var i = 0; i < L; i++) z(hs0[i].rel, p0[i])];
  final s1 = [for (var i = 0; i < L; i++) z(hs1[i].shape, p1[i])];
  final o1 = [for (var i = 0; i < L; i++) z(hs1[i].orient, p1[i])];
  final r1 = [for (var i = 0; i < L; i++) z(hs1[i].rel, p1[i])];

  double meanScale(List<_HandShape> hs, List<bool> p) {
    var s = 0.0, c = 0;
    for (var i = 0; i < L; i++) {
      if (p[i]) {
        s += hs[i].scale;
        c++;
      }
    }
    return s / c;
  }

  final ms = p0.contains(true)
      ? meanScale(hs0, p0)
      : (p1.contains(true) ? meanScale(hs1, p1) : 1.0);

  final rows = <Float32List>[];
  final pose = w.pose, pok = w.poseOk;
  for (var i = 0; i < L; i++) {
    if (!(p0[i] || p1[i])) {
      rows.add(Float32List(wordDim));
      continue;
    }
    final ps = pose[i];
    final mid = [(ps[_pLS][0] + ps[_pRS][0]) / 2.0, (ps[_pLS][1] + ps[_pRS][1]) / 2.0];
    final sw = math.max(_dist2(ps[_pLS], ps[_pRS]), _eps);
    List<double> relXY(V3 pt, bool valid) =>
        (valid && pok[i]) ? [(pt[0] - mid[0]) / sw, (pt[1] - mid[1]) / sw] : [0.0, 0.0];
    final mouth = _scale([ps[_pML][0] + ps[_pMR][0], ps[_pML][1] + ps[_pMR][1],
        ps[_pML][2] + ps[_pMR][2]], 0.5);
    final face = [ps[_pNose], mouth, ps[_pLEar], ps[_pREar]];
    List<double> faceDist(V3 pt, bool valid) => (valid && pok[i])
        ? [for (final a in face) _dist2(pt, a) / sw]
        : List<double>.filled(4, 0.0);
    final h0 = w.h0[i], h1 = w.h1[i];
    final loc = <double>[
      for (final j in [0, ..._tips]) ...relXY(h0[j], p0[i]), // 12
      ...relXY(h1[0], p1[i]), ...relXY(h1[8], p1[i]), // 4
      for (final k in [_pNose, _pLEye, _pREye, _pLEar, _pREar]) ...relXY(ps[k], true),
      ...relXY(mouth, true), // 12
      ...relXY(ps[_pLE], true), ...relXY(ps[_pRE], true), // 4
      for (final t in _tips) ...faceDist(h0[t], p0[i]), // 20
      ...faceDist(h1[8], p1[i]).sublist(0, 2), // 2
      pok[i] ? 1.0 : 0.0, // 1
    ];
    List<double> inter;
    if (p0[i] && p1[i]) {
      final f0 = hs0[i].frame, f1 = hs1[i].frame;
      final centre1 = _mean([h1[0], h1[5], h1[9], h1[13], h1[17]]);
      final dIdx = _sub(h1[8], h0[0]);
      inter = [
        ..._scale(_sub(h1[0], h0[0]), 1.0 / ms), // 3
        for (final t in _tips) _dist(h0[t], h1[8]) / ms, // 5
        for (final t in _tips) _dist(h0[t], centre1) / ms, // 5
        _dot(f0.u, f1.u), _dot(f0.n, f1.n), // 2
        _dot(dIdx, f0.u) / ms, _dot(dIdx, f0.v) / ms, _dot(dIdx, f0.n) / ms, // 3
      ];
    } else {
      inter = List<double>.filled(18, 0.0);
    }
    rows.add(Float32List.fromList([
      ...s0[i], ...o0[i], ...r0[i], p0[i] ? 1.0 : 0.0,
      ...s1[i], ...o1[i], ...r1[i], p1[i] ? 1.0 : 0.0,
      ...loc, ...inter,
      // motion appended below
      ...List<double>.filled(33, 0.0),
    ]));
  }
  // motion (33): needs the whole sequence
  final vW0 = _div(_velocity([for (final h in w.h0) h[0]], w.t, p0), ms);
  final vI0 = _div(_velocity([for (final h in w.h0) h[8]], w.t, p0), ms);
  final vW1 = _div(_velocity([for (final h in w.h1) h[0]], w.t, p1), ms);
  final vI1 = _div(_velocity([for (final h in w.h1) h[8]], w.t, p1), ms);
  final vTips = _velocity(
      [for (final h in hs0) [for (final t in _tips) ...h.local[t]]], w.t, p0);
  final vO = _velocity(o0, w.t, p0);
  const motionStart = wordDim - 33;
  for (var i = 0; i < L; i++) {
    if (!(p0[i] || p1[i])) continue;
    final m = [...vW0[i], ...vI0[i], ...vW1[i], ...vI1[i], ...vTips[i], ...vO[i]];
    for (var k = 0; k < 33; k++) {
      rows[i][motionStart + k] = m[k];
    }
  }
  return rows;
}

/// Full pipeline for one window of canonical frames.
List<Float32List>? featuresV4(List<CanonFrame> frames, bool letters,
    {int length = 30, OneEuroParams oe = const OneEuroParams()}) {
  final w = prepareWindow(frames, length, oe);
  if (w == null) return null;
  return letters ? letterFeatures(w) : wordFeatures(w);
}
