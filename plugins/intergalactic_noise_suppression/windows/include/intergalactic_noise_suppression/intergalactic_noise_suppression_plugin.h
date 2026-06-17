#ifndef FLUTTER_PLUGIN_INTERGALACTIC_NOISE_SUPPRESSION_PLUGIN_H_
#define FLUTTER_PLUGIN_INTERGALACTIC_NOISE_SUPPRESSION_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define INTERGALACTIC_NOISE_SUPPRESSION_EXPORT __declspec(dllexport)
#else
#define INTERGALACTIC_NOISE_SUPPRESSION_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT void
IntergalacticNoiseSuppressionPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_initialize();

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_configure(double vad_threshold,
                                          int speech_grace_frames,
                                          double closed_gain,
                                          double transient_sensitivity,
                                          int fast_close_enabled);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_set_pipeline_mode(int mode);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_start_diagnostic_capture(
    const char* directory,
    int duration_ms,
    int stage_mask);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_start_tap_order_capture(
    const char* directory,
    int duration_ms,
    int stage_mask,
    int include_wasapi_sidecar,
    const char* wasapi_device_id);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_stop_diagnostic_capture();

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_set_enabled(int enabled);

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT int
intergalactic_noise_suppression_shutdown();

INTERGALACTIC_NOISE_SUPPRESSION_EXPORT const char*
intergalactic_noise_suppression_get_status_json();

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_INTERGALACTIC_NOISE_SUPPRESSION_PLUGIN_H_
