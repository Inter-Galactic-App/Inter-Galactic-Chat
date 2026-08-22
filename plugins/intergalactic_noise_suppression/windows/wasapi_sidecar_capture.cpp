#include "wasapi_sidecar_capture.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cwchar>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <audioclient.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <windows.h>
#include <wrl/client.h>

namespace intergalactic_noise_suppression {

namespace {

using Microsoft::WRL::ComPtr;

constexpr int kDefaultDiagnosticCaptureMs = 10000;
constexpr int kMaxDiagnosticCaptureMs = 30000;
constexpr REFERENCE_TIME kWasapiBufferDuration = 10000000;
constexpr REFERENCE_TIME kWasapiPeriodicity = 0;

std::string HResultString(HRESULT hr) {
  std::ostringstream stream;
  stream << "0x" << std::hex << static_cast<unsigned long>(hr);
  return stream.str();
}

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') {
    return "";
  }
  const int input_length = static_cast<int>(std::wcslen(value));
  if (input_length <= 0) {
    return "";
  }
  const int length = WideCharToMultiByte(
      CP_UTF8, 0, value, input_length, nullptr, 0, nullptr, nullptr);
  if (length <= 0) {
    return "";
  }
  std::string output(static_cast<size_t>(length), '\0');
  const int written = WideCharToMultiByte(
      CP_UTF8, 0, value, input_length, output.data(), length, nullptr, nullptr);
  if (written <= 0) {
    return "";
  }
  return output;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring output(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), output.data(),
      length);
  return output;
}

std::string ToLowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char ch) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  });
  return value;
}

bool GuidEquals(const GUID& lhs, const GUID& rhs) {
  return IsEqualGUID(lhs, rhs) != 0;
}

bool IsFloatFormat(const WAVEFORMATEX* format) {
  if (format == nullptr) {
    return false;
  }
  if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) {
    return true;
  }
  if (format->wFormatTag != WAVE_FORMAT_EXTENSIBLE ||
      format->cbSize < (sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX))) {
    return false;
  }
  const auto* extensible =
      reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
  return GuidEquals(extensible->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
}

bool IsPcmFormat(const WAVEFORMATEX* format) {
  if (format == nullptr) {
    return false;
  }
  if (format->wFormatTag == WAVE_FORMAT_PCM) {
    return true;
  }
  if (format->wFormatTag != WAVE_FORMAT_EXTENSIBLE ||
      format->cbSize < (sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX))) {
    return false;
  }
  const auto* extensible =
      reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
  return GuidEquals(extensible->SubFormat, KSDATAFORMAT_SUBTYPE_PCM);
}

float ReadPcmSample(const BYTE* sample_data,
                    int bytes_per_sample,
                    int bits_per_sample,
                    bool is_float) {
  if (sample_data == nullptr || bytes_per_sample <= 0) {
    return 0.0f;
  }

  if (is_float && bytes_per_sample == 4) {
    float sample = 0.0f;
    std::memcpy(&sample, sample_data, sizeof(sample));
    return std::isfinite(sample)
               ? (std::clamp)(sample, -1.0f, 1.0f)
               : 0.0f;
  }

  if (bits_per_sample <= 16 && bytes_per_sample >= 2) {
    std::int16_t sample = 0;
    std::memcpy(&sample, sample_data, sizeof(sample));
    return static_cast<float>(sample) / 32768.0f;
  }

  if (bits_per_sample <= 24 && bytes_per_sample >= 3) {
    std::int32_t sample =
        static_cast<std::int32_t>(sample_data[0]) |
        (static_cast<std::int32_t>(sample_data[1]) << 8) |
        (static_cast<std::int32_t>(sample_data[2]) << 16);
    if ((sample & 0x00800000) != 0) {
      sample |= static_cast<std::int32_t>(0xff000000);
    }
    return static_cast<float>(sample) / 8388608.0f;
  }

  if (bytes_per_sample >= 4) {
    std::int32_t sample = 0;
    std::memcpy(&sample, sample_data, sizeof(sample));
    return static_cast<float>(sample) / 2147483648.0f;
  }

  return 0.0f;
}

bool WriteMonoWavFile(const std::string& path,
                      const std::vector<float>& samples,
                      int sample_rate_hz) {
  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file.is_open() || sample_rate_hz <= 0) {
    return false;
  }

  const int bytes_per_sample = 2;
  const int channel_count = 1;
  const int sample_count = static_cast<int>(samples.size());
  const int byte_rate = sample_rate_hz * channel_count * bytes_per_sample;
  const int block_align = channel_count * bytes_per_sample;
  const int data_bytes = sample_count * bytes_per_sample;
  const int riff_size = 36 + data_bytes;

  auto write_u16 = [&](std::uint16_t value) {
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
  };
  auto write_u32 = [&](std::uint32_t value) {
    file.write(reinterpret_cast<const char*>(&value), sizeof(value));
  };

  file.write("RIFF", 4);
  write_u32(static_cast<std::uint32_t>(riff_size));
  file.write("WAVE", 4);
  file.write("fmt ", 4);
  write_u32(16);
  write_u16(1);
  write_u16(static_cast<std::uint16_t>(channel_count));
  write_u32(static_cast<std::uint32_t>(sample_rate_hz));
  write_u32(static_cast<std::uint32_t>(byte_rate));
  write_u16(static_cast<std::uint16_t>(block_align));
  write_u16(16);
  file.write("data", 4);
  write_u32(static_cast<std::uint32_t>(data_bytes));

  for (const float sample : samples) {
    const float normalized = (std::clamp)(sample, -1.0f, 1.0f);
    const auto pcm =
        static_cast<std::int16_t>(std::lrint(normalized * 32767.0f));
    file.write(reinterpret_cast<const char*>(&pcm), sizeof(pcm));
  }

  return file.good();
}

HRESULT ResolveCaptureDevice(IMMDeviceEnumerator* enumerator,
                             const std::string& requested_device_id,
                             ComPtr<IMMDevice>* output,
                             std::string* resolution) {
  if (enumerator == nullptr || output == nullptr || resolution == nullptr) {
    return E_POINTER;
  }

  const std::string requested_lower = ToLowerAscii(requested_device_id);
  if (!requested_lower.empty()) {
    ComPtr<IMMDeviceCollection> collection;
    HRESULT hr = enumerator->EnumAudioEndpoints(
        eCapture, DEVICE_STATE_ACTIVE, &collection);
    if (SUCCEEDED(hr) && collection) {
      UINT count = 0;
      collection->GetCount(&count);
      for (UINT index = 0; index < count; ++index) {
        ComPtr<IMMDevice> candidate;
        if (FAILED(collection->Item(index, &candidate)) || !candidate) {
          continue;
        }
        LPWSTR endpoint_id = nullptr;
        if (FAILED(candidate->GetId(&endpoint_id)) || endpoint_id == nullptr) {
          continue;
        }
        const std::string endpoint_id_utf8 = WideToUtf8(endpoint_id);
        CoTaskMemFree(endpoint_id);
        const std::string endpoint_lower = ToLowerAscii(endpoint_id_utf8);
        if (endpoint_lower == requested_lower ||
            endpoint_lower.find(requested_lower) != std::string::npos ||
            requested_lower.find(endpoint_lower) != std::string::npos) {
          *output = candidate;
          *resolution = "selected_endpoint";
          return S_OK;
        }
      }
    }
    *resolution = "default_fallback";
  } else {
    *resolution = "default_communications";
  }

  return enumerator->GetDefaultAudioEndpoint(
      eCapture, eCommunications, output->GetAddressOf());
}

}  // namespace

WasapiSidecarCapture::~WasapiSidecarCapture() {
  Stop();
}

bool WasapiSidecarCapture::Start(const std::string& directory,
                                 int duration_ms,
                                 const std::string& requested_device_id) {
  Stop();
  if (directory.empty()) {
    SetLastError("directory_empty");
    return false;
  }

  try {
    std::filesystem::create_directories(directory);
  } catch (const std::exception& error) {
    SetLastError(error.what());
    return false;
  }

  const int clamped_duration_ms = (std::clamp)(
      duration_ms <= 0 ? kDefaultDiagnosticCaptureMs : duration_ms,
      1,
      kMaxDiagnosticCaptureMs);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    last_error_.clear();
    device_resolution_ = "starting";
  }
  captured_frames_.store(0);
  dropped_packets_.store(0);
  written_files_.store(0);
  sample_rate_hz_.store(0);
  num_channels_.store(0);
  stop_requested_.store(false);
  active_.store(true);

  worker_ = std::thread(
      &WasapiSidecarCapture::Worker,
      this,
      directory,
      clamped_duration_ms,
      requested_device_id);
  return true;
}

bool WasapiSidecarCapture::Stop() {
  stop_requested_.store(true);
  active_.store(false);
  if (worker_.joinable()) {
    worker_.join();
  }
  return last_error().empty();
}

std::string WasapiSidecarCapture::last_error() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return last_error_;
}

std::string WasapiSidecarCapture::device_resolution() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return device_resolution_;
}

void WasapiSidecarCapture::SetLastError(const std::string& error) {
  std::lock_guard<std::mutex> lock(mutex_);
  last_error_ = error;
}

void WasapiSidecarCapture::SetDeviceResolution(const std::string& resolution) {
  std::lock_guard<std::mutex> lock(mutex_);
  device_resolution_ = resolution;
}

void WasapiSidecarCapture::Worker(std::string directory,
                                  int duration_ms,
                                  std::string requested_device_id) {
  try {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool com_initialized = SUCCEEDED(hr);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    SetLastError("com_initialize_failed:" + HResultString(hr));
    active_.store(false);
    return;
  }

  auto cleanup_com = [&]() {
    if (com_initialized) {
      CoUninitialize();
    }
  };

  ComPtr<IMMDeviceEnumerator> enumerator;
  hr = CoCreateInstance(__uuidof(MMDeviceEnumerator),
                        nullptr,
                        CLSCTX_ALL,
                        IID_PPV_ARGS(&enumerator));
  if (FAILED(hr) || !enumerator) {
    SetLastError("device_enumerator_failed:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  ComPtr<IMMDevice> device;
  std::string resolution;
  hr = ResolveCaptureDevice(
      enumerator.Get(), requested_device_id, &device, &resolution);
  SetDeviceResolution(resolution);
  if (FAILED(hr) || !device) {
    SetLastError("capture_device_unavailable:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  ComPtr<IAudioClient> audio_client;
  hr = device->Activate(
      __uuidof(IAudioClient),
      CLSCTX_ALL,
      nullptr,
      reinterpret_cast<void**>(audio_client.GetAddressOf()));
  if (FAILED(hr) || !audio_client) {
    SetLastError("audio_client_activate_failed:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  WAVEFORMATEX* mix_format = nullptr;
  hr = audio_client->GetMixFormat(&mix_format);
  if (FAILED(hr) || mix_format == nullptr) {
    SetLastError("mix_format_unavailable:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  const int sample_rate_hz = static_cast<int>(mix_format->nSamplesPerSec);
  const int channel_count = static_cast<int>(mix_format->nChannels);
  const int bits_per_sample = static_cast<int>(mix_format->wBitsPerSample);
  const int bytes_per_sample = std::max(1, bits_per_sample / 8);
  const int block_align = static_cast<int>(mix_format->nBlockAlign);
  const bool float_format = IsFloatFormat(mix_format);
  const bool pcm_format = IsPcmFormat(mix_format);
  sample_rate_hz_.store(sample_rate_hz);
  num_channels_.store(channel_count);

  if (!float_format && !pcm_format) {
    CoTaskMemFree(mix_format);
    SetLastError("unsupported_mix_format");
    active_.store(false);
    cleanup_com();
    return;
  }

  hr = audio_client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                                kWasapiBufferDuration,
                                kWasapiPeriodicity,
                                mix_format,
                                nullptr);
  if (FAILED(hr)) {
    CoTaskMemFree(mix_format);
    SetLastError("audio_client_initialize_failed:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  HANDLE event_handle = CreateEvent(nullptr, FALSE, FALSE, nullptr);
  if (event_handle == nullptr) {
    CoTaskMemFree(mix_format);
    SetLastError("capture_event_failed");
    active_.store(false);
    cleanup_com();
    return;
  }

  hr = audio_client->SetEventHandle(event_handle);
  if (FAILED(hr)) {
    CloseHandle(event_handle);
    CoTaskMemFree(mix_format);
    SetLastError("capture_event_bind_failed:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  ComPtr<IAudioCaptureClient> capture_client;
  hr = audio_client->GetService(IID_PPV_ARGS(&capture_client));
  if (FAILED(hr) || !capture_client) {
    CloseHandle(event_handle);
    CoTaskMemFree(mix_format);
    SetLastError("capture_client_unavailable:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  std::vector<float> samples;
  samples.reserve(static_cast<size_t>(
      (static_cast<int64_t>(sample_rate_hz) * duration_ms) / 1000));

  const auto started_at = std::chrono::steady_clock::now();
  const auto deadline =
      started_at + std::chrono::milliseconds(duration_ms);

  hr = audio_client->Start();
  if (FAILED(hr)) {
    CloseHandle(event_handle);
    CoTaskMemFree(mix_format);
    SetLastError("audio_client_start_failed:" + HResultString(hr));
    active_.store(false);
    cleanup_com();
    return;
  }

  while (!stop_requested_.load() &&
         std::chrono::steady_clock::now() < deadline) {
    const DWORD wait_result = WaitForSingleObject(event_handle, 100);
    if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_TIMEOUT) {
      dropped_packets_.fetch_add(1);
      continue;
    }

    UINT32 packet_frames = 0;
    hr = capture_client->GetNextPacketSize(&packet_frames);
    if (FAILED(hr)) {
      SetLastError("packet_size_failed:" + HResultString(hr));
      break;
    }

    while (packet_frames > 0) {
      BYTE* data = nullptr;
      UINT32 frame_count = 0;
      DWORD flags = 0;
      hr = capture_client->GetBuffer(
          &data, &frame_count, &flags, nullptr, nullptr);
      if (FAILED(hr)) {
        SetLastError("capture_buffer_failed:" + HResultString(hr));
        packet_frames = 0;
        break;
      }

      for (UINT32 frame = 0; frame < frame_count; ++frame) {
        float mono = 0.0f;
        if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0 && data != nullptr) {
          const BYTE* frame_data =
              data + (static_cast<size_t>(frame) * block_align);
          for (int channel = 0; channel < channel_count; ++channel) {
            mono += ReadPcmSample(
                frame_data + (channel * bytes_per_sample),
                bytes_per_sample,
                bits_per_sample,
                float_format);
          }
          mono /= static_cast<float>(std::max(1, channel_count));
        }
        samples.push_back((std::clamp)(mono, -1.0f, 1.0f));
      }
      captured_frames_.fetch_add(static_cast<int>(frame_count));

      capture_client->ReleaseBuffer(frame_count);
      hr = capture_client->GetNextPacketSize(&packet_frames);
      if (FAILED(hr)) {
        SetLastError("packet_size_failed:" + HResultString(hr));
        packet_frames = 0;
      }
    }
  }

  audio_client->Stop();
  active_.store(false);

  const std::filesystem::path path =
      std::filesystem::path(directory) / "device_raw_wasapi.wav";
  if (!samples.empty() && WriteMonoWavFile(path.string(), samples,
                                           sample_rate_hz)) {
    written_files_.store(1);
  } else if (last_error().empty()) {
    SetLastError(samples.empty() ? "no_wasapi_samples" : "wav_write_failed");
  }

  CloseHandle(event_handle);
  CoTaskMemFree(mix_format);
  cleanup_com();
  } catch (const std::exception& error) {
    SetLastError(std::string("worker_exception:") + error.what());
    active_.store(false);
  } catch (...) {
    SetLastError("worker_exception:unknown");
    active_.store(false);
  }
}

}  // namespace intergalactic_noise_suppression
