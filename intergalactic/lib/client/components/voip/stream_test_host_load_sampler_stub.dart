import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_model.dart';

StreamTestHostLoadSampler createStreamTestHostLoadSampler(
  int? targetProcessId,
) {
  return StreamTestUnavailableHostLoadSampler(
    reason: 'host load sampler is not available on this platform',
    sampleIntervalMs: _hostLoadSampleInterval.inMilliseconds,
    targetProcessLoadRequested: targetProcessId != null,
  );
}

const _hostLoadSampleInterval = Duration(seconds: 2);
