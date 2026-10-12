import 'dart:convert';
import 'dart:io';

import 'package:filosign/recognizer/v4/canonical_v4.dart';
import 'package:filosign/recognizer/v4/features_v4.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parity with the Python training pipeline. Golden data comes from
/// 2026-09-14-filosign-ai-v3-sprint/src/make_golden_v4.py.
void main() {
  final golden = jsonDecode(
      File('test/golden/features_v4_golden.json').readAsStringSync()) as Map<String, dynamic>;
  final oeJson = golden['one_euro'] as Map<String, dynamic>;
  final oe = OneEuroParams(
    minCutoff: (oeJson['min_cutoff'] as num).toDouble(),
    beta: (oeJson['beta'] as num).toDouble(),
    dCutoff: (oeJson['d_cutoff'] as num).toDouble(),
  );
  final length = golden['sequence_length'] as int;

  for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
    test('${c['head']} ${c['sign']}/${c['clip']}', () {
      final tMs = (c['t_ms'] as List).cast<int>();
      final handN = (c['hand_n'] as List).cast<int>();
      final hands = c['hands'] as List;
      final pose = c['pose'] as List;
      final poseDet = (c['pose_det'] as List).cast<bool>();
      final w = (c['width'] as num).toDouble(), h = (c['height'] as num).toDouble();
      final reflect = c['reflect'] as bool;

      final frames = <CanonFrame>[];
      for (var i = 0; i < tMs.length; i++) {
        final hs = <List<double>>[
          for (var k = 0; k < handN[i]; k++)
            [for (final lm in (hands[i] as List)[k] as List) ...(lm as List).map((v) => (v as num).toDouble())]
        ];
        final p = poseDet[i]
            ? [for (final lm in pose[i] as List) ...(lm as List).map((v) => (v as num).toDouble())]
            : null;
        frames.add(canonicalizeFrame(RawFrameV4(tMs: tMs[i], hands: hs, pose: p), w, h, reflect));
      }

      final expPresent = (c['expected_present'] as List);
      for (var i = 0; i < frames.length; i++) {
        final e = (expPresent[i] as List).cast<bool>();
        expect(frames[i].present, e, reason: 'slot presence differs at frame $i');
      }

      final letters = c['head'] == 'letters';
      final got = featuresV4(frames, letters, length: length, oe: oe)!;
      final exp = (c['expected_features'] as List);
      expect(got.length, exp.length);
      var maxDiff = 0.0;
      var where = '';
      for (var i = 0; i < exp.length; i++) {
        final row = (exp[i] as List);
        expect(got[i].length, row.length);
        for (var k = 0; k < row.length; k++) {
          final e = (row[k] as num).toDouble();
          final d = (got[i][k] - e).abs() / (1.0 + e.abs());
          if (d > maxDiff) {
            maxDiff = d;
            where = 'frame $i feature $k: dart ${got[i][k]} python $e';
          }
        }
      }
      // ignore: avoid_print
      print('${c['sign']}: max relative diff $maxDiff  ($where)');
      expect(maxDiff, lessThan(1e-3), reason: where);
    });
  }
}
