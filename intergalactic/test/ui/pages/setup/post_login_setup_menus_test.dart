import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/setup/post_login_setup_menus.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';

/// REVIEW finding, 2026-09-06: the post-login queue offered the preview-privacy
/// choice TWICE.
///
/// `main.dart` registers `NotificationPreviewPrivacySetup()` into
/// `FirstTimeSetup.postLogin` under `shouldShowNotificationPreviewPrivacyChoice`,
/// and `MainPage` spread `postLogin` and then appended a second instance under
/// the same condition. One list build, both entries, so the user answered the
/// same question twice in one run.
///
/// Deleting the append fixes the instance. This pins the CLASS of bug: a setup
/// menu is a one-time question, so the same kind of question may not appear
/// twice in one queue however it got there - including from a future caller
/// that does not know what `main.dart` already registered.
void main() {
  test('a menu registered at startup is not asked again by the caller', () {
    final menus = buildPostLoginSetupMenus(
      registered: [_PreviewPrivacyMenu()],
      perAccount: [_PreviewPrivacyMenu()],
    );

    expect(menus.whereType<_PreviewPrivacyMenu>(), hasLength(1));
  });

  test('duplicates among the registered menus are collapsed too', () {
    final menus = buildPostLoginSetupMenus(
      registered: [
        _PreviewPrivacyMenu(),
        _UpdateCheckerMenu(),
        _PreviewPrivacyMenu(),
      ],
      perAccount: const [],
    );

    expect(menus, hasLength(2));
  });

  test('distinct menus are all kept, in order', () {
    final menus = buildPostLoginSetupMenus(
      registered: [_PreviewPrivacyMenu(), _UpdateCheckerMenu()],
      perAccount: const [],
    );

    expect(menus.map((menu) => menu.runtimeType), [
      _PreviewPrivacyMenu,
      _UpdateCheckerMenu,
    ]);
  });

  // The exception that makes the rule usable. The mute migration is asked once
  // per Matrix account, so two of them is correct and must survive - collapsing
  // by type alone would silently migrate only the first account.
  test('per-account menus are kept one per account', () {
    final menus = buildPostLoginSetupMenus(
      registered: const [],
      perAccount: [
        _AccountMenu('@a:example.org'),
        _AccountMenu('@b:example.org'),
      ],
    );

    expect(menus, hasLength(2));
    expect(
      menus.whereType<_AccountMenu>().map((menu) => menu.clientIdentifier),
      ['@a:example.org', '@b:example.org'],
    );
  });

  test('a per-account menu is not collapsed against a device-wide one', () {
    final menus = buildPostLoginSetupMenus(
      registered: [_PreviewPrivacyMenu()],
      perAccount: [_AccountMenu('@a:example.org')],
    );

    expect(menus, hasLength(2));
  });

  // The exemption above is narrow, and this is where its edge is. Being exempt
  // from de-duplication BY TYPE is not the same as being exempt from
  // de-duplication: the same question for the same account is a duplicate by
  // the definition at the top of this file, and the account is what tells two
  // per-account menus apart.
  //
  // Not reachable from the caller in main_page.dart, which builds one menu per
  // entry of clientManager.clients and so cannot repeat an identifier. That is
  // exactly the assumption this pins - the header claims the guarantee holds
  // "however it got there", and until this test the per-account branch did not
  // keep it.
  test('the same question is not asked twice for one account', () {
    final menus = buildPostLoginSetupMenus(
      registered: const [],
      perAccount: [
        _AccountMenu('@a:example.org'),
        _AccountMenu('@a:example.org'),
      ],
    );

    expect(
      menus,
      hasLength(1),
      reason:
          'two menus of one kind for one account is the same question twice, '
          'which is what this function exists to make unrepresentable',
    );
  });

  test('one repeated account does not drop a different account', () {
    // The failure mode of a key that is too COARSE, guarded from the other
    // side: collapsing per-account menus by type alone would keep only the
    // first account and silently skip the rest.
    final menus = buildPostLoginSetupMenus(
      registered: const [],
      perAccount: [
        _AccountMenu('@a:example.org'),
        _AccountMenu('@a:example.org'),
        _AccountMenu('@b:example.org'),
      ],
    );

    expect(
      menus.whereType<_AccountMenu>().map((menu) => menu.clientIdentifier),
      ['@a:example.org', '@b:example.org'],
    );
  });

  test('two per-account KINDS for one account are both kept', () {
    // The failure mode of a key that is too NARROW in the other direction:
    // keying on the account alone would collapse two unrelated questions that
    // happen to concern the same account.
    final menus = buildPostLoginSetupMenus(
      registered: const [],
      perAccount: [
        _AccountMenu('@a:example.org'),
        _OtherAccountMenu('@a:example.org'),
      ],
    );

    expect(menus, hasLength(2));
  });
}

class _StubMenu implements SetupMenu {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewPrivacyMenu extends _StubMenu {}

class _UpdateCheckerMenu extends _StubMenu {}

class _AccountMenu implements PerAccountSetupMenu {
  _AccountMenu(this.clientIdentifier);

  @override
  final String clientIdentifier;

  @override
  Widget builder(BuildContext context) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A SECOND per-account kind. Without it the account-scoped tests above cannot
/// tell a key of (type, account) from a key of account alone.
class _OtherAccountMenu extends _AccountMenu {
  _OtherAccountMenu(super.clientIdentifier);
}
