import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_session_event_gate.dart';

void main() {
  group('CallSessionEventGate', () {
    test(
      'processes participant and track events while the session is active',
      () {
        final gate = CallSessionEventGate();
        final handled = <String>[];

        expect(
          gate.runIfActive(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
            handleEvent: () => handled.add('participant_connected'),
          ),
          isTrue,
        );
        expect(
          gate.runIfActive(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
            handleEvent: () => handled.add('track_subscribed'),
          ),
          isTrue,
        );

        expect(handled, ['participant_connected', 'track_subscribed']);
      },
    );

    test(
      'ignores late participant events once hang-up is ending the session',
      () {
        final gate = CallSessionEventGate();
        final handled = <String>[];

        final connectedHandled = gate.runIfActive(
          isEnding: true,
          isEnded: false,
          transientResourcesDisposed: false,
          handleEvent: () => handled.add('participant_connected'),
        );
        final disconnectedHandled = gate.runIfActive(
          isEnding: true,
          isEnded: false,
          transientResourcesDisposed: false,
          handleEvent: () => handled.add('participant_disconnected'),
        );

        expect(connectedHandled, isFalse);
        expect(disconnectedHandled, isFalse);
        expect(handled, isEmpty);
      },
    );

    test(
      'ignores late track and subscription events after resource disposal',
      () {
        final gate = CallSessionEventGate();
        final handled = <String>[];

        final publishedHandled = gate.runIfActive(
          isEnding: false,
          isEnded: false,
          transientResourcesDisposed: true,
          handleEvent: () => handled.add('track_published'),
        );
        final unsubscribedHandled = gate.runIfActive(
          isEnding: false,
          isEnded: false,
          transientResourcesDisposed: true,
          handleEvent: () => handled.add('track_unsubscribed'),
        );

        expect(publishedHandled, isFalse);
        expect(unsubscribedHandled, isFalse);
        expect(handled, isEmpty);
      },
    );

    test(
      'stays closed for late LiveKit callbacks after the gate is disposed',
      () {
        final gate = CallSessionEventGate();
        final handled = <String>[];

        gate.dispose();

        expect(gate.isDisposed, isTrue);
        expect(
          gate.shouldProcess(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
          ),
          isFalse,
        );
        expect(
          gate.runIfActive(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
            handleEvent: () => handled.add('track_subscribed_after_dispose'),
          ),
          isFalse,
        );
        expect(handled, isEmpty);
      },
    );

    test('blocks diagnostic probe operations at teardown boundaries', () {
      final gate = CallSessionEventGate();
      final handled = <String>[];

      expect(
        gate.runIfActive(
          isEnding: false,
          isEnded: false,
          transientResourcesDisposed: false,
          handleEvent: () => handled.add('start_receiver_probe'),
        ),
        isTrue,
      );
      expect(handled, ['start_receiver_probe']);

      for (final boundary in const [
        _NotificationBoundary(isEnding: true),
        _NotificationBoundary(isEnded: true),
        _NotificationBoundary(transientResourcesDisposed: true),
      ]) {
        expect(
          gate.runIfActive(
            isEnding: boundary.isEnding,
            isEnded: boundary.isEnded,
            transientResourcesDisposed: boundary.transientResourcesDisposed,
            handleEvent: () => handled.add('late_probe_operation'),
          ),
          isFalse,
        );
      }

      gate.dispose();
      expect(
        gate.runIfActive(
          isEnding: false,
          isEnded: false,
          transientResourcesDisposed: false,
          handleEvent: () => handled.add('after_gate_dispose'),
        ),
        isFalse,
      );
      expect(handled, ['start_receiver_probe']);
    });

    test(
      'blocks transient session notifications after teardown boundaries',
      () {
        final gate = CallSessionEventGate();
        final notified = <String>[];

        expect(
          gate.notifyIfActive(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
            closed: false,
            notify: () => notified.add('volume_visualizer'),
          ),
          isTrue,
        );
        expect(notified, ['volume_visualizer']);

        for (final boundary in const [
          _NotificationBoundary(isEnding: true),
          _NotificationBoundary(isEnded: true),
          _NotificationBoundary(transientResourcesDisposed: true),
          _NotificationBoundary(closed: true),
        ]) {
          expect(
            gate.notifyIfActive(
              isEnding: boundary.isEnding,
              isEnded: boundary.isEnded,
              transientResourcesDisposed: boundary.transientResourcesDisposed,
              closed: boundary.closed,
              notify: () => notified.add('late_transient_signal'),
            ),
            isFalse,
          );
        }

        gate.dispose();
        expect(
          gate.notifyIfActive(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
            closed: false,
            notify: () => notified.add('after_gate_dispose'),
          ),
          isFalse,
        );
        expect(notified, ['volume_visualizer']);
      },
    );
  });
}

class _NotificationBoundary {
  const _NotificationBoundary({
    this.isEnding = false,
    this.isEnded = false,
    this.transientResourcesDisposed = false,
    this.closed = false,
  });

  final bool isEnding;
  final bool isEnded;
  final bool transientResourcesDisposed;
  final bool closed;
}
