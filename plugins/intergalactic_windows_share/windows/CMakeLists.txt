cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "intergalactic_windows_share")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "intergalactic_windows_share_plugin")

add_library(${PLUGIN_NAME} SHARED
  "intergalactic_windows_share_plugin.cpp"
  "windows_share_capture.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
  LIB_WEBRTC_API_DLL
  RTC_DESKTOP_DEVICE
  _CRT_SECURE_NO_WARNINGS
)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

set(INTERGALACTIC_WINDOWS_SHARE_WEBRTC_LIBS flutter_webrtc_plugin)
if(TARGET flutter_webrtc_plugin)
  get_target_property(FLUTTER_WEBRTC_INCLUDE_DIRS
    flutter_webrtc_plugin
    INTERFACE_INCLUDE_DIRECTORIES
  )
  list(GET FLUTTER_WEBRTC_INCLUDE_DIRS 0 FLUTTER_WEBRTC_WINDOWS_DIR)
  list(APPEND INTERGALACTIC_WINDOWS_SHARE_WEBRTC_LIBS
    "${FLUTTER_WEBRTC_WINDOWS_DIR}/../third_party/libwebrtc/lib/win64/libwebrtc.dll.lib"
  )
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  ${INTERGALACTIC_WINDOWS_SHARE_WEBRTC_LIBS}
  # OpenProcessToken / GetTokenInformation / GetSidSubAuthorityCount /
  # GetSidSubAuthority (integrity-level probe) live in Advapi32. Link it
  # explicitly rather than relying on it arriving transitively, which is what
  # makes a clean build fail to link while an incremental one succeeds.
  Advapi32
  Mmdevapi
  Ole32
  RuntimeObject
)

set(intergalactic_windows_share_bundled_libraries
  ""
  PARENT_SCOPE
)
