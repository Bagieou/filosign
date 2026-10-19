import CoreVideo
import Flutter
import MediaPipeTasksVision
import UIKit

/// FiloSign addition: iOS hand landmarks with the same MediaPipe model as
/// Android (hand_landmarker.task), behind the "filosign/hands_ios" channel.
///
/// "initialize"  -> true, or a FlutterError
/// "process"     {bytes: BGRA, width, height, bytesPerRow, ts}
///               -> [[x0, y0, z0, ... x20, y20, z20], ...] (one list per hand,
///                  normalized to the frame as sent: no rotation applied)
/// Detection runs on a serial background queue; the Dart side sends the next
/// frame only after the previous result came back, so nothing queues up.
public class HandLandmarkerIosPlugin: NSObject, FlutterPlugin {
  private var landmarker: HandLandmarker?
  private let queue = DispatchQueue(label: "filosign.hand_landmarker", qos: .userInitiated)
  private var lastTimestamp = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "filosign/hands_ios", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HandLandmarkerIosPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      queue.async {
        do {
          try self.setUp()
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "init", message: "\(error)", details: nil))
          }
        }
      }
    case "process":
      guard let args = call.arguments as? [String: Any],
        let data = args["bytes"] as? FlutterStandardTypedData,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int,
        let bytesPerRow = args["bytesPerRow"] as? Int,
        let ts = args["ts"] as? Int
      else {
        result(FlutterError(code: "args", message: "bad arguments", details: nil))
        return
      }
      let bytes = data.data
      queue.async {
        let hands = self.detect(
          bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow, ts: ts)
        DispatchQueue.main.async { result(hands) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setUp() throws {
    if landmarker != nil { return }
    guard let path = Self.modelPath() else {
      throw NSError(
        domain: "hand_landmarker", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "hand_landmarker.task not found in the app bundle"])
    }
    let options = HandLandmarkerOptions()
    options.baseOptions.modelAssetPath = path
    options.runningMode = .video
    options.numHands = 2
    options.minHandDetectionConfidence = 0.5
    landmarker = try HandLandmarker(options: options)
  }

  private static func modelPath() -> String? {
    for bundle in [Bundle(for: HandLandmarkerIosPlugin.self), Bundle.main] {
      if let url = bundle.url(forResource: "hand_landmarker_model", withExtension: "bundle"),
        let resources = Bundle(url: url),
        let path = resources.path(forResource: "hand_landmarker", ofType: "task")
      {
        return path
      }
      if let path = bundle.path(forResource: "hand_landmarker", ofType: "task") {
        return path
      }
    }
    return nil
  }

  private func detect(bytes: Data, width: Int, height: Int, bytesPerRow: Int, ts: Int) -> [[Double]]? {
    guard let landmarker = landmarker, width > 0, height > 0,
      bytes.count >= (height - 1) * bytesPerRow + width * 4
    else { return nil }

    var buffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &buffer)
        == kCVReturnSuccess,
      let pixelBuffer = buffer
    else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let dst = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let dstRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let rowBytes = min(width * 4, bytesPerRow, dstRow)
      bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let src = raw.baseAddress else { return }
        for row in 0..<height {
          memcpy(dst + row * dstRow, src + row * bytesPerRow, rowBytes)
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    // VIDEO mode needs strictly increasing timestamps
    let timestamp = max(ts, lastTimestamp + 1)
    lastTimestamp = timestamp
    do {
      let image = try MPImage(pixelBuffer: pixelBuffer, orientation: .up)
      let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestamp)
      return result.landmarks.map { hand in
        hand.flatMap { [Double($0.x), Double($0.y), Double($0.z)] }
      }
    } catch {
      return nil
    }
  }
}
