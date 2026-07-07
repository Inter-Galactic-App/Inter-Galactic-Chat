RNNoise is vendored here for the Inter Galactic Windows noise-suppression
plugin.

Pinned source:
- Upstream mirror: https://github.com/xiph/rnnoise
- Tag: `v0.2`
- Git commit: `904a876dce1f9ab8860c0a5000ed151f9f6eef58`

Pinned model data:
- Source tarball: `https://media.xiph.org/rnnoise/models/rnnoise_data-0b50c45.tar.gz`
- Model version: `0b50c45`

Vendored files:
- `include/rnnoise.h`
- The minimal library source set from upstream `Makefile.am`
- `COPYING` and `README`

Notes:
- Inter Galactic currently vendors the full default model via `src/rnnoise_data.c`
  for better suppression quality.
- x86 RTCD / AVX-specific upstream sources are intentionally not enabled in this
  first integration to keep the native surface smaller and easier to audit.
