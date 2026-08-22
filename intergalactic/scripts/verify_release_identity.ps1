param(
    [string]$ProjectRoot,
    [string]$AppDir,
    [string]$ExpectedVersionTag,
    [string]$LatestJson,
    [string]$InstallerPath,
    [string]$AndroidApkPath,
    [string]$SourceZipPath,
    [string]$ChecksumPath,
    [switch]$SyncIosProject
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$message) {
    $failures.Add($message) | Out-Null
}

function Add-Note([string]$message) {
    $notes.Add($message) | Out-Null
}

function Test-RequiredFile([string]$path, [string]$label) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        Add-Failure "$label path was not provided."
        return $false
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "$label was not found: $path"
        return $false
    }

    return $true
}

function Test-OptionalFile([string]$path, [string]$label) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Note "$label not present for this release identity: $path"
        return $false
    }

    return $true
}

function Test-FileName([string]$path, [string]$expectedName, [string]$label) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }

    $actualName = Split-Path -Leaf $path
    if ($actualName -ne $expectedName) {
        Add-Failure "$label filename '$actualName' should be '$expectedName'."
    }
}

function Test-DartStringFromEnvironment([string]$source, [string]$defineName) {
    # Match only a real declaration line - `[static] const <type> <name> =
    # String.fromEnvironment('<define>'...)` - anchored to the start of a line
    # (only leading whitespace allowed before the modifier). This keeps a
    # commented-out line (`// const ...`), a quoted example inside a string, or
    # any other incidental occurrence from satisfying the check after the real
    # BuildConfig field is removed, without the fragility of stripping comments
    # (which also mangles `//` inside Dart string literals).
    $pattern = '(?m)^\s*(?:static\s+)?const\b\s+\w+\s+\w+\s*=\s*String\s*\.\s*fromEnvironment\s*\(\s*[''"]' +
        [regex]::Escape($defineName) +
        '[''"]'
    return $source -match $pattern
}

if ([string]::IsNullOrWhiteSpace($AppDir)) {
    $AppDir = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $AppDir
}

$pubspecPath = Join-Path $AppDir 'pubspec.yaml'
if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "pubspec.yaml was not found at $pubspecPath"
}

$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s+(\d+\.\d+\.\d+)\+(\d+)\s*$'
)
if (-not $versionMatch.Success) {
    throw "Could not parse pubspec version as X.Y.Z+build."
}

$versionName = $versionMatch.Groups[1].Value
$buildNumber = $versionMatch.Groups[2].Value
$fullVersion = "$versionName+$buildNumber"
$msixVersion = "$versionName.$buildNumber"
$versionTag = "v$fullVersion"

if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionTag) -and
    $ExpectedVersionTag -ne $versionTag) {
    Add-Failure "Expected version tag '$ExpectedVersionTag' does not match pubspec '$versionTag'."
}

$msixMatch = [regex]::Match($pubspec, '(?m)^\s+msix_version:\s+(\S+)\s*$')
if ($msixMatch.Success -and $msixMatch.Groups[1].Value -ne $msixVersion) {
    Add-Failure "msix_version '$($msixMatch.Groups[1].Value)' should match MSIX identity '$msixVersion' for pubspec '$fullVersion'."
}

$buildConfigPath = Join-Path $AppDir 'lib/config/build_config.dart'
if (Test-RequiredFile $buildConfigPath 'BuildConfig source') {
    $buildConfig = Get-Content -LiteralPath $buildConfigPath -Raw
    foreach ($defineName in @('VERSION_TAG', 'GIT_HASH', 'BUILD_DATE')) {
        if (-not (Test-DartStringFromEnvironment $buildConfig $defineName)) {
            Add-Failure "BuildConfig no longer reads $defineName from dart-define."
        }
    }
    if ($buildConfig -notmatch 'buildFingerprintDisplay') {
        Add-Failure 'BuildConfig no longer exposes buildFingerprintDisplay for diagnostics/about surfaces.'
    }
}

$iosProjectPath = Join-Path $AppDir 'ios/Runner.xcodeproj/project.pbxproj'
if (Test-Path -LiteralPath $iosProjectPath -PathType Leaf) {
    $iosProject = Get-Content -LiteralPath $iosProjectPath -Raw
    if ($SyncIosProject) {
        $syncedProject = $iosProject `
            -replace 'CURRENT_PROJECT_VERSION = \d+;', "CURRENT_PROJECT_VERSION = $buildNumber;" `
            -replace 'MARKETING_VERSION = "[^"]+";', "MARKETING_VERSION = `"$versionName`";"
        if ($syncedProject -ne $iosProject) {
            [System.IO.File]::WriteAllText($iosProjectPath, $syncedProject)
            $iosProject = $syncedProject
            Add-Note "Synced iOS Broadcast Extension version fields to $fullVersion."
        }
    }

    $runnerBuildPlaceholders = [regex]::Matches(
        $iosProject,
        'CURRENT_PROJECT_VERSION = "?\$\(FLUTTER_BUILD_NUMBER\)"?;'
    ).Count
    if ($runnerBuildPlaceholders -lt 1) {
        Add-Failure 'Runner target no longer uses FLUTTER_BUILD_NUMBER for CURRENT_PROJECT_VERSION.'
    }

    $marketingVersions = [regex]::Matches(
        $iosProject,
        'MARKETING_VERSION = "([^"]+)";'
    )
    foreach ($match in $marketingVersions) {
        $value = $match.Groups[1].Value
        if ($value -ne $versionName) {
            Add-Failure "iOS MARKETING_VERSION '$value' should be '$versionName'."
        }
    }

    $projectVersions = [regex]::Matches(
        $iosProject,
        'CURRENT_PROJECT_VERSION = ([^;]+);'
    )
    foreach ($match in $projectVersions) {
        $value = $match.Groups[1].Value.Trim('"')
        if ($value -eq '$(FLUTTER_BUILD_NUMBER)') {
            continue
        }
        if ($value -ne $buildNumber) {
            Add-Failure "iOS CURRENT_PROJECT_VERSION '$value' should be '$buildNumber'."
        }
    }
} else {
    Add-Note "iOS project file not present; skipped iOS version-field checks."
}

$installerName = "InterGalactic-Setup-$fullVersion.exe"
$androidName = "InterGalactic-$fullVersion.apk"
$sourceName = "intergalactic-$fullVersion-source.zip"
$checksumName = "checksums-$fullVersion.txt"

if (Test-OptionalFile $InstallerPath 'Windows installer') {
    Test-FileName $InstallerPath $installerName 'Windows installer'
}
if (Test-OptionalFile $AndroidApkPath 'Android APK') {
    Test-FileName $AndroidApkPath $androidName 'Android APK'
}
if (Test-OptionalFile $SourceZipPath 'Source archive') {
    Test-FileName $SourceZipPath $sourceName 'Source archive'
}
if (Test-OptionalFile $ChecksumPath 'Checksum file') {
    Test-FileName $ChecksumPath $checksumName 'Checksum file'
    $checksumText = Get-Content -LiteralPath $ChecksumPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($InstallerPath) -and
        (Test-Path -LiteralPath $InstallerPath -PathType Leaf) -and
        $checksumText -notmatch [regex]::Escape($installerName)) {
        Add-Failure "Checksum file does not include $installerName."
    }
    if (-not [string]::IsNullOrWhiteSpace($AndroidApkPath) -and
        (Test-Path -LiteralPath $AndroidApkPath -PathType Leaf) -and
        $checksumText -notmatch [regex]::Escape($androidName)) {
        Add-Failure "Checksum file does not include $androidName."
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceZipPath) -and
        (Test-Path -LiteralPath $SourceZipPath -PathType Leaf) -and
        $checksumText -notmatch [regex]::Escape($sourceName)) {
        Add-Failure "Checksum file does not include $sourceName."
    }
}

if (-not [string]::IsNullOrWhiteSpace($LatestJson)) {
    if (Test-RequiredFile $LatestJson 'latest.json') {
        $manifest = Get-Content -LiteralPath $LatestJson -Raw | ConvertFrom-Json
        if ($manifest.version -ne $versionTag) {
            Add-Failure "latest.json version '$($manifest.version)' should be '$versionTag'."
        }
        if ($manifest.version_name -ne $versionName) {
            Add-Failure "latest.json version_name '$($manifest.version_name)' should be '$versionName'."
        }
        if ([string]$manifest.build_number -ne $buildNumber) {
            Add-Failure "latest.json build_number '$($manifest.build_number)' should be '$buildNumber'."
        }
        if ($manifest.checksums_url -and
            $manifest.checksums_url -notmatch [regex]::Escape($checksumName)) {
            Add-Failure "latest.json checksums_url should reference $checksumName."
        }
        if ($manifest.source_url -and
            $manifest.source_url -notmatch [regex]::Escape($sourceName)) {
            Add-Failure "latest.json source_url should reference $sourceName."
        }
        if ($manifest.platforms.windows.download_url -and
            $manifest.platforms.windows.download_url -notmatch [regex]::Escape($installerName)) {
            Add-Failure "latest.json Windows download_url should reference $installerName."
        }
        if ($manifest.platforms.android -and
            $manifest.platforms.android.download_url -and
            $manifest.platforms.android.download_url -notmatch [regex]::Escape($androidName)) {
            Add-Failure "latest.json Android download_url should reference $androidName."
        }
    }
}

foreach ($note in $notes) {
    Write-Host "[release-identity] $note"
}

if ($failures.Count -gt 0) {
    Write-Error "Release identity verification failed:`n- $($failures -join "`n- ")"
    exit 1
}

Write-Host "[release-identity] OK: $versionTag"
