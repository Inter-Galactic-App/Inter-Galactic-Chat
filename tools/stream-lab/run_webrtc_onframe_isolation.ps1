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

  [string]$WebrtcSourceSmokeJson = '',
  [string]$NativeMfIsolationJson = '',
  [string]$LibwebrtcPath = '',
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

function Resolve-FirstExistingPath([string[]]$Candidates, [string]$Label) {
  foreach ($candidate in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "$Label was not found. Checked: $($Candidates -join '; ')"
}

function ConvertTo-ArgumentString([string[]]$Arguments) {
  return (($Arguments | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"' + ($_ -replace '"', '\"') + '"'
    } else {
      $_
    }
  }) -join ' ')
}

function Find-WindowProcessByTitle([string]$Title) {
  if ([string]::IsNullOrWhiteSpace($Title)) {
    return $null
  }
  $needle = $Title.Trim()
  $matches = Get-Process |
    Where-Object {
      $_.MainWindowHandle -ne 0 -and
      -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) -and
      $_.MainWindowTitle.IndexOf(
        $needle,
        [System.StringComparison]::OrdinalIgnoreCase
      ) -ge 0
    } |
    Sort-Object ProcessName, Id
  return $matches | Select-Object -First 1
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

function Get-JsonBool([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  if ($value -is [bool]) {
    return [bool]$value
  }
  $parsed = $false
  if ([bool]::TryParse([string]$value, [ref]$parsed)) {
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

function Get-LatestNativeMfIsolationJson([string]$Root) {
  if (-not (Test-Path -LiteralPath $Root)) {
    return ''
  }
  $candidate = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'native-capture-mf-isolation.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) {
    return $candidate.FullName
  }
  return ''
}

function Get-FileSha256([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Stop-LaunchedTarget([System.Diagnostics.Process]$Process) {
  if ($null -eq $Process) {
    return
  }
  try {
    if (-not $Process.HasExited) {
      [void]$Process.CloseMainWindow()
      if (-not $Process.WaitForExit(5000)) {
        $Process.Kill()
        $Process.WaitForExit()
      }
    }
  } catch {
    if (-not $Process.HasExited) {
      $Process.Kill()
      $Process.WaitForExit()
    }
  }
}

function Ensure-WebrtcSmokeInterop {
  if ('InterGalactic.StreamLab.WebrtcSmokeNative' -as [type]) {
    return
  }

  Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace InterGalactic.StreamLab {
  public static class WebrtcSmokeNative {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string lpFileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    private delegate int WebrtcSourceSmokeDelegate(
      string helperPath,
      UInt32 targetProcessId,
      UInt32 maxWidth,
      UInt32 maxHeight,
      UInt32 targetFps,
      UInt32 durationMs,
      string outputJsonPath);

    public static int Invoke(
      string libwebrtcPath,
      string helperPath,
      UInt32 targetProcessId,
      UInt32 maxWidth,
      UInt32 maxHeight,
      UInt32 targetFps,
      UInt32 durationMs,
      string outputJsonPath) {
      IntPtr library = LoadLibrary(libwebrtcPath);
      if (library == IntPtr.Zero) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "LoadLibrary failed for " + libwebrtcPath);
      }
      IntPtr proc = GetProcAddress(library, "InterGalacticGameCaptureWebrtcSourceSmoke");
      if (proc == IntPtr.Zero) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "InterGalacticGameCaptureWebrtcSourceSmoke export was not found.");
      }
      WebrtcSourceSmokeDelegate callback =
        (WebrtcSourceSmokeDelegate)Marshal.GetDelegateForFunctionPointer(proc, typeof(WebrtcSourceSmokeDelegate));
      return callback(helperPath, targetProcessId, maxWidth, maxHeight, targetFps, durationMs, outputJsonPath);
    }
  }
}
"@
}

function Invoke-WebrtcSourceSmoke(
  [string]$LibPath,
  [string]$ResolvedHelperPath,
  [int]$ResolvedSourcePid,
  [string]$RunDirectory
) {
  Ensure-WebrtcSmokeInterop
  $jsonPath = Join-Path $RunDirectory 'webrtc-source-smoke.json'
  $durationMs = [Math]::Max(1000, [Math]::Min($DurationSeconds * 1000, 30000))
  $exitCode = [InterGalactic.StreamLab.WebrtcSmokeNative]::Invoke(
    $LibPath,
    $ResolvedHelperPath,
    [uint32]$ResolvedSourcePid,
    [uint32]$TargetWidth,
    [uint32]$TargetHeight,
    [uint32]$TargetFps,
    [uint32]$durationMs,
    $jsonPath
  )
  return [ordered]@{
    exitCode = $exitCode
    jsonPath = $jsonPath
    durationMs = $durationMs
  }
}

function Write-IsolationReport(
  [string]$SmokeJsonPath,
  [object]$SmokeRun,
  [string]$ReportDirectory,
  [string]$ResolvedLibwebrtc,
  [string]$ResolvedHelper,
  [string]$ResolvedMfJson
) {
  $smoke = Get-Content -LiteralPath $SmokeJsonPath -Raw | ConvertFrom-Json
  $runDirectory = if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    Split-Path -Parent $SmokeJsonPath
  } else {
    New-SafeDirectory $ReportDirectory
    $ReportDirectory
  }

  $requestedDuration = [double]$DurationSeconds
  if ($SmokeRun -and (Get-JsonProperty $SmokeRun 'durationMs')) {
    $requestedDuration = [double](Get-JsonProperty $SmokeRun 'durationMs') / 1000.0
  }
  $frameBudgetMs = [Math]::Round(1000.0 / [Math]::Max(1.0, [double]$TargetFps), 3)

  $mf = $null
  if (-not [string]::IsNullOrWhiteSpace($ResolvedMfJson) -and
      (Test-Path -LiteralPath $ResolvedMfJson)) {
    $mf = Get-Content -LiteralPath $ResolvedMfJson -Raw | ConvertFrom-Json
  }

  $sourceStatus = Get-JsonString $smoke 'status'
  $startupFailureReason = Get-JsonString $smoke 'startupFailureReason'
  $helperOutputRoot = Get-JsonString $smoke 'helperOutputRoot'
  $helperExitedBeforeSharedState = Get-JsonBool $smoke 'helperExitedBeforeSharedState'
  $helperExitCodeAvailable = Get-JsonBool $smoke 'helperExitCodeAvailable'
  $helperExitCode = Get-JsonDouble $smoke 'helperExitCode'
  $openSharedStateWaitMs = Get-JsonDouble $smoke 'openSharedStateWaitMs'
  $sourceFormat = Get-JsonString $smoke 'sourceFormat'
  $sourceApi = Get-JsonString $smoke 'sourceApi'
  $outputWidth = Get-JsonDouble $smoke 'outputWidth'
  $outputHeight = Get-JsonDouble $smoke 'outputHeight'
  $submitted = Get-JsonDouble $smoke 'submitted'
  $deliverySubmitted = Get-JsonDouble $smoke 'deliverySubmitted'
  $nativeNv12Submitted = Get-JsonDouble $smoke 'nativeNv12Submitted'
  $nativeNv12Failures = Get-JsonDouble $smoke 'nativeNv12Failures'
  $nativeNv12ReadyPolicy = Get-JsonString $smoke 'nativeNv12ReadyPolicy'
  $nativeNv12FenceAvailable = Get-JsonBool $smoke 'nativeNv12FenceAvailable'
  $nativeNv12FenceSignaled = Get-JsonDouble $smoke 'nativeNv12FenceSignaled'
  $cpuFallback = Get-JsonDouble $smoke 'cpuFallback'
  $deliveryQueued = Get-JsonDouble $smoke 'deliveryQueued'
  $deliveryOverwritten = Get-JsonDouble $smoke 'deliveryOverwritten'
  $deliveryQueueWaitMs = Get-JsonDouble $smoke 'deliveryQueueWaitMs'
  $deliveryQueueWaitMaxMs = Get-JsonDouble $smoke 'deliveryQueueWaitMaxMs'
  $deliveryOnFrameMs = Get-JsonDouble $smoke 'deliveryOnFrameMs'
  $deliveryOnFrameMaxMs = Get-JsonDouble $smoke 'deliveryOnFrameMaxMs'
  $deliveryOnFrameCallMs = Get-JsonDouble $smoke 'deliveryOnFrameCallMs'
  $deliveryOnFrameCallMaxMs = Get-JsonDouble $smoke 'deliveryOnFrameCallMaxMs'
  $deliverySubmitPrepMs = Get-JsonDouble $smoke 'deliverySubmitPrepMs'
  $deliveryPostOnFrameMs = Get-JsonDouble $smoke 'deliveryPostOnFrameMs'
  $deliveryWallDeltaMs = Get-JsonDouble $smoke 'deliveryWallDeltaMs'
  $deliveryWallSamples = Get-JsonDouble $smoke 'deliveryWallSamples'
  $nativeBufferReleaseMs = Get-JsonDouble $smoke 'nativeBufferReleaseMs'
  $nativeBufferReleaseMaxMs = Get-JsonDouble $smoke 'nativeBufferReleaseMaxMs'
  $sourceToSubmitMs = Get-JsonDouble $smoke 'sourceToSubmitMs'
  $sourceToSubmitMaxMs = Get-JsonDouble $smoke 'sourceToSubmitMaxMs'
  $nativeNv12ConvertMs = Get-JsonDouble $smoke 'nativeNv12ConvertMs'
  $nativeNv12ConvertMaxMs = Get-JsonDouble $smoke 'nativeNv12ConvertMaxMs'
  $nativeNv12BltToReadyMs = Get-JsonDouble $smoke 'nativeNv12VideoProcessorBltToReadyMs'
  $nativeNv12BltToReadyMaxMs = Get-JsonDouble $smoke 'nativeNv12VideoProcessorBltToReadyMaxMs'
  $visibleProofFrames = Get-JsonDouble $smoke 'visibleProofFrames'
  $visibleI420ProofFrames = Get-JsonDouble $smoke 'visibleI420ProofFrames'

  $deliveryFps = if ($null -ne $deliverySubmitted) {
    Get-FrameRateFromCount $deliverySubmitted $requestedDuration
  } elseif ($null -ne $submitted) {
    Get-FrameRateFromCount $submitted $requestedDuration
  } else {
    $null
  }
  $measuredDeliveryFps = $null
  if ($null -ne $deliverySubmitted -and
      $null -ne $deliveryWallDeltaMs -and
      $null -ne $deliveryWallSamples -and
      $deliveryWallDeltaMs -gt 0 -and
      $deliveryWallSamples -gt 0) {
    $measuredDeliverySeconds = ($deliveryWallDeltaMs * $deliveryWallSamples) / 1000.0
    if ($measuredDeliverySeconds -gt 0) {
      $measuredDeliveryFps = [Math]::Round($deliverySubmitted / $measuredDeliverySeconds, 3)
    }
  }
  $gateDeliveryFps = if ($null -ne $measuredDeliveryFps) {
    $measuredDeliveryFps
  } else {
    $deliveryFps
  }

  $missing = [System.Collections.Generic.List[string]]::new()
  Add-IfMissing $missing $sourceStatus 'status'
  Add-IfMissing $missing $submitted 'submitted'
  Add-IfMissing $missing $deliverySubmitted 'deliverySubmitted'
  Add-IfMissing $missing $nativeNv12Submitted 'nativeNv12Submitted'
  Add-IfMissing $missing $nativeNv12Failures 'nativeNv12Failures'
  Add-IfMissing $missing $cpuFallback 'cpuFallback'
  Add-IfMissing $missing $outputWidth 'outputWidth'
  Add-IfMissing $missing $outputHeight 'outputHeight'
  Add-IfMissing $missing $deliveryOnFrameCallMs 'deliveryOnFrameCallMs'
  Add-IfMissing $missing $deliveryOnFrameCallMaxMs 'deliveryOnFrameCallMaxMs'
  Add-IfMissing $missing $nativeBufferReleaseMs 'nativeBufferReleaseMs'

  $issues = [System.Collections.Generic.List[string]]::new()
  $smokeExitCode = if ($SmokeRun) { Get-JsonProperty $SmokeRun 'exitCode' } else { $null }
  Add-IfTrue $issues ($null -ne $smokeExitCode -and [int]$smokeExitCode -ne 0) "smoke_exit_code_$smokeExitCode"
  Add-IfTrue $issues ($sourceStatus -ne 'completed') "source_smoke_status_$sourceStatus"
  Add-IfTrue $issues (-not [string]::IsNullOrWhiteSpace($startupFailureReason)) "source_smoke_startup_$startupFailureReason"
  Add-IfTrue $issues ($null -ne $helperExitCodeAvailable -and $helperExitCodeAvailable -and $null -ne $helperExitCode -and [int]$helperExitCode -ne 0) "helper_exit_code_$helperExitCode"
  Add-IfTrue $issues ($null -ne $outputWidth -and [int]$outputWidth -ne $TargetWidth) "wrong_output_width_$outputWidth"
  Add-IfTrue $issues ($null -ne $outputHeight -and [int]$outputHeight -ne $TargetHeight) "wrong_output_height_$outputHeight"
  Add-IfTrue $issues ($null -ne $gateDeliveryFps -and $gateDeliveryFps -lt $MinSustainedFps) 'webrtc_source_delivery_below_gate'
  Add-IfTrue $issues ($null -ne $nativeNv12Submitted -and $nativeNv12Submitted -le 0) 'native_nv12_not_submitted'
  Add-IfTrue $issues ($null -ne $nativeNv12Failures -and $nativeNv12Failures -gt 0) 'native_nv12_failures'
  Add-IfTrue $issues ($null -ne $cpuFallback -and $cpuFallback -gt 0) 'cpu_i420_fallback_active'
  Add-IfTrue $issues ($null -ne $deliveryOnFrameCallMs -and $deliveryOnFrameCallMs -gt ($frameBudgetMs * 0.75)) 'onframe_call_avg_over_75pct_frame_budget'
  Add-IfTrue $issues ($null -ne $deliveryOnFrameCallMaxMs -and $deliveryOnFrameCallMaxMs -gt ($frameBudgetMs * 3.0)) 'onframe_call_max_over_3x_frame_budget'
  Add-IfTrue $issues ($null -ne $nativeBufferReleaseMs -and $nativeBufferReleaseMs -gt ($frameBudgetMs * 0.5)) 'native_buffer_release_avg_over_half_frame_budget'

  $warnings = [System.Collections.Generic.List[string]]::new()
  Add-IfTrue $warnings ($sourceFormat -ne 'r10g10b10a2') "source_format_not_r10g10b10a2_$sourceFormat"
  Add-IfTrue $warnings ($nativeNv12ReadyPolicy -ne 'fence') "native_ready_policy_not_fence_$nativeNv12ReadyPolicy"
  Add-IfTrue $warnings ($null -ne $nativeNv12FenceAvailable -and -not $nativeNv12FenceAvailable) 'native_nv12_fence_unavailable'
  Add-IfTrue $warnings ($null -ne $deliveryQueueWaitMaxMs -and $deliveryQueueWaitMaxMs -gt ($frameBudgetMs * 2.0)) 'delivery_queue_wait_max_over_2x_frame_budget'
  Add-IfTrue $warnings ($null -ne $deliveryFps -and $null -ne $measuredDeliveryFps -and $deliveryFps -lt $MinSustainedFps -and $measuredDeliveryFps -ge $MinSustainedFps) 'fixed_window_fps_below_gate_but_measured_delivery_fps_passes'
  Add-IfTrue $warnings ($null -ne $sourceToSubmitMaxMs -and $sourceToSubmitMaxMs -gt ($frameBudgetMs * 4.0)) 'source_to_submit_max_tail'
  Add-IfTrue $warnings ($null -ne $nativeNv12BltToReadyMaxMs -and $nativeNv12BltToReadyMaxMs -gt ($frameBudgetMs * 4.0)) 'native_nv12_blt_to_ready_tail'

  $mfStatus = $null
  $mfNextBoundary = $null
  if ($mf) {
    $mfStatus = Get-JsonString $mf 'status'
    $mfNextBoundary = Get-JsonString $mf 'nextBoundary'
    if ($mfStatus -ne 'passed_native_capture_mf_720p30') {
      [void]$warnings.Add("native_mf_isolation_not_passed_$mfStatus")
    }
  } else {
    [void]$warnings.Add('native_mf_isolation_not_linked')
  }

  $result = if ($missing.Count -gt 0) {
    'inconclusive_webrtc_onframe_isolation'
  } elseif ($issues.Count -eq 0) {
    'passed_webrtc_onframe_isolation'
  } else {
    'failed_webrtc_onframe_isolation'
  }

  $nextBoundary = if ($result -eq 'passed_webrtc_onframe_isolation' -and
      $mfStatus -eq 'passed_native_capture_mf_720p30') {
    'webrtc_sender_or_native_encoded_frame_handoff'
  } elseif (-not [string]::IsNullOrWhiteSpace($startupFailureReason)) {
    'webrtc_source_smoke_startup'
  } elseif ($issues -contains 'webrtc_source_delivery_below_gate' -or
      $issues -contains 'native_nv12_not_submitted' -or
      $issues -contains 'native_nv12_failures' -or
      $issues -contains 'cpu_i420_fallback_active') {
    'local_webrtc_source_native_frame_path'
  } elseif ($issues -contains 'onframe_call_avg_over_75pct_frame_budget' -or
      $issues -contains 'onframe_call_max_over_3x_frame_budget') {
    'webrtc_onframe_callback'
  } elseif ($issues -contains 'native_buffer_release_avg_over_half_frame_budget') {
    'native_surface_lifetime_release'
  } elseif ($missing.Count -gt 0) {
    'diagnostic_coverage'
  } else {
    'webrtc_sender_boundary_requires_native_mf_comparison'
  }

  $recommendation = if ($nextBoundary -eq 'webrtc_sender_or_native_encoded_frame_handoff') {
    'Local BG3 native capture-to-MF and no-sender WebRTC OnFrame source paths are healthy; the next implementation should isolate or redesign WebRTC sender/native encoded-frame handoff before another broad live-call loop.'
  } elseif ($result -eq 'inconclusive_webrtc_onframe_isolation') {
    'Repair source-smoke diagnostic coverage before using this result as a WebRTC sender-boundary gate.'
  } else {
    'Do not run another full BG3 call yet; fix the failing local WebRTC source/OnFrame/native-frame boundary first.'
  }

  $report = [ordered]@{
    schema = 'intergalactic.webrtcOnFrameIsolation.v1'
    status = $result
    webRtcSourceSmokeJson = $SmokeJsonPath
    webRtcSourceSmokeExitCode = $smokeExitCode
    nativeMfIsolationJson = $ResolvedMfJson
    libwebrtc = [ordered]@{
      path = $ResolvedLibwebrtc
      sha256 = Get-FileSha256 $ResolvedLibwebrtc
    }
    helper = [ordered]@{
      path = $ResolvedHelper
      sha256 = Get-FileSha256 $ResolvedHelper
    }
    target = [ordered]@{
      width = $TargetWidth
      height = $TargetHeight
      fps = $TargetFps
      durationSeconds = $requestedDuration
      minSustainedFps = $MinSustainedFps
      frameBudgetMs = $frameBudgetMs
    }
    boundaries = [ordered]@{
      matrixTested = $false
      liveKitTested = $false
      webRtcSenderTested = $false
      webRtcSourceOnFrameTested = $true
      nativeEncodedFrameHandoffTested = $false
      networkTested = $false
      receiverTested = $false
      localD3d11CaptureTested = $true
      localMediaFoundationEncoderLinked = ($null -ne $mf)
    }
    evidence = [ordered]@{
      sourceStatus = $sourceStatus
      startupFailureReason = $startupFailureReason
      helperOutputRoot = $helperOutputRoot
      helperExitedBeforeSharedState = $helperExitedBeforeSharedState
      helperExitCodeAvailable = $helperExitCodeAvailable
      helperExitCode = $helperExitCode
      openSharedStateWaitMs = $openSharedStateWaitMs
      sourceApi = $sourceApi
      sourceFormat = $sourceFormat
      outputWidth = $outputWidth
      outputHeight = $outputHeight
      submitted = $submitted
      deliveryQueued = $deliveryQueued
      deliverySubmitted = $deliverySubmitted
      fixedWindowDeliveryFps = $deliveryFps
      measuredDeliveryFps = $measuredDeliveryFps
      gateDeliveryFps = $gateDeliveryFps
      deliveryOverwritten = $deliveryOverwritten
      nativeNv12Submitted = $nativeNv12Submitted
      nativeNv12Failures = $nativeNv12Failures
      nativeNv12ReadyPolicy = $nativeNv12ReadyPolicy
      nativeNv12FenceAvailable = $nativeNv12FenceAvailable
      nativeNv12FenceSignaled = $nativeNv12FenceSignaled
      cpuFallback = $cpuFallback
      deliveryQueueWaitMs = $deliveryQueueWaitMs
      deliveryQueueWaitMaxMs = $deliveryQueueWaitMaxMs
      deliveryOnFrameMs = $deliveryOnFrameMs
      deliveryOnFrameMaxMs = $deliveryOnFrameMaxMs
      deliveryOnFrameCallMs = $deliveryOnFrameCallMs
      deliveryOnFrameCallMaxMs = $deliveryOnFrameCallMaxMs
      deliverySubmitPrepMs = $deliverySubmitPrepMs
      deliveryPostOnFrameMs = $deliveryPostOnFrameMs
      deliveryWallDeltaMs = $deliveryWallDeltaMs
      deliveryWallSamples = $deliveryWallSamples
      nativeBufferReleaseMs = $nativeBufferReleaseMs
      nativeBufferReleaseMaxMs = $nativeBufferReleaseMaxMs
      sourceToSubmitMs = $sourceToSubmitMs
      sourceToSubmitMaxMs = $sourceToSubmitMaxMs
      nativeNv12ConvertMs = $nativeNv12ConvertMs
      nativeNv12ConvertMaxMs = $nativeNv12ConvertMaxMs
      nativeNv12VideoProcessorBltToReadyMs = $nativeNv12BltToReadyMs
      nativeNv12VideoProcessorBltToReadyMaxMs = $nativeNv12BltToReadyMaxMs
      visibleProofFrames = $visibleProofFrames
      visibleI420ProofFrames = $visibleI420ProofFrames
      nativeMfIsolationStatus = $mfStatus
      nativeMfNextBoundary = $mfNextBoundary
    }
    missingEvidence = @($missing)
    failingGates = @($issues)
    warnings = @($warnings)
    nextBoundary = $nextBoundary
    recommendation = $recommendation
  }

  $jsonOut = Join-Path $runDirectory 'webrtc-onframe-isolation.json'
  $mdOut = Join-Path $runDirectory 'webrtc-onframe-isolation.md'
  $report | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $jsonOut -Encoding UTF8

  $missingText = if ($missing.Count -gt 0) { $missing -join ', ' } else { 'none' }
  $issueText = if ($issues.Count -gt 0) { $issues -join ', ' } else { 'none' }
  $warningText = if ($warnings.Count -gt 0) { $warnings -join ', ' } else { 'none' }

  @(
    '# WebRTC OnFrame Isolation'
    ''
    '## Summary'
    ''
    "- Status: $result"
    "- WebRTC source-smoke report: $SmokeJsonPath"
    "- Native capture-to-MF report: $ResolvedMfJson"
    "- Target gate: ${TargetWidth}x${TargetHeight}@${TargetFps}, minimum sustained FPS $MinSustainedFps"
    "- Next boundary: $nextBoundary"
    "- Recommendation: $recommendation"
    ''
    '## Evidence'
    ''
    "- Source status/startup failure/API/format: $sourceStatus / $startupFailureReason / $sourceApi / $sourceFormat"
    "- Helper output root: $helperOutputRoot"
    "- Helper exited before shared state / exit code available / exit code: $helperExitedBeforeSharedState / $helperExitCodeAvailable / $helperExitCode"
    "- Open shared state wait: $openSharedStateWaitMs ms"
    "- Output resolution: ${outputWidth}x${outputHeight}"
    "- Submitted / delivery submitted / gate delivery FPS: $submitted / $deliverySubmitted / $gateDeliveryFps"
    "- Fixed-window / measured delivery FPS: $deliveryFps / $measuredDeliveryFps"
    "- Native NV12 submitted/failures/policy/fence available/fence signaled: $nativeNv12Submitted / $nativeNv12Failures / $nativeNv12ReadyPolicy / $nativeNv12FenceAvailable / $nativeNv12FenceSignaled"
    "- CPU fallback: $cpuFallback"
    "- Delivery queue wait avg/max: $deliveryQueueWaitMs / $deliveryQueueWaitMaxMs ms"
    "- Delivery OnFrame total avg/max: $deliveryOnFrameMs / $deliveryOnFrameMaxMs ms"
    "- Delivery OnFrame call avg/max: $deliveryOnFrameCallMs / $deliveryOnFrameCallMaxMs ms"
    "- Delivery submit prep / post-OnFrame avg: $deliverySubmitPrepMs / $deliveryPostOnFrameMs ms"
    "- Delivery wall delta avg/samples: $deliveryWallDeltaMs ms / $deliveryWallSamples"
    "- Native buffer release avg/max: $nativeBufferReleaseMs / $nativeBufferReleaseMaxMs ms"
    "- Source-to-submit avg/max: $sourceToSubmitMs / $sourceToSubmitMaxMs ms"
    "- Native NV12 convert avg/max: $nativeNv12ConvertMs / $nativeNv12ConvertMaxMs ms"
    "- Native NV12 Blt-to-ready avg/max: $nativeNv12BltToReadyMs / $nativeNv12BltToReadyMaxMs ms"
    "- Visible proof frames / I420 proof frames: $visibleProofFrames / $visibleI420ProofFrames"
    "- Native MF isolation status: $mfStatus"
    ''
    '## Gate Details'
    ''
    "- Missing evidence: $missingText"
    "- Failing gates: $issueText"
    "- Warnings: $warningText"
    ''
    '## Boundaries'
    ''
    'This isolation run exercises the native D3D11 WebRTC game-capture source and its local VideoCapturer OnFrame path. It bypasses Matrix, LiveKit publishing, WebRTC sender stats, encoded-frame delivery, network, and the receiver. When paired with a passing native capture-to-Media Foundation report, a passing result shifts the remaining BG3 call-work toward the full WebRTC sender or native encoded-frame handoff.'
    ''
    '## Output Files'
    ''
    "- Isolation JSON: $jsonOut"
    "- Isolation Markdown: $mdOut"
    "- Source-smoke JSON: $SmokeJsonPath"
    "- Helper diagnostics root: $helperOutputRoot"
  ) | Set-Content -LiteralPath $mdOut -Encoding UTF8

  Write-Host "WebRTC OnFrame isolation report: $mdOut"
  Write-Host "WebRTC OnFrame isolation status: $result"
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

if ([string]::IsNullOrWhiteSpace($NativeMfIsolationJson)) {
  $NativeMfIsolationJson = Get-LatestNativeMfIsolationJson $OutputRoot
}

$smokeRun = $null
$analyzingExistingReport = -not [string]::IsNullOrWhiteSpace($WebrtcSourceSmokeJson)
if (-not $analyzingExistingReport) {
  $runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $runDirectory = Join-Path $OutputRoot "webrtc-onframe-isolation-$runStamp"
  New-SafeDirectory $runDirectory

  $libwebrtcCandidates = @(
    $LibwebrtcPath,
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\libwebrtc.dll'),
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Release\libwebrtc.dll'),
    (Join-Path $workspaceRoot 'webrtc-build\src\out\Default\libwebrtc.dll')
  )
  $LibwebrtcPath = Resolve-FirstExistingPath $libwebrtcCandidates 'libwebrtc.dll'

  $helperCandidates = @(
    $HelperPath,
    (Join-Path $repoRoot 'plugins\intergalactic_game_capture\windows\build\Debug\intergalactic_game_capture_helper.exe'),
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\intergalactic_game_capture_helper.exe')
  )
  $HelperPath = Resolve-FirstExistingPath $helperCandidates 'intergalactic_game_capture_helper.exe'

  $targetProcess = $null
  try {
    $sourceProcess = $null
    if ($LaunchSyntheticTarget) {
      $targetCandidates = @(
        $SyntheticTargetPath,
        (Join-Path $repoRoot 'tools\game-capture-target\build\Debug\InterGalacticCaptureTarget.exe'),
        (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\InterGalacticCaptureTarget.exe')
      )
      $resolvedTarget = Resolve-FirstExistingPath $targetCandidates 'InterGalacticCaptureTarget.exe'
      $captureTargetOutputDir = Join-Path $runDirectory 'capture-target'
      New-SafeDirectory $captureTargetOutputDir

      $targetArgs = @(
        '--width', "$Width",
        '--height', "$Height",
        '--mode', $SyntheticMode,
        '--scene', $SyntheticScene,
        '--format', $SyntheticFormat,
        '--fps', $Fps,
        '--title', $SourceTitle,
        '--output-dir', $captureTargetOutputDir
      )
      if ($SyntheticHdrLike) {
        $targetArgs += @('--hdr-like', 'true')
      }
      $targetProcess = Start-Process `
        -FilePath $resolvedTarget `
        -ArgumentList (ConvertTo-ArgumentString $targetArgs) `
        -PassThru

      $deadline = (Get-Date).AddSeconds(10)
      do {
        Start-Sleep -Milliseconds 200
        $sourceProcess = Get-Process -Id $targetProcess.Id -ErrorAction SilentlyContinue
        if ($sourceProcess -and $sourceProcess.MainWindowHandle -ne 0) {
          break
        }
      } while ((Get-Date) -lt $deadline)

      if (-not $sourceProcess -or $sourceProcess.MainWindowHandle -eq 0) {
        throw "Synthetic target launched but no visible window appeared for pid $($targetProcess.Id)."
      }
    } elseif ($SourcePid -gt 0) {
      $sourceProcess = Get-Process -Id $SourcePid -ErrorAction Stop
    } else {
      $sourceProcess = Find-WindowProcessByTitle $SourceTitle
      if (-not $sourceProcess) {
        throw "No visible process window matched SourceTitle '$SourceTitle'."
      }
    }

    $smokeRun = Invoke-WebrtcSourceSmoke `
      -LibPath $LibwebrtcPath `
      -ResolvedHelperPath $HelperPath `
      -ResolvedSourcePid $sourceProcess.Id `
      -RunDirectory $runDirectory
    $WebrtcSourceSmokeJson = $smokeRun.jsonPath
  } finally {
    if ($targetProcess) {
      Stop-LaunchedTarget $targetProcess
    }
  }
} else {
  $WebrtcSourceSmokeJson = (Resolve-Path -LiteralPath $WebrtcSourceSmokeJson).Path
  $runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $runDirectory = Join-Path $OutputRoot "webrtc-onframe-isolation-$runStamp"
  New-SafeDirectory $runDirectory

  $libwebrtcCandidates = @(
    $LibwebrtcPath,
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\libwebrtc.dll'),
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Release\libwebrtc.dll'),
    (Join-Path $workspaceRoot 'webrtc-build\src\out\Default\libwebrtc.dll')
  )
  try {
    $LibwebrtcPath = Resolve-FirstExistingPath $libwebrtcCandidates 'libwebrtc.dll'
  } catch {
    $LibwebrtcPath = ''
  }

  $helperCandidates = @(
    $HelperPath,
    (Join-Path $repoRoot 'plugins\intergalactic_game_capture\windows\build\Debug\intergalactic_game_capture_helper.exe'),
    (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\intergalactic_game_capture_helper.exe')
  )
  try {
    $HelperPath = Resolve-FirstExistingPath $helperCandidates 'intergalactic_game_capture_helper.exe'
  } catch {
    $HelperPath = ''
  }
}

if (-not [string]::IsNullOrWhiteSpace($NativeMfIsolationJson)) {
  $NativeMfIsolationJson = (Resolve-Path -LiteralPath $NativeMfIsolationJson).Path
}

$written = Write-IsolationReport `
  -SmokeJsonPath $WebrtcSourceSmokeJson `
  -SmokeRun $smokeRun `
  -ReportDirectory $runDirectory `
  -ResolvedLibwebrtc $LibwebrtcPath `
  -ResolvedHelper $HelperPath `
  -ResolvedMfJson $NativeMfIsolationJson

if ($written.status -eq 'failed_webrtc_onframe_isolation') {
  exit 2
}
if ($written.status -eq 'inconclusive_webrtc_onframe_isolation') {
  exit 3
}
