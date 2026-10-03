cmake_minimum_required(VERSION 3.15)
project(intergalactic_rnnoise_replay LANGUAGES C CXX)

set(PLUGIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(WINDOWS_ROOT "${PLUGIN_ROOT}/windows")
set(RNNOISE_ROOT "${PLUGIN_ROOT}/third_party/rnnoise")
set(DEEPFILTERNET_ROOT "${PLUGIN_ROOT}/third_party/deepfilternet")
set(HUSH_ROOT "${PLUGIN_ROOT}/third_party/hush")

add_executable(intergalactic_rnnoise_replay
  "rnnoise_replay_main.cpp"
  "${WINDOWS_ROOT}/rnnoise_capture_processor.cpp"
  "${WINDOWS_ROOT}/deep_filter_net_runtime.cpp"
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
  INTERGALACTIC_AUDIO_NATIVE_TEST
)

enable_testing()
add_test(NAME hush_gain_quiet_to_loud
  COMMAND intergalactic_rnnoise_replay --test-hush-gain-quiet-to-loud)

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

# DeepFilterNet runtime (df.dll) for the deepfilternet replay mode. The DLL
# and the model archives are copied beside the executable so the runtime's
# executable-directory model resolution works without environment overrides.
target_link_libraries(intergalactic_rnnoise_replay PRIVATE
  "${DEEPFILTERNET_ROOT}/windows/x64/df.dll.lib"
)
add_custom_command(TARGET intergalactic_rnnoise_replay POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${DEEPFILTERNET_ROOT}/windows/x64/df.dll"
    "$<TARGET_FILE_DIR:intergalactic_rnnoise_replay>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${DEEPFILTERNET_ROOT}/models/DeepFilterNet3_onnx.tar.gz"
    "$<TARGET_FILE_DIR:intergalactic_rnnoise_replay>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${HUSH_ROOT}/onnx/advanced_dfnet16k_model_best_onnx.tar.gz"
    "$<TARGET_FILE_DIR:intergalactic_rnnoise_replay>"
)
