import 'package:filosign/recognizer/v4/hold_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand of size 0.1 (wrist -> middle knuckle) with its centre near (x, y).
List<double> hand(double x, double y) {
  final h = List<double>.filled(63, 0);
  for (var j = 0; j < 21; j++) {
    h[j * 3] = x;
    h[j * 3 + 1] = y;
  }
  h[27] = x; // landmark 9 (middle knuckle) 0.1 above the wrist
  h[28] = y - 0.1;
  return h;
}

/// Runs a script of (seconds, moving?) segments at 20 frames/s; returns the
/// times (from the start) when the detector fired.
List<double> run(List<(double, bool)> script) {
  final d = HoldDetector();
  final fired = <double>[];
  var t = 0.0, x = 0.3;
  for (final (secs, moving) in script) {
    final end = t + secs;
    while (t < end - 1e-9) {
      if (moving) x += 0.02; // 0.4 /s = 4 hand sizes per second
      if (d.add(hand(x, 0.5), t, 1, 1)) fired.add(t);
      t += 0.05;
    }
  }
  return fired;
}

void main() {
  test('sign, then hold still -> fires once, 0.7-1.1 s into the hold', () {
    // 80% of the last 1.0 s must be still (same rule as src/hold_sim_v4.py)
    final f = run([(1.2, true), (2.0, false)]);
    expect(f.length, 1);
    expect(f.first, inInclusiveRange(1.2 + 0.7, 1.2 + 1.1));
  });

  test('a 0.5 s pause mid-sign (5 -> 9) does not fire', () {
    expect(run([(1.2, true), (0.5, false), (0.8, true), (0.5, false), (0.6, true)]), isEmpty);
  });

  test('moving again re-arms: a second hold fires again', () {
    expect(run([(1.2, true), (1.5, false), (0.6, true), (1.5, false)]).length, 2);
  });

  test('never fires without movement first (hand just raised and held)', () {
    expect(run([(3.0, false)]), isEmpty);
  });
}
