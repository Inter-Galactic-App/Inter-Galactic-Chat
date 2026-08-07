[CmdletBinding()]
param(
    [ValidateSet('decode-only', 'render')]
    [string] $Mode = 'decode-only',

    [string] $RunId = '',

    [ValidateRange(1, 3600)]
    [int] $DurationSeconds = 60,

    [ValidateRange(1, 7680)]
    [int] $ExpectedWidth = 1280,

    [ValidateRange(1, 4320)]
    [int] $ExpectedHeight = 720,

    [ValidateRange(1, 240)]
    [int] $ExpectedFps = 30,

    [string] $OutputDir = '',

    [string] $ControlPipe = '',

    [string] $AppExe = '',

    [ValidateRange(-1, 64)]
    [int] $RenderMonitorIndex = -1,

    [switch] $VisualFrameMarker,

    [ValidateSet('native-renderer-hash', 'stats-only')]
    [string] $FrameDiagnosticsMode = 'native-renderer-hash'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$blockedMissingRuntime = 'blocked_missing_livekit_receiver_runtime'
$blockedMissingRuntimeExecutable = 'blocked_missing_receiver_runtime_executable'
$diagnosticContract =
    'docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md'

function ConvertTo-SafeJson {
    param([Parameter(Mandatory = $true)] [object] $Value)
    return ($Value | ConvertTo-Json -Depth 12)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [object] $Value
    )

    ConvertTo-SafeJson -Value $Value | Set-Content -Path $Path -Encoding utf8
}

function Write-JsonLine {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [object] $Value
    )

    ($Value | ConvertTo-Json -Depth 12 -Compress) |
        Add-Content -Path $Path -Encoding utf8
}

function Get-UtcNow {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Get-Sha256Tag {
    param([object] $Value)

    if ($null -eq $Value) {
        return 'unknown'
    }

    $text = $Value.ToString()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return 'unknown'
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $hash = $sha.ComputeHash($bytes)
        return 'sha256:' + ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-EnvelopeValue {
    param(
        [object] $Envelope,
        [string[]] $Names
    )

    if ($null -eq $Envelope) {
        return $null
    }

    foreach ($name in $Names) {
        $property = $Envelope.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            if (-not [string]::IsNullOrWhiteSpace($property.Value.ToString())) {
                return $property.Value
            }
        }
    }

    return $null
}

function Get-EnvelopeHash {
    param(
        [object] $Envelope,
        [string[]] $HashNames,
        [string[]] $RawNames
    )

    $hashValue = Get-EnvelopeValue -Envelope $Envelope -Names $HashNames
    if ($null -ne $hashValue) {
        return $hashValue.ToString()
    }

    $rawValue = Get-EnvelopeValue -Envelope $Envelope -Names $RawNames
    return Get-Sha256Tag -Value $rawValue
}

function Test-TokenLikeCommandLineArgument {
    $commandLine = [Environment]::CommandLine
    return $commandLine -match '(?i)(^|\s)-{1,2}(jwt|token|access-token|openid-token|media-key)(\s|=|$)'
}

function Read-ControlEnvelopeRaw {
    param([Parameter(Mandatory = $true)] [string] $PipeName)

    $pipe = $null
    $reader = $null
    try {
        $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
            '.',
            $PipeName,
            [System.IO.Pipes.PipeDirection]::In
        )
        $pipe.Connect(60000)
        $reader = [System.IO.StreamReader]::new($pipe, [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
    } finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        } elseif ($null -ne $pipe) {
            $pipe.Dispose()
        }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'Protected IPC control envelope was empty.'
    }

    return $raw
}

function Read-ControlEnvelope {
    param([Parameter(Mandatory = $true)] [string] $PipeName)

    $raw = Read-ControlEnvelopeRaw -PipeName $PipeName
    return ($raw | ConvertFrom-Json)
}

function New-FreshnessReport {
    param(
        [string] $Lane,
        [string] $RoomHash,
        [string] $PublisherIdentityHash,
        [string] $ReceiverIdentityHash,
        [string] $TrackSidHash,
        [string] $TrackSource,
        [bool] $RendererAttached,
        [bool] $RendererVisible,
        [string] $Reason
    )

    return [ordered]@{
        schema_version = 1
        marker = 'intergalactic_stream_view_probe'
        status = $blockedMissingRuntime
        blocking_reason = $Reason
        run_id = $RunId
        lane = $Lane
        sample_time_utc = Get-UtcNow
        diagnostic_contract = $diagnosticContract
        protected_ipc = $true
        in_process = $false
        room_hash = $RoomHash
        publisher_identity_hash = $PublisherIdentityHash
        receiver_identity_hash = $ReceiverIdentityHash
        track_sid_hash = $TrackSidHash
        track_source = $TrackSource
        subscription_state = 'not_started'
        subscribed_quality = 'unknown'
        simulcast_layer = 'unknown'
        codec = 'unknown'
        decoder_implementation = 'unknown'
        hardware_decode = 'unknown'
        renderer_attached = $RendererAttached
        renderer_visible = $RendererVisible
        renderer_width = 0
        renderer_height = 0
        frames_received = 0
        frames_decoded = 0
        frames_rendered = 0
        freshness_source = $null
        frame_hash_algorithm = $null
        frame_hash_sample_count = 0
        frame_hash_error_count = 0
        last_frame_captured_at_utc = $null
        unique_frames = 0
        duplicate_frames = 0
        unique_fps = 0
        p50_gap_ms = $null
        p95_gap_ms = $null
        max_gap_ms = $null
        longest_stale_run_ms = $null
        jitter_buffer_delay_ms = $null
        jitter_buffer_emitted_count = $null
        total_decode_time_ms = $null
        frames_dropped = $null
        freeze_count = $null
        total_freeze_duration_ms = $null
        receive_to_decode_ms = $null
        decode_to_render_ms = $null
        frame_id = $null
        source_qpc = $null
        stage_qpc = $null
        frame_age_ms = $null
        previous_frame_id = $null
        sender_frame_id = $null
        sender_to_render_ms = $null
        frame_diagnostics_mode = $FrameDiagnosticsMode
        native_frame_hash_diagnostics_enabled = ($FrameDiagnosticsMode -eq 'native-renderer-hash')
    }
}

function Write-ReceiverOutputs {
    param(
        [string] $Status,
        [string] $Reason,
        [object] $Envelope,
        [bool] $CredentialsReceived
    )

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $eventsPath = Join-Path $OutputDir 'events.jsonl'
    if (Test-Path $eventsPath) {
        Remove-Item -Path $eventsPath -Force
    }

    $roomHash = Get-EnvelopeHash `
        -Envelope $Envelope `
        -HashNames @('room_hash') `
        -RawNames @('room_id', 'room')
    $publisherIdentityHash = Get-EnvelopeHash `
        -Envelope $Envelope `
        -HashNames @('publisher_identity_hash') `
        -RawNames @('publisher_identity', 'publisher')
    $receiverIdentityHash = Get-EnvelopeHash `
        -Envelope $Envelope `
        -HashNames @('receiver_identity_hash', 'probe_identity_hash') `
        -RawNames @('receiver_identity', 'probe_identity', 'identity')
    $trackSidHash = Get-EnvelopeHash `
        -Envelope $Envelope `
        -HashNames @('track_sid_hash', 'track_id_hash') `
        -RawNames @('track_sid', 'track_id')

    $trackSource = Get-EnvelopeValue `
        -Envelope $Envelope `
        -Names @('track_source', 'source')
    if ($null -eq $trackSource) {
        $trackSource = 'screenshare'
    } else {
        $trackSource = $trackSource.ToString()
    }

    $sfuUrl = Get-EnvelopeValue `
        -Envelope $Envelope `
        -Names @('sfu_url', 'url', 'livekit_url')
    $jwt = Get-EnvelopeValue `
        -Envelope $Envelope `
        -Names @('jwt', 'livekit_jwt', 'token')
    $expiresAt = Get-EnvelopeValue `
        -Envelope $Envelope `
        -Names @('expires_at_utc', 'expires_at')

    $decoded = New-FreshnessReport `
        -Lane 'remote_decode' `
        -RoomHash $roomHash `
        -PublisherIdentityHash $publisherIdentityHash `
        -ReceiverIdentityHash $receiverIdentityHash `
        -TrackSidHash $trackSidHash `
        -TrackSource $trackSource `
        -RendererAttached $false `
        -RendererVisible $false `
        -Reason $Reason
    $rendered = New-FreshnessReport `
        -Lane 'remote_renderer_callback' `
        -RoomHash $roomHash `
        -PublisherIdentityHash $publisherIdentityHash `
        -ReceiverIdentityHash $receiverIdentityHash `
        -TrackSidHash $trackSidHash `
        -TrackSource $trackSource `
        -RendererAttached $false `
        -RendererVisible $false `
        -Reason $Reason

    Write-JsonFile -Path (Join-Path $OutputDir 'decoded-freshness.json') -Value $decoded
    Write-JsonFile -Path (Join-Path $OutputDir 'rendered-freshness.json') -Value $rendered

    $event = [ordered]@{
        schema_version = 1
        marker = 'intergalactic_stream_view_probe'
        status = $Status
        blocking_reason = $Reason
        run_id = $RunId
        lane = 'remote_decode'
        sample_time_utc = Get-UtcNow
        diagnostic_contract = $diagnosticContract
        protected_ipc = $true
        in_process = $false
        frame_diagnostics_mode = $FrameDiagnosticsMode
        native_frame_hash_diagnostics_enabled = ($FrameDiagnosticsMode -eq 'native-renderer-hash')
        credentials_received = $CredentialsReceived
        control_pipe_name_hash = Get-Sha256Tag -Value $ControlPipe
        sfu_url_received = -not [string]::IsNullOrWhiteSpace([string] $sfuUrl)
        jwt_received = -not [string]::IsNullOrWhiteSpace([string] $jwt)
        expires_at_received = -not [string]::IsNullOrWhiteSpace([string] $expiresAt)
        room_hash = $roomHash
        publisher_identity_hash = $publisherIdentityHash
        receiver_identity_hash = $receiverIdentityHash
        track_sid_hash = $trackSidHash
        track_source = $trackSource
        subscription_state = 'not_started'
        subscribed_quality = 'unknown'
        simulcast_layer = 'unknown'
        renderer_attached = $false
        renderer_visible = $false
    }
    Write-JsonLine -Path $eventsPath -Value $event

    $summary = [ordered]@{
        schema_version = 1
        status = $Status
        blocking_reason = $Reason
        run_id = $RunId
        mode = $Mode
        duration_seconds = $DurationSeconds
        expected_width = $ExpectedWidth
        expected_height = $ExpectedHeight
        expected_fps = $ExpectedFps
        created_utc = Get-UtcNow
        diagnostic_contract = $diagnosticContract
        protected_ipc = $true
        in_process = $false
        frame_diagnostics_mode = $FrameDiagnosticsMode
        native_frame_hash_diagnostics_enabled = ($FrameDiagnosticsMode -eq 'native-renderer-hash')
        credentials_received = $CredentialsReceived
        sfu_url_received = -not [string]::IsNullOrWhiteSpace([string] $sfuUrl)
        jwt_received = -not [string]::IsNullOrWhiteSpace([string] $jwt)
        expires_at_received = -not [string]::IsNullOrWhiteSpace([string] $expiresAt)
        room_hash = $roomHash
        publisher_identity_hash = $publisherIdentityHash
        receiver_identity_hash = $receiverIdentityHash
        track_sid_hash = $trackSidHash
        track_source = $trackSource
        subscription_state = 'not_started'
        subscribed_quality = 'unknown'
        simulcast_layer = 'unknown'
        codec = 'unknown'
        decoder_implementation = 'unknown'
        hardware_decode = 'unknown'
        renderer_attached = $false
        renderer_visible = $false
        renderer_width = 0
        renderer_height = 0
        frames_received = 0
        frames_decoded = 0
        frames_rendered = 0
        freshness_source = $null
        decode_freshness_source = $null
        render_freshness_source = $null
        frame_hash_algorithm = $null
        frame_hash_sample_count = 0
        frame_hash_error_count = 0
        last_frame_captured_at_utc = $null
        unique_frames = 0
        decode_unique_fps = 0
        render_unique_fps = 0
        duplicate_frames = 0
        unique_fps = 0
        p50_gap_ms = $null
        p95_gap_ms = $null
        max_gap_ms = $null
        longest_stale_run_ms = $null
        jitter_buffer_delay_ms = $null
        jitter_buffer_emitted_count = $null
        total_decode_time_ms = $null
        frames_dropped = $null
        freeze_count = $null
        total_freeze_duration_ms = $null
        receive_to_decode_ms = $null
        decode_to_render_ms = $null
        source_lineage_event_count = 0
        source_frame_id_event_count = 0
        source_qpc_event_count = 0
        stage_qpc_event_count = 0
        source_frame_id_available = $false
        source_lineage_available = $false
        source_lineage_reason = 'events_empty'
        visual_frame_marker_source_linked = $false
        sender_frame_id = $null
        sender_to_render_ms = $null
        capabilities = [ordered]@{
            livekit_connect = $false
            decode_frame_hash_tap = $false
            render_frame_hash_tap = $false
            native_frame_hash_diagnostics_enabled = ($FrameDiagnosticsMode -eq 'native-renderer-hash')
            protected_ipc = $true
        }
        outputs = @(
            'receiver-summary.json',
            'receiver-summary.md',
            'events.jsonl',
            'decoded-freshness.json',
            'rendered-freshness.json'
        )
    }
    Write-JsonFile -Path (Join-Path $OutputDir 'receiver-summary.json') -Value $summary

    $markdown = @(
        "# Receiver Probe $RunId",
        '',
        "- status: $Status",
        "- mode: $Mode",
        "- protected_ipc: true",
        "- in_process: false",
        "- frame_diagnostics_mode: $FrameDiagnosticsMode",
        "- native_frame_hash_diagnostics_enabled: $($FrameDiagnosticsMode -eq 'native-renderer-hash')",
        "- credentials_received: $CredentialsReceived",
        "- sfu_url_received: $($summary.sfu_url_received)",
        "- jwt_received: $($summary.jwt_received)",
        "- livekit_connect: false",
        "- renderer_attached: false",
        "- renderer_visible: false",
        "- source_lineage: frame_id_events=0; source_qpc_events=0; stage_qpc_events=0; complete=false; reason=events_empty",
        '',
        "Blocking reason: $Reason",
        '',
        "No LiveKit token, Matrix id, room id, track id, or raw video content is written by this probe scaffold."
    )
    $markdown | Set-Content -Path (Join-Path $OutputDir 'receiver-summary.md') -Encoding utf8
}

function Resolve-ReceiverAppExe {
    if (-not [string]::IsNullOrWhiteSpace($AppExe)) {
        $resolved = Resolve-Path -LiteralPath $AppExe -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Path
        }
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($env:INTERGALACTIC_RECEIVER_PROBE_APP_EXE)) {
        $resolved = Resolve-Path -LiteralPath $env:INTERGALACTIC_RECEIVER_PROBE_APP_EXE -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            return $resolved.Path
        }
        return $null
    }

    $scriptDir = Split-Path -Parent $PSCommandPath
    $repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
    $candidates = @(
        (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Debug\InterGalactic.exe'),
        (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Profile\InterGalactic.exe'),
        (Join-Path $repoRoot 'intergalactic\build\windows\x64\runner\Release\InterGalactic.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function New-ChildControlPipeName {
    $safeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) {
        'run'
    } else {
        $RunId -replace '[^A-Za-z0-9_.-]', '_'
    }
    return "intergalactic.receiver-probe.$safeRunId.$([Guid]::NewGuid().ToString('N'))"
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

function Get-ProcessTreeIds {
    param([Parameter(Mandatory = $true)] [int] $RootProcessId)

    $ids = @($RootProcessId)
    foreach ($childId in Get-ChildProcessIds -ParentProcessId $RootProcessId) {
        $ids += @(Get-ProcessTreeIds -RootProcessId $childId)
    }
    return @($ids | Select-Object -Unique)
}

function Ensure-ReceiverProbeWindowType {
    if ($null -ne ([System.Management.Automation.PSTypeName]'InterGalactic.ReceiverProbe.WindowPlacement').Type) {
        return
    }

    Add-Type -Namespace 'InterGalactic.ReceiverProbe' -Name 'WindowPlacement' -MemberDefinition @"
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
public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT rect);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowTextLength(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int maxCount);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

public static string GetWindowTitle(System.IntPtr hWnd)
{
    var length = GetWindowTextLength(hWnd);
    var builder = new System.Text.StringBuilder(System.Math.Max(length + 1, 256));
    GetWindowText(hWnd, builder, builder.Capacity);
    return builder.ToString();
}

public static System.IntPtr FindVisibleWindowForProcessIds(int[] targetProcessIds, string titleContains)
{
    var targets = new System.Collections.Generic.HashSet<uint>();
    foreach (var id in targetProcessIds)
    {
        if (id > 0)
        {
            targets.Add((uint)id);
        }
    }

    System.IntPtr result = System.IntPtr.Zero;
    EnumWindows(delegate(System.IntPtr hWnd, System.IntPtr lParam) {
        if (!IsWindowVisible(hWnd))
        {
            return true;
        }

        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);
        if (!targets.Contains(processId))
        {
            return true;
        }

        if (!System.String.IsNullOrWhiteSpace(titleContains))
        {
            var title = GetWindowTitle(hWnd);
            if (title.IndexOf(titleContains, System.StringComparison.OrdinalIgnoreCase) < 0)
            {
                return true;
            }
        }

        if (targets.Contains(processId))
        {
            result = hWnd;
            return false;
        }

        return true;
    }, System.IntPtr.Zero);
    return result;
}
"@
}

function Resolve-ReceiverProbeMonitorRequest {
    $monitorIndex = $RenderMonitorIndex
    if ($monitorIndex -lt 0 -and
        -not [string]::IsNullOrWhiteSpace($env:INTERGALACTIC_RECEIVER_PROBE_MONITOR_INDEX)) {
        $parsed = -1
        if ([int]::TryParse($env:INTERGALACTIC_RECEIVER_PROBE_MONITOR_INDEX, [ref]$parsed) -and
            $parsed -ge 0) {
            $monitorIndex = $parsed
        }
    }

    $request = [ordered]@{
        schema_version = 1
        requested = $monitorIndex -ge 0
        monitor_index = $monitorIndex
        status = 'not_requested'
        reason = ''
        monitor_count = $null
        device_name = ''
        x = $null
        y = $null
        width = $null
        height = $null
    }

    if ($monitorIndex -lt 0) {
        return [pscustomobject]$request
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $request['monitor_count'] = $screens.Count
        if ($monitorIndex -ge $screens.Count) {
            $request['status'] = 'invalid_monitor_index'
            $request['reason'] = "Monitor index $monitorIndex is outside the available monitor count $($screens.Count)."
            return [pscustomobject]$request
        }

        $screen = $screens[$monitorIndex]
        $request['status'] = 'ready'
        $request['device_name'] = $screen.DeviceName
        $request['x'] = $screen.WorkingArea.X
        $request['y'] = $screen.WorkingArea.Y
        $request['width'] = $screen.WorkingArea.Width
        $request['height'] = $screen.WorkingArea.Height
        return [pscustomobject]$request
    } catch {
        $request['status'] = 'screen_api_unavailable'
        $request['reason'] = $_.Exception.Message
        return [pscustomobject]$request
    }
}

function Move-ReceiverProbeWindowToMonitor {
    param(
        [Parameter(Mandatory = $true)] [System.Diagnostics.Process] $Process,
        [Parameter(Mandatory = $true)] [object] $MonitorRequest
    )

    $result = [ordered]@{
        schema_version = 1
        requested = [bool]$MonitorRequest.requested
        monitor_index = $MonitorRequest.monitor_index
        monitor_status = $MonitorRequest.status
        status = $MonitorRequest.status
        reason = $MonitorRequest.reason
        process_id = $Process.Id
        window_handle = $null
        window_title = ''
        monitor = $null
        original = $null
        target = $null
        z_order = ''
        z_order_restore_status = ''
        created_utc = Get-UtcNow
    }

    $observeOnly = (-not [bool]$MonitorRequest.requested) -and $Mode -eq 'render'
    if (-not [bool]$MonitorRequest.requested -and -not $observeOnly) {
        return [pscustomobject]$result
    }
    if ([bool]$MonitorRequest.requested -and $MonitorRequest.status -ne 'ready') {
        return [pscustomobject]$result
    }
    if ([bool]$MonitorRequest.requested) {
        $result['monitor'] = [ordered]@{
            x = [int]$MonitorRequest.x
            y = [int]$MonitorRequest.y
            width = [int]$MonitorRequest.width
            height = [int]$MonitorRequest.height
            device_name = $MonitorRequest.device_name
        }
    }

    Ensure-ReceiverProbeWindowType
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(20)
    $hWnd = [IntPtr]::Zero
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $Process.Refresh()
            if ($Process.HasExited) {
                $result['status'] = 'process_exited_before_window'
                $result['reason'] = "Receiver runtime exited before a visible window was found. ExitCode=$($Process.ExitCode)"
                return [pscustomobject]$result
            }
        } catch {
        }

        $processIds = [int[]]@(Get-ProcessTreeIds -RootProcessId $Process.Id)
        $hWnd = [InterGalactic.ReceiverProbe.WindowPlacement]::FindVisibleWindowForProcessIds(
            $processIds,
            'Receiver Probe'
        )
        if ($hWnd -ne [IntPtr]::Zero) {
            break
        }
        Start-Sleep -Milliseconds 250
    }

    if ($hWnd -eq [IntPtr]::Zero) {
        $result['status'] = 'window_not_found'
        $result['reason'] = 'No visible receiver runtime window was found before placement timeout.'
        return [pscustomobject]$result
    }

    $windowTitle = [InterGalactic.ReceiverProbe.WindowPlacement]::GetWindowTitle($hWnd)
    $rect = New-Object InterGalactic.ReceiverProbe.WindowPlacement+RECT
    if (-not [InterGalactic.ReceiverProbe.WindowPlacement]::GetWindowRect($hWnd, [ref]$rect)) {
        $result['status'] = 'get_window_rect_failed'
        $result['reason'] = 'GetWindowRect failed for receiver runtime window.'
        return [pscustomobject]$result
    }

    $width = [Math]::Max(1, $rect.Right - $rect.Left)
    $height = [Math]::Max(1, $rect.Bottom - $rect.Top)
    if ($observeOnly) {
        $result['status'] = 'observed_not_moved'
        $result['reason'] = ''
        $result['window_handle'] = $hWnd.ToInt64()
        $result['window_title'] = $windowTitle
        $result['original'] = [ordered]@{
            x = $rect.Left
            y = $rect.Top
            width = $width
            height = $height
        }
        return [pscustomobject]$result
    }

    $offsetX = [Math]::Max(0, [Math]::Min(40, [int]$MonitorRequest.width - $width))
    $offsetY = [Math]::Max(0, [Math]::Min(40, [int]$MonitorRequest.height - $height))
    $targetX = [int]$MonitorRequest.x + $offsetX
    $targetY = [int]$MonitorRequest.y + $offsetY
    $swpNoActivate = 0x0010
    $swpShowWindow = 0x0040
    $hwndTopmost = [IntPtr](-1)
    $flags = [uint32]($swpNoActivate -bor $swpShowWindow)

    if (-not [InterGalactic.ReceiverProbe.WindowPlacement]::SetWindowPos(
            $hWnd,
            $hwndTopmost,
            $targetX,
            $targetY,
            $width,
            $height,
            $flags
        )) {
        $result['status'] = 'set_window_pos_failed'
        $result['reason'] = 'SetWindowPos failed for receiver runtime window.'
        return [pscustomobject]$result
    }

    $result['status'] = 'moved'
    $result['reason'] = ''
    $result['window_handle'] = $hWnd.ToInt64()
    $result['window_title'] = $windowTitle
    $result['z_order'] = 'topmost_no_activate'
    $result['z_order_restore_status'] = 'kept_topmost_until_probe_exit'
    $result['original'] = [ordered]@{
        x = $rect.Left
        y = $rect.Top
        width = $width
        height = $height
    }
    $result['target'] = [ordered]@{
        x = $targetX
        y = $targetY
        width = $width
        height = $height
    }
    return [pscustomobject]$result
}

function Invoke-ReceiverRuntime {
    param(
        [Parameter(Mandatory = $true)] [string] $ResolvedAppExe,
        [Parameter(Mandatory = $true)] [string] $EnvelopeRaw,
        [Parameter(Mandatory = $true)] [object] $Envelope
    )

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $childPipeName = New-ChildControlPipeName
    $childPipeServer = $null
    $writer = $null
    $process = $null
    $oldInstanceId = $env:INTERGALACTIC_DEV_INSTANCE_ID
    $oldProfileDir = $env:INTERGALACTIC_DEV_PROFILE_DIR
    $oldProbeProcess = $env:INTERGALACTIC_RECEIVER_PROBE_PROCESS

    try {
        $safeRunId = $RunId -replace '[^A-Za-z0-9_.-]', '_'
        if ([string]::IsNullOrWhiteSpace($safeRunId)) {
            $safeRunId = [Guid]::NewGuid().ToString('N')
        }
        $env:INTERGALACTIC_DEV_INSTANCE_ID = "receiver-probe-$safeRunId"
        $env:INTERGALACTIC_DEV_PROFILE_DIR = Join-Path $OutputDir 'app-profile'
        $env:INTERGALACTIC_RECEIVER_PROBE_PROCESS = '1'

        $appArgs = @(
            '--receiver-probe',
            '--receiver-probe-mode', $Mode,
            '--receiver-probe-run-id', $RunId,
            '--receiver-probe-duration-seconds', $DurationSeconds.ToString(),
            '--receiver-probe-expected-width', $ExpectedWidth.ToString(),
            '--receiver-probe-expected-height', $ExpectedHeight.ToString(),
            '--receiver-probe-expected-fps', $ExpectedFps.ToString(),
            '--receiver-probe-output-dir', $OutputDir,
            '--receiver-probe-control-pipe', $childPipeName,
            '--receiver-probe-frame-diagnostics-mode', $FrameDiagnosticsMode,
            '--ig-debug-logs',
            '--ig-webrtc-stats'
        )
        if ($VisualFrameMarker) {
            $appArgs += @('--receiver-probe-visual-frame-marker')
        }

        $childPipeServer = [System.IO.Pipes.NamedPipeServerStream]::new(
            $childPipeName,
            [System.IO.Pipes.PipeDirection]::InOut,
            1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::None
        )

        $startParameters = @{
            FilePath = $ResolvedAppExe
            ArgumentList = $appArgs
            WorkingDirectory = (Split-Path -Parent $ResolvedAppExe)
            PassThru = $true
        }
        $startParameters.WindowStyle = 'Normal'

        $process = Start-Process @startParameters

        try {
            $connectTask = $childPipeServer.WaitForConnectionAsync()
            if (-not $connectTask.Wait(15000)) {
                throw 'Timed out waiting for receiver runtime to connect to protected child IPC pipe.'
            }
            if ($connectTask.IsFaulted) {
                throw $connectTask.Exception.GetBaseException()
            }
        } catch {
            if ($null -ne $process -and -not $process.HasExited) {
                Stop-ProcessTree -RootProcessId $process.Id
            }
            Write-ReceiverOutputs `
                -Status 'blocked_receiver_runtime_ipc_timeout' `
                -Reason 'Receiver runtime did not connect to the protected child IPC pipe.' `
                -Envelope $Envelope `
                -CredentialsReceived $true
            return 0
        }

        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($childPipeServer, $utf8NoBom)
        $writer.Write($EnvelopeRaw)
        $writer.Flush()
        $writer.Dispose()
        $writer = $null

        $monitorRequest = Resolve-ReceiverProbeMonitorRequest
        $windowPlacement = Move-ReceiverProbeWindowToMonitor `
            -Process $process `
            -MonitorRequest $monitorRequest
        Write-JsonFile `
            -Path (Join-Path $OutputDir 'receiver-window-placement.json') `
            -Value $windowPlacement

        $runtimeTimeoutSeconds = [Math]::Max($DurationSeconds + 45, 60)
        $completed = $false
        try {
            Wait-Process -Id $process.Id -Timeout $runtimeTimeoutSeconds -ErrorAction Stop
            $completed = $true
        } catch {
            $completed = $false
        }

        if (-not $completed) {
            Stop-ProcessTree -RootProcessId $process.Id
            Write-ReceiverOutputs `
                -Status 'blocked_receiver_runtime_timeout' `
                -Reason "Receiver runtime exceeded $runtimeTimeoutSeconds seconds and was terminated." `
                -Envelope $Envelope `
                -CredentialsReceived $true
            return 0
        }

        $process.Refresh()
        $summaryPath = Join-Path $OutputDir 'receiver-summary.json'
        if (-not (Test-Path -LiteralPath $summaryPath)) {
            Write-ReceiverOutputs `
                -Status 'blocked_receiver_runtime_no_summary' `
                -Reason "Receiver runtime exited without receiver-summary.json. ExitCode=$($process.ExitCode)" `
                -Envelope $Envelope `
                -CredentialsReceived $true
            return 0
        }

        return $process.ExitCode
    } finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        } elseif ($null -ne $childPipeServer) {
            $childPipeServer.Dispose()
        }
        if ($null -eq $oldInstanceId) {
            Remove-Item Env:\INTERGALACTIC_DEV_INSTANCE_ID -ErrorAction SilentlyContinue
        } else {
            $env:INTERGALACTIC_DEV_INSTANCE_ID = $oldInstanceId
        }
        if ($null -eq $oldProfileDir) {
            Remove-Item Env:\INTERGALACTIC_DEV_PROFILE_DIR -ErrorAction SilentlyContinue
        } else {
            $env:INTERGALACTIC_DEV_PROFILE_DIR = $oldProfileDir
        }
        if ($null -eq $oldProbeProcess) {
            Remove-Item Env:\INTERGALACTIC_RECEIVER_PROBE_PROCESS -ErrorAction SilentlyContinue
        } else {
            $env:INTERGALACTIC_RECEIVER_PROBE_PROCESS = $oldProbeProcess
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    throw 'Missing required -OutputDir.'
}

if (Test-TokenLikeCommandLineArgument) {
    Write-ReceiverOutputs `
        -Status 'blocked_token_argument_rejected' `
        -Reason 'Probe tokens must be delivered through protected local IPC, not command-line arguments.' `
        -Envelope $null `
        -CredentialsReceived $false
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ControlPipe)) {
    Write-ReceiverOutputs `
        -Status 'blocked_missing_protected_ipc' `
        -Reason 'Missing -ControlPipe. Tokens are not accepted on the command line.' `
        -Envelope $null `
        -CredentialsReceived $false
    exit 0
}

try {
    $envelopeRaw = Read-ControlEnvelopeRaw -PipeName $ControlPipe
    $envelope = $envelopeRaw | ConvertFrom-Json
} catch {
    Write-ReceiverOutputs `
        -Status 'blocked_protected_ipc_unavailable' `
        -Reason "Could not read protected IPC control envelope: $($_.Exception.Message)" `
        -Envelope $null `
        -CredentialsReceived $false
    exit 0
}

$resolvedAppExe = Resolve-ReceiverAppExe
if ([string]::IsNullOrWhiteSpace($resolvedAppExe)) {
    $reason = if (-not [string]::IsNullOrWhiteSpace($AppExe)) {
        "Receiver app executable was not found: $AppExe"
    } elseif (-not [string]::IsNullOrWhiteSpace($env:INTERGALACTIC_RECEIVER_PROBE_APP_EXE)) {
        "Receiver app executable from INTERGALACTIC_RECEIVER_PROBE_APP_EXE was not found."
    } else {
        'Receiver app executable was not found. Build the Windows app or set INTERGALACTIC_RECEIVER_PROBE_APP_EXE.'
    }
    Write-ReceiverOutputs `
        -Status $blockedMissingRuntimeExecutable `
        -Reason $reason `
        -Envelope $envelope `
        -CredentialsReceived $true
    exit 0
}

$credentialJwt = Get-EnvelopeValue `
    -Envelope $envelope `
    -Names @('jwt', 'livekit_jwt', 'token')
$credentialSfuUrl = Get-EnvelopeValue `
    -Envelope $envelope `
    -Names @('sfu_url', 'url', 'livekit_url')

if ([string]::IsNullOrWhiteSpace([string] $credentialJwt) -or
    [string]::IsNullOrWhiteSpace([string] $credentialSfuUrl)) {
    Write-ReceiverOutputs `
        -Status 'blocked_incomplete_probe_credentials' `
        -Reason 'Protected IPC envelope must include a LiveKit URL and subscribe-only JWT.' `
        -Envelope $envelope `
        -CredentialsReceived $true
    exit 0
}

$receiverExitCode = Invoke-ReceiverRuntime `
    -ResolvedAppExe $resolvedAppExe `
    -EnvelopeRaw $envelopeRaw `
    -Envelope $envelope
exit $receiverExitCode
