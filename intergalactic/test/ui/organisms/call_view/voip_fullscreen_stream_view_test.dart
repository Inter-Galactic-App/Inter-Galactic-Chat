import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/rtc_screen_share_annotation/rtc_screen_share_annotation_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';

void main() {
  test('fullscreen annotation cursor updates active session', () {
    final annotationSession = _FakeAnnotationSession();

    debugSetFullscreenAnnotationCursorForTesting(
      session: annotationSession,
      streamId: 'stream-1',
      x: -0.2,
      y: 1.4,
    );

    expect(annotationSession.streamId, 'stream-1');
    expect(annotationSession.x, 0);
    expect(annotationSession.y, 1);
  });

  test('fullscreen annotation cursor failures are recovered', () {
    final annotationSession = _ThrowingAnnotationSession(
      StateError('annotation session closed'),
    );

    expect(
      () => debugSetFullscreenAnnotationCursorForTesting(
        session: annotationSession,
        streamId: 'stream-1',
        x: 0.25,
        y: 0.75,
      ),
      returnsNormally,
    );
  });

  testWidgets('fullscreen annotation action ignores completion after dispose', (
    tester,
  ) async {
    final annotationComponent = _FakeAnnotationComponent();
    final client = _FakeClient(annotationComponent);
    final session = _FakeVoipSession(client);
    final stream = _FakeVoipStream();

    await tester.pumpWidget(
      MaterialApp(
        home: VoipFullscreenStreamView(session: session, stream: stream),
      ),
    );

    await tester.tap(find.byIcon(Icons.mouse));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    annotationComponent.complete(_FakeAnnotationSession());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen annotation action recovers setup failures', (
    tester,
  ) async {
    final annotationComponent = _FakeAnnotationComponent();
    final client = _FakeClient(annotationComponent);
    final session = _FakeVoipSession(client);
    final stream = _FakeVoipStream();

    await tester.pumpWidget(
      MaterialApp(
        home: VoipFullscreenStreamView(session: session, stream: stream),
      ),
    );

    await tester.tap(find.byIcon(Icons.mouse));
    await tester.pump();

    annotationComponent.fail(StateError('annotation unavailable'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _FakeAnnotationComponent
    implements RTCScreenShareAnnotationComponent<Client> {
  final Completer<RTCScreenShareAnnotationSession> _sessionCompleter =
      Completer<RTCScreenShareAnnotationSession>();

  void complete(RTCScreenShareAnnotationSession session) {
    _sessionCompleter.complete(session);
  }

  void fail(Object error) {
    _sessionCompleter.completeError(error);
  }

  @override
  Client get client => throw UnimplementedError();

  @override
  Future<RTCScreenShareAnnotationSession> createSession(VoipSession session) {
    return _sessionCompleter.future;
  }

  @override
  RTCScreenShareAnnotationSession? getExistingSession(VoipSession session) {
    return null;
  }

  @override
  Future<RTCScreenShareAnnotationSession> getOrCreateSession(
    VoipSession session,
  ) {
    return _sessionCompleter.future;
  }
}

class _FakeAnnotationSession implements RTCScreenShareAnnotationSession {
  String? streamId;
  double? x;
  double? y;

  @override
  void setCursorPosition({
    required String streamId,
    required double x,
    required double y,
  }) {
    this.streamId = streamId;
    this.x = x;
    this.y = y;
  }
}

class _ThrowingAnnotationSession implements RTCScreenShareAnnotationSession {
  const _ThrowingAnnotationSession(this.error);

  final Object error;

  @override
  void setCursorPosition({
    required String streamId,
    required double x,
    required double y,
  }) {
    throw error;
  }
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession(this.client);

  @override
  final Client client;

  @override
  String get roomId => '!room:example.org';

  @override
  String get roomName => 'Test Voice';

  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipStream implements VoipStream {
  final StreamController<void> _changed = StreamController<void>.broadcast();

  @override
  double get audiolevel => 0;

  @override
  double? get aspectRatio => null;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get isMuted => false;

  @override
  String get label => 'Screen';

  @override
  Stream<void> get onStreamChanged => _changed.stream;

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.medium;

  @override
  String get streamId => 'screen-stream';

  @override
  String get streamUserId => '@alice:example.org';

  @override
  VoipStreamType get type => VoipStreamType.screenshare;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) {
    return const SizedBox.expand();
  }

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}
}

class _FakeClient implements Client {
  _FakeClient(this.annotationComponent);

  final RTCScreenShareAnnotationComponent<Client> annotationComponent;
  final Room _room = _FakeRoom();

  @override
  Profile? self;

  @override
  Room? getRoom(String identifier) => _room;

  @override
  T? getComponent<T extends Component>() {
    if (T == RTCScreenShareAnnotationComponent) {
      return annotationComponent as T;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  const _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  ImageProvider<Object>? get avatar => null;

  @override
  String? get avatarId => null;

  @override
  Color get defaultColor => Colors.blueGrey;

  @override
  String? get detail => null;

  @override
  String get displayName => 'Alice';

  @override
  String get userName => 'alice';
}
