import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler_model.dart';

StreamTestHostLoadSampler createStreamTestHostLoadSampler(
  int? targetProcessId,
) {
  if (!Platform.isWindows) {
    return StreamTestUnavailableHostLoadSampler(
      reason: 'host load sampler is only implemented for Windows stream tests',
      sampleIntervalMs: _hostLoadSampleInterval.inMilliseconds,
      targetProcessLoadRequested: targetProcessId != null,
    );
  }
  if (_isAutomatedTestProcess) {
    return StreamTestUnavailableHostLoadSampler(
      reason: 'host load sampler is disabled during automated tests',
      sampleIntervalMs: _hostLoadSampleInterval.inMilliseconds,
      targetProcessLoadRequested: targetProcessId != null,
    );
  }
  return _WindowsPowerShellHostLoadSampler(
    targetProcessId: targetProcessId,
    sampleInterval: _hostLoadSampleInterval,
  );
}

const _hostLoadSampleInterval = Duration(seconds: 2);
const _maxHostLoadSamples = 600;
const _hostLoadStopTimeout = Duration(seconds: 2);

bool get _isAutomatedTestProcess {
  final executable = Platform.resolvedExecutable.toLowerCase();
  return executable.contains('flutter_tester') ||
      Platform.environment['FLUTTER_TEST'] == 'true';
}

class _WindowsPowerShellHostLoadSampler implements StreamTestHostLoadSampler {
  _WindowsPowerShellHostLoadSampler({
    required this.targetProcessId,
    required this.sampleInterval,
  });

  final int? targetProcessId;
  final Duration sampleInterval;
  final _samples = <StreamTestHostLoadSample>[];
  final _stderrLines = <String>[];
  int _droppedSampleCount = 0;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  String? _unavailableReason;
  bool _stopped = false;

  @override
  Future<void> start() async {
    try {
      final process = await Process.start(
        'powershell.exe',
        const [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _hostLoadPowerShellScript,
        ],
        environment: {
          'INTERGALACTIC_STREAM_TEST_HOST_LOAD_INTERVAL_MS': sampleInterval
              .inMilliseconds
              .toString(),
          'INTERGALACTIC_STREAM_TEST_APP_PID': pid.toString(),
          'INTERGALACTIC_STREAM_TEST_TARGET_PID':
              targetProcessId?.toString() ?? '',
        },
      );
      _process = process;
      _stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine, onError: _handleStdoutError);
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStderrLine, onError: _handleStdoutError);
    } catch (_) {
      _unavailableReason = 'host load sampler failed to start';
    }
  }

  @override
  Future<StreamTestHostLoadReport> stop() async {
    if (_stopped) {
      return _buildReport();
    }
    _stopped = true;
    final process = _process;
    if (process != null) {
      try {
        process.kill();
        await process.exitCode.timeout(_hostLoadStopTimeout);
      } catch (_) {
        _unavailableReason ??= 'host load sampler did not stop cleanly';
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    return _buildReport();
  }

  StreamTestHostLoadReport _buildReport() {
    if (_samples.isEmpty) {
      return StreamTestHostLoadReport.unavailable(
        reason: _unavailableReason ?? 'host load sampler emitted no samples',
        sampleIntervalMs: sampleInterval.inMilliseconds,
        targetProcessLoadRequested: targetProcessId != null,
      );
    }
    return StreamTestHostLoadReport(
      samples: _samples,
      sampleIntervalMs: sampleInterval.inMilliseconds,
      targetProcessLoadRequested: targetProcessId != null,
      unavailableReason: _unavailableReason,
      droppedSampleCount: _droppedSampleCount,
    );
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return;
      }
      if (_samples.length >= _maxHostLoadSamples) {
        _droppedSampleCount += 1;
        return;
      }
      _samples.add(
        StreamTestHostLoadSample.fromJson(decoded.cast<String, Object?>()),
      );
    } catch (_) {
      _unavailableReason ??= 'host load sampler emitted an unparsable sample';
    }
  }

  void _handleStderrLine(String line) {
    if (_stderrLines.length >= 3) {
      return;
    }
    if (line.trim().isNotEmpty) {
      _stderrLines.add(line.trim());
      _unavailableReason ??= 'host load sampler emitted stderr';
    }
  }

  void _handleStdoutError(Object _) {
    _unavailableReason ??= 'host load sampler stream failed';
  }
}

const _hostLoadPowerShellScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$intervalMs = 2000
[int]::TryParse($env:INTERGALACTIC_STREAM_TEST_HOST_LOAD_INTERVAL_MS, [ref]$intervalMs) | Out-Null
if ($intervalMs -lt 500) { $intervalMs = 500 }
[int]$appPidNumber = 0
$appPidValue = $null
if ([int]::TryParse($env:INTERGALACTIC_STREAM_TEST_APP_PID, [ref]$appPidNumber)) {
  $appPidValue = $appPidNumber
}
[int]$targetPidNumber = 0
$targetPidValue = $null
if ([int]::TryParse($env:INTERGALACTIC_STREAM_TEST_TARGET_PID, [ref]$targetPidNumber)) {
  $targetPidValue = $targetPidNumber
}
$processorCount = [Math]::Max(1, [Environment]::ProcessorCount)
$previousCpu = @{}
$lastGpu = @{}

function RoundOrNull($value) {
  if ($null -eq $value) { return $null }
  return [Math]::Round([double]$value, 2)
}

function ClampPercent($value) {
  if ($null -eq $value) { return $null }
  return [Math]::Min(100, [Math]::Max(0, [double]$value))
}

function NewCounter([string]$category, [string]$counter, [string]$instance) {
  try {
    if ([string]::IsNullOrWhiteSpace($instance)) {
      return New-Object Diagnostics.PerformanceCounter -ArgumentList $category, $counter
    }
    return New-Object Diagnostics.PerformanceCounter -ArgumentList $category, $counter, $instance
  } catch {
    return $null
  }
}

function GetCounterValue($counter) {
  if ($null -eq $counter) { return $null }
  try {
    return [double]$counter.NextValue()
  } catch {
    return $null
  }
}

$systemCpuCounter = NewCounter 'Processor' '% Processor Time' '_Total'
$memoryAvailableCounter = NewCounter 'Memory' 'Available MBytes' $null
$memoryUsedCounter = NewCounter 'Memory' '% Committed Bytes In Use' $null
try {
  if ($null -ne $systemCpuCounter) {
    $systemCpuCounter.NextValue() | Out-Null
    Start-Sleep -Milliseconds 250
  }
} catch {}

function GetProcessCpuPercent($procId, [string]$key) {
  if ($null -eq $procId) { return $null }
  $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
  if ($null -eq $proc) { return $null }
  $now = [DateTime]::UtcNow
  $cpu = [double]$proc.CPU
  if ($previousCpu.ContainsKey($key)) {
    $previous = $previousCpu[$key]
    $elapsed = ($now - $previous.Time).TotalSeconds
    $delta = $cpu - [double]$previous.Cpu
    $previousCpu[$key] = @{ Time = $now; Cpu = $cpu }
    if ($elapsed -gt 0 -and $delta -ge 0) {
      return ClampPercent (($delta / ($elapsed * $processorCount)) * 100)
    }
  } else {
    $previousCpu[$key] = @{ Time = $now; Cpu = $cpu }
  }
  return $null
}

function GetGpuUtilization {
  $gpu3d = 0.0
  $gpuCopy = 0.0
  $gpuVideoEncode = 0.0
  $gpuVideoDecode = 0.0
  $gpuCompute = 0.0
  $hasAny = $false
  try {
    $category = New-Object Diagnostics.PerformanceCounterCategory -ArgumentList 'GPU Engine'
    foreach ($instance in $category.GetInstanceNames()) {
      $normalizedPath = $instance.ToLowerInvariant() -replace '[^a-z0-9]', ''
      if (-not ($normalizedPath.Contains('engtype3d') -or
          $normalizedPath.Contains('engtypevideoencode') -or
          $normalizedPath.Contains('engtypevideodecode') -or
          $normalizedPath.Contains('engtypecopy') -or
          $normalizedPath.Contains('engtypecompute'))) {
        continue
      }
      $counter = NewCounter 'GPU Engine' 'Utilization Percentage' $instance
      $value = GetCounterValue $counter
      if ($null -eq $value) { continue }
      if ($normalizedPath.Contains('engtype3d')) {
        $gpu3d += $value
        $hasAny = $true
      } elseif ($normalizedPath.Contains('engtypevideoencode')) {
        $gpuVideoEncode += $value
        $hasAny = $true
      } elseif ($normalizedPath.Contains('engtypevideodecode')) {
        $gpuVideoDecode += $value
        $hasAny = $true
      } elseif ($normalizedPath.Contains('engtypecopy')) {
        $gpuCopy += $value
        $hasAny = $true
      } elseif ($normalizedPath.Contains('engtypecompute')) {
        $gpuCompute += $value
        $hasAny = $true
      }
    }
  } catch {}
  if (-not $hasAny) { return @{} }
  return @{
    gpu3dPercent = RoundOrNull (ClampPercent $gpu3d)
    gpuCopyPercent = RoundOrNull (ClampPercent $gpuCopy)
    gpuVideoEncodePercent = RoundOrNull (ClampPercent $gpuVideoEncode)
    gpuVideoDecodePercent = RoundOrNull (ClampPercent $gpuVideoDecode)
    gpuComputePercent = RoundOrNull (ClampPercent $gpuCompute)
  }
}

function GetGpuDedicatedMemoryMb {
  try {
    $category = New-Object Diagnostics.PerformanceCounterCategory -ArgumentList 'GPU Adapter Memory'
    $total = 0.0
    $hasAny = $false
    foreach ($instance in $category.GetInstanceNames()) {
      $counter = NewCounter 'GPU Adapter Memory' 'Dedicated Usage' $instance
      $value = GetCounterValue $counter
      if ($null -eq $value) { continue }
      $total += [double]$value
      $hasAny = $true
    }
    if ($hasAny) {
      return RoundOrNull ($total / 1MB)
    }
  } catch {}
  return $null
}

while ($true) {
  $timestamp = (Get-Date).ToUniversalTime().ToString('o')
  $gpu = $lastGpu
  $sample = [ordered]@{
    timestamp = $timestamp
    systemCpuPercent = RoundOrNull (ClampPercent (GetCounterValue $systemCpuCounter))
    memoryUsedPercent = RoundOrNull (ClampPercent (GetCounterValue $memoryUsedCounter))
    memoryAvailableMb = RoundOrNull (GetCounterValue $memoryAvailableCounter)
    appCpuPercent = RoundOrNull (GetProcessCpuPercent $appPidValue 'app')
    targetCpuPercent = RoundOrNull (GetProcessCpuPercent $targetPidValue 'target')
    gpu3dPercent = $gpu.gpu3dPercent
    gpuCopyPercent = $gpu.gpuCopyPercent
    gpuVideoEncodePercent = $gpu.gpuVideoEncodePercent
    gpuVideoDecodePercent = $gpu.gpuVideoDecodePercent
    gpuComputePercent = $gpu.gpuComputePercent
    gpuDedicatedMemoryMb = $gpu.gpuDedicatedMemoryMb
  }
  [Console]::Out.WriteLine(($sample | ConvertTo-Json -Compress -Depth 3))
  [Console]::Out.Flush()
  $lastGpu = GetGpuUtilization
  $lastGpu['gpuDedicatedMemoryMb'] = GetGpuDedicatedMemoryMb
  Start-Sleep -Milliseconds $intervalMs
}
''';
