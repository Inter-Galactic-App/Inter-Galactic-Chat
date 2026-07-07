param(
  [int]$ProcessId = 0,
  [string]$AppExe = '',
  [string]$WindowTitle = 'Inter Galactic',
  [int]$StartupDelaySeconds = 12,
  [int]$DurationSeconds = 30,
  [int]$WarmupSeconds = 5,
  [int]$RecordingSeconds = 48,
  [int]$ActiveSegmentStartSeconds = 8,
  [int]$ActiveSegmentSeconds = 30,
  [double]$ReceiverProbeWindowMeasureStartSeconds = -1,
  [double]$ReceiverProbeWindowMeasureSeconds = -1,
  [int]$TimeoutSeconds = 180,
  [double]$MinUniqueFps = 25.0,
  [ValidateSet('default', 'wgc-only', 'directx-only', 'game-d3d11-hook-experimental')]
  [string]$WindowsBackendMode = 'game-d3d11-hook-experimental',
  [string]$OutputRoot = '',
  [string]$CaptureTargetExe = '',
  [string]$CaptureTargetTitle = 'Inter Galactic Capture Target',
  [int]$CaptureTargetWidth = 1280,
  [int]$CaptureTargetHeight = 720,
  [string]$CaptureTargetScene = 'high-motion',
  [string]$CaptureTargetFps = '60',
  [int]$CaptureTargetX = -2147483648,
  [int]$CaptureTargetY = -2147483648,
  [int]$AppWindowX = -2147483648,
  [int]$AppWindowY = -2147483648,
  [switch]$AllowBackgroundAppRecording,
  [int]$SourceProcessId = 0,
  [string]$SourceTitle = '',
  [switch]$StartBg3CameraRotation,
  [switch]$UseAppLaunchedCaptureTarget,
  [switch]$DummyNv12LiveSender,
  [int]$PublicationHandoffMaxWidth = 1280,
  [int]$PublicationHandoffMaxHeight = 720,
  [int]$PublicationHandoffMaxFps = 0,
  [int]$PublicationHandoffTargetFps = 30,
  [int]$PublicationHandoffBitrateKbps = 0,
  [int]$PublicationHandoffMinBitrateKbps = 0,
  [switch]$PublicationHandoffSingleLayer,
  [switch]$PreferHardwareEncoding,
  [switch]$ReceiverProbeEnabled,
  [ValidateSet('decode-only', 'render', 'local-preview', 'external-decode-only', 'external-render')]
  [string]$ReceiverProbeMode = 'decode-only',
  [string]$ReceiverProbeExe = '',
  [string]$ReceiverProbeAppExe = '',
  [ValidateRange(-1, 64)]
  [int]$ReceiverProbeMonitorIndex = -1,
  [switch]$ReceiverProbeVisualFrameMarker,
  [switch]$SourceFrameContentMarker,
  [ValidateSet('native-renderer-hash', 'stats-only')]
  [string]$ReceiverProbeFrameDiagnosticsMode = 'native-renderer-hash',
  [switch]$MaintainBg3FocusDuringRun,
  [ValidateRange(1, 30)]
  [int]$Bg3FocusIntervalSeconds = 3,
  [string]$CallRoomAddress = '',
  [string]$CallRoomClientId = '',
  [ValidateRange(0, 60)]
  [int]$CallRoomOpenSettleSeconds = 5,
  [switch]$SkipCallHotkey,
  [switch]$ClickJoinButtonAfterHotkey,
  [double]$JoinButtonRelativeX = 0.615,
  [double]$JoinButtonRelativeY = 0.905,
  [int]$JoinButtonSettleSeconds = 5,
  [string]$ExpectedCallWindowTitle = 'Test Voice',
  [ValidateRange(0, 120)]
  [int]$CallEntryVerifyTimeoutSeconds = 20,
  [switch]$SkipCallEntryVerification,
  [string[]]$Presets = @('smooth'),
  [int]$CropX = 345,
  [int]$CropY = 244,
  [int]$CropWidth = 448,
  [int]$CropHeight = 252,
  [ValidateSet('auto', 'ddagrab', 'gdigrab')]
  [string]$RecordingCaptureMode = 'auto',
  [ValidateSet('auto', 'h264_nvenc', 'libx264')]
  [string]$RecordingVideoCodec = 'auto',
  [int]$RecordingDdagrabOutputIndex = -1,
  [int]$RecordingDdagrabOriginX = 0,
  [int]$RecordingDdagrabOriginY = 0,
  [ValidateSet('', 'auto', 'ddagrab', 'gdigrab')]
  [string]$ReceiverProbeWindowRecordingCaptureMode = '',
  [ValidateSet('', 'auto', 'h264_nvenc', 'libx264')]
  [string]$ReceiverProbeWindowRecordingVideoCodec = '',
  [int]$ReceiverProbeWindowRecordingDdagrabOutputIndex = -1,
  [int]$ReceiverProbeWindowRecordingDdagrabOriginX = 0,
  [int]$ReceiverProbeWindowRecordingDdagrabOriginY = 0,
  [switch]$SkipReceiverProbeWindowRecording,
  [switch]$SkipSelfViewRecording,
  [switch]$KeepAppOpen,
  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'stream_lab_env.ps1')

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function New-SafeDirectory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
  }
}

function ConvertTo-ArgumentString([string[]]$Arguments) {
  return (($Arguments | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"' + ($_ -replace '"', '\"') + '"'
    } else {
      $_
    }
  }) -join ' ')
}

function New-ReceiverProbePipeName([string]$RunId) {
  $safeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) {
    'run'
  } else {
    $RunId -replace '[^A-Za-z0-9_.-]', '_'
  }
  return "intergalactic.receiver-probe.synthetic.$safeRunId.$([Guid]::NewGuid().ToString('N'))"
}

function Get-ChildProcessIds {
  param([Parameter(Mandatory = $true)] [int] $ParentProcessId)

  try {
    return @(
      Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentProcessId" |
        ForEach-Object { [int] $_.ProcessId }
    )
  } catch {
    return @()
  }
}

function Stop-ProcessTree {
  param([Parameter(Mandatory = $true)] [int] $RootProcessId)

  foreach ($childId in Get-ChildProcessIds -ParentProcessId $RootProcessId) {
    Stop-ProcessTree -RootProcessId $childId
  }

  Stop-Process -Id $RootProcessId -Force -ErrorAction SilentlyContinue
}

function Resolve-Ffmpeg {
  $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw 'ffmpeg was not found on PATH.'
  }
  return $command.Source
}

function Resolve-Ffprobe {
  $command = Get-Command ffprobe -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw 'ffprobe was not found on PATH.'
  }
  return $command.Source
}

function Test-FfmpegEncoder([string]$FfmpegExe, [string]$EncoderName) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfmpegExe
  $startInfo.Arguments = ConvertTo-ArgumentString @('-hide_banner', '-encoders')
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  [void]$process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "ffmpeg encoder discovery failed with code $($process.ExitCode): $stderr"
  }
  return ($stdout -match [regex]::Escape($EncoderName))
}

function Test-FfmpegFilter([string]$FfmpegExe, [string]$FilterName) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfmpegExe
  $startInfo.Arguments = ConvertTo-ArgumentString @('-hide_banner', '-filters')
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  [void]$process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "ffmpeg filter discovery failed with code $($process.ExitCode): $stderr"
  }
  return ($stdout -match [regex]::Escape($FilterName))
}

function Resolve-RecordingVideoCodec([string]$FfmpegExe, [string]$RequestedCodec) {
  if ($RequestedCodec -eq 'h264_nvenc') {
    return 'h264_nvenc'
  }
  if ($RequestedCodec -eq 'libx264') {
    return 'libx264'
  }
  if (Test-FfmpegEncoder -FfmpegExe $FfmpegExe -EncoderName 'h264_nvenc') {
    return 'h264_nvenc'
  }
  return 'libx264'
}

function Resolve-RecordingCaptureMode([string]$FfmpegExe, [string]$RequestedMode, [string]$VideoCodec) {
  if ($RequestedMode -eq 'ddagrab') {
    if ($VideoCodec -ne 'h264_nvenc') {
      throw 'The ddagrab recorder mode currently requires h264_nvenc so frames can stay on the GPU.'
    }
    if (-not (Test-FfmpegFilter -FfmpegExe $FfmpegExe -FilterName 'ddagrab')) {
      throw 'ffmpeg ddagrab filter was not found.'
    }
    return 'ddagrab'
  }
  if ($RequestedMode -eq 'gdigrab') {
    return 'gdigrab'
  }
  if ($VideoCodec -eq 'h264_nvenc' -and (Test-FfmpegFilter -FfmpegExe $FfmpegExe -FilterName 'ddagrab')) {
    return 'ddagrab'
  }
  return 'gdigrab'
}

function Get-RecordingCodecArguments([string]$Codec) {
  if ($Codec -eq 'h264_nvenc') {
    return @('-c:v', 'h264_nvenc', '-preset', 'p1', '-rc', 'constqp', '-qp', '18')
  }
  return @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18')
}

function Resolve-CaptureTargetExe([string]$ConfiguredPath, [string]$RepoRoot) {
  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    $candidates += $ConfiguredPath
  }
  $candidates += Join-Path $RepoRoot 'tools\game-capture-target\build\Debug\InterGalacticCaptureTarget.exe'
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw 'InterGalacticCaptureTarget.exe was not found. Build tools/game-capture-target first or pass -CaptureTargetExe.'
}

function Ensure-WindowRectType {
  if ($null -ne ([System.Management.Automation.PSTypeName]'InterGalactic.StreamLab.WindowCapture').Type) {
    return
  }

  Add-Type -Namespace 'InterGalactic.StreamLab' -Name 'WindowCapture' -MemberDefinition @"
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct RECT
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint processId);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT rect);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int GetSystemMetrics(int nIndex);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool BringWindowToTop(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr SetActiveWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr SetFocus(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint GetCurrentThreadId();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindowAsync(System.IntPtr hWnd, int nCmdShow);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetCursorPos(int X, int Y);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, System.UIntPtr dwExtraInfo);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowTextLength(System.IntPtr hWnd);

public static System.IntPtr FindVisibleWindowForProcessId(int targetPid)
{
    System.IntPtr found = System.IntPtr.Zero;
    EnumWindows(delegate(System.IntPtr hWnd, System.IntPtr lParam) {
        uint pid = 0;
        GetWindowThreadProcessId(hWnd, out pid);
        if (pid == (uint)targetPid && IsWindowVisible(hWnd)) {
            found = hWnd;
            return false;
        }
        return true;
    }, System.IntPtr.Zero);
    return found;
}

public static System.IntPtr FindVisibleWindowForProcessIdAndTitle(int targetPid, string expectedTitle)
{
    System.IntPtr found = System.IntPtr.Zero;
    string needle = expectedTitle == null ? "" : expectedTitle;
    EnumWindows(delegate(System.IntPtr hWnd, System.IntPtr lParam) {
        uint pid = 0;
        GetWindowThreadProcessId(hWnd, out pid);
        if (pid == (uint)targetPid && IsWindowVisible(hWnd)) {
            string title = GetWindowTitle(hWnd);
            if (needle.Length == 0 ||
                title.IndexOf(needle, System.StringComparison.OrdinalIgnoreCase) >= 0) {
                found = hWnd;
                return false;
            }
        }
        return true;
    }, System.IntPtr.Zero);
    return found;
}

public static string GetWindowTitle(System.IntPtr hWnd)
{
    int length = GetWindowTextLength(hWnd);
    if (length <= 0) {
        return "";
    }
    System.Text.StringBuilder builder = new System.Text.StringBuilder(length + 1);
    GetWindowText(hWnd, builder, builder.Capacity);
    return builder.ToString();
}

public static bool TryForceForegroundWindow(System.IntPtr hWnd)
{
    uint targetPid = 0;
    uint targetThread = GetWindowThreadProcessId(hWnd, out targetPid);
    System.IntPtr foreground = GetForegroundWindow();
    uint foregroundPid = 0;
    uint foregroundThread = foreground == System.IntPtr.Zero
        ? 0
        : GetWindowThreadProcessId(foreground, out foregroundPid);
    uint currentThread = GetCurrentThreadId();
    bool attachedTarget = false;
    bool attachedForeground = false;

    try {
        if (targetThread != 0 && targetThread != currentThread) {
            attachedTarget = AttachThreadInput(currentThread, targetThread, true);
        }
        if (foregroundThread != 0 &&
            foregroundThread != currentThread &&
            foregroundThread != targetThread) {
            attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
        }

        ShowWindowAsync(hWnd, 9);
        BringWindowToTop(hWnd);
        SetActiveWindow(hWnd);
        SetFocus(hWnd);
        return SetForegroundWindow(hWnd);
    } finally {
        if (attachedForeground) {
            AttachThreadInput(currentThread, foregroundThread, false);
        }
        if (attachedTarget) {
            AttachThreadInput(currentThread, targetThread, false);
        }
    }
}
"@
}

function Get-VirtualDesktopRect {
  Ensure-WindowRectType
  $left = [InterGalactic.StreamLab.WindowCapture]::GetSystemMetrics(76)
  $top = [InterGalactic.StreamLab.WindowCapture]::GetSystemMetrics(77)
  $width = [InterGalactic.StreamLab.WindowCapture]::GetSystemMetrics(78)
  $height = [InterGalactic.StreamLab.WindowCapture]::GetSystemMetrics(79)
  if ($width -le 0 -or $height -le 0) {
    throw "Invalid virtual desktop metrics: $left,$top ${width}x${height}."
  }
  return [pscustomobject]@{
    X = $left
    Y = $top
    Width = $width
    Height = $height
    Right = $left + $width
    Bottom = $top + $height
  }
}

function Clamp-RectToVirtualDesktop([object]$Rect) {
  $desktop = Get-VirtualDesktopRect
  $left = [Math]::Max([int]$Rect.X, [int]$desktop.X)
  $top = [Math]::Max([int]$Rect.Y, [int]$desktop.Y)
  $right = [Math]::Min(([int]$Rect.X + [int]$Rect.Width), [int]$desktop.Right)
  $bottom = [Math]::Min(([int]$Rect.Y + [int]$Rect.Height), [int]$desktop.Bottom)
  $width = $right - $left
  $height = $bottom - $top
  if ($width -le 0 -or $height -le 0) {
    throw "Window capture rectangle is outside the virtual desktop: $($Rect.X),$($Rect.Y) $($Rect.Width)x$($Rect.Height)."
  }
  return [pscustomobject]@{
    X = $left
    Y = $top
    Width = $width
    Height = $height
  }
}

function ConvertTo-WindowHandle([object]$Value) {
  if ($null -eq $Value) {
    return [IntPtr]::Zero
  }
  if ($Value -is [IntPtr]) {
    return $Value
  }
  $text = ([string]$Value).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) {
    return [IntPtr]::Zero
  }

  $parsed = [int64]0
  if ($text.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
    try {
      $parsed = [Convert]::ToInt64($text.Substring(2), 16)
    } catch {
      return [IntPtr]::Zero
    }
  } elseif (-not [int64]::TryParse(
      $text,
      [System.Globalization.NumberStyles]::Integer,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    )) {
    return [IntPtr]::Zero
  }

  if ($parsed -le 0) {
    return [IntPtr]::Zero
  }
  return [IntPtr]$parsed
}

function Get-HotkeyWindowSelection([object]$HotkeyResult, [int]$ExpectedProcessId, [string]$ExpectedTitle) {
  $hotkeyPid = Get-JsonInt $HotkeyResult 'Pid'
  if ($null -eq $hotkeyPid -or $hotkeyPid -ne $ExpectedProcessId) {
    throw "Call hotkey helper selected process '$hotkeyPid', expected Inter Galactic process '$ExpectedProcessId'."
  }

  $hasWindowHandle = [bool](Get-JsonProperty $HotkeyResult 'HasWindowHandle')
  $hWnd = ConvertTo-WindowHandle (Get-JsonProperty $HotkeyResult 'MainWindowHandle')
  if (-not $hasWindowHandle -or $hWnd -eq [IntPtr]::Zero) {
    throw 'Call hotkey helper did not report a usable Inter Galactic window handle.'
  }

  $title = Get-JsonString $HotkeyResult 'MainWindowTitle'
  if (-not [string]::IsNullOrWhiteSpace($ExpectedTitle) -and
      ([string]::IsNullOrWhiteSpace($title) -or
        $title.IndexOf($ExpectedTitle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
    throw "Call hotkey helper selected window '$title', expected title containing '$ExpectedTitle'."
  }

  return [pscustomobject]@{
    ProcessId = $hotkeyPid
    Hwnd = $hWnd
    HwndDecimal = $hWnd.ToInt64()
    Title = $title
  }
}

function Get-WindowInfoForHandle([IntPtr]$Hwnd, [int]$ExpectedProcessId, [string]$Stage) {
  Ensure-WindowRectType
  if ($Hwnd -eq [IntPtr]::Zero) {
    throw "No Inter Galactic window handle was available during $Stage."
  }
  if (-not [InterGalactic.StreamLab.WindowCapture]::IsWindow($Hwnd)) {
    throw "Inter Galactic window handle $($Hwnd.ToInt64()) was not a valid window during $Stage."
  }

  $actualProcessId = [uint32]0
  [InterGalactic.StreamLab.WindowCapture]::GetWindowThreadProcessId($Hwnd, [ref]$actualProcessId) | Out-Null
  if ([int]$actualProcessId -ne $ExpectedProcessId) {
    throw "Inter Galactic window handle $($Hwnd.ToInt64()) belonged to process $actualProcessId during $Stage, expected $ExpectedProcessId."
  }

  if (-not [InterGalactic.StreamLab.WindowCapture]::IsWindowVisible($Hwnd)) {
    throw "Inter Galactic window handle $($Hwnd.ToInt64()) was not visible during $Stage."
  }

  $rect = New-Object InterGalactic.StreamLab.WindowCapture+RECT
  if (-not [InterGalactic.StreamLab.WindowCapture]::GetWindowRect($Hwnd, [ref]$rect)) {
    throw "GetWindowRect failed for Inter Galactic process $ExpectedProcessId during $Stage."
  }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) {
    throw "Invalid window rectangle for Inter Galactic process ${ExpectedProcessId}: $($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)."
  }

  return [pscustomobject]@{
    Hwnd = $Hwnd
    HwndDecimal = $Hwnd.ToInt64()
    Title = [InterGalactic.StreamLab.WindowCapture]::GetWindowTitle($Hwnd)
    X = $rect.Left
    Y = $rect.Top
    Width = $width
    Height = $height
  }
}

function Test-WindowTitleContains([string]$Title, [string]$ExpectedTitle) {
  if ([string]::IsNullOrWhiteSpace($ExpectedTitle)) {
    return $true
  }
  if ([string]::IsNullOrWhiteSpace($Title)) {
    return $false
  }
  return $Title.IndexOf($ExpectedTitle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Find-VisibleWindowByTitle([int]$ExpectedProcessId, [string]$ExpectedTitle) {
  if ([string]::IsNullOrWhiteSpace($ExpectedTitle)) {
    return $null
  }
  Ensure-WindowRectType
  $matchingHwnd = [InterGalactic.StreamLab.WindowCapture]::FindVisibleWindowForProcessIdAndTitle(
    $ExpectedProcessId,
    $ExpectedTitle
  )
  if ($matchingHwnd -eq [IntPtr]::Zero) {
    return $null
  }
  return Get-WindowInfoForHandle `
    -Hwnd $matchingHwnd `
    -ExpectedProcessId $ExpectedProcessId `
    -Stage 'call entry verification title match'
}

function Wait-CallEntryVerification(
  [IntPtr]$Hwnd,
  [int]$ExpectedProcessId,
  [string]$ExpectedTitle,
  [int]$TimeoutSeconds,
  [bool]$Skip
) {
  $started = Get-Date
  if ($Skip -or [string]::IsNullOrWhiteSpace($ExpectedTitle)) {
    return [pscustomobject]@{
      status = 'skipped'
      expectedTitle = $ExpectedTitle
      observedTitle = ''
      windowHandle = 0
      matchedBy = 'skipped'
      waitedSeconds = 0.0
      verifiedAt = $null
    }
  }

  $lastTitle = ''
  $lastHwnd = 0
  $deadline = $started.AddSeconds([Math]::Max(0, $TimeoutSeconds))
  do {
    $matchingWindow = Find-VisibleWindowByTitle `
      -ExpectedProcessId $ExpectedProcessId `
      -ExpectedTitle $ExpectedTitle
    if ($null -ne $matchingWindow) {
      return [pscustomobject]@{
        status = 'verified'
        expectedTitle = $ExpectedTitle
        observedTitle = $matchingWindow.Title
        windowHandle = $matchingWindow.HwndDecimal
        matchedBy = 'process_title'
        waitedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        verifiedAt = (Get-Date).ToString('o')
      }
    }
    try {
      $windowInfo = Get-WindowInfoForHandle `
        -Hwnd $Hwnd `
        -ExpectedProcessId $ExpectedProcessId `
        -Stage 'call entry verification'
      $lastTitle = $windowInfo.Title
      $lastHwnd = $windowInfo.HwndDecimal
      if (Test-WindowTitleContains -Title $lastTitle -ExpectedTitle $ExpectedTitle) {
        return [pscustomobject]@{
          status = 'verified'
          expectedTitle = $ExpectedTitle
          observedTitle = $lastTitle
          windowHandle = $lastHwnd
          matchedBy = 'hotkey_window'
          waitedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
          verifiedAt = (Get-Date).ToString('o')
        }
      }
    } catch {
      $lastTitle = "window lookup failed: $($_.Exception.Message)"
      $lastHwnd = 0
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return [pscustomobject]@{
    status = 'failed_wrong_window'
    expectedTitle = $ExpectedTitle
    observedTitle = $lastTitle
    windowHandle = $lastHwnd
    matchedBy = 'none'
    waitedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    verifiedAt = $null
  }
}

function Assert-ForegroundWindow([IntPtr]$ExpectedHwnd, [int]$ExpectedProcessId, [string]$Stage) {
  Ensure-WindowRectType
  $foreground = [InterGalactic.StreamLab.WindowCapture]::GetForegroundWindow()
  if ($foreground.ToInt64() -eq $ExpectedHwnd.ToInt64()) {
    return
  }

  $foregroundProcessId = [uint32]0
  $foregroundTitle = ''
  if ($foreground -ne [IntPtr]::Zero) {
    [InterGalactic.StreamLab.WindowCapture]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcessId) | Out-Null
    $foregroundTitle = [InterGalactic.StreamLab.WindowCapture]::GetWindowTitle($foreground)
  }

  throw "Unsafe desktop capture during ${Stage}: foreground hwnd $($foreground.ToInt64()) pid $foregroundProcessId '$foregroundTitle' did not match Inter Galactic hwnd $($ExpectedHwnd.ToInt64()) pid $ExpectedProcessId."
}

function Invoke-WindowForegroundActivation(
  [IntPtr]$Hwnd,
  [int]$TargetProcessId,
  [string]$Stage,
  [int]$TimeoutMilliseconds = 5000
) {
  Ensure-WindowRectType
  $shell = $null
  try {
    try {
      $shell = New-Object -ComObject WScript.Shell
    } catch {
      $shell = $null
    }

    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    do {
      [InterGalactic.StreamLab.WindowCapture]::ShowWindowAsync($Hwnd, 9) | Out-Null
      if ($null -ne $shell) {
        try {
          [void]$shell.AppActivate($TargetProcessId)
        } catch {
        }
      }
      [InterGalactic.StreamLab.WindowCapture]::SetForegroundWindow($Hwnd) | Out-Null
      [InterGalactic.StreamLab.WindowCapture]::TryForceForegroundWindow($Hwnd) | Out-Null
      Start-Sleep -Milliseconds 250

      $foreground = [InterGalactic.StreamLab.WindowCapture]::GetForegroundWindow()
      if ($foreground.ToInt64() -eq $Hwnd.ToInt64()) {
        return
      }
    } while ((Get-Date) -lt $deadline)
  } finally {
    if ($null -ne $shell) {
      [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
  }

  Assert-ForegroundWindow -ExpectedHwnd $Hwnd -ExpectedProcessId $TargetProcessId -Stage $Stage
}

function Get-WindowCaptureRect(
  [int]$TargetProcessId,
  [IntPtr]$PreferredHwnd = [IntPtr]::Zero,
  [string]$Stage = 'capture',
  [bool]$RequireForeground = $true
) {
  Ensure-WindowRectType
  $hWnd = $PreferredHwnd
  if ($hWnd -eq [IntPtr]::Zero) {
    $hWnd = [InterGalactic.StreamLab.WindowCapture]::FindVisibleWindowForProcessId($TargetProcessId)
  }
  if ($hWnd -eq [IntPtr]::Zero) {
    throw "No visible window was found for Inter Galactic process $TargetProcessId during $Stage."
  }

  $windowInfo = Get-WindowInfoForHandle -Hwnd $hWnd -ExpectedProcessId $TargetProcessId -Stage $Stage
  if ($RequireForeground) {
    Invoke-WindowForegroundActivation -Hwnd $hWnd -TargetProcessId $TargetProcessId -Stage $Stage
    $windowInfo = Get-WindowInfoForHandle -Hwnd $hWnd -ExpectedProcessId $TargetProcessId -Stage $Stage
  }
  return $windowInfo
}

function Invoke-WindowRelativeClick(
  [IntPtr]$Hwnd,
  [int]$TargetProcessId,
  [double]$RelativeX,
  [double]$RelativeY,
  [string]$Stage
) {
  if ($RelativeX -lt 0.0 -or $RelativeX -gt 1.0 -or
      $RelativeY -lt 0.0 -or $RelativeY -gt 1.0) {
    throw "$Stage relative click coordinates must be between 0.0 and 1.0."
  }

  Ensure-WindowRectType
  Invoke-WindowForegroundActivation -Hwnd $Hwnd -TargetProcessId $TargetProcessId -Stage $Stage
  $windowInfo = Get-WindowInfoForHandle -Hwnd $Hwnd -ExpectedProcessId $TargetProcessId -Stage $Stage
  $x = [int][Math]::Round($windowInfo.X + ($windowInfo.Width * $RelativeX))
  $y = [int][Math]::Round($windowInfo.Y + ($windowInfo.Height * $RelativeY))
  if (-not [InterGalactic.StreamLab.WindowCapture]::SetCursorPos($x, $y)) {
    throw "SetCursorPos failed for $Stage at $x,$y."
  }
  Start-Sleep -Milliseconds 100
  [InterGalactic.StreamLab.WindowCapture]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [InterGalactic.StreamLab.WindowCapture]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 250

  return [pscustomobject]@{
    x = $x
    y = $y
    relativeX = $RelativeX
    relativeY = $RelativeY
    stage = $Stage
  }
}

function Assert-WindowRectStable([object]$Expected, [object]$Actual, [int]$TolerancePixels, [string]$Stage) {
  $delta = [Math]::Max(
    [Math]::Max([Math]::Abs($Expected.X - $Actual.X), [Math]::Abs($Expected.Y - $Actual.Y)),
    [Math]::Max([Math]::Abs($Expected.Width - $Actual.Width), [Math]::Abs($Expected.Height - $Actual.Height))
  )
  if ($delta -gt $TolerancePixels) {
    throw "Inter Galactic window rectangle changed by $delta px before $Stage; desktop recording would no longer match the verified call window."
  }
}

function Get-PreflightFrameStats([string]$FfmpegExe, [string]$FramePath, [string]$LogPath) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfmpegExe
  $startInfo.Arguments = ConvertTo-ArgumentString @(
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    $FramePath,
    '-vf',
    'scale=64:36',
    '-f',
    'rawvideo',
    '-pix_fmt',
    'gray',
    '-'
  )
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $memory = New-Object System.IO.MemoryStream
  $process.StandardOutput.BaseStream.CopyTo($memory)
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $stderr | Set-Content -LiteralPath $LogPath -Encoding UTF8
  }
  if ($process.ExitCode -ne 0) {
    throw "ffmpeg preflight stats exited with code $($process.ExitCode): $stderr"
  }

  $bytes = $memory.ToArray()
  if ($bytes.Length -eq 0) {
    throw 'Preflight frame analysis returned no pixels.'
  }

  $min = 255
  $max = 0
  $sum = 0.0
  foreach ($byte in $bytes) {
    $value = [int]$byte
    if ($value -lt $min) {
      $min = $value
    }
    if ($value -gt $max) {
      $max = $value
    }
    $sum += $value
  }
  $mean = $sum / $bytes.Length
  $varianceSum = 0.0
  foreach ($byte in $bytes) {
    $delta = ([int]$byte) - $mean
    $varianceSum += $delta * $delta
  }
  $stdDev = [Math]::Sqrt($varianceSum / $bytes.Length)

  return [pscustomobject]@{
    samplePixels = $bytes.Length
    mean = [Math]::Round($mean, 3)
    min = $min
    max = $max
    contrast = $max - $min
    stdDev = [Math]::Round($stdDev, 3)
  }
}

function Invoke-PreflightWindowCheck(
  [string]$FfmpegExe,
  [object]$Rect,
  [string]$FramePath,
  [string]$CaptureLogPath,
  [string]$StatsLogPath
) {
  $captureRect = Clamp-RectToVirtualDesktop -Rect $Rect
  if ($captureRect.X -ne [int]$Rect.X -or
      $captureRect.Y -ne [int]$Rect.Y -or
      $captureRect.Width -ne [int]$Rect.Width -or
      $captureRect.Height -ne [int]$Rect.Height) {
    throw "Preflight capture rectangle was clipped by virtual desktop bounds: requested $($Rect.X),$($Rect.Y) $($Rect.Width)x$($Rect.Height), clamped to $($captureRect.X),$($captureRect.Y) $($captureRect.Width)x$($captureRect.Height)."
  }
  Invoke-ToolProcess `
    -FileName $FfmpegExe `
    -Arguments @(
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'gdigrab',
      '-framerate',
      '1',
      '-offset_x',
      "$($captureRect.X)",
      '-offset_y',
      "$($captureRect.Y)",
      '-video_size',
      "$($captureRect.Width)x$($captureRect.Height)",
      '-i',
      'desktop',
      '-frames:v',
      '1',
      $FramePath
    ) `
    -StdoutPath '' `
    -StderrPath $CaptureLogPath

  if (-not (Test-Path -LiteralPath $FramePath)) {
    throw "Preflight frame was not written: $FramePath"
  }
  $frameItem = Get-Item -LiteralPath $FramePath
  if ($frameItem.Length -le 0) {
    throw "Preflight frame was empty: $FramePath"
  }

  $stats = Get-PreflightFrameStats -FfmpegExe $FfmpegExe -FramePath $FramePath -LogPath $StatsLogPath
  if ($stats.contrast -lt 12 -or $stats.mean -lt 4 -or $stats.mean -gt 251) {
    throw "Preflight frame did not look like a visible Inter Galactic call window: mean=$($stats.mean), contrast=$($stats.contrast), stdDev=$($stats.stdDev)."
  }
  return $stats
}

function Get-JsonProperty([object]$Object, [string]$Name) {
  if ($null -eq $Object) {
    return $null
  }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      return $Object[$Name]
    }
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-NestedJsonProperty([object]$Object, [string[]]$Names) {
  $current = $Object
  foreach ($name in $Names) {
    $current = Get-JsonProperty $current $name
    if ($null -eq $current) {
      return $null
    }
  }
  return $current
}

function Get-JsonString([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  return [string]$value
}

function Get-JsonDouble([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  $parsed = 0.0
  if ([double]::TryParse(
      [string]$value,
      [System.Globalization.NumberStyles]::Float,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    )) {
    return $parsed
  }
  return $null
}

function Get-JsonInt([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $null
  }
  $parsed = 0
  if ([int]::TryParse([string]$value, [ref]$parsed)) {
    return $parsed
  }
  return $null
}

function Get-DeepestReceiverPresentationStage(
  [object]$RemoteDecodeEventCount,
  [object]$RemoteRendererCallbackEventCount,
  [object]$RemoteTextureReadyEventCount,
  [object]$RemoteUiPaintEventCount,
  [object]$RemoteScreenPresentEventCount
) {
  $stages = @(
    @{ Name = 'remote_screen_present'; Count = $RemoteScreenPresentEventCount },
    @{ Name = 'remote_ui_paint'; Count = $RemoteUiPaintEventCount },
    @{ Name = 'remote_texture_ready'; Count = $RemoteTextureReadyEventCount },
    @{ Name = 'remote_renderer_callback'; Count = $RemoteRendererCallbackEventCount },
    @{ Name = 'remote_decode'; Count = $RemoteDecodeEventCount }
  )

  foreach ($stage in $stages) {
    $count = 0
    if ([int]::TryParse([string]$stage.Count, [ref]$count) -and $count -gt 0) {
      return $stage.Name
    }
  }

  return ''
}

function Test-JsonValuePresent([object]$Object, [string]$Name) {
  $value = Get-JsonProperty $Object $Name
  if ($null -eq $value) {
    return $false
  }
  return -not [string]::IsNullOrWhiteSpace([string]$value)
}

function Get-ReceiverSourceLineageStats([string]$EventsPath) {
  $stats = [ordered]@{
    eventCount = 0
    sourceLineageEventCount = 0
    frameIdEventCount = 0
    previousFrameIdEventCount = 0
    sourceFrameMarkerIdEventCount = 0
    sourceQpcEventCount = 0
    stageQpcEventCount = 0
    sourceFrameIdAvailable = $false
    sourceLineageAvailable = $false
    reason = 'events_missing'
  }

  if ([string]::IsNullOrWhiteSpace($EventsPath) -or
      -not (Test-Path -LiteralPath $EventsPath)) {
    return $stats
  }

  foreach ($line in Get-Content -LiteralPath $EventsPath) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    try {
      $event = $line | ConvertFrom-Json
    } catch {
      continue
    }

    $stats.eventCount++
    $hasFrameId = Test-JsonValuePresent $event 'frame_id'
    $hasPreviousFrameId = Test-JsonValuePresent $event 'previous_frame_id'
    $hasSourceFrameMarkerId = Test-JsonValuePresent $event 'source_frame_marker_id'
    $hasSourceQpc = Test-JsonValuePresent $event 'source_qpc'
    $hasStageQpc = Test-JsonValuePresent $event 'stage_qpc'
    if ($hasFrameId) {
      $stats.frameIdEventCount++
    }
    if ($hasPreviousFrameId) {
      $stats.previousFrameIdEventCount++
    }
    if ($hasSourceFrameMarkerId) {
      $stats.sourceFrameMarkerIdEventCount++
    }
    if ($hasSourceQpc) {
      $stats.sourceQpcEventCount++
    }
    if ($hasStageQpc) {
      $stats.stageQpcEventCount++
    }
    if ($hasFrameId -or $hasPreviousFrameId -or $hasSourceFrameMarkerId -or
        $hasSourceQpc -or
        $hasStageQpc) {
      $stats.sourceLineageEventCount++
    }
  }

  $stats.sourceFrameIdAvailable =
    $stats.frameIdEventCount -gt 0 -or
    $stats.previousFrameIdEventCount -gt 0 -or
    $stats.sourceFrameMarkerIdEventCount -gt 0
  $stats.sourceLineageAvailable =
    $stats.sourceFrameIdAvailable -and
    $stats.sourceQpcEventCount -gt 0 -and
    $stats.stageQpcEventCount -gt 0
  $stats.reason = if ($stats.sourceLineageAvailable) {
    if ($stats.frameIdEventCount -gt 0) {
      'source_frame_id_source_qpc_stage_qpc_present'
    } elseif ($stats.previousFrameIdEventCount -gt 0) {
      'source_frame_id_observed_as_previous_source_qpc_stage_qpc_present'
    } else {
      'source_frame_content_marker_source_qpc_stage_qpc_present'
    }
  } elseif ($stats.sourceFrameMarkerIdEventCount -gt 0) {
    'source_frame_content_marker_present_without_complete_lineage'
  } elseif ($stats.sourceFrameIdAvailable) {
    if ($stats.frameIdEventCount -gt 0) {
      'source_frame_id_present_without_complete_lineage'
    } else {
      'source_frame_id_observed_as_previous_without_complete_lineage'
    }
  } elseif ($stats.eventCount -gt 0) {
    'source_frame_id_missing'
  } else {
    'events_empty'
  }

  return $stats
}

function Test-NumberAtLeast([object]$Value, [double]$Threshold) {
  if ($null -eq $Value) {
    return $false
  }
  return [double]$Value -ge $Threshold
}

function Test-NumberGreaterThan([object]$Value, [double]$Threshold) {
  if ($null -eq $Value) {
    return $false
  }
  return [double]$Value -gt $Threshold
}

function Test-NumberLessThan([object]$Value, [double]$Threshold) {
  if ($null -eq $Value) {
    return $false
  }
  return [double]$Value -lt $Threshold
}

function ConvertTo-CompactList([object[]]$Values) {
  $items = @(
    $Values |
      Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
      Select-Object -Unique
  )
  if ($items.Count -eq 0) {
    return 'none'
  }
  return ($items -join ', ')
}

function ConvertTo-UtcDateTimeOffset([object]$Value) {
  if ($null -eq $Value) {
    return $null
  }
  $parsed = [DateTimeOffset]::MinValue
  if ([DateTimeOffset]::TryParse(
      [string]$Value,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::AssumeUniversal,
      [ref]$parsed
    )) {
    return $parsed.ToUniversalTime()
  }
  return $null
}

function Get-NumberSummary([object[]]$Values) {
  $numbers = @()
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }
    $parsed = 0.0
    if ([double]::TryParse(
        [string]$value,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
      )) {
      $numbers += $parsed
    }
  }

  if ($numbers.Count -eq 0) {
    return [ordered]@{
      count = 0
      average = $null
      min = $null
      p50 = $null
      max = $null
    }
  }

  $sorted = @($numbers | Sort-Object)
  $sum = 0.0
  foreach ($number in $numbers) {
    $sum += $number
  }
  $middle = [int][Math]::Floor(($sorted.Count - 1) / 2)
  return [ordered]@{
    count = $numbers.Count
    average = [Math]::Round($sum / $numbers.Count, 3)
    min = [Math]::Round($sorted[0], 3)
    p50 = [Math]::Round($sorted[$middle], 3)
    max = [Math]::Round($sorted[$sorted.Count - 1], 3)
  }
}

function Read-ReceiverProbeEvents([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or
      -not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  $events = @()
  foreach ($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
      $sampleTime = ConvertTo-UtcDateTimeOffset (Get-JsonString $event 'sample_time_utc')
      if ($null -eq $sampleTime) {
        continue
      }
      $events += [pscustomobject]@{
        SampleTimeUtc = $sampleTime
        Event = $event
      }
    } catch {
    }
  }
  return @($events)
}

function New-SenderReceiverWindowCorrelation(
  [object]$PrimaryResult,
  [string]$ReceiverEventsPath,
  [double]$ReceiverPresentationP95LimitMs,
  [double]$MinUniqueFps
) {
  $windows = Get-NestedJsonProperty $PrimaryResult @('timeWindows', 'windows')
  $presetStartedAt = ConvertTo-UtcDateTimeOffset (Get-JsonString $PrimaryResult 'startedAt')
  if ($null -eq $windows -or $null -eq $presetStartedAt) {
    return [ordered]@{
      available = $false
      reason = 'missing_sender_time_windows_or_preset_start'
      receiverEventsPath = $ReceiverEventsPath
      windows = @()
    }
  }

  $receiverEvents = @(Read-ReceiverProbeEvents -Path $ReceiverEventsPath)
  if ($receiverEvents.Count -eq 0) {
    return [ordered]@{
      available = $false
      reason = 'missing_receiver_events'
      receiverEventsPath = $ReceiverEventsPath
      windows = @()
    }
  }

  $rows = @()
  foreach ($window in @($windows)) {
    $label = Get-JsonString $window 'label'
    $startMs = Get-JsonDouble $window 'startMs'
    $endMs = Get-JsonDouble $window 'endMs'
    if ($null -eq $startMs -or $null -eq $endMs) {
      continue
    }

    $windowStart = $presetStartedAt.AddMilliseconds($startMs)
    $windowEnd = $presetStartedAt.AddMilliseconds($endMs)
    $windowEvents = @(
      $receiverEvents |
        Where-Object {
          $lane = Get-JsonString $_.Event 'lane'
          $_.SampleTimeUtc -ge $windowStart -and
            $_.SampleTimeUtc -lt $windowEnd -and
            ($lane -eq 'remote_renderer_callback' -or
              $lane -eq 'remote_render')
        }
    )
    $activeEvents = @(
      $windowEvents |
        Where-Object {
          (Get-JsonString $_.Event 'status') -eq 'frame_hash_tap_active'
        }
    )
    $frameHashStageEvents = @(
      $windowEvents |
        Where-Object {
          (Get-JsonString $_.Event 'freshness_source') -eq 'frame_hash_tap' -and
          $null -ne (Get-JsonDouble $_.Event 'unique_fps')
        }
    )
    $uiPaintFrameHashEvents = @(
      $frameHashStageEvents |
        Where-Object { (Get-JsonString $_.Event 'stage') -eq 'remote_ui_paint' }
    )
    $textureReadyFrameHashEvents = @(
      $frameHashStageEvents |
        Where-Object { (Get-JsonString $_.Event 'stage') -eq 'remote_texture_ready' }
    )
    $rendererCallbackFrameHashEvents = @(
      $frameHashStageEvents |
        Where-Object {
          (Get-JsonString $_.Event 'stage') -eq 'remote_renderer_callback'
        }
    )
    if ($uiPaintFrameHashEvents.Count -gt 0) {
      $activeEvents = $uiPaintFrameHashEvents
    } elseif ($textureReadyFrameHashEvents.Count -gt 0) {
      $activeEvents = $textureReadyFrameHashEvents
    } elseif ($rendererCallbackFrameHashEvents.Count -gt 0) {
      $activeEvents = $rendererCallbackFrameHashEvents
    } elseif ($frameHashStageEvents.Count -gt 0) {
      $activeEvents = $frameHashStageEvents
    }

    $receiverDecodedFps = Get-NumberSummary @(
      $activeEvents | ForEach-Object { Get-JsonDouble $_.Event 'decoded_fps' }
    )
    $receiverUniqueFps = Get-NumberSummary @(
      $activeEvents | ForEach-Object { Get-JsonDouble $_.Event 'unique_fps' }
    )
    $receiverPresentationP95 = Get-NumberSummary @(
      $activeEvents |
        ForEach-Object { Get-JsonDouble $_.Event 'frame_presentation_p95_gap_ms' }
    )
    $receiverPresentationMax = Get-NumberSummary @(
      $activeEvents |
        ForEach-Object { Get-JsonDouble $_.Event 'frame_presentation_max_gap_ms' }
    )
    $receiverRendererCallbackToStage = Get-NumberSummary @(
      $activeEvents |
        ForEach-Object { Get-JsonDouble $_.Event 'renderer_callback_to_stage_ms' }
    )
    $receiverBitrate = Get-NumberSummary @(
      $activeEvents | ForEach-Object { Get-JsonDouble $_.Event 'inbound_bitrate_bps' }
    )
    $receiverQp = Get-NumberSummary @(
      $activeEvents | ForEach-Object { Get-JsonDouble $_.Event 'average_qp' }
    )

    $gameCapture = Get-JsonProperty $window 'gameCapture'
    $sentFramePacing = Get-NestedJsonProperty $window @('framePacing', 'sent')
    $maxDeliveryWallMs = Get-JsonDouble $gameCapture 'maxDeliveryWallDeltaMs'
    $maxSourceToSubmitMs = Get-JsonDouble $gameCapture 'maxSourceToSubmitMs'
    $maxSourceToReadbackReadyMs =
      Get-JsonDouble $gameCapture 'maxSourceToReadbackReadyMs'
    $maxReadbackQueueToMapMs = Get-JsonDouble $gameCapture 'maxReadbackQueueToMapMs'
    $sourceFrameGapsDelta = Get-JsonInt $gameCapture 'sourceFrameGapsDelta'
    $senderWindowRed =
      (Test-NumberGreaterThan $maxDeliveryWallMs 100.0) -or
      (Test-NumberGreaterThan $maxSourceToSubmitMs 100.0) -or
      (Test-NumberGreaterThan $maxSourceToReadbackReadyMs 100.0) -or
      (Test-NumberGreaterThan $maxReadbackQueueToMapMs 100.0) -or
      (Test-NumberGreaterThan $sourceFrameGapsDelta 0.0)
    $receiverPresentationRed =
      (Test-NumberGreaterThan $receiverPresentationP95.p50 $ReceiverPresentationP95LimitMs) -or
      (Test-NumberGreaterThan $receiverPresentationP95.max $ReceiverPresentationP95LimitMs)
    $receiverCadenceRed =
      (Test-NumberLessThan $receiverDecodedFps.p50 $MinUniqueFps) -or
      (Test-NumberLessThan $receiverUniqueFps.p50 $MinUniqueFps)

    $windowClassification = if ($activeEvents.Count -eq 0) {
      'insufficient_receiver_samples'
    } elseif ($senderWindowRed -and $receiverPresentationRed) {
      'sender_and_receiver_presentation_red'
    } elseif ($receiverPresentationRed) {
      'receiver_presentation_red_only'
    } elseif ($senderWindowRed) {
      'sender_window_red_only'
    } elseif ($receiverCadenceRed) {
      'receiver_cadence_red_only'
    } else {
      'window_counters_green'
    }

    $rows += [ordered]@{
      label = $label
      startMs = $startMs
      endMs = $endMs
      classification = $windowClassification
      sender = [ordered]@{
        averageCaptureFps = Get-JsonDouble $window 'averageCaptureFps'
        averageEncodeFps = Get-JsonDouble $window 'averageEncodeFps'
        averageSendFps = Get-JsonDouble $window 'averageSendFps'
        minimumSendFps = Get-JsonDouble $window 'minimumSendFps'
        averageBitrateBps = Get-JsonDouble $window 'averageBitrateBps'
        maxDeliveryWallDeltaMs = $maxDeliveryWallMs
        maxDeliveryQueueWaitMs =
          Get-JsonDouble $gameCapture 'maxDeliveryQueueWaitMs'
        maxReadyToSubmitMs = Get-JsonDouble $gameCapture 'maxReadyToSubmitMs'
        maxSourceToSubmitMs = $maxSourceToSubmitMs
        maxSourceToReadbackReadyMs = $maxSourceToReadbackReadyMs
        maxReadbackQueueToMapMs = $maxReadbackQueueToMapMs
        maxMapToI420Ms = Get-JsonDouble $gameCapture 'maxMapToI420Ms'
        maxSourceToI420ReadyMs =
          Get-JsonDouble $gameCapture 'maxSourceToI420ReadyMs'
        submittedFps = Get-JsonDouble $gameCapture 'submittedFps'
        nativeNv12NotReadyPollsDelta =
          Get-JsonInt $gameCapture 'nativeNv12NotReadyPollsDelta'
        nativeNv12ReadyDroppedDelta =
          Get-JsonInt $gameCapture 'nativeNv12ReadyDroppedDelta'
        readbackNotReadyDelta =
          Get-JsonInt $gameCapture 'readbackNotReadyDelta'
        readbackStaleDroppedDelta =
          Get-JsonInt $gameCapture 'readbackStaleDroppedDelta'
        readbackLatencyDroppedDelta =
          Get-JsonInt $gameCapture 'readbackLatencyDroppedDelta'
        sourceFrameGapsDelta = $sourceFrameGapsDelta
        deliveryWallOver2xDelta =
          Get-JsonInt $gameCapture 'deliveryWallOver2xDelta'
        deliveryWallOver3xDelta =
          Get-JsonInt $gameCapture 'deliveryWallOver3xDelta'
        sentP95IntervalMs = Get-JsonDouble $sentFramePacing 'p95IntervalMs'
        sentMaxIntervalMs = Get-JsonDouble $sentFramePacing 'maxIntervalMs'
      }
      receiver = [ordered]@{
        eventCount = $windowEvents.Count
        activeEventCount = $activeEvents.Count
        decodedFps = $receiverDecodedFps
        uniqueFps = $receiverUniqueFps
        presentationP95GapMs = $receiverPresentationP95
        presentationMaxGapMs = $receiverPresentationMax
        rendererCallbackToStageMs = $receiverRendererCallbackToStage
        inboundBitrateBps = $receiverBitrate
        averageQp = $receiverQp
      }
    }
  }

  return [ordered]@{
    available = $rows.Count -gt 0
    reason = if ($rows.Count -gt 0) { '' } else { 'no_aligned_windows' }
    receiverEventsPath = $ReceiverEventsPath
    presetStartedAtUtc = $presetStartedAt.ToString('o')
    receiverEventCount = $receiverEvents.Count
    windows = $rows
  }
}

function New-SenderReceiverPresentationTailCorrelation(
  [object]$CorrelationWindows,
  [double]$ReceiverPresentationP95LimitMs,
  [double]$MinUniqueFps
) {
  $windowsAvailable = [bool](Get-JsonProperty $CorrelationWindows 'available')
  $windows = @((Get-JsonProperty $CorrelationWindows 'windows'))
  if (-not $windowsAvailable -or $windows.Count -eq 0) {
    return [ordered]@{
      available = $false
      reason = Get-JsonString $CorrelationWindows 'reason'
      classification = 'window_alignment_unavailable'
      summary =
        'Sender/receiver presentation-tail correlation is unavailable because aligned sender/receiver windows were not available.'
      next =
        'Repair window alignment or receiver event capture before using window-level correlation.'
      sampledWindowCount = 0
      receiverPresentationRedWindowCount = 0
      senderTailWindowCount = 0
      coupledWindowCount = 0
      receiverOnlyWindowCount = 0
      senderOnlyWindowCount = 0
      receiverPresentationRedWindows = @()
      senderTailWindows = @()
      coupledWindows = @()
      receiverOnlyWindows = @()
      senderOnlyWindows = @()
      dominantTailSignals = @()
      dominantReceiverPresentationWindow = ''
      rows = @()
    }
  }

  $tailCounts = [ordered]@{
    delivery_wall_gap = 0
    source_to_submit_gap = 0
    source_to_readback_ready_gap = 0
    readback_queue_to_map_gap = 0
    sent_p95_gap = 0
    source_frame_gaps = 0
    sender_capture_fps_low = 0
    sender_encode_fps_low = 0
    sender_send_fps_low = 0
  }
  $sampledWindowCount = 0
  $receiverPresentationRedWindows = @()
  $senderTailWindows = @()
  $coupledWindows = @()
  $receiverOnlyWindows = @()
  $senderOnlyWindows = @()
  $rowSummaries = @()
  $dominantReceiverPresentationWindow = ''
  $dominantReceiverPresentationMs = $null

  foreach ($row in $windows) {
    $label = Get-JsonString $row 'label'
    $sender = Get-JsonProperty $row 'sender'
    $receiver = Get-JsonProperty $row 'receiver'
    $activeEventCount = Get-JsonInt $receiver 'activeEventCount'
    $presentationP95 = Get-JsonProperty $receiver 'presentationP95GapMs'
    $presentationMax = Get-JsonProperty $receiver 'presentationMaxGapMs'
    $decodedFps = Get-JsonProperty $receiver 'decodedFps'
    $uniqueFps = Get-JsonProperty $receiver 'uniqueFps'
    $presentationP95P50 = Get-JsonDouble $presentationP95 'p50'
    $presentationP95Max = Get-JsonDouble $presentationP95 'max'
    $presentationMaxGapMax = Get-JsonDouble $presentationMax 'max'
    $decodedFpsP50 = Get-JsonDouble $decodedFps 'p50'
    $uniqueFpsP50 = Get-JsonDouble $uniqueFps 'p50'

    $tailSignals = @()
    if (Test-NumberGreaterThan (Get-JsonDouble $sender 'maxDeliveryWallDeltaMs') 100.0) {
      $tailSignals += 'delivery_wall_gap'
    }
    if (Test-NumberGreaterThan (Get-JsonDouble $sender 'maxSourceToSubmitMs') 100.0) {
      $tailSignals += 'source_to_submit_gap'
    }
    if (Test-NumberGreaterThan (Get-JsonDouble $sender 'maxSourceToReadbackReadyMs') 100.0) {
      $tailSignals += 'source_to_readback_ready_gap'
    }
    if (Test-NumberGreaterThan (Get-JsonDouble $sender 'maxReadbackQueueToMapMs') 100.0) {
      $tailSignals += 'readback_queue_to_map_gap'
    }
    if (Test-NumberGreaterThan (Get-JsonDouble $sender 'sentP95IntervalMs') 50.0) {
      $tailSignals += 'sent_p95_gap'
    }
    if (Test-NumberGreaterThan (Get-JsonInt $sender 'sourceFrameGapsDelta') 0.0) {
      $tailSignals += 'source_frame_gaps'
    }
    if (Test-NumberLessThan (Get-JsonDouble $sender 'averageCaptureFps') $MinUniqueFps) {
      $tailSignals += 'sender_capture_fps_low'
    }
    if (Test-NumberLessThan (Get-JsonDouble $sender 'averageEncodeFps') $MinUniqueFps) {
      $tailSignals += 'sender_encode_fps_low'
    }
    if (Test-NumberLessThan (Get-JsonDouble $sender 'averageSendFps') $MinUniqueFps) {
      $tailSignals += 'sender_send_fps_low'
    }

    foreach ($tailSignal in @($tailSignals | Select-Object -Unique)) {
      $tailCounts[$tailSignal] = [int]$tailCounts[$tailSignal] + 1
    }

    $receiverPresentationRed =
      (Test-NumberGreaterThan $presentationP95P50 $ReceiverPresentationP95LimitMs) -or
      (Test-NumberGreaterThan $presentationP95Max $ReceiverPresentationP95LimitMs)
    $receiverCadenceRed =
      (Test-NumberLessThan $decodedFpsP50 $MinUniqueFps) -or
      (Test-NumberLessThan $uniqueFpsP50 $MinUniqueFps)
    $senderTailRed = $tailSignals.Count -gt 0

    $candidatePresentationMs = $null
    if ($null -ne $presentationP95P50) {
      $candidatePresentationMs = $presentationP95P50
    }
    if ($null -ne $presentationP95Max -and
        ($null -eq $candidatePresentationMs -or
          [double]$presentationP95Max -gt [double]$candidatePresentationMs)) {
      $candidatePresentationMs = $presentationP95Max
    }
    if ($null -ne $candidatePresentationMs -and
        ($null -eq $dominantReceiverPresentationMs -or
          [double]$candidatePresentationMs -gt [double]$dominantReceiverPresentationMs)) {
      $dominantReceiverPresentationMs = $candidatePresentationMs
      $dominantReceiverPresentationWindow = $label
    }

    $classification = if ($null -eq $activeEventCount -or $activeEventCount -eq 0) {
      'insufficient_receiver_samples'
    } elseif ($receiverPresentationRed -and $senderTailRed) {
      'sender_tail_and_receiver_presentation_red'
    } elseif ($receiverPresentationRed) {
      'receiver_presentation_red_without_sender_tail'
    } elseif ($senderTailRed) {
      'sender_tail_without_receiver_presentation_red'
    } elseif ($receiverCadenceRed) {
      'receiver_cadence_red_without_presentation_tail'
    } else {
      'window_counters_green'
    }

    if ($null -ne $activeEventCount -and $activeEventCount -gt 0) {
      $sampledWindowCount += 1
      if ($receiverPresentationRed) {
        $receiverPresentationRedWindows += $label
      }
      if ($senderTailRed) {
        $senderTailWindows += $label
      }
      if ($receiverPresentationRed -and $senderTailRed) {
        $coupledWindows += $label
      } elseif ($receiverPresentationRed) {
        $receiverOnlyWindows += $label
      } elseif ($senderTailRed) {
        $senderOnlyWindows += $label
      }
    }

    $rowSummaries += [ordered]@{
      label = $label
      classification = $classification
      activeEventCount = $activeEventCount
      receiverPresentationRed = $receiverPresentationRed
      receiverCadenceRed = $receiverCadenceRed
      senderTailRed = $senderTailRed
      tailSignals = @($tailSignals | Select-Object -Unique)
      receiverPresentationP95P50Ms = $presentationP95P50
      receiverPresentationP95MaxMs = $presentationP95Max
      receiverPresentationMaxGapMaxMs = $presentationMaxGapMax
      receiverDecodedFpsP50 = $decodedFpsP50
      receiverUniqueFpsP50 = $uniqueFpsP50
      senderCaptureFps = Get-JsonDouble $sender 'averageCaptureFps'
      senderEncodeFps = Get-JsonDouble $sender 'averageEncodeFps'
      senderSendFps = Get-JsonDouble $sender 'averageSendFps'
      senderDeliveryWallMaxMs =
        Get-JsonDouble $sender 'maxDeliveryWallDeltaMs'
      senderSourceToSubmitMaxMs =
        Get-JsonDouble $sender 'maxSourceToSubmitMs'
      senderSourceToReadbackReadyMaxMs =
        Get-JsonDouble $sender 'maxSourceToReadbackReadyMs'
      senderReadbackQueueToMapMaxMs =
        Get-JsonDouble $sender 'maxReadbackQueueToMapMs'
      senderSentP95IntervalMs = Get-JsonDouble $sender 'sentP95IntervalMs'
    }
  }

  $dominantTailSignals = @(
    $tailCounts.GetEnumerator() |
      Where-Object { [int]$_.Value -gt 0 } |
      Sort-Object `
        @{ Expression = { [int]$_.Value }; Descending = $true },
        @{ Expression = { [string]$_.Key }; Ascending = $true } |
      ForEach-Object { [string]$_.Key }
  )

  $classification = if ($sampledWindowCount -eq 0) {
    'insufficient_receiver_samples'
  } elseif ($receiverPresentationRedWindows.Count -gt 0 -and
      $coupledWindows.Count -eq $receiverPresentationRedWindows.Count) {
    'sender_tail_matches_receiver_presentation_windows'
  } elseif ($coupledWindows.Count -gt 0) {
    'mixed_sender_tail_and_receiver_presentation_windows'
  } elseif ($receiverOnlyWindows.Count -gt 0) {
    'receiver_presentation_red_without_sender_window_tail'
  } elseif ($senderOnlyWindows.Count -gt 0) {
    'sender_tail_without_receiver_presentation_red'
  } else {
    'sender_receiver_windows_green'
  }

  $summary =
    "Receiver presentation was red in $($receiverPresentationRedWindows.Count)/$sampledWindowCount sampled windows; $($coupledWindows.Count) overlapped sender delivery/readback tail signals; dominant sender tail signals: $(ConvertTo-CompactList $dominantTailSignals)."
  $next = switch ($classification) {
    'sender_tail_matches_receiver_presentation_windows' {
      'Inspect sender/native/VSE delivery tails behind the coupled windows before receiver layer, bitrate, hook-target, or widget tuning.'
    }
    'mixed_sender_tail_and_receiver_presentation_windows' {
      'Split coupled windows from receiver-only windows; tune only the first proven upstream sender/native/VSE boundary.'
    }
    'receiver_presentation_red_without_sender_window_tail' {
      'Inspect receiver renderer/texture presentation because sampled presentation-red windows did not show sender window tail evidence.'
    }
    'sender_tail_without_receiver_presentation_red' {
      'Keep sender tail evidence as risk, but do not attribute receiver presentation failure without matching receiver-red windows.'
    }
    'sender_receiver_windows_green' {
      'Require visual or user-visible proof before declaring gameplay streaming green.'
    }
    default {
      'Collect aligned sender time windows and receiver presentation events before tuning behavior.'
    }
  }

  return [ordered]@{
    available = $true
    reason = ''
    classification = $classification
    summary = $summary
    next = $next
    sampledWindowCount = $sampledWindowCount
    receiverPresentationRedWindowCount = $receiverPresentationRedWindows.Count
    senderTailWindowCount = $senderTailWindows.Count
    coupledWindowCount = $coupledWindows.Count
    receiverOnlyWindowCount = $receiverOnlyWindows.Count
    senderOnlyWindowCount = $senderOnlyWindows.Count
    receiverPresentationRedWindows = @($receiverPresentationRedWindows)
    senderTailWindows = @($senderTailWindows)
    coupledWindows = @($coupledWindows)
    receiverOnlyWindows = @($receiverOnlyWindows)
    senderOnlyWindows = @($senderOnlyWindows)
    dominantTailSignals = @($dominantTailSignals)
    dominantTailSummary = ConvertTo-CompactList $dominantTailSignals
    dominantReceiverPresentationWindow = $dominantReceiverPresentationWindow
    dominantReceiverPresentationMs = $dominantReceiverPresentationMs
    thresholds = [ordered]@{
      receiverPresentationP95LimitMs = $ReceiverPresentationP95LimitMs
      senderTailLimitMs = 100.0
      senderSentP95LimitMs = 50.0
      minUniqueFps = $MinUniqueFps
    }
    tailCounts = $tailCounts
    rows = $rowSummaries
  }
}

function Copy-IfExists([string]$Path, [string]$DestinationDirectory) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return ''
  }
  $destination = Join-Path $DestinationDirectory ([System.IO.Path]::GetFileName($Path))
  Copy-Item -LiteralPath $Path -Destination $destination -Force
  return $destination
}

function Resolve-ReportJsonPath([string]$ReportPath, [datetime]$StartedAt, [string]$StreamTestDir) {
  if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    if (([System.IO.Path]::GetExtension($ReportPath)).ToLowerInvariant() -eq '.json' -and
        (Test-Path -LiteralPath $ReportPath)) {
      return (Resolve-Path -LiteralPath $ReportPath).Path
    }
    $candidate = [System.IO.Path]::ChangeExtension($ReportPath, '.json')
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  if (-not (Test-Path -LiteralPath $StreamTestDir)) {
    return ''
  }
  $threshold = $StartedAt.AddSeconds(-2)
  $latest = Get-ChildItem -LiteralPath $StreamTestDir -Filter 'stream-test-*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $threshold } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($latest) {
    return $latest.FullName
  }
  return ''
}

function Invoke-ToolProcess(
  [string]$FileName,
  [string[]]$Arguments,
  [string]$StdoutPath,
  [string]$StderrPath
) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FileName
  $startInfo.Arguments = ConvertTo-ArgumentString $Arguments
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if (-not [string]::IsNullOrWhiteSpace($StdoutPath)) {
    $stdout | Set-Content -LiteralPath $StdoutPath -Encoding UTF8
  }
  if (-not [string]::IsNullOrWhiteSpace($StderrPath)) {
    $stderr | Set-Content -LiteralPath $StderrPath -Encoding UTF8
  }
  if ($process.ExitCode -ne 0) {
    throw "$FileName exited with code $($process.ExitCode): $stderr"
  }
}

function Start-RecordingProcess(
  [string]$FfmpegExe,
  [object]$Rect,
  [int]$Seconds,
  [string]$OutputPath,
  [string]$LogPath,
  [string]$CaptureMode,
  [string]$VideoCodec,
  [int]$DdagrabOutputIndex,
  [int]$DdagrabOriginX,
  [int]$DdagrabOriginY
) {
  $codecArguments = Get-RecordingCodecArguments -Codec $VideoCodec
  if ($CaptureMode -eq 'ddagrab') {
    $offsetX = $Rect.X
    $offsetY = $Rect.Y
    $outputIndexSpec = ''
    $screenEnumerationSucceeded = $false
    $screens = @()
    try {
      Add-Type -AssemblyName System.Windows.Forms
      $screens = @([System.Windows.Forms.Screen]::AllScreens)
      $screenEnumerationSucceeded = $true
    } catch {
      if ($DdagrabOutputIndex -ge 0) {
        Write-Warning (
          "Monitor enumeration failed; using supplied ddagrab output_idx " +
          "$DdagrabOutputIndex with origin ${DdagrabOriginX},${DdagrabOriginY}: " +
          "$($_.Exception.Message)"
        )
      } else {
        Write-Warning (
          'Falling back to desktop-relative ddagrab coordinates after monitor ' +
          "enumeration failed: $($_.Exception.Message)"
        )
      }
    }
    if ($screenEnumerationSucceeded) {
      if ($DdagrabOutputIndex -ge $screens.Count) {
        Write-Warning (
          "Ignoring invalid ddagrab output index $DdagrabOutputIndex; " +
          "only $($screens.Count) monitor(s) were enumerated."
        )
        $DdagrabOutputIndex = -1
      }
      if ($DdagrabOutputIndex -ge 0) {
        $selectedScreenBounds = $screens[$DdagrabOutputIndex].Bounds
        $DdagrabOriginX = $selectedScreenBounds.X
        $DdagrabOriginY = $selectedScreenBounds.Y
      } else {
        for ($screenIndex = 0; $screenIndex -lt $screens.Count; $screenIndex++) {
          $area = $screens[$screenIndex].Bounds
          if ($Rect.X -ge $area.X -and
              $Rect.Y -ge $area.Y -and
              ($Rect.X + $Rect.Width) -le ($area.X + $area.Width) -and
              ($Rect.Y + $Rect.Height) -le ($area.Y + $area.Height)) {
            $DdagrabOutputIndex = $screenIndex
            $DdagrabOriginX = $area.X
            $DdagrabOriginY = $area.Y
            break
          }
        }
      }
      if ($DdagrabOutputIndex -lt 0 -and $screenEnumerationSucceeded) {
        Write-Warning (
          'Falling back to desktop-relative ddagrab coordinates because no ' +
          "monitor Bounds contained rect $($Rect.X),$($Rect.Y) " +
          "$($Rect.Width)x$($Rect.Height)."
        )
      }
    }
    if ($DdagrabOutputIndex -ge 0) {
      $offsetX = $Rect.X - $DdagrabOriginX
      $offsetY = $Rect.Y - $DdagrabOriginY
      $outputIndexSpec = ":output_idx=$DdagrabOutputIndex"
    }
    $captureSpec = "ddagrab=framerate=30:video_size=$($Rect.Width)x$($Rect.Height):offset_x=${offsetX}:offset_y=${offsetY}:output_fmt=bgra:draw_mouse=0$outputIndexSpec"
    $arguments = @(
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      $captureSpec,
      '-t',
      "$Seconds"
    ) + $codecArguments + @(
      $OutputPath
    )
  } else {
    $arguments = @(
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'gdigrab',
      '-framerate',
      '30',
      '-offset_x',
      "$($Rect.X)",
      '-offset_y',
      "$($Rect.Y)",
      '-video_size',
      "$($Rect.Width)x$($Rect.Height)",
      '-i',
      'desktop',
      '-t',
      "$Seconds",
      '-pix_fmt',
      'yuv420p'
    ) + $codecArguments + @(
      $OutputPath
    )
  }

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfmpegExe
  $startInfo.Arguments = ConvertTo-ArgumentString $arguments
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $false
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  "ffmpeg command: $FfmpegExe $($startInfo.Arguments)" |
    Set-Content -LiteralPath $LogPath -Encoding UTF8
  [void]$process.Start()
  return [pscustomobject]@{
    Process = $process
    LogPath = $LogPath
    Rect = $Rect
    CaptureMode = $CaptureMode
    VideoCodec = $VideoCodec
    DdagrabOutputIndex = $DdagrabOutputIndex
    DdagrabOriginX = $DdagrabOriginX
    DdagrabOriginY = $DdagrabOriginY
  }
}

function Start-CaptureTargetProcess(
  [string]$ExecutablePath,
  [string]$Title,
  [int]$Width,
  [int]$Height,
  [string]$Scene,
  [string]$Fps,
  [string]$OutputDirectory
) {
  New-SafeDirectory $OutputDirectory
  $arguments = @(
    '--width',
    "$Width",
    '--height',
    "$Height",
    '--mode',
    'windowed',
    '--scene',
    $Scene,
    '--fps',
    $Fps,
    '--title',
    $Title,
    '--output-dir',
    $OutputDirectory
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $ExecutablePath
  $startInfo.Arguments = ConvertTo-ArgumentString $arguments
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $false
  $startInfo.RedirectStandardError = $false
  $startInfo.CreateNoWindow = $false

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  return $process
}

function Move-CaptureTargetWindow(
  [System.Diagnostics.Process]$Process,
  [int]$X,
  [int]$Y
) {
  Ensure-WindowRectType
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
  $hWnd = [IntPtr]::Zero
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $Process.Refresh()
    $hWnd = [InterGalactic.StreamLab.WindowCapture]::FindVisibleWindowForProcessId(
      $Process.Id
    )
    if ($hWnd -ne [IntPtr]::Zero) {
      break
    }
    Start-Sleep -Milliseconds 100
  }
  if ($hWnd -eq [IntPtr]::Zero) {
    throw "Could not find visible capture target window for process $($Process.Id)."
  }

  $rect = New-Object InterGalactic.StreamLab.WindowCapture+RECT
  if (-not [InterGalactic.StreamLab.WindowCapture]::GetWindowRect($hWnd, [ref]$rect)) {
    throw "GetWindowRect failed for capture target process $($Process.Id)."
  }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  $swpNoZOrder = 0x0004
  $swpNoActivate = 0x0010
  $flags = [uint32]($swpNoZOrder -bor $swpNoActivate)
  if (-not [InterGalactic.StreamLab.WindowCapture]::SetWindowPos(
      $hWnd,
      [IntPtr]::Zero,
      $X,
      $Y,
      $width,
      $height,
      $flags
    )) {
    throw "SetWindowPos failed for capture target process $($Process.Id)."
  }

  return [pscustomobject]@{
    Hwnd = $hWnd
    HwndDecimal = $hWnd.ToInt64()
    X = $X
    Y = $Y
    Width = $width
    Height = $height
  }
}

function Move-WindowHandle(
  [IntPtr]$Hwnd,
  [int]$ExpectedProcessId,
  [int]$X,
  [int]$Y,
  [string]$Stage
) {
  Ensure-WindowRectType
  $windowInfo = Get-WindowInfoForHandle -Hwnd $Hwnd -ExpectedProcessId $ExpectedProcessId -Stage $Stage
  $swpNoZOrder = 0x0004
  $swpNoActivate = 0x0010
  $flags = [uint32]($swpNoZOrder -bor $swpNoActivate)
  if (-not [InterGalactic.StreamLab.WindowCapture]::SetWindowPos(
      $Hwnd,
      [IntPtr]::Zero,
      $X,
      $Y,
      $windowInfo.Width,
      $windowInfo.Height,
      $flags
    )) {
    throw "SetWindowPos failed for Inter Galactic process $ExpectedProcessId during $Stage."
  }
  Start-Sleep -Milliseconds 300
  return Get-WindowInfoForHandle -Hwnd $Hwnd -ExpectedProcessId $ExpectedProcessId -Stage $Stage
}

function Invoke-StreamLabOpenRoom(
  [object]$Process,
  [string]$ConfiguredAppExe,
  [string]$RoomAddress,
  [string]$ClientId,
  [int]$SettleSeconds
) {
  if ([string]::IsNullOrWhiteSpace($RoomAddress)) {
    return $null
  }

  $pipeName = 'chat.intergalactic.app'
  $instanceId = $env:INTERGALACTIC_DEV_INSTANCE_ID
  if (-not [string]::IsNullOrWhiteSpace($instanceId)) {
    $safeInstanceId = $instanceId.Trim() -replace '[^A-Za-z0-9_.-]', '_'
    if (-not [string]::IsNullOrWhiteSpace($safeInstanceId)) {
      $pipeName = "$pipeName.$safeInstanceId"
    }
  }

  $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
    '.',
    $pipeName,
    [System.IO.Pipes.PipeDirection]::InOut,
    [System.IO.Pipes.PipeOptions]::None
  )
  $hello = ''
  try {
    $pipe.Connect(3000)
    $buffer = New-Object byte[] 4096
    $read = $pipe.Read($buffer, 0, $buffer.Length)
    if ($read -gt 0) {
      $hello = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
    }

    $message = [ordered]@{
      type = 'stream_lab_open_room'
      room = $RoomAddress
    }
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) {
      $message['client_id'] = $ClientId
    }
    $json = $message | ConvertTo-Json -Compress -Depth 4
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $pipe.Write($bytes, 0, $bytes.Length)
    $pipe.Flush()
  } finally {
    $pipe.Dispose()
  }
  Start-Sleep -Seconds ([Math]::Max(0, $SettleSeconds))
  $Process.Refresh()

  return [pscustomobject]@{
    ProcessId = $Process.Id
    PipeName = $pipeName
    Hello = $hello
    RoomAddress = $RoomAddress
    ClientId = if ([string]::IsNullOrWhiteSpace($ClientId)) { $null } else { $ClientId }
    SettleSeconds = $SettleSeconds
    OpenedAt = (Get-Date).ToString('o')
  }
}

function New-ExistingAppWindowSelection(
  [object]$Process,
  [string]$WindowTitle
) {
  Ensure-WindowRectType
  $hWnd = [InterGalactic.StreamLab.WindowCapture]::FindVisibleWindowForProcessId($Process.Id)
  if ($hWnd -eq [IntPtr]::Zero) {
    throw "No visible Inter Galactic window was found for process id $($Process.Id)."
  }
  $title = [InterGalactic.StreamLab.WindowCapture]::GetWindowTitle($hWnd)
  return [pscustomobject]@{
    Pid = $Process.Id
    ProcessName = $Process.ProcessName
    MainWindowHandle = $hWnd.ToInt64()
    HasWindowHandle = $true
    MainWindowTitle = $title
    HasWindowTitle = -not [string]::IsNullOrWhiteSpace($title)
    MatchedProcessCount = 1
    Activated = $true
    ActivatedBy = @('existing-window')
    ActivationAttemptsUsed = 0
    Hotkey = if ([string]::IsNullOrWhiteSpace($WindowTitle)) { 'skipped' } else { "skipped for $WindowTitle" }
    SendKeys = $null
    DryRun = $true
    SentAt = $null
  }
}

function Invoke-Bg3CameraRotationHotkey(
  [string]$WorkspaceRoot,
  [int]$ProcessId,
  [string]$Action,
  [string]$OutputPath
) {
  $hotkeyScript = Join-Path $WorkspaceRoot 'tools\stream-lab\send_bg3_camera_rotation_hotkey.ps1'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hotkeyScript `
    -ProcessId $ProcessId `
    -Action $Action `
    -AsJson |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8
  if ($LASTEXITCODE -ne 0) {
    throw "BG3 camera rotation $Action helper failed with exit code $LASTEXITCODE."
  }
}

function Wait-ReceiverProbeWindowPlacement(
  [string]$Path,
  [int]$TimeoutSeconds
) {
  $started = Get-Date
  $deadline = $started.AddSeconds([Math]::Max(1, $TimeoutSeconds))
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $Path) {
      $parsed = $null
      $status = ''
      $reason = ''
      try {
        $parsed = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
        $statusProperty = $parsed.PSObject.Properties['status']
        if ($null -ne $statusProperty) {
          $status = [string]$statusProperty.Value
        }
        $reasonProperty = $parsed.PSObject.Properties['reason']
        if ($null -ne $reasonProperty) {
          $reason = [string]$reasonProperty.Value
        }
      } catch {
        $status = 'unreadable'
        $reason = $_.Exception.Message
      }
      return [pscustomobject]@{
        observed = $true
        path = $Path
        status = $status
        reason = $reason
        waitedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        target = if ($null -ne $parsed) {
          Get-JsonProperty $parsed 'target'
        } else {
          $null
        }
        monitor = if ($null -ne $parsed) {
          Get-JsonProperty $parsed 'monitor'
        } else {
          $null
        }
      }
    }
    Start-Sleep -Milliseconds 250
  }

  return [pscustomobject]@{
    observed = $false
    path = $Path
    status = 'missing'
    reason = "receiver-window-placement.json was not written within $TimeoutSeconds seconds."
    waitedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    target = $null
    monitor = $null
  }
}

function Wait-RecordingProcess([object]$Recording, [int]$TimeoutSeconds) {
  $process = $Recording.Process
  $exited = $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
  $stderr = ''
  try {
    $stderr = $process.StandardError.ReadToEnd()
  } catch {
  }
  if (-not $exited) {
    try {
      $process.Kill()
    } catch {
    }
    throw "Timed out waiting for ffmpeg recording after $TimeoutSeconds seconds."
  }
  @(
    "ffmpeg recording exit code: $($process.ExitCode)"
    $stderr
  ) | Add-Content -LiteralPath $Recording.LogPath -Encoding UTF8
  if ($process.ExitCode -ne 0) {
    throw "ffmpeg recording exited with code $($process.ExitCode)."
  }
}

function Get-VideoSize([string]$FfprobeExe, [string]$VideoPath) {
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FfprobeExe
  $startInfo.Arguments = ConvertTo-ArgumentString @(
    '-v',
    'error',
    '-select_streams',
    'v:0',
    '-show_entries',
    'stream=width,height',
    '-of',
    'csv=p=0',
    $VideoPath
  )
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd().Trim()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "ffprobe exited with code $($process.ExitCode): $stderr"
  }
  $parts = $stdout.Split(',')
  if ($parts.Count -lt 2) {
    throw "Unexpected ffprobe size output: $stdout"
  }
  return [pscustomobject]@{
    Width = [int]$parts[0]
    Height = [int]$parts[1]
  }
}

$repoRoot = Resolve-RepoRoot
Import-StreamLabLocalEnv -RepoRoot $repoRoot
$workspaceRoot = Resolve-StreamLabWorkspaceRoot -RepoRoot $repoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Resolve-StreamLabOutputRoot -RepoRoot $repoRoot -WorkspaceRoot $workspaceRoot
}
New-SafeDirectory $OutputRoot

if ([string]::IsNullOrWhiteSpace($AppExe)) {
  $AppExe = Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\InterGalactic.exe'
}
if ($ProcessId -le 0) {
  $AppExe = (Resolve-Path -LiteralPath $AppExe).Path
}

$streamTestDir = Resolve-StreamLabAppStreamTestDirectory -RepoRoot $repoRoot
New-SafeDirectory $streamTestDir

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sourceOverrideRequested = $SourceProcessId -gt 0
if (-not $sourceOverrideRequested -and -not [string]::IsNullOrWhiteSpace($SourceTitle)) {
  throw '-SourceTitle requires -SourceProcessId so the stream-test source can be selected safely.'
}
$outputBaseName = if ($sourceOverrideRequested) {
  'source-live-call-freshness'
} else {
  'synthetic-live-call-freshness'
}
$id = "$outputBaseName-$stamp"
$runDirectory = Join-Path $OutputRoot $id
New-SafeDirectory $runDirectory

$externalReceiverProbeRequested = [bool]$ReceiverProbeEnabled -and
  ($ReceiverProbeMode -eq 'external-decode-only' -or
    $ReceiverProbeMode -eq 'external-render')
$appReceiverProbeMode = if ($ReceiverProbeMode -eq 'external-render') {
  'render'
} elseif ($ReceiverProbeMode -eq 'external-decode-only') {
  'decode-only'
} else {
  $ReceiverProbeMode
}
$receiverProbeControlPipe = if ($externalReceiverProbeRequested) {
  New-ReceiverProbePipeName -RunId $id
} else {
  ''
}
$receiverProbeRunId = if ($externalReceiverProbeRequested) {
  "$id-external-receiver"
} else {
  "$id-in-process-receiver"
}
$receiverProbeOutputRoot = Join-Path $runDirectory 'receiver-results'
$receiverProbeRunDirectory = Join-Path $receiverProbeOutputRoot $receiverProbeRunId
$receiverProbeSummaryPath = Join-Path $receiverProbeRunDirectory 'receiver-summary.json'
$receiverProbeReportPath = Join-Path $receiverProbeRunDirectory 'true-receiver-test.json'
$receiverProbeWindowPlacementPath = Join-Path $receiverProbeRunDirectory 'receiver-window-placement.json'

$requestPath = Join-Path $streamTestDir 'stream-test-request.json'
$completePath = Join-Path $streamTestDir "stream-test-request-$id.complete.json"
$startedAt = Get-Date

if (Test-Path -LiteralPath $requestPath) {
  throw "A stream-test automation request is already pending: $requestPath"
}
if (Test-Path -LiteralPath $completePath) {
  Remove-Item -LiteralPath $completePath -Force
}

$ffmpeg = Resolve-Ffmpeg
$ffprobe = Resolve-Ffprobe
$startedProcess = $false
$appProcess = $null
$captureTargetProcess = $null
$captureTargetWindow = $null
$sourceOverrideProcess = $null
$sourceRequestTitle = ''
$appWindowMove = $null
$externalReceiverProbeProcess = $null
$externalReceiverProbeStarted = $false
$receiverProbeWindowPlacement = $null
$bg3RotationStarted = $false
$bg3RotationStartJson = ''
$bg3RotationStopJson = ''
$bg3FocusReassertions = [System.Collections.Generic.List[string]]::new()
$bg3LastFocusReassertionAt = $null
$captureTargetOutputDirectory = ''
$joinButtonClick = $null
$callEntryVerification = $null
$recording = $null
$recordingResolvedDdagrabOutputIndex = $RecordingDdagrabOutputIndex
$recordingResolvedDdagrabOriginX = $RecordingDdagrabOriginX
$recordingResolvedDdagrabOriginY = $RecordingDdagrabOriginY
$fullVideo = $null
$tightVideoFull = ''
$tightVideo = ''
$recordingLog = ''
$visualDirectory = ''
$visualLog = ''
$visualExitCode = $null
$visual = $null
$size = $null
$receiverProbeWindowRecording = $null
$receiverProbeWindowRecordRect = $null
$receiverProbeWindowVideoFull = ''
$receiverProbeWindowVideo = ''
$receiverProbeWindowRecordingLog = ''
$receiverProbeWindowVisualDirectory = ''
$receiverProbeWindowVisualReportPath = ''
$receiverProbeWindowVisualLog = ''
$receiverProbeWindowVisualExitCode = $null
$receiverProbeWindowVisual = $null
$receiverProbeWindowVisualStatus = ''
$receiverProbeWindowUniqueFps = $null
$receiverProbeWindowLongestStaleMs = $null
$receiverProbeWindowExactUniqueFps = $null
$receiverProbeWindowExactDuplicateFrames = $null
$receiverProbeWindowExactLongestStaleMs = $null
$receiverProbeWindowSourceMarkerDecodedFrames = $null
$receiverProbeWindowSourceMarkerMissingFrames = $null
$receiverProbeWindowSourceMarkerUniqueFps = $null
$receiverProbeWindowSourceMarkerLongestStaleMs = $null
$receiverProbeWindowSourceMarkerAvailable = $false
$receiverProbeWindowSourceMarkerPass = $false
$previousVideoFrameTrackingIdEnv = $env:INTERGALACTIC_VIDEO_FRAME_TRACKING_ID
$videoFrameTrackingIdEnvChanged = $false
$previousSourceFrameVisualMarkerEnv = $env:INTERGALACTIC_GAME_CAPTURE_SOURCE_FRAME_VISUAL_MARKER
$sourceFrameVisualMarkerEnvChanged = $false
$videoFrameTrackingIdRequested = [bool]$ReceiverProbeEnabled -and
  $ReceiverProbeFrameDiagnosticsMode -eq 'native-renderer-hash'
if ($videoFrameTrackingIdRequested) {
  $env:INTERGALACTIC_VIDEO_FRAME_TRACKING_ID = '1'
  $videoFrameTrackingIdEnvChanged = $true
}
if ($SourceFrameContentMarker) {
  $env:INTERGALACTIC_GAME_CAPTURE_SOURCE_FRAME_VISUAL_MARKER = '1'
  $sourceFrameVisualMarkerEnvChanged = $true
}
$receiverProbeWindowActiveSegmentStartSeconds = if ($ReceiverProbeWindowMeasureStartSeconds -ge 0) {
  [Math]::Max(0, $ReceiverProbeWindowMeasureStartSeconds)
} else {
  [Math]::Max(0, $ActiveSegmentStartSeconds)
}
$receiverProbeWindowRequestedSegmentSeconds = if ($ReceiverProbeWindowMeasureSeconds -gt 0) {
  $ReceiverProbeWindowMeasureSeconds
} else {
  $ActiveSegmentSeconds
}
$receiverProbeWindowActiveSegmentSeconds =
  [Math]::Max(
    1,
    [Math]::Min(
      $receiverProbeWindowRequestedSegmentSeconds,
      $RecordingSeconds - $receiverProbeWindowActiveSegmentStartSeconds
    )
  )
$recordingCodec = Resolve-RecordingVideoCodec -FfmpegExe $ffmpeg -RequestedCodec $RecordingVideoCodec
$recordingCaptureMode = Resolve-RecordingCaptureMode `
  -FfmpegExe $ffmpeg `
  -RequestedMode $RecordingCaptureMode `
  -VideoCodec $recordingCodec
$receiverProbeWindowRequestedVideoCodec = if (
  [string]::IsNullOrWhiteSpace($ReceiverProbeWindowRecordingVideoCodec)
) {
  $RecordingVideoCodec
} else {
  $ReceiverProbeWindowRecordingVideoCodec
}
$receiverProbeWindowVideoCodec = Resolve-RecordingVideoCodec `
  -FfmpegExe $ffmpeg `
  -RequestedCodec $receiverProbeWindowRequestedVideoCodec
$receiverProbeWindowRequestedCaptureMode = if (
  [string]::IsNullOrWhiteSpace($ReceiverProbeWindowRecordingCaptureMode)
) {
  $RecordingCaptureMode
} else {
  $ReceiverProbeWindowRecordingCaptureMode
}
$receiverProbeWindowCaptureMode = Resolve-RecordingCaptureMode `
  -FfmpegExe $ffmpeg `
  -RequestedMode $receiverProbeWindowRequestedCaptureMode `
  -VideoCodec $receiverProbeWindowVideoCodec
$receiverProbeWindowResolvedDdagrabOutputIndex =
  $ReceiverProbeWindowRecordingDdagrabOutputIndex
$receiverProbeWindowResolvedDdagrabOriginX =
  $ReceiverProbeWindowRecordingDdagrabOriginX
$receiverProbeWindowResolvedDdagrabOriginY =
  $ReceiverProbeWindowRecordingDdagrabOriginY

try {
  if ($ProcessId -gt 0) {
    $appProcess = Get-Process -Id $ProcessId -ErrorAction Stop
  } else {
    $appProcess = Start-Process -FilePath $AppExe -PassThru
    $startedProcess = $true
  }

  $hotkeyScript = Join-Path $workspaceRoot 'tools\stream-lab\send_intergalactic_call_hotkey.ps1'
  $hotkeyJson = Join-Path $runDirectory 'call-hotkey.json'
  $roomOpenJson = Join-Path $runDirectory 'call-room-open.json'
  $roomOpenResult = Invoke-StreamLabOpenRoom `
    -Process $appProcess `
    -ConfiguredAppExe $AppExe `
    -RoomAddress $CallRoomAddress `
    -ClientId $CallRoomClientId `
    -SettleSeconds $CallRoomOpenSettleSeconds
  if ($null -ne $roomOpenResult) {
    $roomOpenResult |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath $roomOpenJson -Encoding UTF8
  }

  if ($SkipCallHotkey) {
    New-ExistingAppWindowSelection `
      -Process $appProcess `
      -WindowTitle $WindowTitle |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath $hotkeyJson -Encoding UTF8
  } else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hotkeyScript `
      -ProcessId $appProcess.Id `
      -WindowTitle $WindowTitle `
      -StartupDelaySeconds $StartupDelaySeconds `
      -AsJson |
      Set-Content -LiteralPath $hotkeyJson -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
      throw "Call hotkey helper failed with exit code $LASTEXITCODE."
    }
  }
  $hotkeyResult = Get-Content -Raw -LiteralPath $hotkeyJson | ConvertFrom-Json
  $hotkeySelection = Get-HotkeyWindowSelection `
    -HotkeyResult $hotkeyResult `
    -ExpectedProcessId $appProcess.Id `
    -ExpectedTitle $WindowTitle

  $callEntryVerificationPath = Join-Path $runDirectory 'call-entry-verification.json'
  $callEntryVerification = Wait-CallEntryVerification `
    -Hwnd $hotkeySelection.Hwnd `
    -ExpectedProcessId $appProcess.Id `
    -ExpectedTitle $ExpectedCallWindowTitle `
    -TimeoutSeconds $CallEntryVerifyTimeoutSeconds `
    -Skip ([bool]$SkipCallEntryVerification)
  $callEntryVerification |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $callEntryVerificationPath -Encoding UTF8
  if ($callEntryVerification.status -eq 'failed_wrong_window') {
    throw "Call entry verification failed: expected Inter Galactic window title containing '$ExpectedCallWindowTitle' but observed '$($callEntryVerification.observedTitle)'. See $callEntryVerificationPath."
  }
  $appWindowHwnd = $hotkeySelection.Hwnd
  if ($callEntryVerification.status -eq 'verified' -and $callEntryVerification.windowHandle) {
    $verifiedCallHwnd = ConvertTo-WindowHandle $callEntryVerification.windowHandle
    if ($verifiedCallHwnd -ne [IntPtr]::Zero) {
      $appWindowHwnd = $verifiedCallHwnd
    }
  }

  if ($ClickJoinButtonAfterHotkey) {
    Start-Sleep -Seconds 1
    $joinButtonClick = Invoke-WindowRelativeClick `
      -Hwnd $appWindowHwnd `
      -TargetProcessId $appProcess.Id `
      -RelativeX $JoinButtonRelativeX `
      -RelativeY $JoinButtonRelativeY `
      -Stage 'call join button click'
    Start-Sleep -Seconds ([Math]::Max(0, $JoinButtonSettleSeconds))
  }

  Start-Sleep -Seconds 2

  if (($AppWindowX -ne -2147483648) -or ($AppWindowY -ne -2147483648)) {
    if ($AppWindowX -eq -2147483648 -or $AppWindowY -eq -2147483648) {
      throw '-AppWindowX and -AppWindowY must be provided together.'
    }
    $appWindowMove = Move-WindowHandle `
      -Hwnd $appWindowHwnd `
      -ExpectedProcessId $appProcess.Id `
      -X $AppWindowX `
      -Y $AppWindowY `
      -Stage 'app window move'
  }

  if ($sourceOverrideRequested) {
    $sourceOverrideProcess = Get-Process -Id $SourceProcessId -ErrorAction Stop
    $sourceRequestTitle = $SourceTitle
    if ([string]::IsNullOrWhiteSpace($sourceRequestTitle)) {
      $sourceRequestTitle = $sourceOverrideProcess.MainWindowTitle
    }
    if ([string]::IsNullOrWhiteSpace($sourceRequestTitle)) {
      $sourceRequestTitle = $sourceOverrideProcess.ProcessName
    }
  }

  $externalCaptureTarget = (-not $sourceOverrideRequested) -and
    (-not $UseAppLaunchedCaptureTarget) -and
    (-not $DummyNv12LiveSender)
  if ($externalCaptureTarget) {
    $captureTargetOutputDirectory = Join-Path $runDirectory 'capture-target'
    $captureTargetProcess = Start-CaptureTargetProcess `
      -ExecutablePath (Resolve-CaptureTargetExe -ConfiguredPath $CaptureTargetExe -RepoRoot $repoRoot) `
      -Title $CaptureTargetTitle `
      -Width $CaptureTargetWidth `
      -Height $CaptureTargetHeight `
      -Scene $CaptureTargetScene `
      -Fps $CaptureTargetFps `
      -OutputDirectory $captureTargetOutputDirectory
    Start-Sleep -Milliseconds 1200
    if ($CaptureTargetX -ne -2147483648 -and $CaptureTargetY -ne -2147483648) {
      $captureTargetWindow = Move-CaptureTargetWindow `
        -Process $captureTargetProcess `
        -X $CaptureTargetX `
        -Y $CaptureTargetY
      Start-Sleep -Milliseconds 300
    }
  }

  $windowRect = Get-WindowCaptureRect `
    -TargetProcessId $appProcess.Id `
    -PreferredHwnd $appWindowHwnd `
    -Stage 'preflight capture' `
    -RequireForeground (-not [bool]$AllowBackgroundAppRecording)
  $preflightFrame = Join-Path $runDirectory 'preflight-intergalactic-window.png'
  $preflightStats = Invoke-PreflightWindowCheck `
    -FfmpegExe $ffmpeg `
    -Rect $windowRect `
    -FramePath $preflightFrame `
    -CaptureLogPath (Join-Path $runDirectory 'preflight-intergalactic-window-ffmpeg.log') `
    -StatsLogPath (Join-Path $runDirectory 'preflight-intergalactic-window-stats-ffmpeg.log')

    $tightRecordRect = [pscustomobject]@{
      X = $windowRect.X + $CropX
      Y = $windowRect.Y + $CropY
      Width = $CropWidth
      Height = $CropHeight
    }
  if (-not [bool]$SkipSelfViewRecording) {
    $tightVideoFull = Join-Path $runDirectory 'synthetic-live-call-stream-tight-full.mp4'
    $recordingLog = Join-Path $runDirectory 'synthetic-live-call-stream-tight-full-ffmpeg.log'
    $recording = Start-RecordingProcess `
      -FfmpegExe $ffmpeg `
      -Rect $tightRecordRect `
      -Seconds $RecordingSeconds `
      -OutputPath $tightVideoFull `
      -LogPath $recordingLog `
      -CaptureMode $recordingCaptureMode `
      -VideoCodec $recordingCodec `
      -DdagrabOutputIndex $RecordingDdagrabOutputIndex `
      -DdagrabOriginX $RecordingDdagrabOriginX `
      -DdagrabOriginY $RecordingDdagrabOriginY
    $recordingResolvedDdagrabOutputIndex = [int]$recording.DdagrabOutputIndex
    $recordingResolvedDdagrabOriginX = [int]$recording.DdagrabOriginX
    $recordingResolvedDdagrabOriginY = [int]$recording.DdagrabOriginY

    Start-Sleep -Seconds 2
    if ($recording.Process.HasExited) {
      Wait-RecordingProcess -Recording $recording -TimeoutSeconds 1
    }
  } else {
    Start-Sleep -Seconds 2
  }

  $requestWindowRect = Get-WindowCaptureRect `
    -TargetProcessId $appProcess.Id `
    -PreferredHwnd $appWindowHwnd `
    -Stage 'stream-test request' `
    -RequireForeground (-not [bool]$AllowBackgroundAppRecording)
  if ([bool]$SkipSelfViewRecording) {
    $windowRect = $requestWindowRect
  } else {
    Assert-WindowRectStable `
      -Expected $windowRect `
      -Actual $requestWindowRect `
      -TolerancePixels 2 `
      -Stage 'stream-test request'
  }

  if ($StartBg3CameraRotation -and -not $externalReceiverProbeRequested) {
    if (-not $sourceOverrideRequested -or $null -eq $sourceOverrideProcess) {
      throw '-StartBg3CameraRotation requires -SourceProcessId so the BG3 process can be targeted.'
    }
    $bg3RotationStartJson = Join-Path $runDirectory 'bg3-camera-rotation-start.json'
    Invoke-Bg3CameraRotationHotkey `
      -WorkspaceRoot $workspaceRoot `
      -ProcessId $sourceOverrideProcess.Id `
      -Action 'Start' `
      -OutputPath $bg3RotationStartJson
    $bg3RotationStarted = $true
    Start-Sleep -Milliseconds 500
  }

  if ($externalReceiverProbeRequested) {
    $trueReceiverRunner = Join-Path $PSScriptRoot 'run_true_receiver_test.ps1'
    $resolvedReceiverProbeExe = if ([string]::IsNullOrWhiteSpace($ReceiverProbeExe)) {
      Join-Path $repoRoot 'tools\stream-receiver-probe\InterGalacticReceiverProbe.ps1'
    } else {
      $ReceiverProbeExe
    }
    $resolvedReceiverProbeAppExe = if (-not [string]::IsNullOrWhiteSpace($ReceiverProbeAppExe)) {
      $ReceiverProbeAppExe
    } elseif (-not [string]::IsNullOrWhiteSpace($AppExe)) {
      $AppExe
    } else {
      Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\InterGalactic.exe'
    }
    $externalRunnerMode = if ($ReceiverProbeMode -eq 'external-render') {
      'Render'
    } else {
      'DecodeOnly'
    }
    $externalReceiverProbeDurationSeconds =
      [Math]::Max(1, $DurationSeconds + $WarmupSeconds + 5)
    $externalReceiverProbeTimeoutSeconds =
      [Math]::Max($TimeoutSeconds, $externalReceiverProbeDurationSeconds + 160)
    $externalRunnerArgs = @(
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      $trueReceiverRunner,
      '-Mode',
      $externalRunnerMode,
      '-RunId',
      $receiverProbeRunId,
      '-DurationSeconds',
      $externalReceiverProbeDurationSeconds.ToString(),
      '-ExpectedWidth',
      $PublicationHandoffMaxWidth.ToString(),
      '-ExpectedHeight',
      $PublicationHandoffMaxHeight.ToString(),
      '-ExpectedFps',
      $PublicationHandoffTargetFps.ToString(),
      '-OutputRoot',
      $receiverProbeOutputRoot,
      '-ProbeExe',
      $resolvedReceiverProbeExe,
      '-ProbeAppExe',
      $resolvedReceiverProbeAppExe,
      '-ProbeControlPipe',
      $receiverProbeControlPipe,
      '-FrameDiagnosticsMode',
      $ReceiverProbeFrameDiagnosticsMode,
      '-MinUniqueFps',
      $MinUniqueFps.ToString([System.Globalization.CultureInfo]::InvariantCulture),
      '-TimeoutSeconds',
      $externalReceiverProbeTimeoutSeconds.ToString()
    )
    if ($ReceiverProbeMonitorIndex -ge 0) {
      $externalRunnerArgs += @('-ProbeMonitorIndex', $ReceiverProbeMonitorIndex.ToString())
    }
    if ($ReceiverProbeVisualFrameMarker) {
      $externalRunnerArgs += @('-VisualFrameMarker')
    }
    $externalReceiverProbeProcess = Start-Process `
      -FilePath 'powershell.exe' `
      -ArgumentList $externalRunnerArgs `
      -WorkingDirectory $runDirectory `
      -WindowStyle Hidden `
      -PassThru
    $externalReceiverProbeStarted = $true
  }

  $request = [ordered]@{
    schema = 'intergalactic.streamTestAutomationRequest.v1'
    id = $id
    presets = $Presets
    durationSeconds = $DurationSeconds
    warmupSeconds = $WarmupSeconds
    windowsBackendMode = $WindowsBackendMode
    nativeFramePacingEnabled = $true
    dummyNv12LiveSender = [bool]$DummyNv12LiveSender
    launchCaptureTarget = [bool]$UseAppLaunchedCaptureTarget
    publicationHandoff = [ordered]@{
      maxWidth = $PublicationHandoffMaxWidth
      maxHeight = $PublicationHandoffMaxHeight
      targetFps = $PublicationHandoffTargetFps
    }
    receiverProbe = [ordered]@{
      enabled = [bool]$ReceiverProbeEnabled
      mode = $appReceiverProbeMode
      inProcess = -not $externalReceiverProbeRequested
      startBeforeShare = -not $externalReceiverProbeRequested
      externalControlPipe = $receiverProbeControlPipe
      frameDiagnosticsMode = $ReceiverProbeFrameDiagnosticsMode
    }
    captureTarget = [ordered]@{
      enabled = [bool]$UseAppLaunchedCaptureTarget
      width = $CaptureTargetWidth
      height = $CaptureTargetHeight
      mode = 'windowed'
      scene = $CaptureTargetScene
      fps = $CaptureTargetFps
      title = $CaptureTargetTitle
    }
  }
  if ($PublicationHandoffMaxFps -gt 0) {
    $request.publicationHandoff.maxFps = $PublicationHandoffMaxFps
  }
  if ($PublicationHandoffBitrateKbps -gt 0) {
    $request.publicationHandoff.bitrateKbps = $PublicationHandoffBitrateKbps
  }
  if ($PublicationHandoffMinBitrateKbps -gt 0) {
    $request.publicationHandoff.minBitrateKbps = $PublicationHandoffMinBitrateKbps
  }
  if ($PublicationHandoffSingleLayer) {
    $request.publicationHandoff.singleLayer = $true
  }
  if ($PreferHardwareEncoding) {
    $request.preferHardwareEncoding = $true
  }
  if ($sourceOverrideRequested -and $null -ne $sourceOverrideProcess) {
    $request.sourceProcessId = $sourceOverrideProcess.Id
    $request.sourceTitle = $sourceRequestTitle
  }
  if ($externalCaptureTarget -and $null -ne $captureTargetProcess) {
    $request.sourceProcessId = $captureTargetProcess.Id
    $request.sourceTitle = $CaptureTargetTitle
  }

  $requestJson = $request | ConvertTo-Json -Depth 20
  $requestJson | Set-Content -LiteralPath $requestPath -Encoding UTF8
  $requestJson | Set-Content -LiteralPath (Join-Path $runDirectory 'stream-test-request.json') -Encoding UTF8

  $shouldHandleReceiverProbeWindow =
    $externalReceiverProbeRequested -and
    $ReceiverProbeMode -eq 'external-render'
  $shouldRecordReceiverProbeWindow =
    $shouldHandleReceiverProbeWindow -and
    -not [bool]$SkipReceiverProbeWindowRecording
  if ($shouldHandleReceiverProbeWindow) {
    $receiverProbeWindowPlacement = Wait-ReceiverProbeWindowPlacement `
      -Path $receiverProbeWindowPlacementPath `
      -TimeoutSeconds ([Math]::Max(15, [Math]::Min(60, $WarmupSeconds + 40)))
    if ($null -ne $receiverProbeWindowPlacement -and
        $receiverProbeWindowPlacement.status -eq 'moved') {
      $placementTarget = Get-JsonProperty $receiverProbeWindowPlacement 'target'
      $placementX = Get-JsonInt $placementTarget 'x'
      $placementY = Get-JsonInt $placementTarget 'y'
      $placementWidth = Get-JsonInt $placementTarget 'width'
      $placementHeight = Get-JsonInt $placementTarget 'height'
      if ($null -ne $placementX -and
          $null -ne $placementY -and
          $null -ne $placementWidth -and
          $null -ne $placementHeight -and
          $placementWidth -gt 0 -and
          $placementHeight -gt 0) {
        $receiverProbeWindowRecordRect = [pscustomobject]@{
          X = $placementX
          Y = $placementY
          Width = $placementWidth
          Height = $placementHeight
        }
        if ($shouldRecordReceiverProbeWindow) {
          if ($receiverProbeWindowCaptureMode -eq 'ddagrab' -and
              $receiverProbeWindowResolvedDdagrabOutputIndex -lt 0 -and
              $ReceiverProbeMonitorIndex -ge 0) {
            $placementMonitor =
              Get-JsonProperty $receiverProbeWindowPlacement 'monitor'
            $monitorX = Get-JsonInt $placementMonitor 'x'
            $monitorY = Get-JsonInt $placementMonitor 'y'
            if ($null -ne $monitorX -and $null -ne $monitorY) {
              $receiverProbeWindowResolvedDdagrabOutputIndex =
                $ReceiverProbeMonitorIndex
              $receiverProbeWindowResolvedDdagrabOriginX = $monitorX
              $receiverProbeWindowResolvedDdagrabOriginY = $monitorY
            }
          }
          $receiverProbeWindowVideoFull = Join-Path $runDirectory 'receiver-probe-window-full.mp4'
          $receiverProbeWindowRecordingLog =
            Join-Path $runDirectory 'receiver-probe-window-full-ffmpeg.log'
          $receiverProbeWindowRecording = Start-RecordingProcess `
            -FfmpegExe $ffmpeg `
            -Rect $receiverProbeWindowRecordRect `
            -Seconds $RecordingSeconds `
            -OutputPath $receiverProbeWindowVideoFull `
            -LogPath $receiverProbeWindowRecordingLog `
            -CaptureMode $receiverProbeWindowCaptureMode `
            -VideoCodec $receiverProbeWindowVideoCodec `
            -DdagrabOutputIndex $receiverProbeWindowResolvedDdagrabOutputIndex `
            -DdagrabOriginX $receiverProbeWindowResolvedDdagrabOriginX `
            -DdagrabOriginY $receiverProbeWindowResolvedDdagrabOriginY
          $receiverProbeWindowResolvedDdagrabOutputIndex =
            [int]$receiverProbeWindowRecording.DdagrabOutputIndex
          $receiverProbeWindowResolvedDdagrabOriginX =
            [int]$receiverProbeWindowRecording.DdagrabOriginX
          $receiverProbeWindowResolvedDdagrabOriginY =
            [int]$receiverProbeWindowRecording.DdagrabOriginY
          Start-Sleep -Seconds 1
          if ($receiverProbeWindowRecording.Process.HasExited) {
            Wait-RecordingProcess -Recording $receiverProbeWindowRecording -TimeoutSeconds 1
          }
        }
      }
    }
  }

  if ($StartBg3CameraRotation -and $externalReceiverProbeRequested) {
    if (-not $sourceOverrideRequested -or $null -eq $sourceOverrideProcess) {
      throw '-StartBg3CameraRotation requires -SourceProcessId so the BG3 process can be targeted.'
    }
    $bg3RotationStartJson = Join-Path $runDirectory 'bg3-camera-rotation-start.json'
    Invoke-Bg3CameraRotationHotkey `
      -WorkspaceRoot $workspaceRoot `
      -ProcessId $sourceOverrideProcess.Id `
      -Action 'Start' `
      -OutputPath $bg3RotationStartJson
    $bg3RotationStarted = $true
    Start-Sleep -Milliseconds 500
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $completePath) {
      break
    }
    if ($MaintainBg3FocusDuringRun -and
      $bg3RotationStarted -and
      $sourceOverrideRequested -and
      $null -ne $sourceOverrideProcess) {
      $now = Get-Date
      $shouldReassertFocus = $null -eq $bg3LastFocusReassertionAt -or
        ($now - $bg3LastFocusReassertionAt).TotalSeconds -ge $Bg3FocusIntervalSeconds
      if ($shouldReassertFocus) {
        $focusPath = Join-Path $runDirectory ("bg3-focus-reassert-{0:000}.json" -f ($bg3FocusReassertions.Count + 1))
        Invoke-Bg3CameraRotationHotkey `
          -WorkspaceRoot $workspaceRoot `
          -ProcessId $sourceOverrideProcess.Id `
          -Action 'Focus' `
          -OutputPath $focusPath
        [void]$bg3FocusReassertions.Add($focusPath)
        $bg3LastFocusReassertionAt = $now
      }
    }
    Start-Sleep -Seconds 1
  }

  if (-not (Test-Path -LiteralPath $completePath)) {
    if (Test-Path -LiteralPath $requestPath) {
      Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    }
    throw "Timed out waiting for stream-test automation completion after $TimeoutSeconds seconds."
  }

  if ($null -ne $recording) {
    Wait-RecordingProcess -Recording $recording -TimeoutSeconds ([Math]::Max(10, $RecordingSeconds + 15))
    $recording = $null
  }
  if ($null -ne $receiverProbeWindowRecording) {
    Wait-RecordingProcess `
      -Recording $receiverProbeWindowRecording `
      -TimeoutSeconds ([Math]::Max(10, $RecordingSeconds + 15))
    $receiverProbeWindowRecording = $null
  }

  $completion = Get-Content -Raw -LiteralPath $completePath | ConvertFrom-Json
  $completionCopy = Copy-IfExists $completePath $runDirectory
  $completionStatus = Get-JsonString $completion 'status'
  $completionError = Get-JsonString $completion 'error'
  $reportPath = Get-JsonString $completion 'reportPath'
  $reportJsonPath = Resolve-ReportJsonPath $reportPath $startedAt $streamTestDir
  $reportMdPath = if (-not [string]::IsNullOrWhiteSpace($reportJsonPath)) {
    [System.IO.Path]::ChangeExtension($reportJsonPath, '.md')
  } else {
    ''
  }
  $reportJsonCopy = Copy-IfExists $reportJsonPath $runDirectory
  $reportMdCopy = Copy-IfExists $reportMdPath $runDirectory

  if (-not [bool]$SkipSelfViewRecording) {
    $size = Get-VideoSize -FfprobeExe $ffprobe -VideoPath $tightVideoFull
    if ($size.Width -ne $CropWidth -or $size.Height -ne $CropHeight) {
      throw "Direct stream-tile recording produced $($size.Width)x$($size.Height); expected configured crop ${CropWidth}x${CropHeight}."
    }

    foreach ($second in @(2, 12, 22)) {
      if ($second -lt $RecordingSeconds) {
        Invoke-ToolProcess `
          -FileName $ffmpeg `
          -Arguments @(
            '-hide_banner',
            '-loglevel',
            'error',
            '-y',
            '-ss',
            "$second",
            '-i',
            $tightVideoFull,
            '-frames:v',
            '1',
            (Join-Path $runDirectory "stream-tile-frame-${second}s.png")
          ) `
          -StdoutPath '' `
          -StderrPath (Join-Path $runDirectory "stream-tile-frame-${second}s-ffmpeg.log")
      }
    }

    $tightVideo = Join-Path $runDirectory 'synthetic-live-call-stream-tight-active.mp4'
    Invoke-ToolProcess `
      -FileName $ffmpeg `
      -Arguments @(
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-ss',
        "$ActiveSegmentStartSeconds",
        '-t',
        "$ActiveSegmentSeconds",
        '-i',
        $tightVideoFull,
        '-pix_fmt',
        'yuv420p',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '18',
        $tightVideo
      ) `
      -StdoutPath '' `
      -StderrPath (Join-Path $runDirectory 'synthetic-live-call-stream-tight-active-ffmpeg.log')

    $visualDirectory = Join-Path $runDirectory 'visual-freshness-stream-tight'
    $visualLog = Join-Path $runDirectory 'visual-freshness-stream-tight.log'
    $measureScript = Join-Path $PSScriptRoot 'measure_visual_freshness.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $measureScript `
      -InputVideo $tightVideo `
      -OutputDirectory $visualDirectory `
      -SampleMode 'synthetic-live-call-stream-tight' `
      -SampleFps 30 `
      -MinUniqueFps $MinUniqueFps `
      -AsJson |
      Set-Content -LiteralPath $visualLog -Encoding UTF8
    $visualExitCode = $LASTEXITCODE

    $visualJsonPath = Join-Path $visualDirectory 'visual-freshness.json'
    $visual = if (Test-Path -LiteralPath $visualJsonPath) {
      Get-Content -Raw -LiteralPath $visualJsonPath | ConvertFrom-Json
    } else {
      $null
    }
  } else {
    $visualExitCode = 0
    $visual = [pscustomobject]@{
      status = 'skipped_self_view_recording'
      metrics = [pscustomobject]@{}
    }
  }
  $measureScript = Join-Path $PSScriptRoot 'measure_visual_freshness.ps1'

  if (-not [string]::IsNullOrWhiteSpace($receiverProbeWindowVideoFull) -and
      (Test-Path -LiteralPath $receiverProbeWindowVideoFull)) {
    foreach ($second in @(2, 12, 22)) {
      if ($second -lt $RecordingSeconds) {
        Invoke-ToolProcess `
          -FileName $ffmpeg `
          -Arguments @(
            '-hide_banner',
            '-loglevel',
            'error',
            '-y',
            '-ss',
            "$second",
            '-i',
            $receiverProbeWindowVideoFull,
            '-frames:v',
            '1',
            (Join-Path $runDirectory "receiver-probe-window-frame-${second}s.png")
          ) `
          -StdoutPath '' `
          -StderrPath (Join-Path $runDirectory "receiver-probe-window-frame-${second}s-ffmpeg.log")
      }
    }

    $receiverProbeWindowVideo = Join-Path $runDirectory 'receiver-probe-window-active.mp4'
    Invoke-ToolProcess `
      -FileName $ffmpeg `
      -Arguments @(
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-ss',
        "$receiverProbeWindowActiveSegmentStartSeconds",
        '-t',
        "$receiverProbeWindowActiveSegmentSeconds",
        '-i',
        $receiverProbeWindowVideoFull,
        '-pix_fmt',
        'yuv420p',
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '18',
        $receiverProbeWindowVideo
      ) `
      -StdoutPath '' `
      -StderrPath (Join-Path $runDirectory 'receiver-probe-window-active-ffmpeg.log')

    $receiverProbeWindowVisualDirectory =
      Join-Path $runDirectory 'visual-freshness-receiver-probe-window'
    $receiverProbeWindowVisualReportPath =
      Join-Path $receiverProbeWindowVisualDirectory 'visual-freshness.md'
    $receiverProbeWindowVisualLog =
      Join-Path $runDirectory 'visual-freshness-receiver-probe-window.log'
    $receiverProbeMeasureArgs = @(
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      $measureScript,
      '-InputVideo',
      $receiverProbeWindowVideo,
      '-OutputDirectory',
      $receiverProbeWindowVisualDirectory,
      '-SampleMode',
      'receiver-probe-window',
      '-SampleFps',
      '30',
      '-MinUniqueFps',
      $MinUniqueFps.ToString([Globalization.CultureInfo]::InvariantCulture)
    )
    if ($ReceiverProbeVisualFrameMarker) {
      $receiverProbeMeasureArgs += '-ExcludeReceiverProbeMarkerRegion'
    }
    if ($SourceFrameContentMarker) {
      $receiverProbeMeasureArgs += @(
        '-ScaleWidth',
        '160',
        '-ScaleHeight',
        '90',
        '-DecodeSourceFrameMarker',
        '-ExcludeSourceFrameMarkerRegion',
        '-SourceFrameMarkerOffsetX',
        '4',
        '-SourceFrameMarkerOffsetY',
        '4'
      )
    }
    $receiverProbeMeasureArgs += '-AsJson'

    & powershell.exe @receiverProbeMeasureArgs |
      Set-Content -LiteralPath $receiverProbeWindowVisualLog -Encoding UTF8
    $receiverProbeWindowVisualExitCode = $LASTEXITCODE

    $receiverProbeWindowVisualJsonPath =
      Join-Path $receiverProbeWindowVisualDirectory 'visual-freshness.json'
    $receiverProbeWindowVisual = if (Test-Path -LiteralPath $receiverProbeWindowVisualJsonPath) {
      Get-Content -Raw -LiteralPath $receiverProbeWindowVisualJsonPath | ConvertFrom-Json
    } else {
      $null
    }
    $receiverProbeWindowVisualStatus =
      Get-JsonString $receiverProbeWindowVisual 'status'
    $receiverProbeWindowUniqueFps =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'uniqueFps')
    $receiverProbeWindowLongestStaleMs =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'longestStaleMs')
    $receiverProbeWindowExactUniqueFps =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'exactUniqueFps')
    $receiverProbeWindowExactDuplicateFrames =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'exactDuplicateFrames')
    $receiverProbeWindowExactLongestStaleMs =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'exactLongestStaleMs')
    $receiverProbeWindowSourceMarkerDecodedFrames =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'sourceFrameMarker', 'decodedFrames')
    $receiverProbeWindowSourceMarkerMissingFrames =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'sourceFrameMarker', 'missingFrames')
    $receiverProbeWindowSourceMarkerUniqueFps =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'sourceFrameMarker', 'uniqueFps')
    $receiverProbeWindowSourceMarkerLongestStaleMs =
      Get-NestedJsonProperty $receiverProbeWindowVisual @('metrics', 'sourceFrameMarker', 'longestStaleMs')
    $receiverProbeWindowSourceMarkerAvailable =
      $SourceFrameContentMarker -and
      $receiverProbeWindowSourceMarkerDecodedFrames -ne $null -and
      [int]$receiverProbeWindowSourceMarkerDecodedFrames -gt 0
    $receiverProbeWindowSourceMarkerPass =
      $receiverProbeWindowSourceMarkerAvailable -and
      $receiverProbeWindowSourceMarkerUniqueFps -ne $null -and
      [double]$receiverProbeWindowSourceMarkerUniqueFps -ge $MinUniqueFps
  }

  $report = if (-not [string]::IsNullOrWhiteSpace($reportJsonPath)) {
    Get-Content -Raw -LiteralPath $reportJsonPath | ConvertFrom-Json
  } else {
    $null
  }
  $primaryResult = $null
  $presetResults = Get-JsonProperty $report 'presetResults'
  if ($null -ne $presetResults) {
    $primaryResult = @($presetResults) | Select-Object -First 1
  }
  $summary = Get-JsonProperty $primaryResult 'summary'
  $native = Get-JsonProperty $primaryResult 'nativeDiagnostics'
  if ($null -eq $native) {
    $native = Get-JsonProperty $summary 'nativeDiagnostics'
  }
  $rawSender = Get-JsonProperty $native 'webrtcRawSenderBoundary'
  $broadcaster = Get-JsonProperty $rawSender 'videoBroadcaster'
  $score = Get-JsonProperty $primaryResult 'score'
  $bottleneck = Get-JsonProperty $score 'bottleneck'

  $uniqueFps = Get-NestedJsonProperty $visual @('metrics', 'uniqueFps')
  $longestStaleMs = Get-NestedJsonProperty $visual @('metrics', 'longestStaleMs')
  $visualStatus = Get-JsonString $visual 'status'
  $averageCaptureFps = Get-JsonDouble $summary 'averageCaptureFps'
  $averageEncodeFps = Get-JsonDouble $summary 'averageEncodeFps'
  $averageSendFps = Get-JsonDouble $summary 'averageSendFps'
  $refreshed = Get-JsonInt $broadcaster 'inactiveNativeSinksRefreshed'
  $bypassed = Get-JsonInt $broadcaster 'inactiveNativeSinksBypassed'
  $broadcasterSamples = Get-JsonInt $broadcaster 'samples'
  $bottleneckLabel = Get-JsonString $bottleneck 'label'
  $sourceMode = Get-JsonString $native 'gameCaptureSourceMode'
  $videoStreamEncoder = Get-JsonProperty $rawSender 'videoStreamEncoder'
  $activeProcessingSplit =
    Get-JsonProperty $videoStreamEncoder 'activeProcessingSplit'
  $hostLoad = Get-JsonProperty $report 'hostLoad'
  $hostSystemCpu = Get-JsonProperty $hostLoad 'systemCpuPercent'
  $hostTargetCpu = Get-JsonProperty $hostLoad 'targetCpuPercent'
  $requestedWidth = Get-JsonInt $summary 'requestedWidth'
  $requestedHeight = Get-JsonInt $summary 'requestedHeight'
  $senderSourceToSubmitAverageMs =
    Get-JsonDouble $native 'averageGameCaptureSourceToSubmitMs'
  $senderSourceToSubmitMaxMs =
    Get-JsonDouble $native 'maxGameCaptureSourceToSubmitMs'
  $senderDeliveryWallAverageMs =
    Get-JsonDouble $native 'averageGameCaptureDeliveryWallDeltaMs'
  $senderDeliveryWallMaxMs =
    Get-JsonDouble $native 'maxGameCaptureDeliveryWallDeltaMs'
  $senderDeliveryWallOver2xFrames =
    Get-JsonInt $native 'gameCaptureDeliveryWallOver2xFrames'
  $senderDeliveryWallOver3xFrames =
    Get-JsonInt $native 'gameCaptureDeliveryWallOver3xFrames'
  $senderSourceQpcMaxMs =
    Get-JsonDouble $native 'maxGameCaptureSourceQpcDeltaMs'
  $senderTimestampDeltaMaxMs =
    Get-JsonDouble $native 'maxGameCaptureTimestampDeltaMs'
  $senderDeliveryOnFrameCallAverageMs =
    Get-JsonDouble $native 'averageGameCaptureDeliveryOnFrameCallMs'
  $senderDeliveryOnFrameCallMaxMs =
    Get-JsonDouble $native 'maxGameCaptureDeliveryOnFrameCallMs'
  $senderNativeBltToReadyAverageMs =
    Get-JsonDouble $native 'averageGameCaptureNativeNv12VideoProcessorBltToReadyMs'
  $senderNativeBltToReadyMaxMs =
    Get-JsonDouble $native 'maxGameCaptureNativeNv12VideoProcessorBltToReadyMs'
  $senderNativeBltSubmitMaxMs =
    Get-JsonDouble $native 'maxGameCaptureNativeNv12VideoProcessorBltSubmitMs'
  $senderNativeConvertMaxMs =
    Get-JsonDouble $native 'maxGameCaptureNativeNv12ConvertMs'
  $senderSourceToReadbackReadyMaxMs =
    Get-JsonDouble $native 'maxGameCaptureSourceToReadbackReadyMs'
  $senderReadbackQueueToMapMaxMs =
    Get-JsonDouble $native 'maxGameCaptureReadbackQueueToMapMs'
  $senderReadbackLatencyAverageMs =
    Get-JsonDouble $native 'averageGameCaptureReadbackLatencyMs'
  $senderNativeNv12NotReadyPolls =
    Get-JsonInt $native 'gameCaptureNativeNv12NotReadyPolls'
  $senderNativeNv12ReadyDroppedFrames =
    Get-JsonInt $native 'gameCaptureNativeNv12ReadyDroppedFrames'
  $senderNativeNv12OverwrittenFrames =
    Get-JsonInt $native 'gameCaptureNativeNv12OverwrittenFrames'
  $senderNativeNv12SubmittedFrames =
    Get-JsonInt $native 'gameCaptureNativeNv12SubmittedFrames'
  $senderNativeNv12Suspended =
    Get-JsonProperty $native 'gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure'
  $senderNativeNv12BackpressureMaxMs =
    Get-JsonDouble $native 'gameCaptureNativeNv12OnFrameBackpressureMaxMs'
  $senderNativeNv12DisabledReason =
    Get-JsonString $native 'gameCaptureNativeNv12HandoffDisabledReason'
  $senderVideoStreamEncoderPostToOnFrameAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averagePostToOnFrameMs'
  $senderVideoStreamEncoderPostToOnFrameMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxPostToOnFrameMs'
  $senderVideoStreamEncoderOnFrameAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageOnFrameMs'
  $senderVideoStreamEncoderOnFrameMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxOnFrameMs'
  $senderVideoStreamEncoderMaybeEncodeAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybeEncodeMs'
  $senderVideoStreamEncoderMaybeEncodeMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybeEncodeMs'
  $senderVideoStreamEncoderMaybePreEncodeAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybePreEncodeMs'
  $senderVideoStreamEncoderMaybePreEncodeMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybePreEncodeMs'
  $senderVideoStreamEncoderMaybeEncodeCallAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybeEncodeCallMs'
  $senderVideoStreamEncoderMaybeEncodeCallMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybeEncodeCallMs'
  $senderVideoStreamEncoderMaybeParameterUpdateAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybeParameterUpdateMs'
  $senderVideoStreamEncoderMaybeParameterUpdateMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybeParameterUpdateMs'
  $senderVideoStreamEncoderMaybeReconfigureAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybeReconfigureMs'
  $senderVideoStreamEncoderMaybeReconfigureMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybeReconfigureMs'
  $senderVideoStreamEncoderPendingReconfigureSignals =
    Get-JsonInt $videoStreamEncoder 'pendingReconfigureSignals'
  $senderVideoStreamEncoderPendingReconfigureConfigureEncoder =
    Get-JsonInt $videoStreamEncoder 'pendingReconfigureConfigureEncoder'
  $senderVideoStreamEncoderPendingReconfigureFrameInfoChange =
    Get-JsonInt $videoStreamEncoder 'pendingReconfigureFrameInfoChange'
  $senderVideoStreamEncoderPendingReconfigureSourceRestriction =
    Get-JsonInt $videoStreamEncoder 'pendingReconfigureSourceRestriction'
  $senderVideoStreamEncoderPendingReconfigureUnknown =
    Get-JsonInt $videoStreamEncoder 'pendingReconfigureUnknown'
  $senderVideoStreamEncoderPendingReconfigureLastReason =
    Get-JsonString $videoStreamEncoder 'pendingReconfigureLastReason'
  $senderVideoStreamEncoderMaybeRateUpdateAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageMaybeRateUpdateMs'
  $senderVideoStreamEncoderMaybeRateUpdateMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxMaybeRateUpdateMs'
  $senderVideoStreamEncoderEncodeFrameAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageEncodeFrameMs'
  $senderVideoStreamEncoderEncodeFrameMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxEncodeFrameMs'
  $senderVideoEncoderEncodeAverageMs =
    Get-JsonDouble $videoStreamEncoder 'averageVideoEncoderEncodeMs'
  $senderVideoEncoderEncodeMaxMs =
    Get-JsonDouble $videoStreamEncoder 'maxVideoEncoderEncodeMs'
  $senderMfEncoderAverageTotalMs =
    Get-JsonDouble $native 'averageEncoderTotalMs'
  $senderMfEncoderMaxTotalMs =
    Get-JsonDouble $native 'maxEncoderTotalMs'
  $senderMfEncoderAverageProcessInputMs =
    Get-JsonDouble $native 'averageEncoderProcessInputMs'
  $senderMfEncoderMaxProcessInputMs =
    Get-JsonDouble $native 'maxEncoderProcessInputMs'
  $senderMfEncoderAverageProcessOutputMs =
    Get-JsonDouble $native 'averageEncoderProcessOutputMs'
  $senderMfEncoderMaxProcessOutputMs =
    Get-JsonDouble $native 'maxEncoderProcessOutputMs'
  $senderMfEncoderAverageEncodedCallbackMs =
    Get-JsonDouble $native 'averageEncoderEncodedCallbackMs'
  $senderMfEncoderMaxEncodedCallbackMs =
    Get-JsonDouble $native 'maxEncoderEncodedCallbackMs'
  $senderMfEncoderOutputFrames =
    Get-JsonInt $native 'encoderOutputFrames'
  $senderMfEncoderProcessInputSamples =
    Get-JsonInt $native 'encoderProcessInputSamples'
  $senderMfEncoderProcessOutputSamples =
    Get-JsonInt $native 'encoderProcessOutputSamples'
  $senderActiveTaskPostedToTaskStartsAverageMs =
    Get-JsonDouble $activeProcessingSplit 'task_posted_to_task_starts_ms'
  $senderActiveTaskPostedToTaskStartsMaxMs =
    Get-JsonDouble $activeProcessingSplit 'task_posted_to_task_starts_max_ms'
  $senderActiveTaskStartsToAdaptationCompleteAverageMs =
    Get-JsonDouble $activeProcessingSplit 'task_starts_to_adaptation_complete_ms'
  $senderActiveTaskStartsToAdaptationCompleteMaxMs =
    Get-JsonDouble $activeProcessingSplit 'task_starts_to_adaptation_complete_max_ms'
  $senderActiveAdaptationCompleteToVseEntryAverageMs =
    Get-JsonDouble $activeProcessingSplit 'adaptation_complete_to_vse_entry_ms'
  $senderActiveAdaptationCompleteToVseEntryMaxMs =
    Get-JsonDouble $activeProcessingSplit 'adaptation_complete_to_vse_entry_max_ms'
  $senderActiveVseEntryToEncoderTaskPostedAverageMs =
    Get-JsonDouble $activeProcessingSplit 'vse_entry_to_encoder_task_posted_ms'
  $senderActiveVseEntryToEncoderTaskPostedMaxMs =
    Get-JsonDouble $activeProcessingSplit 'vse_entry_to_encoder_task_posted_max_ms'
  $senderActiveEncoderTaskPostedToStartedAverageMs =
    Get-JsonDouble $activeProcessingSplit 'encoder_task_posted_to_started_ms'
  $senderActiveEncoderTaskPostedToStartedMaxMs =
    Get-JsonDouble $activeProcessingSplit 'encoder_task_posted_to_started_max_ms'
  $senderActiveEncoderTaskStartsToEncodeEntryAverageMs =
    Get-JsonDouble $activeProcessingSplit 'encoder_task_starts_to_video_encoder_encode_entry_ms'
  $senderActiveEncoderTaskStartsToEncodeEntryMaxMs =
    Get-JsonDouble $activeProcessingSplit 'encoder_task_starts_to_video_encoder_encode_entry_max_ms'
  $senderActiveEncodeEntryToReturnAverageMs =
    Get-JsonDouble $activeProcessingSplit 'encode_entry_to_encode_return_ms'
  $senderActiveEncodeEntryToReturnMaxMs =
    Get-JsonDouble $activeProcessingSplit 'encode_entry_to_encode_return_max_ms'
  $senderVideoStreamEncoderQueueDrops =
    Get-JsonInt $videoStreamEncoder 'encoderQueueDrops'
  $senderVideoStreamEncoderOverloadDrops =
    Get-JsonInt $videoStreamEncoder 'queueOverloadDrops'
  $hostSystemCpuAverage =
    Get-JsonDouble $hostSystemCpu 'average'
  $hostSystemCpuMaximum =
    Get-JsonDouble $hostSystemCpu 'maximum'
  $hostTargetCpuAverage =
    Get-JsonDouble $hostTargetCpu 'average'
  $hostTargetCpuMaximum =
    Get-JsonDouble $hostTargetCpu 'maximum'

  $receiverProbeEventsPath = if ($ReceiverProbeEnabled -and $externalReceiverProbeRequested) {
    Join-Path $receiverProbeRunDirectory 'events.jsonl'
  } elseif ($ReceiverProbeEnabled) {
    Join-Path $runDirectory 'in-process-receiver-events.jsonl'
  } else {
    ''
  }
  $receiverProbeStatus = ''
  $receiverProbeBlockingReason = ''
  $receiverProbeExitCode = $null
  $receiverProbeSummary = $null
  $receiverProbeRuntimeFrameDiagnosticsMode = $ReceiverProbeFrameDiagnosticsMode
  $receiverDecodeUniqueFps = $null
  $receiverRenderUniqueFps = $null
  $receiverDecodeSourceFrameMarkerUniqueFps = $null
  $receiverRenderSourceFrameMarkerUniqueFps = $null
  $receiverSourceFrameMarkerUniqueFps = $null
  $receiverSourceFrameMarkerLongestStaleMs = $null
  $receiverSourceFrameMarkerDecodedFrames = $null
  $localPreviewUniqueFps = $null
  $receiverStatsFps = $null
  $receiverReceivedFps = $null
  $receiverReceivedFpsP50 = $null
  $receiverReceivedFpsAverage = $null
  $receiverDecodedFps = $null
  $receiverDecodedFpsP50 = $null
  $receiverDecodedFpsAverage = $null
  $receiverRenderedFps = $null
  $receiverRenderedFpsP50 = $null
  $receiverRenderedFpsAverage = $null
  $receiverEffectiveStatsFps = $null
  $receiverStatsFpsGateSource = 'missing'
  $receiverStatsSampleWindowMs = $null
  $receiverFramePresentationP95GapMs = $null
  $receiverFramePresentationP95GapP50Ms = $null
  $receiverFramePresentationP95GapAverageMs = $null
  $receiverEffectiveFramePresentationP95GapMs = $null
  $receiverPresentationGateSource = 'missing'
  $receiverFramePresentationMaxGapMs = $null
  $receiverInboundBitrateBps = $null
  $receiverAverageQp = $null
  $receiverSubscribedQuality = ''
  $receiverSimulcastLayer = ''
  $receiverReceivedWidth = $null
  $receiverReceivedHeight = $null
  $receiverDecodedWidth = $null
  $receiverDecodedHeight = $null
  $receiverRenderedWidth = $null
  $receiverRenderedHeight = $null
  $receiverRendererAttached = $null
  $receiverRendererVisible = $null
  $receiverUpscalingLowerLayerSuspected = $null
  $receiverAdaptiveStreamLowLayerSuspected = $null
  $receiverPliCount = $null
  $receiverFirCount = $null
  $receiverNackCount = $null
  $receiverDroppedOrReplacedTextureUpdates = $null
  $receiverDecodeFreshnessSource = ''
  $receiverRenderFreshnessSource = ''
  $localPreviewFreshnessSource = ''
  $receiverLatestTargetStage = ''
  $receiverStageSource = ''
  $receiverDeepestObservedStage = ''
  $receiverRemoteDecodeEventCount = $null
  $receiverRemoteRendererCallbackEventCount = $null
  $receiverRemoteTextureReadyEventCount = $null
  $receiverRemoteUiPaintEventCount = $null
  $receiverRemoteScreenPresentEventCount = $null
  $receiverStageObservedGapMs = $null
  $receiverRendererCallbackToStageMs = $null
  $receiverWindowFlutterFrameCount = $null
  $receiverWindowFlutterFrameGapP95Ms = $null
  $receiverWindowFlutterFrameGapMaxMs = $null
  $receiverWindowFlutterFrameGapsOver50Ms = $null
  $receiverWindowFlutterFrameGapsOver100Ms = $null
  $receiverSourceLineageStats = [ordered]@{
    eventCount = 0
    sourceLineageEventCount = 0
    frameIdEventCount = 0
    previousFrameIdEventCount = 0
    sourceFrameMarkerIdEventCount = 0
    sourceQpcEventCount = 0
    stageQpcEventCount = 0
    sourceFrameIdAvailable = $false
    sourceLineageAvailable = $false
    reason = 'not_measured'
  }
  $receiverSourceLineageEventCount = 0
  $receiverSourceFrameIdEventCount = 0
  $receiverPreviousFrameIdEventCount = 0
  $receiverSourceFrameMarkerIdEventCount = 0
  $receiverSourceQpcEventCount = 0
  $receiverStageQpcEventCount = 0
  $receiverSourceFrameIdAvailable = $false
  $receiverSourceLineageAvailable = $false
  $receiverSourceLineageReason = 'not_measured'
  if ($ReceiverProbeEnabled) {
    if ($externalReceiverProbeRequested) {
      if ($null -eq $externalReceiverProbeProcess) {
        $receiverProbeExitCode = 6
        $receiverProbeStatus = 'blocked_external_receiver_probe_not_started'
        $receiverProbeBlockingReason = 'External receiver probe process was not started.'
      } else {
        $externalWaitTimeoutSeconds =
          [Math]::Max(
            [Math]::Max(60, $DurationSeconds + $WarmupSeconds + 120),
            $externalReceiverProbeTimeoutSeconds + 15
          )
        $externalCompleted = $false
        $externalProcessExitCode = $null
        try {
          Wait-Process -Id $externalReceiverProbeProcess.Id `
            -Timeout $externalWaitTimeoutSeconds `
            -ErrorAction Stop
          $externalCompleted = $true
          $externalReceiverProbeProcess.Refresh()
          $externalProcessExitCode = $externalReceiverProbeProcess.ExitCode
        } catch {
          $externalCompleted = $false
        }

        $externalReportExists = Test-Path -LiteralPath $receiverProbeReportPath
        $externalSummaryExists = Test-Path -LiteralPath $receiverProbeSummaryPath
        if (-not $externalCompleted -and
            (-not $externalReportExists) -and
            (-not $externalSummaryExists)) {
          Stop-ProcessTree -RootProcessId $externalReceiverProbeProcess.Id
          $receiverProbeExitCode = 6
          $receiverProbeStatus = 'blocked_external_receiver_probe_timeout'
          $receiverProbeBlockingReason =
            "External receiver probe exceeded wait timeout of $externalWaitTimeoutSeconds seconds."
        } else {
          if (-not $externalCompleted) {
            Stop-ProcessTree -RootProcessId $externalReceiverProbeProcess.Id
          }
          if (Test-Path -LiteralPath $receiverProbeSummaryPath) {
            $receiverProbeSummary = Get-Content -Raw -LiteralPath $receiverProbeSummaryPath |
              ConvertFrom-Json
          }
          if (Test-Path -LiteralPath $receiverProbeReportPath) {
            $trueReceiverReport = Get-Content -Raw -LiteralPath $receiverProbeReportPath |
              ConvertFrom-Json
            $receiverProbeStatus = Get-JsonString $trueReceiverReport 'status'
            $receiverProbeBlockingReason =
              Get-JsonString $trueReceiverReport 'blocking_reason'
            $reportedFrameDiagnosticsMode =
              Get-JsonString $trueReceiverReport 'frame_diagnostics_mode'
            if (-not [string]::IsNullOrWhiteSpace($reportedFrameDiagnosticsMode)) {
              $receiverProbeRuntimeFrameDiagnosticsMode = $reportedFrameDiagnosticsMode
            }
            if ($receiverProbeStatus -eq 'completed_external_receiver_probe_events' -or
                $receiverProbeStatus -eq 'completed_external_receiver_probe_stats_only_events') {
              $receiverProbeExitCode = 0
            } elseif ($null -ne $externalProcessExitCode) {
              $receiverProbeExitCode = $externalProcessExitCode
            } else {
              $receiverProbeExitCode = 6
            }
          } elseif ($null -ne $receiverProbeSummary) {
            $receiverProbeStatus = Get-JsonString $receiverProbeSummary 'status'
            $receiverProbeBlockingReason =
              Get-JsonString $receiverProbeSummary 'blocking_reason'
            $reportedFrameDiagnosticsMode =
              Get-JsonString $receiverProbeSummary 'frame_diagnostics_mode'
            if (-not [string]::IsNullOrWhiteSpace($reportedFrameDiagnosticsMode)) {
              $receiverProbeRuntimeFrameDiagnosticsMode = $reportedFrameDiagnosticsMode
            }
            if ($receiverProbeStatus -eq 'completed_receiver_probe_events' -or
                $receiverProbeStatus -eq 'completed_stats_only_receiver_probe_events') {
              $receiverProbeExitCode = 0
            } elseif ($null -ne $externalProcessExitCode) {
              $receiverProbeExitCode = $externalProcessExitCode
            } else {
              $receiverProbeExitCode = 6
            }
          } else {
            $receiverProbeStatus = 'inconclusive_missing_receiver_summary'
            $receiverProbeBlockingReason =
              'External receiver probe exited without receiver-summary.json.'
            $receiverProbeExitCode = if ($null -ne $externalProcessExitCode) {
              $externalProcessExitCode
            } else {
              6
            }
          }
        }
      }
    } else {
      if (Test-Path -LiteralPath $receiverProbeEventsPath) {
        Remove-Item -LiteralPath $receiverProbeEventsPath -Force
      }
      $receiverEvents = @()
      $receiverProbeAppResult = $null
      foreach ($preset in @($presetResults)) {
        $probe = Get-JsonProperty $preset 'receiverProbe'
        if ($null -ne $probe -and $null -eq $receiverProbeAppResult) {
          $receiverProbeAppResult = $probe
        }
        $probeEvents = Get-JsonProperty $probe 'events'
        if ($null -ne $probeEvents) {
          $receiverEvents += @($probeEvents)
        }
      }
      foreach ($event in $receiverEvents) {
        ($event | ConvertTo-Json -Depth 12 -Compress) |
          Add-Content -LiteralPath $receiverProbeEventsPath -Encoding UTF8
      }

      $receiverProbeRunnerMode = if ($ReceiverProbeMode -eq 'render') {
        'InProcessRender'
      } elseif ($ReceiverProbeMode -eq 'local-preview') {
        'InProcessLocalPreview'
      } else {
        'InProcessDecodeOnly'
      }
      $appProbeStatus = Get-JsonString $receiverProbeAppResult 'status'
      $appProbeBlockingReason = Get-JsonString $receiverProbeAppResult 'blockingReason'
      if ([string]::IsNullOrWhiteSpace($appProbeBlockingReason)) {
        $appProbeBlockingReason = Get-JsonString $receiverProbeAppResult 'error'
      }

      if ($receiverEvents.Count -eq 0) {
        New-Item -ItemType File -Force -Path $receiverProbeEventsPath | Out-Null
      }

      $receiverProbeSummarySource = 'stream_test_receiver_probe_result'
      $receiverProbeCompletedStatus = if ($ReceiverProbeMode -eq 'local-preview') {
        'completed_local_preview_probe_events'
      } else {
        'completed_receiver_probe_events'
      }
      $shouldWriteReceiverProbeBlocker = $receiverEvents.Count -eq 0 -and
        -not [string]::IsNullOrWhiteSpace($appProbeStatus) -and
        $appProbeStatus -ne $receiverProbeCompletedStatus
      if ($receiverEvents.Count -eq 0 -and -not $shouldWriteReceiverProbeBlocker) {
        $shouldWriteReceiverProbeBlocker = $true
        $receiverProbeSummarySource = 'stream_test_completion_result'
        $receiverProbeStatus = if ($completionStatus -ne 'completed' -or
            -not [string]::IsNullOrWhiteSpace($completionError)) {
          'blocked_stream_test_automation_failed_no_receiver_events'
        } else {
          'inconclusive_no_receiver_probe_events'
        }
        $receiverProbeBlockingReason = if (-not [string]::IsNullOrWhiteSpace($completionError)) {
          $completionError
        } else {
          'The in-process receiver probe did not produce events.'
        }
      }

      if ($shouldWriteReceiverProbeBlocker) {
        New-Item -ItemType Directory -Force -Path $receiverProbeRunDirectory | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($appProbeStatus) -and
            $appProbeStatus -ne $receiverProbeCompletedStatus) {
          $receiverProbeStatus = $appProbeStatus
          $receiverProbeBlockingReason = if ([string]::IsNullOrWhiteSpace($appProbeBlockingReason)) {
            'The in-process receiver probe did not produce events.'
          } else {
            $appProbeBlockingReason
          }
        }
        $receiverProbeExitCode = 6
        $receiverProbeSummary = [ordered]@{
          run_id = $receiverProbeRunId
          mode = $receiverProbeRunnerMode
          status = $receiverProbeStatus
          blocking_reason = $receiverProbeBlockingReason
          in_process_events = $receiverProbeEventsPath
          min_unique_fps = $MinUniqueFps
          source = $receiverProbeSummarySource
          event_count = 0
          local_preview_event_count = 0
          remote_decode_event_count = 0
          remote_renderer_callback_lane_event_count = 0
        }
        $receiverProbeSummary |
          ConvertTo-Json -Depth 12 |
          Set-Content -LiteralPath $receiverProbeSummaryPath -Encoding UTF8
        @(
          "# In-Process Receiver Probe Summary"
          ''
          "- Status: $receiverProbeStatus"
          "- Blocking reason: $receiverProbeBlockingReason"
          "- Events: 0"
          "- Source: $receiverProbeSummarySource"
        ) | Set-Content -LiteralPath (Join-Path $receiverProbeRunDirectory 'receiver-summary.md') -Encoding UTF8
      } else {
        $trueReceiverRunner = Join-Path $PSScriptRoot 'run_true_receiver_test.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $trueReceiverRunner `
          -Mode $receiverProbeRunnerMode `
          -RunId $receiverProbeRunId `
          -DurationSeconds $DurationSeconds `
          -ExpectedWidth $PublicationHandoffMaxWidth `
          -ExpectedHeight $PublicationHandoffMaxHeight `
          -ExpectedFps $PublicationHandoffTargetFps `
          -OutputRoot $receiverProbeOutputRoot `
          -InProcessEventsPath $receiverProbeEventsPath `
          -FrameDiagnosticsMode $ReceiverProbeFrameDiagnosticsMode `
          -MinUniqueFps $MinUniqueFps
        $receiverProbeExitCode = $LASTEXITCODE
        if (Test-Path -LiteralPath $receiverProbeSummaryPath) {
          $receiverProbeSummary = Get-Content -Raw -LiteralPath $receiverProbeSummaryPath |
            ConvertFrom-Json
          $receiverProbeStatus = Get-JsonString $receiverProbeSummary 'status'
          $receiverProbeBlockingReason =
            Get-JsonString $receiverProbeSummary 'blocking_reason'
          $reportedFrameDiagnosticsMode =
            Get-JsonString $receiverProbeSummary 'frame_diagnostics_mode'
          if (-not [string]::IsNullOrWhiteSpace($reportedFrameDiagnosticsMode)) {
            $receiverProbeRuntimeFrameDiagnosticsMode = $reportedFrameDiagnosticsMode
          }
        }
      }
    }

    if ($null -ne $receiverProbeSummary) {
      $receiverDecodeUniqueFps = Get-JsonDouble $receiverProbeSummary 'decode_unique_fps'
      $receiverRenderUniqueFps = Get-JsonDouble $receiverProbeSummary 'render_unique_fps'
      $receiverDecodeSourceFrameMarkerUniqueFps =
        Get-JsonDouble $receiverProbeSummary 'decode_source_frame_marker_unique_fps'
      $receiverRenderSourceFrameMarkerUniqueFps =
        Get-JsonDouble $receiverProbeSummary 'render_source_frame_marker_unique_fps'
      $receiverSourceFrameMarkerUniqueFps =
        Get-JsonDouble $receiverProbeSummary 'source_frame_marker_unique_fps'
      $receiverSourceFrameMarkerLongestStaleMs =
        Get-JsonDouble $receiverProbeSummary 'source_frame_marker_longest_stale_run_ms'
      $receiverSourceFrameMarkerDecodedFrames =
        Get-JsonInt $receiverProbeSummary 'source_frame_marker_decoded_frames'
      $localPreviewUniqueFps = Get-JsonDouble $receiverProbeSummary 'local_preview_unique_fps'
      $receiverStatsFps = Get-JsonDouble $receiverProbeSummary 'receiver_fps'
      $receiverReceivedFps = Get-JsonDouble $receiverProbeSummary 'received_fps'
      $receiverReceivedFpsP50 = Get-JsonDouble $receiverProbeSummary 'received_fps_p50'
      $receiverReceivedFpsAverage = Get-JsonDouble $receiverProbeSummary 'received_fps_average'
      $receiverDecodedFps = Get-JsonDouble $receiverProbeSummary 'decoded_fps'
      $receiverDecodedFpsP50 = Get-JsonDouble $receiverProbeSummary 'decoded_fps_p50'
      $receiverDecodedFpsAverage = Get-JsonDouble $receiverProbeSummary 'decoded_fps_average'
      $receiverRenderedFps = Get-JsonDouble $receiverProbeSummary 'rendered_fps'
      $receiverRenderedFpsP50 = Get-JsonDouble $receiverProbeSummary 'rendered_fps_p50'
      $receiverRenderedFpsAverage = Get-JsonDouble $receiverProbeSummary 'rendered_fps_average'
      $receiverStatsSampleWindowMs =
        Get-JsonDouble $receiverProbeSummary 'receiver_stats_sample_window_ms'
      $receiverFramePresentationP95GapMs =
        Get-JsonDouble $receiverProbeSummary 'frame_presentation_p95_gap_ms'
      $receiverFramePresentationP95GapP50Ms =
        Get-JsonDouble $receiverProbeSummary 'frame_presentation_p95_gap_ms_p50'
      $receiverFramePresentationP95GapAverageMs =
        Get-JsonDouble $receiverProbeSummary 'frame_presentation_p95_gap_ms_average'
      $receiverFramePresentationMaxGapMs =
        Get-JsonDouble $receiverProbeSummary 'frame_presentation_max_gap_ms'
      $receiverInboundBitrateBps = Get-JsonInt $receiverProbeSummary 'inbound_bitrate_bps'
      $receiverAverageQp = Get-JsonDouble $receiverProbeSummary 'average_qp'
      $receiverSubscribedQuality = Get-JsonString $receiverProbeSummary 'subscribed_quality'
      $receiverSimulcastLayer = Get-JsonString $receiverProbeSummary 'simulcast_layer'
      $receiverReceivedWidth = Get-JsonInt $receiverProbeSummary 'received_width'
      $receiverReceivedHeight = Get-JsonInt $receiverProbeSummary 'received_height'
      $receiverDecodedWidth = Get-JsonInt $receiverProbeSummary 'decoded_width'
      $receiverDecodedHeight = Get-JsonInt $receiverProbeSummary 'decoded_height'
      $receiverRenderedWidth = Get-JsonInt $receiverProbeSummary 'rendered_width'
      $receiverRenderedHeight = Get-JsonInt $receiverProbeSummary 'rendered_height'
      $receiverDecodeFreshnessSource = Get-JsonString $receiverProbeSummary 'decode_freshness_source'
      $receiverRenderFreshnessSource = Get-JsonString $receiverProbeSummary 'render_freshness_source'
      $localPreviewFreshnessSource = Get-JsonString $receiverProbeSummary 'local_preview_freshness_source'
      $receiverUpscalingLowerLayerSuspected =
        Get-JsonProperty $receiverProbeSummary 'upscaling_lower_layer_suspected'
      $receiverAdaptiveStreamLowLayerSuspected =
        Get-JsonProperty $receiverProbeSummary 'adaptive_stream_low_layer_suspected'
      $receiverPliCount = Get-JsonInt $receiverProbeSummary 'pli_count'
      $receiverFirCount = Get-JsonInt $receiverProbeSummary 'fir_count'
      $receiverNackCount = Get-JsonInt $receiverProbeSummary 'nack_count'
      $receiverDroppedOrReplacedTextureUpdates =
        Get-JsonInt $receiverProbeSummary 'dropped_or_replaced_texture_updates'
      $receiverLatestTargetStage =
        Get-JsonString $receiverProbeSummary 'latest_target_stage'
      $receiverStageSource =
        Get-JsonString $receiverProbeSummary 'stage_source'
      $receiverRemoteDecodeEventCount =
        Get-JsonInt $receiverProbeSummary 'remote_decode_event_count'
      $receiverRemoteRendererCallbackEventCount =
        Get-JsonInt $receiverProbeSummary 'remote_renderer_callback_event_count'
      $receiverRemoteTextureReadyEventCount =
        Get-JsonInt $receiverProbeSummary 'remote_texture_ready_event_count'
      $receiverRemoteUiPaintEventCount =
        Get-JsonInt $receiverProbeSummary 'remote_ui_paint_event_count'
      $receiverRemoteScreenPresentEventCount =
        Get-JsonInt $receiverProbeSummary 'remote_screen_present_event_count'
      $receiverDeepestObservedStage = Get-DeepestReceiverPresentationStage `
        -RemoteDecodeEventCount $receiverRemoteDecodeEventCount `
        -RemoteRendererCallbackEventCount $receiverRemoteRendererCallbackEventCount `
        -RemoteTextureReadyEventCount $receiverRemoteTextureReadyEventCount `
        -RemoteUiPaintEventCount $receiverRemoteUiPaintEventCount `
        -RemoteScreenPresentEventCount $receiverRemoteScreenPresentEventCount
      $receiverStageObservedGapMs =
        Get-JsonDouble $receiverProbeSummary 'stage_observed_gap_ms'
      $receiverRendererCallbackToStageMs =
        Get-JsonDouble $receiverProbeSummary 'renderer_callback_to_stage_ms'
      $receiverWindowFlutterFrameCount =
        Get-JsonInt $receiverProbeSummary 'receiver_window_flutter_frame_count'
      $receiverWindowFlutterFrameGapP95Ms =
        Get-JsonDouble $receiverProbeSummary 'receiver_window_flutter_frame_gap_p95_ms'
      $receiverWindowFlutterFrameGapMaxMs =
        Get-JsonDouble $receiverProbeSummary 'receiver_window_flutter_frame_gap_max_ms'
      $receiverWindowFlutterFrameGapsOver50Ms =
        Get-JsonInt $receiverProbeSummary 'receiver_window_flutter_frame_gaps_over_50ms'
      $receiverWindowFlutterFrameGapsOver100Ms =
        Get-JsonInt $receiverProbeSummary 'receiver_window_flutter_frame_gaps_over_100ms'

      $rendererAttachedValue = Get-JsonProperty $receiverProbeSummary 'renderer_attached'
      if ($null -ne $rendererAttachedValue) {
        $receiverRendererAttached = [bool]$rendererAttachedValue
      }

      $rendererVisibleValue = Get-JsonProperty $receiverProbeSummary 'renderer_visible'
      if ($null -ne $rendererVisibleValue) {
        $receiverRendererVisible = [bool]$rendererVisibleValue
      }
    }
  }
  if ($ReceiverProbeEnabled) {
    $receiverSourceLineageStats =
      Get-ReceiverSourceLineageStats -EventsPath $receiverProbeEventsPath
    $receiverSourceLineageEventCount =
      [int]$receiverSourceLineageStats.sourceLineageEventCount
    $receiverSourceFrameIdEventCount =
      [int]$receiverSourceLineageStats.frameIdEventCount
    $receiverPreviousFrameIdEventCount =
      [int]$receiverSourceLineageStats.previousFrameIdEventCount
    $receiverSourceFrameMarkerIdEventCount =
      [int]$receiverSourceLineageStats.sourceFrameMarkerIdEventCount
    $receiverSourceQpcEventCount =
      [int]$receiverSourceLineageStats.sourceQpcEventCount
    $receiverStageQpcEventCount =
      [int]$receiverSourceLineageStats.stageQpcEventCount
    $receiverSourceFrameIdAvailable =
      [bool]$receiverSourceLineageStats.sourceFrameIdAvailable
    $receiverSourceLineageAvailable =
      [bool]$receiverSourceLineageStats.sourceLineageAvailable
    $receiverSourceLineageReason =
      [string]$receiverSourceLineageStats.reason
  }

  $selfViewCropFreshnessPass = $visualStatus -eq 'completed' -and
    $uniqueFps -ne $null -and
    [double]$uniqueFps -ge $MinUniqueFps
  $receiverProbeFreshnessCompleted = $receiverProbeStatus -eq 'completed_receiver_probe_events' -or
    $receiverProbeStatus -eq 'completed_external_receiver_probe_events'
  $receiverProbeStatsOnlyCompleted =
    $receiverProbeStatus -eq 'completed_stats_only_receiver_probe_events' -or
    $receiverProbeStatus -eq 'completed_external_receiver_probe_stats_only_events'
  if ($null -ne $receiverRenderedFpsP50) {
    $receiverEffectiveStatsFps = $receiverRenderedFpsP50
    $receiverStatsFpsGateSource = 'rendered_fps_p50'
  } elseif ($null -ne $receiverDecodedFpsP50) {
    $receiverEffectiveStatsFps = $receiverDecodedFpsP50
    $receiverStatsFpsGateSource = 'decoded_fps_p50'
  } elseif ($null -ne $receiverReceivedFpsP50) {
    $receiverEffectiveStatsFps = $receiverReceivedFpsP50
    $receiverStatsFpsGateSource = 'received_fps_p50'
  } elseif ($null -ne $receiverRenderedFps) {
    $receiverEffectiveStatsFps = $receiverRenderedFps
    $receiverStatsFpsGateSource = 'rendered_fps_latest'
  } elseif ($null -ne $receiverDecodedFps) {
    $receiverEffectiveStatsFps = $receiverDecodedFps
    $receiverStatsFpsGateSource = 'decoded_fps_latest'
  } elseif ($null -ne $receiverReceivedFps) {
    $receiverEffectiveStatsFps = $receiverReceivedFps
    $receiverStatsFpsGateSource = 'received_fps_latest'
  } elseif ($null -ne $receiverStatsFps) {
    $receiverEffectiveStatsFps = $receiverStatsFps
    $receiverStatsFpsGateSource = 'receiver_fps'
  }
  $receiverStatsFpsPass = $null -eq $receiverEffectiveStatsFps -or
    [double]$receiverEffectiveStatsFps -ge $MinUniqueFps
  $receiverPresentationP95LimitMs = 50.0
  if ($null -ne $receiverFramePresentationP95GapP50Ms) {
    $receiverEffectiveFramePresentationP95GapMs =
      $receiverFramePresentationP95GapP50Ms
    $receiverPresentationGateSource = 'frame_presentation_p95_gap_ms_p50'
  } elseif ($null -ne $receiverFramePresentationP95GapMs) {
    $receiverEffectiveFramePresentationP95GapMs = $receiverFramePresentationP95GapMs
    $receiverPresentationGateSource = 'frame_presentation_p95_gap_ms_latest'
  }
  $receiverPresentationPass = $null -eq $receiverEffectiveFramePresentationP95GapMs -or
    [double]$receiverEffectiveFramePresentationP95GapMs -le $receiverPresentationP95LimitMs
  $receiverQualityCountersPass = $receiverStatsFpsPass -and $receiverPresentationPass
  $receiverFrameTapPresentationUnhealthy = -not $receiverPresentationPass
  $receiverScreenPresentObserved =
    Test-NumberGreaterThan $receiverRemoteScreenPresentEventCount 0.0
  $receiverFlutterFrameGapP95Pass =
    $receiverScreenPresentObserved -and
    $null -ne $receiverWindowFlutterFrameGapP95Ms -and
    [double]$receiverWindowFlutterFrameGapP95Ms -le 20.0
  $receiverFlutterFrameSchedulingSpikePresent =
    (Test-NumberGreaterThan $receiverWindowFlutterFrameGapMaxMs 100.0) -or
    (Test-NumberGreaterThan $receiverWindowFlutterFrameGapsOver100Ms 0.0)
  $receiverFlutterFrameSchedulingUnhealthy =
    (Test-NumberGreaterThan $receiverWindowFlutterFrameGapP95Ms 50.0) -or
    $receiverFlutterFrameSchedulingSpikePresent
  $receiverFrameTapRedButFlutterP95Healthy =
    $receiverFrameTapPresentationUnhealthy -and $receiverFlutterFrameGapP95Pass
  $receiverLayerHealthy = $null
  if (-not [string]::IsNullOrWhiteSpace($receiverSubscribedQuality) -or
      -not [string]::IsNullOrWhiteSpace($receiverSimulcastLayer)) {
    $receiverLayerHealthy =
      $receiverSubscribedQuality -eq 'high' -and
      ($receiverSimulcastLayer -eq 'single' -or
        [string]::IsNullOrWhiteSpace($receiverSimulcastLayer))
  }
  $receiverDecodedDimensionsHealthy = $null
  if ($null -ne $requestedWidth -and
      $null -ne $requestedHeight -and
      $null -ne $receiverDecodedWidth -and
      $null -ne $receiverDecodedHeight) {
    $receiverDecodedDimensionsHealthy =
      [int]$receiverDecodedWidth -ge [int]$requestedWidth -and
      [int]$receiverDecodedHeight -ge [int]$requestedHeight
  }
  $receiverDecodedCadenceHealthy =
    $receiverStatsFpsPass -and
    ($null -eq $receiverDecodeUniqueFps -or
      (Test-NumberAtLeast $receiverDecodeUniqueFps $MinUniqueFps)) -and
    ($null -eq $receiverRenderUniqueFps -or
      (Test-NumberAtLeast $receiverRenderUniqueFps $MinUniqueFps))
  $receiverPresentationUnhealthy = $receiverFrameTapPresentationUnhealthy
  $receiverBitrateLow = Test-NumberLessThan $receiverInboundBitrateBps 2000000
  $receiverQpHigh = Test-NumberAtLeast $receiverAverageQp 38
  $receiverLayerOrUpscaleSuspected =
    $receiverLayerHealthy -eq $false -or
    $receiverDecodedDimensionsHealthy -eq $false -or
    $receiverUpscalingLowerLayerSuspected -eq $true -or
    $receiverAdaptiveStreamLowLayerSuspected -eq $true
  $senderQueuePressure =
    (Test-NumberGreaterThan $senderVideoStreamEncoderQueueDrops 0.0) -or
    (Test-NumberGreaterThan $senderVideoStreamEncoderOverloadDrops 0.0)
  $senderVseExpectedStartupReconfigureOnly =
    (Test-NumberGreaterThan $senderVideoStreamEncoderPendingReconfigureSignals 0.0) -and
    $senderVideoStreamEncoderPendingReconfigureSignals -eq
      ($senderVideoStreamEncoderPendingReconfigureConfigureEncoder +
        $senderVideoStreamEncoderPendingReconfigureFrameInfoChange) -and
    -not (Test-NumberGreaterThan $senderVideoStreamEncoderPendingReconfigureSourceRestriction 0.0) -and
    -not (Test-NumberGreaterThan $senderVideoStreamEncoderPendingReconfigureUnknown 0.0)
  $senderVseSteadyTailPresent =
    (Test-NumberGreaterThan $senderVideoStreamEncoderPostToOnFrameMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderVideoEncoderEncodeMaxMs 100.0) -or
    $senderQueuePressure -or
    ((Test-NumberGreaterThan $senderVideoStreamEncoderOnFrameMaxMs 100.0) -or
      (Test-NumberGreaterThan $senderVideoStreamEncoderMaybeEncodeMaxMs 100.0) -or
      (Test-NumberGreaterThan $senderVideoStreamEncoderMaybeReconfigureMaxMs 100.0)) -and
      -not $senderVseExpectedStartupReconfigureOnly
  $senderAverageFpsLow =
    (Test-NumberLessThan $averageCaptureFps $MinUniqueFps) -or
    (Test-NumberLessThan $averageEncodeFps $MinUniqueFps) -or
    (Test-NumberLessThan $averageSendFps $MinUniqueFps)
  $senderLongGapPresent =
    (Test-NumberGreaterThan $senderSourceToSubmitMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderDeliveryWallMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderSourceQpcMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderTimestampDeltaMaxMs 100.0) -or
    $senderVseSteadyTailPresent
  $senderNativeReadinessSpike =
    (Test-NumberGreaterThan $senderNativeBltToReadyMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderNativeConvertMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderSourceToReadbackReadyMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderReadbackQueueToMapMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderReadbackLatencyAverageMs 33.4) -or
    ($senderNativeNv12Suspended -eq $true)
  $senderDeliveryWallTailPresent =
    (Test-NumberGreaterThan $senderSourceToSubmitMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderDeliveryWallMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderSourceQpcMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderTimestampDeltaMaxMs 100.0)
  $senderVseTailPresent = $senderVseSteadyTailPresent
  $senderVseTailDominant = if (
    $senderVseExpectedStartupReconfigureOnly -and
    -not $senderVseSteadyTailPresent) {
    'expected_startup_reconfigure'
  } elseif (
    Test-NumberGreaterThan $senderVideoStreamEncoderMaybeReconfigureMaxMs 100.0) {
    'maybe_reconfigure'
  } elseif (Test-NumberGreaterThan $senderVideoEncoderEncodeMaxMs 100.0) {
    'video_encoder_encode'
  } elseif (Test-NumberGreaterThan $senderVideoStreamEncoderMaybeEncodeCallMaxMs 100.0) {
    'maybe_encode_call'
  } elseif (Test-NumberGreaterThan $senderVideoStreamEncoderMaybePreEncodeMaxMs 100.0) {
    'maybe_pre_encode'
  } elseif (Test-NumberGreaterThan $senderVideoStreamEncoderPostToOnFrameMaxMs 100.0) {
    'post_to_onframe'
  } elseif ($senderQueuePressure) {
    'queue_pressure'
  } else {
    'none'
  }
  $senderActiveSplitCandidates = @(
    [pscustomobject]@{
      name = 'task_posted_to_task_starts'
      value = $senderActiveTaskPostedToTaskStartsMaxMs
    }
    [pscustomobject]@{
      name = 'task_starts_to_adaptation_complete'
      value = $senderActiveTaskStartsToAdaptationCompleteMaxMs
    }
    [pscustomobject]@{
      name = 'adaptation_complete_to_vse_entry'
      value = $senderActiveAdaptationCompleteToVseEntryMaxMs
    }
    [pscustomobject]@{
      name = 'vse_entry_to_encoder_task_posted'
      value = $senderActiveVseEntryToEncoderTaskPostedMaxMs
    }
    [pscustomobject]@{
      name = 'encoder_task_posted_to_started'
      value = $senderActiveEncoderTaskPostedToStartedMaxMs
    }
    [pscustomobject]@{
      name = 'encoder_task_starts_to_encode_entry'
      value = $senderActiveEncoderTaskStartsToEncodeEntryMaxMs
    }
    [pscustomobject]@{
      name = 'encode_entry_to_encode_return'
      value = $senderActiveEncodeEntryToReturnMaxMs
    }
  ) | Where-Object { $null -ne $_.value }
  $senderActiveSplitDominant = 'none'
  if ($senderActiveSplitCandidates.Count -gt 0) {
    $largestActiveSplit =
      $senderActiveSplitCandidates | Sort-Object -Property value -Descending |
      Select-Object -First 1
    if (Test-NumberGreaterThan $largestActiveSplit.value 0.0) {
      $senderActiveSplitDominant = $largestActiveSplit.name
    }
  }
  $senderEncodeReturnTailPresent =
    Test-NumberGreaterThan $senderActiveEncodeEntryToReturnMaxMs 100.0
  $senderMfMarkersPresent =
    (Test-NumberGreaterThan $senderMfEncoderProcessInputSamples 0.0) -or
    (Test-NumberGreaterThan $senderMfEncoderProcessOutputSamples 0.0) -or
    (Test-NumberGreaterThan $senderMfEncoderOutputFrames 0.0)
  $senderMfEncoderSubstagesFast =
    $senderMfMarkersPresent -and
    (-not (Test-NumberGreaterThan $senderMfEncoderMaxTotalMs 33.4)) -and
    (-not (Test-NumberGreaterThan $senderMfEncoderMaxProcessInputMs 33.4)) -and
    (-not (Test-NumberGreaterThan $senderMfEncoderMaxProcessOutputMs 33.4)) -and
    (-not (Test-NumberGreaterThan $senderMfEncoderMaxEncodedCallbackMs 33.4))
  $senderEncodeReturnAttribution = if (-not $senderEncodeReturnTailPresent) {
    'encode_return_tail_absent'
  } elseif ($senderMfEncoderSubstagesFast) {
    'encode_return_tail_not_explained_by_mf_substages'
  } elseif ($senderMfMarkersPresent) {
    'encode_return_tail_with_mf_substage_pressure'
  } else {
    'encode_return_tail_missing_mf_substage_markers'
  }
  $senderNativeTailPresent =
    (Test-NumberGreaterThan $senderNativeBltToReadyMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderNativeConvertMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderSourceToReadbackReadyMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderReadbackQueueToMapMaxMs 100.0) -or
    (Test-NumberGreaterThan $senderReadbackLatencyAverageMs 33.4) -or
    ($senderNativeNv12Suspended -eq $true)
  $inactivePreviewBypassInactive =
    (Test-NumberGreaterThan $refreshed 0.0) -and
    -not (Test-NumberGreaterThan $bypassed 0.0)
  $senderDeliverySuspected =
    $senderAverageFpsLow -or
    $senderLongGapPresent -or
    $senderNativeReadinessSpike -or
    $senderQueuePressure -or
    $bottleneckLabel -eq 'native_nv12_ready_limited'

  $correlationClassification = 'insufficient_evidence'
  $correlationSummary =
    'Sender/receiver boundary could not be classified from the available fields.'
  $correlationNext =
    'Add or repair missing sender/receiver correlation fields before tuning behavior.'
  if ($receiverLayerOrUpscaleSuspected) {
    $correlationClassification = 'receiver_layer_or_resolution_limited'
    $correlationSummary =
      'Receiver quality/layer or decoded dimensions are not aligned with the requested stream.'
    $correlationNext =
      'Fix receiver subscription/layer policy before sender capture tuning.'
  } elseif (-not $receiverStatsFpsPass) {
    $correlationClassification = 'receiver_counter_cadence_low'
    $correlationSummary =
      'Receiver counter FPS is below the target before presentation cadence is considered.'
    $correlationNext =
      'Compare sender sent cadence with receiver framesReceived/framesDecoded before changing render behavior.'
  } elseif ($receiverPresentationUnhealthy -and $senderDeliverySuspected) {
    $correlationClassification =
      'sender_delivery_correlates_with_receiver_presentation'
    $correlationSummary =
      'Receiver decoded cadence/layer are broadly healthy, but receiver presentation p95 is red while sender/native delivery gaps or queue pressure are present.'
    $correlationNext =
      'Correlate sender delivery/native readiness windows with receiver presentation gaps before hook-target, bitrate, or receiver-widget tuning.'
  } elseif ($receiverPresentationUnhealthy) {
    $correlationClassification = 'receiver_presentation_limited'
    $correlationSummary =
      'Receiver decoded cadence is broadly healthy and sender delivery evidence is not currently red enough to explain presentation p95.'
    $correlationNext =
      'Inspect receiver renderer/texture presentation and decode-to-render timing.'
  } elseif ($receiverBitrateLow -or $receiverQpHigh) {
    $correlationClassification = 'receiver_quality_pressure'
    $correlationSummary =
      'Receiver cadence is acceptable but bitrate/QP suggests visual quality pressure.'
    $correlationNext =
      'Inspect sender/SFU bitrate allocation and encoder rate control only after cadence stays green.'
  } elseif ($receiverDecodedCadenceHealthy) {
    $correlationClassification = 'receiver_counters_green'
    $correlationSummary =
      'Receiver decoded/render cadence, presentation, layer, and quality counters are green by current gates.'
    $correlationNext =
      'Require receiver-window visual or user-visible proof before declaring gameplay streaming green.'
  }
  $correlationWindows = New-SenderReceiverWindowCorrelation `
    -PrimaryResult $primaryResult `
    -ReceiverEventsPath $receiverProbeEventsPath `
    -ReceiverPresentationP95LimitMs $receiverPresentationP95LimitMs `
    -MinUniqueFps $MinUniqueFps
  $senderPresentationTailCorrelation =
    New-SenderReceiverPresentationTailCorrelation `
      -CorrelationWindows $correlationWindows `
      -ReceiverPresentationP95LimitMs $receiverPresentationP95LimitMs `
      -MinUniqueFps $MinUniqueFps
  $senderPresentationTailClassification =
    Get-JsonString $senderPresentationTailCorrelation 'classification'
  $senderPresentationTailSummary =
    Get-JsonString $senderPresentationTailCorrelation 'summary'
  $senderPresentationTailNext =
    Get-JsonString $senderPresentationTailCorrelation 'next'
  if ($correlationClassification -eq
      'sender_delivery_correlates_with_receiver_presentation' -and
      $senderPresentationTailClassification -eq
        'mixed_sender_tail_and_receiver_presentation_windows') {
    $correlationClassification =
      'mixed_receiver_presentation_and_sender_delivery'
    $correlationSummary =
      'Receiver presentation is red in both receiver-only windows and sender-coupled sender/native tail windows.'
    $correlationNext =
      'Split receiver renderer/texture/UI/screen-present cadence from sender delivery/native readiness and encoder-return tails before tuning either side.'
  }
  $receiverSourceFrameMarkerPass =
    $receiverSourceFrameMarkerUniqueFps -ne $null -and
    [double]$receiverSourceFrameMarkerUniqueFps -ge $MinUniqueFps
  $receiverRenderContentFreshnessPass = if ($SourceFrameContentMarker) {
    $receiverSourceFrameMarkerPass
  } else {
    $receiverRenderUniqueFps -ne $null -and
      [double]$receiverRenderUniqueFps -ge $MinUniqueFps
  }
  $receiverRenderFreshnessPass = $ReceiverProbeEnabled -and
    ($ReceiverProbeMode -eq 'render' -or $ReceiverProbeMode -eq 'external-render') -and
    $receiverProbeExitCode -eq 0 -and
    $receiverProbeFreshnessCompleted -and
    $receiverRendererAttached -eq $true -and
    $receiverRendererVisible -eq $true -and
    $receiverRenderFreshnessSource -eq 'frame_hash_tap' -and
    $receiverRenderContentFreshnessPass -and
    $receiverQualityCountersPass
  $receiverDecodeFreshnessPass = $ReceiverProbeEnabled -and
    $ReceiverProbeMode -eq 'external-decode-only' -and
    $receiverProbeExitCode -eq 0 -and
    $receiverProbeFreshnessCompleted -and
    $receiverDecodeFreshnessSource -eq 'frame_hash_tap' -and
    $receiverDecodeUniqueFps -ne $null -and
    [double]$receiverDecodeUniqueFps -ge $MinUniqueFps
  $localPreviewFreshnessPass = $ReceiverProbeEnabled -and
    $ReceiverProbeMode -eq 'local-preview' -and
    $receiverProbeExitCode -eq 0 -and
    $receiverProbeStatus -eq 'completed_local_preview_probe_events' -and
    $localPreviewFreshnessSource -eq 'frame_hash_tap' -and
    $localPreviewUniqueFps -ne $null -and
    [double]$localPreviewUniqueFps -ge $MinUniqueFps
  $receiverWindowVisualMeasured =
    -not [bool]$SkipReceiverProbeWindowRecording -and
    $null -ne $receiverProbeWindowVisualExitCode -and
    $null -ne $receiverProbeWindowVisual
  $receiverWindowVisualFreshnessPass = $receiverWindowVisualMeasured -and
    $receiverProbeWindowVisualExitCode -eq 0 -and
    $receiverProbeWindowVisualStatus -eq 'completed' -and
    $receiverProbeWindowUniqueFps -ne $null -and
    [double]$receiverProbeWindowUniqueFps -ge $MinUniqueFps
  $receiverWindowExactFreshnessPass = $receiverWindowVisualMeasured -and
    $receiverProbeWindowExactUniqueFps -ne $null -and
    [double]$receiverProbeWindowExactUniqueFps -ge $MinUniqueFps
  $receiverVisualFrameMarkerSourceLinked = if ($SourceFrameContentMarker) {
    $receiverProbeWindowSourceMarkerAvailable -or
      $receiverSourceFrameMarkerIdEventCount -gt 0
  } else {
    $ReceiverProbeVisualFrameMarker -and $receiverSourceFrameIdAvailable
  }
  $receiverVisualFrameMarkerSourceLineageReason = if ($SourceFrameContentMarker) {
    if ($receiverProbeWindowSourceMarkerAvailable) {
      'source_frame_content_marker_decoded_from_receiver_window'
    } elseif ($receiverSourceFrameMarkerIdEventCount -gt 0) {
      'source_frame_content_marker_decoded_from_receiver_renderer_callback'
    } else {
      'source_frame_content_marker_missing_from_receiver'
    }
  } elseif (-not $ReceiverProbeVisualFrameMarker) {
    'visual_frame_marker_not_requested'
  } elseif ($receiverVisualFrameMarkerSourceLinked) {
    $receiverSourceLineageReason
  } else {
    'source_frame_id_missing_for_visual_marker'
  }
  $receiverWindowScreenPresentGateSource = if ($SourceFrameContentMarker) {
    if ($receiverProbeWindowSourceMarkerAvailable) {
      'source_frame_content_marker'
    } elseif ($receiverSourceFrameMarkerIdEventCount -gt 0) {
      'source_frame_content_marker_receiver_callback'
    } else {
      'source_frame_content_marker_missing'
    }
  } elseif ($ReceiverProbeVisualFrameMarker) {
    if ($receiverVisualFrameMarkerSourceLinked) {
      'source_frame_id_exact_visual_marker'
    } else {
      'source_frame_id_marker_missing'
    }
  } else {
    'perceptual_visual_freshness'
  }
  $receiverWindowScreenPresentPass = if ($SourceFrameContentMarker) {
    $receiverProbeWindowSourceMarkerPass
  } elseif ($ReceiverProbeVisualFrameMarker) {
    $receiverVisualFrameMarkerSourceLinked -and $receiverWindowExactFreshnessPass
  } else {
    $receiverWindowVisualFreshnessPass
  }
  $receiverWindowVisualGateRequired = $ReceiverProbeEnabled -and
    $ReceiverProbeMode -eq 'external-render' -and
    $receiverWindowVisualMeasured
  $receiverWindowPerceptualFreshnessUnhealthy =
    $receiverWindowVisualMeasured -and
    $receiverProbeWindowUniqueFps -ne $null -and
    -not $receiverWindowVisualFreshnessPass
  $receiverWindowExactFreshnessMeasured =
    $receiverWindowVisualMeasured -and
    ($ReceiverProbeVisualFrameMarker -or $SourceFrameContentMarker) -and
    $receiverProbeWindowExactUniqueFps -ne $null
  $receiverPresentationIntervalsUnhealthy =
    $receiverFrameTapPresentationUnhealthy -or
    $receiverFlutterFrameSchedulingUnhealthy
  $receiverScreenPresentFreshButPerceptualPoor =
    ($ReceiverProbeVisualFrameMarker -or $SourceFrameContentMarker) -and
    $receiverVisualFrameMarkerSourceLinked -and
    $receiverWindowScreenPresentPass -eq $true -and
    $receiverWindowPerceptualFreshnessUnhealthy
  $sameHostRecorderLoadSuspected =
    -not [bool]$SkipReceiverProbeWindowRecording -and
    ((Test-NumberGreaterThan $hostSystemCpuAverage 70.0) -or
      (Test-NumberGreaterThan $hostSystemCpuMaximum 90.0) -or
      $senderAverageFpsLow)
  $presentationVisualMismatchClassification = 'insufficient_evidence'
  $presentationVisualMismatchSummary =
    'Receiver screen-present, perceptual visual freshness, and presentation cadence could not be split from the available fields.'
  $presentationVisualMismatchNext =
    'Collect receiver-window visual evidence with the exact frame marker before tuning sender or receiver behavior.'
  if ($SourceFrameContentMarker -and
      $receiverWindowVisualMeasured -and
      -not $receiverProbeWindowSourceMarkerAvailable) {
    $presentationVisualMismatchClassification =
      'source_frame_content_marker_missing'
    $presentationVisualMismatchSummary =
      'Receiver-window visual analysis was measured, but the encoded source-frame content marker could not be decoded from the receiver window.'
    $presentationVisualMismatchNext =
      'Verify marker visibility/recording scale before using receiver-window source-marker cadence as a screen-present gate.'
  } elseif ($ReceiverProbeVisualFrameMarker -and
      $receiverWindowVisualMeasured -and
      -not $receiverVisualFrameMarkerSourceLinked) {
    $presentationVisualMismatchClassification =
      'source_lineage_missing_for_visual_marker'
    $presentationVisualMismatchSummary =
      'Receiver-window exact hashes were measured, but receiver probe events did not carry source frame_id, so the visual marker cannot prove source-frame screen-present cadence.'
    $presentationVisualMismatchNext =
      'Propagate a real source frame ID to receiver events or encode a debug source marker before using marker-on visual freshness as a gate.'
  } elseif ($receiverFrameTapRedButFlutterP95Healthy -and
      -not $receiverWindowVisualMeasured) {
    $presentationVisualMismatchClassification =
      'frame_tap_presentation_red_flutter_present_p95_healthy_visual_unmeasured'
    $presentationVisualMismatchSummary =
      'Receiver native frame-tap presentation p95 is red, but the external receiver-window Flutter frame-timing p95 is healthy; receiver-window visual freshness was not measured.'
    $presentationVisualMismatchNext =
      'Treat this as renderer/content-cadence or measurement-path split evidence before blaming broad Flutter/window presentation; use source-linked receiver frame IDs or a marker-on receiver-window recording for visual proof.'
  } elseif (-not $receiverWindowVisualMeasured) {
    $presentationVisualMismatchClassification = 'visual_measurement_unavailable'
    $presentationVisualMismatchSummary =
      'Receiver-window recording or visual analysis was skipped or unavailable.'
    $presentationVisualMismatchNext =
      'Run an external-render receiver probe with receiver-window recording when visual confirmation is needed.'
  } elseif ($receiverScreenPresentFreshButPerceptualPoor -and
      $senderDeliverySuspected) {
    $presentationVisualMismatchClassification =
      'screen_present_green_perceptual_red_sender_pressure'
    $presentationVisualMismatchSummary =
      'Source-linked marker content reaches the receiver window at the target cadence, but perceptual visual freshness is red while sender/native delivery pressure is also present.'
    $presentationVisualMismatchNext =
      'Use clean no-recorder runs for sender/native pressure and marker-on recorder runs only to prove the screen-present/perceptual split.'
  } elseif ($receiverScreenPresentFreshButPerceptualPoor -and
      $receiverPresentationIntervalsUnhealthy) {
    $presentationVisualMismatchClassification =
      'screen_present_green_perceptual_red_presentation_intervals'
    $presentationVisualMismatchSummary =
      'Source-linked marker content reaches the receiver window at the target cadence, but perceptual visual freshness and presentation/frame-gap intervals are red.'
    $presentationVisualMismatchNext =
      'Correlate receiver Flutter frame gaps and remote presentation events before changing layer, bitrate, hook target, or sender capture behavior.'
  } elseif ($receiverScreenPresentFreshButPerceptualPoor) {
    $presentationVisualMismatchClassification =
      'screen_present_green_perceptual_red_visual_quality'
    $presentationVisualMismatchSummary =
      'Source-linked marker content reaches the receiver window at the target cadence, but perceptual visual freshness remains red.'
    $presentationVisualMismatchNext =
      'Treat this as visual-quality/perceptual loss until receiver presentation or sender delivery evidence explains it.'
  } elseif ($receiverWindowScreenPresentPass -eq $true -and
      -not $receiverQualityCountersPass) {
    $presentationVisualMismatchClassification =
      'screen_present_green_receiver_counters_red'
    $presentationVisualMismatchSummary =
      'Receiver screen-present freshness is green, but receiver FPS/presentation quality counters are still red.'
    $presentationVisualMismatchNext =
      'Investigate counter and presentation cadence mismatch before declaring the receiver path healthy.'
  } elseif ($receiverWindowScreenPresentPass -eq $true -and
      $receiverWindowVisualFreshnessPass -and
      $receiverQualityCountersPass) {
    $presentationVisualMismatchClassification =
      'screen_present_and_receiver_counters_green'
    $presentationVisualMismatchSummary =
      'Receiver-window visual freshness, source-marker freshness, and receiver quality counters are green by current gates.'
    $presentationVisualMismatchNext =
      'Use user-visible/mobile or physical-receiver proof before moving to visual-quality tuning.'
  } elseif ($receiverWindowExactFreshnessMeasured -and
      -not $receiverWindowScreenPresentPass) {
    $presentationVisualMismatchClassification = 'screen_present_red'
    $presentationVisualMismatchSummary =
      'Source-linked marker screen-present freshness is below the target cadence.'
    $presentationVisualMismatchNext =
      'Stay on receiver/sender presentation correlation before treating perceptual visual quality as the primary issue.'
  } elseif ($receiverWindowVisualMeasured -and
      -not $ReceiverProbeVisualFrameMarker -and
      -not $SourceFrameContentMarker -and
      -not $receiverWindowVisualFreshnessPass) {
    $presentationVisualMismatchClassification =
      'perceptual_visual_red_without_marker'
    $presentationVisualMismatchSummary =
      'Perceptual receiver-window visual freshness is red, but source-linked marker screen-present proof was not requested.'
    $presentationVisualMismatchNext =
      'Repeat with -SourceFrameContentMarker when a screen-present versus perceptual-quality split is needed.'
  }
  $receiverQualityPresentationClassification = 'insufficient_evidence'
  $receiverQualityPresentationSummary =
    'Receiver layer, bitrate, decoded uniqueness, and presentation cadence could not be separated from the available fields.'
  $receiverQualityPresentationNext =
    'Collect receiver layer, bitrate/QP, decoded dimensions, unique hash cadence, and presentation interval evidence before changing behavior.'
  if ($receiverLayerOrUpscaleSuspected) {
    $receiverQualityPresentationClassification =
      'receiver_low_layer_or_resolution'
    $receiverQualityPresentationSummary =
      'Receiver subscription, decoded dimensions, or upscaling evidence suggests the receiver is not presenting the requested high layer.'
    $receiverQualityPresentationNext =
      'Fix receiver subscription/layer policy before sender capture or bitrate tuning.'
  } elseif (-not $receiverStatsFpsPass) {
    $receiverQualityPresentationClassification = 'receiver_counter_cadence_low'
    $receiverQualityPresentationSummary =
      'Receiver received/decoded/rendered FPS counters are below the target before visual presentation cadence is considered.'
    $receiverQualityPresentationNext =
      'Compare sender framesSent cadence with receiver framesReceived/framesDecoded windows.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverFrameTapRedButFlutterP95Healthy -and
      $senderPresentationTailClassification -eq
        'mixed_sender_tail_and_receiver_presentation_windows') {
    $receiverQualityPresentationClassification =
      'unique_frames_frame_tap_red_flutter_present_p95_healthy_mixed_tail'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and high-layer selection are healthy, native frame-tap presentation p95 is red, and the receiver-window Flutter frame-timing p95 is healthy while sampled windows split between receiver-only and sender-coupled tails.'
    $receiverQualityPresentationNext =
      'Treat receiver-only windows as renderer/content-cadence or measurement-path evidence, and coupled windows as sender/native/encode-return attribution; do not call this broad Flutter/window scheduling.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverFrameTapRedButFlutterP95Healthy -and
      $senderDeliverySuspected) {
    $receiverQualityPresentationClassification =
      'unique_frames_frame_tap_red_flutter_present_p95_healthy_sender_tail'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and layer are healthy, native frame-tap presentation p95 is red, and the receiver-window Flutter frame-timing p95 is healthy while sender delivery evidence is also present.'
    $receiverQualityPresentationNext =
      'Split sender/native/encode-return tails from receiver renderer/content-cadence evidence before tuning either side.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverPresentationUnhealthy -and
      ($receiverBitrateLow -or $receiverQpHigh) -and
      $senderDeliverySuspected) {
    $receiverQualityPresentationClassification =
      'unique_frames_presentation_red_low_bitrate_sender_tail'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and high-layer selection are broadly healthy, but presentation cadence is red while bitrate/QP and sender delivery tails are also red.'
    $receiverQualityPresentationNext =
      'Split sender delivery/VSE/native tails from receiver renderer-stage delay; do not treat this as a layer-selection bug.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverPresentationUnhealthy -and
      $senderPresentationTailClassification -eq
        'mixed_sender_tail_and_receiver_presentation_windows') {
    $receiverQualityPresentationClassification =
      'unique_frames_presentation_red_mixed_receiver_and_sender_tail'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and high-layer selection are broadly healthy, but presentation cadence is red in both receiver-only and sender-coupled windows.'
    $receiverQualityPresentationNext =
      'Inspect receiver renderer-stage delay separately from sender native/VSE/encoder-return tails.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverPresentationUnhealthy -and
      $senderDeliverySuspected) {
    $receiverQualityPresentationClassification =
      'unique_frames_presentation_red_sender_tail'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and layer are broadly healthy, but presentation cadence is red while sender delivery/VSE/native tails are present.'
    $receiverQualityPresentationNext =
      'Inspect sender delivery/VSE/native tail attribution before receiver-widget or bitrate-only tuning.'
  } elseif ($receiverDecodedCadenceHealthy -and
      $receiverPresentationUnhealthy) {
    $receiverQualityPresentationClassification =
      'unique_frames_presentation_red_receiver_render'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and layer are broadly healthy, but presentation cadence is red without enough sender-tail evidence to explain it.'
    $receiverQualityPresentationNext =
      'Inspect receiver renderer, texture presentation, and Flutter frame scheduling.'
  } elseif ($receiverDecodedCadenceHealthy -and
      ($receiverBitrateLow -or $receiverQpHigh)) {
    $receiverQualityPresentationClassification =
      'unique_frames_low_bitrate_quality_pressure'
    $receiverQualityPresentationSummary =
      'Receiver unique-frame cadence and presentation counters are acceptable, but bitrate/QP suggests visual quality pressure.'
    $receiverQualityPresentationNext =
      'Inspect sender/SFU bitrate allocation and encoder rate control only after presentation cadence stays green.'
  } elseif ($receiverQualityCountersPass -and $receiverDecodedCadenceHealthy) {
    $receiverQualityPresentationClassification =
      'receiver_cadence_and_presentation_green'
    $receiverQualityPresentationSummary =
      'Receiver cadence, presentation interval, layer, and decoded dimensions are green by current counters.'
    $receiverQualityPresentationNext =
      'Require visual or user-visible receiver proof before declaring gameplay streaming green.'
  }
  $freshnessEvidenceSource = if ($receiverWindowScreenPresentPass) {
    if ($SourceFrameContentMarker) {
      'receiver_window_source_frame_content_marker'
    } elseif ($ReceiverProbeVisualFrameMarker) {
      'receiver_window_exact_visual_frame_marker'
    } else {
      'receiver_window_visual'
    }
  } elseif ($receiverRenderFreshnessPass) {
    'receiver_remote_renderer_callback'
  } elseif ($receiverDecodeFreshnessPass) {
    'receiver_remote_decode'
  } elseif ($localPreviewFreshnessPass) {
    'local_preview_diagnostic'
  } else {
    ''
  }
  $receiverRenderPassedStatus = if ($sourceOverrideRequested) {
    'passed_source_live_call_receiver_render_freshness'
  } else {
    'passed_synthetic_live_call_receiver_render_freshness'
  }
  $receiverWindowVisualPassedStatus = if ($sourceOverrideRequested) {
    'passed_source_live_call_receiver_window_visual_freshness'
  } else {
    'passed_synthetic_live_call_receiver_window_visual_freshness'
  }
  $receiverWindowVisualFailedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_window_visual_freshness'
  } else {
    'failed_synthetic_live_call_receiver_window_visual_freshness'
  }
  $receiverWindowExactFailedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_window_exact_freshness'
  } else {
    'failed_synthetic_live_call_receiver_window_exact_freshness'
  }
  $receiverWindowSourceMarkerFailedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_source_frame_content_marker'
  } else {
    'failed_synthetic_live_call_receiver_source_frame_content_marker'
  }
  $receiverSourceLineageFailedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_source_lineage_missing'
  } else {
    'failed_synthetic_live_call_receiver_source_lineage_missing'
  }
  $receiverQualityCountersFailedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_quality_counters'
  } else {
    'failed_synthetic_live_call_receiver_quality_counters'
  }
  $receiverDecodePassedStatus = if ($sourceOverrideRequested) {
    'passed_source_live_call_receiver_decode_freshness'
  } else {
    'passed_synthetic_live_call_receiver_decode_freshness'
  }
  $localPreviewPassedStatus = if ($sourceOverrideRequested) {
    'passed_source_live_call_local_preview_diagnostic'
  } else {
    'passed_synthetic_live_call_local_preview_diagnostic'
  }
  $failedStatus = if ($sourceOverrideRequested) {
    'failed_source_live_call_receiver_freshness_required'
  } else {
    'failed_synthetic_live_call_receiver_freshness_required'
  }
  $selfViewCropGate = 'retired_diagnostic_only'
  $status = if ($completionStatus -ne 'completed' -or -not [string]::IsNullOrWhiteSpace($completionError)) {
    'failed_stream_test_automation'
  } elseif ($receiverWindowVisualGateRequired -and -not $receiverWindowScreenPresentPass) {
    if ($SourceFrameContentMarker -and
        -not $receiverProbeWindowSourceMarkerAvailable) {
      $receiverSourceLineageFailedStatus
    } elseif ($SourceFrameContentMarker) {
      $receiverWindowSourceMarkerFailedStatus
    } elseif ($ReceiverProbeVisualFrameMarker -and
        -not $receiverVisualFrameMarkerSourceLinked) {
      $receiverSourceLineageFailedStatus
    } elseif ($receiverProbeWindowExactUniqueFps -ne $null -and
        -not $receiverWindowExactFreshnessPass) {
      $receiverWindowExactFailedStatus
    } else {
      $receiverWindowVisualFailedStatus
    }
  } elseif ($receiverWindowVisualGateRequired -and
      ($receiverRenderFreshnessPass -or $receiverProbeStatsOnlyCompleted) -and
      $receiverWindowScreenPresentPass) {
    $receiverWindowVisualPassedStatus
  } elseif ($ReceiverProbeEnabled -and
      ($ReceiverProbeMode -eq 'render' -or $ReceiverProbeMode -eq 'external-render') -and
      $receiverProbeExitCode -eq 0 -and
      $receiverProbeFreshnessCompleted -and
      -not $receiverQualityCountersPass) {
    $receiverQualityCountersFailedStatus
  } elseif ($receiverRenderFreshnessPass) {
    $receiverRenderPassedStatus
  } elseif ($receiverDecodeFreshnessPass) {
    $receiverDecodePassedStatus
  } elseif ($localPreviewFreshnessPass) {
    $localPreviewPassedStatus
  } elseif ($visualExitCode -ne 0 -or $null -eq $visual) {
    'failed_self_view_crop_diagnostic_measurement'
  } elseif ($ReceiverProbeEnabled -and $receiverProbeExitCode -ne 0) {
    'failed_receiver_probe'
  } else {
    $failedStatus
  }
  if ($receiverWindowVisualGateRequired -and -not $receiverWindowScreenPresentPass) {
    $freshnessEvidenceSource = if ($SourceFrameContentMarker -and
        -not $receiverProbeWindowSourceMarkerAvailable) {
      'receiver_window_source_frame_content_marker_missing'
    } elseif ($SourceFrameContentMarker) {
      'receiver_window_source_frame_content_marker_failed'
    } elseif ($ReceiverProbeVisualFrameMarker -and
        -not $receiverVisualFrameMarkerSourceLinked) {
      'receiver_window_source_frame_marker_missing'
    } elseif ($ReceiverProbeVisualFrameMarker) {
      'receiver_window_exact_visual_frame_marker_failed'
    } else {
      'receiver_window_visual_failed'
    }
  }

  if ($bg3RotationStarted -and
    $sourceOverrideRequested -and
    $null -ne $sourceOverrideProcess -and
    [string]::IsNullOrWhiteSpace($bg3RotationStopJson)) {
    try {
      $bg3RotationStopJson = Join-Path $runDirectory 'bg3-camera-rotation-stop.json'
      Invoke-Bg3CameraRotationHotkey `
        -WorkspaceRoot $workspaceRoot `
        -ProcessId $sourceOverrideProcess.Id `
        -Action 'Stop' `
        -OutputPath $bg3RotationStopJson
    } catch {
      $bg3RotationStopJson = ''
    }
  }

  $result = [ordered]@{
    schema = 'intergalactic.syntheticLiveCallFreshness.v1'
    id = $id
    status = $status
    minUniqueFps = $MinUniqueFps
    runDirectory = $runDirectory
    appProcessId = $appProcess.Id
    appStartedByScript = $startedProcess
    appWindow = [ordered]@{
      hotkeyProcessId = $hotkeySelection.ProcessId
      hotkeyWindowHandle = $hotkeySelection.HwndDecimal
      hotkeyWindowTitle = $hotkeySelection.Title
      verifiedWindowHandle = $windowRect.HwndDecimal
      verifiedWindowTitle = $windowRect.Title
      joinButtonClick = $joinButtonClick
      callEntryVerification = $callEntryVerification
    }
    externalCaptureTarget = $externalCaptureTarget
    sourceOverride = [ordered]@{
      enabled = $sourceOverrideRequested
      processId = if ($null -ne $sourceOverrideProcess) {
        $sourceOverrideProcess.Id
      } else {
        $null
      }
      processName = if ($null -ne $sourceOverrideProcess) {
        $sourceOverrideProcess.ProcessName
      } else {
        $null
      }
      title = $sourceRequestTitle
    }
    appWindowMove = $appWindowMove
    bg3CameraRotation = [ordered]@{
      requested = [bool]$StartBg3CameraRotation
      started = $bg3RotationStarted
      startJson = $bg3RotationStartJson
      stopJson = $bg3RotationStopJson
      delayedUntilReceiverWindowPlacement = [bool]($StartBg3CameraRotation -and $externalReceiverProbeRequested)
      receiverWindowPlacement = $receiverProbeWindowPlacement
      maintainFocusDuringRun = [bool]$MaintainBg3FocusDuringRun
      focusIntervalSeconds = $Bg3FocusIntervalSeconds
      focusReassertionCount = $bg3FocusReassertions.Count
      focusReassertionJsons = @($bg3FocusReassertions)
    }
    captureTargetProcessId = if ($null -ne $captureTargetProcess) {
      $captureTargetProcess.Id
    } else {
      $null
    }
    captureTargetOutputDirectory = $captureTargetOutputDirectory
    captureTargetWindow = $captureTargetWindow
    crop = [ordered]@{
      x = $CropX
      y = $CropY
      width = $CropWidth
      height = $CropHeight
      recordedWidth = if ($null -ne $size) {
        $size.Width
      } else {
        $null
      }
      recordedHeight = if ($null -ne $size) {
        $size.Height
      } else {
        $null
      }
      desktopX = $tightRecordRect.X
      desktopY = $tightRecordRect.Y
      desktopWidth = $tightRecordRect.Width
      desktopHeight = $tightRecordRect.Height
      windowDesktopX = $windowRect.X
      windowDesktopY = $windowRect.Y
      windowDesktopWidth = $windowRect.Width
      windowDesktopHeight = $windowRect.Height
      activeSegmentStartSeconds = $ActiveSegmentStartSeconds
      activeSegmentSeconds = $ActiveSegmentSeconds
    }
    completion = [ordered]@{
      status = $completionStatus
      error = $completionError
      completionCopy = $completionCopy
      reportPath = $reportPath
    }
    artifacts = [ordered]@{
      preflightFrame = $preflightFrame
      callEntryVerification = $callEntryVerificationPath
      fullVideo = $fullVideo
      fullTightVideo = $tightVideoFull
      tightVideo = $tightVideo
      activeTightVideo = $tightVideo
      visualDirectory = $visualDirectory
      receiverProbeWindowFullVideo = $receiverProbeWindowVideoFull
      receiverProbeWindowActiveVideo = $receiverProbeWindowVideo
      receiverProbeWindowVisualDirectory = $receiverProbeWindowVisualDirectory
      reportJson = $reportJsonPath
      reportJsonCopy = $reportJsonCopy
      reportMarkdown = $reportMdPath
      reportMarkdownCopy = $reportMdCopy
      receiverProbeEvents = $receiverProbeEventsPath
      receiverProbeDirectory = $receiverProbeRunDirectory
      receiverProbeSummary = $receiverProbeSummaryPath
      receiverProbeWindowPlacement = $receiverProbeWindowPlacementPath
    }
    windowsBackendMode = $WindowsBackendMode
    recording = [ordered]@{
      requestedCaptureMode = $RecordingCaptureMode
      captureMode = $recordingCaptureMode
      requestedVideoCodec = $RecordingVideoCodec
      videoCodec = $recordingCodec
      ddagrabOutputIndex = $recordingResolvedDdagrabOutputIndex
      ddagrabOriginX = $recordingResolvedDdagrabOriginX
      ddagrabOriginY = $recordingResolvedDdagrabOriginY
      receiverProbeWindowRequestedCaptureMode = $receiverProbeWindowRequestedCaptureMode
      receiverProbeWindowCaptureMode = $receiverProbeWindowCaptureMode
      receiverProbeWindowRequestedVideoCodec = $receiverProbeWindowRequestedVideoCodec
      receiverProbeWindowVideoCodec = $receiverProbeWindowVideoCodec
      receiverProbeWindowDdagrabOutputIndex = $receiverProbeWindowResolvedDdagrabOutputIndex
      receiverProbeWindowDdagrabOriginX = $receiverProbeWindowResolvedDdagrabOriginX
      receiverProbeWindowDdagrabOriginY = $receiverProbeWindowResolvedDdagrabOriginY
      receiverProbeWindowRecordingSkipped = [bool]$SkipReceiverProbeWindowRecording
      receiverProbeVisualFrameMarker = [bool]$ReceiverProbeVisualFrameMarker
      receiverVisualFrameMarkerSourceLinked = $receiverVisualFrameMarkerSourceLinked
      receiverVisualFrameMarkerSourceLineageReason =
        $receiverVisualFrameMarkerSourceLineageReason
      dummyNv12LiveSender = [bool]$DummyNv12LiveSender
      ffmpegLog = $recordingLog
    }
    correlation = [ordered]@{
      classification = $correlationClassification
      summary = $correlationSummary
      next = $correlationNext
      windowAlignment = $correlationWindows
      senderPresentationTailCorrelation =
        $senderPresentationTailCorrelation
      senderPresentationTailGlobalSignals = [ordered]@{
        deliveryWallTailPresent = $senderDeliveryWallTailPresent
        nativeTailPresent = $senderNativeTailPresent
        vseTailPresent = $senderVseTailPresent
        queuePressurePresent = $senderQueuePressure
        senderDeliverySuspected = $senderDeliverySuspected
        sourceToSubmitMaxMs = $senderSourceToSubmitMaxMs
        deliveryWallMaxMs = $senderDeliveryWallMaxMs
        sourceQpcMaxMs = $senderSourceQpcMaxMs
        nativeBltToReadyMaxMs = $senderNativeBltToReadyMaxMs
        nativeConvertMaxMs = $senderNativeConvertMaxMs
        sourceToReadbackReadyMaxMs = $senderSourceToReadbackReadyMaxMs
        readbackQueueToMapMaxMs = $senderReadbackQueueToMapMaxMs
        videoStreamEncoderPostToOnFrameMaxMs =
          $senderVideoStreamEncoderPostToOnFrameMaxMs
        videoStreamEncoderOnFrameMaxMs =
          $senderVideoStreamEncoderOnFrameMaxMs
        videoStreamEncoderMaybeEncodeMaxMs =
          $senderVideoStreamEncoderMaybeEncodeMaxMs
        videoStreamEncoderMaybePreEncodeMaxMs =
          $senderVideoStreamEncoderMaybePreEncodeMaxMs
        videoStreamEncoderMaybeEncodeCallMaxMs =
          $senderVideoStreamEncoderMaybeEncodeCallMaxMs
        videoStreamEncoderMaybeParameterUpdateMaxMs =
          $senderVideoStreamEncoderMaybeParameterUpdateMaxMs
        videoStreamEncoderMaybeReconfigureMaxMs =
          $senderVideoStreamEncoderMaybeReconfigureMaxMs
        videoStreamEncoderPendingReconfigureSignals =
          $senderVideoStreamEncoderPendingReconfigureSignals
        videoStreamEncoderPendingReconfigureConfigureEncoder =
          $senderVideoStreamEncoderPendingReconfigureConfigureEncoder
        videoStreamEncoderPendingReconfigureFrameInfoChange =
          $senderVideoStreamEncoderPendingReconfigureFrameInfoChange
        videoStreamEncoderPendingReconfigureSourceRestriction =
          $senderVideoStreamEncoderPendingReconfigureSourceRestriction
        videoStreamEncoderPendingReconfigureUnknown =
          $senderVideoStreamEncoderPendingReconfigureUnknown
        videoStreamEncoderPendingReconfigureLastReason =
          $senderVideoStreamEncoderPendingReconfigureLastReason
        videoStreamEncoderExpectedStartupReconfigureOnly =
          $senderVseExpectedStartupReconfigureOnly
        videoStreamEncoderMaybeRateUpdateMaxMs =
          $senderVideoStreamEncoderMaybeRateUpdateMaxMs
        videoEncoderEncodeMaxMs = $senderVideoEncoderEncodeMaxMs
        activeProcessingSplit = [ordered]@{
          dominant = $senderActiveSplitDominant
          taskPostedToTaskStartsAverageMs =
            $senderActiveTaskPostedToTaskStartsAverageMs
          taskPostedToTaskStartsMaxMs =
            $senderActiveTaskPostedToTaskStartsMaxMs
          taskStartsToAdaptationCompleteAverageMs =
            $senderActiveTaskStartsToAdaptationCompleteAverageMs
          taskStartsToAdaptationCompleteMaxMs =
            $senderActiveTaskStartsToAdaptationCompleteMaxMs
          adaptationCompleteToVseEntryAverageMs =
            $senderActiveAdaptationCompleteToVseEntryAverageMs
          adaptationCompleteToVseEntryMaxMs =
            $senderActiveAdaptationCompleteToVseEntryMaxMs
          vseEntryToEncoderTaskPostedAverageMs =
            $senderActiveVseEntryToEncoderTaskPostedAverageMs
          vseEntryToEncoderTaskPostedMaxMs =
            $senderActiveVseEntryToEncoderTaskPostedMaxMs
          encoderTaskPostedToStartedAverageMs =
            $senderActiveEncoderTaskPostedToStartedAverageMs
          encoderTaskPostedToStartedMaxMs =
            $senderActiveEncoderTaskPostedToStartedMaxMs
          encoderTaskStartsToEncodeEntryAverageMs =
            $senderActiveEncoderTaskStartsToEncodeEntryAverageMs
          encoderTaskStartsToEncodeEntryMaxMs =
            $senderActiveEncoderTaskStartsToEncodeEntryMaxMs
          encodeEntryToReturnAverageMs =
            $senderActiveEncodeEntryToReturnAverageMs
          encodeEntryToReturnMaxMs =
            $senderActiveEncodeEntryToReturnMaxMs
        }
        encodeReturnAttribution = [ordered]@{
          classification = $senderEncodeReturnAttribution
          encodeReturnTailPresent = $senderEncodeReturnTailPresent
          mfMarkersPresent = $senderMfMarkersPresent
          mfSubstagesFast = $senderMfEncoderSubstagesFast
          mfTotalMaxMs = $senderMfEncoderMaxTotalMs
          mfProcessInputMaxMs = $senderMfEncoderMaxProcessInputMs
          mfProcessOutputMaxMs = $senderMfEncoderMaxProcessOutputMs
          mfEncodedCallbackMaxMs = $senderMfEncoderMaxEncodedCallbackMs
          mfOutputFrames = $senderMfEncoderOutputFrames
          mfProcessInputSamples = $senderMfEncoderProcessInputSamples
          mfProcessOutputSamples = $senderMfEncoderProcessOutputSamples
        }
        videoStreamEncoderQueueDrops = $senderVideoStreamEncoderQueueDrops
        videoStreamEncoderOverloadDrops =
          $senderVideoStreamEncoderOverloadDrops
        videoStreamEncoderTailDominant = $senderVseTailDominant
      }
      presentationVisualMismatch = [ordered]@{
        classification = $presentationVisualMismatchClassification
        summary = $presentationVisualMismatchSummary
        next = $presentationVisualMismatchNext
        screenPresentGateSource = $receiverWindowScreenPresentGateSource
        screenPresentPass = $receiverWindowScreenPresentPass
        visualFrameMarkerSourceLinked = $receiverVisualFrameMarkerSourceLinked
        visualFrameMarkerSourceLineageReason =
          $receiverVisualFrameMarkerSourceLineageReason
        sourceFrameIdEventCount = $receiverSourceFrameIdEventCount
        previousFrameIdEventCount = $receiverPreviousFrameIdEventCount
        sourceFrameMarkerIdEventCount = $receiverSourceFrameMarkerIdEventCount
        sourceQpcEventCount = $receiverSourceQpcEventCount
        stageQpcEventCount = $receiverStageQpcEventCount
        sourceLineageEventCount = $receiverSourceLineageEventCount
        sourceLineageAvailable = $receiverSourceLineageAvailable
        visualFreshnessPass = $receiverWindowVisualFreshnessPass
        exactFreshnessPass = $receiverWindowExactFreshnessPass
        exactFreshnessMeasured = $receiverWindowExactFreshnessMeasured
        perceptualFreshnessUnhealthy =
          $receiverWindowPerceptualFreshnessUnhealthy
        receiverQualityCountersPass = $receiverQualityCountersPass
        receiverStatsFpsPass = $receiverStatsFpsPass
        receiverPresentationPass = $receiverPresentationPass
        presentationIntervalsUnhealthy =
          $receiverPresentationIntervalsUnhealthy
        frameTapPresentationUnhealthy =
          $receiverFrameTapPresentationUnhealthy
        receiverScreenPresentObserved = $receiverScreenPresentObserved
        flutterFrameGapP95Pass = $receiverFlutterFrameGapP95Pass
        flutterFrameSchedulingSpikePresent =
          $receiverFlutterFrameSchedulingSpikePresent
        flutterFrameSchedulingUnhealthy =
          $receiverFlutterFrameSchedulingUnhealthy
        perceptualUniqueFps = $receiverProbeWindowUniqueFps
        perceptualLongestStaleMs = $receiverProbeWindowLongestStaleMs
        exactUniqueFps = $receiverProbeWindowExactUniqueFps
        exactLongestStaleMs = $receiverProbeWindowExactLongestStaleMs
        sourceFrameContentMarkerRequested = [bool]$SourceFrameContentMarker
        sourceFrameContentMarkerAvailable =
          $receiverProbeWindowSourceMarkerAvailable
        sourceFrameContentMarkerPass = $receiverProbeWindowSourceMarkerPass
        sourceFrameContentMarkerDecodedFrames =
          $receiverProbeWindowSourceMarkerDecodedFrames
        sourceFrameContentMarkerMissingFrames =
          $receiverProbeWindowSourceMarkerMissingFrames
        sourceFrameContentMarkerUniqueFps =
          $receiverProbeWindowSourceMarkerUniqueFps
        sourceFrameContentMarkerLongestStaleMs =
          $receiverProbeWindowSourceMarkerLongestStaleMs
        receiverSourceFrameMarkerDecodedFrames =
          $receiverSourceFrameMarkerDecodedFrames
        receiverSourceFrameMarkerUniqueFps =
          $receiverSourceFrameMarkerUniqueFps
        receiverSourceFrameMarkerLongestStaleMs =
          $receiverSourceFrameMarkerLongestStaleMs
        receiverSourceFrameMarkerPass = $receiverSourceFrameMarkerPass
        flutterFrameGapP95Ms = $receiverWindowFlutterFrameGapP95Ms
        flutterFrameGapMaxMs = $receiverWindowFlutterFrameGapMaxMs
        flutterFrameGapsOver50Ms = $receiverWindowFlutterFrameGapsOver50Ms
        flutterFrameGapsOver100Ms = $receiverWindowFlutterFrameGapsOver100Ms
        senderDeliverySuspected = $senderDeliverySuspected
        sameHostRecorderLoadSuspected = $sameHostRecorderLoadSuspected
      }
      receiverQualityPresentationMismatch = [ordered]@{
        classification = $receiverQualityPresentationClassification
        summary = $receiverQualityPresentationSummary
        next = $receiverQualityPresentationNext
        receiverLayerHealthy = $receiverLayerHealthy
        receiverDecodedDimensionsHealthy = $receiverDecodedDimensionsHealthy
        receiverDecodedCadenceHealthy = $receiverDecodedCadenceHealthy
        receiverBitrateLow = $receiverBitrateLow
        receiverQpHigh = $receiverQpHigh
        receiverPresentationPass = $receiverPresentationPass
        receiverQualityCountersPass = $receiverQualityCountersPass
        frameTapPresentationUnhealthy =
          $receiverFrameTapPresentationUnhealthy
        receiverScreenPresentObserved = $receiverScreenPresentObserved
        flutterFrameGapP95Pass = $receiverFlutterFrameGapP95Pass
        flutterFrameSchedulingSpikePresent =
          $receiverFlutterFrameSchedulingSpikePresent
        flutterFrameSchedulingUnhealthy =
          $receiverFlutterFrameSchedulingUnhealthy
        senderDeliverySuspected = $senderDeliverySuspected
        senderDeliveryWallTailPresent = $senderDeliveryWallTailPresent
        senderVseTailPresent = $senderVseTailPresent
        senderNativeTailPresent = $senderNativeTailPresent
        layer = $receiverSimulcastLayer
        subscribedQuality = $receiverSubscribedQuality
        inboundBitrateBps = $receiverInboundBitrateBps
        averageQp = $receiverAverageQp
        decodedWidth = $receiverDecodedWidth
        decodedHeight = $receiverDecodedHeight
        renderUniqueFps = $receiverRenderUniqueFps
        decodedFpsP50 = $receiverDecodedFpsP50
        presentationP95P50Ms = $receiverFramePresentationP95GapP50Ms
        rendererCallbackToStageMs = $receiverRendererCallbackToStageMs
      }
      gates = [ordered]@{
        minUniqueFps = $MinUniqueFps
        receiverPresentationP95LimitMs = $receiverPresentationP95LimitMs
        receiverStatsFpsPass = $receiverStatsFpsPass
        receiverPresentationPass = $receiverPresentationPass
        frameTapPresentationUnhealthy =
          $receiverFrameTapPresentationUnhealthy
        receiverScreenPresentObserved = $receiverScreenPresentObserved
        flutterFrameGapP95Pass = $receiverFlutterFrameGapP95Pass
        flutterFrameSchedulingSpikePresent =
          $receiverFlutterFrameSchedulingSpikePresent
        flutterFrameSchedulingUnhealthy =
          $receiverFlutterFrameSchedulingUnhealthy
        receiverQualityCountersPass = $receiverQualityCountersPass
        receiverLayerHealthy = $receiverLayerHealthy
        receiverDecodedDimensionsHealthy = $receiverDecodedDimensionsHealthy
        receiverDecodedCadenceHealthy = $receiverDecodedCadenceHealthy
        receiverBitrateLow = $receiverBitrateLow
        receiverQpHigh = $receiverQpHigh
        senderAverageFpsLow = $senderAverageFpsLow
        senderLongGapPresent = $senderLongGapPresent
        senderNativeReadinessSpike = $senderNativeReadinessSpike
        senderQueuePressure = $senderQueuePressure
        senderDeliveryWallTailPresent = $senderDeliveryWallTailPresent
        senderVseTailPresent = $senderVseTailPresent
        senderNativeTailPresent = $senderNativeTailPresent
        senderDeliverySuspected = $senderDeliverySuspected
        receiverSourceFrameIdAvailable = $receiverSourceFrameIdAvailable
        receiverSourceLineageAvailable = $receiverSourceLineageAvailable
        receiverVisualFrameMarkerSourceLinked =
          $receiverVisualFrameMarkerSourceLinked
        inactivePreviewBypassInactive = $inactivePreviewBypassInactive
      }
      sender = [ordered]@{
        averageCaptureFps = $averageCaptureFps
        averageEncodeFps = $averageEncodeFps
        averageSendFps = $averageSendFps
        bottleneck = $bottleneckLabel
        sourceToSubmitAverageMs = $senderSourceToSubmitAverageMs
        sourceToSubmitMaxMs = $senderSourceToSubmitMaxMs
        deliveryWallAverageMs = $senderDeliveryWallAverageMs
        deliveryWallMaxMs = $senderDeliveryWallMaxMs
        deliveryWallOver2xFrames = $senderDeliveryWallOver2xFrames
        deliveryWallOver3xFrames = $senderDeliveryWallOver3xFrames
        sourceQpcMaxMs = $senderSourceQpcMaxMs
        timestampDeltaMaxMs = $senderTimestampDeltaMaxMs
        deliveryOnFrameCallAverageMs = $senderDeliveryOnFrameCallAverageMs
        deliveryOnFrameCallMaxMs = $senderDeliveryOnFrameCallMaxMs
        nativeBltToReadyAverageMs = $senderNativeBltToReadyAverageMs
        nativeBltToReadyMaxMs = $senderNativeBltToReadyMaxMs
        nativeBltSubmitMaxMs = $senderNativeBltSubmitMaxMs
        nativeConvertMaxMs = $senderNativeConvertMaxMs
        sourceToReadbackReadyMaxMs = $senderSourceToReadbackReadyMaxMs
        readbackQueueToMapMaxMs = $senderReadbackQueueToMapMaxMs
        readbackLatencyAverageMs = $senderReadbackLatencyAverageMs
        nativeNv12NotReadyPolls = $senderNativeNv12NotReadyPolls
        nativeNv12ReadyDroppedFrames = $senderNativeNv12ReadyDroppedFrames
        nativeNv12OverwrittenFrames = $senderNativeNv12OverwrittenFrames
        nativeNv12SubmittedFrames = $senderNativeNv12SubmittedFrames
        nativeNv12SuspendedAfterOnFrameBackpressure = $senderNativeNv12Suspended
        nativeNv12OnFrameBackpressureMaxMs = $senderNativeNv12BackpressureMaxMs
        nativeNv12HandoffDisabledReason = $senderNativeNv12DisabledReason
        videoStreamEncoderPostToOnFrameAverageMs =
          $senderVideoStreamEncoderPostToOnFrameAverageMs
        videoStreamEncoderPostToOnFrameMaxMs =
          $senderVideoStreamEncoderPostToOnFrameMaxMs
        videoStreamEncoderOnFrameAverageMs =
          $senderVideoStreamEncoderOnFrameAverageMs
        videoStreamEncoderOnFrameMaxMs =
          $senderVideoStreamEncoderOnFrameMaxMs
        videoStreamEncoderMaybeEncodeAverageMs =
          $senderVideoStreamEncoderMaybeEncodeAverageMs
        videoStreamEncoderMaybeEncodeMaxMs =
          $senderVideoStreamEncoderMaybeEncodeMaxMs
        videoStreamEncoderMaybePreEncodeAverageMs =
          $senderVideoStreamEncoderMaybePreEncodeAverageMs
        videoStreamEncoderMaybePreEncodeMaxMs =
          $senderVideoStreamEncoderMaybePreEncodeMaxMs
        videoStreamEncoderMaybeEncodeCallAverageMs =
          $senderVideoStreamEncoderMaybeEncodeCallAverageMs
        videoStreamEncoderMaybeEncodeCallMaxMs =
          $senderVideoStreamEncoderMaybeEncodeCallMaxMs
        videoStreamEncoderMaybeParameterUpdateAverageMs =
          $senderVideoStreamEncoderMaybeParameterUpdateAverageMs
        videoStreamEncoderMaybeParameterUpdateMaxMs =
          $senderVideoStreamEncoderMaybeParameterUpdateMaxMs
        videoStreamEncoderMaybeReconfigureAverageMs =
          $senderVideoStreamEncoderMaybeReconfigureAverageMs
        videoStreamEncoderMaybeReconfigureMaxMs =
          $senderVideoStreamEncoderMaybeReconfigureMaxMs
        videoStreamEncoderPendingReconfigureSignals =
          $senderVideoStreamEncoderPendingReconfigureSignals
        videoStreamEncoderPendingReconfigureConfigureEncoder =
          $senderVideoStreamEncoderPendingReconfigureConfigureEncoder
        videoStreamEncoderPendingReconfigureFrameInfoChange =
          $senderVideoStreamEncoderPendingReconfigureFrameInfoChange
        videoStreamEncoderPendingReconfigureSourceRestriction =
          $senderVideoStreamEncoderPendingReconfigureSourceRestriction
        videoStreamEncoderPendingReconfigureUnknown =
          $senderVideoStreamEncoderPendingReconfigureUnknown
        videoStreamEncoderPendingReconfigureLastReason =
          $senderVideoStreamEncoderPendingReconfigureLastReason
        videoStreamEncoderExpectedStartupReconfigureOnly =
          $senderVseExpectedStartupReconfigureOnly
        videoStreamEncoderMaybeRateUpdateAverageMs =
          $senderVideoStreamEncoderMaybeRateUpdateAverageMs
        videoStreamEncoderMaybeRateUpdateMaxMs =
          $senderVideoStreamEncoderMaybeRateUpdateMaxMs
        videoStreamEncoderEncodeFrameAverageMs =
          $senderVideoStreamEncoderEncodeFrameAverageMs
        videoStreamEncoderEncodeFrameMaxMs =
          $senderVideoStreamEncoderEncodeFrameMaxMs
        videoEncoderEncodeAverageMs = $senderVideoEncoderEncodeAverageMs
        videoEncoderEncodeMaxMs = $senderVideoEncoderEncodeMaxMs
        activeProcessingSplit = [ordered]@{
          dominant = $senderActiveSplitDominant
          taskPostedToTaskStartsAverageMs =
            $senderActiveTaskPostedToTaskStartsAverageMs
          taskPostedToTaskStartsMaxMs =
            $senderActiveTaskPostedToTaskStartsMaxMs
          taskStartsToAdaptationCompleteAverageMs =
            $senderActiveTaskStartsToAdaptationCompleteAverageMs
          taskStartsToAdaptationCompleteMaxMs =
            $senderActiveTaskStartsToAdaptationCompleteMaxMs
          adaptationCompleteToVseEntryAverageMs =
            $senderActiveAdaptationCompleteToVseEntryAverageMs
          adaptationCompleteToVseEntryMaxMs =
            $senderActiveAdaptationCompleteToVseEntryMaxMs
          vseEntryToEncoderTaskPostedAverageMs =
            $senderActiveVseEntryToEncoderTaskPostedAverageMs
          vseEntryToEncoderTaskPostedMaxMs =
            $senderActiveVseEntryToEncoderTaskPostedMaxMs
          encoderTaskPostedToStartedAverageMs =
            $senderActiveEncoderTaskPostedToStartedAverageMs
          encoderTaskPostedToStartedMaxMs =
            $senderActiveEncoderTaskPostedToStartedMaxMs
          encoderTaskStartsToEncodeEntryAverageMs =
            $senderActiveEncoderTaskStartsToEncodeEntryAverageMs
          encoderTaskStartsToEncodeEntryMaxMs =
            $senderActiveEncoderTaskStartsToEncodeEntryMaxMs
          encodeEntryToReturnAverageMs =
            $senderActiveEncodeEntryToReturnAverageMs
          encodeEntryToReturnMaxMs =
            $senderActiveEncodeEntryToReturnMaxMs
        }
        videoStreamEncoderTailDominant = $senderVseTailDominant
        videoStreamEncoderQueueDrops = $senderVideoStreamEncoderQueueDrops
        videoStreamEncoderOverloadDrops = $senderVideoStreamEncoderOverloadDrops
        inactiveNativeSinksRefreshed = $refreshed
        inactiveNativeSinksBypassed = $bypassed
        hostSystemCpuAverage = $hostSystemCpuAverage
        hostSystemCpuMaximum = $hostSystemCpuMaximum
        hostTargetCpuAverage = $hostTargetCpuAverage
        hostTargetCpuMaximum = $hostTargetCpuMaximum
      }
      receiver = [ordered]@{
        decodeUniqueFps = $receiverDecodeUniqueFps
        renderUniqueFps = $receiverRenderUniqueFps
        effectiveStatsFps = $receiverEffectiveStatsFps
        statsFpsGateSource = $receiverStatsFpsGateSource
        decodedFpsP50 = $receiverDecodedFpsP50
        decodedFpsAverage = $receiverDecodedFpsAverage
        receivedFpsP50 = $receiverReceivedFpsP50
        receivedFpsAverage = $receiverReceivedFpsAverage
        effectiveFramePresentationP95GapMs =
          $receiverEffectiveFramePresentationP95GapMs
        presentationGateSource = $receiverPresentationGateSource
        framePresentationP95GapP50Ms = $receiverFramePresentationP95GapP50Ms
        framePresentationP95GapAverageMs =
          $receiverFramePresentationP95GapAverageMs
        framePresentationMaxGapMs = $receiverFramePresentationMaxGapMs
        inboundBitrateBps = $receiverInboundBitrateBps
        averageQp = $receiverAverageQp
        subscribedQuality = $receiverSubscribedQuality
        simulcastLayer = $receiverSimulcastLayer
        receivedWidth = $receiverReceivedWidth
        receivedHeight = $receiverReceivedHeight
        decodedWidth = $receiverDecodedWidth
        decodedHeight = $receiverDecodedHeight
        renderedWidth = $receiverRenderedWidth
        renderedHeight = $receiverRenderedHeight
        rendererAttached = $receiverRendererAttached
        rendererVisible = $receiverRendererVisible
        upscalingLowerLayerSuspected = $receiverUpscalingLowerLayerSuspected
        adaptiveStreamLowLayerSuspected = $receiverAdaptiveStreamLowLayerSuspected
        pliCount = $receiverPliCount
        firCount = $receiverFirCount
        nackCount = $receiverNackCount
        droppedOrReplacedTextureUpdates =
          $receiverDroppedOrReplacedTextureUpdates
        latestTargetStage = $receiverLatestTargetStage
        stageSource = $receiverStageSource
        deepestObservedStage = $receiverDeepestObservedStage
        remoteDecodeEventCount = $receiverRemoteDecodeEventCount
        remoteRendererCallbackEventCount =
          $receiverRemoteRendererCallbackEventCount
        remoteTextureReadyEventCount = $receiverRemoteTextureReadyEventCount
        remoteUiPaintEventCount = $receiverRemoteUiPaintEventCount
        remoteScreenPresentEventCount = $receiverRemoteScreenPresentEventCount
        sourceLineageEventCount = $receiverSourceLineageEventCount
        sourceFrameIdEventCount = $receiverSourceFrameIdEventCount
        sourceFrameMarkerIdEventCount = $receiverSourceFrameMarkerIdEventCount
        sourceQpcEventCount = $receiverSourceQpcEventCount
        stageQpcEventCount = $receiverStageQpcEventCount
        sourceFrameIdAvailable = $receiverSourceFrameIdAvailable
        sourceLineageAvailable = $receiverSourceLineageAvailable
        sourceLineageReason = $receiverSourceLineageReason
        visualFrameMarkerSourceLinked = $receiverVisualFrameMarkerSourceLinked
        visualFrameMarkerSourceLineageReason =
          $receiverVisualFrameMarkerSourceLineageReason
        stageObservedGapMs = $receiverStageObservedGapMs
        rendererCallbackToStageMs = $receiverRendererCallbackToStageMs
        receiverWindowFlutterFrameCount = $receiverWindowFlutterFrameCount
        receiverWindowFlutterFrameGapP95Ms =
          $receiverWindowFlutterFrameGapP95Ms
        receiverWindowFlutterFrameGapMaxMs =
          $receiverWindowFlutterFrameGapMaxMs
        receiverWindowFlutterFrameGapsOver50Ms =
          $receiverWindowFlutterFrameGapsOver50Ms
        receiverWindowFlutterFrameGapsOver100Ms =
          $receiverWindowFlutterFrameGapsOver100Ms
      }
    }
    evidence = [ordered]@{
      preflightMean = $preflightStats.mean
      preflightContrast = $preflightStats.contrast
      preflightStdDev = $preflightStats.stdDev
      selfViewCropGate = $selfViewCropGate
      selfViewCropFreshnessPass = $selfViewCropFreshnessPass
      selfViewCropStatus = $visualStatus
      selfViewCropUniqueFps = $uniqueFps
      selfViewCropLongestStaleMs = $longestStaleMs
      selfViewCropMeasurementExitCode = $visualExitCode
      visualStatus = $visualStatus
      uniqueFps = $uniqueFps
      longestStaleMs = $longestStaleMs
      averageCaptureFps = $averageCaptureFps
      averageEncodeFps = $averageEncodeFps
      averageSendFps = $averageSendFps
      sourceMode = $sourceMode
      bottleneck = $bottleneckLabel
      broadcasterSamples = $broadcasterSamples
      inactiveNativeSinksRefreshed = $refreshed
      inactiveNativeSinksBypassed = $bypassed
      receiverProbeEnabled = [bool]$ReceiverProbeEnabled
      receiverProbeMode = $ReceiverProbeMode
      receiverProbeFrameDiagnosticsModeRequested = $ReceiverProbeFrameDiagnosticsMode
      receiverProbeFrameDiagnosticsModeReported =
        $receiverProbeRuntimeFrameDiagnosticsMode
      receiverProbeStatsOnlyCompleted = $receiverProbeStatsOnlyCompleted
      receiverProbeVideoFrameTrackingRequested = $videoFrameTrackingIdRequested
      receiverProbeVideoFrameTrackingEnvApplied = $videoFrameTrackingIdEnvChanged
      receiverProbeExternal = $externalReceiverProbeRequested
      receiverProbeControlPipeSet = -not [string]::IsNullOrWhiteSpace($receiverProbeControlPipe)
      receiverProbeMonitorIndex = $ReceiverProbeMonitorIndex
      receiverProbeVisualFrameMarker = [bool]$ReceiverProbeVisualFrameMarker
      sourceFrameContentMarker = [bool]$SourceFrameContentMarker
      sourceFrameContentMarkerEnvApplied = $sourceFrameVisualMarkerEnvChanged
      receiverProbeWindowSourceFrameContentMarkerAvailable =
        $receiverProbeWindowSourceMarkerAvailable
      receiverProbeWindowSourceFrameContentMarkerPass =
        $receiverProbeWindowSourceMarkerPass
      receiverProbeWindowSourceFrameContentMarkerDecodedFrames =
        $receiverProbeWindowSourceMarkerDecodedFrames
      receiverProbeWindowSourceFrameContentMarkerMissingFrames =
        $receiverProbeWindowSourceMarkerMissingFrames
      receiverProbeWindowSourceFrameContentMarkerUniqueFps =
        $receiverProbeWindowSourceMarkerUniqueFps
      receiverProbeWindowSourceFrameContentMarkerLongestStaleMs =
        $receiverProbeWindowSourceMarkerLongestStaleMs
      receiverSourceLineageEventCount = $receiverSourceLineageEventCount
      receiverSourceFrameIdEventCount = $receiverSourceFrameIdEventCount
      receiverPreviousFrameIdEventCount = $receiverPreviousFrameIdEventCount
      receiverSourceFrameMarkerIdEventCount =
        $receiverSourceFrameMarkerIdEventCount
      receiverSourceFrameMarkerDecodedFrames =
        $receiverSourceFrameMarkerDecodedFrames
      receiverSourceFrameMarkerUniqueFps = $receiverSourceFrameMarkerUniqueFps
      receiverSourceFrameMarkerLongestStaleMs =
        $receiverSourceFrameMarkerLongestStaleMs
      receiverSourceFrameMarkerPass = $receiverSourceFrameMarkerPass
      receiverSourceQpcEventCount = $receiverSourceQpcEventCount
      receiverStageQpcEventCount = $receiverStageQpcEventCount
      receiverSourceFrameIdAvailable = $receiverSourceFrameIdAvailable
      receiverSourceLineageAvailable = $receiverSourceLineageAvailable
      receiverSourceLineageReason = $receiverSourceLineageReason
      receiverVisualFrameMarkerSourceLinked = $receiverVisualFrameMarkerSourceLinked
      receiverVisualFrameMarkerSourceLineageReason =
        $receiverVisualFrameMarkerSourceLineageReason
      receiverProbeWindowPlacementStatus = if ($null -ne $receiverProbeWindowPlacement) {
        $receiverProbeWindowPlacement.status
      } else {
        ''
      }
      receiverProbeWindowRecordingRect = $receiverProbeWindowRecordRect
      receiverProbeWindowActiveSegmentStartSeconds = $receiverProbeWindowActiveSegmentStartSeconds
      receiverProbeWindowActiveSegmentSeconds = $receiverProbeWindowActiveSegmentSeconds
      receiverProbeWindowVisualStatus = $receiverProbeWindowVisualStatus
      receiverProbeWindowUniqueFps = $receiverProbeWindowUniqueFps
      receiverProbeWindowLongestStaleMs = $receiverProbeWindowLongestStaleMs
      receiverProbeWindowExactUniqueFps = $receiverProbeWindowExactUniqueFps
      receiverProbeWindowExactDuplicateFrames = $receiverProbeWindowExactDuplicateFrames
      receiverProbeWindowExactLongestStaleMs = $receiverProbeWindowExactLongestStaleMs
      receiverWindowVisualGateRequired = $receiverWindowVisualGateRequired
      receiverWindowScreenPresentGateSource = $receiverWindowScreenPresentGateSource
      receiverWindowScreenPresentPass = $receiverWindowScreenPresentPass
      receiverWindowVisualFreshnessPass = $receiverWindowVisualFreshnessPass
      receiverWindowExactFreshnessPass = $receiverWindowExactFreshnessPass
      receiverProbeWindowMeasurementExitCode = $receiverProbeWindowVisualExitCode
      receiverProbeStatus = $receiverProbeStatus
      receiverProbeBlockingReason = $receiverProbeBlockingReason
      receiverProbeExitCode = $receiverProbeExitCode
      receiverDecodeUniqueFps = $receiverDecodeUniqueFps
      receiverRenderUniqueFps = $receiverRenderUniqueFps
      localPreviewUniqueFps = $localPreviewUniqueFps
      receiverStatsFps = $receiverStatsFps
      receiverReceivedFps = $receiverReceivedFps
      receiverReceivedFpsP50 = $receiverReceivedFpsP50
      receiverReceivedFpsAverage = $receiverReceivedFpsAverage
      receiverDecodedFps = $receiverDecodedFps
      receiverDecodedFpsP50 = $receiverDecodedFpsP50
      receiverDecodedFpsAverage = $receiverDecodedFpsAverage
      receiverRenderedFps = $receiverRenderedFps
      receiverRenderedFpsP50 = $receiverRenderedFpsP50
      receiverRenderedFpsAverage = $receiverRenderedFpsAverage
      receiverEffectiveStatsFps = $receiverEffectiveStatsFps
      receiverStatsFpsGateSource = $receiverStatsFpsGateSource
      receiverStatsSampleWindowMs = $receiverStatsSampleWindowMs
      receiverStatsFpsPass = $receiverStatsFpsPass
      receiverFramePresentationP95GapMs = $receiverFramePresentationP95GapMs
      receiverFramePresentationP95GapP50Ms = $receiverFramePresentationP95GapP50Ms
      receiverFramePresentationP95GapAverageMs = $receiverFramePresentationP95GapAverageMs
      receiverEffectiveFramePresentationP95GapMs = $receiverEffectiveFramePresentationP95GapMs
      receiverPresentationGateSource = $receiverPresentationGateSource
      receiverFramePresentationMaxGapMs = $receiverFramePresentationMaxGapMs
      receiverPresentationP95LimitMs = $receiverPresentationP95LimitMs
      receiverPresentationPass = $receiverPresentationPass
      receiverQualityCountersPass = $receiverQualityCountersPass
      receiverInboundBitrateBps = $receiverInboundBitrateBps
      receiverAverageQp = $receiverAverageQp
      receiverSubscribedQuality = $receiverSubscribedQuality
      receiverSimulcastLayer = $receiverSimulcastLayer
      receiverReceivedWidth = $receiverReceivedWidth
      receiverReceivedHeight = $receiverReceivedHeight
      receiverDecodedWidth = $receiverDecodedWidth
      receiverDecodedHeight = $receiverDecodedHeight
      receiverRenderedWidth = $receiverRenderedWidth
      receiverRenderedHeight = $receiverRenderedHeight
      receiverRendererAttached = $receiverRendererAttached
      receiverRendererVisible = $receiverRendererVisible
      receiverDecodeFreshnessSource = $receiverDecodeFreshnessSource
      receiverRenderFreshnessSource = $receiverRenderFreshnessSource
      localPreviewFreshnessSource = $localPreviewFreshnessSource
      receiverLatestTargetStage = $receiverLatestTargetStage
      receiverStageSource = $receiverStageSource
      receiverDeepestObservedStage = $receiverDeepestObservedStage
      receiverRemoteDecodeEventCount = $receiverRemoteDecodeEventCount
      receiverRemoteRendererCallbackEventCount =
        $receiverRemoteRendererCallbackEventCount
      receiverRemoteTextureReadyEventCount = $receiverRemoteTextureReadyEventCount
      receiverRemoteUiPaintEventCount = $receiverRemoteUiPaintEventCount
      receiverRemoteScreenPresentEventCount =
        $receiverRemoteScreenPresentEventCount
      receiverStageObservedGapMs = $receiverStageObservedGapMs
      receiverRendererCallbackToStageMs = $receiverRendererCallbackToStageMs
      receiverWindowFlutterFrameCount = $receiverWindowFlutterFrameCount
      receiverWindowFlutterFrameGapP95Ms =
        $receiverWindowFlutterFrameGapP95Ms
      receiverWindowFlutterFrameGapMaxMs =
        $receiverWindowFlutterFrameGapMaxMs
      receiverWindowFlutterFrameGapsOver50Ms =
        $receiverWindowFlutterFrameGapsOver50Ms
      receiverWindowFlutterFrameGapsOver100Ms =
        $receiverWindowFlutterFrameGapsOver100Ms
      correlationClassification = $correlationClassification
      correlationSummary = $correlationSummary
      correlationNext = $correlationNext
      senderPresentationTailCorrelationClassification =
        $senderPresentationTailClassification
      senderPresentationTailCorrelationSummary =
        $senderPresentationTailSummary
      senderPresentationTailCorrelationNext =
        $senderPresentationTailNext
      senderDeliveryWallTailPresent = $senderDeliveryWallTailPresent
      senderVseTailPresent = $senderVseTailPresent
      senderNativeTailPresent = $senderNativeTailPresent
      presentationVisualMismatchClassification =
        $presentationVisualMismatchClassification
      presentationVisualMismatchSummary = $presentationVisualMismatchSummary
      presentationVisualMismatchNext = $presentationVisualMismatchNext
      receiverQualityPresentationClassification =
        $receiverQualityPresentationClassification
      receiverQualityPresentationSummary =
        $receiverQualityPresentationSummary
      receiverQualityPresentationNext = $receiverQualityPresentationNext
      receiverWindowPerceptualFreshnessUnhealthy =
        $receiverWindowPerceptualFreshnessUnhealthy
      receiverWindowExactFreshnessMeasured =
        $receiverWindowExactFreshnessMeasured
      receiverPresentationIntervalsUnhealthy =
        $receiverPresentationIntervalsUnhealthy
      sameHostRecorderLoadSuspected = $sameHostRecorderLoadSuspected
      correlationWindowAlignmentAvailable =
        Get-JsonProperty $correlationWindows 'available'
      correlationWindowAlignmentReason =
        Get-JsonString $correlationWindows 'reason'
      freshnessEvidenceSource = $freshnessEvidenceSource
    }
  }

  $jsonOut = Join-Path $runDirectory "$outputBaseName.json"
  $mdOut = Join-Path $runDirectory "$outputBaseName.md"
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonOut -Encoding UTF8
  $markdownTitle = if ($sourceOverrideRequested) {
    '# Source Live Call Freshness'
  } else {
    '# Synthetic Live Call Freshness'
  }
  $sourceLine = if ($sourceOverrideRequested) {
    "- Source override: PID $($sourceOverrideProcess.Id) '$sourceRequestTitle'"
  } elseif ($null -ne $captureTargetProcess) {
    "- Synthetic capture target PID: $($captureTargetProcess.Id)"
  } elseif ($UseAppLaunchedCaptureTarget) {
    '- Synthetic capture target PID: app-launched by Inter Galactic'
  } else {
    '- Synthetic capture target PID: unavailable'
  }
  $scopeLine = if ($sourceOverrideRequested) {
    'This helper validates receiver/local-preview frame-hash freshness with an existing source process. The self-view crop is recorded as a retired diagnostic only.'
  } else {
    'This helper validates receiver/local-preview frame-hash freshness with a synthetic high-motion capture target before BG3 is requested again. The self-view crop is recorded as a retired diagnostic only.'
  }
  $visualReportPath = if (-not [string]::IsNullOrWhiteSpace($visualDirectory)) {
    Join-Path $visualDirectory 'visual-freshness.md'
  } else {
    ''
  }
  $correlationWindowLines = @()
  $correlationWindowsAvailable =
    [bool](Get-JsonProperty $correlationWindows 'available')
  if ($correlationWindowsAvailable) {
    foreach ($row in @((Get-JsonProperty $correlationWindows 'windows'))) {
      $senderWindow = Get-JsonProperty $row 'sender'
      $receiverWindow = Get-JsonProperty $row 'receiver'
      $receiverDecoded = Get-JsonProperty $receiverWindow 'decodedFps'
      $receiverUnique = Get-JsonProperty $receiverWindow 'uniqueFps'
      $receiverPresentation = Get-JsonProperty $receiverWindow 'presentationP95GapMs'
      $receiverPresentationMax = Get-JsonProperty $receiverWindow 'presentationMaxGapMs'
      $receiverCallbackToStage =
        Get-JsonProperty $receiverWindow 'rendererCallbackToStageMs'
      $correlationWindowLines +=
        "- Window $(Get-JsonString $row 'label'): $(Get-JsonString $row 'classification'); sender cap/enc/send $(Get-JsonDouble $senderWindow 'averageCaptureFps') / $(Get-JsonDouble $senderWindow 'averageEncodeFps') / $(Get-JsonDouble $senderWindow 'averageSendFps') FPS; sender max delivery/source/readback $(Get-JsonDouble $senderWindow 'maxDeliveryWallDeltaMs') / $(Get-JsonDouble $senderWindow 'maxSourceToSubmitMs') / $(Get-JsonDouble $senderWindow 'maxReadbackQueueToMapMs') ms; receiver active events $(Get-JsonInt $receiverWindow 'activeEventCount'); decoded p50 $(Get-JsonDouble $receiverDecoded 'p50') FPS; unique p50 $(Get-JsonDouble $receiverUnique 'p50') FPS; frame-tap presentation p95 p50/max $(Get-JsonDouble $receiverPresentation 'p50') / $(Get-JsonDouble $receiverPresentation 'max') ms; frame-tap presentation max-gap max $(Get-JsonDouble $receiverPresentationMax 'max') ms; renderer-callback-to-stage p50/max $(Get-JsonDouble $receiverCallbackToStage 'p50') / $(Get-JsonDouble $receiverCallbackToStage 'max') ms"
    }
  } else {
    $correlationWindowLines +=
      "- Window alignment: unavailable ($(Get-JsonString $correlationWindows 'reason'))"
  }
  $senderPresentationCoupledWindows = ConvertTo-CompactList @(
    Get-JsonProperty $senderPresentationTailCorrelation 'coupledWindows'
  )
  $senderPresentationReceiverOnlyWindows = ConvertTo-CompactList @(
    Get-JsonProperty $senderPresentationTailCorrelation 'receiverOnlyWindows'
  )
  $senderPresentationSenderOnlyWindows = ConvertTo-CompactList @(
    Get-JsonProperty $senderPresentationTailCorrelation 'senderOnlyWindows'
  )
  $senderPresentationDominantTailSignals = ConvertTo-CompactList @(
    Get-JsonProperty $senderPresentationTailCorrelation 'dominantTailSignals'
  )

  @(
    $markdownTitle
    ''
    "Status: $status"
    ''
    '## Evidence'
    ''
    "- Verified app window: $($windowRect.HwndDecimal) '$($windowRect.Title)'"
    $sourceLine
    "- Preflight frame mean/contrast/stdDev: $($preflightStats.mean) / $($preflightStats.contrast) / $($preflightStats.stdDev)"
    "- Self-view crop gate: $selfViewCropGate"
    "- Self-view crop unique FPS (diagnostic only): $uniqueFps"
    "- Self-view crop longest stale run (diagnostic only): $longestStaleMs ms"
    "- Freshness evidence source: $freshnessEvidenceSource"
    "- Stream-test capture/encode/send FPS: $averageCaptureFps / $averageEncodeFps / $averageSendFps"
    "- Source mode: $sourceMode"
    "- Bottleneck: $bottleneckLabel"
    "- VideoBroadcaster samples: $broadcasterSamples"
    "- Inactive native sinks refreshed/bypassed: $refreshed / $bypassed"
    "- Receiver probe: enabled=$([bool]$ReceiverProbeEnabled) mode=$ReceiverProbeMode status=$receiverProbeStatus"
    "- Receiver probe frame diagnostics: requested=$ReceiverProbeFrameDiagnosticsMode reported=$receiverProbeRuntimeFrameDiagnosticsMode statsOnlyCompleted=$receiverProbeStatsOnlyCompleted"
    "- Receiver probe video frame tracking: requested=$videoFrameTrackingIdRequested envApplied=$videoFrameTrackingIdEnvChanged"
    "- Receiver probe monitor index: $ReceiverProbeMonitorIndex"
    "- Receiver probe visual frame marker: $([bool]$ReceiverProbeVisualFrameMarker)"
    "- Receiver source-frame content marker: requested=$([bool]$SourceFrameContentMarker) envApplied=$sourceFrameVisualMarkerEnvChanged available=$receiverProbeWindowSourceMarkerAvailable pass=$receiverProbeWindowSourceMarkerPass decoded=$receiverProbeWindowSourceMarkerDecodedFrames missing=$receiverProbeWindowSourceMarkerMissingFrames uniqueFPS=$receiverProbeWindowSourceMarkerUniqueFps longestStale=$receiverProbeWindowSourceMarkerLongestStaleMs ms"
    "- Receiver native source marker: marker_id_events=$receiverSourceFrameMarkerIdEventCount; decoded=$receiverSourceFrameMarkerDecodedFrames; uniqueFPS=$receiverSourceFrameMarkerUniqueFps; longestStale=$receiverSourceFrameMarkerLongestStaleMs ms; pass=$receiverSourceFrameMarkerPass"
    "- Receiver source lineage: frame_id events=$receiverSourceFrameIdEventCount; previous_frame_id events=$receiverPreviousFrameIdEventCount; marker_id events=$receiverSourceFrameMarkerIdEventCount; source_qpc events=$receiverSourceQpcEventCount; stage_qpc events=$receiverStageQpcEventCount; complete=$receiverSourceLineageAvailable; reason=$receiverSourceLineageReason"
    "- Receiver visual marker source-linked: $receiverVisualFrameMarkerSourceLinked ($receiverVisualFrameMarkerSourceLineageReason)"
    "- Receiver probe window placement status: $(if ($null -ne $receiverProbeWindowPlacement) { $receiverProbeWindowPlacement.status } else { 'not_observed' })"
    "- Receiver probe window recording: $receiverProbeWindowVideoFull"
    "- Receiver screen-present gate: $receiverWindowScreenPresentPass via $receiverWindowScreenPresentGateSource"
    "- Receiver probe window unique FPS (diagnostic only): $receiverProbeWindowUniqueFps"
    "- Receiver probe window longest stale run (diagnostic only): $receiverProbeWindowLongestStaleMs ms"
    "- Receiver probe window exact unique FPS: $receiverProbeWindowExactUniqueFps"
    "- Receiver probe window exact duplicate frames: $receiverProbeWindowExactDuplicateFrames"
    "- Receiver probe window exact longest stale run: $receiverProbeWindowExactLongestStaleMs ms"
    "- BG3 rotation delayed until receiver window placement: $([bool]($StartBg3CameraRotation -and $externalReceiverProbeRequested))"
    "- BG3 focus reassertions during run: $($bg3FocusReassertions.Count)"
    "- Receiver decode unique FPS: $receiverDecodeUniqueFps"
    "- Local preview unique FPS: $localPreviewUniqueFps"
    "- Receiver render unique FPS: $receiverRenderUniqueFps"
    "- Receiver stats FPS / frame-tap presentation p95: $receiverStatsFps / $receiverFramePresentationP95GapMs ms"
    "- Receiver received/decoded/rendered FPS: $receiverReceivedFps / $receiverDecodedFps / $receiverRenderedFps"
    "- Receiver received/decoded/rendered FPS p50: $receiverReceivedFpsP50 / $receiverDecodedFpsP50 / $receiverRenderedFpsP50"
    "- Receiver decoded FPS average: $receiverDecodedFpsAverage"
    "- Receiver frame-tap presentation p95 p50/avg: $receiverFramePresentationP95GapP50Ms / $receiverFramePresentationP95GapAverageMs ms"
    "- Receiver stats gate source/effective FPS/window: $receiverStatsFpsGateSource / $receiverEffectiveStatsFps / $receiverStatsSampleWindowMs ms"
    "- Receiver frame-tap presentation gate source/effective p95: $receiverPresentationGateSource / $receiverEffectiveFramePresentationP95GapMs ms"
    "- Receiver quality counters pass: $receiverQualityCountersPass"
    "- Receiver decode freshness source: $receiverDecodeFreshnessSource"
    "- Local preview freshness source: $localPreviewFreshnessSource"
    "- Receiver render freshness source: $receiverRenderFreshnessSource"
    "- Receiver latest target stage/source: $receiverLatestTargetStage / $receiverStageSource"
    "- Receiver deepest observed stage: $receiverDeepestObservedStage"
    "- Receiver presentation stage counts: remote_decode=$receiverRemoteDecodeEventCount; remote_renderer_callback=$receiverRemoteRendererCallbackEventCount; remote_texture_ready=$receiverRemoteTextureReadyEventCount; remote_ui_paint=$receiverRemoteUiPaintEventCount; remote_screen_present=$receiverRemoteScreenPresentEventCount"
    "- Receiver stage timing: observed gap $receiverStageObservedGapMs ms; renderer-callback-to-stage $receiverRendererCallbackToStageMs ms"
    "- Receiver Flutter frame gaps: frames=$receiverWindowFlutterFrameCount; p95=$receiverWindowFlutterFrameGapP95Ms ms; max=$receiverWindowFlutterFrameGapMaxMs ms; >50ms=$receiverWindowFlutterFrameGapsOver50Ms; >100ms=$receiverWindowFlutterFrameGapsOver100Ms"
    "- Receiver presentation scheduling split: screen_present_observed=$receiverScreenPresentObserved; frame_tap_red=$receiverFrameTapPresentationUnhealthy; flutter_p95_pass=$receiverFlutterFrameGapP95Pass; flutter_spikes=$receiverFlutterFrameSchedulingSpikePresent; flutter_unhealthy=$receiverFlutterFrameSchedulingUnhealthy"
    "- Recorder capture mode: $recordingCaptureMode (requested $RecordingCaptureMode)"
    "- Recorder codec: $recordingCodec (requested $RecordingVideoCodec)"
    ''
    '## Sender/Receiver Correlation'
    ''
    "- Classification: $correlationClassification"
    "- Summary: $correlationSummary"
    "- Sender/presentation window split: $senderPresentationTailClassification"
    "- Sender/presentation summary: $senderPresentationTailSummary"
    "- Sender/presentation windows: coupled=$senderPresentationCoupledWindows; receiver-only=$senderPresentationReceiverOnlyWindows; sender-only=$senderPresentationSenderOnlyWindows"
    "- Dominant sender window tails: $senderPresentationDominantTailSignals"
    "- Global sender tail flags: delivery=$senderDeliveryWallTailPresent; native=$senderNativeTailPresent; VSE=$senderVseTailPresent; queue=$senderQueuePressure"
    "- Presentation/visual split: $presentationVisualMismatchClassification"
    "- Presentation/visual summary: $presentationVisualMismatchSummary"
    "- Receiver quality/presentation split: $receiverQualityPresentationClassification"
    "- Receiver quality/presentation summary: $receiverQualityPresentationSummary"
    "- Screen-present/perceptual: gate $receiverWindowScreenPresentPass via $receiverWindowScreenPresentGateSource; marker source-linked=$receiverVisualFrameMarkerSourceLinked; source-marker FPS/stale $receiverProbeWindowSourceMarkerUniqueFps / $receiverProbeWindowSourceMarkerLongestStaleMs ms; perceptual FPS/stale $receiverProbeWindowUniqueFps / $receiverProbeWindowLongestStaleMs ms; exact full-frame FPS/stale $receiverProbeWindowExactUniqueFps / $receiverProbeWindowExactLongestStaleMs ms"
    "- Presentation intervals: frame-tap p95 pass=$receiverPresentationPass; Flutter frame gaps p95/max $receiverWindowFlutterFrameGapP95Ms / $receiverWindowFlutterFrameGapMaxMs ms; >50ms/$($receiverWindowFlutterFrameGapsOver50Ms); >100ms/$($receiverWindowFlutterFrameGapsOver100Ms)"
    "- Same-host recorder load suspected: $sameHostRecorderLoadSuspected"
    "- Sender gaps: source-to-submit max $senderSourceToSubmitMaxMs ms; delivery-wall max $senderDeliveryWallMaxMs ms; source-QPC max $senderSourceQpcMaxMs ms"
    "- Sender native readiness: NV12 BLT-to-ready max $senderNativeBltToReadyMaxMs ms; convert max $senderNativeConvertMaxMs ms; readback queue-to-map max $senderReadbackQueueToMapMaxMs ms; suspended=$senderNativeNv12Suspended reason=$senderNativeNv12DisabledReason"
    "- Sender WebRTC queue: VSE post-to-OnFrame max $senderVideoStreamEncoderPostToOnFrameMaxMs ms; VSE OnFrame max $senderVideoStreamEncoderOnFrameMaxMs ms; video-encoder encode max $senderVideoEncoderEncodeMaxMs ms; queue/overload drops $senderVideoStreamEncoderQueueDrops / $senderVideoStreamEncoderOverloadDrops"
    "- Sender VSE split: dominant=$senderVseTailDominant; maybe pre-encode/reconfigure/rate-update/encode-call max $senderVideoStreamEncoderMaybePreEncodeMaxMs / $senderVideoStreamEncoderMaybeReconfigureMaxMs / $senderVideoStreamEncoderMaybeRateUpdateMaxMs / $senderVideoStreamEncoderMaybeEncodeCallMaxMs ms"
    "- Sender active split: dominant=$senderActiveSplitDominant; task-post/start max $senderActiveTaskPostedToTaskStartsMaxMs ms; start/adapt max $senderActiveTaskStartsToAdaptationCompleteMaxMs ms; adapt/VSE max $senderActiveAdaptationCompleteToVseEntryMaxMs ms; VSE/encoder-post max $senderActiveVseEntryToEncoderTaskPostedMaxMs ms; encoder-post/start max $senderActiveEncoderTaskPostedToStartedMaxMs ms; encoder-start/encode-entry max $senderActiveEncoderTaskStartsToEncodeEntryMaxMs ms; encode-entry/return max $senderActiveEncodeEntryToReturnMaxMs ms"
    "- Sender encode-return attribution: $senderEncodeReturnAttribution; MF total/process-input/process-output/callback max $senderMfEncoderMaxTotalMs / $senderMfEncoderMaxProcessInputMs / $senderMfEncoderMaxProcessOutputMs / $senderMfEncoderMaxEncodedCallbackMs ms; MF output frames=$senderMfEncoderOutputFrames samples=$senderMfEncoderProcessInputSamples/$senderMfEncoderProcessOutputSamples"
    "- Sender VSE reconfigure causes: signals=$senderVideoStreamEncoderPendingReconfigureSignals; configure=$senderVideoStreamEncoderPendingReconfigureConfigureEncoder; frame-info=$senderVideoStreamEncoderPendingReconfigureFrameInfoChange; source-restriction=$senderVideoStreamEncoderPendingReconfigureSourceRestriction; unknown=$senderVideoStreamEncoderPendingReconfigureUnknown; last=$senderVideoStreamEncoderPendingReconfigureLastReason; expected-startup-only=$senderVseExpectedStartupReconfigureOnly"
    "- Receiver boundary: decoded FPS p50 $receiverDecodedFpsP50; render unique FPS $receiverRenderUniqueFps; frame-tap presentation p95 p50 $receiverFramePresentationP95GapP50Ms ms; layer $receiverSubscribedQuality/$receiverSimulcastLayer; decoded ${receiverDecodedWidth}x${receiverDecodedHeight}; bitrate $receiverInboundBitrateBps bps; QP $receiverAverageQp"
    "- Host/load caveat: system CPU avg/max $hostSystemCpuAverage / $hostSystemCpuMaximum%; BG3 CPU avg/max $hostTargetCpuAverage / $hostTargetCpuMaximum%; inactive native sinks refreshed/bypassed $refreshed / $bypassed"
    "- Next: $correlationNext"
    "- Sender/presentation next: $senderPresentationTailNext"
    "- Presentation/visual next: $presentationVisualMismatchNext"
    "- Receiver quality/presentation next: $receiverQualityPresentationNext"
    ''
    '### Window Alignment'
    ''
    $correlationWindowLines
    ''
    '## Artifacts'
    ''
    "- Preflight frame: $preflightFrame"
    "- Direct tight stream recording: $tightVideoFull"
    "- Active tight stream crop: $tightVideo"
    "- Visual freshness report: $visualReportPath"
    "- Receiver probe window active recording: $receiverProbeWindowVideo"
    "- Receiver probe window visual freshness report: $receiverProbeWindowVisualReportPath"
    "- Stream-test report: $reportMdPath"
    "- Receiver probe summary: $receiverProbeSummaryPath"
    "- Receiver probe window placement: $receiverProbeWindowPlacementPath"
    ''
    $scopeLine
  ) | Set-Content -LiteralPath $mdOut -Encoding UTF8

  if ($AsJson) {
    $result | ConvertTo-Json -Depth 20
  } else {
    Write-Host "Live call freshness report: $mdOut"
    Write-Host "Live call freshness status: $status"
    Write-Host "Self-view crop unique FPS (diagnostic only): $uniqueFps"
  }

  if ($status -like 'failed_*') {
    exit 1
  }
} finally {
  if ($bg3RotationStarted -and
    $sourceOverrideRequested -and
    $null -ne $sourceOverrideProcess -and
    [string]::IsNullOrWhiteSpace($bg3RotationStopJson)) {
    try {
      $bg3RotationStopJson = Join-Path $runDirectory 'bg3-camera-rotation-stop.json'
      Invoke-Bg3CameraRotationHotkey `
        -WorkspaceRoot $workspaceRoot `
        -ProcessId $sourceOverrideProcess.Id `
        -Action 'Stop' `
        -OutputPath $bg3RotationStopJson
    } catch {
    }
  }
  if ($null -ne $recording) {
    try {
      if (-not $recording.Process.HasExited) {
        $recording.Process.Kill()
      }
    } catch {
    }
  }
  if ($null -ne $receiverProbeWindowRecording) {
    try {
      if (-not $receiverProbeWindowRecording.Process.HasExited) {
        $receiverProbeWindowRecording.Process.Kill()
      }
    } catch {
    }
  }
  if ($externalReceiverProbeStarted -and $null -ne $externalReceiverProbeProcess) {
    try {
      $externalReceiverProbeProcess.Refresh()
      if (-not $externalReceiverProbeProcess.HasExited) {
        Stop-ProcessTree -RootProcessId $externalReceiverProbeProcess.Id
      }
    } catch {
    }
  }
  if ($startedProcess -and -not $KeepAppOpen -and $null -ne $appProcess) {
    try {
      $refreshedProcess = Get-Process -Id $appProcess.Id -ErrorAction SilentlyContinue
      if ($null -ne $refreshedProcess -and -not $refreshedProcess.HasExited) {
        Stop-Process -Id $appProcess.Id -Force
      }
    } catch {
    }
  }
  if ($null -ne $captureTargetProcess) {
    try {
      $refreshedTarget = Get-Process -Id $captureTargetProcess.Id -ErrorAction SilentlyContinue
      if ($null -ne $refreshedTarget -and -not $refreshedTarget.HasExited) {
        Stop-Process -Id $captureTargetProcess.Id -Force
      }
    } catch {
    }
  }
  if ($videoFrameTrackingIdEnvChanged) {
    if ($null -eq $previousVideoFrameTrackingIdEnv) {
      Remove-Item Env:\INTERGALACTIC_VIDEO_FRAME_TRACKING_ID -ErrorAction SilentlyContinue
    } else {
      $env:INTERGALACTIC_VIDEO_FRAME_TRACKING_ID = $previousVideoFrameTrackingIdEnv
    }
  }
  if ($sourceFrameVisualMarkerEnvChanged) {
    if ($null -eq $previousSourceFrameVisualMarkerEnv) {
      Remove-Item Env:\INTERGALACTIC_GAME_CAPTURE_SOURCE_FRAME_VISUAL_MARKER -ErrorAction SilentlyContinue
    } else {
      $env:INTERGALACTIC_GAME_CAPTURE_SOURCE_FRAME_VISUAL_MARKER = $previousSourceFrameVisualMarkerEnv
    }
  }
}
