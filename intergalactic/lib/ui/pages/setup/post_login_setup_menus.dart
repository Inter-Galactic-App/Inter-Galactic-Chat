import 'package:intergalactic/ui/pages/setup/setup_menu.dart';

/// Builds the post-login setup queue.
///
/// Extracted from `MainPage` for one reason: the list is assembled from two
/// sources - what `main.dart` registered into `FirstTimeSetup.postLogin` at
/// startup, and what the caller adds for each account - and a menu present in
/// both was shown to the user TWICE in a single run. `NotificationPreviewPrivacySetup`
/// was, because `main.dart` registers it under the same condition the caller
/// was re-testing.
///
/// De-duplicating by runtime type is what makes that unrepresentable: a setup
/// menu is a one-time question, so asking the same KIND of question twice in
/// one queue is never right, however it got there.
List<SetupMenu> buildPostLoginSetupMenus({
  required List<SetupMenu> registered,
  required List<SetupMenu> perAccount,
}) {
  final seenTypes = <Type>{};
  final seenAccountMenus = <(Type, String)>{};
  final menus = <SetupMenu>[];
  for (final menu in [...registered, ...perAccount]) {
    // Per-account menus are the exception, but a narrower one than "not
    // de-duplicated": one per account is correct, so they are told apart by the
    // account they carry AS WELL AS by their type. Exempting them from the
    // check entirely would leave the same question asked twice for the same
    // account, which is the bug this function exists to make unrepresentable.
    if (menu is PerAccountSetupMenu) {
      if (seenAccountMenus.add((menu.runtimeType, menu.clientIdentifier))) {
        menus.add(menu);
      }
      continue;
    }
    if (seenTypes.add(menu.runtimeType)) {
      menus.add(menu);
    }
  }
  return menus;
}

/// A setup menu that is legitimately asked once PER ACCOUNT rather than once
/// per device, and so is exempt from the de-duplication above.
abstract class PerAccountSetupMenu implements SetupMenu {
  String get clientIdentifier;
}
