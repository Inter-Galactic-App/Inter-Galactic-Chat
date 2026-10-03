# Rust standard-library evidence for the libDF runtime

The recorded local builds of `df.dll` and the Android `libdf.so` inputs used
`rustc 1.94.1`, commit
`e408947bfd200af42db322daf0fadfe7e26d3bd1`. The Rust standard library is
linked into these Rust native binaries and is therefore included in the libDF
recipient notice in addition to the 109 Cargo package/version pairs.

| Text | Bytes | SHA-256 |
| --- | ---: | --- |
| `Apache-2.0.txt` | 10,280 | `074E6E32C86A4C0EF8B3ED25B721CA23ACA83DF277CD88106EF7177C354615FF` |
| `MIT.txt` | 1,078 | `B85DCD3E453D05982552C52B5FC9E0BDD6D23C6F8E844B984A88AF32570B0CC0` |

The files are byte-preserved from that toolchain's distributed
`share/doc/rust/licenses/` directory. The compiler revision is the evidence
boundary; a later installed toolchain must not replace these texts without a
new runtime measurement. Upstream source is the Rust project at
<https://github.com/rust-lang/rust/tree/e408947bfd200af42db322daf0fadfe7e26d3bd1>.

The standard library declares `Apache-2.0 OR MIT`. Both texts are reproduced
in the composed recipient notice; this record does not elect one licence arm
or make a corresponding-source-offer conclusion.
