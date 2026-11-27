import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('matrixHistoryVisibilityAllowsInviteSharing', () {
    test('allows only shared and world-readable history visibility', () {
      expect(
        matrixHistoryVisibilityAllowsInviteSharing(
          matrix.HistoryVisibility.shared,
        ),
        isTrue,
      );
      expect(
        matrixHistoryVisibilityAllowsInviteSharing(
          matrix.HistoryVisibility.worldReadable,
        ),
        isTrue,
      );
      expect(
        matrixHistoryVisibilityAllowsInviteSharing(
          matrix.HistoryVisibility.invited,
        ),
        isFalse,
      );
      expect(
        matrixHistoryVisibilityAllowsInviteSharing(
          matrix.HistoryVisibility.joined,
        ),
        isFalse,
      );
      expect(matrixHistoryVisibilityAllowsInviteSharing(null), isFalse);
    });
  });

  group('matrixHistorySessionPayloadIsShareable', () {
    test('recognizes MSC3061 shared-history room-key payloads', () {
      expect(
        matrixHistorySessionPayloadIsShareable(const {
          matrixSharedHistoryFlag: true,
        }),
        isTrue,
      );
      expect(
        matrixHistorySessionPayloadIsShareable(const {'shared_history': true}),
        isTrue,
      );
      expect(
        matrixHistorySessionPayloadIsShareable(const {
          matrixSharedHistoryFlag: false,
        }),
        isFalse,
      );
      expect(matrixHistorySessionPayloadIsShareable(const {}), isFalse);
    });
  });

  group('matrixHistoryBundleDeclaredFileSizesAreSafe', () {
    test('requires bounded plaintext and encrypted sizes', () {
      expect(
        matrixHistoryBundleDeclaredFileSizesAreSafe(const {
          'size': 1024,
          'encrypted_size': 2048,
        }),
        isTrue,
      );
      expect(
        matrixHistoryBundleDeclaredFileSizesAreSafe(const {
          'size': 6 * 1024 * 1024,
          'encrypted_size': 2048,
        }),
        isFalse,
      );
      expect(
        matrixHistoryBundleDeclaredFileSizesAreSafe(const {
          'size': 1024,
          'encrypted_size': 6 * 1024 * 1024,
        }),
        isFalse,
      );
      expect(
        matrixHistoryBundleDeclaredFileSizesAreSafe(const {'size': 1024}),
        isFalse,
      );
    });
  });

  group('matrixHistoryShouldImportLatePendingBundle', () {
    test('imports late bundles only after the room is joined', () {
      expect(
        matrixHistoryShouldImportLatePendingBundle(
          roomIsJoined: false,
          acceptedInviteKnown: true,
          acceptedInviterUserId: '@alice:example.test',
          bundleSenderUserId: '@alice:example.test',
        ),
        isFalse,
      );
      expect(
        matrixHistoryShouldImportLatePendingBundle(
          roomIsJoined: true,
          acceptedInviteKnown: true,
          acceptedInviterUserId: '@alice:example.test',
          bundleSenderUserId: '@alice:example.test',
        ),
        isTrue,
      );
    });

    test('keeps known accepted invite sender as the late-import boundary', () {
      expect(
        matrixHistoryShouldImportLatePendingBundle(
          roomIsJoined: true,
          acceptedInviteKnown: true,
          acceptedInviterUserId: '@alice:example.test',
          bundleSenderUserId: '@mallory:example.test',
        ),
        isFalse,
      );
      expect(
        matrixHistoryShouldImportLatePendingBundle(
          roomIsJoined: true,
          acceptedInviteKnown: false,
          acceptedInviterUserId: null,
          bundleSenderUserId: '@alice:example.test',
        ),
        isTrue,
      );
    });
  });

  group('matrixHistoryShouldAutoShareRequestedKey', () {
    test('allows active joined full-history encrypted eligible requests', () {
      expect(
        matrixHistoryShouldAutoShareRequestedKey(
          requestCanceled: false,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: true,
          deviceEligible: true,
        ),
        isTrue,
      );
    });

    test('rejects requests outside the full-history policy boundary', () {
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: false,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: false,
          requesterIsJoined: true,
          deviceEligible: true,
        ),
        'history_visibility_not_shared',
      );
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: false,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: false,
          deviceEligible: true,
        ),
        'requester_not_joined',
      );
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: false,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: true,
          deviceEligible: false,
        ),
        'requesting_device_not_eligible',
      );
    });

    test('uses the same history permission boundary as invite bundles', () {
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: false,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: true,
          deviceEligible: true,
        ),
        isNull,
      );
    });

    test('does not auto-answer canceled or self-device requests', () {
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: true,
          requesterIsSelf: false,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: true,
          deviceEligible: true,
        ),
        'request_canceled',
      );
      expect(
        matrixHistoryAutoKeyShareSkipReason(
          requestCanceled: false,
          requesterIsSelf: true,
          roomIsE2EE: true,
          visibilityAllowsSharing: true,
          requesterIsJoined: true,
          deviceEligible: true,
        ),
        'requester_is_self',
      );
    });
  });

  group('MatrixHistoryShareReport deferrals', () {
    // The break-glass flow prompts the user to approve an ineligible device
    // and only then attempts the send. A deferral there is not a decision
    // about that device - the encryption store was released and did not come
    // back - so it must not be counted with, or read like, the refusals. The
    // report is what the user is shown when the dialog closes.
    MatrixHistoryShareReport report() =>
        MatrixHistoryShareReport(targetUserIds: <String>['@a:example.org']);

    test('a deferral is counted and explained, apart from the refusals', () {
      final text = (report()..deferredRequests = 2).toMultilineString();

      expect(text, contains('Deferred (storage resuming): 2'));
      expect(
        text,
        contains('Nothing was refused'),
        reason:
            'the count alone reads as another kind of ignored request; the '
            'user needs to know a retry will work',
      );
      expect(text, contains('request the keys again'));
    });

    test('explains nothing about deferrals when there were none', () {
      final text = report().toMultilineString();

      // The count line is always printed - it is the explanation that is
      // conditional, so the name says "explains", not "says".
      expect(text, contains('Deferred (storage resuming): 0'));
      expect(text, isNot(contains('Nothing was refused')));
      expect(
        text,
        isNot(contains('request the keys again')),
        reason:
            'the remediation sentence is the actionable half of the note; a '
            'report that always printed it would tell the user to retry when '
            'nothing was deferred and there is nothing to retry for',
      );
    });

    test('a deferral is not an ignored request', () {
      final text =
          (report()
                ..deferredRequests = 1
                ..ineligibleRequestsIgnored = 0
                ..blockedRequestsIgnored = 0)
              .toMultilineString();

      expect(text, contains('Ineligible requests ignored: 0'));
      expect(text, contains('Blocked requests ignored:    0'));
      expect(text, contains('Deferred (storage resuming): 1'));
    });
  });

  group('matrixHistoryResolveShareTargets', () {
    test('infers the only other joined member when no target is provided', () {
      final result = matrixHistoryResolveShareTargets(
        explicitTargetUserIds: const <String>[],
        joinedUserIds: const <String>[
          '@alice:example.test',
          '@bob:example.test',
        ],
        selfUserId: '@alice:example.test',
      );

      expect(result.canProceed, isTrue);
      expect(result.inferredSingleTarget, isTrue);
      expect(result.targetUserIds, const <String>['@bob:example.test']);
    });

    test('requires an explicit target when multiple joined members exist', () {
      final result = matrixHistoryResolveShareTargets(
        explicitTargetUserIds: const <String>[],
        joinedUserIds: const <String>[
          '@alice:example.test',
          '@bob:example.test',
          '@charlie:example.test',
        ],
        selfUserId: '@alice:example.test',
      );

      expect(result.canProceed, isFalse);
      expect(result.issue, contains('2 other joined members'));
    });

    test('rejects display names or partial ids before sharing keys', () {
      final result = matrixHistoryResolveShareTargets(
        explicitTargetUserIds: const <String>['Bob'],
        joinedUserIds: const <String>[
          '@alice:example.test',
          '@bob:example.test',
        ],
        selfUserId: '@alice:example.test',
      );

      expect(result.canProceed, isFalse);
      expect(result.issue, contains('not full Matrix user IDs'));
    });

    test('rejects users that are not currently joined', () {
      final result = matrixHistoryResolveShareTargets(
        explicitTargetUserIds: const <String>['@mallory:example.test'],
        joinedUserIds: const <String>[
          '@alice:example.test',
          '@bob:example.test',
        ],
        selfUserId: '@alice:example.test',
      );

      expect(result.canProceed, isFalse);
      expect(result.issue, contains('not currently joined'));
    });
  });
}
