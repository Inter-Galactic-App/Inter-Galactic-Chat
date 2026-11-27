export 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact_model.dart';

import 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact_model.dart';
import 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact_stub.dart'
    if (dart.library.io) 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact_io.dart'
    as impl;

Future<StreamTestLoadedLibwebrtcArtifact?>
    loadStreamTestLoadedLibwebrtcArtifact() {
  return impl.loadStreamTestLoadedLibwebrtcArtifact();
}
