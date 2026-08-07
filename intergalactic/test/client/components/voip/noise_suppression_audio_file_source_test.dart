import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_audio_file_source.dart';

void main() {
  group('NoiseSuppressionAudioFileSource', () {
    test('prepares WAV input as deterministic 10 ms frame metadata', () async {
      final temp = await Directory.systemTemp.createTemp(
        'ig_audio_file_source_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final input = File('${temp.path}${Platform.pathSeparator}input.wav');
      await input.writeAsBytes(_wavPcm16(
        sampleRateHz: 16000,
        channels: 1,
        frameCount: 400,
      ));

      final report = await const NoiseSuppressionAudioFileSource().prepareFile(
        inputPath: input.path,
        outputDirectoryPath: '${temp.path}${Platform.pathSeparator}prepared',
      );

      expect(report.sourceSampleRateHz, 16000);
      expect(report.targetSampleRateHz, 48000);
      expect(report.frameSizeSamples, 480);
      expect(report.totalOutputSamples, 1200);
      expect(report.frameCount, 3);
      expect(report.lastFramePaddedSamples, 240);
      expect(report.underrunCount, 0);
      expect(report.droppedSamples, 0);
      expect(report.productionBehaviorChanged, isFalse);
      expect(report.debugOnly, isTrue);
      expect(report.frames[1].sourceStartSample, 160);
      expect(report.frames[1].sourceStartTimeMs, 10.0);
      expect(report.frames[2].paddedSamples, 240);
      expect(await File(report.jsonReportPath).exists(), isTrue);
      expect(await File(report.markdownReportPath).exists(), isTrue);
      expect(await File(report.frameIndexPath).exists(), isTrue);
      expect(await File(report.resampledMonoWavPath).exists(), isTrue);

      final frameJson = jsonDecode(
        await File(report.frameIndexPath).readAsString(),
      ) as List<dynamic>;
      expect(frameJson, hasLength(3));
      expect(frameJson[1]['sourceStartSample'], 160);
    });

    test('downmixes multichannel PCM16 WAV before frame planning', () async {
      final temp = await Directory.systemTemp.createTemp(
        'ig_audio_file_source_stereo_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final input = File('${temp.path}${Platform.pathSeparator}stereo.wav');
      await input.writeAsBytes(_wavPcm16(
        sampleRateHz: 48000,
        channels: 2,
        frameCount: 960,
      ));

      final report = await const NoiseSuppressionAudioFileSource().prepareFile(
        inputPath: input.path,
        outputDirectoryPath: '${temp.path}${Platform.pathSeparator}prepared',
      );

      expect(report.sourceChannels, 2);
      expect(report.monoDownmixApplied, isTrue);
      expect(report.resampler, 'none');
      expect(report.frameCount, 2);
      expect(report.lastFramePaddedSamples, 0);
    });
  });
}

Uint8List _wavPcm16({
  required int sampleRateHz,
  required int channels,
  required int frameCount,
}) {
  final dataSize = frameCount * channels * 2;
  final bytes = BytesBuilder(copy: false);

  void writeAscii(String value) => bytes.add(ascii.encode(value));
  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + dataSize);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(channels);
  writeUint32(sampleRateHz);
  writeUint32(sampleRateHz * channels * 2);
  writeUint16(channels * 2);
  writeUint16(16);
  writeAscii('data');
  writeUint32(dataSize);

  final pcm = Uint8List(dataSize);
  final data = ByteData.sublistView(pcm);
  for (var frame = 0; frame < frameCount; frame++) {
    for (var channel = 0; channel < channels; channel++) {
      final value = ((frame % 32) - 16) * (channel.isEven ? 200 : -200);
      data.setInt16(
        ((frame * channels) + channel) * 2,
        value,
        Endian.little,
      );
    }
  }
  bytes.add(pcm);
  return bytes.takeBytes();
}
