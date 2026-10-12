import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

const double kConfidenceThreshold = 0.85;

class SignPrediction {
  final String? sign;
  final double confidence;
  const SignPrediction({required this.sign, required this.confidence});
  bool get isMatch => sign != null && confidence >= kConfidenceThreshold;
  static const SignPrediction none = SignPrediction(sign: null, confidence: 0.0);
}

abstract class SignRecognizer {
  Future<void> init();
  bool get isReady;
  SignPrediction addFrame(
      List<Hand> hands, List<PoseLandmark> pose, List<String> candidates);
  void reset();
  void dispose();
}
