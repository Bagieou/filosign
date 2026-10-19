#
# FiloSign addition: iOS side of the vendored hand_landmarker plugin.
# Runs the same MediaPipe hand_landmarker.task as Android, through Google's
# MediaPipeTasksVision pod, so landmarks match what the sign model expects.
#
Pod::Spec.new do |s|
  s.name             = 'hand_landmarker'
  s.version          = '3.1.0'
  s.summary          = 'MediaPipe hand landmarks for FiloSign (iOS).'
  s.description      = 'MediaPipe Tasks HandLandmarker (VIDEO mode) behind a method channel.'
  s.homepage         = 'https://github.com/IoT-gamer/hand_landmarker'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FiloSign' => 'filosign@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resource_bundles = { 'hand_landmarker_model' => ['Assets/hand_landmarker.task'] }
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision', '0.10.14'
  s.platform         = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version    = '5.0'
end
