# Windows Native Runtime Evidence — 0.8.1+1003

## Scope

This is an artefact-first inventory record for the current Windows release
payload. It supplies the seven `native_components` records required by
`tools/release/native-payload-inventory.json`; it does **not** decide broader
licence sufficiency or source-offer obligations.

The observed payload is a current development build, not a public release.
The SHA-256 values below identify what was measured. A release candidate must
run the native-payload gate against its own fresh runner payload; no retained
development or desktop copy may stand in for that check.

The extracted `data/flutter_assets/NOTICES.Z` in this payload has SHA-256
`16AA55B070DD07010F977BBEB38C33D66A2B2D0640FF0BE26A93A925F968366F`.
It contains Flutter/ICU, ANGLE, SwiftShader, Vulkan and zlib licence material.
It does not name Direct3D Compiler or WebView2.

## Direct3D Compiler

- `d3dcompiler_47.dll`: 4,891,080 bytes,
  `5653BC7B0E2701561464EF36602FF6171C96BFFE96E4C3597359CD7ADDCBA88A`.
- Version resource: `10.0.20348.1 (WinBuild.160101.0800)`; Microsoft-signed.
- The game-capture CMake path links `D3DCompiler`. Microsoft documents
  `D3DCOMPILER_47.DLL` as an application-local Windows SDK redistributable.
- [Microsoft's DirectX guidance](https://learn.microsoft.com/en-us/windows/win32/directx-sdk--august-2009-)
  confirms that this Windows SDK DLL may be distributed application-local.
- The original Windows SDK package, REDIST record, and exact licence terms from
  which this particular DLL was staged were not retained. The Windows in-app
  LicenseRegistry entry identifies the shipped component and this limitation; it
  does not assert an exact Microsoft terms route or restate vendor terms.

## Flutter engine and ICU

- `flutter_windows.dll`: 20,802,048 bytes,
  `D3B43A11850159AC1E1F73BDF0CAA8DB728A958467EF49B72C5772EECD3E95F4`.
- `data/icudtl.dat`: 862,304 bytes,
  `998367809A821D595928089C197B3F7959F0420F81F79D4D0DAEE53378492ED5`.
- The installed Flutter SDK identifies Flutter 3.41.1 and engine
  `3452d735bd38224ef2db85ca763d862d6326b17f`. Its release engine DLL has the
  same hash as the measured payload. The SDK's `license.windows_flutter.md`
  links that exact engine revision and its BSD-3-Clause distribution licence.
- ICU notices are present in `NOTICES.Z`; no standalone ICU version was asserted
  from `icudtl.dat`.

## ANGLE and SwiftShader

### ANGLE

- `libEGL.dll`: 472,904 bytes,
  `B2590BD0692F0381FC45C20BF1C7F7F713C9EA19C7EA6BAB62EFDD1FADC4EAAC`.
- `libGLESv2.dll`: 7,414,088 bytes,
  `620BB6E38D7ED6C760A0CF4A8EB6A8F64B259B96FF286551CD32CEFC6C35CA39`.
  Both are Google-signed and report ANGLE `2.1.18844`, git hash `2693b03eba82`.
### SwiftShader

- `vk_swiftshader.dll`: 4,808,008 bytes,
  `4F33EEA716491972CB1AD123A78ACEF485F852581130D3F3A98A1981009004F2`;
  product version `5.0.0`.
- `NOTICES.Z` contains BSD-style and Apache-2.0 ANGLE notices and Apache-2.0
  SwiftShader notices. SwiftShader's upstream project identifies Apache-2.0 as
  its project licence. The SwiftShader PE resource does not provide an upstream
  revision, so none is inferred.

## Vulkan loader

- `vulkan-1.dll`: 872,776 bytes,
  `3BE9A95DD9019AA1ACA47ADE26F5C1C7C0047F3CF6F633D586C9EC0D3B459566`.
- Version resource: `1.0.1111.2222.Dev Build`; it does not identify a source
  revision. `NOTICES.Z` contains Apache-2.0 Vulkan loader/header notices.
- The upstream [Khronos Vulkan Loader](https://github.com/KhronosGroup/Vulkan-Loader)
  is the provenance route. Do not convert the development version string into a
  source pin without separate evidence.

## WebView2 loader

- `Webview2Loader.dll`: 137,640 bytes,
  `C4674ACF95F0800793A4A6D61132ADF5DFA694C218E482D86093494C4E84100A`;
  product version `1.0.992.28`, Microsoft-signed.
- It is byte-identical to `desktop_webview_window` 0.2.3's package-pinned x64
  binary. That package is locked to mixin-flutter-plugins commit
  `82c19ad6ee5ac2b2acac6001d3e0cbefb90f1e22`, whose Windows CMake configuration
  explicitly bundles the loader.
- [NuGet's exact 1.0.992.28 licence page](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.992.28/License)
  provides the BSD-3-Clause text, and Microsoft documents that the matching
  loader DLL is shipped with the app. The current Flutter notice bundle does
  not name WebView2; the app instead bundles
  `assets/licenses/Microsoft-WebView2-BSD-3-Clause.txt` (1,487 bytes,
  SHA-256 `9995174528dba139ca753d02d8667dbec49f65ab17e65c643a914f2b58cfb4a2`)
  and registers it for the Windows in-app license page. Its line endings follow
  the app's existing LF asset convention; its legal text is from that exact
  package's `LICENSE.txt`.

## zlib

- `zlib.dll`: 203,264 bytes,
  `82D5BF175CF882AC9AFC1558B416E674606D055966BC09529076B28A498FC0E4`.
- There is no PE version resource. The Flutter notice bundle contains zlib
  material, but it does not prove an upstream revision for this DLL.
- Android's separately measured, statically linked zlib 1.2.12 must not be
  copied into this Windows record.

## Follow-up boundary

This file proves payload identity and the available provenance/notice route.
The Windows in-app LicenseRegistry now renders the Direct3D Compiler component
disclosure and retained-evidence limitation, plus the WebView2 BSD-3-Clause
text. It does not establish that this presentation
was exercised in a packaged Windows app: a fresh release candidate still needs
the packaged-notice gate and a manual About → Open Source Licenses smoke.
