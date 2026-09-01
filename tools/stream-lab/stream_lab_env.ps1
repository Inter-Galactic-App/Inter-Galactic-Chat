function Import-StreamLabLocalEnv {
  param([string]$RepoRoot)

  $loaded = Get-Variable -Name StreamLabLocalEnvLoaded -Scope Script -ErrorAction SilentlyContinue
  if ($loaded -and $loaded.Value) {
    return
  }

  $envPath = $env:INTERGALACTIC_STREAM_TEST_ENV
  if ([string]::IsNullOrWhiteSpace($envPath)) {
    $envPath = Join-Path $RepoRoot '.env.stream-test.local'
  }
  $envPath = [Environment]::ExpandEnvironmentVariables($envPath)

  if (Test-Path -LiteralPath $envPath) {
    foreach ($line in Get-Content -LiteralPath $envPath) {
      $trimmed = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
        continue
      }
      if ($trimmed -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        continue
      }
      $name = $Matches[1]
      $value = $Matches[2].Trim()
      if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
          ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      $value = [Environment]::ExpandEnvironmentVariables($value)
      $value = [regex]::Replace($value, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
        param($match)
        $replacement = [Environment]::GetEnvironmentVariable($match.Groups[1].Value)
        if ($null -eq $replacement) {
          return $match.Value
        }
        return $replacement
      })
      $value = [regex]::Replace($value, '\$env:([A-Za-z_][A-Za-z0-9_]*)', {
        param($match)
        $replacement = [Environment]::GetEnvironmentVariable($match.Groups[1].Value)
        if ($null -eq $replacement) {
          return $match.Value
        }
        return $replacement
      })

      if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        Set-Item -Path "Env:$name" -Value $value
      }
    }
  }

  $script:StreamLabLocalEnvLoaded = $true
}

function Get-StreamLabEnvValue {
  param([string]$Name)

  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ''
  }
  return [Environment]::ExpandEnvironmentVariables($value.Trim())
}

function Resolve-StreamLabConfiguredPath {
  param(
    [string]$Value,
    [string]$BasePath
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ''
  }
  if ([System.IO.Path]::IsPathRooted($Value)) {
    return $Value
  }
  return Join-Path $BasePath $Value
}

function Resolve-StreamLabWorkspaceRoot {
  param([string]$RepoRoot)

  $configured = Get-StreamLabEnvValue 'INTERGALACTIC_WORKSPACE_ROOT'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    return (Resolve-StreamLabConfiguredPath -Value $configured -BasePath $RepoRoot)
  }
  return (Resolve-Path (Join-Path $RepoRoot '..\..')).Path
}

function Resolve-StreamLabDirectory {
  param(
    [string]$RepoRoot,
    [string]$WorkspaceRoot
  )

  $configured = Get-StreamLabEnvValue 'INTERGALACTIC_STREAM_LAB_DIR'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    return (Resolve-StreamLabConfiguredPath -Value $configured -BasePath $RepoRoot)
  }
  return Join-Path $WorkspaceRoot 'runtime\stream-lab'
}

function Resolve-StreamLabOutputRoot {
  param(
    [string]$RepoRoot,
    [string]$WorkspaceRoot
  )

  $configured = Get-StreamLabEnvValue 'INTERGALACTIC_STREAM_LAB_OUTPUT_ROOT'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    return (Resolve-StreamLabConfiguredPath -Value $configured -BasePath $RepoRoot)
  }
  return Join-Path (Resolve-StreamLabDirectory -RepoRoot $RepoRoot -WorkspaceRoot $WorkspaceRoot) 'local-results'
}

function Resolve-StreamLabWebrtcBuildRoot {
  param(
    [string]$RepoRoot,
    [string]$WorkspaceRoot
  )

  $configured = Get-StreamLabEnvValue 'INTERGALACTIC_WEBRTC_BUILD_ROOT'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    return (Resolve-StreamLabConfiguredPath -Value $configured -BasePath $RepoRoot)
  }
  return Join-Path $WorkspaceRoot 'webrtc-build'
}

function Resolve-StreamLabAppStreamTestDirectory {
  param([string]$RepoRoot)

  $configured = Get-StreamLabEnvValue 'INTERGALACTIC_STREAM_TEST_APP_DIR'
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    return (Resolve-StreamLabConfiguredPath -Value $configured -BasePath $RepoRoot)
  }
  if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    throw 'APPDATA is not set; set INTERGALACTIC_STREAM_TEST_APP_DIR in .env.stream-test.local.'
  }
  return (Join-Path $env:APPDATA 'Inter Galactic\Inter Galactic\logs\stream-tests')
}
