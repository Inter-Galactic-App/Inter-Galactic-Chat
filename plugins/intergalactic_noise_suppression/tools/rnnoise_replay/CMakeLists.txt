cmake_minimum_required(VERSION 3.15)
project(intergalactic_rnnoise_replay LANGUAGES C CXX)

set(PLUGIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(WINDOWS_ROOT "${PLUGIN_ROOT}/windows")
set(RNNOISE_ROOT "${PLUGIN_ROOT}/third_party/rnnoise")

add_executable(intergalactic_rnnoise_replay
  "rnnoise_replay_main.cpp"
  "${WINDOWS_ROOT}/rnnoise_capture_processor.cpp"
  "${WINDOWS_ROOT}/rnnoise_wrapper.c"
  "${RNNOISE_ROOT}/src/celt_lpc.c"
  "${RNNOISE_ROOT}/src/denoise.c"
  "${RNNOISE_ROOT}/src/kiss_fft.c"
  "${RNNOISE_ROOT}/src/nnet.c"
  "${RNNOISE_ROOT}/src/nnet_default.c"
  "${RNNOISE_ROOT}/src/parse_lpcnet_weights.c"
  "${RNNOISE_ROOT}/src/pitch.c"
  "${RNNOISE_ROOT}/src/rnn.c"
  "${RNNOISE_ROOT}/src/rnnoise_data.c"
  "${RNNOISE_ROOT}/src/rnnoise_tables.c"
)

target_compile_features(intergalactic_rnnoise_replay PRIVATE cxx_std_17)
set_target_properties(intergalactic_rnnoise_replay PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED YES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(intergalactic_rnnoise_replay PRIVATE
  _CRT_SECURE_NO_WARNINGS
  NOMINMAX
)

if (MSVC)
  target_compile_options(intergalactic_rnnoise_replay PRIVATE
    /wd4244
    /wd4305
  )
endif()

target_include_directories(intergalactic_rnnoise_replay PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${WINDOWS_ROOT}"
  "${RNNOISE_ROOT}/include"
  "${RNNOISE_ROOT}/src"
)
