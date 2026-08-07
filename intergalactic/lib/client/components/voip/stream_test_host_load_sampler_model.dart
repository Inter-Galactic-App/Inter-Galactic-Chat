class StreamTestHostLoadSample {
  const StreamTestHostLoadSample({
    required this.timestampUtc,
    this.systemCpuPercent,
    this.memoryUsedPercent,
    this.memoryAvailableMb,
    this.appCpuPercent,
    this.targetCpuPercent,
    this.gpu3dPercent,
    this.gpuCopyPercent,
    this.gpuVideoEncodePercent,
    this.gpuComputePercent,
    this.gpuDedicatedMemoryMb,
  });

  factory StreamTestHostLoadSample.fromJson(Map<String, Object?> json) {
    final parsedTimestamp = _dateTimeFromJson(json['timestamp']);
    if (parsedTimestamp == null) {
      throw const FormatException(
        'missing or invalid host load sample timestamp',
      );
    }

    return StreamTestHostLoadSample(
      timestampUtc: parsedTimestamp,
      systemCpuPercent: _doubleFromJson(json['systemCpuPercent']),
      memoryUsedPercent: _doubleFromJson(json['memoryUsedPercent']),
      memoryAvailableMb: _doubleFromJson(json['memoryAvailableMb']),
      appCpuPercent: _doubleFromJson(json['appCpuPercent']),
      targetCpuPercent: _doubleFromJson(json['targetCpuPercent']),
      gpu3dPercent: _doubleFromJson(json['gpu3dPercent']),
      gpuCopyPercent: _doubleFromJson(json['gpuCopyPercent']),
      gpuVideoEncodePercent: _doubleFromJson(json['gpuVideoEncodePercent']),
      gpuComputePercent: _doubleFromJson(json['gpuComputePercent']),
      gpuDedicatedMemoryMb: _doubleFromJson(json['gpuDedicatedMemoryMb']),
    );
  }

  final DateTime timestampUtc;
  final double? systemCpuPercent;
  final double? memoryUsedPercent;
  final double? memoryAvailableMb;
  final double? appCpuPercent;
  final double? targetCpuPercent;
  final double? gpu3dPercent;
  final double? gpuCopyPercent;
  final double? gpuVideoEncodePercent;
  final double? gpuComputePercent;
  final double? gpuDedicatedMemoryMb;

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestampUtc.toUtc().toIso8601String(),
      'systemCpuPercent': systemCpuPercent,
      'memoryUsedPercent': memoryUsedPercent,
      'memoryAvailableMb': memoryAvailableMb,
      'appCpuPercent': appCpuPercent,
      'targetCpuPercent': targetCpuPercent,
      'gpu3dPercent': gpu3dPercent,
      'gpuCopyPercent': gpuCopyPercent,
      'gpuVideoEncodePercent': gpuVideoEncodePercent,
      'gpuComputePercent': gpuComputePercent,
      'gpuDedicatedMemoryMb': gpuDedicatedMemoryMb,
    };
  }
}

class StreamTestHostLoadMetricSummary {
  const StreamTestHostLoadMetricSummary({
    required this.sampleCount,
    this.average,
    this.minimum,
    this.maximum,
  });

  final int sampleCount;
  final double? average;
  final double? minimum;
  final double? maximum;

  bool get hasSamples => sampleCount > 0;

  Map<String, Object?> toJson() {
    return {
      'sampleCount': sampleCount,
      'average': average,
      'minimum': minimum,
      'maximum': maximum,
    };
  }
}

class StreamTestHostLoadReport {
  StreamTestHostLoadReport({
    required List<StreamTestHostLoadSample> samples,
    required this.sampleIntervalMs,
    required this.targetProcessLoadRequested,
    this.unavailableReason,
    this.droppedSampleCount = 0,
  }) : samples = List.unmodifiable(samples);

  factory StreamTestHostLoadReport.unavailable({
    required String reason,
    int sampleIntervalMs = 0,
    bool targetProcessLoadRequested = false,
  }) {
    return StreamTestHostLoadReport(
      samples: const [],
      sampleIntervalMs: sampleIntervalMs,
      targetProcessLoadRequested: targetProcessLoadRequested,
      unavailableReason: reason,
    );
  }

  final List<StreamTestHostLoadSample> samples;
  final int sampleIntervalMs;
  final bool targetProcessLoadRequested;
  final String? unavailableReason;
  final int droppedSampleCount;

  bool get available => samples.isNotEmpty;

  DateTime? get startedAtUtc =>
      samples.isEmpty ? null : samples.first.timestampUtc;

  DateTime? get endedAtUtc =>
      samples.isEmpty ? null : samples.last.timestampUtc;

  StreamTestHostLoadMetricSummary get systemCpuPercent =>
      _summarize((sample) => sample.systemCpuPercent);

  StreamTestHostLoadMetricSummary get memoryUsedPercent =>
      _summarize((sample) => sample.memoryUsedPercent);

  StreamTestHostLoadMetricSummary get memoryAvailableMb =>
      _summarize((sample) => sample.memoryAvailableMb);

  StreamTestHostLoadMetricSummary get appCpuPercent =>
      _summarize((sample) => sample.appCpuPercent);

  StreamTestHostLoadMetricSummary get targetCpuPercent =>
      _summarize((sample) => sample.targetCpuPercent);

  StreamTestHostLoadMetricSummary get gpu3dPercent =>
      _summarize((sample) => sample.gpu3dPercent);

  StreamTestHostLoadMetricSummary get gpuCopyPercent =>
      _summarize((sample) => sample.gpuCopyPercent);

  StreamTestHostLoadMetricSummary get gpuVideoEncodePercent =>
      _summarize((sample) => sample.gpuVideoEncodePercent);

  StreamTestHostLoadMetricSummary get gpuComputePercent =>
      _summarize((sample) => sample.gpuComputePercent);

  StreamTestHostLoadMetricSummary get gpuDedicatedMemoryMb =>
      _summarize((sample) => sample.gpuDedicatedMemoryMb);

  bool get hasSystemCpuMemoryGpuEvidence {
    return systemCpuPercent.hasSamples &&
        memoryUsedPercent.hasSamples &&
        (gpu3dPercent.hasSamples ||
            gpuCopyPercent.hasSamples ||
            gpuVideoEncodePercent.hasSamples ||
            gpuComputePercent.hasSamples);
  }

  List<String> get missingMetricLabels {
    return [
      if (!systemCpuPercent.hasSamples) 'system CPU percent',
      if (!memoryUsedPercent.hasSamples) 'system memory used percent',
      if (!memoryAvailableMb.hasSamples) 'system memory available MB',
      if (!gpu3dPercent.hasSamples &&
          !gpuCopyPercent.hasSamples &&
          !gpuVideoEncodePercent.hasSamples &&
          !gpuComputePercent.hasSamples)
        'GPU utilization percent',
      if (!appCpuPercent.hasSamples) 'app process CPU percent',
      if (targetProcessLoadRequested && !targetCpuPercent.hasSamples)
        'target process CPU percent',
    ];
  }

  Map<String, Object?> toJson() {
    return {
      'available': available,
      'unavailableReason': unavailableReason,
      'sampleIntervalMs': sampleIntervalMs,
      'sampleCount': samples.length,
      'droppedSampleCount': droppedSampleCount,
      'targetProcessLoadRequested': targetProcessLoadRequested,
      'startedAt': startedAtUtc?.toUtc().toIso8601String(),
      'endedAt': endedAtUtc?.toUtc().toIso8601String(),
      'missingMetrics': missingMetricLabels,
      'systemCpuPercent': systemCpuPercent.toJson(),
      'memoryUsedPercent': memoryUsedPercent.toJson(),
      'memoryAvailableMb': memoryAvailableMb.toJson(),
      'appCpuPercent': appCpuPercent.toJson(),
      'targetCpuPercent': targetCpuPercent.toJson(),
      'gpu3dPercent': gpu3dPercent.toJson(),
      'gpuCopyPercent': gpuCopyPercent.toJson(),
      'gpuVideoEncodePercent': gpuVideoEncodePercent.toJson(),
      'gpuComputePercent': gpuComputePercent.toJson(),
      'gpuDedicatedMemoryMb': gpuDedicatedMemoryMb.toJson(),
      'samples':
          samples.map((sample) => sample.toJson()).toList(growable: false),
    };
  }

  StreamTestHostLoadMetricSummary _summarize(
    double? Function(StreamTestHostLoadSample sample) selector,
  ) {
    var count = 0;
    var total = 0.0;
    double? minimum;
    double? maximum;
    for (final sample in samples) {
      final value = selector(sample);
      if (value == null || value.isNaN || !value.isFinite) {
        continue;
      }
      count += 1;
      total += value;
      minimum = minimum == null ? value : (value < minimum ? value : minimum);
      maximum = maximum == null ? value : (value > maximum ? value : maximum);
    }
    return StreamTestHostLoadMetricSummary(
      sampleCount: count,
      average: count == 0 ? null : total / count,
      minimum: minimum,
      maximum: maximum,
    );
  }
}

abstract class StreamTestHostLoadSampler {
  Future<void> start();
  Future<StreamTestHostLoadReport> stop();
}

class StreamTestUnavailableHostLoadSampler
    implements StreamTestHostLoadSampler {
  const StreamTestUnavailableHostLoadSampler({
    required this.reason,
    this.sampleIntervalMs = 0,
    this.targetProcessLoadRequested = false,
  });

  final String reason;
  final int sampleIntervalMs;
  final bool targetProcessLoadRequested;

  @override
  Future<void> start() async {}

  @override
  Future<StreamTestHostLoadReport> stop() async {
    return StreamTestHostLoadReport.unavailable(
      reason: reason,
      sampleIntervalMs: sampleIntervalMs,
      targetProcessLoadRequested: targetProcessLoadRequested,
    );
  }
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

double? _doubleFromJson(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
