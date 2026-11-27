# Android core-library desugaring 2.1.5

## Component and licence

Android builds using `com.android.tools:desugar_jdk_libs:2.1.5` select the
core-library desugaring runtime. Its Maven declaration is
`GPL-2.0-only WITH Classpath-exception-2.0`.
The published [Maven JAR](https://dl.google.com/dl/android/maven2/com/android/tools/desugar_jdk_libs/2.1.5/desugar_jdk_libs-2.1.5.jar)
has SHA-256
`D8044BEFAE095781B9A80BF1FAA92EDC30382D75D437476784C1BF991598A976`.

Existing [Android Gradle evidence](../../../android-gradle/0.7.4+985/THIRD_PARTY_LICENSES.android-gradle.json)
records this coordinate and its configuration dependency. Its runtime POM hash
is `2E195880F15D4545C8D60B2D2CAC52201CCF98DB7A29DB2577AD5826A930FCCA`;
the configuration POM hash is
`B2099735B93905D6F01B52E136D1364280CD6A72C6E7EA3BE274A6C67703F2B4`.
These identify dependencies and declared terms, not every class in a later APK.

[LICENSE](LICENSE) is the complete verbatim GPLv2/Classpath text from the
immutable source revision below: 19274 bytes, SHA-256
`4B9ABEBC4338048A7C2DC184E9F800DEB349366BDF28EB23C2677A77B4C87726`.
It matches the text reached through the existing
[hosted notice inventory](https://app.ourgalaxy.space/third-party-notices/THIRD_PARTY_LICENSES.json)
and its upstream licence link. The application's About policy links include
that hosted notice route; this record does not establish offline notice access
or device behavior for a particular package.

## Immutable upstream source reference

Upstream [commit 73170c345e6a762fc6a1f0301bb15218850023ef](https://github.com/google/desugar_jdk_libs/commit/73170c345e6a762fc6a1f0301bb15218850023ef)
prepares the JDK11-based 2.1.5 release. At that revision:

- [VERSION_JDK11.txt](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/VERSION_JDK11.txt)
  declares 2.1.5.
- [DEPENDENCIES_JDK11.txt](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/DEPENDENCIES_JDK11.txt)
  selects `com.android.tools:desugar_jdk_libs_configuration:2.1.5`.
- [BUILD](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/BUILD)
  defines `maven_release_jdk11`, output `desugar_jdk_libs_jdk11.zip`, using
  those selectors and the `desugar_jdk_libs_jdk11` library target.
- [tools/build_maven_artifact.py](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/tools/build_maven_artifact.py)
  is the Maven packaging tool invoked by that target.

The inspected target can be selected with `bazel build maven_release_jdk11`.
This identifies an upstream target, not a complete tested environment recipe,
a build performed for this record, or proof that this revision produced the
published Maven JAR. Source-to-supplier correspondence is not independently
established solely by matching version selectors.

The pinned [Instant.java](https://github.com/google/desugar_jdk_libs/blob/73170c345e6a762fc6a1f0301bb15218850023ef/jdk11/src/java.base/share/classes/java/time/Instant.java)
header retains Oracle and/or its affiliates' copyright 2012/2018 and expressly
designates that file GPLv2-only with the Classpath exception. Exception
applicability is file-specific, not a blanket classification of unknown helpers.

## Delivery boundary

This is a source and licence reference, not a newly published app or library
source archive. A package containing desugared code must be associated with
its applicable source, build material and recipient notice/source-access route;
this reference alone is not proof of complete corresponding-source delivery.
The configuration JAR contains helper classes and declares BSD-3-Clause.
Their presence in an input JAR does not establish that any particular helper
survives transformation into an APK; their conveyed scope remains undetermined.
