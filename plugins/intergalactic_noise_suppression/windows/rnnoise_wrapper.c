#include "rnnoise_wrapper.h"

#include <stdlib.h>

#include "../third_party/rnnoise/include/rnnoise.h"

struct IntergalacticRnnoiseState {
  DenoiseState* denoise_state;
};

IntergalacticRnnoiseState* intergalactic_rnnoise_create(void) {
  IntergalacticRnnoiseState* state =
      (IntergalacticRnnoiseState*)malloc(sizeof(IntergalacticRnnoiseState));
  if (state == NULL) {
    return NULL;
  }

  state->denoise_state = rnnoise_create(NULL);
  if (state->denoise_state == NULL) {
    free(state);
    return NULL;
  }

  return state;
}

void intergalactic_rnnoise_destroy(IntergalacticRnnoiseState* state) {
  if (state == NULL) {
    return;
  }

  if (state->denoise_state != NULL) {
    rnnoise_destroy(state->denoise_state);
  }

  free(state);
}

int intergalactic_rnnoise_process_frame(IntergalacticRnnoiseState* state,
                                        const float* input,
                                        float* output) {
  if (state == NULL || state->denoise_state == NULL || input == NULL ||
      output == NULL) {
    return 0;
  }

  rnnoise_process_frame(state->denoise_state, output, input);
  return 1;
}

float intergalactic_rnnoise_process_frame_with_vad(
    IntergalacticRnnoiseState* state,
    const float* input,
    float* output) {
  if (state == NULL || state->denoise_state == NULL || input == NULL ||
      output == NULL) {
    return -1.0f;
  }

  return rnnoise_process_frame(state->denoise_state, output, input);
}

int intergalactic_rnnoise_frame_size(void) {
  return rnnoise_get_frame_size();
}
