[CmdletBinding()]
param(
  [string]$OutputDir,
  [string]$BuildMode = "unknown",
  [string]$VersionTag = "unknown",
  [string]$GradleCommand,
  [string]$OverridesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $appRoot
$androidRoot = Join-Path $appRoot "android"

if ([string]::IsNullOrWhiteSpace($GradleCommand)) {
  $GradleCommand = Join-Path $androidRoot "gradlew.bat"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $repoRoot "docs\release\evidence\android-gradle"
}

if ([string]::IsNullOrWhiteSpace($OverridesPath)) {
  $OverridesPath = Join-Path $scriptDir "android_gradle_license_overrides.json"
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

function Get-GradleUserHome {
  if (-not [string]::IsNullOrWhiteSpace($env:GRADLE_USER_HOME)) {
    return $env:GRADLE_USER_HOME
  }

  return (Join-Path $HOME ".gradle")
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

function ConvertTo-GradleCacheEvidencePath {
  param(
    [string]$Path,
    [string]$GradleUserHome
  )

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $cachePrefix = (Resolve-Path -LiteralPath $GradleUserHome).Path.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar

  if ($resolved.StartsWith($cachePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return "gradle-cache:{0}" -f ($resolved.Substring($cachePrefix.Length) -replace "\\", "/")
  }

  return $resolved
}

function Get-MavenPomUrl {
  param(
    [string]$Group,
    [string]$Name,
    [string]$Version
  )

  $groupPath = $Group -replace "\.", "/"
  $artifactPath = "{0}/{1}/{2}/{1}-{2}.pom" -f $groupPath, $Name, $Version

  if ($Group -like "androidx.*" -or $Group -like "com.android.*" -or $Group -like "com.google.*") {
    return "https://dl.google.com/dl/android/maven2/$artifactPath"
  }

  return "https://repo1.maven.org/maven2/$artifactPath"
}

function Find-GradlePom {
  param(
    [string]$GradleUserHome,
    [string]$Group,
    [string]$Name,
    [string]$Version
  )

  $moduleRoot = Join-Path $GradleUserHome ("caches\modules-2\files-2.1\{0}\{1}\{2}" -f $Group, $Name, $Version)
  if (-not (Test-Path -LiteralPath $moduleRoot)) {
    return $null
  }

  $pomName = "{0}-{1}.pom" -f $Name, $Version
  $pom = Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -Filter $pomName -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if ($null -eq $pom) {
    return $null
  }

  return $pom.FullName
}

function Get-ChildText {
  param(
    [System.Xml.XmlNode]$Node,
    [string]$Name
  )

  foreach ($child in $Node.ChildNodes) {
    if ($child.LocalName -eq $Name) {
      return $child.InnerText.Trim()
    }
  }

  return $null
}

function Get-PomLicenses {
  param([string]$PomPath)

  $pomXml = [xml](Get-Content -LiteralPath $PomPath -Raw)
  $licenseNodes = @(
    Select-Xml -Xml $pomXml -XPath "/*[local-name()='project']/*[local-name()='licenses']/*[local-name()='license']"
  )
  $licenses = @()

  foreach ($licenseNode in $licenseNodes) {
    $node = $licenseNode.Node
    $name = Get-ChildText -Node $node -Name "name"
    $url = Get-ChildText -Node $node -Name "url"
    $distribution = Get-ChildText -Node $node -Name "distribution"

    if ([string]::IsNullOrWhiteSpace($name) -and
        [string]::IsNullOrWhiteSpace($url) -and
        [string]::IsNullOrWhiteSpace($distribution)) {
      continue
    }

    $licenses += [pscustomobject]@{
      name = $name
      url = $url
      distribution = $distribution
    }
  }

  return $licenses
}

function Get-ObjectPropertyValue {
  param(
    [object]$Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function ConvertTo-StringList {
  param([object]$Value)

  if ($null -eq $Value) {
    return @()
  }

  if ($Value -is [string]) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
      return @()
    }
    return @($Value)
  }

  $items = @()
  foreach ($item in @($Value)) {
    if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
      $items += [string]$item
    }
  }

  return $items
}

function Test-AnyExactMatch {
  param(
    [string]$Actual,
    [object]$Expected
  )

  $expectedValues = @(ConvertTo-StringList -Value $Expected)
  if ($expectedValues.Count -eq 0) {
    return $true
  }

  foreach ($value in $expectedValues) {
    if ($Actual.Equals($value, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Test-AnyPrefixMatch {
  param(
    [string]$Actual,
    [object]$ExpectedPrefixes
  )

  $prefixValues = @(ConvertTo-StringList -Value $ExpectedPrefixes)
  if ($prefixValues.Count -eq 0) {
    return $true
  }

  foreach ($value in $prefixValues) {
    if ($Actual.StartsWith($value, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Test-LicenseOverrideMatch {
  param(
    [object]$Rule,
    [object]$Module
  )

  $hasMatcher = $false

  $moduleId = Get-ObjectPropertyValue -Object $Rule -Name "module_id"
  if (@(ConvertTo-StringList -Value $moduleId).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyExactMatch -Actual $Module.module_id -Expected $moduleId)) {
      return $false
    }
  }

  $modulePrefix = Get-ObjectPropertyValue -Object $Rule -Name "module_prefix"
  if (@(ConvertTo-StringList -Value $modulePrefix).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyPrefixMatch -Actual $Module.module_id -ExpectedPrefixes $modulePrefix)) {
      return $false
    }
  }

  $group = Get-ObjectPropertyValue -Object $Rule -Name "group"
  if (@(ConvertTo-StringList -Value $group).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyExactMatch -Actual $Module.group -Expected $group)) {
      return $false
    }
  }

  $groupPrefix = Get-ObjectPropertyValue -Object $Rule -Name "group_prefix"
  if (@(ConvertTo-StringList -Value $groupPrefix).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyPrefixMatch -Actual $Module.group -ExpectedPrefixes $groupPrefix)) {
      return $false
    }
  }

  $name = Get-ObjectPropertyValue -Object $Rule -Name "name"
  if (@(ConvertTo-StringList -Value $name).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyExactMatch -Actual $Module.name -Expected $name)) {
      return $false
    }
  }

  $namePrefix = Get-ObjectPropertyValue -Object $Rule -Name "name_prefix"
  if (@(ConvertTo-StringList -Value $namePrefix).Count -gt 0) {
    $hasMatcher = $true
    if (-not (Test-AnyPrefixMatch -Actual $Module.name -ExpectedPrefixes $namePrefix)) {
      return $false
    }
  }

  return $hasMatcher
}

function Get-LicenseOverride {
  param(
    [object[]]$Rules,
    [object]$Module
  )

  foreach ($rule in @($Rules)) {
    if (Test-LicenseOverrideMatch -Rule $rule -Module $Module) {
      return $rule
    }
  }

  return $null
}

function ConvertTo-OverrideLicenses {
  param([object]$Rule)

  $licenseRows = @()
  foreach ($license in @(Get-ObjectPropertyValue -Object $Rule -Name "licenses")) {
    $licenseRows += [pscustomobject]@{
      name = Get-ObjectPropertyValue -Object $license -Name "name"
      url = Get-ObjectPropertyValue -Object $license -Name "url"
      distribution = Get-ObjectPropertyValue -Object $license -Name "distribution"
      spdx = Get-ObjectPropertyValue -Object $license -Name "spdx"
      evidence_url = Get-ObjectPropertyValue -Object $license -Name "evidence_url"
      evidence_note = Get-ObjectPropertyValue -Object $license -Name "evidence_note"
    }
  }

  return $licenseRows
}

function Get-LicenseOverrides {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  return @($payload.rules)
}

function Add-ModuleConfiguration {
  param(
    [hashtable]$Modules,
    [string]$Group,
    [string]$Name,
    [string]$Version,
    [string]$Configuration
  )

  $key = "{0}:{1}:{2}" -f $Group, $Name, $Version
  if (-not $Modules.ContainsKey($key)) {
    $Modules[$key] = [pscustomobject]@{
      group = $Group
      name = $Name
      version = $Version
      module_id = $key
      configurations = [System.Collections.Generic.List[string]]::new()
    }
  }

  if (-not $Modules[$key].configurations.Contains($Configuration)) {
    [void]$Modules[$key].configurations.Add($Configuration)
  }
}

function Test-GradleDependencyReportLine {
  param([string]$Line)

  if ([string]::IsNullOrWhiteSpace($Line)) {
    return $false
  }

  if ($Line -match "^\s*(w:|e:)\s+") {
    return $false
  }

  if ($Line -match "^\[Incubating\]") {
    return $false
  }

  return ($Line -match "^\s*(\|\s+)*(\\---|\+---)")
}

function Get-DependencyModules {
  param(
    [string[]]$Lines,
    [string]$Configuration,
    [hashtable]$Modules
  )

  $modulePattern = [regex]"(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]+):([A-Za-z0-9_.-]+):([A-Za-z0-9_.+\-]+)(?:\s*->\s*([A-Za-z0-9_.+\-]+))?"

  foreach ($line in $Lines) {
    if (-not (Test-GradleDependencyReportLine -Line $line)) {
      continue
    }

    $match = $modulePattern.Match($line)
    if (-not $match.Success) {
      continue
    }

    $version = $match.Groups[3].Value
    if ($match.Groups[4].Success -and -not [string]::IsNullOrWhiteSpace($match.Groups[4].Value)) {
      $version = $match.Groups[4].Value
    }

    Add-ModuleConfiguration `
      -Modules $Modules `
      -Group $match.Groups[1].Value `
      -Name $match.Groups[2].Value `
      -Version $version `
      -Configuration $Configuration
  }
}

function Invoke-GradleDependencyReport {
  param(
    [string]$Configuration,
    [string]$ReportPath
  )

  Push-Location $androidRoot
  try {
    $gradleArgs = @(":app:dependencies", "--configuration", $Configuration, "--console=plain", "--no-daemon")
    $output = & $GradleCommand @gradleArgs 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  $lines = @($output | ForEach-Object { $_.ToString() })
  $publicLines = @($lines | ForEach-Object { ConvertTo-PublicEvidenceLine -Line $_ })
  Write-Utf8NoBomLines -Path $ReportPath -Lines $publicLines

  if ($exitCode -ne 0) {
    throw "Gradle dependency report for $Configuration failed with exit code $exitCode. See $ReportPath."
  }

  return $publicLines
}

function Format-TableValue {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  return $Value.Replace("|", "\|")
}

function Write-MarkdownEvidence {
  param(
    [string]$Path,
    [object]$Payload
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("# Android Gradle/Maven License Evidence")
  $lines.Add("")
  $lines.Add("Generated: $($Payload.generated_at)")
  $lines.Add("Build mode: $($Payload.build_mode)")
  $lines.Add("Version tag: $($Payload.version_tag)")
  $lines.Add("Evidence status: $($Payload.evidence_status)")
  $lines.Add("")
  $lines.Add('This evidence is generated from Gradle dependency reports for the Android release APK classpaths. It does not read or embed `google-services.json`.')
  $lines.Add("Gradle warning/progress lines are excluded from module parsing, and local file URI prefixes are normalized for public evidence.")
  $lines.Add("POM license metadata is preferred. Source overrides are applied only when Gradle resolves a runtime module but the local Maven POM metadata is absent or has no `<licenses>` block.")
  $lines.Add("")
  $lines.Add("## Coverage Summary")
  $lines.Add("")
  $lines.Add(("- Total modules: {0}" -f $Payload.summary.total_modules))
  $lines.Add(("- POM license modules: {0}" -f $Payload.summary.pom_license_modules))
  $lines.Add(("- Override evidence modules: {0}" -f $Payload.summary.override_license_modules))
  $lines.Add(("- Remaining missing license modules: {0}" -f $Payload.summary.missing_license_modules))
  $lines.Add("")
  $lines.Add("## Dependency Reports")
  $lines.Add("")
  foreach ($configuration in $Payload.configurations) {
    $lines.Add(('- `{0}`: `{1}`' -f $configuration.name, $configuration.report_path))
  }
  $lines.Add("")
  $lines.Add("## Maven Modules")
  $lines.Add("")
  $lines.Add("| Module | Configurations | License metadata | Source | Evidence |")
  $lines.Add("| --- | --- | --- | --- | --- |")

  foreach ($module in @($Payload.modules)) {
    $licenses = @($module.licenses | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_.name)) {
          $_.name
        } elseif (-not [string]::IsNullOrWhiteSpace($_.url)) {
          $_.url
        } else {
          "UNKNOWN"
        }
      })

    if ($licenses.Count -eq 0) {
      $licenseText = "missing"
    } else {
      $licenseText = ($licenses -join "<br>")
    }

    $source = $module.license_metadata_source
    if ($source -eq "override" -and -not [string]::IsNullOrWhiteSpace($module.override_id)) {
      $source = "override: $($module.override_id)"
    }

    $evidence = $module.pom_evidence_path
    if ($module.license_metadata_source -eq "override" -and -not [string]::IsNullOrWhiteSpace($module.override_evidence_url)) {
      $evidence = $module.override_evidence_url
    }
    if ([string]::IsNullOrWhiteSpace($evidence)) {
      $evidence = $module.pom_url
    }
    if ([string]::IsNullOrWhiteSpace($evidence)) {
      $evidence = "missing"
    }

    $lines.Add(('| `{0}` | `{1}` | {2} | `{3}` | `{4}` |' -f
        $module.module_id,
        (@($module.configurations) -join ", "),
        (Format-TableValue -Value $licenseText),
        $source,
        $evidence))
  }

  if (@($Payload.override_evidence).Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Override Evidence Applied")
    $lines.Add("")
    $lines.Add("| Override | Modules | Evidence | Rationale |")
    $lines.Add("| --- | ---: | --- | --- |")
    foreach ($override in @($Payload.override_evidence)) {
      $lines.Add(('| `{0}` | {1} | `{2}` | {3} |' -f
          $override.id,
          $override.module_count,
          $override.evidence_url,
          (Format-TableValue -Value $override.rationale)))
    }
  }

  if (@($Payload.missing_license_modules).Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Remaining Missing License Metadata")
    $lines.Add("")
    foreach ($group in @($Payload.license_coverage_by_group | Where-Object { $_.missing_license_modules -gt 0 } | Sort-Object group | Sort-Object missing_license_modules -Descending)) {
      $lines.Add(("- `{0}`: {1}" -f $group.group, $group.missing_license_modules))
    }
    $lines.Add("")
    foreach ($module in @($Payload.missing_license_modules | Sort-Object group, module_id)) {
      $lines.Add(('- `{0}`' -f $module.module_id))
    }
  }

  $lines.Add("")
  $lines.Add("## Release Use")
  $lines.Add("")
  $lines.Add("- Regenerate this evidence for release APKs and whenever Gradle, Flutter plugin, Firebase, or Android runtime dependencies change.")
  $lines.Add("- Use the JSON file for machine-readable module/license metadata and the raw Gradle reports for dependency graph evidence.")
  $lines.Add("- Keep actual Firebase client configuration outside the release evidence bundle.")

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

function Write-GroupReport {
  param(
    [string]$Path,
    [object]$Payload
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("# Android Gradle License Coverage By Group")
  $lines.Add("")
  $lines.Add("Generated: $($Payload.generated_at)")
  $lines.Add("Version tag: $($Payload.version_tag)")
  $lines.Add("")
  $lines.Add("| Group | Total | POM | Override | Missing |")
  $lines.Add("| --- | ---: | ---: | ---: | ---: |")
  foreach ($group in @($Payload.license_coverage_by_group | Sort-Object group | Sort-Object missing_license_modules -Descending)) {
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} |' -f
        $group.group,
        $group.total_modules,
        $group.pom_license_modules,
        $group.override_license_modules,
        $group.missing_license_modules))
  }

  if (@($Payload.missing_license_modules).Count -gt 0) {
    $lines.Add("")
    $lines.Add("## Remaining Missing Modules")
    $lines.Add("")
    foreach ($module in @($Payload.missing_license_modules | Sort-Object group, module_id)) {
      $lines.Add(('- `{0}` ({1})' -f $module.module_id, $module.pom_status))
    }
  }

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

if (-not (Test-Path -LiteralPath $GradleCommand)) {
  throw "Gradle wrapper not found: $GradleCommand"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$configurationNames = @("releaseRuntimeClasspath", "coreLibraryDesugaring")
$modulesByKey = @{}
$configurationRows = @()

foreach ($configuration in $configurationNames) {
  $reportPath = Join-Path $OutputDir ("android-gradle-{0}.txt" -f $configuration)
  $lines = Invoke-GradleDependencyReport -Configuration $configuration -ReportPath $reportPath
  Get-DependencyModules -Lines $lines -Configuration $configuration -Modules $modulesByKey
  $configurationRows += [pscustomobject]@{
    name = $configuration
    report_path = ConvertTo-RepoRelativePath -Path $reportPath
  }
}

$gradleUserHome = Get-GradleUserHome
$licenseOverrides = Get-LicenseOverrides -Path $OverridesPath
$moduleRows = @()
$missingLicenseRows = @()

foreach ($module in @($modulesByKey.Values | Sort-Object group, name, version)) {
  $pomPath = Find-GradlePom -GradleUserHome $gradleUserHome -Group $module.group -Name $module.name -Version $module.version
  $pomEvidencePath = $null
  $pomSha256 = $null
  $licenses = @()

  if ($null -ne $pomPath) {
    $pomEvidencePath = ConvertTo-GradleCacheEvidencePath -Path $pomPath -GradleUserHome $gradleUserHome
    $pomSha256 = Get-Sha256Hex -Path $pomPath
    $licenses = @(Get-PomLicenses -PomPath $pomPath)
  }

  $pomStatus = "pom_not_found"
  if ($null -ne $pomPath -and $licenses.Count -gt 0) {
    $pomStatus = "found_with_license"
  } elseif ($null -ne $pomPath) {
    $pomStatus = "found_without_license"
  }

  $licenseMetadataSource = "pom"
  $overrideId = $null
  $overrideDescription = $null
  $overrideRationale = $null
  $overrideEvidenceUrl = $null
  $overrideEvidenceNote = $null

  if ($licenses.Count -eq 0) {
    $override = Get-LicenseOverride -Rules $licenseOverrides -Module $module
    if ($null -ne $override) {
      $overrideLicenses = @(ConvertTo-OverrideLicenses -Rule $override)
      if ($overrideLicenses.Count -gt 0) {
        $licenses = $overrideLicenses
        $licenseMetadataSource = "override"
        $overrideId = Get-ObjectPropertyValue -Object $override -Name "id"
        $overrideDescription = Get-ObjectPropertyValue -Object $override -Name "description"
        $overrideRationale = Get-ObjectPropertyValue -Object $override -Name "rationale"
        $overrideEvidenceUrl = Get-ObjectPropertyValue -Object $override -Name "evidence_url"
        $overrideEvidenceNote = Get-ObjectPropertyValue -Object $override -Name "evidence_note"
      } else {
        $licenseMetadataSource = "missing"
      }
    } else {
      $licenseMetadataSource = "missing"
    }
  }

  $row = [pscustomobject]@{
    group = $module.group
    name = $module.name
    version = $module.version
    module_id = $module.module_id
    configurations = @($module.configurations)
    licenses = $licenses
    license_metadata_source = $licenseMetadataSource
    pom_status = $pomStatus
    pom_evidence_path = $pomEvidencePath
    pom_sha256 = $pomSha256
    pom_url = Get-MavenPomUrl -Group $module.group -Name $module.name -Version $module.version
    override_id = $overrideId
    override_description = $overrideDescription
    override_rationale = $overrideRationale
    override_evidence_url = $overrideEvidenceUrl
    override_evidence_note = $overrideEvidenceNote
  }

  $moduleRows += $row

  if ($licenses.Count -eq 0) {
    $missingLicenseRows += [pscustomobject]@{
      group = $module.group
      module_id = $module.module_id
      configurations = @($module.configurations)
      pom_status = $pomStatus
      pom_evidence_path = $pomEvidencePath
      pom_url = $row.pom_url
    }
  }
}

$coverageByGroup = @()
foreach ($group in @($moduleRows | Group-Object group)) {
  $items = @($group.Group)
  $coverageByGroup += [pscustomobject]@{
    group = $group.Name
    total_modules = $items.Count
    pom_license_modules = @($items | Where-Object { $_.license_metadata_source -eq "pom" }).Count
    override_license_modules = @($items | Where-Object { $_.license_metadata_source -eq "override" }).Count
    missing_license_modules = @($items | Where-Object { $_.license_metadata_source -eq "missing" }).Count
  }
}

$overrideEvidenceRows = @()
foreach ($group in @($moduleRows | Where-Object { $_.license_metadata_source -eq "override" } | Group-Object override_id)) {
  $first = @($group.Group | Select-Object -First 1)[0]
  $overrideEvidenceRows += [pscustomobject]@{
    id = $group.Name
    module_count = @($group.Group).Count
    evidence_url = $first.override_evidence_url
    evidence_note = $first.override_evidence_note
    rationale = $first.override_rationale
  }
}

$summary = [pscustomobject]@{
  total_modules = $moduleRows.Count
  pom_license_modules = @($moduleRows | Where-Object { $_.license_metadata_source -eq "pom" }).Count
  override_license_modules = @($moduleRows | Where-Object { $_.license_metadata_source -eq "override" }).Count
  missing_license_modules = $missingLicenseRows.Count
  artifact_scope = "release APK runtime classpaths"
  build_only_modules_excluded = $true
}

$payload = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  build_mode = $BuildMode
  version_tag = $VersionTag
  evidence_status = if ($missingLicenseRows.Count -gt 0) { "partial_missing_pom_license_metadata" } else { "complete" }
  generation_notes = @(
    "Gradle warning/progress lines are excluded from module parsing.",
    "Gradle conflict lines are normalized to the selected module version.",
    "Local file URI prefixes are normalized before raw reports are written.",
    "Build-only Gradle plugins are not included; this collector is scoped to release APK runtime classpaths."
  )
  gradle_command = ConvertTo-RepoRelativePath -Path $GradleCommand
  override_source = if (Test-Path -LiteralPath $OverridesPath) { ConvertTo-RepoRelativePath -Path $OverridesPath } else { $null }
  source = "Gradle :app:dependencies reports"
  summary = $summary
  configurations = $configurationRows
  modules = $moduleRows
  license_coverage_by_group = $coverageByGroup
  override_evidence = $overrideEvidenceRows
  missing_license_modules = $missingLicenseRows
}

$jsonPath = Join-Path $OutputDir "THIRD_PARTY_LICENSES.android-gradle.json"
$markdownPath = Join-Path $OutputDir "THIRD_PARTY_NOTICES.android-gradle.md"
$groupReportPath = Join-Path $OutputDir "THIRD_PARTY_LICENSES.android-gradle.groups.md"

Write-Utf8NoBomText -Path $jsonPath -Text (($payload | ConvertTo-Json -Depth 10) + "`n")
Write-MarkdownEvidence -Path $markdownPath -Payload $payload
Write-GroupReport -Path $groupReportPath -Payload $payload

Write-Host "[android-gradle-license] Wrote $jsonPath"
Write-Host "[android-gradle-license] Wrote $markdownPath"
Write-Host "[android-gradle-license] Wrote $groupReportPath"
