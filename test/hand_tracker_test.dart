import 'dart:convert';
import 'dart:io';

import 'package:filosign/recognizer/v4/canonical_v4.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand identity on real phone captures must match the Python replay
/// (canonical.tracked_sides) frame by frame: test/golden/tracker_golden.json
/// holds the captures and Python's dominant / other slot per frame.
void main() {
  final cases = jsonDecode(File('test/golden/tracker_golden.json').readAsStringSync()) as List;
  for (final c in cases) {
    test('hand slots: ${c['name']}', () {
      final tracker = HandSideTracker();
      final w = (c['width'] as num).toDouble(), h = (c['height'] as num).toDouble();
      final frames = c['frames'] as List;
      final expected = c['present'] as List;
      for (var i = 0; i < frames.length; i++) {
        final f = frames[i] as Map<String, dynamic>;
        final raw = RawFrameV4(
          tMs: (f['t_ms'] as num).toInt(),
          hands: [for (final hd in f['hands'] as List) [for (final v in hd as List) (v as num).toDouble()]],
          pose: f['pose'] == null ? null : [for (final v in f['pose'] as List) (v as num).toDouble()],
        );
        final frame = canonicalizeFrame(raw, w, h, c['dominant_left'] as bool, tracker: tracker);
        final want = [(expected[i] as List)[0] == 1, (expected[i] as List)[1] == 1];
        expect(frame.present, want, reason: '${c['name']} frame $i');
      }
    });
  }
}
