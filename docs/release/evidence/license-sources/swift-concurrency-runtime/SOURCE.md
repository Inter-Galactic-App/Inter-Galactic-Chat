# Swift concurrency back-deployment runtime

## Component and delivery scope

`libswift_Concurrency.dylib` is the Apple Swift concurrency back-deployment
runtime embedded in the iOS application bundle by Xcode. It was measured in
the retained `0.8.1+1003` and `0.8.1+1004` IPA candidates.

| Candidate | IPA SHA-256 | App-bundle runtime SHA-256 | SwiftSupport runtime SHA-256 |
| --- | --- | --- | --- |
| `0.8.1+1003` | `7040c3690a61c7118e0ac3e3759f3898898388e5b720690acb9bbcf506483507` | `168c3877ec038bd8bd90092d990294643ca6ce36e69a1eb5eade9a1262d3bbde` | `45211caa644bf80ba71543dd0e46c98f91066495125ccd2f59fceec2b42a5cae` |
| `0.8.1+1004` | `78827124525bc03adcc07de9c5818135e3595df6e7850a6f05426254e7ce4493` | `c401df30f4f62479133c6266b386f398cceadf5a0b7ddee33bed3b05b0b40d5c` | `45211caa644bf80ba71543dd0e46c98f91066495125ccd2f59fceec2b42a5cae` |

The two application-bundle copies are each 557,584 bytes. The corresponding
`SwiftSupport/iphoneos/libswift_Concurrency.dylib` copy is 7,741,808 bytes in
both candidates. Its embedded build strings identify Apple Swift 5.7.2
(`swiftlang-5.7.2.135.5`, Apple clang 14.0.0).

## Upstream source and licence capture

- Upstream: <https://github.com/swiftlang/swift>
- Release tag: [`swift-5.7.2-RELEASE`](https://github.com/swiftlang/swift/tree/swift-5.7.2-RELEASE)
- Tag commit: `0c49059f0b058ec9e75d655ec1be9e6a64d7372e`
- Captured upstream file: [`LICENSE.txt`](LICENSE.txt)
- `LICENSE.txt` SHA-256: `770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55`

The captured file is Apache License 2.0 followed by the Swift Runtime Library
Exception. The exception covers portions embedded in a binary product as a
result of compiling source with the software and permits redistribution without
the attribution otherwise required by Apache 2.0 sections 4(a), 4(b), and 4(d).

## Recorded routing

For the measured compiler-embedded iOS runtime, the Runtime Library Exception
is the applicable notice route. No additional in-app licence asset or
corresponding-source offer is added solely for this permissive runtime. The
candidate-specific hashes remain required whenever the embedded runtime changes.
