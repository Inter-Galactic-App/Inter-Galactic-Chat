#Requires -Version 7.0
<#
.SYNOPSIS
  Regression cases for ConvertTo-PublicEvidenceLine in the Android license
  evidence collectors.

.DESCRIPTION
  These collectors write committed, published third-party-notice evidence, and
  ConvertTo-PublicEvidenceLine is the only thing standing between Gradle's raw
  output and that published file. AGENTS.md bars local paths from published
  material, so a gap in these matchers is a privacy defect rather than a
  cosmetic one.

  WHY THIS FILE EXISTS. On 2026-08-01 the matchers were cleared by executing
  them against seven cases - and none of those cases contained a space. The
  matchers bounded each path with [^\s]*, so they stopped at the first space and
  republished the remainder:

      C:\Users\Alice\Private Folder\secret.txt
        -> redacted-path/Private Folder\secret.txt

  The directory name the redaction exists to remove survived. Executing a regex
  is only as good as the case list, which is the whole argument for keeping the
  list in the repository instead of in someone's terminal history.

  The same defect was present in the file:/// rules and was NOT reported by the
  external reviewer; it was found only because this list covers file URIs too.

.NOTES
  Run:  pwsh -File intergalactic/scripts/tests/Test-PublicEvidenceRedaction.ps1
  Exits 0 when every case passes, 1 otherwise.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = Split-Path -Parent $PSScriptRoot

# Both collectors must carry a byte-identical copy of this function. A
# divergence is a silent privacy gap in whichever one falls behind, so the
# comparison below is part of the test rather than a nicety.
$collectors = @(
  'collect_android_gradle_license_evidence.ps1'
  'collect_android_oss_licenses_baseline.ps1'
)

function Get-RedactionFunctionSource {
  param([string]$Path)

  $src = Get-Content -LiteralPath $Path -Raw
  $start = $src.IndexOf('function ConvertTo-PublicEvidenceLine')
  if ($start -lt 0) {
    throw "ConvertTo-PublicEvidenceLine not found in $Path"
  }

  # Brace-COUNTED, not "first newline-brace". Scanning for the first "`n}" works
  # only while the function contains no nested block, and would SILENTLY return
  # a truncated function the moment either collector gains an if/foreach whose
  # closing brace sits at column 0. A truncated extract would still parse and
  # still run - it would just quietly stop applying some of the matchers, which
  # is the worst possible failure for a redaction test: green, and testing less
  # than it claims.
  $depth = 0
  $seenOpen = $false
  for ($i = $start; $i -lt $src.Length; $i++) {
    $ch = $src[$i]
    if ($ch -eq '{') {
      $depth++
      $seenOpen = $true
    } elseif ($ch -eq '}') {
      $depth--
      if ($seenOpen -and $depth -eq 0) {
        return $src.Substring($start, $i - $start + 1)
      }
    }
  }
  throw "Could not find the end of ConvertTo-PublicEvidenceLine in $Path"
}

# Each case is: input, and the substrings that must NOT survive redaction.
# Asserting on "what must not appear" rather than on an exact output keeps the
# test from failing every time the redaction placeholder wording changes, while
# still failing hard on an actual leak.
$leakCases = @(
  @{ Name = 'drive path';              Line = 'C:\Users\Alice\secret.txt';                    Forbidden = @('Alice') }
  @{ Name = 'drive path with space';   Line = 'C:\Users\Alice\Private Folder\secret.txt';     Forbidden = @('Alice', 'Private Folder') }
  @{ Name = 'two spaced directories';  Line = 'Z:\My Build\Out Dir\app.jar';                  Forbidden = @('My Build', 'Out Dir') }
  @{ Name = 'unc path';                Line = '\\host\share\secret.txt';                      Forbidden = @('host\share') }
  @{ Name = 'unc path with space';     Line = '\\host\share\Private Folder\secret.txt';       Forbidden = @('host\share', 'Private Folder') }
  @{ Name = 'file uri';                Line = 'file:///C:/Users/Alice/x.pom';                 Forbidden = @('Alice') }
  @{ Name = 'file uri with space';     Line = 'file:///C:/Users/Alice/Private Folder/x.pom';  Forbidden = @('Alice', 'Private Folder') }
  @{ Name = 'posix file uri w/ space'; Line = 'file:///home/alice/My Repo/x.pom';             Forbidden = @('My Repo') }
  @{ Name = 'path preceding a URL';    Line = 'C:\a\b see https://repo.maven.org/x-1.0.pom';  Forbidden = @('C:\a') }
  @{ Name = 'two paths on one line';   Line = 'from C:\a\b and D:\c\d';                       Forbidden = @('C:\a', 'D:\c') }
)

# The guard against over-redaction. These lines are the reason the evidence
# exists; redacting them would destroy the report's value. The (?<![A-Za-z])
# lookbehind and the ':' exclusion in the segment classes are what protect them.
$preserveCases = @(
  @{ Name = 'maven POM URL';    Line = 'https://repo.maven.apache.org/maven2/foo/bar-1.0.pom' }
  @{ Name = 'maven coordinate'; Line = 'com.example:lib:1.0' }
  @{ Name = 'gradle tree line'; Line = '+--- androidx.core:core:1.13.1' }
  @{ Name = 'plain prose';      Line = 'Note: see the project README for details.' }
)

$failures = New-Object System.Collections.Generic.List[string]
$outputs = @{}

foreach ($collector in $collectors) {
  $path = Join-Path $scriptsDir $collector
  if (-not (Test-Path -LiteralPath $path)) {
    $failures.Add("Missing collector: $path")
    continue
  }

  # Load this collector's copy of the function. [ScriptBlock]::Create rather than
  # Invoke-Expression: same result, but PSScriptAnalyzer flags Invoke-Expression
  # and there is no reason for a security-adjacent test to carry that warning.
  . ([ScriptBlock]::Create((Get-RedactionFunctionSource -Path $path)))

  foreach ($case in $leakCases) {
    $result = ConvertTo-PublicEvidenceLine -Line $case.Line
    $outputs["$($case.Name)|$collector"] = $result
    foreach ($forbidden in $case.Forbidden) {
      if ($result.Contains($forbidden)) {
        $failures.Add("[$collector] '$($case.Name)' leaked '$forbidden': $result")
      }
    }
  }

  foreach ($case in $preserveCases) {
    $result = ConvertTo-PublicEvidenceLine -Line $case.Line
    $outputs["$($case.Name)|$collector"] = $result
    if ($result -ne $case.Line) {
      $failures.Add("[$collector] '$($case.Name)' was altered but must be preserved: '$($case.Line)' -> '$result'")
    }
  }
}

# Divergence check: the same input must redact identically in both collectors.
$allCaseNames = @($leakCases.Name) + @($preserveCases.Name)
foreach ($name in $allCaseNames) {
  $seen = @($collectors | ForEach-Object { $outputs["$name|$_"] } | Select-Object -Unique)
  if ($seen.Count -gt 1) {
    $failures.Add("Collectors disagree on '$name': $($seen -join ' <> ')")
  }
}

if ($failures.Count -gt 0) {
  Write-Host "FAILED ($($failures.Count)):" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}

$caseCount = ($leakCases.Count + $preserveCases.Count) * $collectors.Count
Write-Host "Public evidence redaction: $caseCount case(s) passed across $($collectors.Count) collector(s)."
exit 0
