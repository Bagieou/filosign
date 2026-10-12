import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'sign_recognizer.dart';
import 'v4/canonical_v4.dart';
import 'v4/features_v4.dart';

/// FiloSign v4 recognizer (Dual-Layer). MediaPipe Hands + Pose -> canonical
/// space (upright, isotropic, dominant hand = slot0) -> v4 features over a
/// sliding time window -> average of 3 TFLite LSTMs of ONE head:
///   letters head (alphabet category) or words head (every other category).
/// Same lock rule as before: a class must dominate recent votes at >= 0.85.
class V4SignRecognizer implements SignRecognizer {
  static const int _seqLen = 30;
  static const int _predictEveryN = 5;
  static const int _handsAwayReset = 10;
  static const int _bufferMaxMs = 5000;
  // Live window ~ the typical sign length in training (hand-visible span):
  // letters median 2.7 s, words median 1.6 s (p75 2.2 s).
  static const double lettersWindowS = 2.5;
  static const double wordsWindowS = 1.8;
  static const int _minWindowFrames = 12;
  static const int _stableLockCount = 3;
  static const int _voteWindow = 5;
  static const double _stableLockMinConf = 0.85;
  static const double _minMargin = 0.25;

  final bool letters;
  final List<Interpreter> _interpreters = [];
  List<String> _labels = const [];
  bool _ready = false;

  int _sensorOrientation = 0;
  double _imgW = 0, _imgH = 0; // upright image size
  bool dominantLeft = false;

  final Stopwatch _clock = Stopwatch()..start();
  final List<CanonFrame> _buffer = [];
  final List<int> _voteClass = [];
  final List<double> _voteConf = [];
  int _framesSincePredict = 0;
  int _handsAway = 0;
  bool _locked = false;
  SignPrediction _last = SignPrediction.none;
  List<MapEntry<String, double>> _top3 = const [];
  int lastLatencyMs = 0;
  List<bool> lastPresent = const [false, false];

  V4SignRecognizer({required this.letters});

  String get headName => letters ? 'letters' : 'words';
  double get windowS => letters ? lettersWindowS : wordsWindowS;
  List<MapEntry<String, double>> get top3 => _top3;
  bool get isLocked => _locked;
  @override
  bool get isReady => _ready;

  /// [imageWidth]/[imageHeight] are the CameraImage size (sensor orientation).
  void configureCamera({required int sensorOrientation, int? imageWidth, int? imageHeight}) {
    _sensorOrientation = ((sensorOrientation % 360) + 360) % 360;
    if (imageWidth != null && imageHeight != null) {
      final swap = _sensorOrientation == 90 || _sensorOrientation == 270;
      _imgW = (swap ? imageHeight : imageWidth).toDouble();
      _imgH = (swap ? imageWidth : imageHeight).toDouble();
    }
  }

  bool get hasImageSize => _imgW > 0;

  @override
  Future<void> init() async {
    for (final s in [101, 202, 303]) {
      _interpreters.add(await Interpreter.fromAsset('assets/models/filosign_v4_${headName}_seed$s.tflite'));
    }
    final raw = await rootBundle.loadString('assets/models/labels_v4_$headName.json');
    _labels = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
    _ready = true;
  }

  /// Rotate a sensor-oriented normalized point to the upright image.
  (double, double) _rotateXY(double x, double y) {
    switch (_sensorOrientation) {
      case 90:
        return (1.0 - y, x);
      case 180:
        return (1.0 - x, 1.0 - y);
      case 270:
        return (y, 1.0 - x);
      default:
        return (x, y);
    }
  }

  @override
  SignPrediction addFrame(List<Hand> hands, List<PoseLandmark> pose, List<String> candidates) {
    if (!_ready || _locked || !hasImageSize) return _last;
    if (hands.isEmpty) {
      _handsAway++;
      if (_handsAway >= _handsAwayReset) _clearAttempt();
      return _last;
    }
    _handsAway = 0;

    final rawHands = <List<double>>[
      for (final h in hands.take(2))
        if (h.landmarks.length >= kHandLm)
          [
            for (var j = 0; j < kHandLm; j++) ...() {
              final (x, y) = _rotateXY(h.landmarks[j].x, h.landmarks[j].y);
              return [x, y, h.landmarks[j].z];
            }()
          ]
    ];
    if (rawHands.isEmpty) return _last;
    final rawPose = pose.length >= kPoseLm
        ? [for (var j = 0; j < kPoseLm; j++) ...[pose[j].x, pose[j].y, pose[j].z, pose[j].visibility]]
        : null;
    final frame = canonicalizeFrame(
        RawFrameV4(tMs: _clock.elapsedMilliseconds, hands: rawHands, pose: rawPose),
        _imgW, _imgH, dominantLeft);
    lastPresent = frame.present;
    _buffer.add(frame);
    final cutoff = frame.t - _bufferMaxMs / 1000.0;
    while (_buffer.isNotEmpty && _buffer.first.t < cutoff) {
      _buffer.removeAt(0);
    }

    _framesSincePredict++;
    if (_framesSincePredict >= _predictEveryN) {
      _framesSincePredict = 0;
      _predictAndVote(candidates, frame.t);
    }
    return _last;
  }

  void _predictAndVote(List<String> candidates, double now) {
    final window = [for (final f in _buffer) if (f.t >= now - windowS) f];
    if (window.length < _minWindowFrames) return;
    final sw = Stopwatch()..start();
    final feats = featuresV4(window, letters, length: _seqLen);
    if (feats == null) return;
    final input = [
      [for (final row in feats) row.toList()]
    ];
    final probs = List<double>.filled(_labels.length, 0.0);
    for (final interp in _interpreters) {
      final output = [List<double>.filled(_labels.length, 0.0)];
      interp.run(input, output);
      for (var i = 0; i < probs.length; i++) {
        probs[i] += output[0][i] / _interpreters.length;
      }
    }
    lastLatencyMs = sw.elapsedMilliseconds;

    final allowed = <int>{
      for (final c in candidates)
        if (_labels.contains(c)) _labels.indexOf(c)
    };
    if (allowed.isNotEmpty) {
      for (var i = 0; i < probs.length; i++) {
        if (!allowed.contains(i)) probs[i] = 0.0;
      }
    }
    final sum = probs.fold<double>(0.0, (a, b) => a + b);
    if (sum <= 0) return;
    final disp = [for (final p in probs) p / sum];
    final order = List<int>.generate(disp.length, (i) => i)..sort((a, b) => disp[b].compareTo(disp[a]));
    _top3 = [for (final i in order.take(3)) MapEntry(_labels[i], disp[i])];
    final idx = order.first;
    final conf = disp[idx];
    final second = order.length > 1 ? disp[order[1]] : 0.0;
    _last = SignPrediction(sign: _labels[idx], confidence: conf);
    if (conf - second < _minMargin) return; // ambiguous: show, don't vote

    _voteClass.add(idx);
    _voteConf.add(conf);
    if (_voteClass.length > _voteWindow) {
      _voteClass.removeAt(0);
      _voteConf.removeAt(0);
    }
    // only lock once the buffer covers most of a sign
    if (_buffer.last.t - _buffer.first.t < 0.8 * windowS) return;
    final counts = <int, int>{}, sums = <int, double>{};
    for (var i = 0; i < _voteClass.length; i++) {
      counts[_voteClass[i]] = (counts[_voteClass[i]] ?? 0) + 1;
      sums[_voteClass[i]] = (sums[_voteClass[i]] ?? 0) + _voteConf[i];
    }
    var bestC = -1, bestN = 0;
    counts.forEach((c, n) {
      if (n > bestN) {
        bestN = n;
        bestC = c;
      }
    });
    if (bestC >= 0 && bestN >= _stableLockCount) {
      final mean = sums[bestC]! / bestN;
      if (mean >= _stableLockMinConf) {
        _locked = true;
        _last = SignPrediction(sign: _labels[bestC], confidence: mean);
      }
    }
  }

  void _clearAttempt() {
    _buffer.clear();
    _voteClass.clear();
    _voteConf.clear();
    _framesSincePredict = 0;
    _top3 = const [];
    _last = SignPrediction.none;
  }

  @override
  void reset() {
    _clearAttempt();
    _handsAway = 0;
    _locked = false;
  }

  @override
  void dispose() {
    for (final i in _interpreters) {
      i.close();
    }
    _interpreters.clear();
    _ready = false;
  }
}

