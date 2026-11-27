import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/native_licenses.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/subplatforms/subplatforms.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/public_release_links.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:intergalactic/utils/app_icon/app_icon_utils.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:vodozemac/vodozemac.dart' as vod;
import 'package:intl/intl.dart' as intl;

class SettingsCategoryAbout implements SettingsCategory {
  static const tabIdAbout = "app.about";

  String get labelSettingsAppInfo => Intl.message(
    "About",
    name: "labelSettingsAppInfo",
    desc: "Label for the app info settings page",
  );

  @override
  List<SettingsTab> get tabs => List.from([
    SettingsTab(
      id: tabIdAbout,
      label: labelSettingsAppInfo,
      icon: Icons.info_outline,
      makeScrollable: false,
      searchKeywords: const [
        "version",
        "license",
        "build",
        "source",
        "support",
        "privacy",
        "terms",
        "report abuse",
        "account deletion",
        "community guidelines",
        "third-party notices",
        "third party licenses",
        "asset provenance",
      ],
      pageBuilder: (context) {
        return const _AppInfo();
      },
    ),
  ]);

  static Widget info(BuildContext context) {
    const linkStyle = TextStyle(decoration: TextDecoration.underline);

    return SizedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              tiamat.Text.label(BuildConfig.buildFingerprintDisplay),
              const tiamat.Text.label(" · "),
              Text.rich(
                TextSpan(
                  style: linkStyle,
                  text: "Original Source",
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(
                      Uri.parse(BuildConfig.originalSourceUrl),
                      context: context,
                    ),
                ),
              ),
              const tiamat.Text.label(" · "),
              Text.rich(
                TextSpan(
                  style: linkStyle,
                  text: "Original License",
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(
                      Uri.parse(
                        "${BuildConfig.originalSourceUrl}/blob/main/LICENSE",
                      ),
                      context: context,
                    ),
                ),
              ),
              const tiamat.Text.label(" · "),
              Text.rich(
                TextSpan(
                  style: linkStyle,
                  text: "Open Source Licenses",
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      // LicenseRegistry only knows about Dart packages, so the
                      // bundled native binaries have to register themselves.
                      // Idempotent, and doing it here rather than at startup
                      // keeps the cost off every launch for a page most users
                      // never open.
                      NativeLicenses.register();
                      showLicensePage(context: context);
                    },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              ...PublicReleaseLinks.policyLinks.map(
                (link) => Text.rich(
                  TextSpan(
                    style: linkStyle,
                    text: link.title,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () =>
                          LinkUtils.open(link.uri, context: context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: "Inter Galactic is a modified fork of "),
                TextSpan(
                  style: linkStyle,
                  text: BuildConfig.originalApp,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(
                      Uri.parse(BuildConfig.originalSourceUrl),
                      context: context,
                    ),
                ),
                const TextSpan(text: " by "),
                TextSpan(
                  style: linkStyle,
                  text: BuildConfig.originalCreator,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LinkUtils.open(
                      Uri.parse(BuildConfig.originalWebsiteUrl),
                      context: context,
                    ),
                ),
                TextSpan(
                  text:
                      ". This fork was modified on ${BuildConfig.forkNoticeDate} and remains distributed under ${BuildConfig.licenseName}.",
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  String? get title => null;
}

class _AppInfo extends StatefulWidget {
  const _AppInfo();

  @override
  State<_AppInfo> createState() => _AppInfoState();
}

class _AppInfoState extends State<_AppInfo> {
  BaseDeviceInfo? deviceInfo;
  @override
  void initState() {
    super.initState();
    loadDeviceInfo();
  }

  Future<void> loadDeviceInfo() async {
    var info = await DeviceInfoPlugin().deviceInfo;
    setState(() {
      deviceInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  AppIconUtils.transparentCroppedAssetPath(),
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Flexible(
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.largeTitle(BuildConfig.appName),
                      const tiamat.Text.labelEmphasised(
                        BuildConfig.VERSION_TAG,
                      ),
                      tiamat.Text.labelLow(BuildConfig.buildFingerprintDisplay),
                      tiamat.Text.labelLow(
                        "Built: " +
                            intl.DateFormat(
                              intl.DateFormat.YEAR_MONTH_DAY,
                            ).format(BuildConfig.BUILD_DATE),
                      ),
                      if (deviceInfo != null)
                        Row(
                          spacing: 10,
                          children: [
                            if (deviceInfo!.data["name"] is String)
                              tiamat.Text.labelLow(
                                deviceInfo!.data["name"]!.toString(),
                              ),
                            if (deviceInfo!.data["version"] is String)
                              tiamat.Text.labelLow(
                                deviceInfo!.data["version"]!.toString(),
                              ),
                            if (PlatformUtils.isLinux)
                              tiamat.Text.labelLow(PlatformUtils.displayServer),
                            if (PlatformUtils.desktopEnvironment != null)
                              tiamat.Text.labelLow(
                                PlatformUtils.desktopEnvironment!,
                              ),
                          ],
                        ),
                      if (Subplatforms.subplatform != null)
                        tiamat.Text.labelLow(Subplatforms.subplatform!.name),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(getEncryptionInfo()),
                      if (preferences.developerMode.value)
                        tiamat.Text.labelLow(commandLineArgs.join(" ")),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: tiamat.IconButton(
                      icon: Icons.copy,
                      onPressed: copySystemInfo,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCategoryAbout.info(context),
      ],
    );
  }

  String getEncryptionInfo() {
    var info = getVodozemacVersion();
    info ??= "No encryption library found";
    return info;
  }

  String? getVodozemacVersion() {
    try {
      var initialized = vod.isInitialized();
      if (initialized) {
        return "Vodozemac Initialized";
      }

      return null;
    } catch (exception) {
      return null;
    }
  }

  void copySystemInfo() {
    var data =
        """
<details open>
<summary>Device Information</summary>
<br>

**Device**
App: ${BuildConfig.app} (fork of ${BuildConfig.originalApp} by ${BuildConfig.originalCreator})
Platform: `${BuildConfig.PLATFORM}`
Version: `${BuildConfig.VERSION_TAG}`
Git Hash: `${BuildConfig.GIT_HASH}`
Detail: `${BuildConfig.buildDetailDisplay}`
Build Timestamp: `${BuildConfig.BUILD_DATE.millisecondsSinceEpoch} (${intl.DateFormat(intl.DateFormat.YEAR_MONTH_DAY).format(BuildConfig.BUILD_DATE)})`

**System Info**
${deviceInfo?.data["name"] is String ? "Name: `${deviceInfo!.data["name"]}`" : ""}
${deviceInfo?.data["version"] is String ? "Version: `${deviceInfo!.data["version"]}`" : ""}
${deviceInfo?.data["product"] is String ? "Product: `${deviceInfo!.data["product"]}`" : ""}
${PlatformUtils.isLinux ? "Display Server: `${PlatformUtils.displayServer}`" : ""}
${PlatformUtils.desktopEnvironment != null ? "Desktop Environment: `${PlatformUtils.desktopEnvironment}`" : ""}
${Subplatforms.subplatform != null ? "Subplatform: `${Subplatforms.subplatform!.name}`" : ""}
</details>
""";

    Clipboard.setData(ClipboardData(text: data));
  }
}
