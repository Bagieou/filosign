import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
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
  static const int seqLen = 30;
  /// Debug builds (--dart-define=FILOSIGN_DEBUG_UI=true): log every decision.
  static const bool _log = bool.fromEnvironment('FILOSIGN_DEBUG_UI');
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
  /// Minimum probability the best sign must have among ALL signs (before the
  /// category filter). Random movements spread probability thin.
  static const double _minRawConf = 0.2;
  /// Reject ("not a sign") class name in the label files.
  static const String noneLabel = '__none__';
  /// True when the latest prediction was rejected (show "Not recognized").
  bool notRecognized = false;

  final bool letters;
  final List<Interpreter> _interpreters = [];
  final List<IsolateInterpreter> _isoInterpreters = [];
  /// Shared: the cached models must never run twice at once (IsolateInterpreter
  /// silently skips a run while busy), even across two overlapping screens.
  static bool _predicting = false;
  List<String> _labels = const [];
  bool _ready = false;

  int _sensorOrientation = 0;
  bool _mirrored = false;
  double _imgW = 0, _imgH = 0; // upright image size
  bool dominantLeft = false;

  final Stopwatch _clock = Stopwatch()..start();
  final List<CanonFrame> _buffer = [];
  final List<RawFrameV4> _rawBuffer = [];
  final List<int> _voteClass = [];
  final List<double> _voteConf = [];
  int _framesSincePredict = 0;
  int _handsAway = 0;
  int _attempt = 0;
  final HandSideTracker _sides = HandSideTracker();
  bool _locked = false;
  SignPrediction _last = SignPrediction.none;
  List<MapEntry<String, double>> _top3 = const [];
  int lastLatencyMs = 0;
  List<bool> lastPresent = const [false, false];
  /// Shoulders visible in the latest frame (body location features available).
  bool lastPoseOk = false;
  /// Copy of the previous attempt, kept when the buffer is cleared (e.g. the
  /// hands leave the frame to tap the debug button).
  List<RawFrameV4> _lastAttemptRaw = const [];

  V4SignRecognizer({required this.letters});

  String get headName => letters ? 'letters' : 'words';
  double get windowS => letters ? lettersWindowS : wordsWindowS;
  List<MapEntry<String, double>> get top3 => _top3;
  bool get isLocked => _locked;
  @override
  bool get isReady => _ready;

  /// [imageWidth]/[imageHeight] are the CameraImage size (sensor orientation).
  /// [mirrored]: frames come mirrored like a selfie (iOS front camera); the
  /// landmarks are flipped back so the model sees the real-world view it was
  /// trained on (Android delivers un-mirrored sensor frames).
  void configureCamera({
    required int sensorOrientation,
    int? imageWidth,
    int? imageHeight,
    bool mirrored = false,
  }) {
    _mirrored = mirrored;
    _sensorOrientation = ((sensorOrientation % 360) + 360) % 360;
    if (imageWidth != null && imageHeight != null) {
      final swap = _sensorOrientation == 90 || _sensorOrientation == 270;
      _imgW = (swap ? imageHeight : imageWidth).toDouble();
      _imgH = (swap ? imageWidth : imageHeight).toDouble();
    }
  }

  bool get hasImageSize => _imgW > 0;

  /// Models stay loaded for the whole app session (per head), so opening a
  /// camera screen doesn't reload 3 models + background isolates every time.
  static final Map<String, Future<_HeadModels>> _cache = {};

  static Future<_HeadModels> _models(String head) =>
      _cache[head] ??= _loadModels(head).catchError((Object e) {
        _cache.remove(head);
        throw e;
      });

  static Future<_HeadModels> _loadModels(String head) async {
    final interps = <Interpreter>[], iso = <IsolateInterpreter>[];
    for (final s in [101, 202, 303]) {
      final interp = await Interpreter.fromAsset('assets/models/filosign_v4_${head}_seed$s.tflite');
      interps.add(interp);
      iso.add(await IsolateInterpreter.create(address: interp.address));
    }
    final raw = await rootBundle.loadString('assets/models/labels_v4_$head.json');
    final labels = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
    return _HeadModels(interps, iso, labels);
  }

  /// Load both heads in the background (e.g. after the app starts).
  static Future<void> preload() async {
    try {
      await _models('words');
      await _models('letters');
    } catch (_) {}
  }

  @override
  Future<void> init() async {
    final m = await _models(headName);
    _interpreters.addAll(m.interpreters);
    _isoInterpreters.addAll(m.isolates);
    _labels = m.labels;
    _ready = true;
  }

  /// Rotate a sensor-oriented normalized point to the upright image
  /// (and un-mirror it when the camera delivers mirrored frames).
  (double, double) _rotateXY(double x, double y) {
    final (rx, ry) = switch (_sensorOrientation) {
      90 => (1.0 - y, x),
      180 => (1.0 - x, 1.0 - y),
      270 => (y, 1.0 - x),
      _ => (x, y),
    };
    return _mirrored ? (1.0 - rx, ry) : (rx, ry);
  }

  /// MediaPipe left/right pose landmark pairs (nose 0 has no pair).
  static const List<int> _poseMirror = [
    0, 4, 5, 6, 1, 2, 3, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15, 18, 17, 20, 19,
    22, 21, 24, 23, 26, 25, 28, 27, 30, 29, 32, 31,
  ];

  @override
  SignPrediction addFrame(List<Hand> hands, List<PoseLandmark> pose, List<String> candidates) {
    if (!_ready || _locked || !hasImageSize) return _last;
    if (hands.isEmpty) {
      _handsAway++;
      if (_handsAway == _handsAwayReset) {
        // hands dropped: judge the whole attempt once, the way training saw
        // signs (live windows often hold only part of a sign)
        if (_buffer.length >= _minWindowFrames) {
          _finalDecision(List.of(_buffer), List.of(candidates), _attempt);
        }
        _clearAttempt();
      }
      return _last;
    }
    _handsAway = 0;
    if (_buffer.isEmpty) notRecognized = false; // a new attempt starts

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
    // Pose comes upright from the plugin. On a mirrored frame its "left"
    // points are the person's right ones: flip x back and swap the pairs.
    final rawPose = pose.length >= kPoseLm
        ? [
            for (var j = 0; j < kPoseLm; j++)
              ...() {
                final p = pose[_mirrored ? _poseMirror[j] : j];
                return [_mirrored ? 1.0 - p.x : p.x, p.y, p.z, p.visibility];
              }()
          ]
        : null;
    final raw = RawFrameV4(tMs: _clock.elapsedMilliseconds, hands: rawHands, pose: rawPose);
    final frame = canonicalizeFrame(raw, _imgW, _imgH, dominantLeft, tracker: _sides);
    lastPresent = frame.present;
    lastPoseOk = frame.poseOk;
    _buffer.add(frame);
    _rawBuffer.add(raw);
    final cutoff = frame.t - _bufferMaxMs / 1000.0;
    while (_buffer.isNotEmpty && _buffer.first.t < cutoff) {
      _buffer.removeAt(0);
      _rawBuffer.removeAt(0);
    }

    _framesSincePredict++;
    if (_framesSincePredict >= _predictEveryN) {
      _framesSincePredict = 0;
      _predictAndVote(candidates, frame.t); // async, not awaited
    }
    return _last;
  }

  /// Features + the 3 models run OFF the UI thread (background isolate +
  /// IsolateInterpreter), so the camera preview never freezes. Only one
  /// prediction is in flight at a time; new requests are skipped meanwhile.
  Future<void> _predictAndVote(List<String> candidates, double now) async {
    if (_predicting) return;
    final window = [for (final f in _buffer) if (f.t >= now - windowS) f];
    if (window.length < _minWindowFrames) return;
    _predicting = true;
    try {
      final sw = Stopwatch()..start();
      final out = await _infer(window);
      if (out == null || _locked || !_ready) return;
      lastLatencyMs = sw.elapsedMilliseconds;
      _vote(out.$1, out.$2, candidates);
    } finally {
      _predicting = false;
    }
  }

  /// Averaged probabilities + each model's own, for one window of frames.
  Future<(List<double>, List<List<double>>)?> _infer(List<CanonFrame> window) async {
    final isLetters = letters;
    final input = await Isolate.run(() => _featureInput(window, isLetters));
    final models = [..._isoInterpreters];
    if (input == null || models.isEmpty) return null;
    final probs = List<double>.filled(_labels.length, 0.0);
    final perModel = <List<double>>[];
    for (final interp in models) {
      final output = [List<double>.filled(_labels.length, 0.0)];
      await interp.run(input, output);
      perModel.add(List<double>.of(output[0]));
      for (var i = 0; i < probs.length; i++) {
        probs[i] += output[0][i] / models.length;
      }
    }
    return (probs, perModel);
  }

  /// End of an attempt (hands left the frame) without a live lock: classify
  /// every frame since the hands appeared, like a whole training clip, with
  /// the same strict rule (not __none__, raw >= 0.5, all 3 agree, >= 0.85).
  /// Simulated on held-out clips: words 40% -> 87% correct, wrong ~3%.
  Future<void> _finalDecision(List<CanonFrame> frames, List<String> candidates, int attempt) async {
    while (_predicting) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_locked || !_ready || attempt != _attempt) return;
    _predicting = true;
    try {
      final out = await _infer(frames);
      if (out == null || _locked || !_ready || attempt != _attempt) return;
      final (probs, perModel) = out;
      final noneIdx = _labels.indexOf(noneLabel);
      final allowed = _allowed(candidates, noneIdx);
      final sum = allowed.fold<double>(0.0, (a, i) => a + probs[i]);
      if (sum <= 0) return;
      final j = _judge(probs, perModel, allowed, noneIdx);
      final idx = j.sign;
      final conf = probs[idx] / sum;
      final ok = j.ok && conf >= _stableLockMinConf;
      if (_log) {
        debugPrint('FILOSIGN_FINAL ${_labels[idx]} ${(conf * 100).round()}% '
            'raw ${(probs[idx] * 100).round()}% models ${j.models} '
            'frames ${frames.length} -> ${ok ? "LOCK" : "not recognized"}');
      }
      if (_buffer.isNotEmpty) return; // a new attempt already started
      if (ok) {
        _locked = true;
        notRecognized = false;
        _last = SignPrediction(sign: _labels[idx], confidence: conf);
      } else {
        notRecognized = true;
      }
    } finally {
      _predicting = false;
    }
  }

  /// Is this a sign, and which? Only this screen's signs are compared: a sign
  /// can look like a sign from ANOTHER category (that probability is ignored
  /// - on device "deaf" was 97% within Basics but only 32% over all signs).
  /// Rejected when the model says "not a sign" more than the best sign, the
  /// best sign is weak over all signs, or fewer than 2 of the 3 models pick it
  /// (one model often mixed up look-alikes such as deaf / deaf_blind live).
  /// Together with the 85% lock confidence, on held-out clips: words 90%
  /// correct / 0.6% wrong, fake signs 92% rejected (same as all-3-agree).
  ({int sign, bool ok, String models}) _judge(
      List<double> probs, List<List<double>> perModel, Set<int> allowed, int noneIdx) {
    final signs = [for (final i in allowed) if (i != noneIdx) i];
    if (signs.isEmpty) return (sign: noneIdx, ok: false, models: '');
    int best(List<double> p) => signs.reduce((a, b) => p[b] > p[a] ? b : a);
    final idx = best(probs);
    final picks = [for (final p in perModel) best(p)];
    final noneP = noneIdx >= 0 ? probs[noneIdx] : 0.0;
    final ok = noneP < probs[idx] &&
        probs[idx] >= _minRawConf &&
        picks.where((i) => i == idx).length >= 2;
    return (sign: ok || noneP < probs[idx] ? idx : noneIdx, ok: ok,
        models: picks.map((i) => _labels[i]).join('/'));
  }

  Set<int> _allowed(List<String> candidates, int noneIdx) {
    final allowed = <int>{
      for (final c in candidates)
        if (_labels.contains(c)) _labels.indexOf(c)
    };
    if (allowed.isEmpty) allowed.addAll(List<int>.generate(_labels.length, (i) => i));
    if (noneIdx >= 0) allowed.add(noneIdx);
    return allowed;
  }

  /// Not a sign: the model's reject class, a weak raw score, or the three
  /// models disagreeing. Clears pending votes, so a half-done or random
  /// movement can never add up to a lock. "Not recognized" itself is only
  /// shown by [_finalDecision]: mid-sign windows often look like a partial sign.
  void _reject(double conf) {
    _last = SignPrediction(sign: null, confidence: conf);
    _voteClass.clear();
    _voteConf.clear();
  }

  void _vote(List<double> probs, List<List<double>> perModel, List<String> candidates) {
    final noneIdx = _labels.indexOf(noneLabel);
    final allowed = _allowed(candidates, noneIdx);

    final masked = [for (var i = 0; i < probs.length; i++) allowed.contains(i) ? probs[i] : 0.0];
    final sum = masked.fold<double>(0.0, (a, b) => a + b);
    if (sum <= 0) return;
    final disp = [for (final p in masked) p / sum];
    final order = List<int>.generate(disp.length, (i) => i)..sort((a, b) => disp[b].compareTo(disp[a]));
    _top3 = [for (final i in order.take(3)) MapEntry(_labels[i], disp[i])];

    final j = _judge(probs, perModel, allowed, noneIdx);
    final idx = j.sign;
    final conf = disp[idx];
    final rest = order.where((i) => i != idx);
    final second = rest.isEmpty ? 0.0 : disp[rest.first];
    if (_log) {
      final cover = _buffer.last.t - _buffer.first.t;
      debugPrint('FILOSIGN_VOTE ${_labels[idx]} ${(conf * 100).round()}% '
          'raw ${(probs[idx] * 100).round()}% '
          'none ${noneIdx >= 0 ? (probs[noneIdx] * 100).round() : -1}% '
          'models ${j.models} ok ${j.ok} '
          'margin ${((conf - second) * 100).round()} cover ${cover.toStringAsFixed(1)}s '
          'votes ${_voteClass.map((i) => _labels[i]).join(",")}');
    }
    if (!j.ok) {
      _reject(conf);
      return;
    }
    notRecognized = false;
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

  /// Debug capture: the last few seconds exactly as the recognizer saw them
  /// (upright landmarks before canonicalization), plus camera settings and
  /// the current guesses. Replayed offline by src/replay_debug_v4.py.
  Map<String, dynamic> debugSnapshot({String? expected, List<String>? candidates}) => {
        'version': 1,
        'head': headName,
        'expected': expected,
        'candidates': candidates,
        'width': _imgW,
        'height': _imgH,
        'sensor_orientation': _sensorOrientation,
        'dominant_left': dominantLeft,
        'window_s': windowS,
        'top3': [for (final e in _top3) [e.key, e.value]],
        'locked': _locked,
        'frames': [
          for (final f in (_rawBuffer.length >= _lastAttemptRaw.length ? _rawBuffer : _lastAttemptRaw))
            {'t_ms': f.tMs, 'hands': f.hands, 'pose': f.pose}
        ],
      };

  void _clearAttempt() {
    if (_rawBuffer.length >= 5) _lastAttemptRaw = List.of(_rawBuffer);
    _rawBuffer.clear();
    _buffer.clear();
    _voteClass.clear();
    _voteConf.clear();
    _framesSincePredict = 0;
    _top3 = const [];
    _last = SignPrediction.none;
    notRecognized = false;
    _sides.reset();
  }

  @override
  void reset() {
    _attempt++; // drops a pending end-of-attempt decision
    _clearAttempt();
    _handsAway = 0;
    _locked = false;
  }

  @override
  void dispose() {
    // the models are shared and cached (see [_cache]); just stop using them
    _ready = false;
    _attempt++;
    _isoInterpreters.clear();
    _interpreters.clear();
  }
}

class _HeadModels {
  final List<Interpreter> interpreters;
  final List<IsolateInterpreter> isolates;
  final List<String> labels;
  _HeadModels(this.interpreters, this.isolates, this.labels);
}

/// Runs in a background isolate: canonical frames -> model input [1][30][F].
List<List<List<double>>>? _featureInput(List<CanonFrame> window, bool letters) {
  final feats = featuresV4(window, letters, length: V4SignRecognizer.seqLen);
  if (feats == null) return null;
  return [
    [for (final row in feats) row.toList()]
  ];
}

