import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REVIEW, 2026-09-12 (queue row "Hush is the only defence against TV
/// dialogue, and it is off by default"): a throwaway pump to prove this page
/// actually mounts and renders (no test file existed for it at all before
/// this). Guards two things:
///
/// 1. Moving Hush out of VoipDeveloperSettings into the normal
///    VoipSettingsPage build so it is reachable without Developer mode.
/// 2. The reset that returns the microphone to the Enhanced-only baseline
///    when Developer mode is off. That reset used to also zero Hush - which
///    is correct while Hush is a hidden developer diagnostic, and wrong the
///    moment it becomes a normal-settings preference: a user turning Hush on
///    with Developer mode off (the only way to reach it now) would have it
///    reset back off on the very next onSettingChanged broadcast, which the
///    toggle's own preference write fires. Confirmed here that it survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    NoiseSuppressionService.debugSupportsRnnoiseTuning = true;
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  tearDown(() {
    NoiseSuppressionService.debugSupportsRnnoiseTuning = null;
  });

  // The real settings shell scrolls this page; the test surface does not, so
  // every pump here wraps it in one to avoid an unrelated RenderFlex overflow
  // from a page this long rendered at the default 800x600 test viewport.
  Widget subject() => const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: VoipSettingsPage())),
  );

  testWidgets(
    'Hush is visible on the normal (non-developer) VoIP settings page',
    (tester) async {
      await tester.pumpWidget(subject());
      await tester.pump();

      expect(
        find.text('Hush voice isolation'),
        findsOneWidget,
        reason:
            'Hush must be reachable without turning on Developer mode - '
            'that was the whole point of moving it',
      );
    },
  );

  testWidgets(
    'turning Hush on with Developer mode off does not get silently reset '
    'back off',
    (tester) async {
      await tester.pumpWidget(subject());
      await tester.pump();

      expect(globals.preferences.developerMode.value, isFalse);

      final hushToggle = tester.widget<BooleanPreferenceToggle>(
        find.byWidgetPredicate(
          (widget) =>
              widget is BooleanPreferenceToggle &&
              widget.title == 'Hush voice isolation',
        ),
      );
      await hushToggle.preference.set(true);
      // The reset this guards against runs off onSettingChanged, which
      // set() above just fired - pump to let that listener's async reset
      // (if it incorrectly fired) complete before asserting.
      await tester.pump();
      await tester.pump();

      expect(
        globals
            .preferences
            .voipNoiseSuppressionDeepFilterNetHushSuppression
            .value,
        isTrue,
        reason:
            'Hush is a normal-settings preference now and must survive '
            'Developer mode being off, same as every other toggle on this '
            'page - it must not be swept up in the developer-diagnostics '
            'reset that (correctly) still zeroes the transient click guard',
      );
    },
  );
}
