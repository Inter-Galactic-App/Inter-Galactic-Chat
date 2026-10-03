[CmdletBinding()]
param(
  [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

# These are project workflow labels, including generic queue routing, not
# recipient-facing licence facts. The JSON exemption is intentionally
# field-based: `license_text` is verbatim third-party legal text and must never
# be rewritten by this policy check.
$forbidden = '(?i)(?:\bS&C\b|\bREVIEW\b|(?-i:\bAUDIO\b)|Owner\s*/\s*next validation|Validation owner|\bRELEASE PIPELINE\b|\bapp owner\b|Handoff\s*/\s*queue\s*/\s*release record|\bqueue\b)'
$jsonPath = Join-Path $RepositoryRoot 'docs/release/THIRD_PARTY_LICENSES.json'
$markdownPaths = @(
  'docs/release/THIRD_PARTY_NOTICES.md',
  'docs/policies/THIRD_PARTY_NOTICES.md',
  'docs/policies/SOURCE_OFFER.md',
  'docs/release/ASSET_PROVENANCE.md',
  # Authored receipts added by this branch. The sibling lowercase WebRTC file
  # is an unmodified verbatim upstream notice packet; it is deliberately not
  # scanned because its legal text must remain byte-identical.
  'docs/release/evidence/license-sources/PACKAGED-LICENCE-TEXT-PROVENANCE.md',
  'docs/release/evidence/license-sources/libwebrtc-windows/0.8.2+1008.md',
  'docs/release/evidence/license-sources/dart-vodozemac-ios-patch/SOURCE.md',
  'docs/release/evidence/corresponding-source-holding/HOLDING.json',
  'docs/release/evidence/license-sources/apple/APPLE-CORRESPONDING-SOURCE.md',
  'docs/release/evidence/license-sources/libmpv/THIRD_PARTY_NOTICES.libmpv.md',
  'docs/release/evidence/published-source-surface/SOURCE-CORRESPONDENCE-0.8.1+1004.md',
  'docs/release/evidence/license-sources/android-native-payloads/AAR-ORIGINS-0.8.1+1003.md',
  'docs/release/evidence/license-sources/android-native-payloads/CAMERAX-IMAGE-PROCESSING-LIBYUV-1.6.0.md',
  'docs/release/evidence/license-sources/android-native-payloads/CAMERAX-SURFACE-UTIL-1.6.0.md',
  'docs/release/evidence/license-sources/android-native-payloads/LIVEKIT-NOISE-2.0.0.md',
  'docs/release/evidence/license-sources/android-native-payloads/WEBRTC-SDK-ANDROID-137.7151.04.md'
) | ForEach-Object { Join-Path $RepositoryRoot $_ }

function Find-JsonWorkflowText {
  param([object]$Value, [string]$Path = '$', [string]$FieldName = '')

  if ($FieldName -eq 'license_text') { return }
  if ($Value -is [string]) {
    if ($Value -match $forbidden) {
      [pscustomobject]@{ Path = $Path; Text = $Value }
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) {
      Find-JsonWorkflowText -Value $item -Path "$Path[$index]" -FieldName ''
      $index++
    }
    return
  }
  if ($null -ne $Value) {
    foreach ($property in $Value.PSObject.Properties) {
      Find-JsonWorkflowText -Value $property.Value -Path "$Path.$($property.Name)" -FieldName $property.Name
    }
  }
}

$failures = @()
$json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
$failures += Find-JsonWorkflowText -Value $json

foreach ($path in $markdownPaths) {
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $path) {
    $lineNumber++
    if ($line -match $forbidden) {
      $failures += [pscustomobject]@{ Path = "$path`:$lineNumber"; Text = $line }
    }
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "Public workflow vocabulary at $($_.Path): $($_.Text)" }
  throw "Public licence-disclosure boundary check found $($failures.Count) project-workflow reference(s)."
}

Write-Host 'Public licence-disclosure boundary check passed.'
