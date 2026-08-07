import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class NoiseSuppressionAudioFileSourceFrame {
  const NoiseSuppressionAudioFileSourceFrame({
    required this.frameIndex,
    required this.outputStartSample,
    required this.outputEndSampleExclusive,
    required this.outputStartTimeMs,
    required this.sourceStartSample,
    required this.sourceStartTimeMs,
    required this.sampleCount,
    required this.paddedSamples,
  });

  final int frameIndex;
  final int outputStartSample;
  final int outputEndSampleExclusive;
  final double outputStartTimeMs;
  final int sourceStartSample;
  final double sourceStartTimeMs;
  final int sampleCount;
  final int paddedSamples;

  Map<String, Object> toJson() => <String, Object>{
        'frameIndex': frameIndex,
        'outputStartSample': outputStartSample,
        'outputEndSampleExclusive': outputEndSampleExclusive,
        'outputStartTimeMs': outputStartTimeMs,
        'sourceStartSample': sourceStartSample,
        'sourceStartTimeMs': sourceStartTimeMs,
        'sampleCount': sampleCount,
        'paddedSamples': paddedSamples,
      };
}

class NoiseSuppressionAudioFileSourceMetrics {
  const NoiseSuppressionAudioFileSourceMetrics({
    required this.durationSeconds,
    required this.rms,
    required this.peak,
    required this.maxDelta,
    required this.clippingSamples,
    required this.nonFiniteSamples,
  });

  final double durationSeconds;
  final double rms;
  final double peak;
  final double maxDelta;
  final int clippingSamples;
  final int nonFiniteSamples;

  Map<String, Object> toJson() => <String, Object>{
        'durationSeconds': durationSeconds,
        'rms': rms,
        'peak': peak,
        'maxDelta': maxDelta,
        'clippingSamples': clippingSamples,
        'nonFiniteSamples': nonFiniteSamples,
      };
}

class NoiseSuppressionAudioFileSourceReport {
  const NoiseSuppressionAudioFileSourceReport({
    required this.schemaVersion,
    required this.command,
    required this.createdAtUtc,
    required this.inputPath,
    required this.outputDirectoryPath,
    required this.jsonReportPath,
    required this.markdownReportPath,
    required this.frameIndexPath,
    required this.resampledMonoWavPath,
    required this.sourceFormat,
    required this.sourceSampleRateHz,
    required this.sourceChannels,
    required this.sourceBitsPerSample,
    required this.sourceDurationSeconds,
    required this.targetSampleRateHz,
    required this.frameDurationMs,
    required this.frameSizeSamples,
    required this.frameCount,
    required this.totalOutputSamples,
    required this.lastFramePaddedSamples,
    required this.droppedSamples,
    required this.underrunCount,
    required this.deterministicMode,
    required this.realtimePacing,
    required this.fasterThanRealtimeSupported,
    required this.productionBehaviorChanged,
    required this.debugOnly,
    required this.monoDownmixApplied,
    required this.resampler,
    required this.sourceMetrics,
    required this.outputMetrics,
    required this.frames,
  });

  final int schemaVersion;
  final String command;
  final String createdAtUtc;
  final String inputPath;
  final String outputDirectoryPath;
  final String jsonReportPath;
  final String markdownReportPath;
  final String frameIndexPath;
  final String resampledMonoWavPath;
  final String sourceFormat;
  final int sourceSampleRateHz;
  final int sourceChannels;
  final int sourceBitsPerSample;
  final double sourceDurationSeconds;
  final int targetSampleRateHz;
  final int frameDurationMs;
  final int frameSizeSamples;
  final int frameCount;
  final int totalOutputSamples;
  final int lastFramePaddedSamples;
  final int droppedSamples;
  final int underrunCount;
  final bool deterministicMode;
  final bool realtimePacing;
  final bool fasterThanRealtimeSupported;
  final bool productionBehaviorChanged;
  final bool debugOnly;
  final bool monoDownmixApplied;
  final String resampler;
  final NoiseSuppressionAudioFileSourceMetrics sourceMetrics;
  final NoiseSuppressionAudioFileSourceMetrics outputMetrics;
  final List<NoiseSuppressionAudioFileSourceFrame> frames;

  Map<String, Object?> toJson({bool includeFrames = true}) => <String, Object?>{
        'schemaVersion': schemaVersion,
        'command': command,
        'createdAtUtc': createdAtUtc,
        'input': <String, Object?>{
          'path': inputPath,
          'format': sourceFormat,
          'sampleRateHz': sourceSampleRateHz,
          'channels': sourceChannels,
          'bitsPerSample': sourceBitsPerSample,
          'durationSeconds': sourceDurationSeconds,
          'metrics': sourceMetrics.toJson(),
        },
        'debugAudioFileSource': <String, Object?>{
          'debugOnly': debugOnly,
          'productionBehaviorChanged': productionBehaviorChanged,
          'targetSampleRateHz': targetSampleRateHz,
          'frameDurationMs': frameDurationMs,
          'frameSizeSamples': frameSizeSamples,
          'frameCount': frameCount,
          'totalOutputSamples': totalOutputSamples,
          'lastFramePaddedSamples': lastFramePaddedSamples,
          'droppedSamples': droppedSamples,
          'underrunCount': underrunCount,
          'deterministicMode': deterministicMode,
          'realtimePacing': realtimePacing,
          'fasterThanRealtimeSupported': fasterThanRealtimeSupported,
          'monoDownmixApplied': monoDownmixApplied,
          'resampler': resampler,
          'outputMetrics': outputMetrics.toJson(),
          'frameIndexPath': frameIndexPath,
          'resampledMonoWavPath': resampledMonoWavPath,
          'pipeline': <String>[
            'wav_file',
            'mono_downmix',
            'linear_resample_if_needed',
            'ten_ms_frame_chunks',
            'debug_audio_file_source_frames',
          ],
        },
        'artifacts': <Map<String, Object>>[
          <String, Object>{
            'label': 'app-source JSON report',
            'path': jsonReportPath,
          },
          <String, Object>{
            'label': 'app-source Markdown report',
            'path': markdownReportPath,
          },
          <String, Object>{
            'label': 'frame index JSON',
            'path': frameIndexPath,
          },
          <String, Object>{
            'label': 'resampled mono WAV',
            'path': resampledMonoWavPath,
          },
        ],
        'frames': includeFrames
            ? frames.map((frame) => frame.toJson()).toList(growable: false)
            : <Map<String, Object>>[],
      };
}

class NoiseSuppressionAudioFileSource {
  const NoiseSuppressionAudioFileSource();

  static const int defaultTargetSampleRateHz = 48000;
  static const int defaultFrameDurationMs = 10;

  Future<NoiseSuppressionAudioFileSourceReport> prepareFile({
    required String inputPath,
    required String outputDirectoryPath,
    int targetSampleRateHz = defaultTargetSampleRateHz,
    int frameDurationMs = defaultFrameDurationMs,
    bool deterministicMode = true,
    bool realtimePacing = true,
  }) async {
    if (targetSampleRateHz <= 0) {
      throw ArgumentError.value(
        targetSampleRateHz,
        'targetSampleRateHz',
        'must be positive',
      );
    }
    if (frameDurationMs <= 0) {
      throw ArgumentError.value(
        frameDurationMs,
        'frameDurationMs',
        'must be positive',
      );
    }

    final resolvedInput = File(inputPath).absolute.path;
    final wav = _readWavFile(await File(resolvedInput).readAsBytes());
    final sourceMetrics = _metrics(wav.samples, wav.sampleRateHz);
    final resampled = _resampleLinear(
      wav.samples,
      sourceSampleRateHz: wav.sampleRateHz,
      targetSampleRateHz: targetSampleRateHz,
    );
    final outputMetrics = _metrics(resampled, targetSampleRateHz);
    final frameSizeSamples =
        (targetSampleRateHz * frameDurationMs / 1000.0).round();
    if (frameSizeSamples <= 0) {
      throw StateError('Frame duration is too small for target sample rate.');
    }
    final frameCount =
        resampled.isEmpty ? 0 : (resampled.length / frameSizeSamples).ceil();
    final totalFrameSamples = frameCount * frameSizeSamples;
    final lastFramePaddedSamples =
        frameCount == 0 ? 0 : totalFrameSamples - resampled.length;
    final frames = _buildFrames(
      frameCount: frameCount,
      frameSizeSamples: frameSizeSamples,
      sourceSampleRateHz: wav.sampleRateHz,
      targetSampleRateHz: targetSampleRateHz,
      outputSampleCount: resampled.length,
    );

    final outputDirectory = Directory(outputDirectoryPath);
    await outputDirectory.create(recursive: true);
    final jsonReportPath =
        _join(outputDirectory.path, 'app-source-report.json');
    final markdownReportPath =
        _join(outputDirectory.path, 'app-source-report.md');
    final frameIndexPath = _join(outputDirectory.path, 'source-frames.json');
    final resampledMonoWavPath =
        _join(outputDirectory.path, 'source-resampled-mono.wav');
    await _writeWavFile(
      resampledMonoWavPath,
      samples: resampled,
      sampleRateHz: targetSampleRateHz,
    );

    final report = NoiseSuppressionAudioFileSourceReport(
      schemaVersion: 1,
      command: 'run-app-source',
      createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      inputPath: resolvedInput,
      outputDirectoryPath: outputDirectory.absolute.path,
      jsonReportPath: File(jsonReportPath).absolute.path,
      markdownReportPath: File(markdownReportPath).absolute.path,
      frameIndexPath: File(frameIndexPath).absolute.path,
      resampledMonoWavPath: File(resampledMonoWavPath).absolute.path,
      sourceFormat: wav.format,
      sourceSampleRateHz: wav.sampleRateHz,
      sourceChannels: wav.channels,
      sourceBitsPerSample: wav.bitsPerSample,
      sourceDurationSeconds: wav.samples.length / wav.sampleRateHz,
      targetSampleRateHz: targetSampleRateHz,
      frameDurationMs: frameDurationMs,
      frameSizeSamples: frameSizeSamples,
      frameCount: frameCount,
      totalOutputSamples: resampled.length,
      lastFramePaddedSamples: lastFramePaddedSamples,
      droppedSamples: 0,
      underrunCount: 0,
      deterministicMode: deterministicMode,
      realtimePacing: realtimePacing,
      fasterThanRealtimeSupported: true,
      productionBehaviorChanged: false,
      debugOnly: true,
      monoDownmixApplied: wav.channels > 1,
      resampler: wav.sampleRateHz == targetSampleRateHz
          ? 'none'
          : 'linear_interpolation',
      sourceMetrics: sourceMetrics,
      outputMetrics: outputMetrics,
      frames: frames,
    );

    const encoder = JsonEncoder.withIndent('  ');
    await File(jsonReportPath).writeAsString(
      encoder.convert(report.toJson()),
    );
    await File(frameIndexPath).writeAsString(
      encoder.convert(
        frames.map((frame) => frame.toJson()).toList(growable: false),
      ),
    );
    await File(markdownReportPath).writeAsString(_markdown(report));
    return report;
  }

  static List<NoiseSuppressionAudioFileSourceFrame> _buildFrames({
    required int frameCount,
    required int frameSizeSamples,
    required int sourceSampleRateHz,
    required int targetSampleRateHz,
    required int outputSampleCount,
  }) {
    final frames = <NoiseSuppressionAudioFileSourceFrame>[];
    for (var index = 0; index < frameCount; index++) {
      final outputStart = index * frameSizeSamples;
      final outputEnd = outputStart + frameSizeSamples;
      final outputStartSeconds = outputStart / targetSampleRateHz;
      final sourceStart = (outputStartSeconds * sourceSampleRateHz).floor();
      final paddedSamples = math.max(0, outputEnd - outputSampleCount);
      frames.add(
        NoiseSuppressionAudioFileSourceFrame(
          frameIndex: index,
          outputStartSample: outputStart,
          outputEndSampleExclusive: outputEnd,
          outputStartTimeMs: _round(outputStartSeconds * 1000.0),
          sourceStartSample: sourceStart,
          sourceStartTimeMs: _round(
            sourceStart / sourceSampleRateHz * 1000.0,
          ),
          sampleCount: frameSizeSamples,
          paddedSamples: paddedSamples,
        ),
      );
    }
    return frames;
  }

  static _DecodedWav _readWavFile(Uint8List bytes) {
    if (bytes.length < 44 ||
        _ascii(bytes, 0, 4) != 'RIFF' ||
        _ascii(bytes, 8, 4) != 'WAVE') {
      throw const FormatException('Unsupported WAV file.');
    }

    final data = ByteData.sublistView(bytes);
    var cursor = 12;
    var formatCode = 0;
    var channels = 0;
    var sampleRateHz = 0;
    var blockAlign = 0;
    var bitsPerSample = 0;
    var dataOffset = 0;
    var dataSize = 0;
    while (cursor + 8 <= bytes.length) {
      final chunkId = _ascii(bytes, cursor, 4);
      final chunkSize = data.getUint32(cursor + 4, Endian.little);
      final chunkDataOffset = cursor + 8;
      if (chunkDataOffset + chunkSize > bytes.length) {
        break;
      }
      if (chunkId == 'fmt ' && chunkSize >= 16) {
        formatCode = data.getUint16(chunkDataOffset, Endian.little);
        channels = data.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRateHz = data.getUint32(chunkDataOffset + 4, Endian.little);
        blockAlign = data.getUint16(chunkDataOffset + 12, Endian.little);
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataSize = chunkSize;
      }
      cursor = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (channels <= 0 ||
        sampleRateHz <= 0 ||
        blockAlign <= 0 ||
        dataOffset <= 0 ||
        dataSize <= 0) {
      throw const FormatException('WAV fmt/data chunks are missing.');
    }
    if (!((formatCode == 1 && bitsPerSample == 16) ||
        (formatCode == 3 && bitsPerSample == 32))) {
      throw FormatException(
        'Unsupported WAV encoding. Expected PCM16 or float32, '
        'got format=$formatCode bits=$bitsPerSample.',
      );
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    final frameCount = dataSize ~/ blockAlign;
    final samples = List<double>.filled(frameCount, 0.0);
    for (var frame = 0; frame < frameCount; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final offset =
            dataOffset + (frame * blockAlign) + (channel * bytesPerSample);
        if (formatCode == 1) {
          sum += data.getInt16(offset, Endian.little) / 32768.0;
        } else {
          sum += data.getFloat32(offset, Endian.little);
        }
      }
      samples[frame] = sum / channels;
    }

    return _DecodedWav(
      format: formatCode == 1 ? 'pcm16' : 'float32',
      sampleRateHz: sampleRateHz,
      channels: channels,
      bitsPerSample: bitsPerSample,
      samples: samples,
    );
  }

  static List<double> _resampleLinear(
    List<double> samples, {
    required int sourceSampleRateHz,
    required int targetSampleRateHz,
  }) {
    if (samples.isEmpty || sourceSampleRateHz == targetSampleRateHz) {
      return List<double>.of(samples, growable: false);
    }
    final targetCount =
        (samples.length * targetSampleRateHz / sourceSampleRateHz).round();
    if (targetCount <= 0) {
      return const <double>[];
    }
    final ratio = sourceSampleRateHz / targetSampleRateHz;
    final output = List<double>.filled(targetCount, 0.0);
    for (var index = 0; index < targetCount; index++) {
      final sourcePosition = index * ratio;
      final before = sourcePosition.floor();
      final after = math.min(before + 1, samples.length - 1);
      final fraction = sourcePosition - before;
      output[index] =
          samples[before] + ((samples[after] - samples[before]) * fraction);
    }
    return output;
  }

  static NoiseSuppressionAudioFileSourceMetrics _metrics(
    List<double> samples,
    int sampleRateHz,
  ) {
    if (samples.isEmpty) {
      return const NoiseSuppressionAudioFileSourceMetrics(
        durationSeconds: 0,
        rms: 0,
        peak: 0,
        maxDelta: 0,
        clippingSamples: 0,
        nonFiniteSamples: 0,
      );
    }
    var sumSquares = 0.0;
    var peak = 0.0;
    var maxDelta = 0.0;
    var clipping = 0;
    var nonFinite = 0;
    var previous = samples.first;
    for (final sample in samples) {
      if (sample.isNaN || sample.isInfinite) {
        nonFinite++;
        continue;
      }
      final absolute = sample.abs();
      peak = math.max(peak, absolute);
      if (absolute >= 0.999) {
        clipping++;
      }
      maxDelta = math.max(maxDelta, (sample - previous).abs());
      sumSquares += sample * sample;
      previous = sample;
    }
    return NoiseSuppressionAudioFileSourceMetrics(
      durationSeconds: _round(samples.length / sampleRateHz),
      rms: math.sqrt(sumSquares / samples.length),
      peak: peak,
      maxDelta: maxDelta,
      clippingSamples: clipping,
      nonFiniteSamples: nonFinite,
    );
  }

  static Future<void> _writeWavFile(
    String path, {
    required List<double> samples,
    required int sampleRateHz,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final dataSize = samples.length * 2;
    final bytes = BytesBuilder(copy: false);
    void writeAscii(String value) => bytes.add(ascii.encode(value));
    void writeUint16(int value) {
      final buffer = ByteData(2)..setUint16(0, value, Endian.little);
      bytes.add(buffer.buffer.asUint8List());
    }

    void writeUint32(int value) {
      final buffer = ByteData(4)..setUint32(0, value, Endian.little);
      bytes.add(buffer.buffer.asUint8List());
    }

    writeAscii('RIFF');
    writeUint32(36 + dataSize);
    writeAscii('WAVE');
    writeAscii('fmt ');
    writeUint32(16);
    writeUint16(1);
    writeUint16(1);
    writeUint32(sampleRateHz);
    writeUint32(sampleRateHz * 2);
    writeUint16(2);
    writeUint16(16);
    writeAscii('data');
    writeUint32(dataSize);
    final pcm = Uint8List(dataSize);
    final pcmData = ByteData.sublistView(pcm);
    for (var index = 0; index < samples.length; index++) {
      final clamped = samples[index].clamp(-1.0, 1.0);
      pcmData.setInt16(
        index * 2,
        (clamped * 32767.0).round(),
        Endian.little,
      );
    }
    bytes.add(pcm);
    await file.writeAsBytes(bytes.takeBytes());
  }

  static String _markdown(NoiseSuppressionAudioFileSourceReport report) {
    final lines = <String>[
      '# Audio Lab App File Source Report',
      '',
      '## Summary',
      '',
      '- Status: `prepared`',
      '- Debug-only: `${report.debugOnly}`',
      '- Production behavior changed: `${report.productionBehaviorChanged}`',
      '- Frames: `${report.frameCount}`',
      '- Target format: `${report.targetSampleRateHz} Hz mono, '
          '${report.frameDurationMs} ms frames`',
      '',
      '## Input',
      '',
      '- Path: `${report.inputPath}`',
      '- Format: `${report.sourceFormat}`',
      '- Source format: `${report.sourceSampleRateHz} Hz, '
          '${report.sourceChannels} channel(s), '
          '${report.sourceBitsPerSample} bits`',
      '- Duration: `${_round(report.sourceDurationSeconds)}s`',
      '- Mono downmix applied: `${report.monoDownmixApplied}`',
      '- Resampler: `${report.resampler}`',
      '',
      '## Pipeline Actually Exercised',
      '',
      '- `wav_file -> mono_downmix -> linear_resample_if_needed -> '
          'ten_ms_frame_chunks -> debug_audio_file_source_frames`',
      '- RNNoise active: `false`',
      '- WebRTC NS active: `false`',
      '- AGC active: `false`',
      '- AEC active: `false`',
      '- LiveKit loopback used: `false`',
      '',
      '## Metrics',
      '',
      '| Audio | RMS | Peak | Max delta | Clipping | Non-finite |',
      '| --- | ---: | ---: | ---: | ---: | ---: |',
      '| Source | ${report.sourceMetrics.rms.toStringAsFixed(6)} | '
          '${report.sourceMetrics.peak.toStringAsFixed(6)} | '
          '${report.sourceMetrics.maxDelta.toStringAsFixed(6)} | '
          '${report.sourceMetrics.clippingSamples} | '
          '${report.sourceMetrics.nonFiniteSamples} |',
      '| Prepared | ${report.outputMetrics.rms.toStringAsFixed(6)} | '
          '${report.outputMetrics.peak.toStringAsFixed(6)} | '
          '${report.outputMetrics.maxDelta.toStringAsFixed(6)} | '
          '${report.outputMetrics.clippingSamples} | '
          '${report.outputMetrics.nonFiniteSamples} |',
      '',
      '## Frame Plan',
      '',
      '- Frame size samples: `${report.frameSizeSamples}`',
      '- Total prepared samples: `${report.totalOutputSamples}`',
      '- Last-frame padded samples: `${report.lastFramePaddedSamples}`',
      '- Dropped samples: `${report.droppedSamples}`',
      '- Underrun count: `${report.underrunCount}`',
      '- Realtime pacing metadata written: `${report.realtimePacing}`',
      '- Faster-than-realtime supported: '
          '`${report.fasterThanRealtimeSupported}`',
      '',
      '| Frame | Output ms | Source ms | Source sample | Padded |',
      '| ---: | ---: | ---: | ---: | ---: |',
    ];
    final preview = report.frames.take(8).toList(growable: true);
    for (final frame in preview) {
      lines.add(
        '| ${frame.frameIndex} | ${frame.outputStartTimeMs} | '
        '${frame.sourceStartTimeMs} | ${frame.sourceStartSample} | '
        '${frame.paddedSamples} |',
      );
    }
    if (report.frames.length > 10) {
      lines.add('| ... | ... | ... | ... | ... |');
      for (final frame in report.frames.skip(report.frames.length - 2)) {
        lines.add(
          '| ${frame.frameIndex} | ${frame.outputStartTimeMs} | '
          '${frame.sourceStartTimeMs} | ${frame.sourceStartSample} | '
          '${frame.paddedSamples} |',
        );
      }
    } else if (report.frames.length > preview.length) {
      for (final frame in report.frames.skip(preview.length)) {
        lines.add(
          '| ${frame.frameIndex} | ${frame.outputStartTimeMs} | '
          '${frame.sourceStartTimeMs} | ${frame.sourceStartSample} | '
          '${frame.paddedSamples} |',
        );
      }
    }
    lines.addAll(
      <String>[
        '',
        '## Artifacts',
        '',
        '- JSON report: `${report.jsonReportPath}`',
        '- Frame index JSON: `${report.frameIndexPath}`',
        '- Prepared mono WAV: `${report.resampledMonoWavPath}`',
        '',
        '## Failure Classification',
        '',
        '- `insufficient_evidence` until this prepared source is published '
            'through the native RNNoise/WebRTC/LiveKit path.',
        '',
        '## Recommended Next Tuning Action',
        '',
        'Use this prepared debug source as the deterministic input for the '
            'native RNNoise hook adapter or LiveKit loopback recorder. Do not '
            'change production microphone defaults from this layer alone.',
        '',
      ],
    );
    return lines.join('\n');
  }

  static String _join(String base, String child) {
    if (base.endsWith(Platform.pathSeparator)) {
      return '$base$child';
    }
    return '$base${Platform.pathSeparator}$child';
  }

  static String _ascii(Uint8List bytes, int offset, int length) {
    return ascii.decode(bytes.sublist(offset, offset + length));
  }

  static double _round(double value) => (value * 1000000.0).round() / 1000000.0;
}

class _DecodedWav {
  const _DecodedWav({
    required this.format,
    required this.sampleRateHz,
    required this.channels,
    required this.bitsPerSample,
    required this.samples,
  });

  final String format;
  final int sampleRateHz;
  final int channels;
  final int bitsPerSample;
  final List<double> samples;
}
