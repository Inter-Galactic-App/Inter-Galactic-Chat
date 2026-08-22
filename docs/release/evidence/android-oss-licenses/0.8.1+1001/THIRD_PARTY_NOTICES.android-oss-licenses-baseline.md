# Android Google OSS Licenses Baseline

Generated: 2026-08-05T20:00:17Z
Build mode: fcm
Version tag: v0.8.1+1001
Status: complete

This baseline temporarily applies Google's `oss-licenses-plugin` and `play-services-oss-licenses` SDK, runs the release OSS license generation task, copies the generated artifacts, and restores the Gradle files.
Google documents that this tool scans app POM dependencies and includes the transitive open-source libraries used by Google Play services libraries compiled into the app.
Use the companion Android Gradle evidence as the authoritative shipped runtime dependency graph. The Google OSS plugin dependency list is retained as plugin output and may include helper/plugin coordinates or versions that differ from `releaseRuntimeClasspath`.

## Comparison

- Gradle evidence modules: 236
- Gradle evidence missing licenses: 4
- Google baseline generated files: 18
- Parsed Google baseline entry names: 1
- Parsed Google dependency modules: 1
- Result: google_baseline_generated_runtime_graph_not_authoritative
- Note: Google OSS dependencies.json is retained as plugin output; Android Gradle evidence remains authoritative for shipped runtime module coordinates and versions.

## Gradle Tasks

- `:app:releaseOssLicensesTask`

## Generated Files

| Copied file | Source file | Size | SHA-256 |
| --- | --- | ---: | --- |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__res__debugOssLicensesTask__raw__third_party_license_metadata` | `intergalactic/build/app/generated/res/debugOssLicensesTask/raw/third_party_license_metadata` | 26 | `fd829a671bedfe3f960f0d3b3c102643870e0106f158fd5ae741fc2abe26804e` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__res__debugOssLicensesTask__raw__third_party_licenses` | `intergalactic/build/app/generated/res/debugOssLicensesTask/raw/third_party_licenses` | 127 | `7902d9cd199bae0822f49e0001499623efcc76db57b71cf06904f78f4c907929` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__res__releaseOssLicensesTask__raw__third_party_license_metadata` | `intergalactic/build/app/generated/res/releaseOssLicensesTask/raw/third_party_license_metadata` | 8196 | `bad49e54e05bb4046790708201ecd0f41250761c40b6ffee9aeb491e51335fda` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__res__releaseOssLicensesTask__raw__third_party_licenses` | `intergalactic/build/app/generated/res/releaseOssLicensesTask/raw/third_party_licenses` | 474208 | `05943a56dab0ea50f56d1327f9de1a66d80db357b104e954cf7065e233784198` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__third_party_licenses__debug__dependencies.json` | `intergalactic/build/app/generated/third_party_licenses/debug/dependencies.json` | 96 | `39578b6472d05aa9386236b87ac47a736ea0b13f212a1cecc97300fffccf1a7b` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/generated__third_party_licenses__release__dependencies.json` | `intergalactic/build/app/generated/third_party_licenses/release/dependencies.json` | 28228 | `2647f4bcb84f3f294d909a4904245b0e2d49697119cc4166b6923621e6230576` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged_res__debug__mergeDebugResources__raw_third_party_license_metadata.flat` | `intergalactic/build/app/intermediates/merged_res/debug/mergeDebugResources/raw_third_party_license_metadata.flat` | 168 | `cd40ab034106c5338b665b61bb7b0c621b600b818cb7aa8da83e6938ca492d35` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged_res__debug__mergeDebugResources__raw_third_party_licenses.flat` | `intergalactic/build/app/intermediates/merged_res/debug/mergeDebugResources/raw_third_party_licenses.flat` | 252 | `ec99e47a9d4eb79d05bf5b219e88cab74b76df491b28f259f340ad4b991d72e6` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged_res__release__mergeReleaseResources__raw_keep_third_party_licenses.xml.flat` | `intergalactic/build/app/intermediates/merged_res/release/mergeReleaseResources/raw_keep_third_party_licenses.xml.flat` | 644 | `370db4eb83b15f672d8916eaf572672687308ca2df0af99e65ca3cf76a07557f` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged_res__release__mergeReleaseResources__raw_third_party_license_metadata.flat` | `intergalactic/build/app/intermediates/merged_res/release/mergeReleaseResources/raw_third_party_license_metadata.flat` | 8336 | `6e6bfc80bee36b15474e83c895cdab1f637bf74e7d5bd511bd259a3ec0489043` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged_res__release__mergeReleaseResources__raw_third_party_licenses.flat` | `intergalactic/build/app/intermediates/merged_res/release/mergeReleaseResources/raw_third_party_licenses.flat` | 474332 | `4c7785e69467425955e08220acb78a331a989ec9423dec53c7598bba068430fa` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged-not-compiled-resources__release__raw__keep_third_party_licenses.xml` | `intergalactic/build/app/intermediates/merged-not-compiled-resources/release/raw/keep_third_party_licenses.xml` | 468 | `609f653b27e5ce8075f79185bbe0c4f445de5f16c1a91fad72b7c0e62492f5b7` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged-not-compiled-resources__release__raw__third_party_license_metadata` | `intergalactic/build/app/intermediates/merged-not-compiled-resources/release/raw/third_party_license_metadata` | 8196 | `bad49e54e05bb4046790708201ecd0f41250761c40b6ffee9aeb491e51335fda` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__merged-not-compiled-resources__release__raw__third_party_licenses` | `intergalactic/build/app/intermediates/merged-not-compiled-resources/release/raw/third_party_licenses` | 474208 | `05943a56dab0ea50f56d1327f9de1a66d80db357b104e954cf7065e233784198` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__packaged_res__debug__packageDebugResources__raw__third_party_license_metadata` | `intergalactic/build/app/intermediates/packaged_res/debug/packageDebugResources/raw/third_party_license_metadata` | 26 | `fd829a671bedfe3f960f0d3b3c102643870e0106f158fd5ae741fc2abe26804e` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__packaged_res__debug__packageDebugResources__raw__third_party_licenses` | `intergalactic/build/app/intermediates/packaged_res/debug/packageDebugResources/raw/third_party_licenses` | 127 | `7902d9cd199bae0822f49e0001499623efcc76db57b71cf06904f78f4c907929` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__packaged_res__release__packageReleaseResources__raw__third_party_license_metadata` | `intergalactic/build/app/intermediates/packaged_res/release/packageReleaseResources/raw/third_party_license_metadata` | 8196 | `bad49e54e05bb4046790708201ecd0f41250761c40b6ffee9aeb491e51335fda` |
| `docs/release/evidence/android-oss-licenses/0.8.1+1001/generated-files/intermediates__packaged_res__release__packageReleaseResources__raw__third_party_licenses` | `intergalactic/build/app/intermediates/packaged_res/release/packageReleaseResources/raw/third_party_licenses` | 474208 | `05943a56dab0ea50f56d1327f9de1a66d80db357b104e954cf7065e233784198` |

## Parsed Baseline Entries

- Debug License Info

## Parsed Google OSS Plugin Dependency Modules

These module ids come from Google's generated dependencies.json; use Android Gradle evidence for shipped runtime versions.

- `absent:absent:absent`
