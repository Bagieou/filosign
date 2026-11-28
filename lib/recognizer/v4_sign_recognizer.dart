import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data' show Float32List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../test_build.dart';
import 'sign_recognizer.dart';
import 'v4/canonical_v4.dart';
import 'v4/hold_detector.dart';
import 'v4/features_v4.dart';

class V4SignRecognizer implements SignRecognizer {
  static const int seqLen = 30;
  static const bool _log = bool.fromEnvironment('FILOSIGN_DEBUG_UI') || kTestBuild;
  static void Function(Map<String, dynamic> attempt)? attemptSink;
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
  static const int _handsAwayMs = 700;
  static final bool _ios = Platform.isIOS;
  static int get _awayMs => _ios ? 1000 : _handsAwayMs;
  static int get _minFinalFrames => _ios ? 6 : _minWindowFrames;
  int? _awaySinceMs;
  bool _awayFired = false;
  static const int _bufferMaxMs = 5000;
  static const double lettersWindowS = 2.5;
  static const double wordsWindowS = 1.8;
  static const int _minWindowFrames = 12;
  static const int _stableLockCount = 3;
  static const int _voteWindow = 5;
  static const double _stableLockMinConf = 0.85;
  bool get _endOnly => !letters;
  static const double _endLockWords = 0.70;
  static const double _maxAttemptS = 4.5;
  static const double _holdLock = 0.85;
  final HoldDetector _hold = HoldDetector();
  static const double _minMargin = 0.25;
  static const double _minRawConf = 0.2;
  static const String noneLabel = '__none__';
  bool notRecognized = false;

  final bool letters;
  final List<Interpreter> _interpreters = [];
  final List<IsolateInterpreter> _isoInterpreters = [];
  final List<IsolateInterpreter> _bodyIso = [];
  String _lastSet = '';
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
  int _attempt = 0;
  final HandSideTracker _sides = HandSideTracker();
  bool _locked = false;
  SignPrediction _last = SignPrediction.none;
  List<MapEntry<String, double>> _top3 = const [];
  int lastLatencyMs = 0;
  List<bool> lastPresent = const [false, false];
  bool lastPoseOk = false;
  List<RawFrameV4> _lastAttemptRaw = const [];

  V4SignRecognizer({required this.letters});

  String get headName => letters ? 'letters' : 'words';
  double get windowS => letters ? lettersWindowS : wordsWindowS;
  List<MapEntry<String, double>> get top3 => _top3;
  bool get isLocked => _locked;
  @override
  bool get isReady => _ready;

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

  (double, double) _rotateXY(double x, double y) {
    final (rx, ry) = switch (_sensorOrientation) {
      90 => (1.0 - y, x),
      180 => (1.0 - x, 1.0 - y),
      270 => (y, 1.0 - x),
      _ => (x, y),
    };
    return _mirrored ? (1.0 - rx, ry) : (rx, ry);
  }

  static const List<int> _poseMirror = [
    0, 4, 5, 6, 1, 2, 3, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15, 18, 17, 20, 19,
    22, 21, 24, 23, 26, 25, 28, 27, 30, 29, 32, 31,
  ];

  @override
  SignPrediction addFrame(List<Hand> hands, List<PoseLandmark> pose, List<String> candidates) {
    if (!_ready || _locked || !hasImageSize) return _last;
    _candidates = candidates;
    if (hands.isEmpty) {
      _hold.handsLost();
      final now = _clock.elapsedMilliseconds;
      _awaySinceMs ??= now;
      if (!_awayFired && now - _awaySinceMs! >= _awayMs) {
        _awayFired = true;
        if (_buffer.length >= _minFinalFrames) {
          _finalDecision(List.of(_buffer), List.of(candidates), _attempt,
              List.of(_rawBuffer), List.of(_events));
        } else {
          _emitAttempt(_rawBuffer, _events, 'too_short');
          if (_ios && _buffer.length >= 3) notRecognized = true;
        }
        _clearAttempt();
      }
      return _last;
    }
    _awaySinceMs = null;
    _awayFired = false;
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
      _finalDecision(List.of(_buffer), List.of(candidates), _attempt,
          List.of(_rawBuffer), List.of(_events), null, _ios);
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

  void _checkHold(List<List<double>> hands, double t, List<String> candidates) {
    final s = math.max(_imgW, _imgH);
    var h = hands.first;
    for (final o in hands) {
      if (o[1] < h[1]) h = o; // smaller wrist y = higher hand
    }
    if (!_hold.add(h, t, _imgW / s, _imgH / s) || _buffer.isEmpty) return;
    _event('FILOSIGN_HOLD at ${(t - _buffer.first.t).toStringAsFixed(1)}s');
    _finalDecision(List.of(_buffer), List.of(candidates), _attempt, const [], _events,
        _holdLock);
  }

  Future<void> _predictAndVote(List<String> candidates, double now) async {
    if (_predicting) return;
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

  Future<List<List<List<double>>>?> _input(List<CanonFrame> window) {
    final isLetters = letters;
    return Isolate.run(() => _featureInput(window, isLetters));
  }

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

  Future<(List<double>, List<List<double>>)?> _infer(List<CanonFrame> window) async {
    if (_ios && !letters) window = [for (final f in window) _withoutBody(f)];
    final input = await _input(window);
    if (input == null) return null;
    final withBody = window.where((f) => f.poseOk).length >= 0.5 * window.length;
    final numbers = _candidates.contains('nine') && _candidates.contains('five');
    final months = _candidates.contains('april') && _candidates.contains('august');
    final body = _bodyIso.length == 3 && withBody && !numbers && !months;
    _lastSet = body ? 'body' : 'dropout';
    return _run(input, const [0, 1, 2], body: body);
  }

  static CanonFrame _withoutBody(CanonFrame f) => CanonFrame(
      f.t, f.hands, f.present, Float32List(kPoseLm * 3), Float32List(kPoseLm), false);

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

  Future<void> _finalDecision(List<CanonFrame> frames, List<String> candidates, int attempt,
      [List<RawFrameV4> raw = const [], List<String> events = const [], double? lock,
      bool feedback = false]) async {
    var result = 'final_skipped';
    try {
      await _finalDecisionRun(frames, candidates, attempt, events, (r) => result = r, lock, feedback);
    } finally {
      _emitAttempt(raw, events, result);
    }
  }

  Future<void> _finalDecisionRun(List<CanonFrame> frames, List<String> candidates, int attempt,
      List<String> events, void Function(String) setResult, [double? lock, bool feedback = false]) async {
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
      if (_buffer.isNotEmpty && !ok && !feedback) return;
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

  void _reject(double conf) {
    _last = SignPrediction(sign: null, confidence: conf);
    _voteClass.clear();
    _voteConf.clear();
  }

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
    _hold.reset();
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
    _awaySinceMs = null;
    _awayFired = false;
    _locked = false;
  }

  @override
  void dispose() {
    if (_rawBuffer.isNotEmpty) {
      _emitAttempt(List.of(_rawBuffer), List.of(_events),
          _locked ? 'live_lock:${_last.sign}' : 'closed');
    }
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

List<List<List<double>>>? _featureInput(List<CanonFrame> window, bool letters) {
  final feats = featuresV4(window, letters, length: V4SignRecognizer.seqLen);
  if (feats == null) return null;
  return [
    [for (final row in feats) row.toList()]
  ];
}

