param(
  [int]$SourcePid = 0,
  [string]$SourceTitle = "Baldur's Gate 3",
  [int]$TargetWidth = 1280,
  [int]$TargetHeight = 720,
  [int]$TargetFps = 30,
  [int]$DurationSeconds = 10,
  [double]$MinSustainedFps = 29.0,
  [string]$NativeMfIsolationJson = '',
  [string]$WebrtcOnFrameIsolationJson = '',
  [string]$StreamTestJson = '',
  [string]$NativeMfScript = '',
  [string]$WebrtcOnFrameScript = '',
  [string]$OutputRoot = '',
  [switch]$AnalyzeOnly,
  [switch]$SkipNativeMf,
  [switch]$SkipWebrtcOnFrame
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
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
  }
}

function Get-JsonProperty([object]$Object, [string]$Name) {
  if ($null -eq $Object) {
    return $null
  }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      return $Object[$Name]
    }
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

function Resolve-OptionalJson([string]$Path, [string]$Label) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ''
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "$Label was not found: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-LatestReportJson([string]$Root, [string]$Filter, [datetime]$Since, [switch]$AllowHistoricalFallback) {
  if (-not (Test-Path -LiteralPath $Root)) {
    return ''
  }
  $threshold = if ($Since -le ([datetime]::MinValue).AddSeconds(2)) {
    [datetime]::MinValue
  } else {
    $Since.AddSeconds(-2)
  }
  $candidate = Get-ChildItem -LiteralPath $Root -Recurse -Filter $Filter -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $threshold } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) {
    return $candidate.FullName
  }
  if ($AllowHistoricalFallback) {
    $fallback = Get-ChildItem -LiteralPath $Root -Recurse -Filter $Filter -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($fallback) {
      return $fallback.FullName
    }
  }
  return ''
}

function Invoke-IsolationWrapper(
  [string]$ScriptPath,
  [string[]]$Arguments,
  [string]$OutputRootPath,
  [string]$ReportFileName
) {
  $startedAt = Get-Date
  $shell = (Get-Process -Id $PID).Path
  $output = & $shell @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  $outputText = ($output | ForEach-Object { [string]$_ }) -join "`n"
  $jsonPath = ''
  if ($exitCode -eq 0) {
    $jsonPath = Get-LatestReportJson -Root $OutputRootPath -Filter $ReportFileName -Since $startedAt
  }
  return [ordered]@{
    script = $ScriptPath
    exitCode = $exitCode
    stdout = $outputText
    jsonPath = $jsonPath
  }
}

function Get-Report([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-FirstArrayItem([object]$Value) {
  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [array]) {
    if ($Value.Length -eq 0) {
      return $null
    }
    return $Value[0]
  }
  return @($Value) | Select-Object -First 1
}

function Test-PassedNativeMf([object]$Report) {
  return (Get-JsonString $Report 'status') -eq 'passed_native_capture_mf_720p30'
}

function Test-PassedWebrtcOnFrame([object]$Report) {
  return (Get-JsonString $Report 'status') -eq 'passed_webrtc_onframe_isolation'
}

function Read-LiveStreamEvidence([string]$JsonPath, [double]$MinFps) {
  if ([string]::IsNullOrWhiteSpace($JsonPath)) {
    return [ordered]@{
      compared = $false
    }
  }
  $stream = Get-Report $JsonPath
  if ($null -eq $stream) {
    return [ordered]@{
      compared = $false
      missing = 'stream test JSON could not be parsed'
    }
  }
  $preset = Get-FirstArrayItem (Get-JsonProperty $stream 'presetResults')
  $score = Get-JsonProperty $preset 'score'
  $bottleneck = Get-JsonProperty $score 'bottleneck'
  $summary = Get-JsonProperty $score 'summary'
  if ($null -eq $summary) {
    $summary = Get-JsonProperty $preset 'summary'
  }
  $native = Get-JsonProperty $summary 'nativeDiagnostics'
  $handoff = Get-JsonProperty $summary 'senderHandoffDiagnostics'
  $mediaFoundation = Get-JsonProperty $handoff 'mediaFoundation'
  $label = Get-JsonString $bottleneck 'label'
  $captureFps = Get-JsonDouble $summary 'averageCaptureFps'
  $encodeFps = Get-JsonDouble $summary 'averageEncodeFps'
  $sendFps = Get-JsonDouble $summary 'averageSendFps'
  $onFrameCall = Get-JsonDouble $native 'averageGameCaptureDeliveryOnFrameCallMs'
  $onFrameCallMax = Get-JsonDouble $native 'maxGameCaptureDeliveryOnFrameCallMs'
  $nativeFailures = Get-JsonDouble $native 'gameCaptureNativeNv12Failures'
  $cpuFallback = Get-JsonDouble $native 'gameCaptureCpuFallbackFrames'
  $fenceSignaled = Get-JsonDouble $native 'gameCaptureNativeNv12FenceSignaledFrames'
  $nativeReadyDropped = Get-JsonDouble $native 'gameCaptureNativeNv12ReadyDroppedFrames'
  $streamSlow = $false
  foreach ($fps in @($captureFps, $encodeFps, $sendFps)) {
    if ($null -ne $fps -and $fps -lt $MinFps) {
      $streamSlow = $true
    }
  }
  return [ordered]@{
    compared = $true
    jsonPath = $JsonPath
    bottleneck = $label
    captureFps = $captureFps
    encodeFps = $encodeFps
    sendFps = $sendFps
    streamSlow = $streamSlow
    liveOnFrameCallMs = $onFrameCall
    liveOnFrameCallMaxMs = $onFrameCallMax
    nativeNv12Failures = $nativeFailures
    cpuFallbackFrames = $cpuFallback
    nativeNv12FenceSignaled = $fenceSignaled
    nativeNv12ReadyDropped = $nativeReadyDropped
    senderHandoffDiagnosticsPresent = $null -ne $handoff
    liveEncodedCallbackMs = Get-JsonDouble $mediaFoundation 'averageEncodedCallbackMs'
    liveEncodedCallbackMaxMs = Get-JsonDouble $mediaFoundation 'maxEncodedCallbackMs'
    liveEncodedCallbackQueueWaitMs = Get-JsonDouble $mediaFoundation 'averageEncodedCallbackQueueWaitMs'
    liveEncodedCallbackQueueWaitMaxMs = Get-JsonDouble $mediaFoundation 'maxEncodedCallbackQueueWaitMs'
    liveEncodedCallbackQueueMax = Get-JsonDouble $mediaFoundation 'encodedCallbackQueueMax'
    liveEncodedCallbackDropsMax = Get-JsonDouble $mediaFoundation 'encodedCallbackDropsMax'
  }
}

$repoRoot = Resolve-RepoRoot
$workspaceRoot = Resolve-WorkspaceRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $workspaceRoot 'runtime\stream-lab\local-results'
}
New-SafeDirectory $OutputRoot

if ([string]::IsNullOrWhiteSpace($NativeMfScript)) {
  $NativeMfScript = Join-Path $PSScriptRoot 'run_native_capture_mf_isolation.ps1'
}
if ([string]::IsNullOrWhiteSpace($WebrtcOnFrameScript)) {
  $WebrtcOnFrameScript = Join-Path $PSScriptRoot 'run_webrtc_onframe_isolation.ps1'
}
$NativeMfScript = (Resolve-Path -LiteralPath $NativeMfScript).Path
$WebrtcOnFrameScript = (Resolve-Path -LiteralPath $WebrtcOnFrameScript).Path

$NativeMfIsolationJson = Resolve-OptionalJson $NativeMfIsolationJson 'Native MF isolation JSON'
$WebrtcOnFrameIsolationJson = Resolve-OptionalJson $WebrtcOnFrameIsolationJson 'WebRTC OnFrame isolation JSON'
$StreamTestJson = Resolve-OptionalJson $StreamTestJson 'Stream test JSON'

$nativeRun = $null
$webrtcRun = $null

if (-not $AnalyzeOnly -and -not $SkipNativeMf -and [string]::IsNullOrWhiteSpace($NativeMfIsolationJson)) {
  $args = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $NativeMfScript,
    '-TargetWidth',
    "$TargetWidth",
    '-TargetHeight',
    "$TargetHeight",
    '-TargetFps',
    "$TargetFps",
    '-DurationSeconds',
    "$DurationSeconds",
    '-MinSustainedFps',
    "$MinSustainedFps",
    '-OutputRoot',
    $OutputRoot
  )
  if ($SourcePid -gt 0) {
    $args += @('-SourcePid', "$SourcePid")
  } else {
    $args += @('-SourceTitle', $SourceTitle)
  }
  $nativeRun = Invoke-IsolationWrapper `
    -ScriptPath $NativeMfScript `
    -Arguments $args `
    -OutputRootPath $OutputRoot `
    -ReportFileName 'native-capture-mf-isolation.json'
  $NativeMfIsolationJson = $nativeRun.jsonPath
}

if ([string]::IsNullOrWhiteSpace($NativeMfIsolationJson) -and ($AnalyzeOnly -or $SkipNativeMf)) {
  $NativeMfIsolationJson = Get-LatestReportJson `
    -Root $OutputRoot `
    -Filter 'native-capture-mf-isolation.json' `
    -Since ([datetime]::MinValue) `
    -AllowHistoricalFallback
}

if (-not $AnalyzeOnly -and -not $SkipWebrtcOnFrame -and [string]::IsNullOrWhiteSpace($WebrtcOnFrameIsolationJson)) {
  $args = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $WebrtcOnFrameScript,
    '-TargetWidth',
    "$TargetWidth",
    '-TargetHeight',
    "$TargetHeight",
    '-TargetFps',
    "$TargetFps",
    '-DurationSeconds',
    "$DurationSeconds",
    '-MinSustainedFps',
    "$MinSustainedFps",
    '-OutputRoot',
    $OutputRoot
  )
  if ($SourcePid -gt 0) {
    $args += @('-SourcePid', "$SourcePid")
  } else {
    $args += @('-SourceTitle', $SourceTitle)
  }
  if (-not [string]::IsNullOrWhiteSpace($NativeMfIsolationJson)) {
    $args += @('-NativeMfIsolationJson', $NativeMfIsolationJson)
  }
  $webrtcRun = Invoke-IsolationWrapper `
    -ScriptPath $WebrtcOnFrameScript `
    -Arguments $args `
    -OutputRootPath $OutputRoot `
    -ReportFileName 'webrtc-onframe-isolation.json'
  $WebrtcOnFrameIsolationJson = $webrtcRun.jsonPath
}

if ([string]::IsNullOrWhiteSpace($WebrtcOnFrameIsolationJson) -and ($AnalyzeOnly -or $SkipWebrtcOnFrame)) {
  $WebrtcOnFrameIsolationJson = Get-LatestReportJson `
    -Root $OutputRoot `
    -Filter 'webrtc-onframe-isolation.json' `
    -Since ([datetime]::MinValue) `
    -AllowHistoricalFallback
}

$nativeReport = Get-Report $NativeMfIsolationJson
$webrtcReport = Get-Report $WebrtcOnFrameIsolationJson
$nativeEvidence = Get-JsonProperty $nativeReport 'evidence'
$webrtcEvidence = Get-JsonProperty $webrtcReport 'evidence'
$liveEvidence = Read-LiveStreamEvidence -JsonPath $StreamTestJson -MinFps $MinSustainedFps

$nativePassed = Test-PassedNativeMf $nativeReport
$webrtcPassed = Test-PassedWebrtcOnFrame $webrtcReport
$missing = [System.Collections.Generic.List[string]]::new()
if ($null -eq $nativeReport) {
  [void]$missing.Add('native-capture-mf-isolation.json')
}
if ($null -eq $webrtcReport) {
  [void]$missing.Add('webrtc-onframe-isolation.json')
}

$liveBottleneck = [string](Get-JsonProperty $liveEvidence 'bottleneck')
$liveCompared = [bool](Get-JsonProperty $liveEvidence 'compared')
$liveSlow = [bool](Get-JsonProperty $liveEvidence 'streamSlow')
$liveSenderHandoffLimited = $liveCompared -and $liveSlow -and (
  $liveBottleneck -eq 'encoder_handoff_limited' -or
  $liveBottleneck -eq 'webrtc_onframe_limited' -or
  $liveBottleneck -eq 'delivery_queue_limited' -or
  $liveBottleneck -eq 'native_nv12_ready_limited'
)

$status = if ($missing.Count -gt 0) {
  'inconclusive_native_sender_handoff'
} elseif (-not $nativePassed -or -not $webrtcPassed) {
  'failed_local_sender_handoff_prerequisite'
} elseif ($liveSenderHandoffLimited) {
  'failed_live_sender_handoff'
} elseif ($liveCompared -and -not $liveSlow) {
  'passed_live_sender_handoff'
} else {
  'passed_local_sender_prerequisites'
}

$nextBoundary = if ($status -eq 'passed_local_sender_prerequisites') {
  'one_bg3_dx11_smooth_720p30_live_call_test'
} elseif ($status -eq 'passed_live_sender_handoff') {
  'repeat_live_call_once_for_confirmation'
} elseif ($status -eq 'failed_live_sender_handoff') {
  'native_encoded_frame_or_webrtc_sender_handoff_design'
} elseif ($status -eq 'failed_local_sender_handoff_prerequisite') {
  'native_encoder_input_backpressure_or_sample_lifetime'
} else {
  'diagnostic_coverage'
}

$recommendation = if ($status -eq 'failed_live_sender_handoff') {
  'Local source and Media Foundation prerequisites are healthy, but live sender cadence is not. Stop tuning capture queue constants and design the deeper native encoded-frame/WebRTC sender handoff.'
} elseif ($status -eq 'failed_local_sender_handoff_prerequisite') {
  'Fix the failing local native MF or WebRTC OnFrame isolation gate before another live BG3 call test.'
} elseif ($status -eq 'passed_local_sender_prerequisites') {
  'Run exactly one live BG3 DX11 Smooth 1280x720@30 call test, then compare with this report.'
} elseif ($status -eq 'passed_live_sender_handoff') {
  'Live sender handoff met the local gate; repeat once only if confirmation is needed.'
} else {
  'Repair missing local isolation evidence before using this as a decision gate.'
}

$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $OutputRoot "native-sender-handoff-isolation-$runStamp"
New-SafeDirectory $runDirectory
$jsonOut = Join-Path $runDirectory 'native-sender-handoff-isolation.json'
$mdOut = Join-Path $runDirectory 'native-sender-handoff-isolation.md'

$report = [ordered]@{
  schema = 'intergalactic.nativeSenderHandoffIsolation.v1'
  status = $status
  target = [ordered]@{
    width = $TargetWidth
    height = $TargetHeight
    fps = $TargetFps
    minSustainedFps = $MinSustainedFps
  }
  inputs = [ordered]@{
    nativeMfIsolationJson = $NativeMfIsolationJson
    webrtcOnFrameIsolationJson = $WebrtcOnFrameIsolationJson
    streamTestJson = $StreamTestJson
  }
  boundaries = [ordered]@{
    matrixTested = $false
    liveKitTested = $liveCompared
    webRtcSenderTested = $liveCompared
    webRtcSourceOnFrameTested = $null -ne $webrtcReport
    localMediaFoundationEncoderTested = $null -ne $nativeReport
    networkTested = $liveCompared
    receiverTested = $liveCompared
  }
  evidence = [ordered]@{
    nativeMf = [ordered]@{
      status = Get-JsonString $nativeReport 'status'
      nextBoundary = Get-JsonString $nativeReport 'nextBoundary'
      presentFps = Get-JsonDouble $nativeEvidence 'presentFps'
      handoffOutputFps = Get-JsonDouble $nativeEvidence 'handoffOutputFps'
      handoffOutputGapP95Ms = Get-JsonDouble $nativeEvidence 'handoffOutputGapP95Ms'
      encoderProofEstimatedFps = Get-JsonDouble $nativeEvidence 'encoderProofEstimatedFps'
      encoderProofFramesSubmitted = Get-JsonDouble $nativeEvidence 'encoderProofFramesSubmitted'
      encoderProofOutputBytes = Get-JsonDouble $nativeEvidence 'encoderProofOutputBytes'
      encoderProofSubmitP95Ms = Get-JsonDouble $nativeEvidence 'encoderProofSubmitP95Ms'
      nv12ConvertFailures = Get-JsonDouble $nativeEvidence 'nv12ConvertFailures'
    }
    webrtcOnFrame = [ordered]@{
      status = Get-JsonString $webrtcReport 'status'
      nextBoundary = Get-JsonString $webrtcReport 'nextBoundary'
      gateDeliveryFps = Get-JsonDouble $webrtcEvidence 'gateDeliveryFps'
      deliveryOnFrameCallMs = Get-JsonDouble $webrtcEvidence 'deliveryOnFrameCallMs'
      deliveryOnFrameCallMaxMs = Get-JsonDouble $webrtcEvidence 'deliveryOnFrameCallMaxMs'
      sourceToSubmitMs = Get-JsonDouble $webrtcEvidence 'sourceToSubmitMs'
      nativeNv12Submitted = Get-JsonDouble $webrtcEvidence 'nativeNv12Submitted'
      nativeNv12Failures = Get-JsonDouble $webrtcEvidence 'nativeNv12Failures'
      nativeNv12ReadyPolicy = Get-JsonString $webrtcEvidence 'nativeNv12ReadyPolicy'
      nativeNv12FenceAvailable = Get-JsonProperty $webrtcEvidence 'nativeNv12FenceAvailable'
      nativeNv12FenceSignaled = Get-JsonDouble $webrtcEvidence 'nativeNv12FenceSignaled'
      cpuFallback = Get-JsonDouble $webrtcEvidence 'cpuFallback'
    }
    liveStream = $liveEvidence
  }
  missingEvidence = @($missing)
  nextBoundary = $nextBoundary
  recommendation = $recommendation
  wrapperRuns = [ordered]@{
    nativeMf = $nativeRun
    webrtcOnFrame = $webrtcRun
  }
}

$report | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath $jsonOut -Encoding UTF8

$missingText = if ($missing.Count -gt 0) { $missing -join ', ' } else { 'none' }
$nativeStatus = Get-JsonString $nativeReport 'status'
$webrtcStatus = Get-JsonString $webrtcReport 'status'
$nativeFps = Get-JsonDouble $nativeEvidence 'handoffOutputFps'
$nativeEncoderFps = Get-JsonDouble $nativeEvidence 'encoderProofEstimatedFps'
$webrtcFps = Get-JsonDouble $webrtcEvidence 'gateDeliveryFps'
$webrtcOnFrame = Get-JsonDouble $webrtcEvidence 'deliveryOnFrameCallMs'
$liveSend = Get-JsonProperty $liveEvidence 'sendFps'
$liveCall = Get-JsonProperty $liveEvidence 'liveOnFrameCallMs'
$liveCallback = Get-JsonProperty $liveEvidence 'liveEncodedCallbackMs'

@(
  '# Native Sender Handoff Isolation'
  ''
  '## Summary'
  ''
  "- Status: $status"
  "- Target gate: ${TargetWidth}x${TargetHeight}@${TargetFps}, minimum sustained FPS $MinSustainedFps"
  "- Next boundary: $nextBoundary"
  "- Recommendation: $recommendation"
  ''
  '## Evidence'
  ''
  "- Native capture-to-MF status: $nativeStatus"
  "- Native handoff output FPS / encoder estimated FPS: $nativeFps / $nativeEncoderFps"
  "- WebRTC source-OnFrame status: $webrtcStatus"
  "- WebRTC source gate delivery FPS / OnFrame call avg: $webrtcFps / $webrtcOnFrame ms"
  "- Live stream compared: $liveCompared"
  "- Live bottleneck / send FPS / OnFrame call avg: $liveBottleneck / $liveSend / $liveCall ms"
  "- Live encoded callback avg: $liveCallback ms"
  ''
  '## Gate Details'
  ''
  "- Missing evidence: $missingText"
  "- Native MF report: $NativeMfIsolationJson"
  "- WebRTC OnFrame report: $WebrtcOnFrameIsolationJson"
  "- Live stream-test JSON: $StreamTestJson"
  ''
  '## Boundaries'
  ''
  'This wrapper aggregates local D3D11 source -> GPU NV12 -> explicit fence -> Media Foundation proof and local native source -> VideoCapturer OnFrame isolation. It does not by itself test Matrix, LiveKit, WebRTC sender encoded-frame delivery, network, receiver, or product UI. When a live stream-test JSON is supplied, it compares that live result against the local prerequisites.'
  ''
  '## Output Files'
  ''
  "- Isolation JSON: $jsonOut"
  "- Isolation Markdown: $mdOut"
) | Set-Content -LiteralPath $mdOut -Encoding UTF8

Write-Host "Native sender handoff isolation report: $mdOut"
Write-Host "Native sender handoff isolation status: $status"

if ($status -eq 'inconclusive_native_sender_handoff') {
  exit 3
}
if ($status -like 'failed_*') {
  exit 2
}

exit 0
