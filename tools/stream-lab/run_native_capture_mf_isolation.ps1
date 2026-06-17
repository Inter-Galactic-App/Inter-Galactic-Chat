param(
  [int]$SourcePid = 0,
  [string]$SourceTitle = "Baldur's Gate 3",

  [switch]$LaunchSyntheticTarget,
  [int]$Width = 2560,
  [int]$Height = 1440,
  [string]$Fps = '60',
  [ValidateSet('windowed', 'borderless')]
  [string]$SyntheticMode = 'windowed',
  [ValidateSet('low-motion', 'high-motion', 'gameplay', 'ui-heavy')]
  [string]$SyntheticScene = 'high-motion',
  [ValidateSet('r8g8b8a8', 'r10g10b10a2')]
  [string]$SyntheticFormat = 'r10g10b10a2',
  [bool]$SyntheticHdrLike = $true,

  [int]$TargetWidth = 1280,
  [int]$TargetHeight = 720,
  [int]$TargetFps = 30,
  [int]$DurationSeconds = 10,
  [double]$MinSustainedFps = 29.0,

  [string]$BenchmarkReportJson = '',
  [string]$BenchmarkScript = '',
  [string]$HelperPath = '',
  [string]$SyntheticTargetPath = '',
  [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Resolve-WorkspaceRoot([string]$RepoRoot) {
  return (Resolve-Path (Join-Path $RepoRoot '..\..')).Path
}

function New-SafeDirectory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Get-JsonProperty([object]$Object, [string]$Name) {
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-JsonString([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  return [string]$value
}

function Get-JsonDouble([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  $parsed = 0.0
  $text = [string]$value
  if ([double]::TryParse(
      $text,
      [System.Globalization.NumberStyles]::Float,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    )) {
    return $parsed
  }
  return $null
}

function Add-IfMissing(
  [System.Collections.Generic.List[string]]$List,
  [object]$Value,
  [string]$Name
) {
  if ($null -eq $Value) {
    [void]$List.Add($Name)
  }
}

function Add-IfTrue(
  [System.Collections.Generic.List[string]]$List,
  [bool]$Condition,
  [string]$Name
) {
  if ($Condition) {
    [void]$List.Add($Name)
  }
}

function Get-FrameRateFromCount([double]$Frames, [double]$DurationSeconds) {
  if ($DurationSeconds -le 0) {
    return $null
  }
  return [Math]::Round($Frames / $DurationSeconds, 3)
}

function Invoke-LocalCaptureBenchmark(
  [string]$ScriptPath,
  [string]$OutputRootPath
) {
  $benchmarkArgs = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $ScriptPath,
    '-Backend',
    'future-game-d3d11-hook',
    '-Width',
    "$Width",
    '-Height',
    "$Height",
    '-Fps',
    $Fps,
    '-DurationSeconds',
    "$DurationSeconds",
    '-TargetWidth',
    "$TargetWidth",
    '-TargetHeight',
    "$TargetHeight",
    '-TargetFps',
    "$TargetFps",
    '-PublicationReadbackMode',
    'proof-only',
    '-PublicationOutputFormat',
    'nv12',
    '-PublicationEncoderProof',
    'h264-mf',
    '-PublicationProofFrames',
    '0',
    '-OutputRoot',
    $OutputRootPath
  )

  if ($SourcePid -gt 0) {
    $benchmarkArgs += @('-SourcePid', "$SourcePid")
  } else {
    $benchmarkArgs += @('-SourceTitle', $SourceTitle)
  }

  if ($LaunchSyntheticTarget) {
    $benchmarkArgs += @(
      '-LaunchSyntheticTarget',
      '-SyntheticMode',
      $SyntheticMode,
      '-SyntheticScene',
      $SyntheticScene,
      '-SyntheticFormat',
      $SyntheticFormat
    )
    if ($SyntheticHdrLike) {
      $benchmarkArgs += @('-SyntheticHdrLike')
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($HelperPath)) {
    $benchmarkArgs += @('-HelperPath', $HelperPath)
  }
  if (-not [string]::IsNullOrWhiteSpace($SyntheticTargetPath)) {
    $benchmarkArgs += @('-SyntheticTargetPath', $SyntheticTargetPath)
  }

  $shell = (Get-Process -Id $PID).Path
  $startedAt = Get-Date
  $output = & $shell @benchmarkArgs 2>&1
  $exitCode = $LASTEXITCODE
  $outputText = ($output | ForEach-Object { [string]$_ }) -join "`n"

  $markdownPath = $null
  foreach ($line in ($outputText -split "`n")) {
    if ($line -match 'Local stream benchmark report:\s*(.+)$') {
      $markdownPath = $Matches[1].Trim()
    }
  }

  $jsonPath = $null
  if (-not [string]::IsNullOrWhiteSpace($markdownPath)) {
    $candidate = Join-Path (Split-Path -Parent $markdownPath) 'local-capture-benchmark.json'
    if (Test-Path -LiteralPath $candidate) {
      $jsonPath = (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  if ([string]::IsNullOrWhiteSpace($jsonPath)) {
    $candidate = Get-ChildItem -LiteralPath $OutputRootPath -Directory -Filter 'local-capture-*' |
      Where-Object { $_.LastWriteTime -ge $startedAt.AddSeconds(-2) } |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object {
        $path = Join-Path $_.FullName 'local-capture-benchmark.json'
        if (Test-Path -LiteralPath $path) {
          Get-Item -LiteralPath $path
        }
      } |
      Select-Object -First 1
    if ($candidate) {
      $jsonPath = $candidate.FullName
    }
  }

  if ($exitCode -ne 0 -and [string]::IsNullOrWhiteSpace($jsonPath)) {
    throw "Local capture benchmark failed with exit code $exitCode before writing a report.`n$outputText"
  }
  if ([string]::IsNullOrWhiteSpace($jsonPath)) {
    throw "Local capture benchmark did not expose local-capture-benchmark.json.`n$outputText"
  }

  return [ordered]@{
    exitCode = $exitCode
    stdout = $outputText
    jsonPath = $jsonPath
  }
}

function Write-IsolationReport(
  [string]$JsonPath,
  [object]$BenchmarkRun,
  [string]$ReportDirectory
) {
  $benchmark = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
  $runDirectory = if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    Split-Path -Parent $JsonPath
  } else {
    New-SafeDirectory $ReportDirectory
    $ReportDirectory
  }
  $publication = Get-JsonProperty $benchmark 'publicationHandoff'
  $hook = Get-JsonProperty $benchmark 'hookMetadata'
  $requested = Get-JsonProperty $benchmark 'requested'

  $duration = Get-JsonDouble $requested 'durationSeconds'
  if ($null -eq $duration) {
    $duration = [double]$DurationSeconds
  }
  $targetFps = Get-JsonDouble $requested 'targetFps'
  if ($null -eq $targetFps) {
    $targetFps = [double]$TargetFps
  }
  $frameBudgetMs = [Math]::Round(1000.0 / [Math]::Max(1.0, $targetFps), 3)

  $status = Get-JsonString $benchmark 'status'
  $sourceFormat = Get-JsonString $hook 'sourceFormat'
  $presentFps = Get-JsonDouble $hook 'presentFps'
  $presentP95Ms = Get-JsonDouble $hook 'presentGapP95Ms'
  $presentMaxMs = Get-JsonDouble $hook 'presentGapMaxMs'
  $outputFormat = Get-JsonString $publication 'outputFormat'
  $encoderFormat = Get-JsonString $publication 'encoderFormat'
  $outputWidth = Get-JsonDouble $publication 'outputWidth'
  $outputHeight = Get-JsonDouble $publication 'outputHeight'
  $outputFps = Get-JsonDouble $publication 'outputFps'
  $outputP95Ms = Get-JsonDouble $publication 'outputGapP95Ms'
  $outputMaxMs = Get-JsonDouble $publication 'outputGapMaxMs'
  $nv12Frames = Get-JsonDouble $publication 'nv12OutputFrames'
  $nv12Failures = Get-JsonDouble $publication 'nv12ConvertFailures'
  $nv12AvgMs = Get-JsonDouble $publication 'nv12ConvertAvgMs'
  $encoderMode = Get-JsonString $publication 'encoderProofMode'
  $encoderFrames = Get-JsonDouble $publication 'encoderProofFramesSubmitted'
  $encoderFailures = Get-JsonDouble $publication 'encoderProofWriteFailures'
  $encoderBytes = Get-JsonDouble $publication 'encoderProofOutputBytes'
  $encoderSubmitAvgMs = Get-JsonDouble $publication 'encoderProofSubmitAvgMs'
  $encoderSubmitP95Ms = Get-JsonDouble $publication 'encoderProofSubmitP95Ms'
  $encoderSubmitMaxMs = Get-JsonDouble $publication 'encoderProofSubmitMaxMs'
  $encoderGpuCopyAvgMs = Get-JsonDouble $publication 'encoderProofGpuCopyAvgMs'
  $encoderGpuCopyP95Ms = Get-JsonDouble $publication 'encoderProofGpuCopyP95Ms'
  $encoderInitMs = Get-JsonDouble $publication 'encoderProofInitMs'
  $encoderFinalizeMs = Get-JsonDouble $publication 'encoderProofFinalizeMs'
  $encoderFps = if ($null -ne $encoderFrames) {
    Get-FrameRateFromCount $encoderFrames $duration
  } else {
    $null
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  Add-IfMissing $missing $publication 'publicationHandoff'
  Add-IfMissing $missing $hook 'hookMetadata'
  Add-IfMissing $missing $outputFps 'publicationHandoff.outputFps'
  Add-IfMissing $missing $encoderMode 'publicationHandoff.encoderProofMode'
  Add-IfMissing $missing $encoderFrames 'publicationHandoff.encoderProofFramesSubmitted'
  Add-IfMissing $missing $encoderFailures 'publicationHandoff.encoderProofWriteFailures'
  Add-IfMissing $missing $encoderBytes 'publicationHandoff.encoderProofOutputBytes'

  $issues = [System.Collections.Generic.List[string]]::new()
  Add-IfTrue $issues ($status -ne 'completed') "benchmark_status_$status"
  Add-IfTrue $issues ($outputFormat -ne 'nv12') "wrong_output_format_$outputFormat"
  Add-IfTrue $issues ($encoderMode -ne 'h264-mf') "wrong_encoder_proof_mode_$encoderMode"
  Add-IfTrue $issues ($null -ne $outputWidth -and [int]$outputWidth -ne $TargetWidth) "wrong_output_width_$outputWidth"
  Add-IfTrue $issues ($null -ne $outputHeight -and [int]$outputHeight -ne $TargetHeight) "wrong_output_height_$outputHeight"
  Add-IfTrue $issues ($null -ne $presentFps -and $presentFps -lt $MinSustainedFps) 'source_present_below_gate'
  Add-IfTrue $issues ($null -ne $outputFps -and $outputFps -lt $MinSustainedFps) 'publication_handoff_below_gate'
  Add-IfTrue $issues ($null -ne $encoderFrames -and $encoderFrames -le 0) 'mf_encoder_no_submitted_frames'
  Add-IfTrue $issues ($null -ne $nv12Failures -and $nv12Failures -gt 0) 'nv12_conversion_failures'
  Add-IfTrue $issues ($null -ne $encoderFailures -and $encoderFailures -gt 0) 'mf_encoder_write_failures'
  Add-IfTrue $issues ($null -ne $encoderBytes -and $encoderBytes -le 0) 'mf_encoder_no_output_bytes'
  Add-IfTrue $issues ($null -ne $encoderSubmitP95Ms -and $encoderSubmitP95Ms -gt $frameBudgetMs) 'mf_encoder_submit_p95_over_frame_budget'

  $warnings = [System.Collections.Generic.List[string]]::new()
  Add-IfTrue $warnings ($sourceFormat -ne 'r10g10b10a2') "source_format_not_r10g10b10a2_$sourceFormat"
  Add-IfTrue $warnings ($null -ne $encoderFps -and $encoderFps -lt $MinSustainedFps) 'encoder_frame_count_over_requested_duration_below_gate'
  Add-IfTrue $warnings ($null -ne $outputP95Ms -and $outputP95Ms -gt ($frameBudgetMs * 1.5)) 'publication_gap_p95_tail'
  Add-IfTrue $warnings ($null -ne $presentMaxMs -and $presentMaxMs -gt ($frameBudgetMs * 4.0)) 'source_present_max_tail'
  Add-IfTrue $warnings ($null -ne $outputMaxMs -and $outputMaxMs -gt ($frameBudgetMs * 4.0)) 'publication_output_max_tail'

  $result = if ($missing.Count -gt 0) {
    'inconclusive_native_capture_mf'
  } elseif ($issues.Count -eq 0) {
    'passed_native_capture_mf_720p30'
  } else {
    'failed_native_capture_mf_720p30'
  }

  $nextBoundary = if ($result -eq 'passed_native_capture_mf_720p30') {
    'webrtc_onframe_or_native_encoded_frame_integration'
  } elseif ($issues -contains 'mf_encoder_write_failures' -or
      $issues -contains 'mf_encoder_no_output_bytes' -or
      $issues -contains 'mf_encoder_no_submitted_frames' -or
      $issues -contains 'mf_encoder_submit_p95_over_frame_budget') {
    'media_foundation_native_input'
  } elseif ($missing.Count -gt 0) {
    'diagnostic_coverage'
  } else {
    'local_capture_gpu_conversion_or_source_cadence'
  }

  $recommendation = if ($result -eq 'passed_native_capture_mf_720p30') {
    'Stop tuning local queue constants for this evidence shape; isolate WebRTC OnFrame/native encoded-frame handoff before another broad live-test loop.'
  } elseif ($result -eq 'inconclusive_native_capture_mf') {
    'Repair the local harness diagnostic coverage before using this run as a go/no-go gate.'
  } else {
    'Do not spend another live BG3 call run yet; fix the local capture, NV12 conversion, or Media Foundation proof boundary indicated by the failing fields.'
  }

  $report = [ordered]@{
    schema = 'intergalactic.nativeCaptureMfIsolation.v1'
    status = $result
    benchmarkReportJson = $JsonPath
    benchmarkExitCode = if ($BenchmarkRun) { $BenchmarkRun.exitCode } else { $null }
    target = [ordered]@{
      width = $TargetWidth
      height = $TargetHeight
      fps = $TargetFps
      minSustainedFps = $MinSustainedFps
      frameBudgetMs = $frameBudgetMs
    }
    boundaries = [ordered]@{
      matrixTested = $false
      liveKitTested = $false
      webRtcSenderTested = $false
      networkTested = $false
      receiverTested = $false
      localD3d11CaptureTested = $true
      localMediaFoundationEncoderTested = $true
    }
    evidence = [ordered]@{
      benchmarkStatus = $status
      sourceFormat = $sourceFormat
      presentFps = $presentFps
      presentGapP95Ms = $presentP95Ms
      presentGapMaxMs = $presentMaxMs
      outputFormat = $outputFormat
      encoderFormat = $encoderFormat
      outputWidth = $outputWidth
      outputHeight = $outputHeight
      handoffOutputFps = $outputFps
      handoffOutputGapP95Ms = $outputP95Ms
      handoffOutputGapMaxMs = $outputMaxMs
      nv12OutputFrames = $nv12Frames
      nv12ConvertFailures = $nv12Failures
      nv12ConvertAvgMs = $nv12AvgMs
      encoderProofMode = $encoderMode
      encoderProofFramesSubmitted = $encoderFrames
      encoderProofEstimatedFps = $encoderFps
      encoderProofWriteFailures = $encoderFailures
      encoderProofOutputBytes = $encoderBytes
      encoderProofSubmitAvgMs = $encoderSubmitAvgMs
      encoderProofSubmitP95Ms = $encoderSubmitP95Ms
      encoderProofSubmitMaxMs = $encoderSubmitMaxMs
      encoderProofGpuCopyAvgMs = $encoderGpuCopyAvgMs
      encoderProofGpuCopyP95Ms = $encoderGpuCopyP95Ms
      encoderProofInitMs = $encoderInitMs
      encoderProofFinalizeMs = $encoderFinalizeMs
    }
    missingEvidence = @($missing)
    failingGates = @($issues)
    warnings = @($warnings)
    nextBoundary = $nextBoundary
    recommendation = $recommendation
  }

  $jsonOut = Join-Path $runDirectory 'native-capture-mf-isolation.json'
  $mdOut = Join-Path $runDirectory 'native-capture-mf-isolation.md'
  $report | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $jsonOut -Encoding UTF8

  $missingText = if ($missing.Count -gt 0) { $missing -join ', ' } else { 'none' }
  $issueText = if ($issues.Count -gt 0) { $issues -join ', ' } else { 'none' }
  $warningText = if ($warnings.Count -gt 0) { $warnings -join ', ' } else { 'none' }

  @(
    '# Native Capture To Media Foundation Isolation'
    ''
    '## Summary'
    ''
    "- Status: $result"
    "- Benchmark report: $JsonPath"
    "- Target gate: ${TargetWidth}x${TargetHeight}@${TargetFps}, minimum sustained FPS $MinSustainedFps"
    "- Next boundary: $nextBoundary"
    "- Recommendation: $recommendation"
    ''
    '## Evidence'
    ''
    "- Source format: $sourceFormat"
    "- Present FPS/gap p95/max: $presentFps / $presentP95Ms / $presentMaxMs ms"
    "- Handoff output FPS/gap p95/max: $outputFps / $outputP95Ms / $outputMaxMs ms"
    "- Output format/resolution: $outputFormat / ${outputWidth}x${outputHeight}"
    "- NV12 frames/failures/convert avg: $nv12Frames / $nv12Failures / $nv12AvgMs ms"
    "- Encoder proof mode/format: $encoderMode / $encoderFormat"
    "- Encoder proof frames/estimated FPS/failures/output bytes: $encoderFrames / $encoderFps / $encoderFailures / $encoderBytes"
    "- Encoder submit avg/p95/max: $encoderSubmitAvgMs / $encoderSubmitP95Ms / $encoderSubmitMaxMs ms"
    "- Encoder GPU-copy avg/p95: $encoderGpuCopyAvgMs / $encoderGpuCopyP95Ms ms"
    "- Encoder init/finalize: $encoderInitMs / $encoderFinalizeMs ms"
    ''
    '## Gate Details'
    ''
    "- Missing evidence: $missingText"
    "- Failing gates: $issueText"
    "- Warnings: $warningText"
    ''
    '## Boundaries'
    ''
    'This isolation run bypasses Matrix, LiveKit, WebRTC sender stats, network, and the receiver. It measures the local D3D11 hook, shared-texture host path, GPU NV12 publication handoff, and local Media Foundation H.264 proof only.'
    ''
    '## Output Files'
    ''
    "- Isolation JSON: $jsonOut"
    "- Isolation Markdown: $mdOut"
    "- Benchmark JSON: $JsonPath"
  ) | Set-Content -LiteralPath $mdOut -Encoding UTF8

  Write-Host "Native capture-to-MF isolation report: $mdOut"
  Write-Host "Native capture-to-MF isolation status: $result"
  return [ordered]@{
    status = $result
    json = $jsonOut
    markdown = $mdOut
  }
}

$repoRoot = Resolve-RepoRoot
$workspaceRoot = Resolve-WorkspaceRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $workspaceRoot 'runtime\stream-lab\local-results'
}
New-SafeDirectory $OutputRoot

if ([string]::IsNullOrWhiteSpace($BenchmarkScript)) {
  $BenchmarkScript = Join-Path $PSScriptRoot 'run_local_capture_benchmark.ps1'
}
$BenchmarkScript = (Resolve-Path -LiteralPath $BenchmarkScript).Path

$benchmarkRun = $null
$analyzingExistingReport = -not [string]::IsNullOrWhiteSpace($BenchmarkReportJson)
if (-not $analyzingExistingReport) {
  $benchmarkRun = Invoke-LocalCaptureBenchmark `
    -ScriptPath $BenchmarkScript `
    -OutputRootPath $OutputRoot
  $BenchmarkReportJson = $benchmarkRun.jsonPath
} else {
  $BenchmarkReportJson = (Resolve-Path -LiteralPath $BenchmarkReportJson).Path
}

$isolationReportDirectory = ''
if ($analyzingExistingReport) {
  $isolationStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $isolationReportDirectory = Join-Path $OutputRoot "native-capture-mf-isolation-$isolationStamp"
}

$written = Write-IsolationReport `
  -JsonPath $BenchmarkReportJson `
  -BenchmarkRun $benchmarkRun `
  -ReportDirectory $isolationReportDirectory

if ($written.status -eq 'failed_native_capture_mf_720p30') {
  exit 2
}
if ($written.status -eq 'inconclusive_native_capture_mf') {
  exit 3
}
