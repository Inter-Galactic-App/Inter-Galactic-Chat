import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';

/// IOS request, 2026-09-03: let mobile keep message text in notifications while
/// turning image previews off.
///
/// `showMediaInNotifications` was already honoured on iOS - the NSE policy
/// snapshot reads it and emits `show_media` - but the toggle that sets it lived
/// in a section gated to desktop, so on a phone the preference was live and
/// unreachable. The only way to stop images was the Private preset, which also
/// removes the text.
///
/// These tests drive `notificationSearchEntries` with an explicit platform flag
/// rather than reading the ambient platform. The first version of this suite
/// branched on the real platform, which meant that on a Windows runner every
/// mobile assertion was skipped and a mutation breaking the mobile index stayed
/// green. Passing the flag makes both shapes reachable from any host.
void main() {
  List<SettingsSearchEntry> entriesFor({required bool desktop}) {
    return SettingsCategoryApp.notificationSearchEntries(
      supportsDesktopOptions: desktop,
    );
  }

  List<SettingsSearchEntry> imageEntries({required bool desktop}) {
    return entriesFor(
      desktop: desktop,
    ).where((entry) => entry.title.toLowerCase().contains('image')).toList();
  }

  group('mobile', () {
    test('indexes the standalone image control under Notification previews', () {
      final images = imageEntries(desktop: false);

      expect(images, hasLength(1));
      expect(images.single.title, 'Show images in notifications');
      expect(
        images.single.section,
        'Notification previews',
        reason:
            'on mobile the control is standalone, not inside the desktop-only '
            'Appearance section',
      );
    });

    test('does not index the desktop-only Appearance section', () {
      final sections = entriesFor(
        desktop: false,
      ).map((entry) => entry.section).toSet();

      expect(
        sections,
        isNot(contains('Appearance')),
        reason:
            'the Appearance section is gated to desktop in '
            'NotificationSettingsPage, so indexing it on mobile points search '
            'at a section that never renders',
      );
    });

    test('does not index the desktop body-formatting or URL controls', () {
      final titles = entriesFor(
        desktop: false,
      ).map((entry) => entry.title).toList();

      expect(titles, isNot(contains('Message body formatting')));
      expect(titles, isNot(contains('Preview URLs')));
      expect(
        titles,
        isNot(contains('Show images')),
        reason:
            'the desktop title must not leak onto mobile alongside the mobile '
            'one',
      );
    });
  });

  group('desktop', () {
    test('keeps the Appearance section and its three controls', () {
      final titles = entriesFor(desktop: true).map((e) => e.title).toList();

      expect(titles, contains('Message body formatting'));
      expect(titles, contains('Show images'));
      expect(titles, contains('Preview URLs'));
    });

    test('does not index the mobile-only control', () {
      expect(
        entriesFor(desktop: true).map((e) => e.title),
        isNot(contains('Show images in notifications')),
      );
    });

    test('indexes exactly one image control', () {
      expect(imageEntries(desktop: true), hasLength(1));
    });
  });

  group('shared', () {
    test('both platforms keep the entries that are not platform-specific', () {
      for (final desktop in [true, false]) {
        final titles = entriesFor(desktop: desktop).map((e) => e.title);
        expect(titles, contains('Notification mode'));
        expect(titles, contains('Room and space overrides'));
      }
    });

    test('the word a user types reaches the control on both platforms', () {
      for (final desktop in [true, false]) {
        expect(
          imageEntries(desktop: desktop).single.keywords,
          contains('images'),
        );
      }
    });
  });
}
