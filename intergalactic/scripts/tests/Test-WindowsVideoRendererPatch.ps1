#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install_patched_libwebrtc.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
  throw "Installer does not parse: $($parseErrors[0].Message)"
}
$patchFunction = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Install-WindowsVideoRendererLatestFramePatch'
}, $true)
if ($null -eq $patchFunction) {
  throw 'Windows video renderer patch function is missing.'
}

function Assert-PathInside { param($Parent, $Child) }
function New-IntergalacticPatchBackup {
  param($Target, $Backup, $Source)
  [System.IO.File]::WriteAllText($Backup, $Source)
  return $Backup
}
function Update-SourceText {
  param($Source, $Pattern, $Replacement, $Description)
  $found = [regex]::Matches($Source, $Pattern)
  if ($found.Count -ne 1) {
    throw "$Description expected one function, found $($found.Count)."
  }
  return [regex]::Replace($Source, $Pattern, [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)
    return $Replacement
  })
}
. ([scriptblock]::Create($patchFunction.Extent.Text))

$root = Join-Path ([System.IO.Path]::GetTempPath()) "ig-renderer-patch-$([guid]::NewGuid().ToString('N'))"
$sourceDir = Join-Path $root 'common\cpp\src'
$target = Join-Path $sourceDir 'flutter_video_renderer.cc'
try {
  [System.IO.Directory]::CreateDirectory($sourceDir) | Out-Null
  $legacy = @'
const FlutterDesktopPixelBuffer* FlutterVideoRenderer::CopyPixelBuffer(
    size_t width, size_t height) const {
  // Inter Galactic: do not hold renderer frame mutex while converting.
  return pixel_buffer.get();
}

void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {}
'@
  [System.IO.File]::WriteAllText($target, $legacy)
  $backup = Install-WindowsVideoRendererLatestFramePatch -PackageRoot $root
  if ($backup -ne "$target.intergalactic-renderer-backup") {
    throw 'Existing patch was not backed up before upgrade.'
  }
  $upgraded = [System.IO.File]::ReadAllText($target)
  foreach ($required in @(
      'retain pixel buffers through Flutter texture upload',
      'frame->width() <= 0 || frame->height() <= 0',
      'std::unique_ptr<uint8_t[]> pixels',
      'lease->pixel_buffer.release_callback',
      'lease->pixel_buffer.release_context = lease.get()',
      'return &lease.release()->pixel_buffer'
    )) {
    if (-not $upgraded.Contains($required)) {
      throw "Renderer patch missing lifetime guard: $required"
    }
  }
  $secondBackup = Install-WindowsVideoRendererLatestFramePatch -PackageRoot $root
  if ($null -ne $secondBackup -or [System.IO.File]::ReadAllText($target) -cne $upgraded) {
    throw 'Renderer patch is not idempotent.'
  }
  Write-Host 'Windows renderer patch upgrade and idempotence: PASS'
} finally {
  if (Test-Path -LiteralPath $root) {
    $resolvedRoot = [System.IO.Path]::GetFullPath($root)
    $tempPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedRoot.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove a renderer fixture outside the temp directory: $resolvedRoot"
    }
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}
