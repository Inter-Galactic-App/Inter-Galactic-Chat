cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "intergalactic_noise_suppression")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "intergalactic_noise_suppression_plugin")

add_library(${PLUGIN_NAME} SHARED
  "deep_filter_net_runtime.cpp"
  "intergalactic_noise_suppression_plugin.cpp"
  "rnnoise_capture_processor.cpp"
  "rnnoise_wrapper.c"
  "wasapi_sidecar_capture.cpp"
  "../third_party/rnnoise/src/celt_lpc.c"
  "../third_party/rnnoise/src/denoise.c"
  "../third_party/rnnoise/src/kiss_fft.c"
  "../third_party/rnnoise/src/nnet.c"
  "../third_party/rnnoise/src/nnet_default.c"
  "../third_party/rnnoise/src/parse_lpcnet_weights.c"
  "../third_party/rnnoise/src/pitch.c"
  "../third_party/rnnoise/src/rnn.c"
  "../third_party/rnnoise/src/rnnoise_data.c"
  "../third_party/rnnoise/src/rnnoise_tables.c"
)

set(INTERGALACTIC_DEEPFILTERNET_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/deepfilternet"
)
set(INTERGALACTIC_DEEPFILTERNET_DLL
  "${INTERGALACTIC_DEEPFILTERNET_ROOT}/windows/x64/df.dll"
)
set(INTERGALACTIC_DEEPFILTERNET_IMPORT_LIB
  "${INTERGALACTIC_DEEPFILTERNET_ROOT}/windows/x64/df.dll.lib"
)
set(INTERGALACTIC_DEEPFILTERNET_MODEL
  "${INTERGALACTIC_DEEPFILTERNET_ROOT}/models/DeepFilterNet3_onnx.tar.gz"
)
set(INTERGALACTIC_HUSH_MODEL
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/hush/onnx/advanced_dfnet16k_model_best_onnx.tar.gz"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED YES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  _CRT_SECURE_NO_WARNINGS
)

if (MSVC)
  target_compile_options(${PLUGIN_NAME} PRIVATE
    /wd4244
    /wd4305
  )
endif()

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/rnnoise/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/rnnoise/src"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  flutter_webrtc_plugin
  "${INTERGALACTIC_DEEPFILTERNET_IMPORT_LIB}"
  ole32
  ksuser
  uuid
)

set(intergalactic_noise_suppression_bundled_libraries
  "${INTERGALACTIC_DEEPFILTERNET_DLL}"
  "${INTERGALACTIC_DEEPFILTERNET_MODEL}"
)

if (EXISTS "${INTERGALACTIC_HUSH_MODEL}")
  list(APPEND intergalactic_noise_suppression_bundled_libraries
    "${INTERGALACTIC_HUSH_MODEL}"
  )
endif()

set(intergalactic_noise_suppression_bundled_libraries
  ${intergalactic_noise_suppression_bundled_libraries}
  PARENT_SCOPE
)
