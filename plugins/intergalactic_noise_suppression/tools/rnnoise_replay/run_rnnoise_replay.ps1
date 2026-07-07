param(
  [string]$InputPath,
  [ValidateSet('plosive-speech')]
  [string]$Fixture,
  [string]$OutputRoot,
  [string]$RunName,
  [ValidateSet('clean', 'identity', 'off', 'tuned', 'prototype_suppression', 'prototype_suppression_v2')]
  [string]$Mode = 'clean',
  [ValidateSet('clean', 'identity', 'off', 'tuned', 'prototype_suppression', 'prototype_suppression_v2')]
  [string[]]$Modes,
  [ValidateSet('baseline', 'gentle', 'balanced', 'strong')]
  [string[]]$TunedProfiles = @(),
  [string[]]$CustomProfiles = @(),
  [int[]]$SampleRateHz = @(16000, 48000),
  [string[]]$Segments = @(
    'speech=0-7.14',
    'keyboard=7.14-14.27',
    'clicks=14.27-21.41'
  ),
  [string[]]$EqualSegments = @(),
  [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

function Resolve-MatrixDevRoot {
  $path = (Resolve-Path $PSScriptRoot).Path
  for ($i = 0; $i -lt 6; $i++) {
    $path = Split-Path -Parent $path
  }
  return $path
}

function Invoke-SanitizedProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $pathValue = [Environment]::GetEnvironmentVariable('Path', 'Process')
  if ([string]::IsNullOrEmpty($pathValue)) {
    $pathValue = [Environment]::GetEnvironmentVariable('PATH', 'Process')
  }

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  $psi.UseShellExecute = $false
  if ($null -ne $psi.ArgumentList) {
    foreach ($argument in $Arguments) {
      $psi.ArgumentList.Add($argument)
    }
  } else {
    $escapedArguments = foreach ($argument in $Arguments) {
      if ($argument -match '[\s"]') {
        '"' + ($argument -replace '"', '\"') + '"'
      } else {
        $argument
      }
    }
    $psi.Arguments = $escapedArguments -join ' '
  }

  $envMap = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
    if (-not $envMap.ContainsKey([string]$entry.Key)) {
      $envMap.Add([string]$entry.Key, [string]$entry.Value)
    }
  }
  $envMap.Remove('PATH') | Out-Null
  $envMap.Remove('Path') | Out-Null

  if ($null -ne $psi.Environment) {
    $psi.Environment.Clear()
    foreach ($key in $envMap.Keys) {
      $psi.Environment[$key] = $envMap[$key]
    }
    if (-not [string]::IsNullOrEmpty($pathValue)) {
      $psi.Environment['Path'] = $pathValue
    }
  } else {
    $psi.EnvironmentVariables.Clear()
    foreach ($key in $envMap.Keys) {
      $psi.EnvironmentVariables.Set_Item($key, $envMap[$key])
    }
    if (-not [string]::IsNullOrEmpty($pathValue)) {
      $psi.EnvironmentVariables.Set_Item('Path', $pathValue)
    }
  }

  $process = [System.Diagnostics.Process]::Start($psi)
  $process.WaitForExit()
  return $process.ExitCode
}

function Get-TunedProfileArguments {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Profile
  )

  switch ($Profile.ToLowerInvariant()) {
    'baseline' {
      return @(
        '--vad-threshold', '0.90',
        '--speech-grace-frames', '20',
        '--closed-gain', '0.03',
        '--transient-sensitivity', '0.0',
        '--fast-close', 'false'
      )
    }
    'gentle' {
      return @(
        '--vad-threshold', '0.90',
        '--speech-grace-frames', '20',
        '--closed-gain', '0.03',
        '--transient-sensitivity', '0.0',
        '--fast-close', 'false'
      )
    }
    'balanced' {
      return @(
        '--vad-threshold', '0.91',
        '--speech-grace-frames', '14',
        '--closed-gain', '0.01',
        '--transient-sensitivity', '0.72',
        '--fast-close', 'true'
      )
    }
    'strong' {
      return @(
        '--vad-threshold', '0.95',
        '--speech-grace-frames', '10',
        '--closed-gain', '0.001',
        '--transient-sensitivity', '1.0',
        '--fast-close', 'true'
      )
    }
  }

  throw "Unknown tuned profile: $Profile"
}

function Get-CustomProfileCase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Profile
  )

  $nameAndValues = $Profile -split '=', 2
  if ($nameAndValues.Count -ne 2 -or [string]::IsNullOrWhiteSpace($nameAndValues[0])) {
    throw "Custom profiles must use name=vad,grace,gain,transient,fastClose: $Profile"
  }

  $label = $nameAndValues[0].Trim()
  if ($label -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw "Custom profile label must use letters, numbers, dot, underscore, or dash: $label"
  }

  $values = $nameAndValues[1].Split(',') | ForEach-Object { $_.Trim() }
  if ($values.Count -ne 5) {
    throw "Custom profile '$label' must provide exactly five values: vad,grace,gain,transient,fastClose"
  }

  $vad = 0.0
  $grace = 0
  $gain = 0.0
  $transient = 0.0
  $fastClose = $false
  if (-not [double]::TryParse($values[0], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$vad)) {
    throw "Custom profile '$label' has invalid VAD threshold: $($values[0])"
  }
  if (-not [int]::TryParse($values[1], [ref]$grace)) {
    throw "Custom profile '$label' has invalid speech grace frame count: $($values[1])"
  }
  if (-not [double]::TryParse($values[2], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$gain)) {
    throw "Custom profile '$label' has invalid closed gain: $($values[2])"
  }
  if (-not [double]::TryParse($values[3], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$transient)) {
    throw "Custom profile '$label' has invalid transient sensitivity: $($values[3])"
  }
  if (-not [bool]::TryParse($values[4], [ref]$fastClose)) {
    throw "Custom profile '$label' has invalid fastClose value: $($values[4])"
  }

  if ($vad -lt 0.50 -or $vad -gt 0.999) {
    throw "Custom profile '$label' VAD threshold must be between 0.50 and 0.999."
  }
  if ($grace -lt 0 -or $grace -gt 100) {
    throw "Custom profile '$label' speech grace frames must be between 0 and 100."
  }
  if ($gain -lt 0.0 -or $gain -gt 1.0) {
    throw "Custom profile '$label' closed gain must be between 0.0 and 1.0."
  }
  if ($transient -lt 0.0 -or $transient -gt 1.0) {
    throw "Custom profile '$label' transient sensitivity must be between 0.0 and 1.0."
  }

  return [pscustomobject]@{
    Label = "custom-$label"
    Mode = 'tuned'
    TuningArgs = @(
      '--vad-threshold', $vad.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture),
      '--speech-grace-frames', [string]$grace,
      '--closed-gain', $gain.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture),
      '--transient-sensitivity', $transient.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture),
      '--fast-close', $fastClose.ToString().ToLowerInvariant()
    )
  }
}

function Get-ReplayCaseClassification {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $lower = $Label.ToLowerInvariant()
  switch ($lower) {
    'off' {
      return [pscustomobject]@{
        Group = 'Controls'
        Role = 'control only; no RNNoise processing'
        SortOrder = 10
      }
    }
    'identity' {
      return [pscustomobject]@{
        Group = 'Controls'
        Role = 'hook/control only; copies input unchanged'
        SortOrder = 20
      }
    }
    'clean' {
      return [pscustomobject]@{
        Group = 'Production presets'
        Role = 'clean_rnnoise rollback suppression path'
        SortOrder = 30
      }
    }
    'gentle' {
      return [pscustomobject]@{
        Group = 'Production presets'
        Role = 'conservative rollback suppression preset'
        SortOrder = 40
      }
    }
    'balanced' {
      return [pscustomobject]@{
        Group = 'Production presets'
        Role = 'practical tuned suppression preset'
        SortOrder = 50
      }
    }
    'strong' {
      return [pscustomobject]@{
        Group = 'Production presets'
        Role = 'aggressive suppression preset'
        SortOrder = 60
      }
    }
    'prototype_suppression' {
      return [pscustomobject]@{
        Group = 'Experimental candidates'
        Role = 'lab-only non-scalar transient/stationary prototype mode'
        SortOrder = 65
      }
    }
    'prototype_suppression_v2' {
      return [pscustomobject]@{
        Group = 'Experimental candidates'
        Role = 'lab-only speech-protected transient/stationary prototype v2'
        SortOrder = 66
      }
    }
    'baseline' {
      return [pscustomobject]@{
        Group = 'Experimental candidates'
        Role = 'historical tuned baseline comparator'
        SortOrder = 70
      }
    }
  }

  if ($lower.StartsWith('custom-')) {
    return [pscustomobject]@{
      Group = 'Experimental candidates'
      Role = 'custom scalar suppression candidate'
      SortOrder = 80
    }
  }

  return [pscustomobject]@{
    Group = 'Experimental candidates'
    Role = 'suppression comparison candidate'
    SortOrder = 90
  }
}

function Get-ScoreNumber {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Score,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName,
    [double]$Fallback = 0.0
  )

  $property = $Score.PSObject.Properties[$PropertyName]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $Fallback
  }
  return [double]$property.Value
}

function Get-ScoreBoolText {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Score,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName
  )

  $property = $Score.PSObject.Properties[$PropertyName]
  if ($null -eq $property -or $null -eq $property.Value) {
    return 'n/a'
  }
  if ([bool]$property.Value) {
    return 'pass'
  }
  return 'review'
}

function Add-ComparisonSection {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IList]$Lines,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [AllowEmptyCollection()]
    [object[]]$Rows,
    [string]$Note
  )

  if ($Rows.Count -eq 0) {
    return
  }

  $Lines.Add("## $Title")
  $Lines.Add('')
  if (-not [string]::IsNullOrWhiteSpace($Note)) {
    $Lines.Add($Note)
    $Lines.Add('')
  }
  $Lines.Add('| Mode | Role | Rate | Candidate | Speech | Noise | Safety | Speech gate | Safety gate | Output peak | Output max delta | Gated | Limiter | Resampler issues |')
  $Lines.Add('| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |')
  foreach ($row in ($Rows | Sort-Object -Property `
        @{ Expression = 'Rate'; Descending = $false }, `
        @{ Expression = 'SortOrder'; Descending = $false }, `
        @{ Expression = 'CandidateScore'; Descending = $true })) {
    $Lines.Add(('| {0} | {1} | {2} | {3:N1} | {4:N1} | {5:N1} | {6:N1} | {7} | {8} | {9:N4} | {10:N4} | {11} | {12} | {13} |' -f `
          $row.Mode,
          $row.Role,
          $row.Rate,
          $row.CandidateScore,
          $row.Speech,
          $row.Noise,
          $row.Safety,
          $row.SpeechGate,
          $row.SafetyGate,
          $row.OutputPeak,
          $row.OutputMaxDelta,
          $row.GatedFrames,
          $row.LimiterSamples,
          $row.ResamplerIssues))
  }
  $Lines.Add('')
}

$matrixDevRoot = Resolve-MatrixDevRoot
$useFixture = -not [string]::IsNullOrWhiteSpace($Fixture)
if ($useFixture -and -not [string]::IsNullOrWhiteSpace($InputPath)) {
  throw 'Specify exactly one of -InputPath or -Fixture.'
}
if ([string]::IsNullOrWhiteSpace($InputPath) -and -not $useFixture) {
  $InputPath = Join-Path $matrixDevRoot 'docs\logs\Audio_Samples\Sample.m4a'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $matrixDevRoot 'runtime\rnnoise-replay'
}

$resolvedInput = $null
$ffmpeg = $null
if (-not $useFixture) {
  $resolvedInput = (Resolve-Path $InputPath).Path
  $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($null -eq $ffmpeg) {
    throw 'ffmpeg is required to decode m4a/wav inputs for RNNoise replay.'
  }
}
$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
$cmakeExe = if ($null -ne $cmakeCommand) { $cmakeCommand.Source } else { $null }
if ($null -eq $cmakeExe) {
  $cmakeCandidates = @()
  if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $cmakeCandidates += Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe'
    $cmakeCandidates += Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
  }
  $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
  if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
    $cmakeCandidates += Join-Path $programFilesX86 'CMake\bin\cmake.exe'
  }
  foreach ($candidate in $cmakeCandidates) {
    if (Test-Path $candidate) {
      $cmakeExe = $candidate
      break
    }
  }
}
if ($null -eq $cmakeExe) {
  throw 'CMake is required to build the RNNoise replay harness.'
}

$modesToRun = if ($null -ne $Modes -and $Modes.Count -gt 0) { $Modes } else { @($Mode) }
$replayCases = New-Object System.Collections.Generic.List[object]
foreach ($modeToRun in $modesToRun) {
  $replayCases.Add([pscustomobject]@{
      Label = $modeToRun
      Mode = $modeToRun
      TuningArgs = @()
    }) | Out-Null
}
foreach ($profile in $TunedProfiles) {
  $profileMode = if ($profile -eq 'gentle') { 'clean' } else { 'tuned' }
  $replayCases.Add([pscustomobject]@{
      Label = $profile
      Mode = $profileMode
      TuningArgs = Get-TunedProfileArguments -Profile $profile
    }) | Out-Null
}
foreach ($customProfile in $CustomProfiles) {
  $replayCases.Add((Get-CustomProfileCase -Profile $customProfile)) | Out-Null
}
$segmentArgument = $null
if ($null -ne $Segments -and $Segments.Count -gt 0) {
  $segmentArgument = @('--segments', ($Segments -join ','))
} elseif ($null -ne $EqualSegments -and $EqualSegments.Count -gt 0) {
  $segmentArgument = @('--equal-segments', ($EqualSegments -join ','))
}

$buildDir = Join-Path $OutputRoot 'build'
$runStamp = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
if (-not [string]::IsNullOrWhiteSpace($RunName)) {
  if ([System.IO.Path]::IsPathRooted($RunName) -or $RunName -match '(^|[\\/])\.\.([\\/]|$)') {
    throw 'RunName must be a relative path under OutputRoot.'
  }
  $runStamp = $RunName
}
$runDir = Join-Path $OutputRoot $runStamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

if (-not $NoBuild) {
  New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
  $exitCode = Invoke-SanitizedProcess -FilePath $cmakeExe -Arguments @(
    '-S', $PSScriptRoot,
    '-B', $buildDir,
    '-G', 'Visual Studio 17 2022',
    '-A', 'x64'
  )
  if ($exitCode -ne 0) {
    throw 'CMake configure failed for RNNoise replay harness.'
  }
  $exitCode = Invoke-SanitizedProcess -FilePath $cmakeExe -Arguments @(
    '--build', $buildDir,
    '--config', 'Release',
    '--target', 'intergalactic_rnnoise_replay'
  )
  if ($exitCode -ne 0) {
    throw 'CMake build failed for RNNoise replay harness.'
  }
}

$exe = Join-Path $buildDir 'Release\intergalactic_rnnoise_replay.exe'
if (-not (Test-Path $exe)) {
  throw "Replay executable not found: $exe"
}

$summaries = New-Object System.Collections.Generic.List[string]
$summaries.Add('# RNNoise Replay Run')
$summaries.Add('')
if ($useFixture) {
  $summaries.Add("- Fixture: ``$Fixture``")
} else {
  $summaries.Add("- Input: ``$resolvedInput``")
}
$summaries.Add("- Cases: ``$(($replayCases | ForEach-Object { $_.Label }) -join ', ')``")
$summaries.Add("- Output: ``$runDir``")
if ($null -ne $Segments -and $Segments.Count -gt 0) {
  $summaries.Add("- Segments: ``$($Segments -join ', ')``")
} elseif ($null -ne $EqualSegments -and $EqualSegments.Count -gt 0) {
  $summaries.Add("- Equal segments: ``$($EqualSegments -join ', ')``")
}
$summaries.Add('')
$summaries.Add('## Decision')
$summaries.Add('')
$summaries.Add('No custom preset should replace the current production presets from this pass. Keep RNNoise suppression available. Keep `balanced` as the practical tuned preset, `strong` as aggressive, and `gentle` as rollback. Continue tuning with better segment labels and human listening.')
$summaries.Add('')
$summaries.Add('`off` and `identity` are controls only. They are useful baselines for speech preservation and hook integrity, but they are not production winners because they do not perform noise suppression.')
$summaries.Add('')

$comparisonRows = New-Object System.Collections.Generic.List[object]

foreach ($replayCase in $replayCases) {
  foreach ($rate in $SampleRateHz) {
    if ($rate -le 0 -or ($rate % 100) -ne 0) {
      throw "Sample rate must divide into 10 ms frames: $rate"
    }

    $rateDir = Join-Path $runDir "$($rate)hz-$($replayCase.Label)"
    New-Item -ItemType Directory -Force -Path $rateDir | Out-Null
    $decoded = Join-Path $rateDir 'decoded-input.wav'

    $replayArguments = @(
      '--output', $rateDir,
      '--mode', $replayCase.Mode,
      '--label', "$rate Hz $($replayCase.Label)"
    )
    if ($useFixture) {
      $replayArguments += @(
        '--fixture', $Fixture,
        '--sample-rate-hz', [string]$rate
      )
    } else {
      $exitCode = Invoke-SanitizedProcess -FilePath $ffmpeg.Source -Arguments @(
        '-hide_banner',
        '-loglevel', 'error',
        '-y',
        '-i', $resolvedInput,
        '-ac', '1',
        '-ar', [string]$rate,
        '-c:a', 'pcm_s16le',
        $decoded
      )
      if ($exitCode -ne 0) {
        throw "ffmpeg decode failed for $rate Hz."
      }
      $replayArguments += @('--input', $decoded)
    }
    if ($null -ne $segmentArgument) {
      $replayArguments += $segmentArgument
    }
    if ($null -ne $replayCase.TuningArgs -and $replayCase.TuningArgs.Count -gt 0) {
      $replayArguments += $replayCase.TuningArgs
    }
    $exitCode = Invoke-SanitizedProcess -FilePath $exe -Arguments $replayArguments
    if ($exitCode -ne 0) {
      throw "RNNoise replay failed for $rate Hz $($replayCase.Label)."
    }

    $summaryJson = Join-Path $rateDir 'replay-summary.json'
    $summaryMd = Join-Path $rateDir 'replay-summary.md'
    $summary = Get-Content $summaryJson -Raw | ConvertFrom-Json
    $classification = Get-ReplayCaseClassification -Label $replayCase.Label
    $candidateScore = Get-ScoreNumber -Score $summary.score -PropertyName 'candidateScore' -Fallback ([double]$summary.score.overall)
    $speechGate = Get-ScoreBoolText -Score $summary.score -PropertyName 'speechSafetyPassed'
    $safetyGate = Get-ScoreBoolText -Score $summary.score -PropertyName 'artifactSafetyPassed'
    $hasNoiseSegments = $true
    $hasNoiseProperty = $summary.score.PSObject.Properties['hasNoiseSegments']
    if ($null -ne $hasNoiseProperty -and $null -ne $hasNoiseProperty.Value) {
      $hasNoiseSegments = [bool]$hasNoiseProperty.Value
    }
    $noiseEvidence = if ($hasNoiseSegments) { 'yes' } else { 'no' }

    $comparisonRows.Add([pscustomobject]@{
        Mode = $replayCase.Label
        Group = $classification.Group
        Role = $classification.Role
        SortOrder = $classification.SortOrder
        Rate = $rate
        CandidateScore = $candidateScore
        Overall = [double]$summary.score.overall
        Speech = [double]$summary.score.speechPreservation
        Noise = [double]$summary.score.noiseReduction
        Safety = [double]$summary.score.artifactSafety
        SpeechGate = $speechGate
        SafetyGate = $safetyGate
        HasNoiseSegments = $hasNoiseSegments
        OutputMaxDelta = [double]$summary.outputMetrics.maxDelta
        OutputPeak = [double]$summary.outputMetrics.peak
        GatedFrames = [int]$summary.state.gatedFrames
        LimiterSamples = [int]$summary.state.outputLimiterSamples
        ResamplerIssues = [int]($summary.state.resamplerInputUnderruns + $summary.state.resamplerOutputUnderruns + $summary.state.resamplerOverruns)
        Summary = $summaryMd
        ProcessedOutput = [string]$summary.processedOutput
      }) | Out-Null

    $summaries.Add("## $($replayCase.Label) - $rate Hz")
    $summaries.Add('')
    $summaries.Add("- Summary: ``$summaryMd``")
    $summaries.Add("- Processed output: ``$($summary.processedOutput)``")
    $summaries.Add("- Stage WAVs: ``$($summary.stagesDirectory)``")
    $summaries.Add("- Classification: ``$($classification.Group)`` / ``$($classification.Role)``")
    $summaries.Add("- Score candidate/speech/noise/safety: ``$candidateScore`` / ``$($summary.score.speechPreservation)`` / ``$($summary.score.noiseReduction)`` / ``$($summary.score.artifactSafety)``")
    $summaries.Add("- Gates speech/safety/noise-evidence: ``$speechGate`` / ``$safetyGate`` / ``$noiseEvidence``")
    $summaries.Add("- Frames processed: ``$($summary.state.framesProcessed)``")
    $summaries.Add("- Bypass/gated frames: ``$($summary.state.bypassFrames)`` / ``$($summary.state.gatedFrames)``")
    $summaries.Add("- Input/output peak: ``$($summary.inputMetrics.peak)`` / ``$($summary.outputMetrics.peak)``")
    $summaries.Add("- Input/output max delta: ``$($summary.inputMetrics.maxDelta)`` / ``$($summary.outputMetrics.maxDelta)``")
    $summaries.Add("- Worse-than-input frames: ``$($summary.worseThanInputFrames)``")
    $summaries.Add("- Limiter samples: ``$($summary.state.outputLimiterSamples)``")
    $summaries.Add("- Resampler uses/underruns/overruns: ``$($summary.state.resamplerUses)`` / ``$($summary.state.resamplerInputUnderruns + $summary.state.resamplerOutputUnderruns)`` / ``$($summary.state.resamplerOverruns)``")
    if ($null -ne $summary.segments -and $summary.segments.Count -gt 0) {
      $summaries.Add('')
      $summaries.Add('| Segment | Seconds | Input RMS | Output RMS | Output max delta | Worse frames |')
      $summaries.Add('| --- | ---: | ---: | ---: | ---: | ---: |')
      foreach ($segment in $summary.segments) {
        $summaries.Add(('| {0} | {1:N2}-{2:N2} | {3:N4} | {4:N4} | {5:N4} | {6} |' -f `
              $segment.name,
              $segment.startSeconds,
              $segment.endSeconds,
              $segment.inputMetrics.rms,
              $segment.outputMetrics.rms,
              $segment.outputMetrics.maxDelta,
              $segment.worseThanInputFrames))
      }
    }
    $summaries.Add('')
  }
}

if ($comparisonRows.Count -gt 0) {
  Add-ComparisonSection `
    -Lines $summaries `
    -Title 'Controls' `
    -Rows @($comparisonRows | Where-Object { $_.Group -eq 'Controls' }) `
    -Note 'Controls prove hook and speech-preservation baselines. They are intentionally excluded from production preset ranking because they do not perform RNNoise suppression.'

  Add-ComparisonSection `
    -Lines $summaries `
    -Title 'Production Presets' `
    -Rows @($comparisonRows | Where-Object { $_.Group -eq 'Production presets' }) `
    -Note '`gentle`/`clean` are rollback suppression paths, `balanced` is the practical tuned suppression path, and `strong` is the aggressive suppression path.'

  Add-ComparisonSection `
    -Lines $summaries `
    -Title 'Experimental Candidates' `
    -Rows @($comparisonRows | Where-Object { $_.Group -eq 'Experimental candidates' }) `
    -Note 'Experimental candidates must clear speech and artifact gates, then beat production presets on real noise reduction before they can be promoted.'

  $rates = @($comparisonRows | ForEach-Object { $_.Rate } | Sort-Object -Unique)
  $preferredRate = $null
  if ($rates -contains 48000) {
    $preferredRate = 48000
  } elseif ($rates.Count -gt 0) {
    $preferredRate = [int]($rates | Select-Object -Last 1)
  }
  $candidateRows = if ($null -ne $preferredRate) {
    @($comparisonRows | Where-Object { $_.Rate -eq $preferredRate })
  } else {
    @($comparisonRows)
  }

  $listeningRows = New-Object System.Collections.Generic.List[object]
  foreach ($label in @('off', 'identity', 'clean', 'gentle', 'balanced', 'strong')) {
    $matches = @($candidateRows | Where-Object { $_.Mode -eq $label } | Select-Object -First 1)
    if ($matches.Count -gt 0) {
      $listeningRows.Add($matches[0]) | Out-Null
    }
  }
  $bestCustomRows = @(
    $candidateRows |
      Where-Object { $_.Mode -like 'custom-*' } |
      Sort-Object -Property `
        @{ Expression = 'CandidateScore'; Descending = $true }, `
        @{ Expression = 'Mode'; Descending = $false } |
      Select-Object -First 1
  )
  if ($bestCustomRows.Count -gt 0) {
    $listeningRows.Add($bestCustomRows[0]) | Out-Null
  }

  $uniqueListeningRows = New-Object System.Collections.Generic.List[object]
  $seenListeningRows = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  foreach ($row in $listeningRows) {
    $key = "$($row.Rate)|$($row.Mode)"
    if ($seenListeningRows.Add($key)) {
      $uniqueListeningRows.Add($row) | Out-Null
    }
  }

  if ($uniqueListeningRows.Count -gt 0) {
    $listeningSheet = Join-Path $runDir 'listening-review.md'
    $listeningLines = New-Object System.Collections.Generic.List[string]
    $clipLabel = if ($useFixture) { $Fixture } else { Split-Path -Leaf $resolvedInput }
    $listeningLines.Add('# RNNoise Listening Review')
    $listeningLines.Add('')
    $listeningLines.Add("- Clip: ``$clipLabel``")
    $listeningLines.Add("- Source: ``$(if ($useFixture) { $Fixture } else { $resolvedInput })``")
    $listeningLines.Add("- Preferred review rate: ``$preferredRate Hz``")
    $listeningLines.Add("- Review intent: choose effective suppression that does not damage speech; do not promote no-suppression controls.")
    $listeningLines.Add('')
    $listeningLines.Add('For each output, listen through the full clip and mark the checks that match what you hear.')
    $listeningLines.Add('')
    foreach ($row in ($uniqueListeningRows | Sort-Object -Property `
          @{ Expression = 'SortOrder'; Descending = $false }, `
          @{ Expression = 'Mode'; Descending = $false })) {
      $listeningLines.Add("## $($row.Mode) - $($row.Rate) Hz")
      $listeningLines.Add('')
      $listeningLines.Add("- Classification: ``$($row.Group)`` / ``$($row.Role)``")
      $listeningLines.Add("- Output: ``$($row.ProcessedOutput)``")
      $listeningLines.Add("- Score candidate/speech/noise/safety: ``$($row.CandidateScore)`` / ``$($row.Speech)`` / ``$($row.Noise)`` / ``$($row.Safety)``")
      $listeningLines.Add('- [ ] speech natural')
      $listeningLines.Add('- [ ] speech robotic')
      $listeningLines.Add('- [ ] speech clipped')
      $listeningLines.Add('- [ ] speech tail cut off')
      $listeningLines.Add('- [ ] chair squeak reduced')
      $listeningLines.Add('- [ ] chair squeak became pop/click')
      $listeningLines.Add('- [ ] music pumping')
      $listeningLines.Add('- [ ] acceptable for calls')
      $listeningLines.Add('- [ ] unacceptable')
      $listeningLines.Add('- Notes:')
      $listeningLines.Add('')
    }
    Set-Content -Path $listeningSheet -Value $listeningLines -Encoding UTF8

    $summaries.Add('## Listening Review Packet')
    $summaries.Add('')
    $summaries.Add("- Sheet: ``$listeningSheet``")
    $summaries.Add("- Selected outputs: ``$(($uniqueListeningRows | ForEach-Object { "$($_.Mode) $($_.Rate) Hz" }) -join ', ')``")
    $summaries.Add('')
  }

  $summaries.Add('## Scalar Candidate Tie Investigation')
  $summaries.Add('')
  $tieCandidateRows = @(
    $candidateRows |
      Where-Object { $_.Mode -in @('balanced', 'strong') -or $_.Mode -like 'custom-*' } |
      Sort-Object -Property `
        @{ Expression = 'CandidateScore'; Descending = $true }, `
        @{ Expression = 'Mode'; Descending = $false }
  )
  if ($tieCandidateRows.Count -gt 0) {
    $topScore = [double]$tieCandidateRows[0].CandidateScore
    $tieLabels = New-Object System.Collections.Generic.List[string]
    foreach ($row in ($tieCandidateRows | Where-Object { [Math]::Abs([double]$_.CandidateScore - $topScore) -le 0.25 })) {
      $tieLabels.Add(('{0} ({1:N1})' -f $row.Mode, [double]$row.CandidateScore)) | Out-Null
    }
    $summaries.Add("- Top cluster at ``$preferredRate Hz``: ``$(($tieLabels | ForEach-Object { $_ }) -join ', ')``. Rows within 0.25 points are metric ties pending human listening.")
  } else {
    $summaries.Add('- No balanced/strong/custom rows were available for tie comparison in this run.')
  }
  $summaries.Add('- The replay runner passes distinct scalar arguments for each tuned/custom case, and each native replay JSON records the requested `tuning` values.')
  $summaries.Add('- The native replay harness writes those values into `ProcessorSharedState` before processing each output directory, so repeated scores point to similar native behavior rather than a skipped runner configuration.')
  $summaries.Add('- Current scalar changes can still collapse when high-VAD mechanical transients are treated as protected speech or when the same harsh-transient branch handles every candidate similarly.')
  $summaries.Add('- The next useful pass needs deeper transient classification evidence instead of only moving VAD threshold, closed gain, and grace-frame scalars.')
  $summaries.Add('')

  $summaries.Add('## Next Candidate Sweep Proposal')
  $summaries.Add('')
  $summaries.Add('- Keep this proposal out of production defaults until human listening and LiveKit loopback validation approve it.')
  $summaries.Add('- Add a second candidate family around stronger high-crest transient detection, a short hold-closed window for narrow mechanical transients, and a separate squeak/click path.')
  $summaries.Add('- Weight suppression by peak/delta/crest evidence while preserving speech transients with RMS and speech-confidence guards.')
  $summaries.Add('- Use non-zero closed gain with ramped open/close. Do not hard mute, do not use zero closed gain, and do not reduce global output volume to fake improvement.')
  $summaries.Add('')
}

$runSummary = Join-Path $runDir 'run-summary.md'
Set-Content -Path $runSummary -Value $summaries -Encoding UTF8
Write-Host "RNNoise replay complete: $runSummary"
