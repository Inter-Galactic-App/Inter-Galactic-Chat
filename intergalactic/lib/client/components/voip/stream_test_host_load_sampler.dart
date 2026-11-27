export 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_model.dart';

import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_model.dart';
import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_stub.dart'
    if (dart.library.io) 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_io.dart'
    as impl;

StreamTestHostLoadSampler createStreamTestHostLoadSampler(
  int? targetProcessId,
) {
  return impl.createStreamTestHostLoadSampler(targetProcessId);
}
