import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_pack.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';

void main() {
  test('reorder reads the current pack state before writing', () async {
    final state = _FakeEmoticonStateManager({
      'images': {
        'first': {'url': 'mxc://example/first'},
        'second': {'url': 'mxc://example/second'},
        'remote-new': {'url': 'mxc://example/new'},
      },
    });
    final component = MatrixEmoticonComponent(_FakeMatrixClient(), state);
    final pack = MatrixEmoticonPack(component, 'pack', {
      'images': {
        'first': {'url': 'mxc://example/first'},
        'second': {'url': 'mxc://example/second'},
      },
    });

    await pack.reorderEmoticons(['second', 'first']);

    expect(state.writtenContent!['images'].keys, [
      'second',
      'first',
      'remote-new',
    ]);
  });
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeEmoticonStateManager implements MatrixEmoticonStateManager {
  _FakeEmoticonStateManager(this.currentContent);

  final Map<String, dynamic> currentContent;
  Map<String, dynamic>? writtenContent;

  @override
  String get id => 'test';

  @override
  Stream<void> get onStateChanged => const Stream<void>.empty();

  @override
  Map<String, dynamic> getAllStates() => {'pack': currentContent};

  @override
  Map<String, dynamic> getState(String packKey) => currentContent;

  @override
  Future<void> setState(String packKey, Map<String, dynamic> content) async {
    writtenContent = content;
  }
}
