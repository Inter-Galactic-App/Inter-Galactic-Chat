cmake_minimum_required(VERSION 3.22.1)
project(intergalactic_noise_suppression_android LANGUAGES CXX)

set(DF_LIBRARY "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libdf.so")
if(NOT EXISTS "${DF_LIBRARY}")
  message(FATAL_ERROR "Missing Android DeepFilterNet runtime: ${DF_LIBRARY}")
endif()

# libdf.so is a prebuilt Rust library with no SONAME. Without
# IMPORTED_NO_SONAME, CMake links it by absolute path and the linker bakes
# that host path (Z:/... on Windows build machines) into this plugin's
# DT_NEEDED, so the Android loader looks for the literal path on-device and
# dlopen fails even though libdf.so is packaged in the APK. With it, CMake
# links via -L/-ldf and DT_NEEDED becomes plain "libdf.so".
add_library(df SHARED IMPORTED)
set_target_properties(df PROPERTIES
  IMPORTED_LOCATION "${DF_LIBRARY}"
  IMPORTED_NO_SONAME TRUE)
add_library(intergalactic_noise_suppression SHARED intergalactic_noise_suppression_jni.cpp)
target_compile_features(intergalactic_noise_suppression PRIVATE cxx_std_17)
target_compile_options(intergalactic_noise_suppression PRIVATE -Wall -Wextra -Werror)
target_link_libraries(intergalactic_noise_suppression PRIVATE df log)
