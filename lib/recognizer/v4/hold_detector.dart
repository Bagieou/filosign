import 'dart:math' as math;

/// "Sign, then hold still" detector for word signs (port of
/// src/hold_sim_v4.py). Fed the signing (higher) hand on every hand frame;
/// fires once when that hand, after moving, holds still for [holdS].
///
/// Speed = the hand centre's movement in hand sizes (wrist -> middle
/// knuckle) per second, in isotropic image units. Holding: ~0.1-0.5;
/// signing: median 1.7. [holdS] is 1.0 s: with 0.5 s a short pause mid-sign
/// (the "5" handshape on the way to "9") counted as a finished sign.
class HoldDetector {
  final double stillSpeed, movedSpeed, holdS, minS;
  HoldDetector({this.stillSpeed = 0.6, this.movedSpeed = 1.5, this.holdS = 1.0, this.minS = 1.0});

  final List<(double, double)> _speeds = []; // (t, speed)
  (double, double, double)? _prev; // centre x, y, t
  double _peak = 0;
  bool _armed = true;
  double? _start;

  void reset() {
    _speeds.clear();
    _prev = null;
    _peak = 0;
    _armed = true;
    _start = null;
  }

  /// No hand in this frame: the next speed starts fresh.
  void handsLost() => _prev = null;

  /// [hand]: 21 landmarks as x,y,z (upright image coords, 0..1);
  /// [sx], [sy]: image width / longer side and height / longer side.
  /// Returns true when a hold is detected (once, until the hand moves again).
  bool add(List<double> hand, double t, double sx, double sy) {
    _start ??= t;
    final size = math.max(
        math.sqrt(math.pow((hand[27] - hand[0]) * sx, 2) + math.pow((hand[28] - hand[1]) * sy, 2)),
        1e-3);
    var cx = 0.0, cy = 0.0;
    for (var j = 0; j < 21; j++) {
      cx += hand[j * 3] * sx;
      cy += hand[j * 3 + 1] * sy;
    }
    cx /= 21;
    cy /= 21;
    final prev = _prev;
    _prev = (cx, cy, t);
    if (prev == null || t <= prev.$3) return false;
    final sp = math.sqrt(math.pow(cx - prev.$1, 2) + math.pow(cy - prev.$2, 2)) / size / (t - prev.$3);
    _speeds.add((t, sp));
    final first = _speeds.first.$1;
    // keep a bit more than the hold window, or the history check below
    // could never pass
    while (_speeds.isNotEmpty && _speeds.first.$1 < t - (holdS + 0.5)) {
      _speeds.removeAt(0);
    }
    if (sp > movedSpeed) {
      _peak = math.max(_peak, sp);
      if (!_armed) {
        // moving again after a hold: the next hold counts again, but needs a
        // full new still window (else the old one fires while moving)
        _speeds.removeWhere((e) => e.$1 < t);
        _armed = true;
      }
    }
    if (!_armed || _peak <= movedSpeed) return false;
    if (t - _start! < minS || first > t - holdS) return false;
    final recent = [for (final e in _speeds) if (e.$1 >= t - holdS) e.$2];
    if (recent.length < 5) return false;
    if (recent.where((v) => v < stillSpeed).length < 0.8 * recent.length) return false;
    _armed = false;
    return true;
  }
}
