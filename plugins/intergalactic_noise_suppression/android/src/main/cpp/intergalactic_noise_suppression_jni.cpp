#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <unistd.h>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <mutex>
#include <string>
#include <vector>

extern "C" {
struct DFState;
DFState* df_create(const char* path, float atten_lim, const char* log_level);
size_t df_get_frame_length(DFState* state);
float df_process_frame(DFState* state, float* input, float* output);
void df_set_post_filter_beta(DFState* state, float beta);
void df_free(DFState* state);
}

namespace {
constexpr const char* kLogTag = "IGNoiseSuppression";

std::mutex g_mutex;
std::mutex g_control_mutex;
DFState* g_state = nullptr;
int g_frame_length = 0;

// DeepFilterNet's C API aborts the process on any initialization failure
// (df_create ends in Box::into_raw or a Rust panic; it never returns null), and
// the panic message goes to stderr, which Android discards. Without this pump
// the only artifact is a bare SIGABRT in df_create with no reason attached.
// Redirecting stderr into logcat is the only way to see why it failed.
int g_stderr_pipe[2] = {-1, -1};
bool g_stderr_redirected = false;

void* stderr_pump(void*) {
  char buffer[512];
  ssize_t count;
  while ((count = read(g_stderr_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
    while (count > 0 && (buffer[count - 1] == '\n' || buffer[count - 1] == '\r')) {
      --count;
    }
    buffer[count] = '\0';
    if (count > 0) {
      __android_log_write(ANDROID_LOG_ERROR, kLogTag, buffer);
    }
  }
  return nullptr;
}

// Deliberately unconditional rather than gated behind a diagnostics flag.
// DeepFilterNet is Rust: a panic prints to stderr and then aborts the process.
// On Android an app's stderr is discarded, so without this the single most
// useful artifact - the panic message explaining WHY df_create aborted - is
// gone precisely when it is needed, and all that survives is the abort guard
// noticing that a previous attempt never returned. A flag would have to be set
// before the crash it exists to explain, which is not a thing a field user can
// do. The cost is that unrelated process stderr also lands under this tag;
// since Android was discarding it anyway, that is strictly more information,
// only mislabelled.
void ensure_stderr_redirected() {
  if (g_stderr_redirected) return;
  if (pipe(g_stderr_pipe) != 0) return;

  // Every failure path below must undo the whole redirection, not just bail.
  // Leaving stderr pointing at a pipe with no reader is worse than not
  // redirecting at all: once the ~64KB pipe buffer fills, any write to stderr
  // blocks that thread forever - including the Rust panic this code exists to
  // capture. And leaving g_stderr_redirected false while the descriptors stay
  // open leaks two more on every nativeInitialize.
  const int saved_stderr = dup(STDERR_FILENO);

  auto abandon = [&]() {
    if (saved_stderr != -1) {
      dup2(saved_stderr, STDERR_FILENO);
      close(saved_stderr);
    }
    close(g_stderr_pipe[0]);
    close(g_stderr_pipe[1]);
    g_stderr_pipe[0] = -1;
    g_stderr_pipe[1] = -1;
  };

  setvbuf(stderr, nullptr, _IONBF, 0);
  if (dup2(g_stderr_pipe[1], STDERR_FILENO) == -1) {
    abandon();
    return;
  }
  pthread_t thread;
  if (pthread_create(&thread, nullptr, stderr_pump, nullptr) != 0) {
    abandon();
    return;
  }
  pthread_detach(thread);
  // The pump owns the read end; the write end lives on as STDERR_FILENO.
  if (saved_stderr != -1) close(saved_stderr);
  g_stderr_redirected = true;
}

DFState* detach_state() {
  std::lock_guard<std::mutex> lock(g_mutex);
  DFState* state = g_state;
  g_state = nullptr;
  g_frame_length = 0;
  return state;
}

void free_state(DFState* state) {
  if (state != nullptr) df_free(state);
}

std::string to_utf8(JNIEnv* env, jstring value) {
  if (value == nullptr) return {};
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) return {};
  std::string result(chars);
  env->ReleaseStringUTFChars(value, chars);
  return result;
}
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_chat_intergalactic_noise_1suppression_IntergalacticNoiseSuppressionNative_nativeInitialize(
    JNIEnv* env, jclass, jstring model_path, jint sample_rate_hz,
    jfloat attenuation_limit_db, jfloat post_filter_beta) {
  std::lock_guard<std::mutex> control_lock(g_control_mutex);
  ensure_stderr_redirected();
  free_state(detach_state());
  if (sample_rate_hz != 48000) return 0;
  const std::string path = to_utf8(env, model_path);
  if (path.empty()) return 0;

  // INFO, not WARN: these fire on every successful initialization, so WARN
  // misrepresents normal operation. The full path is deliberately not logged -
  // it is the app-private filesystem location, and logcat is readable well
  // beyond this process. The file name is enough to tell which model loaded.
  const size_t separator = path.find_last_of('/');
  const char* model_name =
      separator == std::string::npos ? path.c_str() : path.c_str() + separator + 1;
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "df_create begin model=%s atten_lim=%.2f", model_name,
                      static_cast<double>(attenuation_limit_db));
  DFState* state = df_create(path.c_str(), attenuation_limit_db, nullptr);
  __android_log_write(ANDROID_LOG_INFO, kLogTag, "df_create returned");
  if (state == nullptr) return 0;
  const int frame_length = static_cast<int>(df_get_frame_length(state));
  if (frame_length <= 0) {
    free_state(state);
    return 0;
  }
  df_set_post_filter_beta(state, post_filter_beta);
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_state = state;
    g_frame_length = frame_length;
  }
  return frame_length;
}

extern "C" JNIEXPORT jint JNICALL
Java_chat_intergalactic_noise_1suppression_IntergalacticNoiseSuppressionNative_nativeProcess(
    JNIEnv* env, jclass, jobject buffer, jint num_frames) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_state == nullptr || num_frames != g_frame_length) return 0;
  auto* samples = static_cast<float*>(env->GetDirectBufferAddress(buffer));
  const jlong capacity = env->GetDirectBufferCapacity(buffer);
  if (samples == nullptr || capacity <= 0 || capacity % sizeof(float) != 0) return 0;
  const size_t sample_count = static_cast<size_t>(capacity) / sizeof(float);
  if (sample_count < static_cast<size_t>(num_frames) ||
      sample_count % static_cast<size_t>(num_frames) != 0) return 0;
  const size_t channels = sample_count / static_cast<size_t>(num_frames);
  if (channels == 0 || channels > 2) return 0;

  std::vector<float> mono(static_cast<size_t>(num_frames), 0.0f);
  for (int frame = 0; frame < num_frames; ++frame) {
    for (size_t channel = 0; channel < channels; ++channel) {
      mono[frame] += samples[static_cast<size_t>(frame) * channels + channel];
    }
  }
  const float scale = 1.0f / static_cast<float>(channels);
  for (float& sample : mono) {
    sample *= scale;
    if (!std::isfinite(sample)) return 0;
  }
  std::vector<float> output(mono.size(), 0.0f);
  df_process_frame(g_state, mono.data(), output.data());
  for (int frame = 0; frame < num_frames; ++frame) {
    const float processed =
        std::isfinite(output[frame]) ? output[frame] : 0.0f;
    for (size_t channel = 0; channel < channels; ++channel) {
      samples[static_cast<size_t>(frame) * channels + channel] = processed;
    }
  }
  return 1;
}

extern "C" JNIEXPORT void JNICALL
Java_chat_intergalactic_noise_1suppression_IntergalacticNoiseSuppressionNative_nativeReset(
    JNIEnv*, jclass, jint) {
  std::lock_guard<std::mutex> control_lock(g_control_mutex);
  free_state(detach_state());
}

extern "C" JNIEXPORT void JNICALL
Java_chat_intergalactic_noise_1suppression_IntergalacticNoiseSuppressionNative_nativeShutdown(
    JNIEnv*, jclass) {
  std::lock_guard<std::mutex> control_lock(g_control_mutex);
  free_state(detach_state());
}
