import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';

String callStreamPopoutIdForStream(VoipStream stream) {
  if (stream.type == VoipStreamType.screenshare) {
    if (stream is MatrixLivekitVoipStream) {
      final sourceName = stream.publication.source.toString();
      final publicationName = stream.publication.name;
      final publicationLabel =
          publicationName.isEmpty ? sourceName : '$sourceName:$publicationName';

      return 'screenshare:${stream.participantIdentity}:'
          '${stream.streamUserId}:$publicationLabel';
    }

    return 'screenshare:${stream.streamUserId}';
  }

  return 'participant:${stream.streamUserId}';
}
