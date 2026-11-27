param(
  [string]$InputVideo = '',
  [string]$BenchmarkReportJson = '',
  [string]$OutputRoot = '',
  [string]$OutputDirectory = '',
  [string]$SampleMode = '',
  [double]$SampleFps = 30.0,
  [int]$ScaleWidth = 64,
  [int]$ScaleHeight = 36,
  [double]$UniqueFrameThreshold = 3.0,
  [double]$LocalUniqueFrameThreshold = 12.0,
  [int]$LocalBlockWidth = 8,
  [int]$LocalBlockHeight = 6,
  [double]$LowChangeThreshold = 1.5,
  [int]$MaxFrames = 0,
  [double]$MinUniqueFps = 0.0,
  [switch]$FailBelowMinUniqueFps,
  [switch]$ExcludeReceiverProbeMarkerRegion,
  [switch]$ExcludeSourceFrameMarkerRegion,
  [switch]$DecodeSourceFrameMarker,
  [int]$SourceFrameMarkerOffsetX = 0,
  [int]$SourceFrameMarkerOffsetY = 0,
  [string]$FfmpegPath = '',
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'stream_lab_env.ps1')

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function New-SafeDirectory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Read-JsonFile([string]$Path) {
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
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

function Get-NestedJsonProperty([object]$Object, [string[]]$Names) {
  $current = $Object
  foreach ($name in $Names) {
    $current = Get-JsonProperty $current $name
    if ($null -eq $current) {
      return $null
    }
  }
  return $current
}

function ConvertTo-ShortHash([string]$Value) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
    return (($hash[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
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

function Resolve-Ffmpeg([string]$ConfiguredPath) {
  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    return (Resolve-Path -LiteralPath $ConfiguredPath).Path
  }
  $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }
  throw 'ffmpeg was not found on PATH. Set -FfmpegPath to a local ffmpeg.exe.'
}

function Get-MeanAbsDiff([byte[]]$Previous, [byte[]]$Current) {
  if ($Previous.Length -ne $Current.Length) {
    throw 'Frame buffers have different lengths.'
  }
  $sum = 0.0
  for ($i = 0; $i -lt $Current.Length; $i++) {
    $sum += [Math]::Abs([int]$Current[$i] - [int]$Previous[$i])
  }
  return $sum / [double]$Current.Length
}

function Get-MaxBlockMeanAbsDiff(
  [byte[]]$Previous,
  [byte[]]$Current,
  [int]$Width,
  [int]$Height,
  [int]$BlockWidth,
  [int]$BlockHeight
) {
  if ($Previous.Length -ne $Current.Length) {
    throw 'Frame buffers have different lengths.'
  }
  if ($BlockWidth -le 0 -or $BlockHeight -le 0) {
    throw 'Local block dimensions must be greater than zero.'
  }

  $maxDiff = 0.0
  for ($blockY = 0; $blockY -lt $Height; $blockY += $BlockHeight) {
    $actualBlockHeight = [Math]::Min($BlockHeight, $Height - $blockY)
    for ($blockX = 0; $blockX -lt $Width; $blockX += $BlockWidth) {
      $actualBlockWidth = [Math]::Min($BlockWidth, $Width - $blockX)
      $sum = 0.0
      for ($y = 0; $y -lt $actualBlockHeight; $y++) {
        $rowOffset = ($blockY + $y) * $Width
        for ($x = 0; $x -lt $actualBlockWidth; $x++) {
          $index = $rowOffset + $blockX + $x
          $sum += [Math]::Abs([int]$Current[$index] - [int]$Previous[$index])
        }
      }
      $blockPixels = [double]($actualBlockWidth * $actualBlockHeight)
      if ($blockPixels -gt 0) {
        $blockDiff = $sum / $blockPixels
        if ($blockDiff -gt $maxDiff) {
          $maxDiff = $blockDiff
        }
      }
    }
  }
  return $maxDiff
}

function Get-FrameHash([byte[]]$Frame) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Frame)
    return (([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant())
  } finally {
    $sha.Dispose()
  }
}

function Get-SourceFrameMarkerRegion(
  [int]$Width,
  [int]$Height,
  [int]$OffsetX,
  [int]$OffsetY
) {
  return [pscustomobject]@{
    x = [Math]::Max(0, [Math]::Min($Width - 1, $OffsetX))
    y = [Math]::Max(0, [Math]::Min($Height - 1, $OffsetY))
    width = [Math]::Min($Width, [Math]::Max(1, [int][Math]::Ceiling($Width * 0.16)))
    height = [Math]::Min($Height, [Math]::Max(1, [int][Math]::Ceiling($Height * 0.14)))
  }
}

function Clear-FrameRegion(
  [byte[]]$Frame,
  [int]$Width,
  [int]$Height,
  [int]$X,
  [int]$Y,
  [int]$RegionWidth,
  [int]$RegionHeight
) {
  $x0 = [Math]::Max(0, $X)
  $y0 = [Math]::Max(0, $Y)
  $x1 = [Math]::Min($Width, $X + $RegionWidth)
  $y1 = [Math]::Min($Height, $Y + $RegionHeight)
  for ($y = $y0; $y -lt $y1; $y++) {
    $rowOffset = $y * $Width
    for ($x = $x0; $x -lt $x1; $x++) {
      $Frame[$rowOffset + $x] = 0
    }
  }
}

function Get-SourceFrameMarkerId(
  [byte[]]$Frame,
  [int]$Width,
  [int]$Height,
  [int]$OffsetX,
  [int]$OffsetY
) {
  $region = Get-SourceFrameMarkerRegion `
    -Width $Width `
    -Height $Height `
    -OffsetX $OffsetX `
    -OffsetY $OffsetY
  if ($region.width -lt 16 -or $region.height -lt 8) {
    return $null
  }

  $marginX = [Math]::Max(1, [int][Math]::Round($region.width * 0.10))
  $marginY = [Math]::Max(1, [int][Math]::Round($region.height * 0.18))
  $markerColumns = 8
  $markerRows = 8
  $markerIdRows = 2
  $cellWidth = ($region.width - (2.0 * $marginX)) / [double]$markerColumns
  $cellHeight = ($region.height - (2.0 * $marginY)) / [double]$markerRows
  if ($cellWidth -lt 1.0 -or $cellHeight -lt 1.0) {
    return $null
  }

  $id = 0
  for ($row = 0; $row -lt $markerIdRows; $row++) {
    for ($column = 0; $column -lt $markerColumns; $column++) {
      $sampleX0 = [int][Math]::Floor($region.x + $marginX + ($column * $cellWidth) + ($cellWidth * 0.25))
      $sampleX1 = [int][Math]::Ceiling($region.x + $marginX + (($column + 1) * $cellWidth) - ($cellWidth * 0.25))
      $sampleY0 = [int][Math]::Floor($region.y + $marginY + ($row * $cellHeight) + ($cellHeight * 0.25))
      $sampleY1 = [int][Math]::Ceiling($region.y + $marginY + (($row + 1) * $cellHeight) - ($cellHeight * 0.25))
      $sampleX0 = [Math]::Max(0, [Math]::Min($Width - 1, $sampleX0))
      $sampleX1 = [Math]::Max($sampleX0 + 1, [Math]::Min($Width, $sampleX1))
      $sampleY0 = [Math]::Max(0, [Math]::Min($Height - 1, $sampleY0))
      $sampleY1 = [Math]::Max($sampleY0 + 1, [Math]::Min($Height, $sampleY1))

      $sum = 0
      $samples = 0
      for ($y = $sampleY0; $y -lt $sampleY1; $y++) {
        $rowOffset = $y * $Width
        for ($x = $sampleX0; $x -lt $sampleX1; $x++) {
          $sum += $Frame[$rowOffset + $x]
          $samples++
        }
      }
      if ($samples -eq 0) {
        return $null
      }
      $average = $sum / [double]$samples
      if ($average -ge 128.0) {
        $bitIndex = ($row * 8) + $column
        $id = $id -bor (1 -shl $bitIndex)
      }
    }
  }

  if ($id -le 0) {
    return $null
  }
  return $id
}

function Copy-FrameForPerceptualComparison(
  [byte[]]$Frame,
  [int]$Width,
  [int]$Height,
  [bool]$ExcludeReceiverProbeMarkerRegion,
  [bool]$ExcludeSourceFrameMarkerRegion,
  [int]$SourceMarkerOffsetX,
  [int]$SourceMarkerOffsetY
) {
  $copy = New-Object byte[] $Frame.Length
  [Array]::Copy($Frame, $copy, $Frame.Length)
  if ($ExcludeReceiverProbeMarkerRegion) {
    $markerWidth = [Math]::Min($Width, [Math]::Max(1, [int][Math]::Ceiling($Width * 0.28)))
    $markerHeight = [Math]::Min($Height, [Math]::Max(1, [int][Math]::Ceiling($Height * 0.16)))
    $originY = [Math]::Max(0, $Height - $markerHeight)
    Clear-FrameRegion `
      -Frame $copy `
      -Width $Width `
      -Height $Height `
      -X 0 `
      -Y $originY `
      -RegionWidth $markerWidth `
      -RegionHeight $markerHeight
  }
  if ($ExcludeSourceFrameMarkerRegion) {
    $region = Get-SourceFrameMarkerRegion `
      -Width $Width `
      -Height $Height `
      -OffsetX $SourceMarkerOffsetX `
      -OffsetY $SourceMarkerOffsetY
    Clear-FrameRegion `
      -Frame $copy `
      -Width $Width `
      -Height $Height `
      -X $region.x `
      -Y $region.y `
      -RegionWidth $region.width `
      -RegionHeight $region.height
  }
  return $copy
}

function Get-Percentile([double[]]$Values, [double]$Percentile) {
  if ($Values.Count -eq 0) {
    return $null
  }
  $sorted = @($Values | Sort-Object)
  $index = [Math]::Floor(($sorted.Count - 1) * $Percentile)
  return [Math]::Round([double]$sorted[$index], 3)
}

function New-StaleRun(
  [int]$StartFrame,
  [int]$EndFrame,
  [int]$FrameCount,
  [double]$FramesPerSecond
) {
  $startSeconds = if ($FramesPerSecond -gt 0) {
    [Math]::Round(($StartFrame - 1) / $FramesPerSecond, 3)
  } else {
    0.0
  }
  $endSeconds = if ($FramesPerSecond -gt 0) {
    [Math]::Round(($EndFrame - 1) / $FramesPerSecond, 3)
  } else {
    0.0
  }
  $durationMs = if ($FramesPerSecond -gt 0) {
    [Math]::Round(($FrameCount / $FramesPerSecond) * 1000.0, 3)
  } else {
    0.0
  }

  return [ordered]@{
    startFrame = $StartFrame
    endFrame = $EndFrame
    frames = $FrameCount
    startSeconds = $startSeconds
    endSeconds = $endSeconds
    durationMs = $durationMs
  }
}

function Measure-VideoFrames(
  [string]$VideoPath,
  [string]$FfmpegExe,
  [double]$FramesPerSecond,
  [int]$Width,
  [int]$Height,
  [double]$UniqueThreshold,
  [double]$LocalUniqueThreshold,
  [int]$BlockWidth,
  [int]$BlockHeight,
  [double]$LowThreshold,
  [int]$FrameLimit,
  [bool]$ExcludeMarkerRegion,
  [bool]$ExcludeSourceMarkerRegion,
  [bool]$DecodeSourceMarker,
  [int]$SourceMarkerOffsetX,
  [int]$SourceMarkerOffsetY
) {
  if ($FramesPerSecond -le 0) {
    throw 'SampleFps must be greater than zero.'
  }
  if ($Width -le 0 -or $Height -le 0) {
    throw 'ScaleWidth and ScaleHeight must be greater than zero.'
  }

  $frameSize = $Width * $Height
  $vf = 'fps=' + $FramesPerSecond.ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
  ) + ',scale=' + $Width + ':' + $Height + ':flags=area,format=gray'

  $arguments = @(
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    $VideoPath,
    '-vf',
    $vf,
    '-an',
    '-sn'
  )
  if ($FrameLimit -gt 0) {
    $arguments += @('-frames:v', "$FrameLimit")
  }
  $arguments += @(
    '-f',
    'rawvideo',
    '-vcodec',
    'rawvideo',
    '-'
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfmpegExe
  $startInfo.Arguments = ConvertTo-ArgumentString $arguments
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()

  $stream = $process.StandardOutput.BaseStream
  $buffer = New-Object byte[] $frameSize
  $previous = $null
  $previousExactHash = ''
  $sampleFrames = 0
  $uniqueFrames = 0
  $lowChangeFrames = 0
  $exactUniqueFrames = 0
  $exactDuplicateFrames = 0
  $currentExactStaleFrames = 0
  $currentExactStaleRunStartFrame = 0
  $longestExactStaleFrames = 0
  $currentStaleFrames = 0
  $currentStaleRunStartFrame = 0
  $longestStaleFrames = 0
  $diffs = New-Object 'System.Collections.Generic.List[double]'
  $localDiffs = New-Object 'System.Collections.Generic.List[double]'
  $staleRuns = New-Object 'System.Collections.Generic.List[object]'
  $exactStaleRuns = New-Object 'System.Collections.Generic.List[object]'
  $exactFrameHashes = New-Object 'System.Collections.Generic.HashSet[string]'
  $sourceMarkerDecodedFrames = 0
  $sourceMarkerMissingFrames = 0
  $sourceMarkerUniqueFrames = 0
  $sourceMarkerDuplicateFrames = 0
  $sourceMarkerCurrentStaleFrames = 0
  $sourceMarkerCurrentStaleRunStartFrame = 0
  $sourceMarkerLongestStaleFrames = 0
  $sourceMarkerPreviousId = $null
  $sourceMarkerIds = New-Object 'System.Collections.Generic.HashSet[int]'
  $sourceMarkerStaleRuns = New-Object 'System.Collections.Generic.List[object]'

  while ($true) {
    $offset = 0
    while ($offset -lt $frameSize) {
      $read = $stream.Read($buffer, $offset, $frameSize - $offset)
      if ($read -le 0) {
        break
      }
      $offset += $read
    }
    if ($offset -eq 0) {
      break
    }
    if ($offset -ne $frameSize) {
      break
    }

    $frame = New-Object byte[] $frameSize
    [Array]::Copy($buffer, $frame, $frameSize)
    $comparisonFrame = Copy-FrameForPerceptualComparison `
      -Frame $frame `
      -Width $Width `
      -Height $Height `
      -ExcludeReceiverProbeMarkerRegion $ExcludeMarkerRegion `
      -ExcludeSourceFrameMarkerRegion $ExcludeSourceMarkerRegion `
      -SourceMarkerOffsetX $SourceMarkerOffsetX `
      -SourceMarkerOffsetY $SourceMarkerOffsetY
    $sampleFrames++
    if ($DecodeSourceMarker) {
      $sourceMarkerId = Get-SourceFrameMarkerId `
        -Frame $frame `
        -Width $Width `
        -Height $Height `
        -OffsetX $SourceMarkerOffsetX `
        -OffsetY $SourceMarkerOffsetY
      if ($null -eq $sourceMarkerId) {
        $sourceMarkerMissingFrames++
        if ($sourceMarkerCurrentStaleFrames -gt 0) {
          [void]$sourceMarkerStaleRuns.Add((New-StaleRun `
            -StartFrame $sourceMarkerCurrentStaleRunStartFrame `
            -EndFrame ($sampleFrames - 1) `
            -FrameCount $sourceMarkerCurrentStaleFrames `
            -FramesPerSecond $FramesPerSecond))
          $sourceMarkerCurrentStaleFrames = 0
          $sourceMarkerCurrentStaleRunStartFrame = 0
        }
      } else {
        $sourceMarkerDecodedFrames++
        [void]$sourceMarkerIds.Add([int]$sourceMarkerId)
        if ($null -eq $sourceMarkerPreviousId -or
            [int]$sourceMarkerId -ne [int]$sourceMarkerPreviousId) {
          $sourceMarkerUniqueFrames++
          if ($sourceMarkerCurrentStaleFrames -gt 0) {
            [void]$sourceMarkerStaleRuns.Add((New-StaleRun `
              -StartFrame $sourceMarkerCurrentStaleRunStartFrame `
              -EndFrame ($sampleFrames - 1) `
              -FrameCount $sourceMarkerCurrentStaleFrames `
              -FramesPerSecond $FramesPerSecond))
          }
          $sourceMarkerCurrentStaleFrames = 0
          $sourceMarkerCurrentStaleRunStartFrame = 0
        } else {
          $sourceMarkerDuplicateFrames++
          if ($sourceMarkerCurrentStaleFrames -eq 0) {
            $sourceMarkerCurrentStaleRunStartFrame = $sampleFrames
          }
          $sourceMarkerCurrentStaleFrames++
          if ($sourceMarkerCurrentStaleFrames -gt $sourceMarkerLongestStaleFrames) {
            $sourceMarkerLongestStaleFrames = $sourceMarkerCurrentStaleFrames
          }
        }
        $sourceMarkerPreviousId = [int]$sourceMarkerId
      }
    }
    $frameHash = Get-FrameHash $frame
    [void]$exactFrameHashes.Add($frameHash)

    if ($null -eq $previous) {
      $uniqueFrames = 1
      $exactUniqueFrames = 1
      $currentStaleFrames = 0
      $currentExactStaleFrames = 0
    } else {
      if ($frameHash -ne $previousExactHash) {
        $exactUniqueFrames++
        if ($currentExactStaleFrames -gt 0) {
          [void]$exactStaleRuns.Add((New-StaleRun `
            -StartFrame $currentExactStaleRunStartFrame `
            -EndFrame ($sampleFrames - 1) `
            -FrameCount $currentExactStaleFrames `
            -FramesPerSecond $FramesPerSecond))
        }
        $currentExactStaleFrames = 0
        $currentExactStaleRunStartFrame = 0
      } else {
        $exactDuplicateFrames++
        if ($currentExactStaleFrames -eq 0) {
          $currentExactStaleRunStartFrame = $sampleFrames
        }
        $currentExactStaleFrames++
        if ($currentExactStaleFrames -gt $longestExactStaleFrames) {
          $longestExactStaleFrames = $currentExactStaleFrames
        }
      }

      $diff = Get-MeanAbsDiff $previous $comparisonFrame
      $localDiff = Get-MaxBlockMeanAbsDiff `
        -Previous $previous `
        -Current $comparisonFrame `
        -Width $Width `
        -Height $Height `
        -BlockWidth $BlockWidth `
        -BlockHeight $BlockHeight
      [void]$diffs.Add($diff)
      [void]$localDiffs.Add($localDiff)
      if ($diff -le $LowThreshold -and $localDiff -lt $LocalUniqueThreshold) {
        $lowChangeFrames++
      }
      if ($diff -ge $UniqueThreshold -or
          $localDiff -ge $LocalUniqueThreshold) {
        $uniqueFrames++
        if ($currentStaleFrames -gt 0) {
          [void]$staleRuns.Add((New-StaleRun `
            -StartFrame $currentStaleRunStartFrame `
            -EndFrame ($sampleFrames - 1) `
            -FrameCount $currentStaleFrames `
            -FramesPerSecond $FramesPerSecond))
        }
        $currentStaleFrames = 0
        $currentStaleRunStartFrame = 0
      } else {
        if ($currentStaleFrames -eq 0) {
          $currentStaleRunStartFrame = $sampleFrames
        }
        $currentStaleFrames++
        if ($currentStaleFrames -gt $longestStaleFrames) {
          $longestStaleFrames = $currentStaleFrames
        }
      }
    }
    $previous = $comparisonFrame
    $previousExactHash = $frameHash
  }

  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "ffmpeg exited with code $($process.ExitCode): $stderr"
  }
  if ($currentStaleFrames -gt 0) {
    [void]$staleRuns.Add((New-StaleRun `
      -StartFrame $currentStaleRunStartFrame `
      -EndFrame $sampleFrames `
      -FrameCount $currentStaleFrames `
      -FramesPerSecond $FramesPerSecond))
  }
  if ($currentExactStaleFrames -gt 0) {
    [void]$exactStaleRuns.Add((New-StaleRun `
      -StartFrame $currentExactStaleRunStartFrame `
      -EndFrame $sampleFrames `
      -FrameCount $currentExactStaleFrames `
      -FramesPerSecond $FramesPerSecond))
  }
  if ($sourceMarkerCurrentStaleFrames -gt 0) {
    [void]$sourceMarkerStaleRuns.Add((New-StaleRun `
      -StartFrame $sourceMarkerCurrentStaleRunStartFrame `
      -EndFrame $sampleFrames `
      -FrameCount $sourceMarkerCurrentStaleFrames `
      -FramesPerSecond $FramesPerSecond))
  }

  $durationSeconds = if ($sampleFrames -gt 0) {
    $sampleFrames / $FramesPerSecond
  } else {
    0.0
  }
  $uniqueFps = if ($durationSeconds -gt 0) {
    [Math]::Round($uniqueFrames / $durationSeconds, 3)
  } else {
    0.0
  }
  $exactUniqueFps = if ($durationSeconds -gt 0) {
    [Math]::Round($exactUniqueFrames / $durationSeconds, 3)
  } else {
    0.0
  }
  $sourceMarkerUniqueFps = if ($durationSeconds -gt 0) {
    [Math]::Round($sourceMarkerUniqueFrames / $durationSeconds, 3)
  } else {
    0.0
  }
  $longestStaleMs = [Math]::Round(
    ($longestStaleFrames / $FramesPerSecond) * 1000.0,
    3
  )
  $longestExactStaleMs = [Math]::Round(
    ($longestExactStaleFrames / $FramesPerSecond) * 1000.0,
    3
  )
  $sourceMarkerLongestStaleMs = [Math]::Round(
    ($sourceMarkerLongestStaleFrames / $FramesPerSecond) * 1000.0,
    3
  )

  $diffArray = [double[]]$diffs.ToArray()
  $localDiffArray = [double[]]$localDiffs.ToArray()
  $averageDiff = if ($diffArray.Count -gt 0) {
    [Math]::Round((($diffArray | Measure-Object -Average).Average), 3)
  } else {
    0.0
  }
  $maxDiff = if ($diffArray.Count -gt 0) {
    [Math]::Round((($diffArray | Measure-Object -Maximum).Maximum), 3)
  } else {
    0.0
  }
  $averageLocalDiff = if ($localDiffArray.Count -gt 0) {
    [Math]::Round((($localDiffArray | Measure-Object -Average).Average), 3)
  } else {
    0.0
  }
  $maxLocalDiff = if ($localDiffArray.Count -gt 0) {
    [Math]::Round((($localDiffArray | Measure-Object -Maximum).Maximum), 3)
  } else {
    0.0
  }
  $staleRunArray = @(
    $staleRuns.ToArray() |
      Sort-Object -Property @{ Expression = { $_.frames }; Descending = $true },
                            @{ Expression = { $_.startFrame }; Descending = $false }
  )
  $topStaleRuns = @($staleRunArray | Select-Object -First 5)
  $exactStaleRunArray = @(
    $exactStaleRuns.ToArray() |
      Sort-Object -Property @{ Expression = { $_.frames }; Descending = $true },
                            @{ Expression = { $_.startFrame }; Descending = $false }
  )
  $topExactStaleRuns = @($exactStaleRunArray | Select-Object -First 5)
  $sourceMarkerStaleRunArray = @(
    $sourceMarkerStaleRuns.ToArray() |
      Sort-Object -Property @{ Expression = { $_.frames }; Descending = $true },
                            @{ Expression = { $_.startFrame }; Descending = $false }
  )
  $topSourceMarkerStaleRuns = @($sourceMarkerStaleRunArray | Select-Object -First 5)
  $staleFramePercent = if ($sampleFrames -gt 0) {
    [Math]::Round(($lowChangeFrames / [double]$sampleFrames) * 100.0, 3)
  } else {
    0.0
  }

  return [ordered]@{
    sampleFrames = $sampleFrames
    durationSeconds = [Math]::Round($durationSeconds, 3)
    uniqueFrames = $uniqueFrames
    uniqueFps = $uniqueFps
    exactFrameHashAlgorithm = "sha256-gray${Width}x${Height}"
    exactDistinctFrameHashes = $exactFrameHashes.Count
    exactUniqueFrames = $exactUniqueFrames
    exactUniqueFps = $exactUniqueFps
    exactDuplicateFrames = $exactDuplicateFrames
    exactLongestStaleMs = $longestExactStaleMs
    exactLongestStaleFrames = $longestExactStaleFrames
    exactStaleRunCount = $exactStaleRuns.Count
    topExactStaleRuns = $topExactStaleRuns
    sourceFrameMarker = [ordered]@{
      decoded = $DecodeSourceMarker
      decodedFrames = $sourceMarkerDecodedFrames
      missingFrames = $sourceMarkerMissingFrames
      distinctFrameIds = $sourceMarkerIds.Count
      uniqueFrames = $sourceMarkerUniqueFrames
      uniqueFps = $sourceMarkerUniqueFps
      duplicateFrames = $sourceMarkerDuplicateFrames
      longestStaleMs = $sourceMarkerLongestStaleMs
      longestStaleFrames = $sourceMarkerLongestStaleFrames
      staleRunCount = $sourceMarkerStaleRuns.Count
      topStaleRuns = $topSourceMarkerStaleRuns
      regionExcluded = $ExcludeSourceMarkerRegion
      region = Get-SourceFrameMarkerRegion `
        -Width $Width `
        -Height $Height `
        -OffsetX $SourceMarkerOffsetX `
        -OffsetY $SourceMarkerOffsetY
    }
    longestStaleMs = $longestStaleMs
    longestStaleFrames = $longestStaleFrames
    lowChangeFrames = $lowChangeFrames
    lowChangeFramePercent = $staleFramePercent
    staleRunCount = $staleRuns.Count
    topStaleRuns = $topStaleRuns
    averageFrameDifference = $averageDiff
    p95FrameDifference = Get-Percentile $diffArray 0.95
    maxFrameDifference = $maxDiff
    averageLocalBlockDifference = $averageLocalDiff
    p95LocalBlockDifference = Get-Percentile $localDiffArray 0.95
    maxLocalBlockDifference = $maxLocalDiff
    receiverProbeMarkerRegionExcluded = $ExcludeMarkerRegion
    sourceFrameMarkerRegionExcluded = $ExcludeSourceMarkerRegion
  }
}

$repoRoot = Resolve-RepoRoot
Import-StreamLabLocalEnv -RepoRoot $repoRoot
$workspaceRoot = Resolve-StreamLabWorkspaceRoot -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Resolve-StreamLabOutputRoot `
    -RepoRoot $repoRoot `
    -WorkspaceRoot $workspaceRoot
}
New-SafeDirectory $OutputRoot

$benchmarkPath = ''
$benchmarkReport = $null
if (-not [string]::IsNullOrWhiteSpace($BenchmarkReportJson)) {
  $benchmarkPath = (Resolve-Path -LiteralPath $BenchmarkReportJson).Path
  $benchmarkReport = Read-JsonFile $benchmarkPath
  if ([string]::IsNullOrWhiteSpace($InputVideo)) {
    $proofPath = Get-NestedJsonProperty `
      -Object $benchmarkReport `
      -Names @('publicationHandoff', 'encoderProofOutputPath')
    if ([string]::IsNullOrWhiteSpace($proofPath)) {
      throw 'BenchmarkReportJson does not expose publicationHandoff.encoderProofOutputPath.'
    }
    $InputVideo = [string]$proofPath
  }
  if ([string]::IsNullOrWhiteSpace($SampleMode)) {
    $synthetic = Get-JsonProperty $benchmarkReport 'syntheticTarget'
    if ($null -ne $synthetic) {
      $SampleMode = 'synthetic-target-mf-proof'
    }
  }
}

if ([string]::IsNullOrWhiteSpace($InputVideo)) {
  throw 'Provide -InputVideo or -BenchmarkReportJson.'
}
$inputPath = (Resolve-Path -LiteralPath $InputVideo).Path
if ([string]::IsNullOrWhiteSpace($SampleMode)) {
  $SampleMode = 'receiver-recording'
}
$ffmpegExe = Resolve-Ffmpeg $FfmpegPath

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutputDirectory = Join-Path $OutputRoot "visual-freshness-$stamp"
}
New-SafeDirectory $OutputDirectory

$metrics = Measure-VideoFrames `
  -VideoPath $inputPath `
  -FfmpegExe $ffmpegExe `
  -FramesPerSecond $SampleFps `
  -Width $ScaleWidth `
  -Height $ScaleHeight `
  -UniqueThreshold $UniqueFrameThreshold `
  -LocalUniqueThreshold $LocalUniqueFrameThreshold `
  -BlockWidth $LocalBlockWidth `
  -BlockHeight $LocalBlockHeight `
  -LowThreshold $LowChangeThreshold `
  -FrameLimit $MaxFrames `
  -ExcludeMarkerRegion ([bool]$ExcludeReceiverProbeMarkerRegion) `
  -ExcludeSourceMarkerRegion ([bool]$ExcludeSourceFrameMarkerRegion) `
  -DecodeSourceMarker ([bool]$DecodeSourceFrameMarker) `
  -SourceMarkerOffsetX $SourceFrameMarkerOffsetX `
  -SourceMarkerOffsetY $SourceFrameMarkerOffsetY

$status = if ($metrics.sampleFrames -lt 2) {
  'insufficient_visual_freshness_frames'
} elseif ($MinUniqueFps -gt 0 -and $metrics.uniqueFps -lt $MinUniqueFps) {
  'failed_visual_freshness_min_fps'
} else {
  'completed'
}

$marker = 'game_capture_output_freshness stats ' +
  "sampleMode=$SampleMode " +
  "sampleFrames=$($metrics.sampleFrames) " +
  "uniqueFrames=$($metrics.uniqueFrames) " +
  ('uniqueFps=' + $metrics.uniqueFps.ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
  ) + ' ') +
  "exactUniqueFrames=$($metrics.exactUniqueFrames) " +
  ('exactUniqueFps=' + $metrics.exactUniqueFps.ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
  ) + ' ') +
  ('longestStaleMs=' + $metrics.longestStaleMs.ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
  ) + ' ') +
  ('exactLongestStaleMs=' + $metrics.exactLongestStaleMs.ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
  ) + ' ') +
  "longestStaleFrames=$($metrics.longestStaleFrames) " +
  "exactLongestStaleFrames=$($metrics.exactLongestStaleFrames) " +
  "lowChangeFrames=$($metrics.lowChangeFrames) " +
  'artifactSet=true'

$jsonOut = Join-Path $OutputDirectory 'visual-freshness.json'
$mdOut = Join-Path $OutputDirectory 'visual-freshness.md'
$markerOut = Join-Path $OutputDirectory 'visual-freshness-marker.txt'
$inputHash = ConvertTo-ShortHash $inputPath

$report = [ordered]@{
  schema = 'intergalactic.visualFreshnessMeasurement.v1'
  status = $status
  sampleMode = $SampleMode
  generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  input = [ordered]@{
    videoPath = $inputPath
    videoPathHash = "sha256-$inputHash"
    benchmarkReportJson = $benchmarkPath
  }
  config = [ordered]@{
    sampleFps = $SampleFps
    scaleWidth = $ScaleWidth
    scaleHeight = $ScaleHeight
    uniqueFrameThreshold = $UniqueFrameThreshold
    localUniqueFrameThreshold = $LocalUniqueFrameThreshold
    localBlockWidth = $LocalBlockWidth
    localBlockHeight = $LocalBlockHeight
    lowChangeThreshold = $LowChangeThreshold
    maxFrames = $MaxFrames
    minUniqueFps = $MinUniqueFps
    excludeReceiverProbeMarkerRegion = [bool]$ExcludeReceiverProbeMarkerRegion
    excludeSourceFrameMarkerRegion = [bool]$ExcludeSourceFrameMarkerRegion
    decodeSourceFrameMarker = [bool]$DecodeSourceFrameMarker
    sourceFrameMarkerOffsetX = $SourceFrameMarkerOffsetX
    sourceFrameMarkerOffsetY = $SourceFrameMarkerOffsetY
  }
  metrics = $metrics
  marker = $marker
  coverage = [ordered]@{
    receiverToolRecording = 'available'
    visualFreshnessCadence = if ($metrics.sampleFrames -ge 2) {
      'available'
    } else {
      'missing'
    }
    streamTestMarker = 'available'
    sourceFrameMarker = if ($DecodeSourceFrameMarker) {
      if ($metrics.sourceFrameMarker.decodedFrames -gt 0) {
        'available'
      } else {
        'missing'
      }
    } else {
      'not_requested'
    }
  }
  output = [ordered]@{
    json = $jsonOut
    markdown = $mdOut
    marker = $markerOut
  }
}

$report | ConvertTo-Json -Depth 20 |
  Set-Content -LiteralPath $jsonOut -Encoding UTF8
$marker | Set-Content -LiteralPath $markerOut -Encoding UTF8

@(
  '# Visual Freshness Measurement'
  ''
  '## Summary'
  ''
  "- Status: $status"
  "- Sample mode: $SampleMode"
  "- Input video hash: sha256-$inputHash"
  "- Sampled frames/duration: $($metrics.sampleFrames) / $($metrics.durationSeconds)s"
  "- Unique frames/unique FPS: $($metrics.uniqueFrames) / $($metrics.uniqueFps)"
  "- Exact changed frames/exact FPS: $($metrics.exactUniqueFrames) / $($metrics.exactUniqueFps)"
  "- Exact distinct frame hashes: $($metrics.exactDistinctFrameHashes)"
  "- Longest stale run: $($metrics.longestStaleFrames) frames / $($metrics.longestStaleMs) ms"
  "- Exact duplicate stale run: $($metrics.exactLongestStaleFrames) frames / $($metrics.exactLongestStaleMs) ms"
  "- Source frame marker: decoded=$($metrics.sourceFrameMarker.decoded) frames=$($metrics.sourceFrameMarker.decodedFrames) uniqueFPS=$($metrics.sourceFrameMarker.uniqueFps) longestStale=$($metrics.sourceFrameMarker.longestStaleMs) ms missing=$($metrics.sourceFrameMarker.missingFrames)"
  "- Low-change frames: $($metrics.lowChangeFrames) / $($metrics.lowChangeFramePercent)%"
  "- Stale runs: $($metrics.staleRunCount)"
  "- Exact duplicate stale runs: $($metrics.exactStaleRunCount)"
  "- Frame-difference avg/p95/max: $($metrics.averageFrameDifference) / $($metrics.p95FrameDifference) / $($metrics.maxFrameDifference)"
  "- Local block-difference avg/p95/max: $($metrics.averageLocalBlockDifference) / $($metrics.p95LocalBlockDifference) / $($metrics.maxLocalBlockDifference)"
  ''
  '## Top Stale Runs'
  ''
  if ($metrics.topStaleRuns.Count -eq 0) {
    '- none'
  } else {
    foreach ($run in $metrics.topStaleRuns) {
      "- frames $($run.startFrame)-$($run.endFrame), $($run.frames) frames / $($run.durationMs) ms, starts at $($run.startSeconds)s"
    }
  }
  ''
  '## Top Exact Duplicate Runs'
  ''
  if ($metrics.topExactStaleRuns.Count -eq 0) {
    '- none'
  } else {
    foreach ($run in $metrics.topExactStaleRuns) {
      "- frames $($run.startFrame)-$($run.endFrame), $($run.frames) frames / $($run.durationMs) ms, starts at $($run.startSeconds)s"
    }
  }
  ''
  '## Marker'
  ''
  '```text'
  $marker
  '```'
  ''
  '## Method'
  ''
  "Frames were sampled with ffmpeg at ${SampleFps} FPS, downscaled to ${ScaleWidth}x${ScaleHeight} grayscale, and compared by mean absolute pixel difference plus the maximum ${LocalBlockWidth}x${LocalBlockHeight} local block difference. A frame is counted as unique when global difference is at least $UniqueFrameThreshold or local block difference is at least $LocalUniqueFrameThreshold. Exact changed frames use $($metrics.exactFrameHashAlgorithm) over the same sampled frames and only aggregate hash counts are persisted. Low-change frames must be below both the low-change and local thresholds. When receiver probe marker exclusion is enabled, the bottom-left marker region is masked only for perceptual difference scoring; when source-frame marker exclusion is enabled, the top-left encoded source marker region is also masked for perceptual difference scoring. Exact hashes still see the sampled frame."
  ''
  '## Output Files'
  ''
  "- JSON: $jsonOut"
  "- Markdown: $mdOut"
  "- Marker: $markerOut"
) | Set-Content -LiteralPath $mdOut -Encoding UTF8

if ($AsJson) {
  $report | ConvertTo-Json -Depth 20
} else {
  Write-Host "Visual freshness report: $mdOut"
  Write-Host "Visual freshness status: $status"
  Write-Host "Visual freshness marker: $marker"
}

if ($FailBelowMinUniqueFps -and $status -eq 'failed_visual_freshness_min_fps') {
  exit 2
}
if ($status -eq 'insufficient_visual_freshness_frames') {
  exit 3
}
