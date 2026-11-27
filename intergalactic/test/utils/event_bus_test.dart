import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/event_bus.dart';

void main() {
  const String client = 'one';
  const String room = '!room:example.org';

  // EventBus.registerInboxJumpTarget writes into a process-global static map,
  // and the disposer only ran on the success path here. Any failing
  // expectation used to leave a live handler registered for the rest of the
  // isolate, so one broken assertion could change the result of every test
  // after it. addTearDown makes removal unconditional.
  VoidCallback register(
    void Function(String eventId) onJump, {
    String clientIdentifier = client,
    String roomIdentifier = room,
  }) {
    final remove = EventBus.registerInboxJumpTarget(
      clientIdentifier: clientIdentifier,
      roomIdentifier: roomIdentifier,
      onJump: onJump,
    );
    addTearDown(remove);
    return remove;
  }

  bool jump(
    String eventId, {
    String clientIdentifier = client,
    String roomIdentifier = room,
  }) => EventBus.jumpToInboxEvent(
    clientIdentifier: clientIdentifier,
    roomIdentifier: roomIdentifier,
    eventId: eventId,
  );

  test('a jump for an unregistered room is not acknowledged', () {
    register((_) {});

    expect(jump(r'$other', roomIdentifier: '!other:example.org'), isFalse);
  });

  test('a stale disposer cannot unregister the handler that replaced it', () {
    final received = <String>[];
    // Re-registering the same room replaces the handler. The FIRST
    // registration's disposer must then be inert - it identity-checks what it
    // is about to remove - or a disposing timeline would silently deafen the
    // one that took its place.
    final removeFirst = register(received.add);
    register((eventId) => received.add('replacement:$eventId'));
    removeFirst();

    expect(jump(r'$target'), isTrue);
    expect(received, [r'replacement:$target']);
  });

  test('a jump never crosses accounts sharing the same room id', () {
    // The registry key joins client AND room, and two accounts can be joined
    // to the same room - so this is reachable, not theoretical. Varying only
    // the room id (as this file did) leaves the account half of the key
    // completely unexercised.
    final delivered = <String>[];
    register((eventId) => delivered.add('one:$eventId'));
    register(
      (eventId) => delivered.add('two:$eventId'),
      clientIdentifier: 'two',
    );

    // BOTH directions. Checking only the second-registered account passes even
    // if the account half of the key is dropped entirely: the later
    // registration would simply overwrite the earlier one under a colliding
    // key and still answer its own jump. The FIRST-registered account is the
    // one that disappears under that defect, so it has to be asserted too.
    expect(jump(r'$for-one'), isTrue);
    expect(jump(r'$for-two', clientIdentifier: 'two'), isTrue);
    expect(
      delivered,
      [r'one:$for-one', r'two:$for-two'],
      reason:
          'a jump reached the wrong account, or never reached the right one',
    );
  });

  test('a jump is not acknowledged once the timeline has disposed', () {
    final remove = register((_) {});
    remove();

    expect(jump(r'$after-dispose'), isFalse);
  });
}
