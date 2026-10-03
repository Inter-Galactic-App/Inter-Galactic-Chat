# iOS patched dart-vodozemac 0.5.0 source record

This record identifies the modified iOS source variant. It is not a public
corresponding-source archive or a claim that an iOS release contains it.

Upstream is `famedly/dart-vodozemac` tag `0.5.0`, commit
`1bdded7dd13d26b3f77c4287c9321f7cf924dec9`, tree
`ef7825610cc462cc16b48d950959ab7325b52d5c`. The repository-root and
`rust/` AGPL-3.0 LICENSE files are byte-identical, SHA-256
`499b339f40cfa26e7bb430bab2674c596422bbbef211a9c455fefaa130dcfdc5`.
The exact AGPL text is also retained in the structured inventory's
`flutter_vodozemac` and `vodozemac` `license_text` fields; this source record
does not replace those bytes with a generic template.

The complete modification is the tracked
`intergalactic/ios/patches/dart-vodozemac/0001-feat-ios-port-bounded-backup-event-decrypt-to-0.5.0.patch`,
SHA-256 `243a925e41af50ffee95004d4043f2cb3512abf45f88c95a1d6c67c545d96975`.
The patch directory's manifest pins every changed file's before/after SHA-256
and the post-patch tree `111243677b895622b8a0659f55ec20e451420f23`.
That directory's README and `prepare.py` are the build instructions. This is an
upstream-source-plus-patch route, not an upstream-unmodified or pub-cache
route. Rust vodozemac 0.9.0 and flutter_rust_bridge 2.11.1 remain pinned;
the added direct `serde_json` edge still resolves 1.0.140 and by itself does
not change the recorded Rust crate roster.

The iOS notification extension and Runner both force-load the generated Rust
archive when built with this variant. The current corresponding-source index
does not list an iOS release archive for it.

The unchanged hosted lock describes the current non-iOS/default package
resolution; it does not identify the patched iOS source tree.
