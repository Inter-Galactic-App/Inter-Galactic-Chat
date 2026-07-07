#ifndef RNNOISE_OS_SUPPORT_H
#define RNNOISE_OS_SUPPORT_H

#include <string.h>

#ifndef OPUS_COPY
#define OPUS_COPY(dst, src, n) \
  (memcpy((dst), (src), (n) * sizeof(*(dst)) + 0 * ((dst) - (src))))
#endif

#ifndef OPUS_MOVE
#define OPUS_MOVE(dst, src, n) \
  (memmove((dst), (src), (n) * sizeof(*(dst)) + 0 * ((dst) - (src))))
#endif

#ifndef OPUS_CLEAR
#define OPUS_CLEAR(dst, n) (memset((dst), 0, (n) * sizeof(*(dst))))
#endif

#endif
