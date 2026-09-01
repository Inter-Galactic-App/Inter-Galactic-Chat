#ifndef INTERGALACTIC_NOISE_SUPPRESSION_MACOS_RTC_AUDIO_PROCESSING_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_MACOS_RTC_AUDIO_PROCESSING_H_

namespace libwebrtc {

class RTCAudioProcessing {
 public:
  class CustomProcessing {
   public:
    virtual ~CustomProcessing() = default;
    virtual void Initialize(int sample_rate_hz, int num_channels) = 0;
    virtual void Process(int num_bands,
                         int num_frames,
                         int buffer_size,
                         float* buffer) = 0;
    virtual void Reset(int new_rate) = 0;
    virtual void Release() = 0;
  };
};

}  // namespace libwebrtc

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_MACOS_RTC_AUDIO_PROCESSING_H_
