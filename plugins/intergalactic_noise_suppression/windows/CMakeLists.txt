cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "intergalactic_noise_suppression")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "intergalactic_noise_suppression_plugin")

add_library(${PLUGIN_NAME} SHARED
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
  ole32
  ksuser
  uuid
)

set(intergalactic_noise_suppression_bundled_libraries
  ""
  PARENT_SCOPE
)
