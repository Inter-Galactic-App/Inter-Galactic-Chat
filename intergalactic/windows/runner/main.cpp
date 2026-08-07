#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/generated_plugin_registrant.h>
#include <gdiplus.h>
#include <windows.h>

#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  Gdiplus::GdiplusStartupInput gdiplus_startup_input;
  ULONG_PTR gdiplus_token = 0;
  Gdiplus::GdiplusStartup(&gdiplus_token, &gdiplus_startup_input, nullptr);

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Inter Galactic", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  Gdiplus::GdiplusShutdown(gdiplus_token);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
