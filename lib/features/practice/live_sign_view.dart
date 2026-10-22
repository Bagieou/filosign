import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FrameTiming;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_settings.dart' show InactivityGuard;
import '../../recognizer/sign_recognizer.dart';
import '../../test_build.dart';
import '../../recognizer/v4_sign_recognizer.dart';

/// Developer overlays (top-3, hand count, debug capture button).
/// Off in normal builds; turn on with
/// `flutter build apk --dart-define=FILOSIGN_DEBUG_UI=true`.
/// The team test version (kTestBuild) shows them too, for reporting.
const bool kShowDebugUi = bool.fromEnvironment('FILOSIGN_DEBUG_UI') || kTestBuild;

/// Live sign checking runs MediaPipe Hands natively: Android (JNI plugin) and
/// iOS (MediaPipeTasksVision, packages/hand_landmarker/ios). Anywhere else
/// the screens show a notice, offer Skip, and keep the quiz to video questions.
final bool kLiveSignSupported = Platform.isAndroid || Platform.isIOS;

/// Debug builds only: camera / hand-result rates and UI frame cost, shown in
/// the Top-3 panel and logged as "FILOSIGN_PERF" (adb logcat) every 2 s.
class _PerfMeter {
  int camera = 0, hands = 0, frames = 0, slow = 0, pose = 0;
  int buildUs = 0, rasterUs = 0, camCbUs = 0, handCbUs = 0;
  int _since = DateTime.now().millisecondsSinceEpoch;
  String text = '';

  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds, r = t.rasterDuration.inMicroseconds;
      frames++;
      buildUs += b;
      rasterUs += r;
      if (b > 16667 || r > 16667) slow++;
    }
  }

  void tick(int inferMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = (now - _since) / 1000.0;
    if (s < 2) return;
    String ms(int us, int n) => n == 0 ? '0' : (us / n / 1000).toStringAsFixed(1);
    text = 'cam ${(camera / s).round()}/s · hands ${(hands / s).round()}/s · pose ${(pose / s).round()}/s · '
        'ui ${(frames / s).round()}fps build ${ms(buildUs, frames)} raster ${ms(rasterUs, frames)}ms '
        'slow $slow · camCb ${ms(camCbUs, camera)} handCb ${ms(handCbUs, hands)}ms · model ${inferMs}ms'
        '${Platform.isAndroid ? ' · yuv ${HandLandmarkerPlugin.lastConvertMs.toStringAsFixed(0)}ms '
            'hand ${HandLandmarkerPlugin.lastLatencyMs.toStringAsFixed(0)}ms' : ''}';
    debugPrint('FILOSIGN_PERF $text');
    camera = hands = frames = slow = pose = buildUs = rasterUs = camCbUs = handCbUs = 0;
    _since = now;
  }
}

/// One hand landmarker + one pose detector for the whole app session.
/// Creating the hand landmarker loads its model on the GPU on the calling
/// (UI) thread - a 1-2 s freeze that made every screen transition stutter -
/// and the plugin shares one event channel between instances, so a second
/// instance's dispose killed the first one's stream. Now: created once, kept,
/// and its results fanned out to whichever camera view is open.
class _SharedDetectors {
  static HandLandmarkerPlugin? _android;
  static const MethodChannel _ios = MethodChannel('filosign/hands_ios');
  static Future<void>? _iosInit;
  static bool _iosBusy = false;
  static bool _started = false;
  static final StreamController<List<Hand>> _results = StreamController.broadcast();
  static final NpuPoseDetector pose = NpuPoseDetector(config: PoseDetectorConfig.realtime());
  static Future<void>? _poseInit;

  /// Creates the hand detector on first use (Android: blocking GPU load).
  static void start() {
    if (_started) return;
    if (Platform.isIOS) {
      _iosInit = _ios.invokeMethod<void>('initialize');
    } else {
      // GPU first: measured on a Reno 10, GPU 33 ms / 22 results per second
      // vs CPU 73-97 ms / 16. Phones whose GPU can't run it fall back to the
      // CPU instead of failing ("Hand detection could not start").
      HandLandmarkerPlugin created;
      try {
        created = HandLandmarkerPlugin.create(
          numHands: 2,
          minHandDetectionConfidence: 0.5,
          delegate: HandLandmarkerDelegate.gpu,
        );
      } catch (_) {
        created = HandLandmarkerPlugin.create(
          numHands: 2,
          minHandDetectionConfidence: 0.5,
          delegate: HandLandmarkerDelegate.cpu,
        );
      }
      created.landmarkStream.listen(_results.add, onError: (_) {});
      _android = created;
    }
    _started = true;
  }

  static Stream<List<Hand>> get results => _results.stream;

  /// Last native hand-detection failure (null while results are good).
  static String? _iosError;
  static String? get lastError =>
      Platform.isIOS ? _iosError : HandLandmarkerPlugin.lastError;

  /// Cheap on the UI thread: Android converts + detects on a native worker;
  /// iOS sends the BGRA frame and skips frames while one is in flight.
  static void processFrame(CameraImage image, int orientation) {
    if (Platform.isIOS) {
      _processIos(image);
    } else {
      _android?.processFrame(image, orientation);
    }
  }

  static Future<void> _processIos(CameraImage image) async {
    if (_iosBusy) return;
    _iosBusy = true;
    try {
      await _iosInit;
      final p = image.planes.first;
      final res = await _ios.invokeMethod<List<Object?>>('process', {
        'bytes': p.bytes,
        'width': image.width,
        'height': image.height,
        'bytesPerRow': p.bytesPerRow,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      _iosError = null;
      _results.add([
        for (final h in res ?? const <Object?>[])
          Hand([
            for (var i = 0; i + 2 < (h as List).length; i += 3)
              Landmark((h[i] as num).toDouble(), (h[i + 1] as num).toDouble(),
                  (h[i + 2] as num).toDouble()),
          ]),
      ]);
    } catch (e) {
      _iosError = '$e';
      _results.add(const []); // keeps the error check + watchdog running
      if (kShowDebugUi) debugPrint('FILOSIGN_IOS_HANDS $e');
    } finally {
      _iosBusy = false;
    }
  }

  static Future<void> initPose() =>
      _poseInit ??= pose.initialize().catchError((Object e) {
        _poseInit = null;
        throw e;
      });
}

/// Snapshot of the live recognizer, sent to the parent after every frame.
class LiveSignState {
  final SignPrediction prediction;
  final bool locked;
  final List<MapEntry<String, double>> top3;
  final int handCount;
  final String head;
  final int latencyMs;
  final List<bool> present;
  final bool notRecognized;
  final bool bodyVisible;
  /// Debug builds: performance readout (see [_PerfMeter]).
  final String perf;
  const LiveSignState({
    required this.prediction,
    required this.locked,
    required this.top3,
    required this.handCount,
    required this.head,
    required this.latencyMs,
    required this.present,
    this.notRecognized = false,
    this.bodyVisible = true,
    this.perf = '',
  });
}

/// Front camera + MediaPipe Hands + Pose + v4 recognizer, with the hand
/// skeleton drawn on the preview. Used by live practice and the quiz.
/// Change [resetToken] (or [dominantLeft]) to start a fresh attempt.
class LiveSignView extends StatefulWidget {
  final List<String> candidates; // model labels allowed for this screen
  final bool letters; // letters head (alphabet) or words head
  final bool dominantLeft;
  final int resetToken;
  final ValueChanged<LiveSignState>? onUpdate;
  final bool active; // false = stop processing frames (camera stays open)
  /// Gives the parent the recognizer (used for the debug capture).
  final ValueChanged<V4SignRecognizer>? onRecognizer;
  /// Distance from the top of the view to the camera warning pill (lighting,
  /// hand at the edge, low resolution), clear of the parent's own top overlay.
  final double warningTop;
  /// The sign this screen asks for (lesson / quiz); saved with TEST attempts.
  final String? expected;

  const LiveSignView({
    super.key,
    required this.candidates,
    required this.letters,
    this.dominantLeft = false,
    this.resetToken = 0,
    this.active = true,
    this.warningTop = 12,
    this.onUpdate,
    this.onRecognizer,
    this.expected,
  });
  @override
  State<LiveSignView> createState() => _LiveSignViewState();
}

class _LiveSignViewState extends State<LiveSignView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _cameraError;
  bool _streaming = false;
  int _lastSentMs = 0;
  int _lastPoseMs = 0;
  int _lastUpdateMs = 0;
  bool _lastLocked = false;
  int _lastPoseOkMs = 0;
  /// Both shoulders inside the frame with some room: a shoulder clamped to
  /// the edge (user too close / off-centre) shifted every body-relative
  /// feature in the debug captures.
  bool _framingOk = true;
  // Camera warnings (REQ028 lighting, REQ029 hand at the edge, REQ030 resolution)
  bool _lowLight = false, _handAtEdge = false, _lowRes = false;
  int _lastLightMs = 0, _edgeRun = 0, _clearRun = 0, _darkSinceMs = 0;
  /// Hand results per second (moving average); slow phones get fewer pose
  /// frames so the hand detector keeps up.
  double _handRate = 20;
  int _lastHandMs = 0;
  bool _disposed = false;
  // Hand detector health: a native failure or no results at all must show on
  // screen (a silent failure looked like "the app recognizes nothing").
  int _firstSentMs = 0, _lastResultMs = 0;
  bool _detectStalled = false;
  String? _detectError;

  // Serializes camera teardown/setup across LiveSignView instances, so a new
  // view never opens the front camera while the previous one is still closing.
  // Every job is isolated: a failure or hang in one never blocks the next.
  static Future<void> _lastTeardown = Future.value();

  static void _enqueue(Future<void> Function() job) {
    _lastTeardown = _lastTeardown
        .catchError((_) {})            // a previous failure never blocks the next job
        .then((_) => job())
        .catchError((_) {});
  }

  /// Runs [f] with a timeout; swallows failures and hangs. Used for every
  /// native dispose/stop call so one bad step can't wedge the chain.
  static Future<void> _quiet(FutureOr<void> Function() f) async {
    try {
      await Future.sync(f).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  bool _detectorsReady = false;
  StreamSubscription<List<Hand>>? _landmarkSub;
  /// Latest hands for the overlay: repaints only the painter, not the preview.
  final ValueNotifier<List<Hand>> _hands = ValueNotifier(const []);

  NpuPoseDetector get _pose => _SharedDetectors.pose;
  bool _poseReady = false;
  bool _poseBusy = false;
  List<PoseLandmark> _latestPose = const [];

  late final V4SignRecognizer _recognizer;
  final _PerfMeter _perf = _PerfMeter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kShowDebugUi) WidgetsBinding.instance.addTimingsCallback(_perf.onTimings);
    _recognizer = V4SignRecognizer(letters: widget.letters)
      ..dominantLeft = widget.dominantLeft
      ..expected = widget.expected;
    if (kTestBuild) V4SignRecognizer.attemptSink ??= _saveAttempt;
    if (!kLiveSignSupported) return; // build() shows the unsupported notice
    // A model that fails to load must show, not leave the screen "watching".
    _recognizer.init().catchError((Object e) {
      if (mounted) setState(() => _cameraError = 'Sign models could not load.\n$e');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRecognizer?.call(_recognizer));
    _setupCamera();
  }

  /// TEST builds: every attempt -> Android/data/<app>/files/attempts/*.json
  /// (pulled with adb, replayed offline by src/replay_debug_v4.py).
  static Future<void> _saveAttempt(Map<String, dynamic> attempt) async {
    try {
      final base = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (base == null) return;
      final dir = Directory('${base.path}/attempts');
      await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final tag = '${attempt['expected'] ?? 'any'}_${attempt['result']}'
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await File('${dir.path}/${stamp}_$tag.json').writeAsString(jsonEncode(attempt));
    } catch (e) {
      debugPrint('FILOSIGN_SAVE_FAILED $e');
    }
  }

  /// Hooks this view up to the shared detectors (created on first use only).
  void _createDetectors() {
    if (!widget.letters) { // the letters model doesn't use the body
      _SharedDetectors.initPose().then((_) {
        if (mounted && !_disposed) _poseReady = true;
      }).catchError((_) {});
    }
    _SharedDetectors.start();
    _detectorsReady = true;
    _landmarkSub = _SharedDetectors.results.listen((hands) {
      if (!mounted || _disposed || !widget.active) return;
      final sw = kShowDebugUi ? (Stopwatch()..start()) : null;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastHandMs > 0) {
        final dt = (nowMs - _lastHandMs).clamp(1, 1000);
        _handRate = _handRate * 0.9 + (1000 / dt) * 0.1;
      }
      _lastHandMs = nowMs;
      _lastResultMs = nowMs;
      final err = _SharedDetectors.lastError;
      if (err != _detectError || _detectStalled) {
        setState(() {
          _detectError = err;
          _detectStalled = false;
        });
      }
      final p = _recognizer.addFrame(hands, _latestPose, widget.candidates);
      _hands.value = hands;
      if (hands.isNotEmpty) InactivityGuard.activity(); // signing counts as activity
      _checkHandEdge(hands);
      if (sw != null) {
        _perf.hands++;
        _perf.handCbUs += sw.elapsedMicroseconds;
      }
      // The parent rebuilds on every update; ~8 per second is plenty for the
      // text and keeps the UI thread free (lock changes go out at once).
      final now = DateTime.now().millisecondsSinceEpoch;
      final locked = _recognizer.isLocked;
      if (now - _lastUpdateMs < 120 && locked == _lastLocked) return;
      _lastUpdateMs = now;
      _lastLocked = locked;
      widget.onUpdate?.call(LiveSignState(
        prediction: p,
        locked: _recognizer.isLocked,
        top3: _recognizer.top3,
        handCount: hands.length,
        head: _recognizer.headName,
        latencyMs: _recognizer.lastLatencyMs,
        present: _recognizer.lastPresent,
        notRecognized: _recognizer.notRecognized,
        bodyVisible: _recognizer.lastPoseOk && _framingOk,
        perf: _perf.text,
      ));
    });
  }

  @override
  void didUpdateWidget(covariant LiveSignView old) {
    super.didUpdateWidget(old);
    if (old.resetToken != widget.resetToken ||
        old.dominantLeft != widget.dominantLeft) {
      _recognizer.dominantLeft = widget.dominantLeft;
      _recognizer.reset();
    }
    if (old.active != widget.active) {
      if (widget.active) {
        _recognizer.reset();
        _startStream();
      } else {
        _stopStream();
      }
    }
  }

  Future<void> _routeSettled() async {
    if (!mounted) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.isCompleted) return;
    final done = Completer<void>();
    void onStatus(AnimationStatus s) {
      if (!s.isAnimating && !done.isCompleted) done.complete();
    }
    anim.addStatusListener(onStatus);
    try {
      await done.future.timeout(const Duration(seconds: 2));
    } catch (_) {}
    anim.removeStatusListener(onStatus);
  }

  Future<void> _setupCamera() async {
    // A replaced view is disposed at the END of the frame that mounts this
    // one, so wait for that frame before reading the teardown queue.
    await WidgetsBinding.instance.endOfFrame;
    // Bounded wait: a hung teardown can't block this view forever.
    try {
      await _lastTeardown.timeout(const Duration(seconds: 3));
    } catch (_) {}
    // Start the camera + detectors only once the page has finished sliding
    // in: doing it during the animation made the transition stutter.
    await _routeSettled();
    if (!mounted || _disposed) return;
    if (!_detectorsReady) {
      try {
        _createDetectors();
      } catch (e) {
        if (mounted) setState(() => _cameraError = 'Hand detection could not start.\n$e');
        return;
      }
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        // 480p: at 240x320 the body/pose detector usually found nothing and hand
        // tracking dropped frames (teammate debug captures); training was 720p.
        ResolutionPreset.medium,
        enableAudio: false,
        // iOS streams BGRA (what MediaPipe / the pose plugin take there)
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await _quiet(controller.dispose);
        return;
      }
      setState(() => _controller = controller);
      await _startStream();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError =
            'Camera error: ${e.code}\n${e.description ?? ''}\n\n'
            'If you denied the camera permission, enable it in Settings and reopen.');
      }
    }
  }

  Future<void> _startStream() async {
    final controller = _controller;
    if (controller == null || !_detectorsReady || _streaming) return;
    // Flip before the await so _setupCamera and didUpdateWidget can't both
    // enter and trigger "already streaming".
    _streaming = true;
    _firstSentMs = 0;
    _lastResultMs = 0;
    try {
      final orientation = controller.description.sensorOrientation;
      await controller.startImageStream((CameraImage image) {
        if (_disposed || !widget.active) return;
        final camSw = kShowDebugUi ? (Stopwatch()..start()) : null;
        if (kShowDebugUi) {
          _perf.camera++;
          _perf.tick(_recognizer.lastLatencyMs);
        }
        if (!_recognizer.hasImageSize) {
          // iOS frames arrive upright and (front camera) mirrored; Android
          // frames arrive in sensor orientation, un-mirrored.
          _recognizer.configureCamera(
              sensorOrientation: Platform.isIOS ? 0 : orientation,
              imageWidth: image.width,
              imageHeight: image.height,
              mirrored: Platform.isIOS &&
                  controller.description.lensDirection == CameraLensDirection.front);
          // REQ030: below 640 px on the long side the hands are too small
          final lowRes = math.max(image.width, image.height) < 640;
          if (lowRes != _lowRes && mounted) setState(() => _lowRes = lowRes);
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastLightMs >= 500) {
          _lastLightMs = now;
          _checkLight(image, now);
          _checkDetector(now);
        }
        // Cheap here: both platforms detect off the UI thread and drop frames
        // while busy, so nothing queues up.
        if (now - _lastSentMs >= 33) {
          _lastSentMs = now;
          if (_firstSentMs == 0) _firstSentMs = now;
          try {
            _SharedDetectors.processFrame(image, orientation);
          } catch (_) {}
        }
        // Pose frames are copied over the platform channel; 5 per second keeps
        // the UI thread responsive (the recognizer reuses the latest pose).
        if (!widget.letters && now - _lastPoseMs >= (_handRate < 12 ? 350 : 200)) {
          _lastPoseMs = now;
          _feedPose(image, orientation);
        }
        if (camSw != null) _perf.camCbUs += camSw.elapsedMicroseconds;
      });
    } catch (_) {
      _streaming = false;
    }
  }

  Future<void> _feedPose(CameraImage image, int orientation) async {
    if (!_poseReady || _poseBusy) return;
    _poseBusy = true;
    try {
      final half = Platform.isIOS ? _halfSizeBgra(image) : _halfSizeI420(image);
      final res = await _pose.processFrame(
        planes: half.planes,
        width: half.width,
        height: half.height,
        format: Platform.isIOS ? 'bgra8888' : 'yuv420',
        rotation: Platform.isIOS ? 0 : orientation,
      );
      if (_disposed) return;
      if (kShowDebugUi) _perf.pose++;
      // Keep the last good pose for a moment when one detection fails, so the
      // body location doesn't flicker on and off (training always had it).
      final now = DateTime.now().millisecondsSinceEpoch;
      if (res.poses.isNotEmpty) {
        _latestPose = res.poses.first.landmarks;
        _lastPoseOkMs = now;
        if (_latestPose.length > 12) {
          final l = _latestPose[11].x, r = _latestPose[12].x;
          _framingOk = l > 0.04 && l < 0.96 && r > 0.04 && r < 0.96 && (l - r).abs() < 0.7;
        }
      } else if (now - _lastPoseOkMs > 1500) {
        _latestPose = const [];
      }
    } catch (_) {
    } finally {
      _poseBusy = false;
    }
  }

  /// Half-size, tightly packed Y/U/V planes for the pose plugin. The plugin
  /// base64-encodes every plane on the UI thread and its native side ignores
  /// row/pixel strides (it assumes packed planes - interleaved camera chroma
  /// came out scrambled). Its model sees a 256 px image anyway, so half size
  /// (320x240) loses nothing and is 4x less work.
  static ({List<Map<String, dynamic>> planes, int width, int height}) _halfSizeI420(
      CameraImage img) {
    final w = (img.width ~/ 2) & ~1, h = (img.height ~/ 2) & ~1;
    final yp = img.planes[0], up = img.planes[1], vp = img.planes[2];
    final y = Uint8List(w * h);
    for (var r = 0; r < h; r++) {
      final src = 2 * r * yp.bytesPerRow, dst = r * w;
      for (var c = 0; c < w; c++) {
        y[dst + c] = yp.bytes[src + 2 * c];
      }
    }
    final cw = w ~/ 2, ch = h ~/ 2;
    final ps = up.bytesPerPixel ?? 1;
    final u = Uint8List(cw * ch), v = Uint8List(cw * ch);
    for (var r = 0; r < ch; r++) {
      final su = 2 * r * up.bytesPerRow, sv = 2 * r * vp.bytesPerRow, dst = r * cw;
      for (var c = 0; c < cw; c++) {
        u[dst + c] = up.bytes[su + 2 * c * ps];
        v[dst + c] = vp.bytes[sv + 2 * c * ps];
      }
    }
    return (
      planes: [
        {'bytes': y, 'bytesPerRow': w, 'bytesPerPixel': 1},
        {'bytes': u, 'bytesPerRow': cw, 'bytesPerPixel': 1},
        {'bytes': v, 'bytesPerRow': cw, 'bytesPerPixel': 1},
      ],
      width: w,
      height: h,
    );
  }

  /// iOS: half-size packed BGRA (the iOS pose plugin copies one packed
  /// plane into a pixel buffer and ignores the row stride).
  static ({List<Map<String, dynamic>> planes, int width, int height}) _halfSizeBgra(
      CameraImage img) {
    final w = (img.width ~/ 2) & ~1, h = (img.height ~/ 2) & ~1;
    final src = img.planes[0].bytes, row = img.planes[0].bytesPerRow;
    final out = Uint8List(w * h * 4);
    for (var r = 0; r < h; r++) {
      final s = 2 * r * row, d = r * w * 4;
      for (var c = 0; c < w; c++) {
        final si = s + 8 * c, di = d + 4 * c;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    return (
      planes: [
        {'bytes': out, 'bytesPerRow': w * 4, 'bytesPerPixel': 4},
      ],
      width: w,
      height: h,
    );
  }

  /// REQ028: average brightness of a sparse sample of the frame (0-255).
  /// Dark for 1 s -> warn; clears with some margin so it doesn't flicker.
  void _checkLight(CameraImage image, int now) {
    final p = image.planes.first;
    final bytes = p.bytes;
    if (bytes.isEmpty) return;
    final bgra = Platform.isIOS; // iOS: BGRA pixels; Android: Y (luma) plane
    const samples = 1500;
    final stride = math.max(1, bytes.length ~/ samples);
    var sum = 0, n = 0;
    for (var i = 0; i + 3 < bytes.length; i += stride) {
      final at = bgra ? i - i % 4 : i;
      sum += bgra
          ? (bytes[at] * 29 + bytes[at + 1] * 150 + bytes[at + 2] * 77) >> 8
          : bytes[at];
      n++;
    }
    if (n == 0) return;
    final mean = sum / n;
    var dark = _lowLight;
    if (mean < 55) {
      if (_darkSinceMs == 0) _darkSinceMs = now;
      if (now - _darkSinceMs >= 1000) dark = true;
    } else {
      _darkSinceMs = 0;
      if (mean > 70) dark = false;
    }
    if (dark != _lowLight && mounted) setState(() => _lowLight = dark);
  }

  /// REQ029: a hand whose landmarks reach the frame edge (3% margin) is cut
  /// off; warn after 3 such results in a row, clear after 5 clear ones.
  void _checkHandEdge(List<Hand> hands) {
    var edge = false;
    for (final h in hands) {
      for (final lm in h.landmarks) {
        if (lm.x < 0.03 || lm.x > 0.97 || lm.y < 0.03 || lm.y > 0.97) {
          edge = true;
          break;
        }
      }
    }
    if (edge) {
      _edgeRun++;
      _clearRun = 0;
    } else {
      _clearRun++;
      _edgeRun = 0;
    }
    final show = _handAtEdge ? _clearRun < 5 : _edgeRun >= 3;
    if (show != _handAtEdge && mounted) setState(() => _handAtEdge = show);
  }

  /// Frames go in but no hand result has come back for 4 s (first start
  /// included: the GPU model load takes ~1 s) -> the detector is stuck.
  void _checkDetector(int now) {
    if (_firstSentMs == 0) return;
    final since = _lastResultMs > _firstSentMs ? _lastResultMs : _firstSentMs;
    final stalled = now - since > 4000;
    if (stalled != _detectStalled && mounted) setState(() => _detectStalled = stalled);
  }

  String? get _warning {
    if (_detectError != null) {
      return 'Hand detection error. Close and reopen this screen.'
          '${kShowDebugUi ? '\n$_detectError' : ''}';
    }
    if (_detectStalled) return 'Hand detection is not responding. Close and reopen this screen.';
    if (_lowLight) return 'Too dark: add light in front of you';
    if (_handAtEdge) return 'Keep your hands inside the frame';
    if (_lowRes) return 'Camera resolution is low: recognition may be less accurate';
    return null;
  }

  Future<void> _stopStream([CameraController? c]) async {
    final controller = c ?? _controller;
    if (controller != null && _streaming) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
    _streaming = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller == null) return;
      _controller = null;
      _recognizer.reset();
      if (mounted) setState(() {});
      _enqueue(() async {
        await _quiet(() => _stopStream(controller));
        await _quiet(controller.dispose);
      });
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_disposed && kLiveSignSupported) _setupCamera();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (kShowDebugUi) WidgetsBinding.instance.removeTimingsCallback(_perf.onTimings);
    _landmarkSub?.cancel();
    _enqueue(_teardown);
    _hands.dispose();
    super.dispose();
  }

  /// Ordered shutdown: stop frames, let any pose call finish, then free native
  /// resources. Every step is isolated and time-boxed, so one failure can't
  /// skip the rest. Runs in the background so dispose() returns immediately.
  Future<void> _teardown() async {
    final controller = _controller;
    _controller = null;
    await _quiet(() => _stopStream(controller));
    for (var i = 0; i < 20 && _poseBusy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await _quiet(_recognizer.dispose);
    await _quiet(() => controller?.dispose());
    // the hand landmarker and pose detector are shared (_SharedDetectors)
  }

  @override
  Widget build(BuildContext context) {
    if (!kLiveSignSupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_android, color: Colors.white70, size: 44),
              SizedBox(height: 12),
              Text('Live sign checking is available on Android only for now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('You can skip this step and keep learning with the videos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_cameraError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)));
    }
    final previewSize = controller.value.previewSize;
    final view = Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        if (previewSize != null)
          RepaintBoundary(
            child: CustomPaint(
              painter: _HandOverlayPainter(
                hands: _hands,
                previewSize: previewSize,
                sensorOrientation: controller.description.sensorOrientation,
                isFront: controller.description.lensDirection ==
                    CameraLensDirection.front,
              ),
            ),
          ),
      ],
    );
    final Widget camera = previewSize == null
        ? Center(
            child: AspectRatio(aspectRatio: 1 / controller.value.aspectRatio, child: view),
          )
        // Fill the whole box (crop the edges) instead of black bars.
        : ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height, // portrait: sensor width/height swap
                height: previewSize.width,
                child: view,
              ),
            ),
          );
    final warning = _warning;
    if (warning == null) return camera;
    return Stack(
      fit: StackFit.expand,
      children: [
        camera,
        Positioned(
          top: widget.warningTop,
          left: 16,
          right: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xEEB45309),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(warning,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HandOverlayPainter extends CustomPainter {
  final ValueListenable<List<Hand>> hands;
  final Size previewSize;
  final int sensorOrientation;
  final bool isFront;
  _HandOverlayPainter({
    required this.hands,
    required this.previewSize,
    required this.sensorOrientation,
    required this.isFront,
  }) : super(repaint: hands);

  static const List<List<int>> _connections = [
    [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8],
    [5, 9], [9, 10], [10, 11], [11, 12], [9, 13], [13, 14], [14, 15], [15, 16],
    [13, 17], [17, 18], [18, 19], [19, 20], [0, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final hands = this.hands.value;
    if (hands.isEmpty) return;
    // iOS landmarks come from the same upright (mirrored) frames the preview
    // shows; Android ones are in sensor orientation and need the transform.
    final upright = Platform.isIOS;
    final scale = upright ? 1.0 : size.width / previewSize.height;
    if (scale <= 0 || scale.isNaN || scale.isInfinite) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (!upright) {
      canvas.rotate(sensorOrientation * math.pi / 180);
      if (isFront) {
        canvas.scale(-1, 1);
        canvas.rotate(math.pi);
      }
      canvas.scale(scale);
    }
    final pointPaint = Paint()
      ..color = const Color(0xFF5EEAD4)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3 / scale
      ..style = PaintingStyle.stroke;
    final r = 5 / scale;
    Offset pt(Landmark lm) => upright
        ? Offset((lm.x - 0.5) * size.width, (lm.y - 0.5) * size.height)
        : Offset((lm.x - 0.5) * previewSize.width, (lm.y - 0.5) * previewSize.height);
    for (final hand in hands) {
      if (hand.landmarks.length < 21) continue;
      for (final c in _connections) {
        canvas.drawLine(pt(hand.landmarks[c[0]]), pt(hand.landmarks[c[1]]), linePaint);
      }
      for (final lm in hand.landmarks) {
        canvas.drawCircle(pt(lm), r, pointPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HandOverlayPainter old) =>
      old.hands != hands ||
      old.previewSize != previewSize ||
      old.sensorOrientation != sensorOrientation ||
      old.isFront != isFront;
}