param(
  [ValidateSet('future-game-d3d11-hook', 'app-default', 'wgc', 'window-gdi')]
  [string]$Backend = 'future-game-d3d11-hook',

  [string]$SourceTitle = 'Inter Galactic Capture Target',
  [int]$SourcePid = 0,

  [int]$Width = 1920,
  [int]$Height = 1080,
  [string]$Fps = '60',
  [ValidateSet('windowed', 'borderless')]
  [string]$SyntheticMode = 'windowed',
  [ValidateSet('low-motion', 'high-motion', 'gameplay', 'ui-heavy')]
  [string]$SyntheticScene = 'gameplay',
  [ValidateSet('r8g8b8a8', 'r10g10b10a2')]
  [string]$SyntheticFormat = 'r8g8b8a8',
  [switch]$SyntheticHdrLike,

  [int]$TargetWidth = 1280,
  [int]$TargetHeight = 720,
  [int]$TargetFps = 30,
  [int]$DurationSeconds = 30,
  [int]$MaxSavedFrames = 0,
  [int]$HostProofFrames = 0,
  [int]$PublicationProofFrames = 0,
  [ValidateSet('all', 'proof-only')]
  [string]$PublicationReadbackMode = 'proof-only',
  [ValidateSet('bgra', 'nv12', 'p010')]
  [string]$PublicationOutputFormat = 'bgra',
  [ValidateSet('off', 'h264-mf')]
  [string]$PublicationEncoderProof = 'off',

  [switch]$LaunchSyntheticTarget,
  [string]$HelperPath = '',
  [string]$SyntheticTargetPath = '',
  [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stream_lab_env.ps1')

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

function ConvertTo-ShortHash([string]$Value) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return (($hash[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
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

function Read-JsonFileOrNull([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-CoverageStatus([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    return 'available'
  }
  return 'missing'
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

function Write-NotImplementedReport(
  [string]$RunDirectory,
  [string]$Backend,
  [string]$Reason
) {
  $jsonPath = Join-Path $RunDirectory 'local-capture-benchmark.json'
  $mdPath = Join-Path $RunDirectory 'local-capture-benchmark.md'
  $report = [ordered]@{
    schema = 'intergalactic.localStreamPipelineHarness.v1'
    status = 'not_implemented'
    mode = 'local-capture-benchmark'
    backend = $Backend
    reason = $Reason
    matrixTested = $false
    liveKitTested = $false
    networkTested = $false
    receiverTested = $false
    encoderTested = $false
    coverage = [ordered]@{
      desktopCapture = 'unavailable'
      gameCapturePresent = 'notApplicable'
      hostConsumer = 'notApplicable'
      publicationHandoff = 'notApplicable'
      encoder = 'notTested'
      liveKitNetworkReceiver = 'notTested'
    }
  }
  $report | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $jsonPath -Encoding UTF8
  @(
    '# Local Stream Pipeline Benchmark'
    ''
    "- Status: not implemented"
    "- Backend: $Backend"
    "- Reason: $Reason"
    ''
    'This report did not run a Matrix call, LiveKit publish, WebRTC sender, encoder, network, or receiver path.'
  ) | Set-Content -LiteralPath $mdPath -Encoding UTF8
  return [ordered]@{
    json = $jsonPath
    markdown = $mdPath
  }
}

function Write-LocalBenchmarkReport(
  [string]$RunDirectory,
  [string]$Backend,
  [object]$SourceProcess,
  [string]$HelperPath,
  [int]$HelperExitCode,
  [bool]$HelperTimedOut,
  [string]$HelperStdout,
  [string]$HelperStderr,
  [string]$HelperResultDirectory,
  [object]$HookMetadata,
  [object]$HostConsumer,
  [object]$PublicationHandoff,
  [object]$CaptureTarget,
  [hashtable]$Requested
) {
  $jsonPath = Join-Path $RunDirectory 'local-capture-benchmark.json'
  $mdPath = Join-Path $RunDirectory 'local-capture-benchmark.md'
  $metadataPath = Join-Path $HelperResultDirectory 'metadata.json'
  $hostPath = Join-Path $HelperResultDirectory 'host-consumer.json'
  $handoffPath = Join-Path $HelperResultDirectory 'publication-handoff.json'
  $targetPath = Join-Path $RunDirectory 'capture-target\capture-target.json'

  $sourceWindowTitle = $SourceProcess.MainWindowTitle
  if ([string]::IsNullOrWhiteSpace($sourceWindowTitle) -and $CaptureTarget) {
    $sourceWindowTitle = $CaptureTarget.windowTitle
  }
  if ([string]::IsNullOrWhiteSpace($sourceWindowTitle)) {
    $sourceWindowTitle = $Requested.sourceTitle
  }
  $pidHash = ConvertTo-ShortHash "$($SourceProcess.Id):$($SourceProcess.ProcessName):$sourceWindowTitle"
  $mainWindowHandle = 0
  if ($SourceProcess.MainWindowHandle) {
    $mainWindowHandle = $SourceProcess.MainWindowHandle.ToInt64()
  }
  $status = if ($HelperTimedOut) {
    'helper_timeout'
  } elseif ($null -eq $HookMetadata) {
    'missing_metadata'
  } elseif ($HelperExitCode -ne 0) {
    'helper_failed'
  } else {
    'completed'
  }

  $coverage = [ordered]@{
    desktopCapture = 'notApplicable'
    gameCapturePresent = Get-CoverageStatus $metadataPath
    hostConsumer = Get-CoverageStatus $hostPath
    publicationHandoff = Get-CoverageStatus $handoffPath
    syntheticTarget = if (Test-Path -LiteralPath $targetPath) {
      'available'
    } else {
      'notApplicable'
    }
    encoder = if ($PublicationHandoff -and $PublicationHandoff.encoderProofEnabled) {
      if ($PublicationHandoff.encoderProofFramesSubmitted -gt 0) {
        'available'
      } elseif ($PublicationHandoff.encoderProofWriteFailures -gt 0) {
        'unavailable'
      } else {
        'missing'
      }
    } else {
      'notTested'
    }
    liveKitNetworkReceiver = 'notTested'
  }

  $report = [ordered]@{
    schema = 'intergalactic.localStreamPipelineHarness.v1'
    status = $status
    mode = 'local-d3d11-hook-handoff'
    backend = $Backend
    startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    runDirectory = $RunDirectory
    matrixTested = $false
    liveKitTested = $false
    networkTested = $false
    receiverTested = $false
    encoderTested = if ($PublicationHandoff) {
      [bool]$PublicationHandoff.encoderProofEnabled
    } else {
      $false
    }
    requested = $Requested
    source = [ordered]@{
      processName = $SourceProcess.ProcessName
      pidHash = "sha256-$pidHash"
      windowTitle = $sourceWindowTitle
      mainWindowHandle = $mainWindowHandle
    }
    helper = [ordered]@{
      path = $HelperPath
      exitCode = $HelperExitCode
      timedOut = $HelperTimedOut
      resultDirectory = $HelperResultDirectory
      stdout = $HelperStdout.Trim()
      stderr = $HelperStderr.Trim()
    }
    coverage = $coverage
    hookMetadata = $HookMetadata
    hostConsumer = $HostConsumer
    publicationHandoff = $PublicationHandoff
    syntheticTarget = $CaptureTarget
  }

  $report | ConvertTo-Json -Depth 80 |
    Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $presentFps = if ($HookMetadata) { $HookMetadata.presentFps } else { $null }
  $presentP95 = if ($HookMetadata) { $HookMetadata.presentGapP95Ms } else { $null }
  $presentMax = if ($HookMetadata) { $HookMetadata.presentGapMaxMs } else { $null }
  $copyAvg = if ($HookMetadata) { $HookMetadata.copyAvgMs } else { $null }
  $copyMax = if ($HookMetadata) { $HookMetadata.copyMaxMs } else { $null }
  $handoffFps = if ($PublicationHandoff) { $PublicationHandoff.outputFps } else { $null }
  $handoffP95 = if ($PublicationHandoff) { $PublicationHandoff.outputGapP95Ms } else { $null }
  $handoffMax = if ($PublicationHandoff) { $PublicationHandoff.outputGapMaxMs } else { $null }
  $handoffTotal = if ($PublicationHandoff) { $PublicationHandoff.totalFrameAvgMs } else { $null }
  $handoffRepeated = if ($PublicationHandoff) { $PublicationHandoff.repeatedOutputFrames } else { $null }
  $handoffPacedDrops = if ($PublicationHandoff) { $PublicationHandoff.pacedDropFrames } else { $null }
  $handoffReadbackMode = if ($PublicationHandoff) { $PublicationHandoff.readbackMode } else { $null }
  $handoffOutputFormat = if ($PublicationHandoff) { $PublicationHandoff.outputFormat } else { $null }
  $handoffEncoderFormat = if ($PublicationHandoff) { $PublicationHandoff.encoderFormat } else { $null }
  $handoffReadbackFrames = if ($PublicationHandoff) { $PublicationHandoff.readbackFrames } else { $null }
  $handoffProofFrames = if ($PublicationHandoff) { $PublicationHandoff.proofOutputFrames } else { $null }
  $handoffVisibleProofFrames = if ($PublicationHandoff) { $PublicationHandoff.visibleProofOutputFrames } else { $null }
  $handoffNv12Frames = if ($PublicationHandoff) { $PublicationHandoff.nv12OutputFrames } else { $null }
  $handoffNv12Failures = if ($PublicationHandoff) { $PublicationHandoff.nv12ConvertFailures } else { $null }
  $handoffNv12Convert = if ($PublicationHandoff) { $PublicationHandoff.nv12ConvertAvgMs } else { $null }
  $handoffP010Frames = if ($PublicationHandoff) { $PublicationHandoff.p010OutputFrames } else { $null }
  $handoffP010Failures = if ($PublicationHandoff) { $PublicationHandoff.p010ConvertFailures } else { $null }
  $handoffP010Convert = if ($PublicationHandoff) { $PublicationHandoff.p010ConvertAvgMs } else { $null }
  $encoderProofMode = if ($PublicationHandoff) { $PublicationHandoff.encoderProofMode } else { $null }
  $encoderProofFrames = if ($PublicationHandoff) { $PublicationHandoff.encoderProofFramesSubmitted } else { $null }
  $encoderProofFailures = if ($PublicationHandoff) { $PublicationHandoff.encoderProofWriteFailures } else { $null }
  $encoderProofSubmit = if ($PublicationHandoff) { $PublicationHandoff.encoderProofSubmitAvgMs } else { $null }
  $encoderProofInit = if ($PublicationHandoff) { $PublicationHandoff.encoderProofInitMs } else { $null }
  $encoderProofOutputBytes = if ($PublicationHandoff) { $PublicationHandoff.encoderProofOutputBytes } else { $null }
  $hostFrames = if ($HostConsumer) { $HostConsumer.consumedFrames } else { $null }
  $hookProofBusy = if ($HookMetadata) { $HookMetadata.proofExportBusyFrames } else { $null }

  @(
    '# Local Stream Pipeline Benchmark'
    ''
    '## Executive Summary'
    ''
    "- Status: $status"
    "- Backend: $Backend"
    "- Source: $($SourceProcess.ProcessName) pidHash=sha256-$pidHash"
    "- Present FPS: $presentFps"
    "- Present gap p95/max: $presentP95 / $presentMax ms"
    "- Hook copy avg/max: $copyAvg / $copyMax ms"
    "- Hook proof export busy frames: $hookProofBusy"
    "- Host consumed frames: $hostFrames"
    "- Handoff output FPS: $handoffFps"
    "- Handoff output gap p95/max: $handoffP95 / $handoffMax ms"
    "- Handoff repeated/pace-dropped frames: $handoffRepeated / $handoffPacedDrops"
    "- Handoff output/encoder format: $handoffOutputFormat / $handoffEncoderFormat"
    "- Handoff readback mode: $handoffReadbackMode"
    "- Handoff readback/proof-visible frames: $handoffReadbackFrames / $handoffProofFrames / $handoffVisibleProofFrames"
    "- Handoff NV12 frames/failures/convert avg: $handoffNv12Frames / $handoffNv12Failures / $handoffNv12Convert ms"
    "- Handoff P010 frames/failures/convert avg: $handoffP010Frames / $handoffP010Failures / $handoffP010Convert ms"
    "- Encoder proof mode/frames/failures/init/submit avg/output bytes: $encoderProofMode / $encoderProofFrames / $encoderProofFailures / $encoderProofInit ms / $encoderProofSubmit ms / $encoderProofOutputBytes"
    "- Handoff total frame avg: $handoffTotal ms"
    ''
    '## Requested Settings'
    ''
    "- Source title: $($Requested.sourceTitle)"
    "- Render source size: $($Requested.sourceWidth)x$($Requested.sourceHeight)"
    "- Render source FPS: $($Requested.sourceFps)"
    "- Synthetic source mode/scene/format/HDR-like: $($Requested.syntheticMode), $($Requested.syntheticScene), $($Requested.syntheticFormat), $($Requested.syntheticHdrLike)"
    "- Handoff target: $($Requested.targetWidth)x$($Requested.targetHeight)@$($Requested.targetFps)fps"
    "- Handoff proof/readback/output/encoder proof: $($Requested.publicationProofFrames) frame(s), $($Requested.publicationReadbackMode), $($Requested.publicationOutputFormat), $($Requested.publicationEncoderProof)"
    "- Duration: $($Requested.durationSeconds)s"
    ''
    '## Diagnostic Coverage'
    ''
    "| Category | Status |"
    "| --- | --- |"
    "| Desktop WGC/GDI capture | $($coverage.desktopCapture) |"
    "| D3D11 Present hook | $($coverage.gameCapturePresent) |"
    "| Host texture consumer | $($coverage.hostConsumer) |"
    "| Publication handoff buffer | $($coverage.publicationHandoff) |"
    "| Synthetic target metrics | $($coverage.syntheticTarget) |"
    "| Encoder | $($coverage.encoder) |"
    "| LiveKit/network/receiver | $($coverage.liveKitNetworkReceiver) |"
    ''
    '## Boundaries'
    ''
    'This local harness did not run Matrix login, room join, call creation, LiveKit publishing, TURN/ICE, remote receiver subscription, or WebRTC sender stats. It measures the local D3D11 hook, shared-texture consumer, publication-handoff readiness, and optional local Media Foundation encoder proof only.'
    ''
    '## Output Files'
    ''
    "- Report JSON: $jsonPath"
    "- Helper result directory: $HelperResultDirectory"
    "- Helper metadata: $metadataPath"
    "- Host consumer: $hostPath"
    "- Publication handoff: $handoffPath"
  ) | Set-Content -LiteralPath $mdPath -Encoding UTF8

  return [ordered]@{
    json = $jsonPath
    markdown = $mdPath
  }
}

$repoRoot = Resolve-RepoRoot
Import-StreamLabLocalEnv -RepoRoot $repoRoot
$workspaceRoot = Resolve-StreamLabWorkspaceRoot -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Resolve-StreamLabOutputRoot -RepoRoot $repoRoot -WorkspaceRoot $workspaceRoot
}
if ($PublicationEncoderProof -ne 'off' -and $PublicationOutputFormat -ne 'nv12') {
  throw "PublicationEncoderProof '$PublicationEncoderProof' currently requires PublicationOutputFormat 'nv12'; run P010 as a non-encoder source-conversion proof."
}
if ($PublicationEncoderProof -ne 'off' -and $PublicationProofFrames -gt 0) {
  throw "PublicationEncoderProof '$PublicationEncoderProof' should be run with PublicationProofFrames 0. Run visible proof as a separate non-encoder pass."
}
New-SafeDirectory $OutputRoot

$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDirectory = Join-Path $OutputRoot "local-capture-$runStamp"
New-SafeDirectory $runDirectory

if ($Backend -ne 'future-game-d3d11-hook') {
  $written = Write-NotImplementedReport `
    -RunDirectory $runDirectory `
    -Backend $Backend `
    -Reason 'A standalone WGC/window-GDI desktop capturer CLI does not exist yet; use future-game-d3d11-hook for the local no-call MVP.'
  Write-Host "Local stream benchmark report: $($written.markdown)"
  exit 0
}

$helperCandidates = @(
  $HelperPath,
  (Get-StreamLabEnvValue 'INTERGALACTIC_GAME_CAPTURE_HELPER_PATH'),
  (Join-Path $repoRoot 'plugins\intergalactic_game_capture\windows\build\Debug\intergalactic_game_capture_helper.exe'),
  (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\intergalactic_game_capture_helper.exe')
)
$resolvedHelper = Resolve-FirstExistingPath $helperCandidates 'intergalactic_game_capture_helper.exe'

$targetProcess = $null
$sourceProcess = $null
$captureTargetJson = $null
$captureTargetOutputDir = Join-Path $runDirectory 'capture-target'

try {
  if ($LaunchSyntheticTarget) {
    $targetCandidates = @(
      $SyntheticTargetPath,
      (Get-StreamLabEnvValue 'INTERGALACTIC_GAME_CAPTURE_TARGET_PATH'),
      (Join-Path $repoRoot 'tools\game-capture-target\build\Debug\InterGalacticCaptureTarget.exe'),
      (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\InterGalacticCaptureTarget.exe')
    )
    $resolvedTarget = Resolve-FirstExistingPath $targetCandidates 'InterGalacticCaptureTarget.exe'
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
    $targetArgString = ConvertTo-ArgumentString $targetArgs
    $targetProcess = Start-Process `
      -FilePath $resolvedTarget `
      -ArgumentList $targetArgString `
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

  $durationMs = [Math]::Max(1000, [Math]::Min($DurationSeconds * 1000, 30000))
  $helperOutputRoot = Join-Path $runDirectory 'game-capture-helper'
  New-SafeDirectory $helperOutputRoot
  $stdoutPath = Join-Path $runDirectory 'helper.stdout.txt'
  $stderrPath = Join-Path $runDirectory 'helper.stderr.txt'
  $helperArgs = @(
    '--pid', "$($sourceProcess.Id)",
    '--duration-ms', "$durationMs",
    '--max-saved-frames', "$([Math]::Max(0, [Math]::Min($MaxSavedFrames, 30)))",
    '--host-consume-frames', 'true',
    '--host-proof-frames', "$([Math]::Max(0, [Math]::Min($HostProofFrames, 10)))",
    '--publication-handoff', 'true',
    '--publication-handoff-max-width', "$TargetWidth",
    '--publication-handoff-max-height', "$TargetHeight",
    '--publication-handoff-target-fps', "$TargetFps",
    '--publication-handoff-proof-frames', "$([Math]::Max(0, [Math]::Min($PublicationProofFrames, 10)))",
    '--publication-handoff-readback-mode', $PublicationReadbackMode,
    '--publication-handoff-output-format', $PublicationOutputFormat,
    '--publication-encoder-proof', $PublicationEncoderProof,
    '--output-root', $helperOutputRoot
  )
  $helperArgString = ConvertTo-ArgumentString $helperArgs
  $helperProcess = Start-Process `
    -FilePath $resolvedHelper `
    -ArgumentList $helperArgString `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  $timeoutMs = $durationMs + 30000
  $helperTimedOut = -not $helperProcess.WaitForExit($timeoutMs)
  if ($helperTimedOut) {
    $helperProcess.Kill()
    $helperProcess.WaitForExit()
    $helperExitCode = -1
  } else {
    $helperExitCode = $helperProcess.ExitCode
  }

  if ($targetProcess) {
    Stop-LaunchedTarget $targetProcess
    $targetProcess = $null
  }

  $helperStdout = if (Test-Path -LiteralPath $stdoutPath) {
    Get-Content -LiteralPath $stdoutPath -Raw
  } else {
    ''
  }
  $helperStderr = if (Test-Path -LiteralPath $stderrPath) {
    Get-Content -LiteralPath $stderrPath -Raw
  } else {
    ''
  }

  $stdoutResultDirectory = $null
  if ($helperStdout -match 'Inter Galactic game-capture POC output:\s*(.+)') {
    $candidate = $Matches[1].Trim()
    if (Test-Path -LiteralPath $candidate) {
      $stdoutResultDirectory = (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  if ($stdoutResultDirectory) {
    $metadataCandidate = Join-Path $stdoutResultDirectory 'metadata.json'
    $metadataFile = if (Test-Path -LiteralPath $metadataCandidate) {
      Get-Item -LiteralPath $metadataCandidate
    } else {
      $null
    }
  } else {
    $metadataFile = Get-ChildItem -LiteralPath $helperOutputRoot -Directory |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object {
        $candidate = Join-Path $_.FullName 'metadata.json'
        if (Test-Path -LiteralPath $candidate) {
          Get-Item -LiteralPath $candidate
        }
      } |
      Select-Object -First 1
  }

  $helperResultDirectory = if ($stdoutResultDirectory) {
    $stdoutResultDirectory
  } elseif ($metadataFile) {
    $metadataFile.Directory.FullName
  } else {
    $helperOutputRoot
  }

  $hookMetadata = if ($metadataFile) {
    Read-JsonFileOrNull $metadataFile.FullName
  } else {
    $null
  }
  $hostConsumer = Read-JsonFileOrNull (Join-Path $helperResultDirectory 'host-consumer.json')
  $publicationHandoff = Read-JsonFileOrNull (Join-Path $helperResultDirectory 'publication-handoff.json')
  $captureTargetJson = Read-JsonFileOrNull (Join-Path $captureTargetOutputDir 'capture-target.json')

  $requested = @{
    sourceTitle = $SourceTitle
    sourceWidth = $Width
    sourceHeight = $Height
    sourceFps = $Fps
    syntheticMode = $SyntheticMode
    syntheticScene = $SyntheticScene
    syntheticFormat = $SyntheticFormat
    syntheticHdrLike = [bool]$SyntheticHdrLike
    targetWidth = $TargetWidth
    targetHeight = $TargetHeight
    targetFps = $TargetFps
    durationSeconds = $DurationSeconds
    maxSavedFrames = $MaxSavedFrames
    hostProofFrames = $HostProofFrames
    publicationProofFrames = $PublicationProofFrames
    publicationReadbackMode = $PublicationReadbackMode
    publicationOutputFormat = $PublicationOutputFormat
    publicationEncoderProof = $PublicationEncoderProof
    launchSyntheticTarget = [bool]$LaunchSyntheticTarget
  }

  $written = Write-LocalBenchmarkReport `
    -RunDirectory $runDirectory `
    -Backend $Backend `
    -SourceProcess $sourceProcess `
    -HelperPath $resolvedHelper `
    -HelperExitCode $helperExitCode `
    -HelperTimedOut $helperTimedOut `
    -HelperStdout $helperStdout `
    -HelperStderr $helperStderr `
    -HelperResultDirectory $helperResultDirectory `
    -HookMetadata $hookMetadata `
    -HostConsumer $hostConsumer `
    -PublicationHandoff $publicationHandoff `
    -CaptureTarget $captureTargetJson `
    -Requested $requested

  Write-Host "Local stream benchmark report: $($written.markdown)"
  if ($helperExitCode -ne 0) {
    exit $helperExitCode
  }
} finally {
  if ($targetProcess) {
    Stop-LaunchedTarget $targetProcess
  }
}
