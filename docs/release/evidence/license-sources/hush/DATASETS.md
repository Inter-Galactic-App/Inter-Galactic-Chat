# Hush Dataset Provenance Note

Status: PROVENANCE NOTE RETAINED; PACKAGE GATED

Hush's model metadata and README identify the project/model artifact as
Apache-2.0, but the upstream project also documents training data with separate
dataset licenses and terms. Keep this note with release records and notices.

S&C reviewed the local Hush checkout and recorded that upstream dataset
documentation lists separately licensed training data, including DNS Challenge
under a Microsoft Research License and ESC-50 as CC BY-NC 3.0. The app package
does not include the raw training datasets or the demo WAV samples from the
local Hush checkout.

Before public release, final package/notice proof must retain:

- Hush Apache-2.0 license text, source URL, and source commit.
- DeepFilterNet attribution because Hush is built on DeepFilterNet3.
- This dataset-provenance caveat.
- Confirmation that no runtime model download or audio upload path was added.

Re-open S&C/legal review if release scope, store review, legal review, Weya
binaries, runtime model downloads, audio uploads, or stricter trained-weight
review requirements apply.
