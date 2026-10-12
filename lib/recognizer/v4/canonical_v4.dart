import 'dart:math' as math;
import 'dart:typed_data';

/// FiloSign v4 canonical landmark space - 1:1 port of
/// 2026-09-14-filosign-ai-v3-sprint/src/canonical.py.
///
///  1. Upright    - hands are rotated by sensorOrientation before this point;
///                  pose arrives upright from the plugin.
///  2. Isotropic  - letterbox into the unit square of the longer side
///                  S = max(W, H):  X = (x-.5)*W/S+.5, Y = (y-.5)*H/S+.5, Z = z*W/S
///  3. Chirality  - reflect (X -> 1-X, swap Pose L/R) when the signer's
///                  dominant hand is the LEFT one (user setting).
///  4. Slots      - slot0 = dominant hand, slot1 = other hand.
const int kHandLm = 21;
const int kPoseLm = 33;
const int poseRWrist = 16, poseLWrist = 15;
const int poseLShoulder = 11, poseRShoulder = 12;
const double poseVisMin = 0.5;

const List<List<int>> _poseLrPairs = [
  [1, 4], [2, 5], [3, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16],
  [17, 18], [19, 20], [21, 22], [23, 24], [25, 26], [27, 28], [29, 30], [31, 32],
];
final List<int> poseSwapIdx = () {
  final idx = List<int>.generate(kPoseLm, (i) => i);
  for (final p in _poseLrPairs) {
    idx[p[0]] = p[1];
    idx[p[1]] = p[0];
  }
  return idx;
}();

/// What the app has for one camera frame, in the UPRIGHT image, normalized
/// to that image (MediaPipe convention, before letterboxing).
class RawFrameV4 {
  final int tMs;
  /// Detected hands in detection order, each 21*3 (x, y, z).
  final List<List<double>> hands;
  /// 33*4 (x, y, z, visibility) or null when no pose this frame.
  final List<double>? pose;
  const RawFrameV4({required this.tMs, required this.hands, this.pose});
}

/// One frame in canonical space.
class CanonFrame {
  final double t; // seconds
  final Float32List hands; // 2 * 21 * 3, slot-major
  final List<bool> present; // [slot0, slot1]
  final Float32List pose; // 33 * 3
  final Float32List poseVis; // 33
  final bool poseOk;
  CanonFrame(this.t, this.hands, this.present, this.pose, this.poseVis, this.poseOk);

  bool get anyHand => present[0] || present[1];
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];

/// Letterbox one (x, y, z) triple; results rounded to float32 like numpy.
List<double> _box(double x, double y, double z, double w, double h) {
  final s = math.max(w, h);
  return [
    _f32((_f32(x) - 0.5) * (w / s) + 0.5),
    _f32((_f32(y) - 0.5) * (h / s) + 0.5),
    _f32(_f32(z) * (w / s)),
  ];
}

/// 'R'/'L' per detected hand (appearance in an un-mirrored camera). With pose:
/// nearest Pose wrist; without: image x-order (the phone plugin gives no
/// handedness labels) - person facing the camera shows the right hand on the
/// image LEFT.
List<String> appearanceSides(List<List<double>> hands, Float32List? pose) {
  final n = hands.length;
  if (n == 0) return const [];
  if (pose != null) {
    double d(int i, int p) {
      final dx = hands[i][0] - pose[p * 3], dy = hands[i][1] - pose[p * 3 + 1];
      return dx * dx + dy * dy;
    }

    if (n == 1) return [d(0, poseRWrist) <= d(0, poseLWrist) ? 'R' : 'L'];
    final straight = d(0, poseRWrist) + d(1, poseLWrist);
    final swapped = d(1, poseRWrist) + d(0, poseLWrist);
    return straight <= swapped ? ['R', 'L'] : ['L', 'R'];
  }
  if (n == 1) return ['R'];
  return hands[0][0] <= hands[1][0] ? ['R', 'L'] : ['L', 'R'];
}

/// Canonicalize one frame. [width]/[height] = upright image size.
CanonFrame canonicalizeFrame(RawFrameV4 f, double width, double height, bool reflect) {
  final hands = <List<double>>[];
  for (final h in f.hands.take(2)) {
    final out = List<double>.filled(kHandLm * 3, 0.0);
    for (var j = 0; j < kHandLm; j++) {
      final b = _box(h[j * 3], h[j * 3 + 1], h[j * 3 + 2], width, height);
      out[j * 3] = b[0];
      out[j * 3 + 1] = b[1];
      out[j * 3 + 2] = b[2];
    }
    hands.add(out);
  }
  final pose = Float32List(kPoseLm * 3);
  final vis = Float32List(kPoseLm);
  final raw = f.pose;
  for (var j = 0; j < kPoseLm; j++) {
    final x = raw == null ? 0.0 : raw[j * 4];
    final y = raw == null ? 0.0 : raw[j * 4 + 1];
    final z = raw == null ? 0.0 : raw[j * 4 + 2];
    final b = _box(x, y, z, width, height);
    pose[j * 3] = b[0];
    pose[j * 3 + 1] = b[1];
    pose[j * 3 + 2] = b[2];
    vis[j] = raw == null ? 0.0 : raw[j * 4 + 3];
  }
  final poseOk = raw != null &&
      vis[poseLShoulder] >= poseVisMin &&
      vis[poseRShoulder] >= poseVisMin;

  final sides = appearanceSides(hands, poseOk ? pose : null);

  var outPose = pose, outVis = vis;
  if (reflect) {
    for (final h in hands) {
      for (var j = 0; j < kHandLm; j++) {
        h[j * 3] = _f32(1.0 - h[j * 3]);
      }
    }
    outPose = Float32List(kPoseLm * 3);
    outVis = Float32List(kPoseLm);
    for (var j = 0; j < kPoseLm; j++) {
      final src = poseSwapIdx[j];
      outPose[j * 3] = _f32(1.0 - pose[src * 3]);
      outPose[j * 3 + 1] = pose[src * 3 + 1];
      outPose[j * 3 + 2] = pose[src * 3 + 2];
      outVis[j] = vis[src];
    }
  }

  final slots = Float32List(2 * kHandLm * 3);
  final present = [false, false];
  for (var k = 0; k < hands.length; k++) {
    var s = sides[k];
    if (reflect) s = s == 'R' ? 'L' : 'R';
    var slot = s == 'R' ? 0 : 1;
    if (present[slot]) slot = 1 - slot; // both on one side: second goes to the other slot
    for (var i = 0; i < kHandLm * 3; i++) {
      slots[slot * kHandLm * 3 + i] = hands[k][i];
    }
    present[slot] = true;
  }
  return CanonFrame(f.tMs / 1000.0, slots, present, outPose, outVis, poseOk);
}

// ---------------------------------------------------------------------------
// temporal smoothing + resampling
// ---------------------------------------------------------------------------
double _alpha(double cutoff, double dt) {
  final tau = 1.0 / (2.0 * math.pi * cutoff);
  return 1.0 / (1.0 + tau / dt);
}

/// Causal One-Euro filter. x: n rows of D values, t seconds, valid per row.
/// Restarts after any invalid row. Output rounded to float32 (numpy parity).
List<Float64List> oneEuro(List<Float64List> x, List<double> t, List<bool> valid,
    {required double minCutoff, required double beta, required double dCutoff}) {
  final out = [for (final r in x) Float64List.fromList(r)];
  Float64List? prev;
  Float64List? dprev;
  for (var i = 0; i < t.length; i++) {
    if (!valid[i]) {
      prev = null;
      continue;
    }
    if (prev == null) {
      prev = Float64List.fromList(x[i]);
      dprev = Float64List(x[i].length);
      out[i] = Float64List.fromList(prev);
      continue;
    }
    final dt = math.max(t[i] - t[i - 1], 1e-3);
    final ad = _alpha(dCutoff, dt);
    final cur = Float64List(x[i].length);
    for (var k = 0; k < x[i].length; k++) {
      final dx = (x[i][k] - prev[k]) / dt;
      final dhat = ad * dx + (1.0 - ad) * dprev![k];
      final a = _alpha(minCutoff + beta * dhat.abs(), dt);
      cur[k] = a * x[i][k] + (1.0 - a) * prev[k];
      dprev[k] = dhat;
    }
    prev = cur;
    out[i] = Float64List.fromList(cur);
  }
  for (final r in out) {
    for (var k = 0; k < r.length; k++) {
      r[k] = _f32(r[k]);
    }
  }
  return out;
}

/// Presence-aware resample of n rows to [length] rows (canonical.resample_presence).
/// Interpolates only when both neighbours are present; otherwise copies the
/// present neighbour. Returns (rows, present).
(List<Float64List>, List<bool>) resamplePresence(
    List<Float64List> values, List<bool> present, int length) {
  final n = values.length;
  final d = n > 0 ? values[0].length : 0;
  final out = List.generate(length, (_) => Float64List(d));
  final pres = List<bool>.filled(length, false);
  for (var i = 0; i < length; i++) {
    int a, b;
    double w;
    if (n == 1) {
      a = 0;
      b = 0;
      w = 0.0;
    } else {
      // numpy.linspace: i * step, last point exactly n - 1
      final src = i == length - 1 ? (n - 1).toDouble() : i * ((n - 1) / (length - 1));
      a = src.floor();
      b = math.min(a + 1, n - 1);
      w = _f32(src - a);
    }
    if (present[a] && present[b]) {
      for (var k = 0; k < d; k++) {
        out[i][k] = _f32((1.0 - w) * values[a][k] + w * values[b][k]);
      }
      pres[i] = true;
    } else if (present[a] || present[b]) {
      final src = (present[a] && (w < 0.5 || !present[b])) ? a : b;
      for (var k = 0; k < d; k++) {
        out[i][k] = values[src][k];
      }
      pres[i] = true;
    }
  }
  return (out, pres);
}
