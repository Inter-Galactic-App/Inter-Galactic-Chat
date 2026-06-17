[CmdletBinding()]
param(
  [string]$OutputDir,
  [string]$BuildMode = "unknown",
  [string]$VersionTag = "unknown",
  [string]$GradleCommand,
  [string]$GradleEvidenceJson,
  [string]$Variant = "release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $appRoot
$androidRoot = Join-Path $appRoot "android"
$settingsGradle = Join-Path $androidRoot "settings.gradle"
$appBuildGradle = Join-Path $androidRoot "app\build.gradle"
$appBuildDir = Join-Path $androidRoot "app\build"
$flutterAppBuildDir = Join-Path $appRoot "build\app"

if ([string]::IsNullOrWhiteSpace($GradleCommand)) {
  $GradleCommand = Join-Path $androidRoot "gradlew.bat"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $repoRoot "docs\release\evidence\android-oss-licenses"
}

if ([string]::IsNullOrWhiteSpace($GradleEvidenceJson) -and -not [string]::IsNullOrWhiteSpace($VersionTag)) {
  $versionDir = $VersionTag
  if ($versionDir.StartsWith("v")) {
    $versionDir = $versionDir.Substring(1)
  }
  $GradleEvidenceJson = Join-Path $repoRoot ("docs\release\evidence\android-gradle\{0}\THIRD_PARTY_LICENSES.android-gradle.json" -f $versionDir)
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

function ConvertTo-PublicEvidenceLine {
  param([string]$Line)

  $value = [string]$Line
  $value = $value -replace 'file:///[^`"''\s]*/([^/`"''\s]+)', 'file:/redacted/$1'
  $value = $value -replace 'file:///[^`"''\s]+', 'file:/redacted'
  return $value
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

function Get-Newline {
  param([string]$Text)

  if ($Text.Contains("`r`n")) {
    return "`r`n"
  }

  return "`n"
}

function Set-ExactText {
  param(
    [string]$Path,
    [string]$Text
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $Path).Path, $Text, $utf8NoBom)
}

function Write-Utf8NoBomText {
  param(
    [string]$Path,
    [string]$Text
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Add-OssLicensePluginResolution {
  param([string]$Text)

  if ($Text -match "com\.google\.android\.gms\.oss-licenses-plugin") {
    return $Text
  }

  $nl = Get-Newline -Text $Text
  $resolutionBlock = @(
    "    resolutionStrategy {",
    "        eachPlugin {",
    "            if (requested.id.id == ""com.google.android.gms.oss-licenses-plugin"") {",
    "                useModule(""com.google.android.gms:oss-licenses-plugin:0.12.0"")",
    "            }",
    "        }",
    "    }"
  ) -join $nl

  $marker = "}$nl${nl}plugins {"
  if (-not $Text.Contains($marker)) {
    throw "Could not find settings.gradle pluginManagement closing marker."
  }

  return $Text.Replace($marker, "$resolutionBlock$nl}$nl${nl}plugins {")
}

function Add-OssLicenseAppPlugin {
  param([string]$Text)

  if ($Text -match "com\.google\.android\.gms\.oss-licenses-plugin") {
    return $Text
  }

  $nl = Get-Newline -Text $Text
  $needle = "    id ""com.android.application"""
  if (-not $Text.Contains($needle)) {
    throw "Could not find com.android.application plugin declaration in app/build.gradle."
  }

  return $Text.Replace($needle, "$needle$nl    id ""com.google.android.gms.oss-licenses-plugin""")
}

function Add-OssLicenseDependency {
  param([string]$Text)

  if ($Text -match "play-services-oss-licenses") {
    return $Text
  }

  $nl = Get-Newline -Text $Text
  $needle = "dependencies {$nl"
  if (-not $Text.Contains($needle)) {
    throw "Could not find dependencies block in app/build.gradle."
  }

  return $Text.Replace($needle, "dependencies {$nl    implementation 'com.google.android.gms:play-services-oss-licenses:17.5.1'$nl")
}

function Invoke-Gradle {
  param(
    [string[]]$Arguments,
    [string]$ReportPath
  )

  Push-Location $androidRoot
  try {
    $output = & $GradleCommand @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  $lines = @($output | ForEach-Object { ConvertTo-PublicEvidenceLine -Line $_.ToString() })
  Write-Utf8NoBomText -Path $ReportPath -Text (($lines -join "`n") + "`n")

  if ($exitCode -ne 0) {
    throw "Gradle command failed with exit code $exitCode. See $ReportPath."
  }

  return $lines
}

function Get-OssLicenseTaskNames {
  param([string[]]$TaskLines)

  $names = @()
  foreach ($line in $TaskLines) {
    if ($line -match "^\s*([A-Za-z][A-Za-z0-9_]*Oss(?:Dependency|Licenses)Task)\b") {
      $names += $Matches[1]
    } elseif ($line -match "^\s*([A-Za-z][A-Za-z0-9_]*OssLicenses[A-Za-z0-9_]*)\b") {
      $names += $Matches[1]
    }
  }

  return @($names | Sort-Object -Unique)
}

function Copy-BaselineFiles {
  param([string]$DestinationDir)

  $filesDir = Join-Path $DestinationDir "generated-files"
  if (-not (Test-Path -LiteralPath $filesDir)) {
    New-Item -ItemType Directory -Path $filesDir | Out-Null
  }

  $buildRoots = @(@($appBuildDir, $flutterAppBuildDir) | Where-Object { Test-Path -LiteralPath $_ })
  if ($buildRoots.Count -eq 0) {
    return @()
  }

  $candidateFiles = @()
  foreach ($buildRoot in $buildRoots) {
    $candidateFiles += Get-ChildItem -LiteralPath $buildRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Name -match "third_party_licenses|third_party_license_metadata|oss_licenses|oss-licenses|dependencies\.json"
      }
  }

  $rows = @()
  foreach ($file in @($candidateFiles | Sort-Object FullName)) {
    $sourceBuildRoot = @($buildRoots | Where-Object {
        $file.FullName.StartsWith((Resolve-Path -LiteralPath $_).Path, [System.StringComparison]::OrdinalIgnoreCase)
      } | Sort-Object Length -Descending | Select-Object -First 1)[0]
    $relative = $file.FullName.Substring((Resolve-Path -LiteralPath $sourceBuildRoot).Path.Length).TrimStart(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
    $safeName = ($relative -replace "[:\\/]", "__")
    $copyPath = Join-Path $filesDir $safeName
    Copy-Item -LiteralPath $file.FullName -Destination $copyPath -Force

    $rows += [pscustomobject]@{
      source_path = ConvertTo-RepoRelativePath -Path $file.FullName
      copied_path = ConvertTo-RepoRelativePath -Path $copyPath
      size_bytes = $file.Length
      sha256 = Get-Sha256Hex -Path $file.FullName
    }
  }

  return $rows
}

function Get-BaselineEntryNames {
  param([object[]]$GeneratedFiles)

  $metadata = @($GeneratedFiles | Where-Object { $_.source_path -match "third_party_license_metadata" } | Select-Object -First 1)
  if ($metadata.Count -eq 0) {
    return @()
  }

  $copiedPath = $metadata[0].copied_path
  if ([System.IO.Path]::IsPathRooted($copiedPath)) {
    $metadataPath = $copiedPath
  } else {
    $metadataPath = Join-Path $repoRoot ($copiedPath -replace "/", "\")
  }
  if (-not (Test-Path -LiteralPath $metadataPath)) {
    return @()
  }

  $names = @()
  foreach ($line in @(Get-Content -LiteralPath $metadataPath -ErrorAction SilentlyContinue)) {
    if ($line -match "^\s*\d+:\d+\s+(.+?)\s*$") {
      $names += $Matches[1]
    }
  }

  return @($names | Sort-Object -Unique)
}

function Get-BaselineDependencyModules {
  param([object[]]$GeneratedFiles)

  $dependencyFile = @($GeneratedFiles | Where-Object { $_.source_path -match "dependencies\.json" } | Select-Object -First 1)
  if ($dependencyFile.Count -eq 0) {
    return @()
  }

  $copiedPath = $dependencyFile[0].copied_path
  if ([System.IO.Path]::IsPathRooted($copiedPath)) {
    $dependencyPath = $copiedPath
  } else {
    $dependencyPath = Join-Path $repoRoot ($copiedPath -replace "/", "\")
  }
  if (-not (Test-Path -LiteralPath $dependencyPath)) {
    return @()
  }

  $rows = @()

  $parsed = Get-Content -LiteralPath $dependencyPath -Raw | ConvertFrom-Json
  $groupValues = @($parsed.group)
  $nameValues = @($parsed.name)
  $versionValues = @($parsed.version)

  if ($groupValues.Count -gt 1 -and $groupValues.Count -eq $nameValues.Count -and $groupValues.Count -eq $versionValues.Count) {
    for ($index = 0; $index -lt $groupValues.Count; $index += 1) {
      $moduleId = "{0}:{1}:{2}" -f $groupValues[$index], $nameValues[$index], $versionValues[$index]
      $rows += [pscustomobject]@{
        group = $groupValues[$index]
        name = $nameValues[$index]
        version = $versionValues[$index]
        module_id = $moduleId
      }
    }
  } else {
    foreach ($dependency in @($parsed)) {
      $moduleId = "{0}:{1}:{2}" -f $dependency.group, $dependency.name, $dependency.version
      $rows += [pscustomobject]@{
        group = $dependency.group
        name = $dependency.name
        version = $dependency.version
        module_id = $moduleId
      }
    }
  }

  return @($rows | Sort-Object module_id)
}

function Write-MarkdownReport {
  param(
    [string]$Path,
    [object]$Payload
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("# Android Google OSS Licenses Baseline")
  $lines.Add("")
  $lines.Add("Generated: $($Payload.generated_at)")
  $lines.Add("Build mode: $($Payload.build_mode)")
  $lines.Add("Version tag: $($Payload.version_tag)")
  $lines.Add("Status: $($Payload.status)")
  $lines.Add("")
  $lines.Add('This baseline temporarily applies Google''s `oss-licenses-plugin` and `play-services-oss-licenses` SDK, runs the release OSS license generation task, copies the generated artifacts, and restores the Gradle files.')
  $lines.Add("Google documents that this tool scans app POM dependencies and includes the transitive open-source libraries used by Google Play services libraries compiled into the app.")
  $lines.Add('Use the companion Android Gradle evidence as the authoritative shipped runtime dependency graph. The Google OSS plugin dependency list is retained as plugin output and may include helper/plugin coordinates or versions that differ from `releaseRuntimeClasspath`.')
  $lines.Add("")
  $lines.Add("## Comparison")
  $lines.Add("")
  $lines.Add(("- Gradle evidence modules: {0}" -f $Payload.comparison.gradle_module_count))
  $lines.Add(("- Gradle evidence missing licenses: {0}" -f $Payload.comparison.gradle_missing_license_count))
  $lines.Add(("- Google baseline generated files: {0}" -f @($Payload.generated_files).Count))
  $lines.Add(("- Parsed Google baseline entry names: {0}" -f @($Payload.baseline_entry_names).Count))
  $lines.Add(("- Parsed Google dependency modules: {0}" -f @($Payload.baseline_dependency_modules).Count))
  $lines.Add(("- Result: {0}" -f $Payload.comparison.result))
  $lines.Add(("- Note: {0}" -f $Payload.comparison.note))
  $lines.Add("")
  $lines.Add("## Gradle Tasks")
  $lines.Add("")
  foreach ($task in @($Payload.gradle_tasks_run)) {
    $lines.Add(('- `{0}`' -f $task))
  }
  $lines.Add("")
  $lines.Add("## Generated Files")
  $lines.Add("")
  $lines.Add("| Copied file | Source file | Size | SHA-256 |")
  $lines.Add("| --- | --- | ---: | --- |")
  foreach ($file in @($Payload.generated_files)) {
    $lines.Add(('| `{0}` | `{1}` | {2} | `{3}` |' -f $file.copied_path, $file.source_path, $file.size_bytes, $file.sha256))
  }

  if (@($Payload.baseline_entry_names).Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Parsed Baseline Entries")
    $lines.Add("")
    foreach ($name in @($Payload.baseline_entry_names)) {
      $lines.Add(("- $name"))
    }
  }

  if (@($Payload.baseline_dependency_modules).Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Parsed Google OSS Plugin Dependency Modules")
    $lines.Add("")
    $lines.Add("These module ids come from Google's generated `dependencies.json`; use Android Gradle evidence for shipped runtime versions.")
    $lines.Add("")
    foreach ($module in @($Payload.baseline_dependency_modules)) {
      $lines.Add(('- `{0}`' -f $module.module_id))
    }
  }

  Write-Utf8NoBomText -Path $Path -Text (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

if (-not (Test-Path -LiteralPath $GradleCommand)) {
  throw "Gradle wrapper not found: $GradleCommand"
}

if (-not (Test-Path -LiteralPath $settingsGradle)) {
  throw "settings.gradle not found: $settingsGradle"
}

if (-not (Test-Path -LiteralPath $appBuildGradle)) {
  throw "app/build.gradle not found: $appBuildGradle"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$settingsOriginal = Get-Content -LiteralPath $settingsGradle -Raw
$appBuildOriginal = Get-Content -LiteralPath $appBuildGradle -Raw
$tasksRun = @()

try {
  $settingsPatched = Add-OssLicensePluginResolution -Text $settingsOriginal
  $appBuildPatched = Add-OssLicenseDependency -Text (Add-OssLicenseAppPlugin -Text $appBuildOriginal)

  Set-ExactText -Path $settingsGradle -Text $settingsPatched
  Set-ExactText -Path $appBuildGradle -Text $appBuildPatched

  $tasksReportPath = Join-Path $OutputDir "android-oss-licenses-gradle-tasks.txt"
  $taskLines = Invoke-Gradle -Arguments @(":app:tasks", "--all", "--console=plain", "--no-daemon") -ReportPath $tasksReportPath
  $ossTasks = @(Get-OssLicenseTaskNames -TaskLines $taskLines)

  $variantTitle = (Get-Culture).TextInfo.ToTitleCase($Variant.ToLowerInvariant())
  $variantLower = $Variant.ToLowerInvariant()
  $candidateGeneratedTaskName = "generate{0}OssLicenses" -f $variantTitle
  $candidateLegacyTaskName = "{0}OssLicensesTask" -f $variantLower
  $candidateTaskNames = @($candidateGeneratedTaskName, $candidateLegacyTaskName)
  $selectedTaskName = $null
  $taskReportText = $taskLines -join "`n"
  if ($taskReportText.Contains($candidateTaskNames[1])) {
    $selectedTaskName = $candidateTaskNames[1]
  } elseif ($taskReportText.Contains($candidateTaskNames[0])) {
    $selectedTaskName = $candidateTaskNames[0]
  }

  if (-not [string]::IsNullOrWhiteSpace($selectedTaskName)) {
    $targetTasks = @(":app:$selectedTaskName")
  } elseif ($ossTasks.Count -gt 0) {
    $targetTasks = @(":app:$($ossTasks[0])")
  } else {
    $targetTasks = @(":app:$($candidateTaskNames[0])")
  }

  foreach ($task in $targetTasks) {
    $taskSafeName = $task -replace "[:\\/]", "_"
    $taskReportPath = Join-Path $OutputDir ("android-oss-licenses-{0}.txt" -f $taskSafeName.TrimStart("_"))
    Invoke-Gradle -Arguments @($task, "--console=plain", "--no-daemon") -ReportPath $taskReportPath | Out-Null
    $tasksRun += $task
  }

  $generatedFiles = @(Copy-BaselineFiles -DestinationDir $OutputDir)
  $baselineNames = @(Get-BaselineEntryNames -GeneratedFiles $generatedFiles)
  $baselineDependencyModules = @(Get-BaselineDependencyModules -GeneratedFiles $generatedFiles)

  $gradleModuleCount = $null
  $gradleMissingLicenseCount = $null
  if (-not [string]::IsNullOrWhiteSpace($GradleEvidenceJson) -and (Test-Path -LiteralPath $GradleEvidenceJson)) {
    $gradleEvidence = Get-Content -LiteralPath $GradleEvidenceJson -Raw | ConvertFrom-Json
    $gradleModuleCount = @($gradleEvidence.modules).Count
    $gradleMissingLicenseCount = @($gradleEvidence.missing_license_modules).Count
  }

  $runtimeGraphNote = "Google OSS dependencies.json is retained as plugin output; Android Gradle evidence remains authoritative for shipped runtime module coordinates and versions."
  $comparisonResult = "google_baseline_generated_runtime_graph_not_authoritative"
  if ($generatedFiles.Count -eq 0) {
    $comparisonResult = "baseline_task_ran_but_no_generated_files_found"
  } elseif ($null -ne $gradleMissingLicenseCount -and $gradleMissingLicenseCount -eq 0) {
    $comparisonResult = "gradle_evidence_complete_google_baseline_generated_runtime_graph_not_authoritative"
  }

  $payload = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    build_mode = $BuildMode
    version_tag = $VersionTag
    status = if ($generatedFiles.Count -gt 0) { "complete" } else { "partial_no_generated_files_found" }
    source = "Google Play services oss-licenses Gradle plugin"
    google_documentation = "https://developers.google.com/android/guides/opensource"
    oss_licenses_plugin = "com.google.android.gms:oss-licenses-plugin:0.12.0"
    oss_licenses_sdk = "com.google.android.gms:play-services-oss-licenses:17.5.1"
    gradle_evidence_json = if (-not [string]::IsNullOrWhiteSpace($GradleEvidenceJson) -and (Test-Path -LiteralPath $GradleEvidenceJson)) { ConvertTo-RepoRelativePath -Path $GradleEvidenceJson } else { $GradleEvidenceJson }
    gradle_tasks_run = $tasksRun
    generated_files = $generatedFiles
    baseline_entry_names = $baselineNames
    baseline_dependency_modules = $baselineDependencyModules
    comparison = [pscustomobject]@{
      gradle_module_count = $gradleModuleCount
      gradle_missing_license_count = $gradleMissingLicenseCount
      result = $comparisonResult
      note = $runtimeGraphNote
    }
  }

  $jsonPath = Join-Path $OutputDir "THIRD_PARTY_LICENSES.android-oss-licenses-baseline.json"
  $markdownPath = Join-Path $OutputDir "THIRD_PARTY_NOTICES.android-oss-licenses-baseline.md"
  Write-Utf8NoBomText -Path $jsonPath -Text (($payload | ConvertTo-Json -Depth 10) + "`n")
  Write-MarkdownReport -Path $markdownPath -Payload $payload

  Write-Host "[android-oss-licenses] Wrote $jsonPath"
  Write-Host "[android-oss-licenses] Wrote $markdownPath"
} finally {
  Set-ExactText -Path $settingsGradle -Text $settingsOriginal
  Set-ExactText -Path $appBuildGradle -Text $appBuildOriginal
}
