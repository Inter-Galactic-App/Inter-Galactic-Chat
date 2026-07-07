import 'package:matrix/matrix.dart' as matrix;

const List<String> matrixRequestableBadEncryptedBodyPhrases = <String>[
  'corrupted session',
  'channel with the sender was corrupted',
  'channel corrupted',
];

bool matrixBadEncryptedBodyMentionsRequestableSessionFailure(String? text) {
  final lower = text?.toLowerCase() ?? '';
  return matrixRequestableBadEncryptedBodyPhrases.any(lower.contains);
}

bool matrixBadEncryptedEventHasStructuredSessionRequestSignal(
  matrix.Event event,
) {
  return event.content['can_request_session'] == true;
}
