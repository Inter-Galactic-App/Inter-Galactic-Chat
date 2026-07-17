# Desktop Native Notice Evidence - 0.8.0+992

This directory is a supplemental, post-release engineering receipt for the
Windows libwebrtc.dll distributed in Inter Galactic 0.8.0+992.

- Public app source checkout: v0.8.0+992 at 3b8ac7ad0414701da4fc53f5656d34b937caf764.
- Released DLL SHA-256: C96E0575C23C94F32640FBE69EC62AE05F1A13EA646E5051A832336678C97ADD.
- Native notice SHA-256: 03A872AC0D3811DDD06BD71AC73340623B6BBAB1B0794BC9EA72247623C9FCE6.
- Original source-manifest SHA-256: 2FEDC18280D1F9738DF4540C21DAE808E02D9312B935318FDF4E23F3E83AD3CA.
- Sanitized public-manifest SHA-256: C9F72A783B15AB0B6185A3651D37062EB27565B5EEE706D0D14942EA34B625B9.
- Components covered: 30, including the libwebrtc
  wrapper, WebRTC, FFmpeg, OpenH264, and libvpx.
- The released DLL matches the retained GN build output byte-for-byte.

THIRD_PARTY_NOTICES.desktop-native.txt is the user-facing supplemental
notice. desktop-native-component-receipt.json ties that notice to the public
app source tag, native source commits, dependency pins, build arguments, build
graph, released DLL, installer/package/source artifacts, and notice hash.

REVIEW source proof is recorded in source-archive-equivalence.json. All 2,142
files from the public release tag are present in the source archive: 290 are
byte-identical and 1,852 match after deterministic CRLF normalization. There
are no content mismatches. The archive also contains seven inventoried
historical public release artifacts under dist/. The public app, WebRTC Core,
and libwebrtc wrapper commits and license files were reachable at the exact
revisions recorded by the receipt.

This evidence does not modify the already-published installer and is not a
legal determination. S&C approved the corrected notice and receipt, and REVIEW
approved the source archive/tag and public native-source chain. User-accessible
publication and inclusion in the next Windows package remain open.
