[CmdletBinding()]
param(
  [string]$FlutterCommand = "flutter",
  [string]$OutputDir,
  [switch]$SkipPubGet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $appRoot
$toggleScript = Join-Path $scriptDir "set_google_services.ps1"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $repoRoot "docs\release\evidence\android-fcm"
}

function Test-GoogleServicesEnabled {
  $pubspec = Join-Path $appRoot "pubspec.yaml"
  $appGradle = Join-Path $appRoot "android\app\build.gradle"
  $settingsGradle = Join-Path $appRoot "android\settings.gradle"

  $hasFirebaseCore = Select-String -Path $pubspec -Pattern "^\s*firebase_core:" -Quiet
  $hasAppPlugin = Select-String -Path $appGradle -SimpleMatch "id 'com.google.gms.google-services'" -Quiet
  $hasSettingsPlugin = Select-String -Path $settingsGradle -SimpleMatch 'id "com.google.gms.google-services"' -Quiet

  return ($hasFirebaseCore -and $hasAppPlugin -and $hasSettingsPlugin)
}

function Invoke-PubGet {
  if ($SkipPubGet) {
    return
  }

  Push-Location $appRoot
  try {
    & $FlutterCommand pub get
    if ($LASTEXITCODE -ne 0) {
      throw "flutter pub get failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
}

function Get-LockfilePath {
  $candidates = @(
    (Join-Path $appRoot "pubspec.lock"),
    (Join-Path $repoRoot "pubspec.lock")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "No pubspec.lock found after enabling Google Services dependencies."
}

function Get-PubspecLockPackages {
  param([string]$LockfilePath)

  $packages = @()
  $current = $null

  foreach ($line in Get-Content -LiteralPath $LockfilePath) {
    if ($line -match "^  ([A-Za-z0-9_]+):\s*$") {
      if ($null -ne $current) {
        $packages += $current
      }

      $current = [ordered]@{
        name = $Matches[1]
        version = $null
        source = $null
      }
      continue
    }

    if ($null -eq $current) {
      continue
    }

    if ($line -match "^\s{4}source:\s+(.+?)\s*$") {
      $current.source = ($Matches[1] -replace '"', '')
      continue
    }

    if ($line -match "^\s{4}version:\s+`"?([^`"]+)`"?\s*$") {
      $current.version = $Matches[1]
      continue
    }
  }

  if ($null -ne $current) {
    $packages += $current
  }

  return $packages
}

function Get-PubCacheRoot {
  if (-not [string]::IsNullOrWhiteSpace($env:PUB_CACHE)) {
    return $env:PUB_CACHE
  }

  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    return (Join-Path $env:LOCALAPPDATA "Pub\Cache")
  }

  return (Join-Path $HOME "AppData\Local\Pub\Cache")
}

function Get-Sha256Hex {
  param([string]$Path)

  $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
  try {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hashBytes = $sha256.ComputeHash($stream)
      return ([System.BitConverter]::ToString($hashBytes) -replace "-", "").ToLowerInvariant()
    } finally {
      $sha256.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Write-Utf8NoBomText {
  param(
    [string]$Path,
    [string]$Text
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Write-Utf8NoBomLines {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  Write-Utf8NoBomText -Path $Path -Text (($Lines -join "`n") + "`n")
}

function Get-LicenseId {
  param([string]$Text)

  if ($Text -match "Apache License\s+Version 2\.0") {
    return "Apache-2.0"
  }

  if ($Text -match "BSD 3-Clause License" -or $Text -match "Redistribution and use in source and binary forms") {
    return "BSD-3-Clause"
  }

  if ($Text -match "MIT License") {
    return "MIT"
  }

  return "UNKNOWN"
}

function Get-PubCacheLicensePath {
  param(
    [string]$PubCacheRoot,
    [string]$Name,
    [string]$Version
  )

  $packageRoot = Join-Path $PubCacheRoot ("hosted\pub.dev\{0}-{1}" -f $Name, $Version)
  $candidates = @("LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING", "NOTICE") |
    ForEach-Object { Join-Path $packageRoot $_ }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  return $null
}

function ConvertTo-RepoRelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $repoPrefix = (Resolve-Path -LiteralPath $repoRoot).Path.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar
  if ($resolved.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ($resolved.Substring($repoPrefix.Length) -replace "\\", "/")
  }
  return $resolved
}

function Write-MarkdownEvidence {
  param(
    [string]$Path,
    [object]$Payload
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("# Android FCM License Evidence")
  $lines.Add("")
  $lines.Add("Generated: $($Payload.generated_at)")
  $lines.Add("")
  $lines.Add('This evidence captures Firebase/FlutterFire Dart package notices from the temporary Google Services dependency state. It does not require or read `google-services.json`.')
  $lines.Add("")
  $lines.Add(('Source lockfile: `{0}`' -f $Payload.source_lockfile))
  $lines.Add("")
  $lines.Add("## Packages")
  $lines.Add("")
  $lines.Add("| Package | Version | License | Evidence |")
  $lines.Add("| --- | --- | --- | --- |")

  foreach ($package in $Payload.packages) {
    $license = $package.license_id
    if ([string]::IsNullOrWhiteSpace($license)) {
      $license = "UNKNOWN"
    }

    $evidence = $package.license_evidence_path
    if ([string]::IsNullOrWhiteSpace($evidence)) {
      $evidence = "missing"
    }

    $lines.Add(('| `{0}` | `{1}` | {2} | `{3}` |' -f $package.name, $package.version, $license, $evidence))
  }

  if ($Payload.missing_license_packages.Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Missing Local License Text")
    $lines.Add("")
    foreach ($package in $Payload.missing_license_packages) {
      $lines.Add(('- `{0}` `{1}`' -f $package.name, $package.version))
    }
  }

  $lines.Add("")
  $lines.Add("## Release Use")
  $lines.Add("")
  $lines.Add("- Include this evidence when the Android release artifact is built with FCM / Google Services enabled.")
  $lines.Add("- Keep the normal shared checkout restored to the non-Google dependency state after collection.")
  $lines.Add("- Android Gradle/Maven runtime notices still need separate Gradle dependency evidence for the shipped APK.")

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

$originalEnabled = Test-GoogleServicesEnabled

try {
  & $toggleScript enable
  if (-not $?) {
    throw "Failed to enable Google Services source state."
  }

  Invoke-PubGet

  $lockfile = Get-LockfilePath
  $allPackages = Get-PubspecLockPackages -LockfilePath $lockfile
  $targetPackages = @($allPackages | Where-Object {
      $_.name -like "firebase_*" -or $_.name -eq "_flutterfire_internals"
    } | Sort-Object name)

  $pubCacheRoot = Get-PubCacheRoot
  $rows = @()
  $missing = @()

  foreach ($package in $targetPackages) {
    $licensePath = $null
    $licenseText = $null
    $licenseHash = $null
    $licenseId = $null
    $licenseEvidencePath = $null

    if ($package.source -eq "hosted" -and -not [string]::IsNullOrWhiteSpace($package.version)) {
      $licensePath = Get-PubCacheLicensePath -PubCacheRoot $pubCacheRoot -Name $package.name -Version $package.version
    }

    if ($null -ne $licensePath) {
      $licenseText = [System.IO.File]::ReadAllText($licensePath)
      $licenseHash = Get-Sha256Hex -Path $licensePath
      $licenseId = Get-LicenseId -Text $licenseText
      $licenseEvidencePath = "pub-cache:hosted/pub.dev/{0}-{1}/{2}" -f $package.name, $package.version, (Split-Path -Leaf $licensePath)
    } else {
      $missing += [pscustomobject]@{
        name = $package.name
        version = $package.version
      }
    }

    $rows += [pscustomobject]@{
      name = $package.name
      version = $package.version
      source = $package.source
      license_id = $licenseId
      license_evidence_path = $licenseEvidencePath
      license_text_sha256 = $licenseHash
      license_text = $licenseText
    }
  }

  if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
  }

  $payload = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    source_state = "temporary-google-services-enabled"
    source_lockfile = ConvertTo-RepoRelativePath -Path $lockfile
    package_selector = "firebase_* plus _flutterfire_internals"
    packages = $rows
    missing_license_packages = $missing
  }

  $jsonPath = Join-Path $OutputDir "THIRD_PARTY_LICENSES.android-fcm.json"
  $markdownPath = Join-Path $OutputDir "THIRD_PARTY_NOTICES.android-fcm.md"

  Write-Utf8NoBomText -Path $jsonPath -Text (($payload | ConvertTo-Json -Depth 8) + "`n")
  Write-MarkdownEvidence -Path $markdownPath -Payload $payload

  Write-Host "[android-fcm-license] Wrote $jsonPath"
  Write-Host "[android-fcm-license] Wrote $markdownPath"
} finally {
  $restoreMode = if ($originalEnabled) { "enable" } else { "disable" }
  & $toggleScript $restoreMode
  if (-not $?) {
    throw "Failed to restore Google Services source state."
  }

  try {
    Invoke-PubGet
  } catch {
    Write-Warning "Restored Google Services source state, but the final pub get failed: $($_.Exception.Message)"
    throw
  }
}
