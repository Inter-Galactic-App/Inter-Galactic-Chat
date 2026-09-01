/*
 * Keep the RNNoise C implementation available to the macOS pod through an
 * in-pod source file. CocoaPods does not reliably compile parent-directory
 * source globs for this local plugin layout.
 */
#include "../../third_party/rnnoise/src/celt_lpc.c"
#include "../../third_party/rnnoise/src/denoise.c"
#include "../../third_party/rnnoise/src/kiss_fft.c"
#include "../../third_party/rnnoise/src/nnet.c"
#include "../../third_party/rnnoise/src/nnet_default.c"
#include "../../third_party/rnnoise/src/parse_lpcnet_weights.c"
#include "../../third_party/rnnoise/src/pitch.c"
#include "../../third_party/rnnoise/src/rnn.c"
#include "../../third_party/rnnoise/src/rnnoise_data.c"
#include "../../third_party/rnnoise/src/rnnoise_tables.c"
