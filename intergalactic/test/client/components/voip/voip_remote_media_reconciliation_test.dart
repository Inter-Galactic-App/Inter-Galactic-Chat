// Coverage for the reconciliation policy *after* it was widened from
// microphone audio to every remote publication kind (P0-3).
//
// `voip_remote_audio_reconciliation_test.dart` still owns the microphone-audio
// behaviour and is deliberately untouched, so the two files together prove the
// widening added kinds without moving the audio path.
//
// Two themes run through this file.
//
// **The tautology.** `RemoteTrackPublication.subscribed` is defined as
// `subscriptionAllowed && track != null` (livekit_client-2.5.4
// `publication/remote.dart:68-72` over `publication/track_publication.dart:59`),
// so it is guaranteed false the instant a publication appears. A
// `!subscribed -> subscribe` rule therefore fires on every publication at
// publish time and detects nothing — which is exactly what the audio
// reconciler's only observed field repair was. The policy's `trackSubscribed`
// input is now the app's own receive switch (`publication.enabled`), and the
// "no media has arrived" case is expressed as a *duration* through
// [VoipRemoteMediaAttachMonitor] instead.
//
// **The state the app creates itself.** CallView disables and unsubscribes
// off-screen screen shares by default, which produces the detached publication
// in which the SDK stops emitting mute/unmute. A widened reconciler that did
// not know about that would resubscribe every hidden screen share on every
// sweep.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';

void main() {
  group('VoipRemoteAudioReconciliationPolicy across publication kinds', () {
    test('a camera publication with no stream object is built, not '
        'subscribed', () {
      // The join path discards the publications it creates for participants
      // already in the room, and TrackPublishedEvent is emitted only while the
      // room is `connected`. Both produce exactly this state: the publication
      // is present and healthy, and nothing rendered it.
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(streamObjectExists: false),
      );

      expect(result.action, VoipRemoteAudioRepairAction.rebuildStreamOrSink);
      expect(result.reason, 'remote_video_stream_missing');
    });

    test('screen-share video and screen-share audio are reconciled with their '
        'own reason tokens', () {
      final screenVideo = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(
          kind: VoipRemoteMediaKind.screenShareVideo,
          streamObjectExists: false,
        ),
      );
      final screenAudio = VoipRemoteAudioReconciliationPolicy.evaluate(
        _audioState(
          kind: VoipRemoteMediaKind.screenShareAudio,
          streamObjectExists: false,
        ),
      );

      expect(screenVideo.reason, 'remote_screenshare_video_stream_missing');
      expect(screenAudio.reason, 'remote_screenshare_audio_stream_missing');
      expect(
        screenVideo.action,
        VoipRemoteAudioRepairAction.rebuildStreamOrSink,
      );
      expect(
        screenAudio.action,
        VoipRemoteAudioRepairAction.rebuildStreamOrSink,
      );
    });

    test('a detached sink is not a fault until the attach window has '
        'elapsed', () {
      // This is the anti-tautology assertion. `sinkAttached: false` is the
      // normal pre-attach state of every publication, so on its own it must
      // never escalate to a resubscribe.
      final freshlyPublished = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(audioSinkAttached: false),
      );
      final stalled = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(audioSinkAttached: false, mediaAttachStalled: true),
      );

      expect(
        freshlyPublished.action,
        VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        reason: 'a missing sink alone must not trigger a subscription repair',
      );
      // The reason, not just the action. Every sibling branch in this file
      // pins its kind token, and this branch used to hardcode
      // `remote_audio_sink_missing` - so a camera publication reported an
      // `audio` reason and the action-only assertion passed anyway.
      expect(freshlyPublished.reason, 'remote_video_sink_missing');
      expect(stalled.action, VoipRemoteAudioRepairAction.resubscribe);
      expect(stalled.reason, VoipRemoteAudioReasons.mediaAttachStalled);
    });

    test('the app hiding a screen share outranks every repair', () {
      // CallView's receive-quality policy calls disable() then unsubscribe()
      // on off-screen screen shares. That leaves `enabled == false` and
      // `track == null` — indistinguishable from a fault unless the policy is
      // told the app asked for it.
      final hidden = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(
          kind: VoipRemoteMediaKind.screenShareVideo,
          receiveDisabled: true,
          trackSubscribed: false,
          audioSinkAttached: false,
          mediaAttachStalled: true,
          streamObjectExists: false,
        ),
      );

      expect(hidden.action, VoipRemoteAudioRepairAction.none);
      expect(hidden.reason, VoipRemoteAudioReasons.receiveDisabled);
    });

    test('the same publication is repaired once the app wants it again', () {
      // Revealing the tile clears receiveDisabled. `enabled` is still false
      // because the reveal path never ran or failed, and that IS a fault.
      final revealed = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(
          kind: VoipRemoteMediaKind.screenShareVideo,
          receiveDisabled: false,
          trackSubscribed: false,
          audioSinkAttached: false,
          streamObjectExists: false,
        ),
      );

      expect(revealed.action, VoipRemoteAudioRepairAction.subscribe);
      expect(revealed.reason, 'remote_screenshare_video_unsubscribed');
    });

    test('a server-refused subscription is reported, not repaired', () {
      final refused = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(
          subscriptionPermitted: false,
          trackSubscribed: false,
          streamObjectExists: false,
        ),
      );

      expect(refused.action, VoipRemoteAudioRepairAction.none);
      expect(refused.reason, VoipRemoteAudioReasons.subscriptionNotPermitted);
    });

    test('a muted video publication with a surviving tile is removed', () {
      // Mute/unmute is emitted from a listener attached to the track, so a
      // camera that switches off while detached emits nothing and the tile
      // outlives the media.
      final stale = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(publicationMuted: true, audioSinkAttached: false),
      );
      final alreadyGone = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(
          publicationMuted: true,
          audioSinkAttached: false,
          streamObjectExists: false,
        ),
      );

      expect(stale.action, VoipRemoteAudioRepairAction.removeStream);
      expect(stale.reason, VoipRemoteAudioReasons.staleVideoStream);
      expect(
        alreadyGone.action,
        VoipRemoteAudioRepairAction.none,
        reason: 'nothing to remove, and a muted camera must not be rebuilt',
      );
    });

    test('a muted audio publication keeps its tile', () {
      // Removing it would discard the per-participant volume and mute state
      // the user set, and a muted participant still belongs in the call.
      final muted = VoipRemoteAudioReconciliationPolicy.evaluate(
        _audioState(publicationMuted: true),
      );

      expect(muted.action, VoipRemoteAudioRepairAction.none);
      expect(muted.reason, 'remote_publication_muted');
    });

    test('a fully attached video publication is rendered and quiet', () {
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(),
      );

      expect(result.audible, isTrue);
      expect(result.action, VoipRemoteAudioRepairAction.none);
      expect(result.reason, 'rendered');
    });

    test('local playback state is not applied to video', () {
      // `locallyMuted` and a zero volume are audio concepts. A video tile with
      // a muted audio sibling must still render.
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _videoState(locallyMuted: true, localVolume: 0),
      );

      expect(result.audible, isTrue);
      expect(result.reason, 'rendered');
    });

    test('screen-share audio gets the same detached-sink treatment as '
        'video', () {
      // The file header claims the widening covers every remote publication
      // kind, but screen-share audio was only ever exercised through the
      // missing-stream and muted branches. These are the two branches the
      // video kind is exercised through and audio was not, and both pin the
      // kind-specific reason token.
      final freshlyPublished = VoipRemoteAudioReconciliationPolicy.evaluate(
        _audioState(audioSinkAttached: false),
      );
      final stalled = VoipRemoteAudioReconciliationPolicy.evaluate(
        _audioState(audioSinkAttached: false, mediaAttachStalled: true),
      );
      final hidden = VoipRemoteAudioReconciliationPolicy.evaluate(
        _audioState(
          receiveDisabled: true,
          trackSubscribed: false,
          audioSinkAttached: false,
          mediaAttachStalled: true,
          streamObjectExists: false,
        ),
      );

      expect(
        freshlyPublished.action,
        VoipRemoteAudioRepairAction.rebuildStreamOrSink,
      );
      expect(freshlyPublished.reason, 'remote_screenshare_audio_sink_missing');
      expect(stalled.action, VoipRemoteAudioRepairAction.resubscribe);
      expect(stalled.reason, VoipRemoteAudioReasons.mediaAttachStalled);
      expect(hidden.action, VoipRemoteAudioRepairAction.none);
      expect(hidden.reason, VoipRemoteAudioReasons.receiveDisabled);
    });

    test('a disconnected participant is reported, not repaired', () {
      // The first branch in the policy and the only one no test reached. It
      // outranks every fault below it, so a participant who dropped must not
      // produce a repair for any kind.
      for (final state in [
        _videoState(
          participantConnected: false,
          trackSubscribed: false,
          audioSinkAttached: false,
          streamObjectExists: false,
        ),
        _audioState(
          participantConnected: false,
          trackSubscribed: false,
          audioSinkAttached: false,
          streamObjectExists: false,
        ),
      ]) {
        final result = VoipRemoteAudioReconciliationPolicy.evaluate(state);
        expect(result.audible, isFalse);
        expect(result.action, VoipRemoteAudioRepairAction.none);
        expect(result.reason, 'participant_disconnected');
      }
    });

    test('a repair routes to the removeStream callback', () async {
      final actions = <String>[];
      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.removeStream,
          reason: VoipRemoteAudioReasons.staleVideoStream,
        ),
        subscribe: () => actions.add('subscribe'),
        removeStream: () => actions.add('remove'),
      );

      expect(actions, <String>['remove']);
      expect(result.repaired, isTrue);
    });
  });

  group('VoipRemoteMediaAttachMonitor', () {
    final start = DateTime.utc(2026, 8, 8, 12);

    test('never reports a fault inside the attach window', () {
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
      );

      expect(
        monitor.recordObservation(
          sid: 'pub-1',
          wanted: true,
          sinkAttached: false,
          now: start,
        ),
        isFalse,
      );
      expect(
        monitor.recordObservation(
          sid: 'pub-1',
          wanted: true,
          sinkAttached: false,
          now: start.add(const Duration(seconds: 7, milliseconds: 999)),
        ),
        isFalse,
      );
    });

    test('reports a fault once the window elapses with the sink still '
        'missing', () {
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
      );

      monitor.recordObservation(
        sid: 'pub-1',
        wanted: true,
        sinkAttached: false,
        now: start,
      );

      expect(
        monitor.recordObservation(
          sid: 'pub-1',
          wanted: true,
          sinkAttached: false,
          now: start.add(const Duration(seconds: 9)),
        ),
        isTrue,
      );
    });

    test('a sink that arrives resets the window', () {
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
      );

      monitor.recordObservation(
        sid: 'pub-1',
        wanted: true,
        sinkAttached: false,
        now: start,
      );
      monitor.recordObservation(
        sid: 'pub-1',
        wanted: true,
        sinkAttached: true,
        now: start.add(const Duration(seconds: 2)),
      );
      // The sink drops again; the clock restarts from here, so the original
      // window elapsing is not enough.
      monitor.recordObservation(
        sid: 'pub-1',
        wanted: true,
        sinkAttached: false,
        now: start.add(const Duration(seconds: 3)),
      );

      expect(
        monitor.recordObservation(
          sid: 'pub-1',
          wanted: true,
          sinkAttached: false,
          now: start.add(const Duration(seconds: 9)),
        ),
        isFalse,
      );
    });

    test('media the app does not want never accrues a fault', () {
      // A hidden screen share is detached for as long as it stays off screen.
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
      );

      for (var second = 0; second < 120; second += 10) {
        expect(
          monitor.recordObservation(
            sid: 'pub-hidden',
            wanted: false,
            sinkAttached: false,
            now: start.add(Duration(seconds: second)),
          ),
          isFalse,
        );
      }
    });

    test('repairs are capped and cooled down per publication', () {
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
        repairCooldown: const Duration(seconds: 30),
        maxRepairs: 2,
      );

      var now = start;
      var repairs = 0;
      for (var tick = 0; tick < 40; tick++) {
        if (monitor.recordObservation(
          sid: 'pub-1',
          wanted: true,
          sinkAttached: false,
          now: now,
        )) {
          repairs++;
          monitor.recordRepair('pub-1', now);
        }
        now = now.add(const Duration(seconds: 10));
      }

      expect(
        repairs,
        2,
        reason: 'a genuinely dead sender must not produce a resubscribe loop',
      );
    });

    test('the repair budget survives a wanted -> unwanted -> wanted cycle', () {
      // The reason `recordObservation` keeps the entry when `wanted` is false
      // instead of removing it. A screen-share tile scrolled off screen goes
      // unwanted, and if that dropped the entry it would come back with a fresh
      // `maxRepairs` allowance - so a genuinely dead sender could be resubscribed
      // indefinitely, two repairs at a time, once per scroll.
      //
      // Neither existing test crosses the transition: 'media the app does not
      // want' stays unwanted throughout and the cap test stays wanted, so
      // restoring `_entries.remove(sid)` in the unwanted branch keeps both green.
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
        repairCooldown: const Duration(seconds: 30),
        maxRepairs: 2,
      );

      var now = start;
      var repairs = 0;
      void run({required bool wanted, required int ticks}) {
        for (var tick = 0; tick < ticks; tick++) {
          if (monitor.recordObservation(
            sid: 'pub-1',
            wanted: wanted,
            sinkAttached: false,
            now: now,
          )) {
            repairs++;
            monitor.recordRepair('pub-1', now);
          }
          now = now.add(const Duration(seconds: 10));
        }
      }

      run(wanted: true, ticks: 40);
      expect(repairs, 2, reason: 'the cap applies before the tile is hidden');

      // Hidden, then visible again.
      run(wanted: false, ticks: 20);
      run(wanted: true, ticks: 40);

      expect(
        repairs,
        2,
        reason:
            'going unwanted and back must not refill the allowance; a fresh '
            'entry would grant two more repairs on every scroll',
      );
    });

    test('retainOnly drops publications that no longer exist', () {
      final monitor = VoipRemoteMediaAttachMonitor(
        attachWindow: const Duration(seconds: 8),
      );

      monitor.recordObservation(
        sid: 'pub-gone',
        wanted: true,
        sinkAttached: false,
        now: start,
      );
      monitor.retainOnly(<String>{'pub-other'});

      // The entry was dropped, so the window starts again from this sample
      // rather than reporting a fault immediately.
      expect(
        monitor.recordObservation(
          sid: 'pub-gone',
          wanted: true,
          sinkAttached: false,
          now: start.add(const Duration(seconds: 9)),
        ),
        isFalse,
      );
    });
  });
}

VoipRemoteAudioState _videoState({
  VoipRemoteMediaKind kind = VoipRemoteMediaKind.cameraVideo,
  bool participantConnected = true,
  bool publicationExists = true,
  bool publicationMuted = false,
  bool trackSubscribed = true,
  bool subscriptionPermitted = true,
  bool receiveDisabled = false,
  bool streamObjectExists = true,
  bool audioSinkAttached = true,
  bool mediaAttachStalled = false,
  double localVolume = 1,
  bool locallyMuted = false,
}) {
  return VoipRemoteAudioState(
    kind: kind,
    participantConnected: participantConnected,
    audioPublicationExists: publicationExists,
    publicationMuted: publicationMuted,
    trackSubscribed: trackSubscribed,
    subscriptionPermitted: subscriptionPermitted,
    receiveDisabled: receiveDisabled,
    streamObjectExists: streamObjectExists,
    audioSinkAttached: audioSinkAttached,
    mediaAttachStalled: mediaAttachStalled,
    localVolume: localVolume,
    locallyMuted: locallyMuted,
    userMuted: false,
  );
}

VoipRemoteAudioState _audioState({
  VoipRemoteMediaKind kind = VoipRemoteMediaKind.screenShareAudio,
  bool participantConnected = true,
  bool publicationExists = true,
  bool publicationMuted = false,
  bool trackSubscribed = true,
  bool subscriptionPermitted = true,
  bool receiveDisabled = false,
  bool streamObjectExists = true,
  bool audioSinkAttached = true,
  bool mediaAttachStalled = false,
  double localVolume = 1,
  bool locallyMuted = false,
}) {
  return VoipRemoteAudioState(
    kind: kind,
    participantConnected: participantConnected,
    audioPublicationExists: publicationExists,
    publicationMuted: publicationMuted,
    trackSubscribed: trackSubscribed,
    subscriptionPermitted: subscriptionPermitted,
    receiveDisabled: receiveDisabled,
    streamObjectExists: streamObjectExists,
    audioSinkAttached: audioSinkAttached,
    mediaAttachStalled: mediaAttachStalled,
    localVolume: localVolume,
    locallyMuted: locallyMuted,
    userMuted: false,
  );
}
