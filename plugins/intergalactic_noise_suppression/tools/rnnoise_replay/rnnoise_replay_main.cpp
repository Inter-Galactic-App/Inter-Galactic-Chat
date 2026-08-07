#include "rnnoise_capture_processor.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace ig = intergalactic_noise_suppression;

namespace {

constexpr int kWavFormatPcm = 1;
constexpr int kWavFormatFloat = 3;
constexpr int kMaxDiagnosticCaptureMs = 30000;
constexpr float kWebRtcFloatS16Scale = 32768.0f;

struct WavData {
  int sample_rate_hz = 0;
  int channels = 0;
  int bits_per_sample = 0;
  int format = 0;
  std::vector<float> mono_samples;
};

struct AudioMetrics {
  double rms = 0.0;
  double peak = 0.0;
  double max_delta = 0.0;
  int clipping_samples = 0;
  int non_finite_samples = 0;
  int noisy_frames = 0;
  int delta_frames = 0;
  int frame_count = 0;
};

struct SegmentSummary {
  std::string name;
  double start_seconds = 0.0;
  double end_seconds = 0.0;
  AudioMetrics input_metrics;
  AudioMetrics output_metrics;
  int worse_than_input_frames = 0;
};

struct SegmentSpec {
  std::string name;
  double start_seconds = 0.0;
  double end_seconds = 0.0;
};

struct ReplayScore {
  double speech_preservation = 0.0;
  double noise_reduction = 0.0;
  double artifact_safety = 0.0;
  double candidate_score = 0.0;
  double overall = 0.0;
  bool has_speech_segments = false;
  bool has_noise_segments = false;
  bool speech_safety_passed = false;
  bool artifact_safety_passed = false;
};

struct ReplayOptions {
  std::string input_path;
  std::string fixture;
  std::string output_dir;
  std::string label = "rnnoise-replay";
  std::string mode = "clean";
  std::vector<std::string> equal_segments;
  std::vector<SegmentSpec> segment_specs;
  bool has_vad_threshold = false;
  bool has_speech_grace_frames = false;
  bool has_closed_gain = false;
  bool has_transient_sensitivity = false;
  bool has_fast_close = false;
  double vad_threshold = 0.90;
  int speech_grace_frames = 20;
  double closed_gain = 0.03;
  double transient_sensitivity = 0.0;
  bool fast_close = false;
  int fixture_sample_rate_hz = 48000;
};

uint16_t ReadLe16(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint16_t>(bytes[offset]) |
         (static_cast<uint16_t>(bytes[offset + 1]) << 8);
}

uint32_t ReadLe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

int16_t ReadLeI16(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<int16_t>(ReadLe16(bytes, offset));
}

float ReadLeFloat32(const std::vector<uint8_t>& bytes, size_t offset) {
  static_assert(sizeof(float) == sizeof(uint32_t), "float must be 32-bit");
  const uint32_t raw = ReadLe32(bytes, offset);
  float value = 0.0f;
  std::memcpy(&value, &raw, sizeof(float));
  return value;
}

std::string EscapeJson(const std::string& value) {
  std::ostringstream stream;
  for (const char ch : value) {
    switch (ch) {
      case '\\':
        stream << "\\\\";
        break;
      case '"':
        stream << "\\\"";
        break;
      case '\n':
        stream << "\\n";
        break;
      case '\r':
        stream << "\\r";
        break;
      case '\t':
        stream << "\\t";
        break;
      default:
        stream << ch;
        break;
    }
  }
  return stream.str();
}

bool ReadFileBytes(const std::string& path, std::vector<uint8_t>* bytes) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return false;
  }
  input.seekg(0, std::ios::end);
  const std::streamoff size = input.tellg();
  if (size <= 0) {
    return false;
  }
  input.seekg(0, std::ios::beg);
  bytes->resize(static_cast<size_t>(size));
  input.read(reinterpret_cast<char*>(bytes->data()), size);
  return input.good();
}

bool ReadWavFile(const std::string& path, WavData* output, std::string* error) {
  std::vector<uint8_t> bytes;
  if (!ReadFileBytes(path, &bytes)) {
    *error = "could_not_read_input";
    return false;
  }
  if (bytes.size() < 44 ||
      std::string(reinterpret_cast<const char*>(bytes.data()), 4) != "RIFF" ||
      std::string(reinterpret_cast<const char*>(bytes.data() + 8), 4) !=
          "WAVE") {
    *error = "input_is_not_riff_wave";
    return false;
  }

  bool has_format = false;
  bool has_data = false;
  uint16_t format = 0;
  uint16_t channels = 0;
  uint32_t sample_rate = 0;
  uint16_t block_align = 0;
  uint16_t bits_per_sample = 0;
  size_t data_offset = 0;
  uint32_t data_size = 0;

  size_t cursor = 12;
  while (cursor + 8 <= bytes.size()) {
    const std::string id(
        reinterpret_cast<const char*>(bytes.data() + cursor), 4);
    const uint32_t chunk_size = ReadLe32(bytes, cursor + 4);
    const size_t chunk_data = cursor + 8;
    if (chunk_data + chunk_size > bytes.size()) {
      break;
    }

    if (id == "fmt " && chunk_size >= 16) {
      format = ReadLe16(bytes, chunk_data);
      channels = ReadLe16(bytes, chunk_data + 2);
      sample_rate = ReadLe32(bytes, chunk_data + 4);
      block_align = ReadLe16(bytes, chunk_data + 12);
      bits_per_sample = ReadLe16(bytes, chunk_data + 14);
      has_format = true;
    } else if (id == "data") {
      data_offset = chunk_data;
      data_size = chunk_size;
      has_data = true;
    }

    cursor = chunk_data + chunk_size + (chunk_size % 2);
  }

  if (!has_format || !has_data || channels == 0 || block_align == 0 ||
      sample_rate == 0) {
    *error = "missing_or_invalid_wav_chunks";
    return false;
  }
  if (!((format == kWavFormatPcm && bits_per_sample == 16) ||
        (format == kWavFormatFloat && bits_per_sample == 32))) {
    *error = "unsupported_wav_format";
    return false;
  }

  const uint32_t frame_count = data_size / block_align;
  output->sample_rate_hz = static_cast<int>(sample_rate);
  output->channels = static_cast<int>(channels);
  output->bits_per_sample = static_cast<int>(bits_per_sample);
  output->format = static_cast<int>(format);
  output->mono_samples.clear();
  output->mono_samples.reserve(frame_count);

  const int bytes_per_sample = bits_per_sample / 8;
  for (uint32_t frame = 0; frame < frame_count; ++frame) {
    double sum = 0.0;
    for (uint16_t channel = 0; channel < channels; ++channel) {
      const size_t offset =
          data_offset + (frame * block_align) + (channel * bytes_per_sample);
      if (format == kWavFormatPcm) {
        sum += static_cast<double>(ReadLeI16(bytes, offset)) / 32768.0;
      } else {
        sum += ReadLeFloat32(bytes, offset);
      }
    }
    output->mono_samples.push_back(
        static_cast<float>(sum / static_cast<double>(channels)));
  }

  return true;
}

void WriteLe16(std::ofstream& output, uint16_t value) {
  output.put(static_cast<char>(value & 0xff));
  output.put(static_cast<char>((value >> 8) & 0xff));
}

void WriteLe32(std::ofstream& output, uint32_t value) {
  output.put(static_cast<char>(value & 0xff));
  output.put(static_cast<char>((value >> 8) & 0xff));
  output.put(static_cast<char>((value >> 16) & 0xff));
  output.put(static_cast<char>((value >> 24) & 0xff));
}

bool WriteWavFile(const std::string& path,
                  const std::vector<float>& samples,
                  int sample_rate_hz) {
  std::ofstream output(path, std::ios::binary);
  if (!output) {
    return false;
  }

  const uint32_t data_size =
      static_cast<uint32_t>(samples.size() * sizeof(int16_t));
  output.write("RIFF", 4);
  WriteLe32(output, 36 + data_size);
  output.write("WAVE", 4);
  output.write("fmt ", 4);
  WriteLe32(output, 16);
  WriteLe16(output, kWavFormatPcm);
  WriteLe16(output, 1);
  WriteLe32(output, static_cast<uint32_t>(sample_rate_hz));
  WriteLe32(output, static_cast<uint32_t>(sample_rate_hz * sizeof(int16_t)));
  WriteLe16(output, sizeof(int16_t));
  WriteLe16(output, 16);
  output.write("data", 4);
  WriteLe32(output, data_size);

  for (const float sample : samples) {
    const float clamped = std::clamp(
        std::isfinite(sample) ? sample : 0.0f,
        -1.0f,
        0.999969f);
    const int16_t pcm =
        static_cast<int16_t>(std::lrint(clamped * 32768.0f));
    WriteLe16(output, static_cast<uint16_t>(pcm));
  }
  return output.good();
}

WavData BuildPlosiveSpeechFixture(int sample_rate_hz) {
  constexpr double kDurationSeconds = 3.0;
  constexpr double kTwoPi = 6.28318530717958647692;
  const int safe_sample_rate = sample_rate_hz;
  const int sample_count =
      static_cast<int>(std::llround(kDurationSeconds * safe_sample_rate));
  const double plosive_times[] = {0.42, 1.18, 2.04};

  WavData data;
  data.sample_rate_hz = safe_sample_rate;
  data.channels = 1;
  data.bits_per_sample = 16;
  data.format = kWavFormatPcm;
  data.mono_samples.reserve(static_cast<size_t>(sample_count));

  for (int index = 0; index < sample_count; ++index) {
    const double t = static_cast<double>(index) /
                     static_cast<double>(safe_sample_rate);
    const double fade_in = std::min(1.0, t / 0.08);
    const double fade_out = std::min(1.0, (kDurationSeconds - t) / 0.08);
    const double envelope = fade_in * fade_out;
    double sample =
        envelope * ((0.090 * std::sin(kTwoPi * 118.0 * t)) +
                    (0.034 * std::sin(kTwoPi * 236.0 * t)) +
                    (0.018 * std::sin(kTwoPi * 354.0 * t)));

    for (const double plosive_time : plosive_times) {
      const double dt = t - plosive_time;
      if (dt < 0.0 || dt >= 0.14) {
        continue;
      }
      if (dt < 0.035) {
        const double decay = std::exp(-85.0 * dt);
        const double polarity = (index % 2 == 0) ? 1.0 : -1.0;
        sample += envelope * decay *
                  ((0.38 * polarity) +
                   (0.20 * std::sin(kTwoPi * 1800.0 * t)) +
                   (0.08 * std::sin(kTwoPi * 3100.0 * t)));
      } else {
        const double tail_decay = std::exp(-35.0 * (dt - 0.035));
        sample += envelope * tail_decay *
                  (0.055 * std::sin(kTwoPi * 1550.0 * t));
      }
    }

    data.mono_samples.push_back(
        static_cast<float>(std::clamp(sample, -0.95, 0.95)));
  }

  return data;
}

AudioMetrics ComputeMetrics(const std::vector<float>& samples,
                            int sample_rate_hz) {
  AudioMetrics metrics;
  if (samples.empty()) {
    return metrics;
  }

  double sum_squares = 0.0;
  for (size_t index = 0; index < samples.size(); ++index) {
    const float sample = samples[index];
    if (!std::isfinite(sample)) {
      metrics.non_finite_samples++;
      continue;
    }
    const double abs_sample = std::abs(static_cast<double>(sample));
    metrics.peak = std::max(metrics.peak, abs_sample);
    if (abs_sample >= 0.9995) {
      metrics.clipping_samples++;
    }
    if (index > 0 && std::isfinite(samples[index - 1])) {
      metrics.max_delta = std::max(
          metrics.max_delta,
          std::abs(static_cast<double>(sample) -
                   static_cast<double>(samples[index - 1])));
    }
    sum_squares += static_cast<double>(sample) * static_cast<double>(sample);
  }
  metrics.rms =
      std::sqrt(sum_squares / static_cast<double>(samples.size()));

  const int frame_size = std::max(1, sample_rate_hz / 100);
  metrics.frame_count = static_cast<int>(samples.size()) / frame_size;
  for (int frame = 0; frame < metrics.frame_count; ++frame) {
    const int offset = frame * frame_size;
    double frame_sum = 0.0;
    double frame_peak = 0.0;
    double frame_delta = 0.0;
    for (int i = 0; i < frame_size; ++i) {
      const float sample = samples[offset + i];
      if (!std::isfinite(sample)) {
        continue;
      }
      frame_sum += static_cast<double>(sample) * static_cast<double>(sample);
      frame_peak = std::max(frame_peak, std::abs(static_cast<double>(sample)));
      if (i > 0 && std::isfinite(samples[offset + i - 1])) {
        frame_delta = std::max(
            frame_delta,
            std::abs(static_cast<double>(sample) -
                     static_cast<double>(samples[offset + i - 1])));
      }
    }
    const double frame_rms =
        std::sqrt(frame_sum / static_cast<double>(frame_size));
    if (frame_rms > 0.006 || frame_peak > 0.02 || frame_delta > 0.025) {
      metrics.noisy_frames++;
    }
    if (frame_delta > 0.025) {
      metrics.delta_frames++;
    }
  }

  return metrics;
}

int CountWorseThanInputFrames(const std::vector<float>& input,
                              const std::vector<float>& output,
                              int sample_rate_hz) {
  const int frame_size = std::max(1, sample_rate_hz / 100);
  const int frame_count =
      static_cast<int>(std::min(input.size(), output.size())) / frame_size;
  int worse = 0;
  for (int frame = 0; frame < frame_count; ++frame) {
    double input_sum = 0.0;
    double output_sum = 0.0;
    for (int i = 0; i < frame_size; ++i) {
      const int offset = (frame * frame_size) + i;
      input_sum += static_cast<double>(input[offset]) *
                   static_cast<double>(input[offset]);
      output_sum += static_cast<double>(output[offset]) *
                    static_cast<double>(output[offset]);
    }
    const double input_rms =
        std::sqrt(input_sum / static_cast<double>(frame_size));
    const double output_rms =
        std::sqrt(output_sum / static_cast<double>(frame_size));
    if (output_rms > 0.003 && output_rms > input_rms * 1.5) {
      worse++;
    }
  }
  return worse;
}

std::vector<std::string> SplitCsv(const std::string& value) {
  std::vector<std::string> result;
  std::stringstream stream(value);
  std::string item;
  while (std::getline(stream, item, ',')) {
    item.erase(
        item.begin(),
        std::find_if(item.begin(), item.end(), [](unsigned char ch) {
          return !std::isspace(ch);
        }));
    item.erase(
        std::find_if(item.rbegin(), item.rend(), [](unsigned char ch) {
          return !std::isspace(ch);
        }).base(),
        item.end());
    if (!item.empty()) {
      result.push_back(item);
    }
  }
  return result;
}

std::string LowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

bool ContainsWord(const std::string& value, const std::string& needle) {
  return LowerAscii(value).find(needle) != std::string::npos;
}

double ClampScore(double value) {
  return std::clamp(value, 0.0, 100.0);
}

bool ParseDouble(const std::string& value, double* output) {
  if (value.empty()) {
    return false;
  }
  char* end = nullptr;
  const double parsed = std::strtod(value.c_str(), &end);
  if (end == value.c_str() || *end != '\0' || !std::isfinite(parsed)) {
    return false;
  }
  *output = parsed;
  return true;
}

bool ParseInt(const std::string& value, int* output) {
  if (value.empty()) {
    return false;
  }
  char* end = nullptr;
  const long parsed = std::strtol(value.c_str(), &end, 10);
  if (end == value.c_str() || *end != '\0' ||
      parsed < std::numeric_limits<int>::min() ||
      parsed > std::numeric_limits<int>::max()) {
    return false;
  }
  *output = static_cast<int>(parsed);
  return true;
}

bool IsSupportedReplaySampleRate(int sample_rate_hz) {
  return sample_rate_hz >= 8000 && sample_rate_hz <= 192000 &&
         sample_rate_hz % 100 == 0;
}

bool ParseBool(const std::string& value, bool* output) {
  const std::string lower = LowerAscii(value);
  if (lower == "1" || lower == "true" || lower == "yes" || lower == "on") {
    *output = true;
    return true;
  }
  if (lower == "0" || lower == "false" || lower == "no" ||
      lower == "off") {
    *output = false;
    return true;
  }
  return false;
}

bool ParseSegmentSpecs(const std::string& value,
                       std::vector<SegmentSpec>* specs,
                       std::string* error) {
  specs->clear();
  for (const std::string& item : SplitCsv(value)) {
    const size_t equals = item.find('=');
    const size_t dash = item.find('-', equals == std::string::npos ? 0 : equals);
    if (equals == std::string::npos || dash == std::string::npos ||
        equals == 0 || dash <= equals + 1 || dash + 1 >= item.size()) {
      *error = "segment_ranges_must_use_name=start-end";
      return false;
    }

    SegmentSpec spec;
    spec.name = item.substr(0, equals);
    if (!ParseDouble(item.substr(equals + 1, dash - equals - 1),
                     &spec.start_seconds) ||
        !ParseDouble(item.substr(dash + 1), &spec.end_seconds)) {
      *error = "segment_range_has_invalid_number";
      return false;
    }
    if (spec.end_seconds <= spec.start_seconds || spec.start_seconds < 0.0) {
      *error = "segment_range_must_increase";
      return false;
    }
    specs->push_back(spec);
  }
  return true;
}

std::vector<float> SliceSamples(const std::vector<float>& samples,
                                size_t begin,
                                size_t end) {
  begin = std::min(begin, samples.size());
  end = std::min(std::max(begin, end), samples.size());
  return std::vector<float>(samples.begin() + begin, samples.begin() + end);
}

SegmentSummary BuildSegmentSummary(const std::string& name,
                                   double start_seconds,
                                   double end_seconds,
                                   const std::vector<float>& input,
                                   const std::vector<float>& output,
                                   int sample_rate_hz,
                                   size_t begin,
                                   size_t end) {
  SegmentSummary segment;
  segment.name = name;
  segment.start_seconds = start_seconds;
  segment.end_seconds = end_seconds;
  const std::vector<float> input_slice = SliceSamples(input, begin, end);
  const std::vector<float> output_slice = SliceSamples(output, begin, end);
  segment.input_metrics = ComputeMetrics(input_slice, sample_rate_hz);
  segment.output_metrics = ComputeMetrics(output_slice, sample_rate_hz);
  segment.worse_than_input_frames =
      CountWorseThanInputFrames(input_slice, output_slice, sample_rate_hz);
  return segment;
}

std::vector<SegmentSummary> BuildEqualSegments(
    const std::vector<std::string>& names,
    const std::vector<float>& input,
    const std::vector<float>& output,
    int sample_rate_hz) {
  std::vector<SegmentSummary> segments;
  if (names.empty() || input.empty() || output.empty()) {
    return segments;
  }

  const size_t usable_samples = std::min(input.size(), output.size());
  for (size_t index = 0; index < names.size(); ++index) {
    const size_t begin = (usable_samples * index) / names.size();
    const size_t end = (usable_samples * (index + 1)) / names.size();
    segments.push_back(BuildSegmentSummary(
        names[index],
        static_cast<double>(begin) / static_cast<double>(sample_rate_hz),
        static_cast<double>(end) / static_cast<double>(sample_rate_hz),
        input,
        output,
        sample_rate_hz,
        begin,
        end));
  }
  return segments;
}

std::vector<SegmentSummary> BuildRangeSegments(
    const std::vector<SegmentSpec>& specs,
    const std::vector<float>& input,
    const std::vector<float>& output,
    int sample_rate_hz) {
  std::vector<SegmentSummary> segments;
  if (specs.empty() || input.empty() || output.empty()) {
    return segments;
  }

  const size_t usable_samples = std::min(input.size(), output.size());
  const double duration =
      static_cast<double>(usable_samples) / static_cast<double>(sample_rate_hz);
  for (const SegmentSpec& spec : specs) {
    const double start_seconds = std::clamp(spec.start_seconds, 0.0, duration);
    const double end_seconds = std::clamp(spec.end_seconds, 0.0, duration);
    if (end_seconds <= start_seconds) {
      continue;
    }
    const size_t begin = static_cast<size_t>(
        std::llround(start_seconds * static_cast<double>(sample_rate_hz)));
    const size_t end = static_cast<size_t>(
        std::llround(end_seconds * static_cast<double>(sample_rate_hz)));
    segments.push_back(BuildSegmentSummary(
        spec.name,
        start_seconds,
        end_seconds,
        input,
        output,
        sample_rate_hz,
        std::min(begin, usable_samples),
        std::min(end, usable_samples)));
  }
  return segments;
}

bool IsSpeechSegment(const std::string& name) {
  return ContainsWord(name, "speech") || ContainsWord(name, "voice") ||
         ContainsWord(name, "talk");
}

double SafeReductionScore(double input_value, double output_value) {
  if (input_value <= 0.000001) {
    return output_value <= 0.000001 ? 100.0 : 0.0;
  }
  return ClampScore((1.0 - (output_value / input_value)) * 100.0);
}

ReplayScore ComputeReplayScore(const std::vector<SegmentSummary>& segments,
                               const AudioMetrics& output_metrics,
                               int callback_budget_misses,
                               int resampler_underruns,
                               int resampler_overruns,
                               int non_finite_samples) {
  ReplayScore score;
  double speech_sum = 0.0;
  double noise_sum = 0.0;
  int speech_count = 0;
  int noise_count = 0;

  for (const SegmentSummary& segment : segments) {
    if (IsSpeechSegment(segment.name)) {
      const double input_rms = std::max(segment.input_metrics.rms, 0.000001);
      const double ratio = segment.output_metrics.rms / input_rms;
      double segment_score = 100.0 - (std::abs(1.0 - ratio) * 180.0);
      if (segment.output_metrics.peak > segment.input_metrics.peak * 1.35) {
        segment_score -= 20.0;
      }
      if (segment.output_metrics.max_delta >
          std::max(0.12, segment.input_metrics.max_delta * 1.25)) {
        segment_score -= 20.0;
      }
      const int frame_count = std::max(1, segment.input_metrics.frame_count);
      segment_score -=
          std::min(25.0,
                   (static_cast<double>(segment.worse_than_input_frames) /
                    static_cast<double>(frame_count)) *
                       100.0);
      speech_sum += ClampScore(segment_score);
      speech_count++;
    } else {
      const double rms_reduction = SafeReductionScore(
          segment.input_metrics.rms,
          segment.output_metrics.rms);
      const double delta_reduction = SafeReductionScore(
          segment.input_metrics.max_delta,
          segment.output_metrics.max_delta);
      double segment_score = (rms_reduction * 0.65) + (delta_reduction * 0.35);
      if (segment.output_metrics.peak > segment.input_metrics.peak * 1.15) {
        segment_score -= 15.0;
      }
      const int frame_count = std::max(1, segment.input_metrics.frame_count);
      segment_score -=
          std::min(20.0,
                   (static_cast<double>(segment.worse_than_input_frames) /
                    static_cast<double>(frame_count)) *
                       60.0);
      noise_sum += ClampScore(segment_score);
      noise_count++;
    }
  }

  score.speech_preservation =
      speech_count == 0 ? 100.0 : speech_sum / static_cast<double>(speech_count);
  score.noise_reduction =
      noise_count == 0 ? 0.0 : noise_sum / static_cast<double>(noise_count);
  score.has_speech_segments = speech_count > 0;
  score.has_noise_segments = noise_count > 0;

  double artifact_safety = 100.0;
  artifact_safety -= std::min(35.0,
                              static_cast<double>(
                                  output_metrics.clipping_samples) *
                                  0.05);
  artifact_safety -= std::min(45.0,
                              static_cast<double>(non_finite_samples) * 1.0);
  artifact_safety -= std::min(30.0,
                              static_cast<double>(callback_budget_misses) *
                                  3.0);
  artifact_safety -= std::min(20.0,
                              static_cast<double>(
                                  resampler_underruns + resampler_overruns) *
                                  2.0);
  if (output_metrics.max_delta > 0.35) {
    artifact_safety -= 15.0;
  }
  score.artifact_safety = ClampScore(artifact_safety);
  score.artifact_safety_passed =
      score.artifact_safety >= 90.0 &&
      output_metrics.clipping_samples == 0 &&
      output_metrics.non_finite_samples == 0 &&
      non_finite_samples == 0;
  score.speech_safety_passed =
      (!score.has_speech_segments || score.speech_preservation >= 80.0) &&
      score.artifact_safety_passed;

  double candidate_score =
      (score.noise_reduction * 0.55) +
      (score.speech_preservation * 0.25) +
      (score.artifact_safety * 0.20);
  double candidate_cap = 100.0;
  if (!score.has_noise_segments) {
    candidate_cap = std::min(candidate_cap, 35.0);
  }
  if (!score.speech_safety_passed) {
    candidate_cap =
        std::min(candidate_cap, std::max(0.0, score.speech_preservation * 0.50));
  }
  if (!score.artifact_safety_passed) {
    candidate_cap =
        std::min(candidate_cap, std::max(0.0, score.artifact_safety * 0.70));
  }
  score.candidate_score = ClampScore(std::min(candidate_score, candidate_cap));
  score.overall = score.candidate_score;
  return score;
}

std::string MetricsJson(const AudioMetrics& metrics) {
  std::ostringstream json;
  json << std::fixed << std::setprecision(8);
  json << "{";
  json << "\"rms\":" << metrics.rms << ",";
  json << "\"peak\":" << metrics.peak << ",";
  json << "\"maxDelta\":" << metrics.max_delta << ",";
  json << "\"clippingSamples\":" << metrics.clipping_samples << ",";
  json << "\"nonFiniteSamples\":" << metrics.non_finite_samples << ",";
  json << "\"noisyFrames\":" << metrics.noisy_frames << ",";
  json << "\"deltaFrames\":" << metrics.delta_frames << ",";
  json << "\"frameCount\":" << metrics.frame_count;
  json << "}";
  return json.str();
}

std::string SegmentsJson(const std::vector<SegmentSummary>& segments) {
  std::ostringstream json;
  json << std::fixed << std::setprecision(8);
  json << "[";
  for (size_t index = 0; index < segments.size(); ++index) {
    const SegmentSummary& segment = segments[index];
    if (index > 0) {
      json << ",";
    }
    json << "{";
    json << "\"name\":\"" << EscapeJson(segment.name) << "\",";
    json << "\"startSeconds\":" << segment.start_seconds << ",";
    json << "\"endSeconds\":" << segment.end_seconds << ",";
    json << "\"inputMetrics\":" << MetricsJson(segment.input_metrics) << ",";
    json << "\"outputMetrics\":" << MetricsJson(segment.output_metrics)
         << ",";
    json << "\"worseThanInputFrames\":"
         << segment.worse_than_input_frames;
    json << "}";
  }
  json << "]";
  return json.str();
}

std::string ScoreJson(const ReplayScore& score) {
  std::ostringstream json;
  json << std::fixed << std::setprecision(2);
  json << "{";
  json << "\"speechPreservation\":" << score.speech_preservation << ",";
  json << "\"noiseReduction\":" << score.noise_reduction << ",";
  json << "\"artifactSafety\":" << score.artifact_safety << ",";
  json << "\"candidateScore\":" << score.candidate_score << ",";
  json << "\"hasSpeechSegments\":"
       << (score.has_speech_segments ? "true" : "false") << ",";
  json << "\"hasNoiseSegments\":"
       << (score.has_noise_segments ? "true" : "false") << ",";
  json << "\"speechSafetyPassed\":"
       << (score.speech_safety_passed ? "true" : "false") << ",";
  json << "\"artifactSafetyPassed\":"
       << (score.artifact_safety_passed ? "true" : "false") << ",";
  json << "\"overall\":" << score.overall;
  json << "}";
  return json.str();
}

std::string TuningJson(const ReplayOptions& options) {
  std::ostringstream json;
  json << std::fixed << std::setprecision(4);
  json << "{";
  json << "\"vadThreshold\":" << options.vad_threshold << ",";
  json << "\"speechGraceFrames\":" << options.speech_grace_frames << ",";
  json << "\"closedGain\":" << options.closed_gain << ",";
  json << "\"transientSensitivity\":" << options.transient_sensitivity << ",";
  json << "\"fastClose\":" << (options.fast_close ? "true" : "false");
  json << "}";
  return json.str();
}

void PrintUsage() {
  std::cerr
      << "Usage: intergalactic_rnnoise_replay "
      << "(--input input.wav | --fixture plosive-speech) "
      << "--output output-dir "
      << "[--mode clean|identity|off|tuned|prototype_suppression|prototype_suppression_v2] "
      << "[--label name] "
      << "[--sample-rate-hz hz] "
      << "[--segments speech=0-7.1,keyboard=7.1-14.3,clicks=14.3-21.4] "
      << "[--equal-segments speech,keyboard,clicks] "
      << "[--vad-threshold value] [--speech-grace-frames frames] "
      << "[--closed-gain value] [--transient-sensitivity value] "
      << "[--fast-close true|false]\n";
}

bool ParseArgs(int argc, char** argv, ReplayOptions* options) {
  std::string parse_error;
  for (int index = 1; index < argc; ++index) {
    const std::string arg = argv[index];
    auto next_value = [&]() -> std::string {
      if (index + 1 >= argc) {
        return "";
      }
      index++;
      return argv[index];
    };

    if (arg == "--input") {
      options->input_path = next_value();
    } else if (arg == "--fixture") {
      options->fixture = next_value();
    } else if (arg == "--output") {
      options->output_dir = next_value();
    } else if (arg == "--mode") {
      options->mode = next_value();
    } else if (arg == "--label") {
      options->label = next_value();
    } else if (arg == "--sample-rate-hz") {
      if (!ParseInt(next_value(), &options->fixture_sample_rate_hz) ||
          !IsSupportedReplaySampleRate(options->fixture_sample_rate_hz)) {
        std::cerr << "Invalid --sample-rate-hz; expected 8000-192000 Hz "
                     "and a 10 ms frame-aligned rate\n";
        return false;
      }
    } else if (arg == "--segments") {
      if (!ParseSegmentSpecs(next_value(), &options->segment_specs,
                             &parse_error)) {
        std::cerr << "Invalid --segments: " << parse_error << "\n";
        return false;
      }
    } else if (arg == "--equal-segments") {
      options->equal_segments = SplitCsv(next_value());
    } else if (arg == "--vad-threshold") {
      options->has_vad_threshold = ParseDouble(next_value(),
                                               &options->vad_threshold);
      if (!options->has_vad_threshold) {
        std::cerr << "Invalid --vad-threshold\n";
        return false;
      }
    } else if (arg == "--speech-grace-frames") {
      options->has_speech_grace_frames =
          ParseInt(next_value(), &options->speech_grace_frames);
      if (!options->has_speech_grace_frames) {
        std::cerr << "Invalid --speech-grace-frames\n";
        return false;
      }
    } else if (arg == "--closed-gain") {
      options->has_closed_gain = ParseDouble(next_value(),
                                             &options->closed_gain);
      if (!options->has_closed_gain) {
        std::cerr << "Invalid --closed-gain\n";
        return false;
      }
    } else if (arg == "--transient-sensitivity") {
      options->has_transient_sensitivity =
          ParseDouble(next_value(), &options->transient_sensitivity);
      if (!options->has_transient_sensitivity) {
        std::cerr << "Invalid --transient-sensitivity\n";
        return false;
      }
    } else if (arg == "--fast-close") {
      options->has_fast_close = ParseBool(next_value(), &options->fast_close);
      if (!options->has_fast_close) {
        std::cerr << "Invalid --fast-close\n";
        return false;
      }
    } else if (arg == "--help" || arg == "-h") {
      return false;
    } else {
      std::cerr << "Unknown argument: " << arg << "\n";
      return false;
    }
  }

  if (options->output_dir.empty()) {
    std::cerr << "--output is required\n";
    return false;
  }
  if (options->input_path.empty() == options->fixture.empty()) {
    std::cerr << "Specify exactly one of --input or --fixture\n";
    return false;
  }
  if (!options->fixture.empty() && options->fixture != "plosive-speech") {
    std::cerr << "Unsupported fixture: " << options->fixture << "\n";
    return false;
  }
  return true;
}

int ModeToNative(const std::string& mode, bool* enabled) {
  if (mode == "off") {
    *enabled = false;
    return ig::kRnnoisePipelineModeOff;
  }
  *enabled = true;
  if (mode == "identity") {
    return ig::kRnnoisePipelineModeIdentity;
  }
  if (mode == "tuned" || mode == "tuned_gate") {
    return ig::kRnnoisePipelineModeTunedGate;
  }
  if (mode == "prototype" ||
      mode == "prototype_suppression" ||
      mode == "prototype-suppression") {
    return ig::kRnnoisePipelineModePrototypeSuppression;
  }
  if (mode == "prototype2" ||
      mode == "prototype_v2" ||
      mode == "prototype-v2" ||
      mode == "prototype_suppression_v2" ||
      mode == "prototype-suppression-v2") {
    return ig::kRnnoisePipelineModePrototypeSuppressionV2;
  }
  return ig::kRnnoisePipelineModeCleanRnnoise;
}

}  // namespace

int main(int argc, char** argv) {
  ReplayOptions options;
  if (!ParseArgs(argc, argv, &options)) {
    PrintUsage();
    return 64;
  }

  WavData input;
  std::string error;
  if (!options.fixture.empty()) {
    input = BuildPlosiveSpeechFixture(options.fixture_sample_rate_hz);
  } else if (!ReadWavFile(options.input_path, &input, &error)) {
    std::cerr << "Could not read WAV input: " << error << "\n";
    return 65;
  }
  if (!IsSupportedReplaySampleRate(input.sample_rate_hz)) {
    std::cerr << "Input sample rate must be 8000-192000 Hz and divide into "
                 "10 ms frames: "
              << input.sample_rate_hz << "\n";
    return 66;
  }

  const int frame_size = input.sample_rate_hz / 100;
  const int usable_frames =
      static_cast<int>(input.mono_samples.size()) / frame_size;
  if (usable_frames <= 0) {
    std::cerr << "Input has no complete 10 ms frames\n";
    return 67;
  }
  const size_t usable_samples =
      static_cast<size_t>(usable_frames) * static_cast<size_t>(frame_size);
  if (usable_samples < input.mono_samples.size()) {
    input.mono_samples.resize(usable_samples);
  }

  std::filesystem::create_directories(options.output_dir);
  const std::string stages_dir =
      (std::filesystem::path(options.output_dir) / "stages").string();

  bool enabled = true;
  const int native_mode = ModeToNative(options.mode, &enabled);
  auto shared_state = std::make_shared<ig::ProcessorSharedState>();
  shared_state->enabled_requested.store(enabled);
  shared_state->pipeline_mode.store(native_mode);
  if (options.has_vad_threshold) {
    shared_state->reference_vad_threshold.store(
        std::clamp(options.vad_threshold, 0.50, 0.999));
  }
  if (options.has_speech_grace_frames) {
    shared_state->reference_speech_grace_frames.store(
        std::max(0, options.speech_grace_frames));
  }
  if (options.has_closed_gain) {
    shared_state->noise_gate_closed_gain.store(
        std::clamp(options.closed_gain, 0.0, 1.0));
  }
  if (options.has_transient_sensitivity) {
    shared_state->transient_sensitivity.store(
        std::clamp(options.transient_sensitivity, 0.0, 1.0));
  }
  if (options.has_fast_close) {
    shared_state->fast_close_enabled.store(options.fast_close);
  }
  shared_state->diagnostic_capture->Start(
      stages_dir,
      std::min(
          kMaxDiagnosticCaptureMs,
          static_cast<int>((static_cast<int64_t>(usable_samples) * 1000) /
                           input.sample_rate_hz)),
      ig::kRnnoiseDiagnosticStageAll);

  ig::RnnoiseCaptureProcessor processor(shared_state);
  processor.Initialize(input.sample_rate_hz, 1);

  std::vector<float> processed;
  processed.reserve(input.mono_samples.size());
  std::vector<float> frame_buffer(frame_size);
  const int num_bands = input.sample_rate_hz >= 48000 ? 3 : 1;
  for (int frame = 0; frame < usable_frames; ++frame) {
    const size_t offset = static_cast<size_t>(frame) * frame_size;
    std::copy(input.mono_samples.begin() + offset,
              input.mono_samples.begin() + offset + frame_size,
              frame_buffer.begin());
    for (float& sample : frame_buffer) {
      sample *= kWebRtcFloatS16Scale;
    }
    processor.Process(
        num_bands,
        frame_size,
        frame_size,
        frame_buffer.data());
    for (float& sample : frame_buffer) {
      sample /= kWebRtcFloatS16Scale;
    }
    processed.insert(
        processed.end(),
        frame_buffer.begin(),
        frame_buffer.end());
  }
  shared_state->diagnostic_capture->Stop();

  const std::string processed_path =
      (std::filesystem::path(options.output_dir) / "processed-output.wav")
          .string();
  if (!WriteWavFile(processed_path, processed, input.sample_rate_hz)) {
    std::cerr << "Could not write processed WAV\n";
    return 68;
  }

  const AudioMetrics input_metrics =
      ComputeMetrics(input.mono_samples, input.sample_rate_hz);
  const AudioMetrics output_metrics =
      ComputeMetrics(processed, input.sample_rate_hz);
  const int worse_frames = CountWorseThanInputFrames(
      input.mono_samples,
      processed,
      input.sample_rate_hz);
  const std::vector<SegmentSummary> segments = BuildEqualSegments(
      options.segment_specs.empty() ? options.equal_segments
                                    : std::vector<std::string>(),
      input.mono_samples,
      processed,
      input.sample_rate_hz);
  const std::vector<SegmentSummary> range_segments = BuildRangeSegments(
      options.segment_specs,
      input.mono_samples,
      processed,
      input.sample_rate_hz);
  const std::vector<SegmentSummary>& active_segments =
      options.segment_specs.empty() ? segments : range_segments;
  const ReplayScore score = ComputeReplayScore(
      active_segments,
      output_metrics,
      shared_state->callback_budget_misses.load(),
      shared_state->resampler_input_underruns.load() +
          shared_state->resampler_output_underruns.load(),
      shared_state->resampler_overruns.load(),
      shared_state->non_finite_samples.load());

  const std::string summary_json_path =
      (std::filesystem::path(options.output_dir) / "replay-summary.json")
          .string();
  {
    std::ofstream json(summary_json_path);
    json << std::fixed << std::setprecision(8);
    json << "{\n";
    json << "  \"label\":\"" << EscapeJson(options.label) << "\",\n";
    json << "  \"inputPath\":\"" << EscapeJson(options.input_path)
         << "\",\n";
    json << "  \"fixture\":\"" << EscapeJson(options.fixture) << "\",\n";
    json << "  \"mode\":\"" << EscapeJson(options.mode) << "\",\n";
    json << "  \"sampleRateHz\":" << input.sample_rate_hz << ",\n";
    json << "  \"durationSeconds\":"
         << (static_cast<double>(processed.size()) /
             static_cast<double>(input.sample_rate_hz))
         << ",\n";
    json << "  \"complete10msFrames\":" << usable_frames << ",\n";
    json << "  \"processedOutput\":\""
         << EscapeJson(processed_path) << "\",\n";
    json << "  \"stagesDirectory\":\"" << EscapeJson(stages_dir) << "\",\n";
    json << "  \"inputMetrics\":" << MetricsJson(input_metrics) << ",\n";
    json << "  \"outputMetrics\":" << MetricsJson(output_metrics) << ",\n";
    json << "  \"worseThanInputFrames\":" << worse_frames << ",\n";
    json << "  \"segments\":" << SegmentsJson(active_segments) << ",\n";
    json << "  \"score\":" << ScoreJson(score) << ",\n";
    json << "  \"tuning\":" << TuningJson(options) << ",\n";
    json << "  \"state\":{\n";
    json << "    \"framesProcessed\":"
         << shared_state->frames_processed.load() << ",\n";
    json << "    \"bypassFrames\":"
         << shared_state->bypass_frames.load() << ",\n";
    json << "    \"gatedFrames\":"
         << shared_state->gated_frames.load() << ",\n";
    json << "    \"resamplerUses\":"
         << shared_state->resampler_uses.load() << ",\n";
    json << "    \"resamplerInputUnderruns\":"
         << shared_state->resampler_input_underruns.load() << ",\n";
    json << "    \"resamplerOutputUnderruns\":"
         << shared_state->resampler_output_underruns.load() << ",\n";
    json << "    \"resamplerOverruns\":"
         << shared_state->resampler_overruns.load() << ",\n";
    json << "    \"resamplerMode\":\""
         << ig::RnnoiseResamplerModeToString(
                shared_state->last_resampler_mode.load())
         << "\",\n";
    json << "    \"pipelineMode\":\""
         << ig::RnnoisePipelineModeToString(
                shared_state->pipeline_mode.load())
         << "\",\n";
    json << "    \"processingApplied\":"
         << (shared_state->processing_applied.load() ? "true" : "false")
         << ",\n";
    json << "    \"identityFrames\":"
         << shared_state->identity_frames.load() << ",\n";
    json << "    \"prototypeStageFrames\":"
         << shared_state->prototype_stage_frames.load() << ",\n";
    json << "    \"prototypeTransientFrames\":"
         << shared_state->prototype_transient_frames.load() << ",\n";
    json << "    \"prototypeStationaryFrames\":"
         << shared_state->prototype_stationary_frames.load() << ",\n";
    json << "    \"prototypeSpeechProtectedFrames\":"
         << shared_state->prototype_speech_protected_frames.load() << ",\n";
    json << "    \"prototypeAdjustedSamples\":"
         << shared_state->prototype_adjusted_samples.load() << ",\n";
    json << "    \"prototypeNoiseFloorRms\":"
         << shared_state->prototype_noise_floor_rms.load() << ",\n";
    json << "    \"prototypeLastGain\":"
         << shared_state->prototype_last_gain.load() << ",\n";
    json << "    \"lastInputMin\":"
         << shared_state->last_input_min.load() << ",\n";
    json << "    \"lastInputMax\":"
         << shared_state->last_input_max.load() << ",\n";
    json << "    \"lastOutputMin\":"
         << shared_state->last_output_min.load() << ",\n";
    json << "    \"lastOutputMax\":"
         << shared_state->last_output_max.load() << ",\n";
    json << "    \"vadLowFrames\":"
         << shared_state->vad_low_frames.load() << ",\n";
    json << "    \"vadMidFrames\":"
         << shared_state->vad_mid_frames.load() << ",\n";
    json << "    \"vadHighFrames\":"
         << shared_state->vad_high_frames.load() << ",\n";
    json << "    \"inputClippingSamples\":"
         << shared_state->input_clipping_samples.load() << ",\n";
    json << "    \"outputClippingSamples\":"
         << shared_state->output_clipping_samples.load() << ",\n";
    json << "    \"outputLimiterSamples\":"
         << shared_state->output_limiter_samples.load() << ",\n";
    json << "    \"outputAntiAliasUses\":"
         << shared_state->output_antialias_uses.load() << ",\n";
    json << "    \"nonFiniteSamples\":"
         << shared_state->non_finite_samples.load() << ",\n";
    json << "    \"callbackAverageProcessingMs\":"
         << shared_state->callback_average_processing_ms.load() << ",\n";
    json << "    \"callbackMaxProcessingMs\":"
         << shared_state->callback_max_processing_ms.load() << ",\n";
    json << "    \"callbackBudgetMisses\":"
         << shared_state->callback_budget_misses.load() << ",\n";
    json << "    \"rnnoiseStateResets\":"
         << shared_state->rnnoise_state_resets.load() << ",\n";
    json << "    \"diagnosticCaptureFrames\":"
         << shared_state->diagnostic_capture->captured_frames() << ",\n";
    json << "    \"diagnosticCaptureDroppedFrames\":"
         << shared_state->diagnostic_capture->dropped_frames() << ",\n";
    json << "    \"diagnosticCaptureWrittenFiles\":"
         << shared_state->diagnostic_capture->written_files() << ",\n";
    json << "    \"diagnosticCaptureLastError\":\""
         << EscapeJson(shared_state->diagnostic_capture->last_error()) << "\"\n";
    json << "  }\n";
    json << "}\n";
  }

  const std::string summary_md_path =
      (std::filesystem::path(options.output_dir) / "replay-summary.md")
          .string();
  {
    std::ofstream md(summary_md_path);
    md << "# RNNoise Replay Summary\n\n";
    md << "- Label: `" << options.label << "`\n";
    md << "- Mode: `" << options.mode << "`\n";
    md << "- Input: `" << options.input_path << "`\n";
    if (!options.fixture.empty()) {
      md << "- Fixture: `" << options.fixture << "`\n";
    }
    md << "- Sample rate: `" << input.sample_rate_hz << " Hz`\n";
    md << "- Duration: `"
       << std::fixed << std::setprecision(2)
       << (static_cast<double>(processed.size()) /
           static_cast<double>(input.sample_rate_hz))
       << "s`\n";
    md << "- Complete 10 ms frames: `" << usable_frames << "`\n";
    md << "- Processed output: `" << processed_path << "`\n";
    md << "- Stage WAVs: `" << stages_dir << "`\n\n";
    md << "- Pipeline mode: `"
       << ig::RnnoisePipelineModeToString(
              shared_state->pipeline_mode.load())
       << "`\n";
    md << "- Processing applied: `"
       << (shared_state->processing_applied.load() ? "true" : "false")
       << "`\n";
    md << "- Identity frames: `" << shared_state->identity_frames.load()
       << "`\n\n";
    if (native_mode == ig::kRnnoisePipelineModePrototypeSuppression ||
        native_mode == ig::kRnnoisePipelineModePrototypeSuppressionV2) {
      md << "- Prototype stage frames: `"
         << shared_state->prototype_stage_frames.load() << "`\n";
      md << "- Prototype transient/stationary/speech-protected frames: `"
         << shared_state->prototype_transient_frames.load() << "` / `"
         << shared_state->prototype_stationary_frames.load() << "` / `"
         << shared_state->prototype_speech_protected_frames.load()
         << "`\n";
      md << "- Prototype adjusted samples: `"
         << shared_state->prototype_adjusted_samples.load() << "`\n";
      md << "- Prototype noise floor RMS / last gain: `"
         << shared_state->prototype_noise_floor_rms.load() << "` / `"
         << shared_state->prototype_last_gain.load() << "`\n\n";
    }
    md << "- Tuning: `vad=" << std::fixed << std::setprecision(3)
       << options.vad_threshold << ", grace=" << options.speech_grace_frames
       << ", gain=" << options.closed_gain
       << ", transient=" << options.transient_sensitivity
       << ", fastClose=" << (options.fast_close ? "true" : "false")
       << "`\n\n";
    md << "## Score\n\n";
    md << "| Candidate | Speech preservation | Noise reduction | Artifact safety | Speech gate | Safety gate | Noise evidence |\n";
    md << "| ---: | ---: | ---: | ---: | --- | --- | --- |\n";
    md << "| " << std::fixed << std::setprecision(1)
       << score.candidate_score << " | " << score.speech_preservation << " | "
       << score.noise_reduction << " | " << score.artifact_safety
       << " | " << (score.speech_safety_passed ? "pass" : "review")
       << " | " << (score.artifact_safety_passed ? "pass" : "review")
       << " | " << (score.has_noise_segments ? "yes" : "no")
       << " |\n\n";
    md << "## Metrics\n\n";
    md << "| Audio | RMS | Peak | Max delta | Clipping samples | Noisy frames | Delta frames |\n";
    md << "| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n";
    md << "| Input | " << input_metrics.rms << " | "
       << input_metrics.peak << " | " << input_metrics.max_delta << " | "
       << input_metrics.clipping_samples << " | "
       << input_metrics.noisy_frames << " | "
       << input_metrics.delta_frames << " |\n";
    md << "| Output | " << output_metrics.rms << " | "
       << output_metrics.peak << " | " << output_metrics.max_delta << " | "
       << output_metrics.clipping_samples << " | "
       << output_metrics.noisy_frames << " | "
       << output_metrics.delta_frames << " |\n\n";
    md << "- Frames where output RMS grew materially over input: `"
       << worse_frames << "`\n";
    md << "- Frames processed: `"
       << shared_state->frames_processed.load() << "`\n";
    md << "- Bypass/gated frames: `"
       << shared_state->bypass_frames.load() << "` / `"
       << shared_state->gated_frames.load() << "`\n";
    md << "- Resampler uses/underruns: `"
       << shared_state->resampler_uses.load() << "` / `"
       << shared_state->resampler_input_underruns.load() << "+"
       << shared_state->resampler_output_underruns.load() << "`\n";
    md << "- Input/output clipping samples: `"
       << shared_state->input_clipping_samples.load() << "` / `"
       << shared_state->output_clipping_samples.load() << "`\n";
    md << "- Limiter samples: `"
       << shared_state->output_limiter_samples.load() << "`\n";
    md << "- Callback average/max/budget misses: `"
       << shared_state->callback_average_processing_ms.load() << "ms` / `"
       << shared_state->callback_max_processing_ms.load() << "ms` / `"
       << shared_state->callback_budget_misses.load() << "`\n";

    if (!active_segments.empty()) {
      md << "\n## Segments\n\n";
      md << "| Segment | Seconds | Input RMS | Output RMS | Input peak | Output peak | Output max delta | Worse frames |\n";
      md << "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n";
      for (const SegmentSummary& segment : active_segments) {
        md << "| " << segment.name << " | "
           << std::fixed << std::setprecision(2)
           << segment.start_seconds << "-" << segment.end_seconds << " | "
           << segment.input_metrics.rms << " | "
           << segment.output_metrics.rms << " | "
           << segment.input_metrics.peak << " | "
           << segment.output_metrics.peak << " | "
           << segment.output_metrics.max_delta << " | "
           << segment.worse_than_input_frames << " |\n";
      }
    }
  }

  std::cout << "Wrote " << summary_json_path << "\n";
  std::cout << "Wrote " << summary_md_path << "\n";
  return 0;
}
