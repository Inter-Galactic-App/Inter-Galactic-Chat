cmake_minimum_required(VERSION 3.20)
project(intergalactic_game_capture LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(intergalactic_game_capture_helper
  helper/intergalactic_game_capture_helper.cpp
)

target_include_directories(intergalactic_game_capture_helper PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/common"
)

target_compile_definitions(intergalactic_game_capture_helper PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
  _CRT_SECURE_NO_WARNINGS
)

target_link_libraries(intergalactic_game_capture_helper PRIVATE
  Advapi32
  D3D11
  D3DCompiler
  DXGI
  Mf
  Mfplat
  Mfreadwrite
  Mfuuid
  Ole32
  Windowscodecs
)

add_library(intergalactic_game_capture_hook64 SHARED
  hook/intergalactic_game_capture_hook.cpp
)

target_include_directories(intergalactic_game_capture_hook64 PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/common"
)

target_compile_definitions(intergalactic_game_capture_hook64 PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
  _CRT_SECURE_NO_WARNINGS
)

target_link_libraries(intergalactic_game_capture_hook64 PRIVATE
  D3D11
  DXGI
  Windowscodecs
  Ole32
)

set_target_properties(intergalactic_game_capture_hook64 PROPERTIES
  OUTPUT_NAME "intergalactic_game_capture_hook64"
)
