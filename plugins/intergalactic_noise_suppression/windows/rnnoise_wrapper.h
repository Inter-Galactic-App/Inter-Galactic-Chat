#ifndef INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_WRAPPER_H_
#define INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_WRAPPER_H_

#ifdef __cplusplus
extern "C" {
#endif

typedef struct IntergalacticRnnoiseState IntergalacticRnnoiseState;

IntergalacticRnnoiseState* intergalactic_rnnoise_create(void);
void intergalactic_rnnoise_destroy(IntergalacticRnnoiseState* state);
int intergalactic_rnnoise_process_frame(IntergalacticRnnoiseState* state,
                                        const float* input,
                                        float* output);
float intergalactic_rnnoise_process_frame_with_vad(
    IntergalacticRnnoiseState* state,
    const float* input,
    float* output);
int intergalactic_rnnoise_frame_size(void);

#ifdef __cplusplus
}
#endif

#endif  // INTERGALACTIC_NOISE_SUPPRESSION_WINDOWS_RNNOISE_WRAPPER_H_
