param(
  [string]$SourceTitle = 'Inter Galactic',
  [int]$SourcePid = 0,
  [int]$DurationSeconds = 30,
  [int]$WarmupSeconds = 5,
  [double]$MinSustainedFps = 29.0,
  [int]$TimeoutSeconds = 180,
  [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'stream_lab_env.ps1')

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

function Get-AppStreamTestDirectory {
  return Resolve-StreamLabAppStreamTestDirectory -RepoRoot (Resolve-RepoRoot)
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

function Get-JsonBool([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $false
  }
  if ($value -is [bool]) {
    return [bool]$value
  }
  return ([string]$value).Trim().ToLowerInvariant() -eq 'true'
}

function Get-JsonDouble([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  $parsed = 0.0
  if ([double]::TryParse(
      [string]$value,
      [System.Globalization.NumberStyles]::Float,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    )) {
    return $parsed
  }
  return $null
}

function Resolve-ReportJsonPath([string]$ReportPath, [datetime]$StartedAt, [string]$StreamTestDir) {
  if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    if (([System.IO.Path]::GetExtension($ReportPath)).ToLowerInvariant() -eq '.json' -and
        (Test-Path -LiteralPath $ReportPath)) {
      return (Resolve-Path -LiteralPath $ReportPath).Path
    }
    $candidate = [System.IO.Path]::ChangeExtension($ReportPath, '.json')
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  if (-not (Test-Path -LiteralPath $StreamTestDir)) {
    return ''
  }
  $threshold = $StartedAt.AddSeconds(-2)
  $latest = Get-ChildItem -LiteralPath $StreamTestDir -Filter 'stream-test-*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $threshold } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($latest) {
    return $latest.FullName
  }
  return ''
}

function Copy-IfExists([string]$Path, [string]$DestinationDirectory) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return ''
  }
  $destination = Join-Path $DestinationDirectory ([System.IO.Path]::GetFileName($Path))
  Copy-Item -LiteralPath $Path -Destination $destination -Force
  return $destination
}

$repoRoot = Resolve-RepoRoot
Import-StreamLabLocalEnv -RepoRoot $repoRoot
$workspaceRoot = Resolve-StreamLabWorkspaceRoot -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Resolve-StreamLabOutputRoot -RepoRoot $repoRoot -WorkspaceRoot $workspaceRoot
}
New-SafeDirectory $OutputRoot

$streamTestDir = Get-AppStreamTestDirectory
New-SafeDirectory $streamTestDir

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$id = "dummy-nv12-live-sender-$stamp"
$runDirectory = Join-Path $OutputRoot "dummy-nv12-live-sender-$stamp"
New-SafeDirectory $runDirectory

$requestPath = Join-Path $streamTestDir 'stream-test-request.json'
$completePath = Join-Path $streamTestDir "stream-test-request-$id.complete.json"
$startedAt = Get-Date

if (Test-Path -LiteralPath $requestPath) {
  throw "A stream-test automation request is already pending: $requestPath"
}
if (Test-Path -LiteralPath $completePath) {
  Remove-Item -LiteralPath $completePath -Force
}

$request = [ordered]@{
  schema = 'intergalactic.streamTestAutomationRequest.v1'
  id = $id
  presets = @('smooth')
  durationSeconds = $DurationSeconds
  warmupSeconds = $WarmupSeconds
  windowsBackendMode = 'game-d3d11-hook-experimental'
  nativeFramePacingEnabled = $true
  dummyNv12LiveSender = $true
  gameCaptureSourceMode = 'dummy-nv12-live-sender'
  launchCaptureTarget = $false
  captureTarget = [ordered]@{
    enabled = $false
    width = 1280
    height = 720
    mode = 'windowed'
    scene = 'dummy-nv12-live-sender'
    fps = '30'
    title = 'Inter Galactic Capture Target'
  }
}
if ($SourcePid -gt 0) {
  $request.sourceProcessId = $SourcePid
}
if (-not [string]::IsNullOrWhiteSpace($SourceTitle)) {
  $request.sourceTitle = $SourceTitle
}

($request | ConvertTo-Json -Depth 20) |
  Set-Content -LiteralPath $requestPath -Encoding UTF8
Copy-Item -LiteralPath $requestPath -Destination (Join-Path $runDirectory 'stream-test-request.json') -Force

Write-Host "Dummy NV12 live sender request written: $requestPath"
Write-Host "Waiting for completion: $completePath"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  if (Test-Path -LiteralPath $completePath) {
    break
  }
  Start-Sleep -Seconds 1
}

if (-not (Test-Path -LiteralPath $completePath)) {
  if (Test-Path -LiteralPath $requestPath) {
    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
  }
  throw "Timed out waiting for stream-test automation completion after $TimeoutSeconds seconds."
}

$completion = Get-Content -Raw -LiteralPath $completePath | ConvertFrom-Json
$completionCopy = Copy-IfExists $completePath $runDirectory
$completionStatus = Get-JsonString $completion 'status'
$completionError = Get-JsonString $completion 'error'
$reportPath = Get-JsonString $completion 'reportPath'
$reportJsonPath = Resolve-ReportJsonPath $reportPath $startedAt $streamTestDir
$reportMdPath = if (-not [string]::IsNullOrWhiteSpace($reportJsonPath)) {
  [System.IO.Path]::ChangeExtension($reportJsonPath, '.md')
} else {
  ''
}
$reportJsonCopy = Copy-IfExists $reportJsonPath $runDirectory
$reportMdCopy = Copy-IfExists $reportMdPath $runDirectory

$report = if (-not [string]::IsNullOrWhiteSpace($reportJsonPath)) {
  Get-Content -Raw -LiteralPath $reportJsonPath | ConvertFrom-Json
} else {
  $null
}
$presetResults = Get-JsonProperty $report 'presetResults'
$primaryResult = $null
if ($null -ne $presetResults) {
  $primaryResult = @($presetResults) | Select-Object -First 1
}
$summary = Get-JsonProperty $primaryResult 'summary'
$native = Get-JsonProperty $primaryResult 'nativeDiagnostics'
if ($null -eq $native) {
  $native = Get-JsonProperty $summary 'nativeDiagnostics'
}
$score = Get-JsonProperty $primaryResult 'score'
$bottleneck = Get-JsonProperty $score 'bottleneck'
$sourceMode = Get-JsonString $native 'gameCaptureSourceMode'
$config = Get-JsonProperty $report 'config'
$dummyConfig = Get-JsonBool $config 'dummyNv12LiveSender'
$captureFps = Get-JsonDouble $summary 'averageCaptureFps'
$encodeFps = Get-JsonDouble $summary 'averageEncodeFps'
$sendFps = Get-JsonDouble $summary 'averageSendFps'
$nativeNv12Failures = Get-JsonDouble $native 'gameCaptureNativeNv12Failures'
$cpuFallback = Get-JsonDouble $native 'gameCaptureCpuFallbackFrames'
$nativeSubmitted = Get-JsonDouble $native 'gameCaptureNativeNv12SubmittedFrames'
$onFrameCall = Get-JsonDouble $native 'averageGameCaptureDeliveryOnFrameCallMs'
$processInput = Get-JsonDouble $native 'averageEncoderProcessInputMs'
$bottleneckLabel = Get-JsonString $bottleneck 'label'

$fpsPass = $captureFps -ne $null -and $encodeFps -ne $null -and $sendFps -ne $null -and
  $captureFps -ge $MinSustainedFps -and
  $encodeFps -ge $MinSustainedFps -and
  $sendFps -ge $MinSustainedFps
$sourceConfirmed = $dummyConfig -and $sourceMode -eq 'dummy-nv12-live-sender'
$nativeHealthy = ($nativeSubmitted -ne $null -and $nativeSubmitted -gt 0) -and
  (($nativeNv12Failures -eq $null) -or $nativeNv12Failures -eq 0) -and
  (($cpuFallback -eq $null) -or $cpuFallback -eq 0)

$status = if ($completionStatus -ne 'completed' -or -not [string]::IsNullOrWhiteSpace($completionError)) {
  'failed_dummy_nv12_live_sender_automation'
} elseif ($null -eq $report) {
  'inconclusive_dummy_nv12_live_sender_missing_report'
} elseif (-not $sourceConfirmed) {
  'inconclusive_dummy_nv12_live_sender_source_not_confirmed'
} elseif (-not $nativeHealthy) {
  'failed_dummy_nv12_live_sender_native_nv12_unhealthy'
} elseif ($fpsPass) {
  'passed_dummy_nv12_live_sender_720p30'
} else {
  'failed_dummy_nv12_live_sender_720p30'
}

$nextBoundary = if ($status -eq 'passed_dummy_nv12_live_sender_720p30') {
  'bg3_native_nv12_readiness_or_frame_ownership_isolation'
} elseif ($status -like 'failed_dummy_nv12_live_sender_720p30') {
  'custom_native_encoded_frame_or_encoder_input_handoff_design'
} elseif ($status -like 'failed_dummy_nv12_live_sender_native_nv12_unhealthy') {
  'native_dummy_nv12_sample_or_mf_input_repair'
} else {
  'repair_dummy_nv12_live_sender_isolation'
}

$result = [ordered]@{
  schema = 'intergalactic.dummyNv12LiveSenderIsolation.v1'
  id = $id
  status = $status
  nextBoundary = $nextBoundary
  minSustainedFps = $MinSustainedFps
  sourceTitle = if ([string]::IsNullOrWhiteSpace($SourceTitle)) { $null } else { $SourceTitle }
  sourcePidSet = $SourcePid -gt 0
  completion = [ordered]@{
    status = $completionStatus
    error = $completionError
    reportPath = $reportPath
    completionCopy = $completionCopy
  }
  report = [ordered]@{
    jsonPath = $reportJsonPath
    jsonCopy = $reportJsonCopy
    markdownPath = $reportMdPath
    markdownCopy = $reportMdCopy
  }
  evidence = [ordered]@{
    dummyConfig = $dummyConfig
    sourceMode = $sourceMode
    averageCaptureFps = $captureFps
    averageEncodeFps = $encodeFps
    averageSendFps = $sendFps
    nativeNv12Submitted = $nativeSubmitted
    nativeNv12Failures = $nativeNv12Failures
    cpuFallbackFrames = $cpuFallback
    averageDeliveryOnFrameCallMs = $onFrameCall
    averageEncoderProcessInputMs = $processInput
    bottleneck = $bottleneckLabel
  }
}

$jsonOut = Join-Path $runDirectory 'dummy-nv12-live-sender-isolation.json'
$mdOut = Join-Path $runDirectory 'dummy-nv12-live-sender-isolation.md'
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonOut -Encoding UTF8

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Dummy NV12 Live Sender Isolation') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- Status: $status") | Out-Null
$lines.Add("- Next boundary: $nextBoundary") | Out-Null
$lines.Add("- Source mode: $sourceMode") | Out-Null
$lines.Add("- FPS capture/encode/send: $captureFps / $encodeFps / $sendFps") | Out-Null
$lines.Add("- Native NV12 submitted/failures/CPU fallback: $nativeSubmitted / $nativeNv12Failures / $cpuFallback") | Out-Null
$lines.Add("- Delivery OnFrame avg: $onFrameCall ms") | Out-Null
$lines.Add("- Encoder ProcessInput avg: $processInput ms") | Out-Null
$lines.Add("- Bottleneck: $bottleneckLabel") | Out-Null
$lines.Add("- Stream-test JSON: $reportJsonPath") | Out-Null
$lines.Add("- Stream-test Markdown: $reportMdPath") | Out-Null
$lines.Add('') | Out-Null
$lines.Add('This isolation publishes a generated 1280x720 NV12 native texture through the normal Windows WebRTC/Media Foundation/LiveKit sender path. It bypasses BG3, the game hook helper, R10 conversion, WGC/GDI capture, receiver tuning, bitrate tuning, and custom encoded-frame handoff.') | Out-Null
$lines | Set-Content -LiteralPath $mdOut -Encoding UTF8

Write-Host "Dummy NV12 live sender isolation report: $mdOut"
Write-Host "Dummy NV12 live sender isolation status: $status"

if ($status -like 'failed_*') {
  exit 1
}
if ($status -like 'inconclusive_*') {
  exit 2
}
