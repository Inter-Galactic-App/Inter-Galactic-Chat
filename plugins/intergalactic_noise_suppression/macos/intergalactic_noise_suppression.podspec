Pod::Spec.new do |s|
  s.name             = 'intergalactic_noise_suppression'
  s.version          = '0.0.1'
  s.summary          = 'RNNoise capture post-processing for Inter Galactic.'
  s.description      = 'Native RNNoise capture post-processing for Inter Galactic desktop calls.'
  s.homepage         = 'https://intergalactic.chat'
  s.license          = { :file => '../third_party/rnnoise/COPYING' }
  s.author           = { 'Inter Galactic' => 'dev@intergalactic.chat' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/IntergalacticNoiseSuppressionPlugin.h'
  s.private_header_files = 'Classes/rtc_audio_processing.h'
  s.dependency 'FlutterMacOS'
  s.dependency 'flutter_webrtc'
  s.osx.deployment_target = '10.15'
  s.requires_arc = true
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_C_LANGUAGE_STANDARD' => 'c11',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SKIP_CONFIG_H=1 RNNOISE_BUILD=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/Classes" "${PODS_TARGET_SRCROOT}/../windows" "${PODS_TARGET_SRCROOT}/../third_party/rnnoise/include" "${PODS_TARGET_SRCROOT}/../third_party/rnnoise/src"'
  }
end
