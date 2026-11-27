cmake_minimum_required(VERSION 3.20)
project(InterGalacticCaptureTarget LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(InterGalacticCaptureTarget WIN32
  src/main.cpp
)

target_compile_definitions(InterGalacticCaptureTarget PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
  _CRT_SECURE_NO_WARNINGS
)

target_link_libraries(InterGalacticCaptureTarget PRIVATE
  D3D11
  D3DCompiler
  DXGI
  Shlwapi
)
