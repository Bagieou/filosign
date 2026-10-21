import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../test_build.dart';
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
  static const bool _log = bool.fromEnvironment('FILOSIGN_DEBUG_UI') || kTestBuild;
  /// TEST builds: receives every finished attempt (raw landmarks + every
  /// decision) so it can be saved on the phone and replayed offline.
  static void Function(Map<String, dynamic> attempt)? attemptSink;
  /// Sign the screen asks for (lesson / quiz), saved with each attempt.
  String? expected;
  final List<String> _events = [];
  List<String> _candidates = const [];

  void _event(String line) {
    if (_log) debugPrint(line);
    if (attemptSink != null) _events.add('${_clock.elapsedMilliseconds} $line');
  }

  void _emitAttempt(List<RawFrameV4> raw, List<String> events, String result) {
    final sink = attemptSink;
    if (sink == null || raw.length < 5) return;
    sink({
      'version': 1,
      'head': headName,
      'expected': expected,
      'candidates': _candidates,
      'width': _imgW,
      'height': _imgH,
      'sensor_orientation': _sensorOrientation,
      'mirrored': _mirrored,
      'dominant_left': dominantLeft,
      'window_s': windowS,
      'result': result,
      'events': List.of(events),
      'frames': [
        for (final f in raw) {'t_ms': f.tMs, 'hands': f.hands, 'pose': f.pose}
      ],
    });
  }
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
  /// Word signs are judged ONCE, on the whole attempt, when the hands drop
  /// (or after [_maxAttemptS] with the hands still up) - never mid-sign.
  /// Replayed on held-out clips + 50 on-device attempts (src/tune_live_v4.py):
  /// live lock 89.2% correct / 3.4% wrong (on-device 44%); whole attempt at
  /// 70%: 91.5% / 0.8% (on-device 50%). Letters keep the live lock (91%).
  bool get _endOnly => !letters;
  static const double _endLockWords = 0.70;
  static const double _maxAttemptS = 4.5;
  /// "Sign, then hold still" also ends a word sign: people taught by the old
  /// live lock hold the sign instead of lowering the hands (teammate captures,
  /// 2026-10-21: hands still up at the end of all 13). The signing (higher)
  /// hand holding < 0.6 hand-sizes/s for 0.5 s (signing: median 1.7), after
  /// moving > 1.5, >= 1 s into the attempt, judges the whole attempt at 85%
  /// (a hold can be a pause mid-sign); a miss there is silent. Replayed
  /// (src/hold_sim_v4.py): held-out 91.3% correct / 1.7% wrong (drop only
  /// 91.5 / 0.8; old live lock 89.2 / 3.4).
  static const double _stillSpeed = 0.6, _movedSpeed = 1.5, _holdS = 0.5, _holdMinS = 1.0;
  static const double _holdLock = 0.85;
  final List<(double, double)> _speeds = []; // (t, hand-sizes/s)
  (double, double, double)? _prevHand; // centre x, y, t
  double _peakSpeed = 0;
  bool _holdArmed = true;
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
  /// Words only: models trained without body dropout (location-aware).
  final List<IsolateInterpreter> _bodyIso = [];
  /// Which word models judged the latest attempt (for the log).
  String _lastSet = '';
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
    // Words: a second set trained WITHOUT body dropout (2026-10-14), used
    // when the body is visible - see [_infer].
    final bodyInterps = <Interpreter>[], bodyIso = <IsolateInterpreter>[];
    if (head == 'words') {
      for (final s in [101, 202, 303]) {
        final interp = await Interpreter.fromAsset('assets/models/filosign_v4_words_body_seed$s.tflite');
        bodyInterps.add(interp);
        bodyIso.add(await IsolateInterpreter.create(address: interp.address));
      }
    }
    final raw = await rootBundle.loadString('assets/models/labels_v4_$head.json');
    final labels = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
    return _HeadModels(interps, iso, labels, bodyInterps, bodyIso);
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
    _bodyIso.addAll(m.bodyIsolates);
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
    _candidates = candidates;
    if (hands.isEmpty) {
      _prevHand = null;
      _handsAway++;
      if (_handsAway == _handsAwayReset) {
        // hands dropped: judge the whole attempt once, the way training saw
        // signs (live windows often hold only part of a sign)
        if (_buffer.length >= _minWindowFrames) {
          _finalDecision(List.of(_buffer), List.of(candidates), _attempt,
              List.of(_rawBuffer), List.of(_events));
        } else {
          _emitAttempt(_rawBuffer, _events, 'too_short');
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

    if (_endOnly && frame.t - _buffer.first.t >= _maxAttemptS) {
      // hands kept up: judge what was signed, then start a new attempt
      _finalDecision(List.of(_buffer), List.of(candidates), _attempt,
          List.of(_rawBuffer), List.of(_events));
      _clearAttempt();
      return _last;
    }
    if (_endOnly) _checkHold(rawHands, frame.t, candidates);

    _framesSincePredict++;
    if (_framesSincePredict >= _predictEveryN) {
      _framesSincePredict = 0;
      _predictAndVote(candidates, frame.t); // async, not awaited
    }
    return _last;
  }

  /// Hold-still trigger for word signs (see [_holdLock]). Speed of the higher
  /// hand's centre in hand sizes (wrist -> middle knuckle) per second, in
  /// isotropic image units - same as src/hold_sim_v4.py.
  void _checkHold(List<List<double>> hands, double t, List<String> candidates) {
    final s = math.max(_imgW, _imgH);
    final sx = _imgW / s, sy = _imgH / s;
    var h = hands.first;
    for (final o in hands) {
      if (o[1] < h[1]) h = o; // smaller wrist y = higher hand
    }
    final size = math.max(
        math.sqrt(math.pow((h[27] - h[0]) * sx, 2) + math.pow((h[28] - h[1]) * sy, 2)), 1e-3);
    var cx = 0.0, cy = 0.0;
    for (var j = 0; j < kHandLm; j++) {
      cx += h[j * 3] * sx;
      cy += h[j * 3 + 1] * sy;
    }
    cx /= kHandLm;
    cy /= kHandLm;
    final prev = _prevHand;
    _prevHand = (cx, cy, t);
    if (prev == null || t <= prev.$3) return;
    final sp = math.sqrt(math.pow(cx - prev.$1, 2) + math.pow(cy - prev.$2, 2)) / size / (t - prev.$3);
    _speeds.add((t, sp));
    final first = _speeds.first.$1;
    while (_speeds.isNotEmpty && _speeds.first.$1 < t - 1.0) {
      _speeds.removeAt(0);
    }
    if (sp > _movedSpeed) {
      _peakSpeed = math.max(_peakSpeed, sp);
      _holdArmed = true; // moving again: the next hold is judged again
    }
    if (!_holdArmed || _peakSpeed <= _movedSpeed || _buffer.isEmpty) return;
    if (t - _buffer.first.t < _holdMinS || first > t - _holdS) return;
    final recent = [for (final e in _speeds) if (e.$1 >= t - _holdS) e.$2];
    if (recent.length < 5) return;
    if (recent.where((v) => v < _stillSpeed).length < 0.8 * recent.length) return;
    _holdArmed = false;
    _event('FILOSIGN_HOLD at ${(t - _buffer.first.t).toStringAsFixed(1)}s');
    _finalDecision(List.of(_buffer), List.of(candidates), _attempt, const [], _events,
        _holdLock);
  }

  /// Cascade, off the UI thread (background isolate + IsolateInterpreter):
  /// while signing only model 1 of 3 runs; when its votes would lock, models
  /// 2 and 3 judge the same window and the lock needs 2 of 3 to agree at 85%.
  /// Simulated on held-out clips (src/compare_ensemble_v4.py): words 89.2%
  /// correct / 3.0% wrong with 40% of the model runs of always-3 (88.6% /
  /// 4.2%); one model alone locked 6-8.5% wrong. One prediction at a time.
  Future<void> _predictAndVote(List<String> candidates, double now) async {
    if (_predicting) return;
    // Word signs: no mid-sign decision; the TEST build still runs model 1
    // for the Top-3 panel and the attempt log.
    if (_endOnly && !_log) return;
    final window = [for (final f in _buffer) if (f.t >= now - windowS) f];
    if (window.length < _minWindowFrames) return;
    _predicting = true;
    try {
      final sw = Stopwatch()..start();
      final input = await _input(window);
      if (input == null || _locked || !_ready) return;
      final first = await _run(input, const [0]);
      if (first == null || _locked || !_ready) return;
      final lockAt = _vote(first.$1, first.$2, candidates);
      if (_endOnly) {
        _last = SignPrediction.none; // nothing shown until the hands drop
        return;
      }
      if (lockAt != null) {
        final rest = await _run(input, const [1, 2]);
        if (rest == null || _locked || !_ready) return;
        _confirmLock(lockAt, [...first.$2, ...rest.$2], candidates);
      }
      lastLatencyMs = sw.elapsedMilliseconds;
    } finally {
      _predicting = false;
    }
  }

  /// Model input for one window of frames (features computed in an isolate).
  Future<List<List<List<double>>>?> _input(List<CanonFrame> window) {
    final isLetters = letters;
    return Isolate.run(() => _featureInput(window, isLetters));
  }

  /// Averaged probabilities + each model's own, for the models in [which].
  Future<(List<double>, List<List<double>>)?> _run(
      List<List<List<double>>> input, List<int> which, {bool body = false}) async {
    final set = body ? _bodyIso : _isoInterpreters;
    final models = [for (final i in which) if (i < set.length) set[i]];
    if (models.isEmpty) return null;
    final perModel = <List<double>>[];
    for (final interp in models) {
      final output = [List<double>.filled(_labels.length, 0.0)];
      await interp.run(input, output);
      perModel.add(List<double>.of(output[0]));
    }
    return (_mean(perModel), perModel);
  }

  List<double> _mean(List<List<double>> perModel) {
    final probs = List<double>.filled(_labels.length, 0.0);
    for (final p in perModel) {
      for (var i = 0; i < probs.length; i++) {
        probs[i] += p[i] / perModel.length;
      }
    }
    return probs;
  }

  /// All 3 models on a whole attempt (the end-of-sign decision).
  /// Word signs with the body (face + shoulders) in view on at least half the
  /// frames use the models trained WITHOUT body dropout: the dropout models
  /// (needed when the body is out of view) mostly ignore WHERE the hand is -
  /// a teammate's grandmother (chin) read as grandfather (forehead) at 98%.
  /// Replayed (src/compare_sets_v4.py): hand moved chin <-> forehead,
  /// right answer 6% -> 56%; held-out with body 91.1% / 1.9% wrong, without
  /// body unchanged (90.9% / 1.7%); teammate captures 0/20 -> 3/20.
  Future<(List<double>, List<List<double>>)?> _infer(List<CanonFrame> window) async {
    final input = await _input(window);
    if (input == null) return null;
    final withBody = window.where((f) => f.poseOk).length >= 0.5 * window.length;
    final body = _bodyIso.length == 3 && withBody;
    _lastSet = body ? 'body' : 'dropout';
    return _run(input, const [0, 1, 2], body: body);
  }

  /// The 3-model check behind a live lock: same rule as the end of a sign.
  void _confirmLock(int cls, List<List<double>> perModel, List<String> candidates) {
    final probs = _mean(perModel);
    final noneIdx = _labels.indexOf(noneLabel);
    final allowed = _allowed(candidates, noneIdx);
    final sum = allowed.fold<double>(0.0, (a, i) => a + probs[i]);
    if (sum <= 0) return;
    final j = _judge(probs, perModel, allowed, noneIdx);
    final conf = probs[j.sign] / sum;
    final ok = j.ok && j.sign == cls && conf >= _stableLockMinConf;
    if (_log) {
      _event('FILOSIGN_CONFIRM ${_labels[cls]} -> ${j.models} ${(conf * 100).round()}% '
          '${ok ? "LOCK" : "rejected"}');
    }
    if (ok) {
      _locked = true;
      _last = SignPrediction(sign: _labels[cls], confidence: conf);
    } else {
      _voteClass.clear(); // the other models disagree: start the votes over
      _voteConf.clear();
    }
  }

  /// End of an attempt (hands left the frame) without a live lock: classify
  /// every frame since the hands appeared, like a whole training clip, with
  /// all 3 models and the same rule as a live lock ([_judge] + 85%).
  /// Simulated on held-out clips: words 40% -> 87% correct, wrong ~3%.
  Future<void> _finalDecision(List<CanonFrame> frames, List<String> candidates, int attempt,
      [List<RawFrameV4> raw = const [], List<String> events = const [], double? lock]) async {
    var result = 'final_skipped';
    try {
      await _finalDecisionRun(frames, candidates, attempt, events, (r) => result = r, lock);
    } finally {
      _emitAttempt(raw, events, result);
    }
  }

  Future<void> _finalDecisionRun(List<CanonFrame> frames, List<String> candidates, int attempt,
      List<String> events, void Function(String) setResult, [double? lock]) async {
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
      final ok = j.ok && conf >= (lock ?? (_endOnly ? _endLockWords : _stableLockMinConf));
      if (_log) {
        final line = 'FILOSIGN_FINAL ${_labels[idx]} ${(conf * 100).round()}% '
            'raw ${(probs[idx] * 100).round()}% models ${j.models} '
            'frames ${frames.length} set $_lastSet -> ${ok ? "LOCK" : "not recognized"}';
        debugPrint(line);
        events.add('${_clock.elapsedMilliseconds} $line');
      }
      setResult(ok ? 'final_lock:${_labels[idx]}' : 'final_rejected:${_labels[idx]}');
      // A new attempt already started (hands back up, or kept up past
      // _maxAttemptS): a match still counts, a miss is not shown over it.
      if (_buffer.isNotEmpty && !ok) return;
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
        picks.where((i) => i == idx).length >= math.min(2, picks.length);
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

  /// Live vote on one window. Returns the sign whose votes would lock (to be
  /// confirmed by all 3 models), or null.
  int? _vote(List<double> probs, List<List<double>> perModel, List<String> candidates) {
    final noneIdx = _labels.indexOf(noneLabel);
    final allowed = _allowed(candidates, noneIdx);

    final masked = [for (var i = 0; i < probs.length; i++) allowed.contains(i) ? probs[i] : 0.0];
    final sum = masked.fold<double>(0.0, (a, b) => a + b);
    if (sum <= 0) return null;
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
      _event('FILOSIGN_VOTE ${_labels[idx]} ${(conf * 100).round()}% '
          'raw ${(probs[idx] * 100).round()}% '
          'none ${noneIdx >= 0 ? (probs[noneIdx] * 100).round() : -1}% '
          'models ${j.models} ok ${j.ok} '
          'margin ${((conf - second) * 100).round()} cover ${cover.toStringAsFixed(1)}s '
          'votes ${_voteClass.map((i) => _labels[i]).join(",")}');
    }
    if (!j.ok) {
      _reject(conf);
      return null;
    }
    notRecognized = false;
    _last = SignPrediction(sign: _labels[idx], confidence: conf);
    if (conf - second < _minMargin) return null; // ambiguous: show, don't vote

    _voteClass.add(idx);
    _voteConf.add(conf);
    if (_voteClass.length > _voteWindow) {
      _voteClass.removeAt(0);
      _voteConf.removeAt(0);
    }
    // only lock once the buffer covers most of a sign
    if (_buffer.last.t - _buffer.first.t < 0.8 * windowS) return null;
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
      if (mean >= _stableLockMinConf) return bestC;
    }
    return null;
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
    _events.clear();
    _buffer.clear();
    _speeds.clear();
    _prevHand = null;
    _peakSpeed = 0;
    _holdArmed = true;
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
    if (_rawBuffer.isNotEmpty) {
      _emitAttempt(List.of(_rawBuffer), List.of(_events),
          _locked ? 'live_lock:${_last.sign}' : 'reset');
    }
    _attempt++; // drops a pending end-of-attempt decision
    _clearAttempt();
    _handsAway = 0;
    _locked = false;
  }

  @override
  void dispose() {
    if (_rawBuffer.isNotEmpty) {
      _emitAttempt(List.of(_rawBuffer), List.of(_events),
          _locked ? 'live_lock:${_last.sign}' : 'closed');
    }
    // the models are shared and cached (see [_cache]); just stop using them
    _ready = false;
    _attempt++;
    _isoInterpreters.clear();
    _bodyIso.clear();
    _interpreters.clear();
  }
}

class _HeadModels {
  final List<Interpreter> interpreters;
  final List<IsolateInterpreter> isolates;
  final List<String> labels;
  final List<Interpreter> bodyInterpreters;
  final List<IsolateInterpreter> bodyIsolates;
  _HeadModels(this.interpreters, this.isolates, this.labels,
      [this.bodyInterpreters = const [], this.bodyIsolates = const []]);
}

/// Runs in a background isolate: canonical frames -> model input [1][30][F].
List<List<List<double>>>? _featureInput(List<CanonFrame> window, bool letters) {
  final feats = featuresV4(window, letters, length: V4SignRecognizer.seqLen);
  if (feats == null) return null;
  return [
    [for (final row in feats) row.toList()]
  ];
}

