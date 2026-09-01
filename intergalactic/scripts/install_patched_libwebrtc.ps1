param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspaceRoot,

  [Parameter(Mandatory = $true)]
  [string]$AppDir,

  [ValidateSet("auto", "require", "off")]
  [string]$Mode = "auto",

  [string]$ZipPath = ""
)

$ErrorActionPreference = "Stop"
$script:InstallerScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  [System.IO.Path]::GetDirectoryName($PSCommandPath)
} else {
  $PSScriptRoot
}
$script:InstallerAppRoot = Split-Path -Parent $script:InstallerScriptRoot

function Resolve-LocalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$BasePath = $script:InstallerAppRoot
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-Sha256Hash {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
  }

  $resolved = Resolve-LocalPath $Path
  $stream = [System.IO.File]::OpenRead($resolved)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $bytes = $sha.ComputeHash($stream)
      return ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToUpperInvariant()
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Test-MatrixDevRootCandidate {
  param([Parameter(Mandatory = $true)][string]$Candidate)

  return (
    (Test-Path -LiteralPath (Join-Path $Candidate "build.bat")) -and
    (Test-Path -LiteralPath (Join-Path $Candidate "intergalactic-app")) -and
    (Test-Path -LiteralPath (Join-Path $Candidate "docs\agent-control"))
  )
}

function Get-MatrixDevRoot {
  param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

  $workspace = Resolve-LocalPath $WorkspaceRoot
  $candidates = New-Object System.Collections.Generic.List[string]
  $current = $workspace
  while (-not [string]::IsNullOrWhiteSpace($current)) {
    $candidates.Add($current)
    $parent = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $current)) {
      break
    }
    $current = $parent
  }

  foreach ($candidate in $candidates) {
    if (Test-MatrixDevRootCandidate -Candidate $candidate) {
      return $candidate
    }
  }

  $driveRoot = [System.IO.Path]::GetPathRoot($workspace).TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
  )
  $workspaceTrimmed = $workspace.TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
  )

  if ($workspaceTrimmed -eq $driveRoot) {
    throw "Could not identify workspace root markers from shallow workspace path: $workspace"
  }

  Write-Warning "Could not identify workspace root markers from $workspace; using WorkspaceRoot for artifact fallback search."
  return $workspace
}

function Get-PackageConfigPath {
  param(
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$AppDir
  )

  $workspace = Resolve-LocalPath $WorkspaceRoot
  $app = Resolve-LocalPath $AppDir
  $candidates = @(
    (Join-Path $app ".dart_tool\package_config.json"),
    (Join-Path $script:InstallerAppRoot ".dart_tool\package_config.json"),
    (Join-Path $workspace ".dart_tool\package_config.json")
  )

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-LocalPath $candidate)
    }
  }

  throw "Could not find package_config.json. Run flutter pub get before installing patched libwebrtc."
}

function Convert-PackageRootUriToPath {
  param(
    [Parameter(Mandatory = $true)][string]$PackageConfigPath,
    [Parameter(Mandatory = $true)][string]$RootUri
  )

  if ($RootUri -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
    return [System.IO.Path]::GetFullPath(([Uri]$RootUri).LocalPath)
  }

  $baseDir = Split-Path -Parent $PackageConfigPath
  return [System.IO.Path]::GetFullPath((Join-Path $baseDir $RootUri))
}

function Get-FlutterWebrtcPackageRoot {
  param(
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$AppDir
  )

  $packageConfigPath = Get-PackageConfigPath -WorkspaceRoot $WorkspaceRoot -AppDir $AppDir
  $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
  $flutterWebrtc = $packageConfig.packages |
      Where-Object { $_.name -eq "flutter_webrtc" } |
      Select-Object -First 1

  if ($null -eq $flutterWebrtc) {
    throw "flutter_webrtc was not found in $packageConfigPath."
  }

  $packageRoot = Convert-PackageRootUriToPath `
      -PackageConfigPath $packageConfigPath `
      -RootUri $flutterWebrtc.rootUri

  if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "flutter_webrtc package root does not exist: $packageRoot"
  }

  return $packageRoot
}

function Get-DartPackageRoot {
  param(
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$AppDir,
    [Parameter(Mandatory = $true)][string]$PackageName
  )

  $packageConfigPath = Get-PackageConfigPath -WorkspaceRoot $WorkspaceRoot -AppDir $AppDir
  $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
  $package = $packageConfig.packages |
      Where-Object { $_.name -eq $PackageName } |
      Select-Object -First 1

  if ($null -eq $package) {
    throw "$PackageName was not found in $packageConfigPath."
  }

  $packageRoot = Convert-PackageRootUriToPath `
      -PackageConfigPath $packageConfigPath `
      -RootUri $package.rootUri

  if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "$PackageName package root does not exist: $packageRoot"
  }

  return $packageRoot
}

function Test-LibwebrtcZip {
  param([Parameter(Mandatory = $true)][string]$Candidate)

  Add-Type -AssemblyName System.IO.Compression.FileSystem

  $zip = [System.IO.Compression.ZipFile]::OpenRead($Candidate)
  try {
    $entries = @{}
    foreach ($entry in $zip.Entries) {
      $entries[$entry.FullName.Replace("\", "/")] = $true
    }

    $required = @(
      "libwebrtc/include/libwebrtc.h",
      "libwebrtc/include/rtc_desktop_capturer.h",
      "libwebrtc/include/rtc_intergalactic_audio_ducking.h",
      "libwebrtc/lib/win64/libwebrtc.dll",
      "libwebrtc/lib/win64/libwebrtc.dll.lib"
    )

    foreach ($path in $required) {
      if (-not $entries.ContainsKey($path)) {
        throw "Patched libwebrtc zip is missing required entry: $path"
      }
    }

    $capturerHeader = $zip.GetEntry("libwebrtc/include/rtc_desktop_capturer.h")
    if ($null -eq $capturerHeader) {
      throw "Patched libwebrtc zip is missing desktop capturer header"
    }
    $reader = New-Object System.IO.StreamReader($capturerHeader.Open())
    try {
      $capturerHeaderText = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }
    if (-not $capturerHeaderText.Contains("StartWithMaxFrameSize")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic desktop capture scaler API"
    }
    if (-not $capturerHeaderText.Contains("SetWindowsCaptureBackendMode")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic Windows capture backend override API"
    }
    if (-not $capturerHeaderText.Contains("SetLatestFramePacingEnabled")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic latest-frame pacing API"
    }
    if (-not $capturerHeaderText.Contains("SetWindowsCaptureDirtyRegionMode")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic Windows capture dirty-region diagnostic API"
    }
    if (-not $capturerHeaderText.Contains("SetWindowsWindowGdiCaptureMode")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic Windows window-GDI capture method diagnostic API"
    }

    $videoDeviceHeader = $zip.GetEntry("libwebrtc/include/rtc_video_device.h")
    if ($null -eq $videoDeviceHeader) {
      throw "Patched libwebrtc zip is missing video device header"
    }
    $reader = New-Object System.IO.StreamReader($videoDeviceHeader.Open())
    try {
      $videoDeviceHeaderText = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }
    if (-not $videoDeviceHeaderText.Contains("CreateGameCapture")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic debug game-capture source API"
    }

    $videoFrameHeader = $zip.GetEntry("libwebrtc/include/rtc_video_frame.h")
    if ($null -eq $videoFrameHeader) {
      throw "Patched libwebrtc zip is missing video frame header"
    }
    $reader = New-Object System.IO.StreamReader($videoFrameHeader.Open())
    try {
      $videoFrameHeaderText = $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }
    if (-not $videoFrameHeaderText.Contains("virtual uint16_t id() const = 0")) {
      throw "Patched libwebrtc zip does not include the Inter Galactic receiver source frame id API"
    }
  } finally {
    $zip.Dispose()
  }
}

function Assert-LibwebrtcManifest {
  # Verifies a libwebrtc zip against its sidecar provenance manifest and returns
  # the manifest (or $null when there is no sidecar).
  #
  # Trust boundary: the manifest sits next to the zip, so this detects drift
  # between the two - a stale manifest, or a zip rebuilt without regenerating
  # it. It does NOT authenticate either file: an attacker who can replace the
  # zip can replace the manifest with it. It is an integrity check on a local
  # build input, not a supply-chain signature.
  #
  # Missing sidecar  -> reported, non-fatal (older artifacts still install).
  # Present sidecar  -> must carry a sha256 and it must match, else fatal. A
  #                     manifest that asserts provenance without binding it to
  #                     the bytes is worse than none, because it invites trust
  #                     it has not earned.
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [string]$KnownSha256 = ""
  )

  $manifestPath = "$ZipPath.manifest.json"
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return $null
  }

  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  } catch {
    throw ("Patched libwebrtc provenance manifest is unreadable: $manifestPath`n" +
           "  $($_.Exception.Message)`n" +
           "Fix or remove the manifest.")
  }

  $recorded = $manifest.artifact.sha256
  if ([string]::IsNullOrWhiteSpace($recorded)) {
    throw ("Patched libwebrtc provenance manifest has no artifact.sha256: $manifestPath`n" +
           "It claims provenance without binding it to the archive bytes. " +
           "Regenerate the manifest.")
  }

  $actual = $KnownSha256
  if ([string]::IsNullOrWhiteSpace($actual)) {
    $actual = Get-Sha256Hash -Path $ZipPath
  }

  if ($actual -ne $recorded) {
    throw ("Patched libwebrtc zip does not match its provenance manifest.`n" +
           "  zip:      $ZipPath`n" +
           "  actual:   $actual`n" +
           "  manifest: $recorded`n" +
           "Rebuild the zip or regenerate $manifestPath.")
  }

  return $manifest
}

function Show-LibwebrtcProvenance {
  # Reports which sources produced this libwebrtc.dll. The structural checks in
  # Test-LibwebrtcZip prove the archive has the right APIs; this proves which
  # commits they came from.
  param([Parameter(Mandatory = $true)][string]$ZipPath)

  $manifest = Assert-LibwebrtcManifest -ZipPath $ZipPath
  if ($null -eq $manifest) {
    Write-Host "  libwebrtc provenance: no manifest sidecar; artifact is untraceable to source."
    Write-Host "    Expected: $ZipPath.manifest.json"
    return
  }

  $wrapper = $manifest.provenance.libwebrtcWrapper
  $core = $manifest.provenance.webrtcCore
  Write-Host "  libwebrtc provenance:"
  Write-Host "    wrapper:  $($wrapper.branch) @ $($wrapper.commit)"
  Write-Host "    core:     $($core.branch) @ $($core.commit)"
  Write-Host "    upstream: $($core.upstreamBranch) @ $($core.upstreamSyncedRevision)"
}

function Find-PatchedZip {
  param(
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [string]$ZipPath
  )

  $matrixDevRoot = Get-MatrixDevRoot -WorkspaceRoot $WorkspaceRoot
  $candidates = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($ZipPath)) {
    $candidates.Add($ZipPath)
  }

  if (-not [string]::IsNullOrWhiteSpace($env:INTERGALACTIC_LIBWEBRTC_ZIP)) {
    $candidates.Add($env:INTERGALACTIC_LIBWEBRTC_ZIP)
  }

  $candidates.Add((Join-Path $matrixDevRoot "artifacts\libwebrtc\windows-hardware-h264\libwebrtc.zip"))
  $candidates.Add((Join-Path $matrixDevRoot "patched-libwebrtc\libwebrtc.zip"))
  $candidates.Add((Join-Path $matrixDevRoot "forks\libwebrtc\artifacts\libwebrtc.zip"))
  $candidates.Add((Join-Path $WorkspaceRoot "artifacts\libwebrtc\windows-hardware-h264\libwebrtc.zip"))

  $script:PatchedZipSearchPaths = @()
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }

    $resolved = Resolve-LocalPath $candidate
    $script:PatchedZipSearchPaths += $resolved
    if (Test-Path -LiteralPath $resolved) {
      Test-LibwebrtcZip -Candidate $resolved
      Show-LibwebrtcProvenance -ZipPath $resolved
      return $resolved
    }
  }

  return $null
}

function Assert-PathInside {
  param(
    [Parameter(Mandatory = $true)][string]$Parent,
    [Parameter(Mandatory = $true)][string]$Child
  )

  $parentFull = Resolve-LocalPath $Parent
  $childFull = Resolve-LocalPath $Child
  $comparison = [System.StringComparison]::OrdinalIgnoreCase
  $parentPrefix = $parentFull.TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar

  if (($childFull -ne $parentFull) -and
      (-not $childFull.StartsWith($parentPrefix, $comparison))) {
    throw "Refusing to modify path outside package root: $childFull"
  }
}

function Update-SourceText {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Replacement,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $updated = [System.Text.RegularExpressions.Regex]::Replace(
    $Source,
    $Pattern,
    $Replacement,
    [System.Text.RegularExpressions.RegexOptions]::Multiline
  )

  if ($updated -eq $Source) {
    throw "Could not patch Flutter WebRTC source: $Description"
  }

  return $updated
}

function New-IntergalacticPatchBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Backup,
    [Parameter(Mandatory = $true)][string]$Source
  )

  $backupErrors = @()

  try {
    if ($PSCmdlet.ShouldProcess($Backup, "Copy backup from $Target")) {
      Copy-Item -LiteralPath $Target -Destination $Backup -Force -ErrorAction Stop
    }
    return $Backup
  } catch {
    $copyError = $_
    $backupErrors += "Primary Copy-Item failed: $copyError"
    try {
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      if ($PSCmdlet.ShouldProcess($Backup, "Write backup from source text")) {
        [System.IO.File]::WriteAllText($Backup, $Source, $utf8NoBom)
      }
      return $Backup
    } catch {
      $backupErrors += "Primary WriteAllText failed: $_"
      try {
        if ($PSCmdlet.ShouldProcess($Backup, "Set backup content from source text")) {
          Set-Content -LiteralPath $Backup -Value $Source -Encoding UTF8 -NoNewline -Force -ErrorAction Stop
        }
        return $Backup
      } catch {
        $backupErrors += "Primary Set-Content failed: $_"
        $fallbackId = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
        $fallbackBackup = Join-Path `
            (Split-Path -Parent $Target) `
            ("igbak-{0}.{1}.{2}" -f ([System.IO.Path]::GetFileName($Target)), $PID, $fallbackId)
        try {
          if ($PSCmdlet.ShouldProcess($fallbackBackup, "Copy fallback backup from $Target")) {
            Copy-Item -LiteralPath $Target -Destination $fallbackBackup -Force -ErrorAction Stop
          }
          return $fallbackBackup
        } catch {
          $backupErrors += "Fallback Copy-Item failed: $_"
          try {
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            if ($PSCmdlet.ShouldProcess($fallbackBackup, "Write fallback backup from source text")) {
              [System.IO.File]::WriteAllText($fallbackBackup, $Source, $utf8NoBom)
            }
            return $fallbackBackup
          } catch {
            $backupErrors += "Fallback WriteAllText failed: $_"
            try {
              if ($PSCmdlet.ShouldProcess($fallbackBackup, "Set fallback backup content from source text")) {
                Set-Content -LiteralPath $fallbackBackup -Value $Source -Encoding UTF8 -NoNewline -Force -ErrorAction Stop
              }
              return $fallbackBackup
            } catch {
              $backupErrors += "Fallback Set-Content failed: $_"
              $message = ("Could not create backup of {0}. Tried primary backup '{1}' " +
                "and fallback backup '{2}' using Copy-Item, WriteAllText, and Set-Content. " +
                "Errors: {3}") -f $Target, $Backup, $fallbackBackup, ($backupErrors -join " | ")
              throw $message
            }
          }
        }
      }
    }
  }
}

function Get-IntergalacticPatchBackupTarget {
  param([Parameter(Mandatory = $true)][string]$Backup)

  $leaf = [System.IO.Path]::GetFileName($Backup)
  if ($leaf.StartsWith("igbak-")) {
    $originalLeaf = $leaf.Substring(6) -replace '\.\d+\.[0-9a-fA-F]{8}$', ''
    return (Join-Path (Split-Path -Parent $Backup) $originalLeaf)
  }

  $suffixPattern = '\.intergalactic-(?:backup|lifecycle-backup|renderer-backup|dev-profile-backup|frame-diagnostics(?:-[^.\\/]+)*-backup).*$'
  return ($Backup -replace $suffixPattern, '')
}

function Remove-IntergalacticInstallBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$Recurse
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  try {
    if ($PSCmdlet.ShouldProcess($Path, "Remove $Label")) {
      Remove-Item -LiteralPath $Path -Force -Recurse:$Recurse -ErrorAction Stop
    }
  } catch {
    Write-Warning ("Patched libwebrtc cleanup could not remove {0} '{1}': {2}" -f $Label, $Path, $_)
  }
}

function Remove-StaleBuildProduct {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  try {
    if ($PSCmdlet.ShouldProcess($Path, "Remove stale build product")) {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      Write-Host "${Label}: removed stale build product $Path"
    }
  } catch {
    $exception = $_.Exception
    if ($exception -is [System.UnauthorizedAccessException] -or
        $exception -is [System.IO.IOException]) {
      $message = (
        "{0}: stale build product is locked and could not be removed: {1}. " +
        "Close any running InterGalactic, Flutter, or MSBuild process that may " +
        "have loaded it, then rerun this installer or rebuild the app if Debug " +
        "still uses stale flutter_webrtc output. Continuing because this file " +
        "is generated build output. Error: {2}") -f $Label, $Path, $exception.Message
      Write-Warning $message
      return
    }

    throw
  }
}

function Clear-WindowsFlutterWebrtcFrameCryptorBuildCache {
  param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot
  )

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_frame_cryptor.cc"
  Assert-PathInside -Parent $PackageRoot -Child $target
  if (-not (Test-Path -LiteralPath $target)) {
    return
  }

  $source = [System.IO.File]::ReadAllText($target)
  $frameCryptorPatchMarker = "FrameCryptorFactoryCreateFrameCryptorUnavailable"
  $usesMissingFrameCryptorExports =
      $source.Contains('FrameCryptorFactory::frameCryptorFromRtpSender') -or
      $source.Contains('FrameCryptorFactory::frameCryptorFromRtpReceiver')

  if ((-not $source.Contains($frameCryptorPatchMarker)) -and
      $usesMissingFrameCryptorExports) {
    return
  }

  $appFull = Resolve-LocalPath $AppRoot
  $buildRoot = Join-Path $appFull "build\windows\x64"
  if (-not (Test-Path -LiteralPath $buildRoot)) {
    return
  }
  Assert-PathInside -Parent $appFull -Child $buildRoot

  $stampPath = Join-Path $buildRoot "plugins\flutter_webrtc\intergalactic-frame-cryptor-cache-cleared.sha256"
  Assert-PathInside -Parent $buildRoot -Child $stampPath

  $sourceHash = Get-Sha256Hash -Path $target

  # Always remove these build products when the compatibility source is present.
  # Flutter/CMake can regenerate stale plugin binaries after the one-time stamp
  # is written, and the stale DLL fails Windows loader import snapping before
  # Dart startup.
  $staleBuildProducts = @(
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Debug\flutter_frame_cryptor.obj",
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Release\flutter_frame_cryptor.obj",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.pdb",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.pdb",
    "runner\Debug\flutter_webrtc_plugin.dll",
    "runner\Debug\flutter_webrtc_plugin.pdb",
    "runner\Release\flutter_webrtc_plugin.dll",
    "runner\Release\flutter_webrtc_plugin.pdb"
  )

  foreach ($relativePath in $staleBuildProducts) {
    $path = Join-Path $buildRoot $relativePath
    Assert-PathInside -Parent $buildRoot -Child $path
    Remove-StaleBuildProduct -Path $path -Label "Flutter WebRTC frame cryptor patch"
  }

  $stampDir = Split-Path -Parent $stampPath
  if (-not (Test-Path -LiteralPath $stampDir)) {
    New-Item -ItemType Directory -Path $stampDir | Out-Null
  }
  Set-Content -LiteralPath $stampPath -Value $sourceHash -Encoding ASCII
}

function Clear-WindowsFlutterWebrtcRendererDiagnosticsBuildCache {
  param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot
  )

  $rendererSource = Join-Path $PackageRoot "common\cpp\src\flutter_video_renderer.cc"
  $webrtcSource = Join-Path $PackageRoot "common\cpp\src\flutter_webrtc.cc"
  foreach ($target in @($rendererSource, $webrtcSource)) {
    Assert-PathInside -Parent $PackageRoot -Child $target
    if (-not (Test-Path -LiteralPath $target)) {
      return
    }
  }

  $rendererCcSource = [System.IO.File]::ReadAllText($rendererSource)
  $webrtcCcSource = [System.IO.File]::ReadAllText($webrtcSource)
  if ((-not $rendererCcSource.Contains("Inter Galactic: native renderer frame diagnostics")) -or
      (-not $webrtcCcSource.Contains("intergalacticVideoRendererSetFrameDiagnostics"))) {
    return
  }

  $appFull = Resolve-LocalPath $AppRoot
  $buildRoot = Join-Path $appFull "build\windows\x64"
  if (-not (Test-Path -LiteralPath $buildRoot)) {
    return
  }
  Assert-PathInside -Parent $appFull -Child $buildRoot

  # The renderer-diagnostics patch spans two C++ sources. If either object is
  # stale, the rebuilt DLL can load but miss the method-channel handler used by
  # the external receiver probe.
  $staleBuildProducts = @(
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Debug\flutter_video_renderer.obj",
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Debug\flutter_webrtc.obj",
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Release\flutter_video_renderer.obj",
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Release\flutter_webrtc.obj",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.exp",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.lib",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.pdb",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.exp",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.lib",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.pdb",
    "runner\Debug\flutter_webrtc_plugin.dll",
    "runner\Debug\flutter_webrtc_plugin.pdb",
    "runner\Release\flutter_webrtc_plugin.dll",
    "runner\Release\flutter_webrtc_plugin.pdb"
  )

  foreach ($relativePath in $staleBuildProducts) {
    $path = Join-Path $buildRoot $relativePath
    Assert-PathInside -Parent $buildRoot -Child $path
    Remove-StaleBuildProduct -Path $path -Label "Flutter WebRTC video renderer diagnostics patch"
  }
}

function Clear-WindowsFlutterWebrtcDesktopCaptureBuildCache {
  param(
    [Parameter(Mandatory = $true)][string]$AppRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot
  )

  $captureSource = Join-Path $PackageRoot "common\cpp\src\flutter_screen_capture.cc"
  Assert-PathInside -Parent $PackageRoot -Child $captureSource
  if (-not (Test-Path -LiteralPath $captureSource)) {
    return
  }

  $source = [System.IO.File]::ReadAllText($captureSource)
  if ((-not $source.Contains("intergalacticCaptureBackend")) -or
      (-not $source.Contains("Inter Galactic desktop capture bridge start"))) {
    return
  }

  $appFull = Resolve-LocalPath $AppRoot
  $buildRoot = Join-Path $appFull "build\windows\x64"
  if (-not (Test-Path -LiteralPath $buildRoot)) {
    return
  }
  Assert-PathInside -Parent $appFull -Child $buildRoot

  # The desktop-capture patch is the bridge from Dart stream-test options into
  # the patched native capturer. A stale object silently drops backend and size
  # constraints, falling back to full-size WGC while app logs still show 720p.
  $staleBuildProducts = @(
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Debug\flutter_screen_capture.obj",
    "plugins\flutter_webrtc\flutter_webrtc_plugin.dir\Release\flutter_screen_capture.obj",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.exp",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.lib",
    "plugins\flutter_webrtc\Debug\flutter_webrtc_plugin.pdb",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.dll",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.exp",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.lib",
    "plugins\flutter_webrtc\Release\flutter_webrtc_plugin.pdb",
    "runner\Debug\flutter_webrtc_plugin.dll",
    "runner\Debug\flutter_webrtc_plugin.pdb",
    "runner\Release\flutter_webrtc_plugin.dll",
    "runner\Release\flutter_webrtc_plugin.pdb"
  )

  foreach ($relativePath in $staleBuildProducts) {
    $path = Join-Path $buildRoot $relativePath
    Assert-PathInside -Parent $buildRoot -Child $path
    Remove-StaleBuildProduct -Path $path -Label "Flutter WebRTC desktop capture patch"
  }
}

function Add-WindowsDesktopCaptureBridgeLogging {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Newline
  )

  $updated = $Source
  $updated = [System.Text.RegularExpressions.Regex]::Replace(
    $updated,
    '(?m)^#include "rtc_base/logging\.h"\r?\n',
    ''
  )

  if (-not $updated.Contains("capture_backend_mode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  double fps = 30\.0;\r?\n  uint32_t max_frame_width = 0;\r?\n  uint32_t max_frame_height = 0;\r?\n' `
      -Replacement "  double fps = 30.0;${Newline}  uint32_t max_frame_width = 0;${Newline}  uint32_t max_frame_height = 0;${Newline}  std::string capture_backend_mode = `"default`";${Newline}" `
      -Description "desktop capture backend mode variable"
  }

  if (-not $updated.Contains("capture_frame_pacing_mode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  std::string capture_backend_mode = "default";\r?\n' `
      -Replacement "  std::string capture_backend_mode = `"default`";${Newline}  std::string capture_frame_pacing_mode = `"off`";${Newline}" `
      -Description "desktop capture latest-frame pacing mode variable"
  }

  if (-not $updated.Contains("capture_dirty_region_mode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  std::string capture_frame_pacing_mode = "off";\r?\n' `
      -Replacement "  std::string capture_frame_pacing_mode = `"off`";${Newline}  std::string capture_dirty_region_mode = `"auto`";${Newline}" `
      -Description "desktop capture dirty-region mode variable"
  }

  if (-not $updated.Contains("capture_window_gdi_mode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  std::string capture_dirty_region_mode = "auto";\r?\n' `
      -Replacement "  std::string capture_dirty_region_mode = `"auto`";${Newline}  std::string capture_window_gdi_mode = `"default`";${Newline}" `
      -Description "desktop capture window-GDI mode variable"
  }

  if (-not $updated.Contains("game_capture_process_id")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  std::string capture_window_gdi_mode = "default";\r?\n' `
      -Replacement "  std::string capture_window_gdi_mode = `"default`";${Newline}  uint32_t game_capture_process_id = 0;${Newline}  std::string game_capture_helper_path;${Newline}  std::string game_capture_source_mode = `"helper-d3d11`";${Newline}" `
      -Description "desktop capture debug game-capture variables"
  }

  if (-not $updated.Contains("game_capture_source_mode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  std::string game_capture_helper_path;\r?\n' `
      -Replacement "  std::string game_capture_helper_path;${Newline}  std::string game_capture_source_mode = `"helper-d3d11`";${Newline}" `
      -Description "desktop capture debug source-mode variable"
  }

  if (-not $updated.Contains("intergalacticCaptureBackend")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    std::string requested_capture_backend =${Newline}        findString(video, `"intergalacticCaptureBackend`");${Newline}    if (!requested_capture_backend.empty()) {${Newline}      capture_backend_mode = requested_capture_backend;${Newline}    }${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture backend mode constraint"
  }

  if (-not $updated.Contains("intergalacticCaptureFramePacing")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    std::string requested_capture_frame_pacing =${Newline}        findString(video, `"intergalacticCaptureFramePacing`");${Newline}    if (!requested_capture_frame_pacing.empty()) {${Newline}      capture_frame_pacing_mode = requested_capture_frame_pacing;${Newline}    }${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture latest-frame pacing constraint"
  }

  if (-not $updated.Contains("intergalacticCaptureDirtyRegion")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    std::string requested_capture_dirty_region =${Newline}        findString(video, `"intergalacticCaptureDirtyRegion`");${Newline}    if (!requested_capture_dirty_region.empty()) {${Newline}      capture_dirty_region_mode = requested_capture_dirty_region;${Newline}    }${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture dirty-region mode constraint"
  }

  if (-not $updated.Contains("intergalacticWindowGdiMode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    std::string requested_capture_window_gdi =${Newline}        findString(video, `"intergalacticWindowGdiMode`");${Newline}    if (!requested_capture_window_gdi.empty()) {${Newline}      capture_window_gdi_mode = requested_capture_window_gdi;${Newline}    }${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture window-GDI mode constraint"
  }

  if (-not $updated.Contains("intergalacticGameCaptureProcessId")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    int requested_game_capture_process_id =${Newline}        findInt(video, `"intergalacticGameCaptureProcessId`");${Newline}    if (requested_game_capture_process_id > 0) {${Newline}      game_capture_process_id =${Newline}          static_cast<uint32_t>(requested_game_capture_process_id);${Newline}    }${Newline}    game_capture_helper_path =${Newline}        findString(video, `"intergalacticGameCaptureHelperPath`");${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture debug game-capture constraints"
  }

  if (-not $updated.Contains("intergalacticGameCaptureSourceMode")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
      -Replacement "    std::string requested_game_capture_source_mode =${Newline}        findString(video, `"intergalacticGameCaptureSourceMode`");${Newline}    if (!requested_game_capture_source_mode.empty()) {${Newline}      game_capture_source_mode = requested_game_capture_source_mode;${Newline}    }${Newline}${Newline}    const EncodableMap deviceId = findMap(video, `"deviceId`");${Newline}" `
      -Description "desktop capture debug game-capture source-mode constraint"
  }

  if (-not $updated.Contains("Inter Galactic game capture WebRTC source start")) {
    $gameCaptureBranchBlock = @"
  if (capture_backend_mode == "game-d3d11-hook-experimental") {
    if (source->type() != kWindow) {
      result->Error("Bad Arguments",
                    "Experimental game capture requires a window source");
      return;
    }
    const bool use_dummy_nv12_live_sender =
        game_capture_source_mode == "dummy-nv12-live-sender";
    if (!use_dummy_nv12_live_sender && game_capture_process_id == 0) {
      result->Error("Bad Arguments",
                    "Experimental game capture requires a target process id");
      return;
    }

    scoped_refptr<RTCVideoCapturer> game_capturer =
        base_->video_device_->CreateGameCapture(
            game_capture_helper_path.empty()
                ? nullptr
                : game_capture_helper_path.c_str(),
            game_capture_process_id,
            max_frame_width > 0 ? max_frame_width : 1280,
            max_frame_height > 0 ? max_frame_height : 720,
            static_cast<size_t>(fps),
            use_dummy_nv12_live_sender
                ? game_capture_source_mode.c_str()
                : nullptr);

    if (!game_capturer.get()) {
      result->Error("Bad Arguments", "CreateGameCapture failed!");
      return;
    }
    if (!game_capturer->StartCapture()) {
      result->Error("Bad Arguments", "Start game capture failed!");
      return;
    }

    const char* video_source_label = "game_capture_input";
    scoped_refptr<RTCVideoSource> video_source =
        base_->factory_->CreateVideoSource(
            game_capturer, video_source_label,
            base_->ParseMediaConstraints(video_constraints));

    scoped_refptr<RTCVideoTrack> track =
        base_->factory_->CreateVideoTrack(video_source, uuid.c_str());

    EncodableList videoTracks;
    EncodableMap info;
    info[EncodableValue("id")] = EncodableValue(track->id().std_string());
    info[EncodableValue("label")] = EncodableValue(track->id().std_string());
    info[EncodableValue("kind")] = EncodableValue(track->kind().std_string());
    info[EncodableValue("enabled")] = EncodableValue(track->enabled());
    videoTracks.push_back(EncodableValue(info));
    params[EncodableValue("videoTracks")] = EncodableValue(videoTracks);

    stream->AddTrack(track);
    base_->local_tracks_[track->id().std_string()] = track;
    base_->video_capturers_[track->id().std_string()] = game_capturer;
    // Inter Galactic: keep game capture stream registered so
    // trackDispose/mediaStreamDispose and local renderers can reach the native
    // stream/capturer instead of leaving a stale helper alive.
    base_->local_streams_[uuid] = stream;

    std::cout << "Inter Galactic game capture WebRTC source start source_type="
              << (source->type() == kWindow ? "window" : "screen")
              << " requested_max=" << max_frame_width << "x"
              << max_frame_height << " fps=" << fps
              << " pid=" << game_capture_process_id
              << " source_mode=" << game_capture_source_mode << std::endl;

    result->Success(EncodableValue(params));
    return;
  }

"@
    $gameCaptureBranchBlock = $gameCaptureBranchBlock -replace "\r?\n", $Newline
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  scoped_refptr<RTCDesktopCapturer> desktop_capturer =\r?\n      base_->desktop_device_->CreateDesktopCapturer\(source\);\r?\n' `
      -Replacement ($gameCaptureBranchBlock + "  scoped_refptr<RTCDesktopCapturer> desktop_capturer =${Newline}      base_->desktop_device_->CreateDesktopCapturer(source);${Newline}") `
      -Description "desktop capture debug game-capture branch"
  }

  if ($updated.Contains("Inter Galactic game capture WebRTC source start") -and
      -not $updated.Contains("Inter Galactic: keep game capture stream registered")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    base_->local_tracks_\[track->id\(\)\.std_string\(\)\] = track;\r?\n    base_->video_capturers_\[track->id\(\)\.std_string\(\)\] = game_capturer;\r?\n' `
      -Replacement "    base_->local_tracks_[track->id().std_string()] = track;${Newline}    base_->video_capturers_[track->id().std_string()] = game_capturer;${Newline}    // Inter Galactic: keep game capture stream registered so${Newline}    // trackDispose/mediaStreamDispose and local renderers can reach the native${Newline}    // stream/capturer instead of leaving a stale helper alive.${Newline}    base_->local_streams_[uuid] = stream;${Newline}" `
      -Description "game-capture stream ownership registration"
  }

  if ($updated.Contains("Inter Galactic game capture WebRTC source start") -and
      -not $updated.Contains("use_dummy_nv12_live_sender")) {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '    if \(game_capture_process_id == 0\) \{\r?\n      result->Error\("Bad Arguments",\r?\n                    "Experimental game capture requires a target process id"\);\r?\n      return;\r?\n    \}\r?\n' `
      -Replacement "    const bool use_dummy_nv12_live_sender =${Newline}        game_capture_source_mode == `"dummy-nv12-live-sender`";${Newline}    if (!use_dummy_nv12_live_sender && game_capture_process_id == 0) {${Newline}      result->Error(`"Bad Arguments`",${Newline}                    `"Experimental game capture requires a target process id`");${Newline}      return;${Newline}    }${Newline}" `
      -Description "game-capture dummy NV12 source PID bypass"

    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '            max_frame_width > 0 \? max_frame_width : 1280,\r?\n            max_frame_height > 0 \? max_frame_height : 720,\r?\n            static_cast<size_t>\(fps\)\);' `
      -Replacement "            max_frame_width > 0 ? max_frame_width : 1280,${Newline}            max_frame_height > 0 ? max_frame_height : 720,${Newline}            static_cast<size_t>(fps),${Newline}            use_dummy_nv12_live_sender${Newline}                ? game_capture_source_mode.c_str()${Newline}                : nullptr);" `
      -Description "game-capture source-mode argument"

    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '              << " pid=" << game_capture_process_id << std::endl;' `
      -Replacement "              << `" pid=`" << game_capture_process_id${Newline}              << `" source_mode=`" << game_capture_source_mode << std::endl;" `
      -Description "game-capture source-mode bridge log"
  }

  $bridgeStartBlock = "  desktop_capturer->SetWindowsCaptureBackendMode(capture_backend_mode.c_str());${Newline}  desktop_capturer->SetWindowsCaptureDirtyRegionMode(${Newline}      capture_dirty_region_mode.c_str());${Newline}  desktop_capturer->SetWindowsWindowGdiCaptureMode(${Newline}      capture_window_gdi_mode.c_str());${Newline}  desktop_capturer->SetLatestFramePacingEnabled(${Newline}      capture_frame_pacing_mode == `"latest`");${Newline}${Newline}  std::cout << `"Inter Galactic desktop capture bridge start source_type=`"${Newline}            << (source->type() == kWindow ? `"window`" : `"screen`")${Newline}            << `" requested_max=`" << max_frame_width << `"x`"${Newline}            << max_frame_height << `" fps=`" << fps${Newline}            << `" capture_backend=`" << capture_backend_mode${Newline}            << `" frame_pacing=`" << capture_frame_pacing_mode${Newline}            << `" dirty_region=`" << capture_dirty_region_mode${Newline}            << `" window_gdi_mode=`" << capture_window_gdi_mode << std::endl;${Newline}${Newline}  if (max_frame_width > 0 && max_frame_height > 0) {${Newline}    desktop_capturer->StartWithMaxFrameSize(uint32_t(fps), max_frame_width,${Newline}                                            max_frame_height);${Newline}  } else {${Newline}    desktop_capturer->Start(uint32_t(fps));${Newline}  }${Newline}"

  if ($updated.Contains("Inter Galactic desktop capture bridge start")) {
    $bridgeStartPattern = '(?:  desktop_capturer->SetWindowsCaptureBackendMode\(capture_backend_mode\.c_str\(\)\);\r?\n(?:  desktop_capturer->SetWindowsCaptureDirtyRegionMode\([\s\S]*?\);\r?\n)?(?:  desktop_capturer->SetWindowsWindowGdiCaptureMode\([\s\S]*?\);\r?\n)?(?:  desktop_capturer->SetLatestFramePacingEnabled\([\s\S]*?\);\r?\n)?\r?\n)?  (?:RTC_LOG\(LS_INFO\)|std::cout) << "Inter Galactic desktop capture bridge start source_type="[\s\S]*?  if \(max_frame_width > 0 && max_frame_height > 0\) \{\r?\n    desktop_capturer->StartWithMaxFrameSize\(uint32_t\(fps\), max_frame_width,\r?\n                                            max_frame_height\);\r?\n  \} else \{\r?\n    desktop_capturer->Start\(uint32_t\(fps\)\);\r?\n  \}\r?\n'
    $repaired = [System.Text.RegularExpressions.Regex]::Replace(
      $updated,
      $bridgeStartPattern,
      $bridgeStartBlock,
      [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    if (($repaired -eq $updated) -and
        $updated.Contains('RTC_LOG(LS_INFO) << "Inter Galactic desktop capture bridge start')) {
      throw "Could not repair Flutter WebRTC source: desktop capture bridge logging uses unavailable rtc_base logging header"
    }

    $updated = $repaired
  } else {
    $updated = Update-SourceText `
      -Source $updated `
      -Pattern '  if \(max_frame_width > 0 && max_frame_height > 0\) \{\r?\n    desktop_capturer->StartWithMaxFrameSize\(uint32_t\(fps\), max_frame_width,\r?\n                                            max_frame_height\);\r?\n  \} else \{\r?\n    desktop_capturer->Start\(uint32_t\(fps\)\);\r?\n  \}\r?\n' `
      -Replacement $bridgeStartBlock `
      -Description "desktop capture bridge scaler start logging"
  }

  return $updated
}

function Install-WindowsFrameCryptorCompatibilityPatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_frame_cryptor.cc"
  $backup = "$target.intergalactic-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "Flutter WebRTC frame cryptor source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $frameCryptorPatchMarker = "FrameCryptorFactoryCreateFrameCryptorUnavailable"
  $usesMissingFrameCryptorExports =
      $source.Contains('FrameCryptorFactory::frameCryptorFromRtpSender') -or
      $source.Contains('FrameCryptorFactory::frameCryptorFromRtpReceiver')

  if ($source.Contains($frameCryptorPatchMarker) -or
      (-not $usesMissingFrameCryptorExports)) {
    Write-Host "Flutter WebRTC frame cryptor patch: compatibility behavior already present."
    return $null
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    $stub = "void FlutterFrameCryptor::FrameCryptorFactoryCreateFrameCryptor(${nl}    const EncodableMap& constraints,${nl}    std::unique_ptr<MethodResultProxy> result) {${nl}  // Inter Galactic: Windows patched libwebrtc artifact does not export${nl}  // FrameCryptorFactory sender/receiver constructors. Inter Galactic uses${nl}  // Matrix room E2EE, not flutter_webrtc's optional media FrameCryptor path,${nl}  // so keep the plugin linkable and fail this optional API open at runtime.${nl}  (void)constraints;${nl}  result->Error(`"FrameCryptorFactoryCreateFrameCryptorUnavailable`",${nl}                `"FrameCryptor is unavailable in this Windows build`");${nl}}${nl}${nl}"
    $methodStartMatch = [regex]::Match(
      $source,
      'void\s+FlutterFrameCryptor::FrameCryptorFactoryCreateFrameCryptor\s*\(')
    if (-not $methodStartMatch.Success) {
      throw "Could not locate FlutterFrameCryptor::FrameCryptorFactoryCreateFrameCryptor for Windows compatibility patch"
    }

    $afterMethodStart = $source.Substring($methodStartMatch.Index + 1)
    $nextMethodStartMatch = [regex]::Match(
      $afterMethodStart,
      'void\s+FlutterFrameCryptor::FrameCryptorSetKeyIndex\s*\(')
    if (-not $nextMethodStartMatch.Success) {
      throw "Could not locate FlutterFrameCryptor::FrameCryptorSetKeyIndex boundary for Windows compatibility patch"
    }

    $nextMethodStart = $methodStartMatch.Index + 1 + $nextMethodStartMatch.Index
    $source =
        $source.Substring(0, $methodStartMatch.Index) +
        $stub +
        $source.Substring($nextMethodStart)

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "Flutter WebRTC frame cryptor patch: installed Windows compatibility stub."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "Flutter WebRTC frame cryptor patch rollback failed: $_"
    }
    throw $originalError
  }
}

function Install-WindowsAudioCaptureOptionsPatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_media_stream.cc"
  $backup = "$target.intergalactic-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "Flutter WebRTC media stream source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $audioOptionsPatchMarker = "Inter Galactic: apply Windows audio capture constraints"

  if ($source.Contains($audioOptionsPatchMarker)) {
    Write-Host "Flutter WebRTC audio capture patch: options bridge already applied."
    return $null
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    $helpers = @'
// Inter Galactic: apply Windows audio capture constraints when creating the
// native microphone source. The stock bridge parsed constraints but never
// copied them into RTCAudioOptions, so AGC/NS/AEC diagnostics did not match the
// actual WebRTC processing path.
bool intergalacticReadBoolConstraintValue(const EncodableValue& value,
                                          bool* output) {
  if (TypeIs<bool>(value)) {
    *output = GetValue<bool>(value);
    return true;
  }

  if (TypeIs<std::string>(value)) {
    const std::string stringValue = GetValue<std::string>(value);
    if (stringValue == RTCMediaConstraints::kValueTrue ||
        stringValue == "1") {
      *output = true;
      return true;
    }
    if (stringValue == RTCMediaConstraints::kValueFalse ||
        stringValue == "0") {
      *output = false;
      return true;
    }
  }

  return false;
}

bool intergalacticFindBoolInMap(const EncodableMap& map,
                                const std::string& key,
                                bool* output) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) {
    return false;
  }
  return intergalacticReadBoolConstraintValue(it->second, output);
}

bool intergalacticFindBoolAudioConstraint(const EncodableMap& mediaConstraints,
                                          const std::string& key,
                                          bool* output) {
  if (intergalacticFindBoolInMap(mediaConstraints, key, output)) {
    return true;
  }

  auto mandatory = mediaConstraints.find(EncodableValue("mandatory"));
  if (mandatory != mediaConstraints.end() &&
      TypeIs<EncodableMap>(mandatory->second) &&
      intergalacticFindBoolInMap(GetValue<EncodableMap>(mandatory->second), key,
                                 output)) {
    return true;
  }

  auto optional = mediaConstraints.find(EncodableValue("optional"));
  if (optional == mediaConstraints.end()) {
    return false;
  }

  if (TypeIs<EncodableMap>(optional->second)) {
    return intergalacticFindBoolInMap(GetValue<EncodableMap>(optional->second),
                                      key, output);
  }

  if (TypeIs<EncodableList>(optional->second)) {
    const EncodableList options = GetValue<EncodableList>(optional->second);
    for (const EncodableValue& option : options) {
      if (TypeIs<EncodableMap>(option) &&
          intergalacticFindBoolInMap(GetValue<EncodableMap>(option), key,
                                     output)) {
        return true;
      }
    }
  }

  return false;
}

RTCAudioOptions intergalacticAudioOptionsFromConstraints(
    const EncodableMap& mediaConstraints) {
  RTCAudioOptions options;
  bool value = false;

  if (intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "echoCancellation", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googEchoCancellation", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googEchoCancellation2", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googDAEchoCancellation", &value)) {
    options.echo_cancellation = value;
  }

  if (intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "autoGainControl", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googAutoGainControl", &value)) {
    options.auto_gain_control = value;
  }

  if (intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "noiseSuppression", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googNoiseSuppression", &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googNoiseSuppression2", &value)) {
    options.noise_suppression = value;
  }

  if (intergalacticFindBoolAudioConstraint(mediaConstraints, "highPassFilter",
                                           &value) ||
      intergalacticFindBoolAudioConstraint(mediaConstraints,
                                           "googHighpassFilter", &value)) {
    options.highpass_filter = value;
  }

  return options;
}

'@
    $helpers = $helpers -replace "\r?\n", $nl

    $source = Update-SourceText `
      -Source $source `
      -Pattern 'void FlutterMediaStream::GetUserAudio' `
      -Replacement ($helpers + "void FlutterMediaStream::GetUserAudio") `
      -Description "insert audio options helpers"

    $source = Update-SourceText `
      -Source $source `
      -Pattern '  std::string sourceId;\r?\n  std::string deviceId;\r?\n' `
      -Replacement "  std::string sourceId;${nl}  std::string deviceId;${nl}  RTCAudioOptions audioOptions;${nl}" `
      -Description "audio options local"

    $source = Update-SourceText `
      -Source $source `
      -Pattern '      audioConstraints = base_->ParseMediaConstraints\(localMap\);\r?\n      enable_audio = true;\r?\n' `
      -Replacement "      audioConstraints = base_->ParseMediaConstraints(localMap);${nl}      audioOptions = intergalacticAudioOptionsFromConstraints(localMap);${nl}      enable_audio = true;${nl}" `
      -Description "copy audio constraints into options"

    $source = Update-SourceText `
      -Source $source `
      -Pattern '    scoped_refptr<RTCAudioSource> source =\r?\n        base_->factory_->CreateAudioSource\("audio_input"\);\r?\n' `
      -Replacement "    scoped_refptr<RTCAudioSource> source =${nl}        base_->factory_->CreateAudioSource(${nl}            `"audio_input`", RTCAudioSource::kMicrophone, audioOptions);${nl}" `
      -Description "create audio source with options"

    $source = Update-SourceText `
      -Source $source `
      -Pattern '    settings\[EncodableValue\("autoGainControl"\)\] = EncodableValue\(true\);\r?\n    settings\[EncodableValue\("echoCancellation"\)\] = EncodableValue\(true\);\r?\n    settings\[EncodableValue\("noiseSuppression"\)\] = EncodableValue\(true\);\r?\n' `
      -Replacement "    settings[EncodableValue(`"autoGainControl`")] =${nl}        EncodableValue(audioOptions.auto_gain_control);${nl}    settings[EncodableValue(`"echoCancellation`")] =${nl}        EncodableValue(audioOptions.echo_cancellation);${nl}    settings[EncodableValue(`"noiseSuppression`")] =${nl}        EncodableValue(audioOptions.noise_suppression);${nl}" `
      -Description "report applied audio options in settings"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "Flutter WebRTC audio capture patch: installed options bridge."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "Flutter WebRTC audio capture patch rollback failed: $_"
    }
    throw $originalError
  }
}

function Install-WindowsSharedPreferencesDevProfilePatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "lib\shared_preferences_windows.dart"
  $backup = "$target.intergalactic-dev-profile-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "shared_preferences_windows source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $patchMarker = "INTERGALACTIC_DEV_PROFILE_DIR"

  if ($source.Contains($patchMarker) -and
      $source.Contains("io.Directory.systemTemp")) {
    Write-Host "shared_preferences_windows dev profile patch: already applied."
    return $null
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    if ($source.Contains($patchMarker)) {
      if ($source.Contains("import 'dart:io';")) {
        $source = $source.Replace(
            "import 'dart:io';${nl}",
            "import 'dart:io' as io;${nl}")
      } elseif (-not $source.Contains("import 'dart:io' as io;")) {
        $source = $source.Replace(
            "import 'dart:convert' show json;${nl}",
            "import 'dart:convert' show json;${nl}import 'dart:io' as io;${nl}")
        if (-not $source.Contains("import 'dart:io' as io;")) {
          throw "Could not add dart:io import to shared_preferences_windows source"
        }
      }

      $source = $source.Replace(
          "Platform.environment['INTERGALACTIC_DEV_PROFILE_DIR']",
          "io.Platform.environment['INTERGALACTIC_DEV_PROFILE_DIR']")
      $source = $source.Replace(
          "Directory.systemTemp.path",
          "io.Directory.systemTemp.path")

      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
      Write-Host "shared_preferences_windows dev profile patch: repaired INTERGALACTIC_DEV_PROFILE_DIR support."
      return $backup
    }

    if ($source.Contains("import 'dart:io';")) {
      $source = $source.Replace(
          "import 'dart:io';${nl}",
          "import 'dart:io' as io;${nl}")
    } elseif (-not $source.Contains("import 'dart:io' as io;")) {
      $source = $source.Replace(
          "import 'dart:convert' show json;${nl}",
          "import 'dart:convert' show json;${nl}import 'dart:io' as io;${nl}")
      if (-not $source.Contains("import 'dart:io' as io;")) {
        throw "Could not add dart:io import to shared_preferences_windows source"
      }
    }

    $helper = @'
String? _intergalacticDevProfilePreferencesDirectory() {
  final String? rawProfile =
      io.Platform.environment['INTERGALACTIC_DEV_PROFILE_DIR']?.trim();
  if (rawProfile == null || rawProfile.isEmpty) {
    return null;
  }

  final String profileRoot = path.isAbsolute(rawProfile)
      ? path.normalize(rawProfile)
      : path.join(
          io.Directory.systemTemp.path,
          'intergalactic-dev-profiles',
          rawProfile.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'),
        );

  return path.join(profileRoot, 'preferences');
}

'@
    $helper = $helper -replace "\r?\n", $nl

    $source = Update-SourceText `
      -Source $source `
      -Pattern '/// Gets the file where the preferences are stored\.\r?\n' `
      -Replacement ($helper + "/// Gets the file where the preferences are stored.${nl}") `
      -Description "shared_preferences_windows Inter Galactic dev profile helper"

    $source = Update-SourceText `
      -Source $source `
      -Pattern '  final String\? directory = await pathProvider\.getApplicationSupportPath\(\);\r?\n' `
      -Replacement "  final String? directory =${nl}      _intergalacticDevProfilePreferencesDirectory() ??${nl}      await pathProvider.getApplicationSupportPath();${nl}" `
      -Description "shared_preferences_windows Inter Galactic dev profile directory override"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "shared_preferences_windows dev profile patch: installed INTERGALACTIC_DEV_PROFILE_DIR support."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "shared_preferences_windows dev profile patch rollback failed: $_"
    }
    throw $originalError
  }
}

function Install-WindowsMediaStreamLifecyclePatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_media_stream.cc"
  $backup = "$target.intergalactic-lifecycle-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "Flutter WebRTC media stream source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lifecyclePatchMarker = "Inter Galactic: stop orphan video capturers"

  if ($source.Contains($lifecyclePatchMarker)) {
    Write-Host "Flutter WebRTC media stream lifecycle patch: already applied."
    return $null
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    if (-not $source.Contains("#include <iostream>")) {
      $source = Update-SourceText `
        -Source $source `
        -Pattern '#include "flutter_media_stream\.h"\r?\n' `
        -Replacement "#include `"flutter_media_stream.h`"${nl}${nl}#include <iostream>${nl}" `
        -Description "media stream lifecycle logging include"
    }

    $orphanCapturerBlock = @"
  // Inter Galactic: stop orphan video capturers even if the track was not
  // found in local_streams_. The debug game-capture branch creates a manual
  // screen-share track, and missing stream ownership previously let its
  // helper/hook survive after LiveKit unpublish.
  auto orphan_video_capture = base_->video_capturers_.find(track_id);
  if (orphan_video_capture != base_->video_capturers_.end()) {
    auto video_capture = orphan_video_capture->second;
    if (video_capture->CaptureStarted()) {
      std::cout
          << "Inter Galactic media stream lifecycle stopping orphan capturer track_id="
          << track_id << std::endl;
      video_capture->StopCapture();
    } else {
      std::cout
          << "Inter Galactic media stream lifecycle erasing stopped orphan capturer track_id="
          << track_id << std::endl;
    }
    base_->video_capturers_.erase(orphan_video_capture);
  }

"@
    $orphanCapturerBlock = $orphanCapturerBlock -replace "\r?\n", $nl

    $source = Update-SourceText `
      -Source $source `
      -Pattern '  base_->RemoveMediaTrackForId\(track_id\);\r?\n  result->Success\(\);\r?\n' `
      -Replacement ($orphanCapturerBlock + "  base_->RemoveMediaTrackForId(track_id);${nl}  result->Success();${nl}") `
      -Description "media stream orphan capturer cleanup"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "Flutter WebRTC media stream lifecycle patch: installed orphan capturer cleanup."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "Flutter WebRTC media stream lifecycle patch rollback failed: $_"
    }
    throw $originalError
  }
}

function Install-WindowsVideoRendererLatestFramePatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_video_renderer.cc"
  $backup = "$target.intergalactic-renderer-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "Flutter WebRTC video renderer source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $rendererPatchMarker = "Inter Galactic: do not hold renderer frame mutex while converting"

  if ($source.Contains($rendererPatchMarker)) {
    Write-Host "Flutter WebRTC video renderer patch: latest-frame mutex behavior already applied."
    return $null
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    $copyPixelBuffer = @'
const FlutterDesktopPixelBuffer* FlutterVideoRenderer::CopyPixelBuffer(
    size_t width,
    size_t height) const {
  (void)width;
  (void)height;

  scoped_refptr<RTCVideoFrame> frame;
  std::shared_ptr<FlutterDesktopPixelBuffer> pixel_buffer;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    frame = frame_;
    pixel_buffer = pixel_buffer_;
  }

  if (!pixel_buffer.get() || !frame.get()) {
    return nullptr;
  }

  if (pixel_buffer->width != frame->width() ||
      pixel_buffer->height != frame->height()) {
    size_t buffer_size =
        (size_t(frame->width()) * size_t(frame->height())) * (32 >> 3);
    rgb_buffer_.reset(new uint8_t[buffer_size],
                      std::default_delete<uint8_t[]>());
    pixel_buffer->width = frame->width();
    pixel_buffer->height = frame->height();
  }

  // Inter Galactic: do not hold renderer frame mutex while converting.
  // Native preview frames can arrive on a WebRTC source/broadcaster thread;
  // holding this lock during I420->ABGR conversion lets Flutter texture pulls
  // block the newest-frame handoff and makes the local stream tile stale.
  frame->ConvertToARGB(RTCVideoFrame::Type::kABGR, rgb_buffer_.get(), 0,
                       static_cast<int>(pixel_buffer->width),
                       static_cast<int>(pixel_buffer->height));

  pixel_buffer->buffer = rgb_buffer_.get();
  return pixel_buffer.get();
}
'@
    $copyPixelBuffer = $copyPixelBuffer -replace "\r?\n", $nl

    $source = Update-SourceText `
      -Source $source `
      -Pattern 'const FlutterDesktopPixelBuffer\* FlutterVideoRenderer::CopyPixelBuffer\([\s\S]*?\r?\n}\r?\n\r?\nvoid FlutterVideoRenderer::OnFrame' `
      -Replacement ($copyPixelBuffer + "${nl}${nl}void FlutterVideoRenderer::OnFrame") `
      -Description "video renderer latest-frame mutex copy"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "Flutter WebRTC video renderer patch: installed latest-frame mutex copy."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "Flutter WebRTC video renderer patch rollback failed: $_"
    }
    throw $originalError
  }
}

function New-WindowsVideoRendererFrameDiagnosticsBlock {
  param([Parameter(Mandatory = $true)][string]$Newline)

  $diagnosticsBlock = @'
namespace {
constexpr int kIntergalacticFrameHashGridX = 64;
constexpr int kIntergalacticFrameHashGridY = 36;
constexpr int kIntergalacticFrameHashChromaGridX = 32;
constexpr int kIntergalacticFrameHashChromaGridY = 18;
constexpr int kIntergalacticSourceFrameMarkerColumns = 8;
constexpr int kIntergalacticSourceFrameMarkerRows = 8;
constexpr int kIntergalacticSourceFrameMarkerIdBits = 16;
constexpr int kIntergalacticSourceFrameMarkerQpcBits = 48;
constexpr int kIntergalacticSourceFrameMarkerClassifiedCellsMin = 48;
constexpr int kIntergalacticSourceFrameMarkerLowLuma = 96;
constexpr int kIntergalacticSourceFrameMarkerHighLuma = 140;
constexpr int kIntergalacticSourceFrameMarkerBorderMinLuma = 90;
constexpr uint64_t kIntergalacticFnvOffset = 1469598103934665603ULL;
constexpr uint64_t kIntergalacticFnvPrime = 1099511628211ULL;

struct IntergalacticSourceFrameMarker {
  int marker_id = 0;
  uint64_t source_qpc_low48 = 0;
  bool source_qpc_available = false;
};

int ClampIntergalacticFrameHashIndex(int value, int max_value) {
  if (value < 0) {
    return 0;
  }
  if (value > max_value) {
    return max_value;
  }
  return value;
}

int AverageIntergalacticLumaRegion(const uint8_t* plane,
                                   int width,
                                   int height,
                                   int stride,
                                   int x0,
                                   int y0,
                                   int x1,
                                   int y1) {
  if (!plane || width <= 0 || height <= 0 || stride <= 0) {
    return -1;
  }
  x0 = ClampIntergalacticFrameHashIndex(x0, width - 1);
  y0 = ClampIntergalacticFrameHashIndex(y0, height - 1);
  x1 = ClampIntergalacticFrameHashIndex(x1, width);
  y1 = ClampIntergalacticFrameHashIndex(y1, height);
  if (x1 <= x0 || y1 <= y0) {
    return -1;
  }

  const int step_x = std::max(1, (x1 - x0) / 8);
  const int step_y = std::max(1, (y1 - y0) / 8);
  uint64_t sum = 0;
  int count = 0;
  for (int y = y0; y < y1; y += step_y) {
    const uint8_t* row = plane + (static_cast<size_t>(y) * stride);
    for (int x = x0; x < x1; x += step_x) {
      sum += row[x];
      ++count;
    }
  }
  return count > 0 ? static_cast<int>(sum / count) : -1;
}

IntergalacticSourceFrameMarker DecodeIntergalacticSourceFrameMarker(
    scoped_refptr<RTCVideoFrame> frame) {
  IntergalacticSourceFrameMarker marker;
  if (!frame.get() || frame->width() < 96 || frame->height() < 48) {
    return marker;
  }

  const uint8_t* y_plane = frame->DataY();
  const int stride_y = frame->StrideY();
  if (!y_plane || stride_y <= 0) {
    return marker;
  }

  const int width = frame->width();
  const int height = frame->height();
  const int marker_width = std::min(width, std::max(96, (width * 16) / 100));
  const int marker_height = std::min(height, std::max(48, (height * 14) / 100));
  const int margin_x = std::max(4, (marker_width * 10) / 100);
  const int margin_y = std::max(4, (marker_height * 18) / 100);
  const int border = std::max(2, (marker_height * 4) / 100);
  const int cell_width =
      (marker_width - (2 * margin_x)) / kIntergalacticSourceFrameMarkerColumns;
  const int cell_height =
      (marker_height - (2 * margin_y)) / kIntergalacticSourceFrameMarkerRows;
  if (cell_width <= 0 || cell_height <= 0) {
    return marker;
  }

  const int border_luma = AverageIntergalacticLumaRegion(
      y_plane, width, height, stride_y, border, 0, marker_width - border,
      border);
  if (border_luma < kIntergalacticSourceFrameMarkerBorderMinLuma) {
    return marker;
  }

  uint64_t marker_bits = 0;
  int classified_cells = 0;
  for (int row = 0; row < kIntergalacticSourceFrameMarkerRows; ++row) {
    for (int column = 0; column < kIntergalacticSourceFrameMarkerColumns;
         ++column) {
      const int center_x = margin_x + (column * cell_width) + cell_width / 2;
      const int center_y = margin_y + (row * cell_height) + cell_height / 2;
      const int half_x = std::max(1, cell_width / 5);
      const int half_y = std::max(1, cell_height / 5);
      const int luma = AverageIntergalacticLumaRegion(
          y_plane, width, height, stride_y, center_x - half_x,
          center_y - half_y, center_x + half_x + 1, center_y + half_y + 1);
      if (luma < 0) {
        continue;
      }
      if (luma >= kIntergalacticSourceFrameMarkerHighLuma) {
        marker_bits |= 1ULL << (row * kIntergalacticSourceFrameMarkerColumns +
                                column);
        ++classified_cells;
      } else if (luma <= kIntergalacticSourceFrameMarkerLowLuma) {
        ++classified_cells;
      } else if (luma >= 128) {
        marker_bits |= 1ULL << (row * kIntergalacticSourceFrameMarkerColumns +
                                column);
      }
    }
  }

  if (classified_cells < kIntergalacticSourceFrameMarkerClassifiedCellsMin ||
      marker_bits == 0) {
    return marker;
  }

  const uint64_t marker_id_bits =
      marker_bits & ((1ULL << kIntergalacticSourceFrameMarkerIdBits) - 1ULL);
  if (marker_id_bits == 0 || marker_id_bits > 65535ULL) {
    return marker;
  }
  marker.marker_id = static_cast<int>(marker_id_bits);
  marker.source_qpc_low48 = marker_bits >> kIntergalacticSourceFrameMarkerIdBits;
  marker.source_qpc_available = marker.source_qpc_low48 != 0;
  return marker;
}

#if defined(_WIN32)
int64_t ExpandIntergalacticSourceQpc(uint64_t source_qpc_low48,
                                     int64_t stage_qpc) {
  if (source_qpc_low48 == 0 || stage_qpc <= 0) {
    return 0;
  }
  constexpr uint64_t kQpcLow48Mask =
      (1ULL << kIntergalacticSourceFrameMarkerQpcBits) - 1ULL;
  constexpr uint64_t kQpcLow48Range =
      1ULL << kIntergalacticSourceFrameMarkerQpcBits;
  constexpr uint64_t kQpcLow48HalfRange =
      1ULL << (kIntergalacticSourceFrameMarkerQpcBits - 1);
  const uint64_t stage = static_cast<uint64_t>(stage_qpc);
  uint64_t candidate = (stage & ~kQpcLow48Mask) |
                       (source_qpc_low48 & kQpcLow48Mask);
  if (candidate > stage + kQpcLow48HalfRange) {
    candidate -= kQpcLow48Range;
  } else if (candidate + kQpcLow48HalfRange < stage) {
    candidate += kQpcLow48Range;
  }
  return static_cast<int64_t>(candidate);
}

double IntergalacticQpcDeltaMs(int64_t start_qpc, int64_t end_qpc) {
  if (start_qpc <= 0 || end_qpc <= start_qpc) {
    return 0.0;
  }
  LARGE_INTEGER frequency{};
  QueryPerformanceFrequency(&frequency);
  if (frequency.QuadPart <= 0) {
    return 0.0;
  }
  return static_cast<double>(end_qpc - start_qpc) * 1000.0 /
         static_cast<double>(frequency.QuadPart);
}
#endif

void HashIntergalacticPlaneSamples(uint64_t* hash,
                                   const uint8_t* plane,
                                   int width,
                                   int height,
                                   int stride,
                                   int grid_x,
                                   int grid_y) {
  if (!hash || !plane || width <= 0 || height <= 0 || stride <= 0 ||
      grid_x <= 0 || grid_y <= 0) {
    return;
  }
  for (int gy = 0; gy < grid_y; ++gy) {
    const int y = ClampIntergalacticFrameHashIndex(
        ((gy * 2 + 1) * height) / (grid_y * 2), height - 1);
    const uint8_t* row = plane + (static_cast<size_t>(y) * stride);
    for (int gx = 0; gx < grid_x; ++gx) {
      const int x = ClampIntergalacticFrameHashIndex(
          ((gx * 2 + 1) * width) / (grid_x * 2), width - 1);
      *hash ^= static_cast<uint64_t>(row[x]);
      *hash *= kIntergalacticFnvPrime;
    }
  }
}
}  // namespace

void FlutterVideoRenderer::SetFrameDiagnosticsEnabled(bool enabled) {
  frame_diagnostics_enabled_.store(enabled);
  if (enabled) {
    frame_diagnostics_sequence_.store(0);
  }
}

uint64_t FlutterVideoRenderer::HashFrameSampledPlanes(
    scoped_refptr<RTCVideoFrame> frame) const {
  if (!frame.get() || frame->width() <= 0 || frame->height() <= 0) {
    return 0;
  }
  const uint8_t* y_plane = frame->DataY();
  const uint8_t* u_plane = frame->DataU();
  const uint8_t* v_plane = frame->DataV();
  const int stride_y = frame->StrideY();
  const int stride_u = frame->StrideU();
  const int stride_v = frame->StrideV();
  if (!y_plane || stride_y <= 0) {
    return 0;
  }

  const int width = frame->width();
  const int height = frame->height();
  const int chroma_width = (width + 1) / 2;
  const int chroma_height = (height + 1) / 2;
  uint64_t hash = kIntergalacticFnvOffset;
  HashIntergalacticPlaneSamples(&hash, y_plane, width, height, stride_y,
                                kIntergalacticFrameHashGridX,
                                kIntergalacticFrameHashGridY);
  HashIntergalacticPlaneSamples(&hash, u_plane, chroma_width, chroma_height,
                                stride_u,
                                kIntergalacticFrameHashChromaGridX,
                                kIntergalacticFrameHashChromaGridY);
  HashIntergalacticPlaneSamples(&hash, v_plane, chroma_width, chroma_height,
                                stride_v,
                                kIntergalacticFrameHashChromaGridX,
                                kIntergalacticFrameHashChromaGridY);
  return hash;
}

void FlutterVideoRenderer::EmitFrameDiagnostics(
    scoped_refptr<RTCVideoFrame> frame) {
  if (!frame_diagnostics_enabled_.load()) {
    return;
  }

  const int64_t sequence = frame_diagnostics_sequence_.fetch_add(1) + 1;
  const auto now = std::chrono::system_clock::now();
  const auto timestamp_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          now.time_since_epoch())
          .count();
  const uint64_t sampled_plane_hash = HashFrameSampledPlanes(frame);
  const uint16_t frame_id = frame->id();
  const IntergalacticSourceFrameMarker source_frame_marker =
      DecodeIntergalacticSourceFrameMarker(frame);
#if defined(_WIN32)
  LARGE_INTEGER stage_qpc{};
  QueryPerformanceCounter(&stage_qpc);
  const int64_t source_qpc =
      source_frame_marker.source_qpc_available
          ? ExpandIntergalacticSourceQpc(source_frame_marker.source_qpc_low48,
                                         stage_qpc.QuadPart)
          : 0;
#endif

  EncodableMap params;
  params[EncodableValue("event")] =
      EncodableValue("didIntergalacticFrameRendered");
  params[EncodableValue("id")] = EncodableValue(texture_id_);
  params[EncodableValue("sequence")] = EncodableValue(sequence);
  if (frame_id != 0) {
    params[EncodableValue("frame_id")] =
        EncodableValue(static_cast<int32_t>(frame_id));
  }
  if (source_frame_marker.marker_id > 0) {
    params[EncodableValue("source_frame_marker_id")] =
        EncodableValue(static_cast<int32_t>(source_frame_marker.marker_id));
  }
#if defined(_WIN32)
  params[EncodableValue("stage_qpc")] =
      EncodableValue(static_cast<int64_t>(stage_qpc.QuadPart));
  if (source_qpc > 0) {
    params[EncodableValue("source_qpc")] =
        EncodableValue(static_cast<int64_t>(source_qpc));
    params[EncodableValue("frame_age_ms")] =
        EncodableValue(IntergalacticQpcDeltaMs(source_qpc, stage_qpc.QuadPart));
  }
#endif
  params[EncodableValue("timestamp_unix_ms")] =
      EncodableValue(static_cast<int64_t>(timestamp_ms));
  params[EncodableValue("width")] = EncodableValue((int32_t)frame->width());
  params[EncodableValue("height")] = EncodableValue((int32_t)frame->height());
  params[EncodableValue("rotation")] =
      EncodableValue((int32_t)frame->rotation());
  params[EncodableValue("hash_algorithm")] =
      EncodableValue("fnv1a-y64x36-uv32x18-native-renderer-onframe");
  params[EncodableValue("sample_grid")] = EncodableValue("y64x36-uv32x18");
  params[EncodableValue("luma_hash")] =
      EncodableValue(std::to_string(sampled_plane_hash));
  // Inter Galactic: native renderer frame diagnostics. These events are
  // opt-in per texture and are never cached, so a disabled probe does not build
  // an event backlog on normal video renderers.
  event_channel_->Success(EncodableValue(params), false);
}

'@

  return $diagnosticsBlock -replace "\r?\n", $Newline
}

function Install-WindowsVideoRendererFrameDiagnosticsPatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $backups = New-Object System.Collections.Generic.List[string]

  $rendererDart = Join-Path $PackageRoot "lib\src\native\rtc_video_renderer_impl.dart"
  $rendererHeader = Join-Path $PackageRoot "common\cpp\include\flutter_video_renderer.h"
  $rendererSource = Join-Path $PackageRoot "common\cpp\src\flutter_video_renderer.cc"
  $webrtcSource = Join-Path $PackageRoot "common\cpp\src\flutter_webrtc.cc"

  foreach ($target in @($rendererDart, $rendererHeader, $rendererSource, $webrtcSource)) {
    Assert-PathInside -Parent $PackageRoot -Child $target
    if (-not (Test-Path -LiteralPath $target)) {
      throw "Flutter WebRTC renderer diagnostics patch source not found: $target"
    }
  }

  $dartSource = [System.IO.File]::ReadAllText($rendererDart)
  $headerSource = [System.IO.File]::ReadAllText($rendererHeader)
  $rendererCcSource = [System.IO.File]::ReadAllText($rendererSource)
  $webrtcCcSource = [System.IO.File]::ReadAllText($webrtcSource)

  $marker = "onIntergalacticFrameRendered"
  $nativeMarker = "Inter Galactic: native renderer frame diagnostics"
  $diagnosticsAfterTextureMarker =
    "Inter Galactic: emit diagnostics after texture handoff"
  $frameIdMarker = 'EncodableValue("frame_id")'
  $sourceFrameMarkerIdMarker = 'EncodableValue("source_frame_marker_id")'
  $sourceQpcMarker = 'EncodableValue("source_qpc")'
  $windowsMinMaxGuardMarker = "#define NOMINMAX"
  if ($dartSource.Contains($marker) -and
      $headerSource.Contains("SetFrameDiagnosticsEnabled") -and
      $headerSource.Contains("VideoRendererSetFrameDiagnostics") -and
      $rendererCcSource.Contains($nativeMarker) -and
      $rendererCcSource.Contains($frameIdMarker) -and
      $rendererCcSource.Contains($sourceFrameMarkerIdMarker) -and
      $rendererCcSource.Contains($sourceQpcMarker) -and
      $rendererCcSource.Contains($windowsMinMaxGuardMarker) -and
      $rendererCcSource.Contains($diagnosticsAfterTextureMarker) -and
      $webrtcCcSource.Contains("intergalacticVideoRendererSetFrameDiagnostics")) {
    Write-Host "Flutter WebRTC video renderer diagnostics patch: already applied."
    return @()
  }

  try {
    if (-not $dartSource.Contains($marker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererDart `
        -Backup "$rendererDart.intergalactic-frame-diagnostics-backup" `
        -Source $dartSource
      $backups.Add($backup) | Out-Null
      $nl = if ($dartSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      $dartSource = Update-SourceText `
        -Source $dartSource `
        -Pattern '  Function\? onFirstFrameRendered;\r?\n' `
        -Replacement "  Function? onFirstFrameRendered;${nl}${nl}  Function? onIntergalacticFrameRendered;${nl}" `
        -Description "Dart renderer frame diagnostics callback"
      $dartSource = Update-SourceText `
        -Source $dartSource `
        -Pattern "      case 'didFirstFrameRendered':\r?\n        value = value.copyWith\(renderVideo: renderVideo\);\r?\n        onFirstFrameRendered\?\.call\(\);\r?\n        break;\r?\n" `
        -Replacement "      case 'didFirstFrameRendered':${nl}        value = value.copyWith(renderVideo: renderVideo);${nl}        onFirstFrameRendered?.call();${nl}        break;${nl}      case 'didIntergalacticFrameRendered':${nl}        onIntergalacticFrameRendered?.call(map);${nl}        break;${nl}" `
        -Description "Dart renderer frame diagnostics event"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererDart, $dartSource, $utf8NoBom)
    }

    if (-not $headerSource.Contains("SetFrameDiagnosticsEnabled")) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererHeader `
        -Backup "$rendererHeader.intergalactic-frame-diagnostics-backup" `
        -Source $headerSource
      $backups.Add($backup) | Out-Null
      $nl = if ($headerSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      if (-not $headerSource.Contains("#include <atomic>")) {
        $headerSource = Update-SourceText `
          -Source $headerSource `
          -Pattern '#include <mutex>\r?\n' `
          -Replacement "#include <atomic>${nl}#include <cstdint>${nl}#include <mutex>${nl}" `
          -Description "video renderer diagnostics includes"
      }
      $headerSource = Update-SourceText `
        -Source $headerSource `
        -Pattern '  virtual void OnFrame\(scoped_refptr<RTCVideoFrame> frame\) override;\r?\n' `
        -Replacement "  virtual void OnFrame(scoped_refptr<RTCVideoFrame> frame) override;${nl}${nl}  void SetFrameDiagnosticsEnabled(bool enabled);${nl}" `
        -Description "video renderer diagnostics public method"
      $headerSource = Update-SourceText `
        -Source $headerSource `
        -Pattern '  FrameSize last_frame_size_ = \{0, 0\};\r?\n' `
        -Replacement "  void EmitFrameDiagnostics(scoped_refptr<RTCVideoFrame> frame);${nl}  uint64_t HashFrameSampledPlanes(scoped_refptr<RTCVideoFrame> frame) const;${nl}${nl}  FrameSize last_frame_size_ = {0, 0};${nl}" `
        -Description "video renderer diagnostics private methods"
      $headerSource = Update-SourceText `
        -Source $headerSource `
        -Pattern '  RTCVideoFrame::VideoRotation rotation_ = RTCVideoFrame::kVideoRotation_0;\r?\n' `
        -Replacement "  std::atomic<bool> frame_diagnostics_enabled_{false};${nl}  std::atomic<int64_t> frame_diagnostics_sequence_{0};${nl}  RTCVideoFrame::VideoRotation rotation_ = RTCVideoFrame::kVideoRotation_0;${nl}" `
        -Description "video renderer diagnostics state"
      $headerSource = Update-SourceText `
        -Source $headerSource `
        -Pattern '  void VideoRendererDispose\(int64_t texture_id,\r?\n                            std::unique_ptr<MethodResultProxy> result\);\r?\n' `
        -Replacement "  void VideoRendererSetFrameDiagnostics(${nl}      int64_t texture_id,${nl}      bool enabled,${nl}      std::unique_ptr<MethodResultProxy> result);${nl}${nl}  void VideoRendererDispose(int64_t texture_id,${nl}                            std::unique_ptr<MethodResultProxy> result);${nl}" `
        -Description "video renderer diagnostics manager declaration"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererHeader, $headerSource, $utf8NoBom)
    }
    if (-not $headerSource.Contains("VideoRendererSetFrameDiagnostics")) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererHeader `
        -Backup "$rendererHeader.intergalactic-frame-diagnostics-backup" `
        -Source $headerSource
      $backups.Add($backup) | Out-Null
      $nl = if ($headerSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      $headerSource = Update-SourceText `
        -Source $headerSource `
        -Pattern '  void VideoRendererDispose\(int64_t texture_id,\r?\n                            std::unique_ptr<MethodResultProxy> result\);\r?\n' `
        -Replacement "  void VideoRendererSetFrameDiagnostics(${nl}      int64_t texture_id,${nl}      bool enabled,${nl}      std::unique_ptr<MethodResultProxy> result);${nl}${nl}  void VideoRendererDispose(int64_t texture_id,${nl}                            std::unique_ptr<MethodResultProxy> result);${nl}" `
        -Description "video renderer diagnostics manager declaration"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererHeader, $headerSource, $utf8NoBom)
    }

    if ($rendererCcSource.Contains($nativeMarker) -and
        -not $rendererCcSource.Contains($windowsMinMaxGuardMarker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererSource `
        -Backup "$rendererSource.intergalactic-frame-diagnostics-nominmax-backup" `
        -Source $rendererCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($rendererCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern '#include "flutter_video_renderer\.h"\r?\n' `
        -Replacement "#ifndef NOMINMAX${nl}#define NOMINMAX${nl}#endif${nl}${nl}#include `"flutter_video_renderer.h`"${nl}" `
        -Description "video renderer diagnostics NOMINMAX guard"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererSource, $rendererCcSource, $utf8NoBom)
    }

    if (-not $rendererCcSource.Contains($nativeMarker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererSource `
        -Backup "$rendererSource.intergalactic-frame-diagnostics-backup" `
        -Source $rendererCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($rendererCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      if (-not $rendererCcSource.Contains("#include <chrono>")) {
        $rendererCcSource = Update-SourceText `
          -Source $rendererCcSource `
          -Pattern '#include "flutter_video_renderer\.h"\r?\n' `
          -Replacement "#ifndef NOMINMAX${nl}#define NOMINMAX${nl}#endif${nl}${nl}#include `"flutter_video_renderer.h`"${nl}${nl}#include <algorithm>${nl}#include <chrono>${nl}#include <cstdint>${nl}#include <string>${nl}${nl}#if defined(_WIN32)${nl}#include <windows.h>${nl}#endif${nl}" `
          -Description "video renderer diagnostics source includes"
      }
      $diagnosticsBlock = @'
namespace {
constexpr int kIntergalacticFrameHashGridX = 64;
constexpr int kIntergalacticFrameHashGridY = 36;
constexpr int kIntergalacticFrameHashChromaGridX = 32;
constexpr int kIntergalacticFrameHashChromaGridY = 18;
constexpr uint64_t kIntergalacticFnvOffset = 1469598103934665603ULL;
constexpr uint64_t kIntergalacticFnvPrime = 1099511628211ULL;

int ClampIntergalacticFrameHashIndex(int value, int max_value) {
  if (value < 0) {
    return 0;
  }
  if (value > max_value) {
    return max_value;
  }
  return value;
}

void HashIntergalacticPlaneSamples(uint64_t* hash,
                                   const uint8_t* plane,
                                   int width,
                                   int height,
                                   int stride,
                                   int grid_x,
                                   int grid_y) {
  if (!hash || !plane || width <= 0 || height <= 0 || stride <= 0 ||
      grid_x <= 0 || grid_y <= 0) {
    return;
  }
  for (int gy = 0; gy < grid_y; ++gy) {
    const int y = ClampIntergalacticFrameHashIndex(
        ((gy * 2 + 1) * height) / (grid_y * 2), height - 1);
    const uint8_t* row = plane + (static_cast<size_t>(y) * stride);
    for (int gx = 0; gx < grid_x; ++gx) {
      const int x = ClampIntergalacticFrameHashIndex(
          ((gx * 2 + 1) * width) / (grid_x * 2), width - 1);
      *hash ^= static_cast<uint64_t>(row[x]);
      *hash *= kIntergalacticFnvPrime;
    }
  }
}
}  // namespace

void FlutterVideoRenderer::SetFrameDiagnosticsEnabled(bool enabled) {
  frame_diagnostics_enabled_.store(enabled);
  if (enabled) {
    frame_diagnostics_sequence_.store(0);
  }
}

uint64_t FlutterVideoRenderer::HashFrameSampledPlanes(
    scoped_refptr<RTCVideoFrame> frame) const {
  if (!frame.get() || frame->width() <= 0 || frame->height() <= 0) {
    return 0;
  }
  const uint8_t* y_plane = frame->DataY();
  const uint8_t* u_plane = frame->DataU();
  const uint8_t* v_plane = frame->DataV();
  const int stride_y = frame->StrideY();
  const int stride_u = frame->StrideU();
  const int stride_v = frame->StrideV();
  if (!y_plane || stride_y <= 0) {
    return 0;
  }

  const int width = frame->width();
  const int height = frame->height();
  const int chroma_width = (width + 1) / 2;
  const int chroma_height = (height + 1) / 2;
  uint64_t hash = kIntergalacticFnvOffset;
  HashIntergalacticPlaneSamples(&hash, y_plane, width, height, stride_y,
                                kIntergalacticFrameHashGridX,
                                kIntergalacticFrameHashGridY);
  HashIntergalacticPlaneSamples(&hash, u_plane, chroma_width, chroma_height,
                                stride_u,
                                kIntergalacticFrameHashChromaGridX,
                                kIntergalacticFrameHashChromaGridY);
  HashIntergalacticPlaneSamples(&hash, v_plane, chroma_width, chroma_height,
                                stride_v,
                                kIntergalacticFrameHashChromaGridX,
                                kIntergalacticFrameHashChromaGridY);
  return hash;
}

void FlutterVideoRenderer::EmitFrameDiagnostics(
    scoped_refptr<RTCVideoFrame> frame) {
  if (!frame_diagnostics_enabled_.load()) {
    return;
  }

  const int64_t sequence = frame_diagnostics_sequence_.fetch_add(1) + 1;
  const auto now = std::chrono::system_clock::now();
  const auto timestamp_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          now.time_since_epoch())
          .count();
  const uint64_t sampled_plane_hash = HashFrameSampledPlanes(frame);
  const uint16_t frame_id = frame->id();
#if defined(_WIN32)
  LARGE_INTEGER stage_qpc{};
  QueryPerformanceCounter(&stage_qpc);
#endif

  EncodableMap params;
  params[EncodableValue("event")] =
      EncodableValue("didIntergalacticFrameRendered");
  params[EncodableValue("id")] = EncodableValue(texture_id_);
  params[EncodableValue("sequence")] = EncodableValue(sequence);
  if (frame_id != 0) {
    params[EncodableValue("frame_id")] =
        EncodableValue(static_cast<int32_t>(frame_id));
  }
#if defined(_WIN32)
  params[EncodableValue("stage_qpc")] =
      EncodableValue(static_cast<int64_t>(stage_qpc.QuadPart));
#endif
  params[EncodableValue("timestamp_unix_ms")] =
      EncodableValue(static_cast<int64_t>(timestamp_ms));
  params[EncodableValue("width")] = EncodableValue((int32_t)frame->width());
  params[EncodableValue("height")] = EncodableValue((int32_t)frame->height());
  params[EncodableValue("rotation")] =
      EncodableValue((int32_t)frame->rotation());
  params[EncodableValue("hash_algorithm")] =
      EncodableValue("fnv1a-y64x36-uv32x18-native-renderer-onframe");
  params[EncodableValue("sample_grid")] = EncodableValue("y64x36-uv32x18");
  params[EncodableValue("luma_hash")] =
      EncodableValue(std::to_string(sampled_plane_hash));
  // Inter Galactic: native renderer frame diagnostics. These events are
  // opt-in per texture and are never cached, so a disabled probe does not build
  // an event backlog on normal video renderers.
  event_channel_->Success(EncodableValue(params), false);
}

'@
      $diagnosticsBlock = New-WindowsVideoRendererFrameDiagnosticsBlock `
        -Newline $nl
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern 'namespace flutter_webrtc_plugin \{\r?\n\r?\n' `
        -Replacement "namespace flutter_webrtc_plugin {${nl}${nl}$diagnosticsBlock" `
        -Description "video renderer native frame diagnostics implementation"
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern '  mutex_\.lock\(\);\r?\n  frame_ = frame;\r?\n  mutex_\.unlock\(\);\r?\n  registrar_->MarkTextureFrameAvailable\(texture_id_\);\r?\n' `
        -Replacement "  mutex_.lock();${nl}  frame_ = frame;${nl}  mutex_.unlock();${nl}  registrar_->MarkTextureFrameAvailable(texture_id_);${nl}  // Inter Galactic: emit diagnostics after texture handoff so probes${nl}  // do not delay the receiver presentation path they are measuring.${nl}  EmitFrameDiagnostics(frame);${nl}" `
        -Description "video renderer native frame diagnostics OnFrame hook"
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern 'void FlutterVideoRendererManager::VideoRendererDispose\(\r?\n    int64_t texture_id,\r?\n    std::unique_ptr<MethodResultProxy> result\) \{\r?\n' `
        -Replacement "void FlutterVideoRendererManager::VideoRendererSetFrameDiagnostics(${nl}    int64_t texture_id,${nl}    bool enabled,${nl}    std::unique_ptr<MethodResultProxy> result) {${nl}  auto it = renderers_.find(texture_id);${nl}  if (it == renderers_.end()) {${nl}    result->Error(`"VideoRendererFrameDiagnosticsFailed`",${nl}                  `"VideoRendererSetFrameDiagnostics() texture not found!`");${nl}    return;${nl}  }${nl}  it->second->SetFrameDiagnosticsEnabled(enabled);${nl}  result->Success();${nl}}${nl}${nl}void FlutterVideoRendererManager::VideoRendererDispose(${nl}    int64_t texture_id,${nl}    std::unique_ptr<MethodResultProxy> result) {${nl}" `
        -Description "video renderer diagnostics manager method"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererSource, $rendererCcSource, $utf8NoBom)
    }
    if ($rendererCcSource.Contains($nativeMarker) -and
        -not $rendererCcSource.Contains($diagnosticsAfterTextureMarker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererSource `
        -Backup "$rendererSource.intergalactic-frame-diagnostics-order-backup" `
        -Source $rendererCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($rendererCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern '  EmitFrameDiagnostics\(frame\);\r?\n  mutex_\.lock\(\);\r?\n  frame_ = frame;\r?\n  mutex_\.unlock\(\);\r?\n  registrar_->MarkTextureFrameAvailable\(texture_id_\);\r?\n' `
        -Replacement "  mutex_.lock();${nl}  frame_ = frame;${nl}  mutex_.unlock();${nl}  registrar_->MarkTextureFrameAvailable(texture_id_);${nl}  // Inter Galactic: emit diagnostics after texture handoff so probes${nl}  // do not delay the receiver presentation path they are measuring.${nl}  EmitFrameDiagnostics(frame);${nl}" `
        -Description "video renderer diagnostics after texture handoff"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererSource, $rendererCcSource, $utf8NoBom)
    }
    if ($rendererCcSource.Contains($nativeMarker) -and
        -not $rendererCcSource.Contains($sourceQpcMarker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererSource `
        -Backup "$rendererSource.intergalactic-frame-diagnostics-marker-backup" `
        -Source $rendererCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($rendererCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      if (-not $rendererCcSource.Contains("#include <windows.h>")) {
        $rendererCcSource = Update-SourceText `
          -Source $rendererCcSource `
          -Pattern '#include <string>\r?\n' `
          -Replacement "#include <string>${nl}${nl}#if defined(_WIN32)${nl}#include <windows.h>${nl}#endif${nl}" `
          -Description "video renderer diagnostics Windows QPC include"
      }
      $diagnosticsBlock = New-WindowsVideoRendererFrameDiagnosticsBlock `
        -Newline $nl
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern 'namespace \{\r?\nconstexpr int kIntergalacticFrameHashGridX[\s\S]*?void FlutterVideoRenderer::EmitFrameDiagnostics\(\r?\n    scoped_refptr<RTCVideoFrame> frame\) \{[\s\S]*?event_channel_->Success\(EncodableValue\(params\), false\);\r?\n\}\r?\n' `
        -Replacement $diagnosticsBlock `
        -Description "video renderer native frame diagnostics source marker refresh"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererSource, $rendererCcSource, $utf8NoBom)
    }
    if ($rendererCcSource.Contains($nativeMarker) -and -not $rendererCcSource.Contains($frameIdMarker)) {
      $backup = New-IntergalacticPatchBackup `
        -Target $rendererSource `
        -Backup "$rendererSource.intergalactic-frame-diagnostics-lineage-backup" `
        -Source $rendererCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($rendererCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      if (-not $rendererCcSource.Contains("#include <windows.h>")) {
        $rendererCcSource = Update-SourceText `
          -Source $rendererCcSource `
          -Pattern '#include <string>\r?\n' `
          -Replacement "#include <string>${nl}${nl}#if defined(_WIN32)${nl}#include <windows.h>${nl}#endif${nl}" `
          -Description "video renderer diagnostics Windows QPC include"
      }
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern '  const uint64_t sampled_plane_hash = HashFrameSampledPlanes\(frame\);\r?\n\r?\n  EncodableMap params;' `
        -Replacement "  const uint64_t sampled_plane_hash = HashFrameSampledPlanes(frame);${nl}  const uint16_t frame_id = frame->id();${nl}#if defined(_WIN32)${nl}  LARGE_INTEGER stage_qpc{};${nl}  QueryPerformanceCounter(&stage_qpc);${nl}#endif${nl}${nl}  EncodableMap params;" `
        -Description "video renderer diagnostics source frame id state"
      $rendererCcSource = Update-SourceText `
        -Source $rendererCcSource `
        -Pattern '  params\[EncodableValue\("sequence"\)\] = EncodableValue\(sequence\);\r?\n  params\[EncodableValue\("timestamp_unix_ms"\)\] =' `
        -Replacement "  params[EncodableValue(`"sequence`")] = EncodableValue(sequence);${nl}  if (frame_id != 0) {${nl}    params[EncodableValue(`"frame_id`")] =${nl}        EncodableValue(static_cast<int32_t>(frame_id));${nl}  }${nl}#if defined(_WIN32)${nl}  params[EncodableValue(`"stage_qpc`")] =${nl}      EncodableValue(static_cast<int64_t>(stage_qpc.QuadPart));${nl}#endif${nl}  params[EncodableValue(`"timestamp_unix_ms`")] =" `
        -Description "video renderer diagnostics source frame id event fields"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($rendererSource, $rendererCcSource, $utf8NoBom)
    }

    if (-not $webrtcCcSource.Contains("intergalacticVideoRendererSetFrameDiagnostics")) {
      $backup = New-IntergalacticPatchBackup `
        -Target $webrtcSource `
        -Backup "$webrtcSource.intergalactic-frame-diagnostics-backup" `
        -Source $webrtcCcSource
      $backups.Add($backup) | Out-Null
      $nl = if ($webrtcCcSource.Contains("`r`n")) { "`r`n" } else { "`n" }
      $handler = "    VideoRendererSetSrcObject(texture_id, stream_id, owner_tag, track_id);${nl}    result->Success();${nl}  } else if (method_call.method_name().compare(${nl}                 `"intergalacticVideoRendererSetFrameDiagnostics`") == 0) {${nl}    if (!method_call.arguments()) {${nl}      result->Error(`"Bad Arguments`", `"Null constraints arguments received`");${nl}      return;${nl}    }${nl}    const EncodableMap params =${nl}        GetValue<EncodableMap>(*method_call.arguments());${nl}    int64_t texture_id = findLongInt(params, `"textureId`");${nl}    bool enabled = findBoolean(params, `"enabled`");${nl}    VideoRendererSetFrameDiagnostics(texture_id, enabled, std::move(result));${nl}  } else if (method_call.method_name().compare(${nl}                 `"mediaStreamTrackSwitchCamera`") == 0) {"
      $webrtcCcSource = Update-SourceText `
        -Source $webrtcCcSource `
        -Pattern '    VideoRendererSetSrcObject\(texture_id, stream_id, owner_tag, track_id\);\r?\n    result->Success\(\);\r?\n  \} else if \(method_call\.method_name\(\)\.compare\(\r?\n                 "mediaStreamTrackSwitchCamera"\) == 0\) \{' `
        -Replacement $handler `
        -Description "video renderer diagnostics method channel handler"
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($webrtcSource, $webrtcCcSource, $utf8NoBom)
    }
  } catch {
    $originalError = $_
    foreach ($backup in $backups) {
      try {
        if (Test-Path -LiteralPath $backup) {
          $target = Get-IntergalacticPatchBackupTarget -Backup $backup
          Copy-Item -LiteralPath $backup -Destination $target -Force
          Remove-Item -LiteralPath $backup -Force
        }
      } catch {
        Write-Warning "Flutter WebRTC video renderer diagnostics rollback failed: $_"
      }
    }
    throw $originalError
  }

  Write-Host "Flutter WebRTC video renderer diagnostics patch: installed native frame tap."
  return $backups.ToArray()
}

function Install-WindowsDesktopCaptureConstraintPatch {
  param([Parameter(Mandatory = $true)][string]$PackageRoot)

  $target = Join-Path $PackageRoot "common\cpp\src\flutter_screen_capture.cc"
  $backup = "$target.intergalactic-backup"
  Assert-PathInside -Parent $PackageRoot -Child $target
  Assert-PathInside -Parent $PackageRoot -Child $backup

  if (-not (Test-Path -LiteralPath $target)) {
    throw "Flutter WebRTC desktop capture source not found: $target"
  }

  $source = [System.IO.File]::ReadAllText($target)
  $nl = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
  $oldCropPatchMarker = "Inter Galactic: honor desktop capture dimensions"
  $fullFramePatchMarker = "Inter Galactic: keep desktop capture full-frame"
  $scalerPatchMarker = "Inter Galactic: scale desktop capture full-frame"
  $bridgeLogMarker = "Inter Galactic desktop capture bridge start"

  if ($source.Contains($scalerPatchMarker)) {
    $hasBridgeLog = $source.Contains($bridgeLogMarker)
    $hasBackendOverride = $source.Contains("intergalacticCaptureBackend") -and
        $source.Contains("SetWindowsCaptureBackendMode")
    $hasPacerOverride = $source.Contains("intergalacticCaptureFramePacing") -and
        $source.Contains("SetLatestFramePacingEnabled")
    $hasDirtyRegionOverride = $source.Contains("intergalacticCaptureDirtyRegion") -and
        $source.Contains("SetWindowsCaptureDirtyRegionMode")
    $hasWindowGdiOverride = $source.Contains("intergalacticWindowGdiMode") -and
        $source.Contains("SetWindowsWindowGdiCaptureMode")
    $hasGameCaptureBridge = $source.Contains("intergalacticGameCaptureProcessId") -and
        $source.Contains("intergalacticGameCaptureSourceMode") -and
        $source.Contains("use_dummy_nv12_live_sender") -and
        $source.Contains("Inter Galactic game capture WebRTC source start") -and
        $source.Contains("Inter Galactic: keep game capture stream registered")
    $hasObsoleteBridgeLogging =
        $source.Contains('#include "rtc_base/logging.h"') -or
        $source.Contains('RTC_LOG(LS_INFO) << "Inter Galactic desktop capture bridge start')

    if ($hasBridgeLog -and $hasBackendOverride -and $hasPacerOverride -and $hasDirtyRegionOverride -and $hasWindowGdiOverride -and $hasGameCaptureBridge -and -not $hasObsoleteBridgeLogging) {
      Write-Host "Flutter WebRTC capture patch: full-frame scaler marker already applied."
      return $null
    }

    $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

    try {
      $source = Add-WindowsDesktopCaptureBridgeLogging `
        -Source $source `
        -Newline $nl

      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
      Write-Host "Flutter WebRTC capture patch: added scaler bridge diagnostics."
      return $backup
    } catch {
      $originalError = $_
      try {
        if (Test-Path -LiteralPath $backup) {
          Copy-Item -LiteralPath $backup -Destination $target -Force
          Remove-Item -LiteralPath $backup -Force
        }
      } catch {
        Write-Warning "Flutter WebRTC capture diagnostics patch rollback failed: $_"
      }
      throw $originalError
    }
  }

  $backup = New-IntergalacticPatchBackup -Target $target -Backup $backup -Source $source

  try {
    if ($source.Contains($oldCropPatchMarker)) {
      $source = Update-SourceText `
        -Source $source `
        -Pattern '  double fps = 30\.0;\r?\n  uint32_t capture_width = 0;\r?\n  uint32_t capture_height = 0;\r?\n' `
        -Replacement "  double fps = 30.0;${nl}  uint32_t max_frame_width = 0;${nl}  uint32_t max_frame_height = 0;${nl}" `
        -Description "replace crop patch size variables"

      $source = Update-SourceText `
        -Source $source `
        -Pattern '    // Inter Galactic: honor desktop capture dimensions so gameplay\r?\n    // presets scale before frames reach the encoder\.\r?\n    int requested_width = findInt\(video, "width"\);\r?\n    int requested_height = findInt\(video, "height"\);\r?\n    if \(requested_width > 0\) \{\r?\n      capture_width = static_cast<uint32_t>\(requested_width\);\r?\n    \}\r?\n    if \(requested_height > 0\) \{\r?\n      capture_height = static_cast<uint32_t>\(requested_height\);\r?\n    \}\r?\n\r?\n    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
        -Replacement "    // Inter Galactic: scale desktop capture full-frame. Requested${nl}    // desktop dimensions are max pre-encode bounds; the native${nl}    // Start(x, y, w, h) overload crops and must not be used here.${nl}    int requested_width = findInt(video, `"width`");${nl}    int requested_height = findInt(video, `"height`");${nl}    if (requested_width > 0) {${nl}      max_frame_width = static_cast<uint32_t>(requested_width);${nl}    }${nl}    if (requested_height > 0) {${nl}      max_frame_height = static_cast<uint32_t>(requested_height);${nl}    }${nl}${nl}    const EncodableMap deviceId = findMap(video, `"deviceId`");${nl}" `
        -Description "replace crop patch top-level dimensions with scaler bounds"

      $source = Update-SourceText `
        -Source $source `
        -Pattern '      int requested_mandatory_width = findInt\(mandatory, "width"\);\r?\n      int requested_mandatory_height = findInt\(mandatory, "height"\);\r?\n      if \(capture_width == 0 && requested_mandatory_width > 0\) \{\r?\n        capture_width = static_cast<uint32_t>\(requested_mandatory_width\);\r?\n      \}\r?\n      if \(capture_height == 0 && requested_mandatory_height > 0\) \{\r?\n        capture_height = static_cast<uint32_t>\(requested_mandatory_height\);\r?\n      \}\r?\n      double frameRate = findDouble\(mandatory, "frameRate"\);\r?\n' `
        -Replacement "      int requested_mandatory_width = findInt(mandatory, `"width`");${nl}      int requested_mandatory_height = findInt(mandatory, `"height`");${nl}      if (max_frame_width == 0 && requested_mandatory_width > 0) {${nl}        max_frame_width = static_cast<uint32_t>(requested_mandatory_width);${nl}      }${nl}      if (max_frame_height == 0 && requested_mandatory_height > 0) {${nl}        max_frame_height = static_cast<uint32_t>(requested_mandatory_height);${nl}      }${nl}      double frameRate = findDouble(mandatory, `"frameRate`");${nl}" `
        -Description "replace crop patch mandatory dimensions with scaler bounds"

      $source = Update-SourceText `
        -Source $source `
        -Pattern '  if \(capture_width > 0 && capture_height > 0\) \{\r?\n    desktop_capturer->Start\(uint32_t\(fps\), 0, 0, capture_width,\r?\n                            capture_height\);\r?\n  \} else \{\r?\n    desktop_capturer->Start\(uint32_t\(fps\)\);\r?\n  \}\r?\n' `
        -Replacement "  if (max_frame_width > 0 && max_frame_height > 0) {${nl}    desktop_capturer->StartWithMaxFrameSize(uint32_t(fps), max_frame_width,${nl}                                            max_frame_height);${nl}  } else {${nl}    desktop_capturer->Start(uint32_t(fps));${nl}  }${nl}" `
        -Description "replace crop start with full-frame scaler start"
    } else {
      $source = Update-SourceText `
        -Source $source `
        -Pattern '  double fps = 30\.0;\r?\n' `
        -Replacement "  double fps = 30.0;${nl}  uint32_t max_frame_width = 0;${nl}  uint32_t max_frame_height = 0;${nl}" `
        -Description "capture scaler size variables"

      if ($source.Contains($fullFramePatchMarker)) {
        $source = Update-SourceText `
          -Source $source `
          -Pattern '    // Inter Galactic: keep desktop capture full-frame\. Requested\r?\n    // desktop dimensions are sender limits; the native Start\(x, y, w, h\)\r?\n    // overload crops a source region instead of scaling the full source\.\r?\n    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
          -Replacement "    // Inter Galactic: scale desktop capture full-frame. Requested${nl}    // desktop dimensions are max pre-encode bounds; the native${nl}    // Start(x, y, w, h) overload crops and must not be used here.${nl}    int requested_width = findInt(video, `"width`");${nl}    int requested_height = findInt(video, `"height`");${nl}    if (requested_width > 0) {${nl}      max_frame_width = static_cast<uint32_t>(requested_width);${nl}    }${nl}    if (requested_height > 0) {${nl}      max_frame_height = static_cast<uint32_t>(requested_height);${nl}    }${nl}${nl}    const EncodableMap deviceId = findMap(video, `"deviceId`");${nl}" `
          -Description "replace full-frame marker with scaler bounds"
      } else {
        $source = Update-SourceText `
          -Source $source `
          -Pattern '    const EncodableMap deviceId = findMap\(video, "deviceId"\);\r?\n' `
          -Replacement "    // Inter Galactic: scale desktop capture full-frame. Requested${nl}    // desktop dimensions are max pre-encode bounds; the native${nl}    // Start(x, y, w, h) overload crops and must not be used here.${nl}    int requested_width = findInt(video, `"width`");${nl}    int requested_height = findInt(video, `"height`");${nl}    if (requested_width > 0) {${nl}      max_frame_width = static_cast<uint32_t>(requested_width);${nl}    }${nl}    if (requested_height > 0) {${nl}      max_frame_height = static_cast<uint32_t>(requested_height);${nl}    }${nl}${nl}    const EncodableMap deviceId = findMap(video, `"deviceId`");${nl}" `
          -Description "top-level scaler bounds"
      }

      $source = Update-SourceText `
        -Source $source `
        -Pattern '      double frameRate = findDouble\(mandatory, "frameRate"\);\r?\n' `
        -Replacement "      int requested_mandatory_width = findInt(mandatory, `"width`");${nl}      int requested_mandatory_height = findInt(mandatory, `"height`");${nl}      if (max_frame_width == 0 && requested_mandatory_width > 0) {${nl}        max_frame_width = static_cast<uint32_t>(requested_mandatory_width);${nl}      }${nl}      if (max_frame_height == 0 && requested_mandatory_height > 0) {${nl}        max_frame_height = static_cast<uint32_t>(requested_mandatory_height);${nl}      }${nl}      double frameRate = findDouble(mandatory, `"frameRate`");${nl}" `
        -Description "mandatory scaler bounds"

      if ($source.Contains($fullFramePatchMarker)) {
        $source = Update-SourceText `
          -Source $source `
          -Pattern '  // Inter Galactic: keep desktop capture full-frame\. Requested\r?\n  // dimensions are sender limits until the native bridge has a scaler API\.\r?\n  desktop_capturer->Start\(uint32_t\(fps\)\);\r?\n' `
          -Replacement "  if (max_frame_width > 0 && max_frame_height > 0) {${nl}    desktop_capturer->StartWithMaxFrameSize(uint32_t(fps), max_frame_width,${nl}                                            max_frame_height);${nl}  } else {${nl}    desktop_capturer->Start(uint32_t(fps));${nl}  }${nl}" `
          -Description "replace full-frame start with scaler start"
      } else {
        $source = Update-SourceText `
          -Source $source `
          -Pattern '  desktop_capturer->Start\(uint32_t\(fps\)\);\r?\n' `
          -Replacement "  if (max_frame_width > 0 && max_frame_height > 0) {${nl}    desktop_capturer->StartWithMaxFrameSize(uint32_t(fps), max_frame_width,${nl}                                            max_frame_height);${nl}  } else {${nl}    desktop_capturer->Start(uint32_t(fps));${nl}  }${nl}" `
          -Description "scaled desktop capturer start"
      }
    }

    $source = Add-WindowsDesktopCaptureBridgeLogging `
      -Source $source `
      -Newline $nl

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $source, $utf8NoBom)
    Write-Host "Flutter WebRTC capture patch: installed full-frame scaler."
    return $backup
  } catch {
    $originalError = $_
    try {
      if (Test-Path -LiteralPath $backup) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        Remove-Item -LiteralPath $backup -Force
      }
    } catch {
      Write-Warning "Flutter WebRTC capture patch rollback failed: $_"
    }
    throw $originalError
  }
}

if ($Mode -eq "off") {
  Write-Host "Patched libwebrtc: disabled by build mode."
  exit 0
}

$workspace = Resolve-LocalPath $WorkspaceRoot
$app = Resolve-LocalPath $AppDir
$patchedZip = Find-PatchedZip -WorkspaceRoot $workspace -ZipPath $ZipPath

if ($null -eq $patchedZip) {
  $searched = $script:PatchedZipSearchPaths -join "; "
  $message = "Patched libwebrtc.zip was not found. Searched: $searched"
  if ($Mode -eq "require") {
    throw $message
  }

  Write-Warning "$message Continuing with the stock Flutter WebRTC dependency; hardware encode will likely still report OpenH264 hw:false."
  exit 0
}

$packageRoot = Get-FlutterWebrtcPackageRoot -WorkspaceRoot $workspace -AppDir $app
$sharedPreferencesWindowsPackageRoot = Get-DartPackageRoot `
    -WorkspaceRoot $workspace `
    -AppDir $app `
    -PackageName "shared_preferences_windows"
$capturePatchBackup = $null
$audioPatchBackup = $null
$mediaLifecyclePatchBackup = $null
$rendererPatchBackup = $null
$rendererDiagnosticsPatchBackups = @()
$frameCryptorPatchBackup = $null
$sharedPreferencesPatchBackup = $null

$thirdPartyDir = Join-Path $packageRoot "third_party"
$downloadsDir = Join-Path $thirdPartyDir "downloads"
$targetZip = Join-Path $downloadsDir "libwebrtc.zip"
$targetZipBackup = Join-Path $downloadsDir "igbak-libwebrtc.zip"
$stagedZipId = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
$stagedTargetZip = Join-Path $downloadsDir ("ignew-libwebrtc-{0}.zip" -f $stagedZipId)
$libwebrtcDir = Join-Path $thirdPartyDir "libwebrtc"
$backupLibwebrtcDir = Join-Path $thirdPartyDir "igbak-libwebrtc"
$targetZipHadOriginal = $false
$targetZipNeedsRestore = $false
$targetZipBackedUp = $false
$libwebrtcExtractionStarted = $false

Assert-PathInside -Parent $packageRoot -Child $thirdPartyDir
Assert-PathInside -Parent $packageRoot -Child $downloadsDir
Assert-PathInside -Parent $packageRoot -Child $targetZip
Assert-PathInside -Parent $packageRoot -Child $targetZipBackup
Assert-PathInside -Parent $packageRoot -Child $stagedTargetZip
Assert-PathInside -Parent $packageRoot -Child $libwebrtcDir
Assert-PathInside -Parent $packageRoot -Child $backupLibwebrtcDir

try {
  $sharedPreferencesPatchBackup = Install-WindowsSharedPreferencesDevProfilePatch -PackageRoot $sharedPreferencesWindowsPackageRoot
  $capturePatchBackup = Install-WindowsDesktopCaptureConstraintPatch -PackageRoot $packageRoot
  Clear-WindowsFlutterWebrtcDesktopCaptureBuildCache -AppRoot $app -PackageRoot $packageRoot
  $audioPatchBackup = Install-WindowsAudioCaptureOptionsPatch -PackageRoot $packageRoot
  $mediaLifecyclePatchBackup = Install-WindowsMediaStreamLifecyclePatch -PackageRoot $packageRoot
  $rendererPatchBackup = Install-WindowsVideoRendererLatestFramePatch -PackageRoot $packageRoot
  $rendererDiagnosticsPatchBackups = Install-WindowsVideoRendererFrameDiagnosticsPatch -PackageRoot $packageRoot
  Clear-WindowsFlutterWebrtcRendererDiagnosticsBuildCache -AppRoot $app -PackageRoot $packageRoot
  $frameCryptorPatchBackup = Install-WindowsFrameCryptorCompatibilityPatch -PackageRoot $packageRoot
  Clear-WindowsFlutterWebrtcFrameCryptorBuildCache -AppRoot $app -PackageRoot $packageRoot

  if (-not (Test-Path -LiteralPath $downloadsDir)) {
    New-Item -ItemType Directory -Path $downloadsDir | Out-Null
  }

  $sourceHash = Get-Sha256Hash -Path $patchedZip

  # Re-verify the exact archive that is about to be installed. Find-PatchedZip
  # checked it when it was resolved, but that was before every patch step above;
  # anything that swapped the zip or its manifest in between would otherwise be
  # copied in unchecked. Reuses $sourceHash, so this costs one structural pass.
  Test-LibwebrtcZip -Candidate $patchedZip
  Assert-LibwebrtcManifest -ZipPath $patchedZip -KnownSha256 $sourceHash | Out-Null

  if (Test-Path -LiteralPath $targetZip) {
    $targetZipHadOriginal = $true
    $targetHash = Get-Sha256Hash -Path $targetZip
    if ($targetHash -ne $sourceHash) {
      $targetZipNeedsRestore = $true
      try {
        Copy-Item -LiteralPath $targetZip -Destination $targetZipBackup -Force -ErrorAction Stop
        $targetZipBackedUp = $true
      } catch {
        throw "Could not back up existing libwebrtc.zip from $targetZip to $targetZipBackup. Continuing could leave a patched archive with reverted Flutter WebRTC sources if a later step fails. $_"
      }
    }
  }

  if (Test-Path -LiteralPath $stagedTargetZip) {
    Remove-Item -LiteralPath $stagedTargetZip -Force
  }

  Copy-Item -LiteralPath $patchedZip -Destination $stagedTargetZip -Force
  Move-Item -LiteralPath $stagedTargetZip -Destination $targetZip -Force

  if (Test-Path -LiteralPath $backupLibwebrtcDir) {
    Remove-Item -LiteralPath $backupLibwebrtcDir -Recurse -Force
  }

  if (Test-Path -LiteralPath $libwebrtcDir) {
    Move-Item -LiteralPath $libwebrtcDir -Destination $backupLibwebrtcDir -Force
  }

  $libwebrtcExtractionStarted = $true
  Expand-Archive -LiteralPath $targetZip -DestinationPath $thirdPartyDir -Force

  $requiredAfterExtract = @(
    (Join-Path $libwebrtcDir "include\libwebrtc.h"),
    (Join-Path $libwebrtcDir "include\rtc_intergalactic_audio_ducking.h"),
    (Join-Path $libwebrtcDir "lib\win64\libwebrtc.dll"),
    (Join-Path $libwebrtcDir "lib\win64\libwebrtc.dll.lib")
  )

  foreach ($path in $requiredAfterExtract) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Patched libwebrtc extraction failed; missing $path"
    }
  }

  $installInfo = [ordered]@{
    patched = $true
    source = $patchedZip
    sha256 = $sourceHash
    installedAt = (Get-Date).ToString("o")
    packageRoot = $packageRoot
    mode = $Mode
  }

  $installInfo |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $libwebrtcDir "intergalactic-patched-libwebrtc.json") -Encoding UTF8
} catch {
  $originalError = $_
  try {
    if (Test-Path -LiteralPath $stagedTargetZip) {
      Remove-Item -LiteralPath $stagedTargetZip -Force
    }
    if ($targetZipNeedsRestore) {
      if ($targetZipBackedUp -and (Test-Path -LiteralPath $targetZipBackup)) {
        Copy-Item -LiteralPath $targetZipBackup -Destination $targetZip -Force
        Remove-Item -LiteralPath $targetZipBackup -Force
        $targetZipBackedUp = $false
      } else {
        Write-Warning "Patched libwebrtc rollback could not restore original libwebrtc.zip because no backup is available."
      }
    } elseif (-not $targetZipHadOriginal -and (Test-Path -LiteralPath $targetZip)) {
      Remove-Item -LiteralPath $targetZip -Force
    }
  } catch {
    Write-Warning "Patched libwebrtc archive rollback failed: $_"
  }
  try {
    if ($libwebrtcExtractionStarted) {
      if (Test-Path -LiteralPath $libwebrtcDir) {
        Remove-Item -LiteralPath $libwebrtcDir -Recurse -Force
      }
      if (Test-Path -LiteralPath $backupLibwebrtcDir) {
        Move-Item -LiteralPath $backupLibwebrtcDir -Destination $libwebrtcDir -Force
      }
    }
  } catch {
    Write-Warning "Patched libwebrtc rollback failed: $_"
  }
  try {
    if ($null -ne $capturePatchBackup -and (Test-Path -LiteralPath $capturePatchBackup)) {
      $capturePatchTarget = Get-IntergalacticPatchBackupTarget -Backup $capturePatchBackup
      Copy-Item -LiteralPath $capturePatchBackup -Destination $capturePatchTarget -Force
      Remove-Item -LiteralPath $capturePatchBackup -Force
    }
    if ($null -ne $mediaLifecyclePatchBackup -and (Test-Path -LiteralPath $mediaLifecyclePatchBackup)) {
      $mediaLifecyclePatchTarget = Get-IntergalacticPatchBackupTarget -Backup $mediaLifecyclePatchBackup
      Copy-Item -LiteralPath $mediaLifecyclePatchBackup -Destination $mediaLifecyclePatchTarget -Force
      Remove-Item -LiteralPath $mediaLifecyclePatchBackup -Force
    }
    if ($null -ne $audioPatchBackup -and (Test-Path -LiteralPath $audioPatchBackup)) {
      $audioPatchTarget = Get-IntergalacticPatchBackupTarget -Backup $audioPatchBackup
      Copy-Item -LiteralPath $audioPatchBackup -Destination $audioPatchTarget -Force
      Remove-Item -LiteralPath $audioPatchBackup -Force
    }
    if ($null -ne $rendererPatchBackup -and (Test-Path -LiteralPath $rendererPatchBackup)) {
      $rendererPatchTarget = Get-IntergalacticPatchBackupTarget -Backup $rendererPatchBackup
      Copy-Item -LiteralPath $rendererPatchBackup -Destination $rendererPatchTarget -Force
      Remove-Item -LiteralPath $rendererPatchBackup -Force
    }
    foreach ($rendererDiagnosticsPatchBackup in $rendererDiagnosticsPatchBackups) {
      if ($null -ne $rendererDiagnosticsPatchBackup -and
          (Test-Path -LiteralPath $rendererDiagnosticsPatchBackup)) {
        $rendererDiagnosticsPatchTarget =
            Get-IntergalacticPatchBackupTarget -Backup $rendererDiagnosticsPatchBackup
        Copy-Item -LiteralPath $rendererDiagnosticsPatchBackup -Destination $rendererDiagnosticsPatchTarget -Force
        Remove-Item -LiteralPath $rendererDiagnosticsPatchBackup -Force
      }
    }
    if ($null -ne $frameCryptorPatchBackup -and (Test-Path -LiteralPath $frameCryptorPatchBackup)) {
      $frameCryptorPatchTarget = Get-IntergalacticPatchBackupTarget -Backup $frameCryptorPatchBackup
      Copy-Item -LiteralPath $frameCryptorPatchBackup -Destination $frameCryptorPatchTarget -Force
      Remove-Item -LiteralPath $frameCryptorPatchBackup -Force
    }
    if ($null -ne $sharedPreferencesPatchBackup -and (Test-Path -LiteralPath $sharedPreferencesPatchBackup)) {
      $sharedPreferencesPatchTarget = Get-IntergalacticPatchBackupTarget -Backup $sharedPreferencesPatchBackup
      Copy-Item -LiteralPath $sharedPreferencesPatchBackup -Destination $sharedPreferencesPatchTarget -Force
      Remove-Item -LiteralPath $sharedPreferencesPatchBackup -Force
    }
  } catch {
    Write-Warning "Flutter WebRTC capture patch rollback failed: $_"
  }
  throw $originalError
}

Remove-IntergalacticInstallBackup -Path $backupLibwebrtcDir -Label "libwebrtc directory backup" -Recurse
Remove-IntergalacticInstallBackup -Path $targetZipBackup -Label "libwebrtc archive backup"
$targetZipBackedUp = $false
if ($null -ne $capturePatchBackup) {
  Remove-IntergalacticInstallBackup -Path $capturePatchBackup -Label "capture patch backup"
}
if ($null -ne $audioPatchBackup) {
  Remove-IntergalacticInstallBackup -Path $audioPatchBackup -Label "audio patch backup"
}
if ($null -ne $mediaLifecyclePatchBackup) {
  Remove-IntergalacticInstallBackup -Path $mediaLifecyclePatchBackup -Label "media lifecycle patch backup"
}
if ($null -ne $rendererPatchBackup) {
  Remove-IntergalacticInstallBackup -Path $rendererPatchBackup -Label "renderer patch backup"
}
foreach ($rendererDiagnosticsPatchBackup in $rendererDiagnosticsPatchBackups) {
  if ($null -ne $rendererDiagnosticsPatchBackup) {
    Remove-IntergalacticInstallBackup `
        -Path $rendererDiagnosticsPatchBackup `
        -Label "renderer diagnostics patch backup"
  }
}
if ($null -ne $frameCryptorPatchBackup) {
  Remove-IntergalacticInstallBackup -Path $frameCryptorPatchBackup -Label "frame cryptor patch backup"
}
if ($null -ne $sharedPreferencesPatchBackup) {
  Remove-IntergalacticInstallBackup `
      -Path $sharedPreferencesPatchBackup `
      -Label "shared preferences patch backup"
}

Write-Host "Patched libwebrtc: installed $patchedZip"
Write-Host "Patched libwebrtc: sha256 $sourceHash"
