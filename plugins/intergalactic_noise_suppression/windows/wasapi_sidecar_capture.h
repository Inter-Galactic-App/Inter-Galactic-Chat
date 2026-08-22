#ifndef INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_WASAPI_SIDECAR_CAPTURE_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_WASAPI_SIDECAR_CAPTURE_H_

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

namespace intergalactic_noise_suppression {

class WasapiSidecarCapture {
 public:
  WasapiSidecarCapture() = default;
  ~WasapiSidecarCapture();

  bool Start(const std::string& directory,
             int duration_ms,
             const std::string& requested_device_id);
  bool Stop();

  bool active() const { return active_.load(); }
  int captured_frames() const { return captured_frames_.load(); }
  int dropped_packets() const { return dropped_packets_.load(); }
  int written_files() const { return written_files_.load(); }
  int sample_rate_hz() const { return sample_rate_hz_.load(); }
  int num_channels() const { return num_channels_.load(); }
  std::string last_error() const;
  std::string device_resolution() const;

 private:
  void Worker(std::string directory,
              int duration_ms,
              std::string requested_device_id);
  void SetLastError(const std::string& error);
  void SetDeviceResolution(const std::string& resolution);

  mutable std::mutex mutex_;
  std::thread worker_;
  std::atomic<bool> active_{false};
  std::atomic<bool> stop_requested_{false};
  std::atomic<int> captured_frames_{0};
  std::atomic<int> dropped_packets_{0};
  std::atomic<int> written_files_{0};
  std::atomic<int> sample_rate_hz_{0};
  std::atomic<int> num_channels_{0};
  std::string last_error_;
  std::string device_resolution_{"not_started"};
};

}  // namespace intergalactic_noise_suppression

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_WASAPI_SIDECAR_CAPTURE_H_
