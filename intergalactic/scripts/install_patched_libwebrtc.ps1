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

function Resolve-LocalPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
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

  $candidates = @(
    (Join-Path $WorkspaceRoot ".dart_tool\package_config.json"),
    (Join-Path $AppDir ".dart_tool\package_config.json")
  )

  foreach ($candidate in $candidates) {
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
  } finally {
    $zip.Dispose()
  }
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

  return ($Backup -replace '(\.intergalactic-backup.*|\.intergalactic-lifecycle-backup.*)$', '')
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
  if (Test-Path -LiteralPath $stampPath) {
    $existingHash = (Get-Content -LiteralPath $stampPath -Raw).Trim()
    if ($existingHash -eq $sourceHash) {
      return
    }
  }

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
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Force
      Write-Host "Flutter WebRTC frame cryptor patch: removed stale build product $path"
    }
  }

  $stampDir = Split-Path -Parent $stampPath
  if (-not (Test-Path -LiteralPath $stampDir)) {
    New-Item -ItemType Directory -Path $stampDir | Out-Null
  }
  Set-Content -LiteralPath $stampPath -Value $sourceHash -Encoding ASCII
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
$capturePatchBackup = $null
$audioPatchBackup = $null
$mediaLifecyclePatchBackup = $null
$frameCryptorPatchBackup = $null

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
  $capturePatchBackup = Install-WindowsDesktopCaptureConstraintPatch -PackageRoot $packageRoot
  $audioPatchBackup = Install-WindowsAudioCaptureOptionsPatch -PackageRoot $packageRoot
  $mediaLifecyclePatchBackup = Install-WindowsMediaStreamLifecyclePatch -PackageRoot $packageRoot
  $frameCryptorPatchBackup = Install-WindowsFrameCryptorCompatibilityPatch -PackageRoot $packageRoot
  Clear-WindowsFlutterWebrtcFrameCryptorBuildCache -AppRoot $app -PackageRoot $packageRoot

  if (-not (Test-Path -LiteralPath $downloadsDir)) {
    New-Item -ItemType Directory -Path $downloadsDir | Out-Null
  }

  $sourceHash = Get-Sha256Hash -Path $patchedZip
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
    if ($null -ne $frameCryptorPatchBackup -and (Test-Path -LiteralPath $frameCryptorPatchBackup)) {
      $frameCryptorPatchTarget = Get-IntergalacticPatchBackupTarget -Backup $frameCryptorPatchBackup
      Copy-Item -LiteralPath $frameCryptorPatchBackup -Destination $frameCryptorPatchTarget -Force
      Remove-Item -LiteralPath $frameCryptorPatchBackup -Force
    }
  } catch {
    Write-Warning "Flutter WebRTC capture patch rollback failed: $_"
  }
  throw $originalError
}

if (Test-Path -LiteralPath $backupLibwebrtcDir) {
  Remove-Item -LiteralPath $backupLibwebrtcDir -Recurse -Force
}
if ($null -ne $capturePatchBackup -and (Test-Path -LiteralPath $capturePatchBackup)) {
  Remove-Item -LiteralPath $capturePatchBackup -Force
}
if ($null -ne $audioPatchBackup -and (Test-Path -LiteralPath $audioPatchBackup)) {
  Remove-Item -LiteralPath $audioPatchBackup -Force
}
if ($null -ne $mediaLifecyclePatchBackup -and (Test-Path -LiteralPath $mediaLifecyclePatchBackup)) {
  Remove-Item -LiteralPath $mediaLifecyclePatchBackup -Force
}
if ($null -ne $frameCryptorPatchBackup -and (Test-Path -LiteralPath $frameCryptorPatchBackup)) {
  Remove-Item -LiteralPath $frameCryptorPatchBackup -Force
}

Write-Host "Patched libwebrtc: installed $patchedZip"
Write-Host "Patched libwebrtc: sha256 $sourceHash"
