# Feature-specific libDF crate rosters

Status: **SOURCE-ROSTER COMPLETE — dependency closures are represented by the normalized crate roster derived from the retained post-build DeepFilterNet lockfile. 107 selected crate packages retain their own licence/notice files; `crunchy` and `realfft` are mapped to canonical SPDX MIT text through their exact upstream/package manifest declarations. Do not use this directory as a final package notice or source-offer record.**

The normalized roster records the captured Windows and Android feature selections: 95 Windows package/version pairs, 105 Android pairs, and 109 in their union. `crate-license-roster.json` maps every pair to its platform scope, registry/path source, declared licence expression, manifest hash, and copied licence/notice file hashes. Host-specific command captures are retained as private byte-preserved evidence and are intentionally not published here.

| Evidence | SHA-256 |
| --- | --- |
| `crate-license-roster.json` | `B9F198325EA0264409721FC30D0D3876DD21EF788EC96D644A088B19942717F7` |

`crate-license-texts/` preserves the exact files found in each selected crate source. `crunchy 0.2.2` and `realfft 3.3.0` declare `MIT` in their exact crate manifests but contain no licence/notice text file in either the crate archive or its matching upstream Git tree. Their manifest/original-manifest/README declaration bytes and upstream revisions are retained in `LICENSE-SOURCE.md`. `SPDX-MIT.txt` is the canonical text explicitly mapped to those exact SPDX declarations; it is not represented as a file that either crate shipped.

This is source-build evidence for the Windows `df.dll` and the three committed Android JNI inputs. It does not prove the distinct release-candidate payload digests, select a licence arm for every multi-licensed package, or establish a public source-offer obligation.
