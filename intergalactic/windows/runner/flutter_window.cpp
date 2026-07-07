#include "flutter_window.h"

#include <gdiplus.h>

#include <filesystem>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { ClearWindowIcons(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  app_icon_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "chat.intergalactic.app/app_icon",
          &flutter::StandardMethodCodec::GetInstance());

  app_icon_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setAppIcon") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments", "Expected a map");
          return;
        }

        const auto asset_path_it =
            arguments->find(flutter::EncodableValue("assetPath"));
        if (asset_path_it == arguments->end()) {
          result->Error("missing_asset_path", "Missing assetPath");
          return;
        }

        const auto* asset_path =
            std::get_if<std::string>(&asset_path_it->second);
        if (asset_path == nullptr) {
          result->Error("invalid_asset_path", "assetPath must be a string");
          return;
        }

        if (!SetAppIcon(*asset_path)) {
          result->Error("set_icon_failed", "Failed to update window icon");
          return;
        }

        result->Success(flutter::EncodableValue(true));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  app_icon_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  ClearWindowIcons();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::SetAppIcon(const std::string& asset_path) {
  wchar_t executable_path[MAX_PATH];
  const auto path_length =
      GetModuleFileNameW(nullptr, executable_path, MAX_PATH);

  if (path_length == 0 || path_length == MAX_PATH) {
    return false;
  }

  const auto icon_path = std::filesystem::path(executable_path).parent_path() /
                         L"data" / L"flutter_assets" /
                         std::filesystem::path(asset_path);

  if (!std::filesystem::exists(icon_path)) {
    return false;
  }

  auto bitmap = std::unique_ptr<Gdiplus::Bitmap>(
      Gdiplus::Bitmap::FromFile(icon_path.c_str(), FALSE));
  if (bitmap == nullptr || bitmap->GetLastStatus() != Gdiplus::Ok) {
    return false;
  }

  HICON new_large_icon = nullptr;
  if (bitmap->GetHICON(&new_large_icon) != Gdiplus::Ok ||
      new_large_icon == nullptr) {
    return false;
  }

  HICON new_small_icon = CopyIcon(new_large_icon);
  if (new_small_icon == nullptr) {
    DestroyIcon(new_large_icon);
    return false;
  }

  SendMessage(GetHandle(), WM_SETICON, ICON_BIG,
              reinterpret_cast<LPARAM>(new_large_icon));
  SendMessage(GetHandle(), WM_SETICON, ICON_SMALL,
              reinterpret_cast<LPARAM>(new_small_icon));

  if (large_icon_ != nullptr) {
    DestroyIcon(large_icon_);
  }
  if (small_icon_ != nullptr) {
    DestroyIcon(small_icon_);
  }

  large_icon_ = new_large_icon;
  small_icon_ = new_small_icon;
  return true;
}

void FlutterWindow::ClearWindowIcons() {
  if (large_icon_ != nullptr) {
    DestroyIcon(large_icon_);
    large_icon_ = nullptr;
  }

  if (small_icon_ != nullptr) {
    DestroyIcon(small_icon_);
    small_icon_ = nullptr;
  }
}
