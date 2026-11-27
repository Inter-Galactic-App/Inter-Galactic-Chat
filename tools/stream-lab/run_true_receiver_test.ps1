[CmdletBinding()]
param(
    [ValidateSet('Plan', 'DecodeOnly', 'Render', 'InProcessDecodeOnly', 'InProcessRender', 'InProcessLocalPreview')]
    [string] $Mode = 'Plan',

    [switch] $PlanOnly,

    [string] $RunId = '',

    [ValidateRange(1, 3600)]
    [int] $DurationSeconds = 60,

    [ValidateRange(1, 7680)]
    [int] $ExpectedWidth = 1280,

    [ValidateRange(1, 4320)]
    [int] $ExpectedHeight = 720,

    [ValidateRange(1, 240)]
    [int] $ExpectedFps = 30,

    [string] $ProbeExe = '',

    [string] $ProbeAppExe = '',

    [string] $ProbeControlPipe = '',

    [string] $OutputRoot = '',

    [string] $InProcessEventsPath = '',

    [ValidateRange(-1, 64)]
    [int] $ProbeMonitorIndex = -1,

    [switch] $VisualFrameMarker,

    [ValidateSet('native-renderer-hash', 'stats-only')]
    [string] $FrameDiagnosticsMode = 'native-renderer-hash',

    [ValidateRange(0.0, 240.0)]
    [double] $MinUniqueFps = 25.0,

    [ValidateRange(1, 7200)]
    [int] $TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SafeJson {
    param([Parameter(Mandatory = $true)] [object] $Value)
    return ($Value | ConvertTo-Json -Depth 10)
}

function Write-ReceiverRunReport {
    param(
        [Parameter(Mandatory = $true)] [string] $RunDirectory,
        [Parameter(Mandatory = $true)] [hashtable] $Report
    )

    New-Item -ItemType Directory -Force -Path $RunDirectory | Out-Null

    $jsonPath = Join-Path $RunDirectory 'true-receiver-test.json'
    ConvertTo-SafeJson -Value $Report | Set-Content -Path $jsonPath -Encoding utf8

    $mdPath = Join-Path $RunDirectory 'true-receiver-test.md'
    $lines = @(
        "# True Receiver Test $($Report.run_id)",
        '',
        "- status: $($Report.status)",
        "- mode: $($Report.mode)",
        "- duration_seconds: $($Report.duration_seconds)",
        "- expected_resolution: $($Report.expected_width)x$($Report.expected_height)",
        "- expected_fps: $($Report.expected_fps)",
        "- output_directory: $RunDirectory",
        '',
        "## Notes"
    )

    foreach ($note in @($Report.notes)) {
        $lines += "- $note"
    }

    if ($Report.ContainsKey('required_outputs')) {
        $lines += ''
        $lines += '## Required Outputs'
        foreach ($output in @($Report.required_outputs)) {
            $lines += "- $output"
        }
    }

    if ($Report.ContainsKey('blocking_reason')) {
        $lines += ''
        $lines += "Blocking reason: $($Report.blocking_reason)"
    }

    $lines | Set-Content -Path $mdPath -Encoding utf8
}

function Write-ReceiverRunError {
    param([Parameter(Mandatory = $true)] [string] $Message)

    [Console]::Error.WriteLine($Message)
}

function Get-ObjectPropertyOrDefault {
    param(
        [object] $Object,
        [string] $Name,
        [object] $DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Test-ReceiverSummaryStatusBlocksRun {
    param([object] $Status)

    if ($null -eq $Status) {
        return $false
    }

    $normalized = $Status.ToString().ToLowerInvariant()
    return $normalized.StartsWith('blocked_') -or
        $normalized.StartsWith('inconclusive_') -or
        $normalized.StartsWith('invalid_') -or
        $normalized.StartsWith('failed_')
}

function Test-ReceiverFrameHashFreshnessSource {
    param([object] $Source)

    if ($null -eq $Source) {
        return $false
    }

    return $Source.ToString() -eq 'frame_hash_tap'
}

function Get-ObjectProperty {
    param(
        [object] $Object,
        [string] $Name
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

function Get-FirstObjectProperty {
    param(
        [object] $Object,
        [string[]] $Names
    )

    foreach ($name in $Names) {
        $value = Get-ObjectProperty -Object $Object -Name $name
        if ($null -ne $value) {
            return $value
        }
    }

    return $null
}

function Get-ReceiverGateSummary {
    param(
        [Parameter(Mandatory = $true)] [object] $Summary,
        [Parameter(Mandatory = $true)] [string] $Mode
    )

    $uniqueFpsValue = if ($Mode -eq 'Render') {
        Get-FirstObjectProperty -Object $Summary -Names @(
            'render_unique_fps',
            'unique_fps'
        )
    } else {
        Get-FirstObjectProperty -Object $Summary -Names @(
            'decode_unique_fps',
            'unique_fps'
        )
    }
    $freshnessSource = if ($Mode -eq 'Render') {
        Get-FirstObjectProperty -Object $Summary -Names @(
            'render_freshness_source',
            'freshness_source'
        )
    } else {
        Get-FirstObjectProperty -Object $Summary -Names @(
            'decode_freshness_source',
            'freshness_source'
        )
    }

    $uniqueFps = $null
    if ($null -ne $uniqueFpsValue) {
        $uniqueFps = [double] $uniqueFpsValue
    }

    return [pscustomobject]@{
        unique_fps = $uniqueFps
        freshness_source = $freshnessSource
        lane = if ($Mode -eq 'Render') { 'remote_renderer_callback' } else { 'remote_decode' }
    }
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

function Read-ReceiverProbeEvents {
    param([Parameter(Mandatory = $true)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Receiver probe events file was not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $trimmed = $raw.Trim()
    if ($trimmed.StartsWith('[')) {
        $parsed = $trimmed | ConvertFrom-Json
        return @($parsed)
    }

    $events = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $events += ($line | ConvertFrom-Json)
    }
    return $events
}

function Get-EventValue {
    param(
        [object] $Event,
        [string] $Name,
        [object] $DefaultValue = $null
    )

    return Get-ObjectPropertyOrDefault -Object $Event -Name $Name -DefaultValue $DefaultValue
}

function Test-ReceiverRendererCallbackLane {
    param([object] $Event)

    $lane = Get-EventValue -Event $Event -Name 'lane' -DefaultValue ''
    return $lane -eq 'remote_renderer_callback' -or $lane -eq 'remote_render'
}

function Test-EventValuePresent {
    param(
        [object] $Event,
        [string] $Name
    )

    $value = Get-EventValue -Event $Event -Name $Name -DefaultValue $null
    if ($null -eq $value) {
        return $false
    }
    return -not [string]::IsNullOrWhiteSpace([string]$value)
}

function Get-ReceiverSourceLineageStats {
    param([object[]] $Events)

    $frameIdEvents = 0
    $previousFrameIdEvents = 0
    $sourceFrameMarkerIdEvents = 0
    $sourceQpcEvents = 0
    $stageQpcEvents = 0
    $sourceLineageEvents = 0
    foreach ($receiverEvent in $Events) {
        $hasFrameId = Test-EventValuePresent -Event $receiverEvent -Name 'frame_id'
        $hasPreviousFrameId = Test-EventValuePresent -Event $receiverEvent -Name 'previous_frame_id'
        $hasSourceFrameMarkerId = Test-EventValuePresent -Event $receiverEvent -Name 'source_frame_marker_id'
        $hasSourceQpc = Test-EventValuePresent -Event $receiverEvent -Name 'source_qpc'
        $hasStageQpc = Test-EventValuePresent -Event $receiverEvent -Name 'stage_qpc'
        if ($hasFrameId) { $frameIdEvents++ }
        if ($hasPreviousFrameId) { $previousFrameIdEvents++ }
        if ($hasSourceFrameMarkerId) { $sourceFrameMarkerIdEvents++ }
        if ($hasSourceQpc) { $sourceQpcEvents++ }
        if ($hasStageQpc) { $stageQpcEvents++ }
        if ($hasFrameId -or $hasPreviousFrameId -or $hasSourceFrameMarkerId -or $hasSourceQpc -or $hasStageQpc) {
            $sourceLineageEvents++
        }
    }

    $sourceFrameIdAvailable = $frameIdEvents -gt 0 -or $previousFrameIdEvents -gt 0 -or $sourceFrameMarkerIdEvents -gt 0
    $sourceLineageAvailable =
        $sourceFrameIdAvailable -and $sourceQpcEvents -gt 0 -and $stageQpcEvents -gt 0
    $reason = if ($sourceLineageAvailable) {
        if ($frameIdEvents -gt 0) {
            'source_frame_id_source_qpc_stage_qpc_present'
        } elseif ($previousFrameIdEvents -gt 0) {
            'source_frame_id_observed_as_previous_source_qpc_stage_qpc_present'
        } else {
            'source_frame_content_marker_source_qpc_stage_qpc_present'
        }
    } elseif ($sourceFrameMarkerIdEvents -gt 0) {
        'source_frame_content_marker_present_without_complete_lineage'
    } elseif ($sourceFrameIdAvailable) {
        if ($frameIdEvents -gt 0) {
            'source_frame_id_present_without_complete_lineage'
        } else {
            'source_frame_id_observed_as_previous_without_complete_lineage'
        }
    } elseif ($Events.Count -gt 0) {
        'source_frame_id_missing'
    } else {
        'events_empty'
    }

    return [ordered]@{
        source_lineage_event_count = $sourceLineageEvents
        source_frame_id_event_count = $frameIdEvents
        previous_frame_id_event_count = $previousFrameIdEvents
        source_frame_marker_id_event_count = $sourceFrameMarkerIdEvents
        source_qpc_event_count = $sourceQpcEvents
        stage_qpc_event_count = $stageQpcEvents
        source_frame_id_available = $sourceFrameIdAvailable
        source_lineage_available = $sourceLineageAvailable
        source_lineage_reason = $reason
    }
}

function New-FreshnessFromReceiverEvent {
    param(
        [string] $Lane,
        [object] $Event,
        [string] $Status,
        [string] $Reason
    )

    return [ordered]@{
        schema_version = 1
        marker = 'intergalactic_stream_view_probe'
        status = $Status
        blocking_reason = $Reason
        run_id = $RunId
        lane = $Lane
        sample_time_utc = Get-EventValue -Event $Event -Name 'sample_time_utc' -DefaultValue ((Get-Date).ToUniversalTime().ToString('o'))
        diagnostic_contract = 'docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md'
        protected_ipc = $false
        in_process = $true
        room_hash = Get-EventValue -Event $Event -Name 'room_hash' -DefaultValue 'unknown'
        publisher_identity_hash = Get-EventValue -Event $Event -Name 'publisher_identity_hash' -DefaultValue 'unknown'
        receiver_identity_hash = Get-EventValue -Event $Event -Name 'receiver_identity_hash' -DefaultValue 'unknown'
        track_sid_hash = Get-EventValue -Event $Event -Name 'track_sid_hash' -DefaultValue 'unknown'
        track_source = Get-EventValue -Event $Event -Name 'track_source' -DefaultValue 'screenshare'
        subscription_state = Get-EventValue -Event $Event -Name 'subscription_state' -DefaultValue 'unknown'
        subscribed_quality = Get-EventValue -Event $Event -Name 'subscribed_quality' -DefaultValue 'unknown'
        simulcast_layer = Get-EventValue -Event $Event -Name 'simulcast_layer' -DefaultValue 'unknown'
        codec = Get-EventValue -Event $Event -Name 'codec' -DefaultValue 'unknown'
        decoder_implementation = Get-EventValue -Event $Event -Name 'decoder_implementation' -DefaultValue 'unknown'
        hardware_decode = Get-EventValue -Event $Event -Name 'hardware_decode' -DefaultValue 'unknown'
        renderer_attached = [bool](Get-EventValue -Event $Event -Name 'renderer_attached' -DefaultValue $false)
        renderer_visible = [bool](Get-EventValue -Event $Event -Name 'renderer_visible' -DefaultValue $false)
        renderer_width = Get-EventValue -Event $Event -Name 'renderer_width' -DefaultValue 0
        renderer_height = Get-EventValue -Event $Event -Name 'renderer_height' -DefaultValue 0
        bitrate_bps = Get-EventValue -Event $Event -Name 'bitrate_bps' -DefaultValue $null
        frames_received = Get-EventValue -Event $Event -Name 'frames_received' -DefaultValue 0
        frames_decoded = Get-EventValue -Event $Event -Name 'frames_decoded' -DefaultValue 0
        frames_rendered = Get-EventValue -Event $Event -Name 'frames_rendered' -DefaultValue 0
        render_fps = Get-EventValue -Event $Event -Name 'render_fps' -DefaultValue $null
        receiver_fps = Get-EventValue -Event $Event -Name 'receiver_fps' -DefaultValue $null
        received_fps = Get-EventValue -Event $Event -Name 'received_fps' -DefaultValue $null
        decoded_fps = Get-EventValue -Event $Event -Name 'decoded_fps' -DefaultValue $null
        rendered_fps = Get-EventValue -Event $Event -Name 'rendered_fps' -DefaultValue $null
        receiver_stats_sample_window_ms = Get-EventValue -Event $Event -Name 'receiver_stats_sample_window_ms' -DefaultValue $null
        freshness_source = Get-EventValue -Event $Event -Name 'freshness_source' -DefaultValue $null
        frame_hash_algorithm = Get-EventValue -Event $Event -Name 'frame_hash_algorithm' -DefaultValue $null
        frame_hash_sample_count = Get-EventValue -Event $Event -Name 'frame_hash_sample_count' -DefaultValue $null
        frame_hash_error_count = Get-EventValue -Event $Event -Name 'frame_hash_error_count' -DefaultValue $null
        last_frame_captured_at_utc = Get-EventValue -Event $Event -Name 'last_frame_captured_at_utc' -DefaultValue $null
        unique_frames = Get-EventValue -Event $Event -Name 'unique_frames' -DefaultValue $null
        duplicate_frames = Get-EventValue -Event $Event -Name 'duplicate_frames' -DefaultValue $null
        unique_fps = Get-EventValue -Event $Event -Name 'unique_fps' -DefaultValue $null
        p50_gap_ms = Get-EventValue -Event $Event -Name 'p50_gap_ms' -DefaultValue $null
        p95_gap_ms = Get-EventValue -Event $Event -Name 'p95_gap_ms' -DefaultValue $null
        max_gap_ms = Get-EventValue -Event $Event -Name 'max_gap_ms' -DefaultValue $null
        longest_stale_run_ms = Get-EventValue -Event $Event -Name 'longest_stale_run_ms' -DefaultValue $null
        jitter_buffer_delay_ms = Get-EventValue -Event $Event -Name 'jitter_buffer_delay_ms' -DefaultValue $null
        jitter_buffer_emitted_count = Get-EventValue -Event $Event -Name 'jitter_buffer_emitted_count' -DefaultValue $null
        total_decode_time_ms = Get-EventValue -Event $Event -Name 'total_decode_time_ms' -DefaultValue $null
        average_decode_time_ms = Get-EventValue -Event $Event -Name 'average_decode_time_ms' -DefaultValue $null
        frames_dropped = Get-EventValue -Event $Event -Name 'frames_dropped' -DefaultValue $null
        freeze_count = Get-EventValue -Event $Event -Name 'freeze_count' -DefaultValue $null
        total_freeze_duration_ms = Get-EventValue -Event $Event -Name 'total_freeze_duration_ms' -DefaultValue $null
        receive_to_decode_ms = Get-EventValue -Event $Event -Name 'receive_to_decode_ms' -DefaultValue $null
        decode_to_render_ms = Get-EventValue -Event $Event -Name 'decode_to_render_ms' -DefaultValue $null
        frame_id_source = Get-EventValue -Event $Event -Name 'frame_id_source' -DefaultValue $null
        source_frame_marker_id = Get-EventValue -Event $Event -Name 'source_frame_marker_id' -DefaultValue $null
        source_frame_marker_decoded_frames = Get-EventValue -Event $Event -Name 'source_frame_marker_decoded_frames' -DefaultValue $null
        source_frame_marker_unique_frames = Get-EventValue -Event $Event -Name 'source_frame_marker_unique_frames' -DefaultValue $null
        source_frame_marker_duplicate_frames = Get-EventValue -Event $Event -Name 'source_frame_marker_duplicate_frames' -DefaultValue $null
        source_frame_marker_unique_fps = Get-EventValue -Event $Event -Name 'source_frame_marker_unique_fps' -DefaultValue $null
        source_frame_marker_longest_stale_run_ms = Get-EventValue -Event $Event -Name 'source_frame_marker_longest_stale_run_ms' -DefaultValue $null
        sender_frame_id = Get-EventValue -Event $Event -Name 'sender_frame_id' -DefaultValue $null
        sender_to_render_ms = Get-EventValue -Event $Event -Name 'sender_to_render_ms' -DefaultValue $null
    }
}

function Write-InProcessReceiverOutputs {
    param(
        [Parameter(Mandatory = $true)] [string] $RunDirectory,
        [Parameter(Mandatory = $true)] [object[]] $Events,
        [Parameter(Mandatory = $true)] [string] $Status,
        [string] $Reason = ''
    )

    New-Item -ItemType Directory -Force -Path $RunDirectory | Out-Null

    $eventsPath = Join-Path $RunDirectory 'events.jsonl'
    if (Test-Path -LiteralPath $eventsPath) {
        Remove-Item -LiteralPath $eventsPath -Force
    }
    foreach ($event in $Events) {
        ($event | ConvertTo-Json -Depth 12 -Compress) |
            Add-Content -LiteralPath $eventsPath -Encoding utf8
    }

    $decodeEvents = @($Events | Where-Object { (Get-EventValue -Event $_ -Name 'lane' -DefaultValue '') -eq 'remote_decode' })
    $renderEvents = @($Events | Where-Object { Test-ReceiverRendererCallbackLane -Event $_ })
    $localPreviewEvents = @($Events | Where-Object { (Get-EventValue -Event $_ -Name 'lane' -DefaultValue '') -eq 'local_preview' })
    $sourceLineage = Get-ReceiverSourceLineageStats -Events $Events
    $latestDecode = if ($decodeEvents.Count -gt 0) { $decodeEvents[-1] } else { $null }
    $latestRender = if ($renderEvents.Count -gt 0) { $renderEvents[-1] } else { $null }
    $latestLocalPreview = if ($localPreviewEvents.Count -gt 0) { $localPreviewEvents[-1] } else { $null }

    ConvertTo-SafeJson -Value (New-FreshnessFromReceiverEvent -Lane 'remote_decode' -Event $latestDecode -Status $Status -Reason $Reason) |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'decoded-freshness.json') -Encoding utf8
    ConvertTo-SafeJson -Value (New-FreshnessFromReceiverEvent -Lane 'remote_renderer_callback' -Event $latestRender -Status $Status -Reason $Reason) |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'rendered-freshness.json') -Encoding utf8
    ConvertTo-SafeJson -Value (New-FreshnessFromReceiverEvent -Lane 'local_preview' -Event $latestLocalPreview -Status $Status -Reason $Reason) |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'local-preview-freshness.json') -Encoding utf8

    $summary = [ordered]@{
        schema_version = 1
        status = $Status
        blocking_reason = $Reason
        run_id = $RunId
        mode = $Mode
        in_process = $true
        event_count = $Events.Count
        local_preview_event_count = $localPreviewEvents.Count
        remote_decode_event_count = $decodeEvents.Count
        remote_renderer_callback_lane_event_count = $renderEvents.Count
        source_lineage_event_count = $sourceLineage.source_lineage_event_count
        source_frame_id_event_count = $sourceLineage.source_frame_id_event_count
        previous_frame_id_event_count = $sourceLineage.previous_frame_id_event_count
        source_frame_marker_id_event_count = $sourceLineage.source_frame_marker_id_event_count
        source_qpc_event_count = $sourceLineage.source_qpc_event_count
        stage_qpc_event_count = $sourceLineage.stage_qpc_event_count
        source_frame_id_available = $sourceLineage.source_frame_id_available
        source_lineage_available = $sourceLineage.source_lineage_available
        source_lineage_reason = $sourceLineage.source_lineage_reason
        min_unique_fps = $MinUniqueFps
        expected_width = $ExpectedWidth
        expected_height = $ExpectedHeight
        expected_fps = $ExpectedFps
        created_utc = (Get-Date).ToUniversalTime().ToString('o')
        diagnostic_contract = 'docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md'
        renderer_attached = [bool](Get-EventValue -Event $latestRender -Name 'renderer_attached' -DefaultValue $false)
        renderer_visible = [bool](Get-EventValue -Event $latestRender -Name 'renderer_visible' -DefaultValue $false)
        local_preview_freshness_source = Get-EventValue -Event $latestLocalPreview -Name 'freshness_source' -DefaultValue $null
        decode_freshness_source = Get-EventValue -Event $latestDecode -Name 'freshness_source' -DefaultValue $null
        render_freshness_source = Get-EventValue -Event $latestRender -Name 'freshness_source' -DefaultValue $null
        local_preview_unique_fps = Get-EventValue -Event $latestLocalPreview -Name 'unique_fps' -DefaultValue $null
        decode_unique_fps = Get-EventValue -Event $latestDecode -Name 'unique_fps' -DefaultValue $null
        render_unique_fps = Get-EventValue -Event $latestRender -Name 'unique_fps' -DefaultValue $null
        receiver_fps = Get-EventValue -Event $latestRender -Name 'receiver_fps' -DefaultValue (Get-EventValue -Event $latestDecode -Name 'receiver_fps' -DefaultValue $null)
        received_fps = Get-EventValue -Event $latestRender -Name 'received_fps' -DefaultValue (Get-EventValue -Event $latestDecode -Name 'received_fps' -DefaultValue $null)
        decoded_fps = Get-EventValue -Event $latestRender -Name 'decoded_fps' -DefaultValue (Get-EventValue -Event $latestDecode -Name 'decoded_fps' -DefaultValue $null)
        rendered_fps = Get-EventValue -Event $latestRender -Name 'rendered_fps' -DefaultValue (Get-EventValue -Event $latestDecode -Name 'rendered_fps' -DefaultValue $null)
        receiver_stats_sample_window_ms = Get-EventValue -Event $latestRender -Name 'receiver_stats_sample_window_ms' -DefaultValue (Get-EventValue -Event $latestDecode -Name 'receiver_stats_sample_window_ms' -DefaultValue $null)
        outputs = @(
            'receiver-summary.json',
            'receiver-summary.md',
            'events.jsonl',
            'local-preview-freshness.json',
            'decoded-freshness.json',
            'rendered-freshness.json'
        )
    }
    ConvertTo-SafeJson -Value $summary |
        Set-Content -LiteralPath (Join-Path $RunDirectory 'receiver-summary.json') -Encoding utf8

    @(
        "# In-Process Receiver Probe $RunId",
        '',
        "- status: $Status",
        "- mode: $Mode",
        "- in_process: true",
        "- events: $($Events.Count)",
        "- local_preview events: $($localPreviewEvents.Count)",
        "- remote_decode events: $($decodeEvents.Count)",
        "- remote_renderer_callback lane events: $($renderEvents.Count)",
            "- source_lineage: frame_id_events=$($sourceLineage.source_frame_id_event_count); previous_frame_id_events=$($sourceLineage.previous_frame_id_event_count); marker_id_events=$($sourceLineage.source_frame_marker_id_event_count); source_qpc_events=$($sourceLineage.source_qpc_event_count); stage_qpc_events=$($sourceLineage.stage_qpc_event_count); complete=$($sourceLineage.source_lineage_available); reason=$($sourceLineage.source_lineage_reason)",
        "- local_preview_freshness_source: $($summary.local_preview_freshness_source)",
        "- decode_freshness_source: $($summary.decode_freshness_source)",
        "- render_freshness_source: $($summary.render_freshness_source)",
        "- local_preview_unique_fps: $($summary.local_preview_unique_fps)",
        "- decode_unique_fps: $($summary.decode_unique_fps)",
        "- render_unique_fps: $($summary.render_unique_fps)",
        "- receiver_fps: $($summary.receiver_fps)",
        "- received_decoded_rendered_fps: $($summary.received_fps)/$($summary.decoded_fps)/$($summary.rendered_fps)",
        "- receiver_stats_sample_window_ms: $($summary.receiver_stats_sample_window_ms)",
        '',
        "Blocking reason: $Reason",
        '',
        'Events are expected to be redacted before ingestion. This runner does not accept LiveKit tokens or Matrix identifiers in this mode.'
    ) | Set-Content -LiteralPath (Join-Path $RunDirectory 'receiver-summary.md') -Encoding utf8
}

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$envScript = Join-Path $scriptDir 'stream_lab_env.ps1'
if (Test-Path $envScript) {
    . $envScript
    Import-StreamLabLocalEnv -RepoRoot $repoRoot
}
$workspaceRoot = if (Get-Command Resolve-StreamLabWorkspaceRoot -ErrorAction SilentlyContinue) {
    Resolve-StreamLabWorkspaceRoot -RepoRoot $repoRoot
} else {
    (Resolve-Path (Join-Path $repoRoot '..\..')).Path
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $streamLabDirectory = if (Get-Command Resolve-StreamLabDirectory -ErrorAction SilentlyContinue) {
        Resolve-StreamLabDirectory -RepoRoot $repoRoot -WorkspaceRoot $workspaceRoot
    } else {
        Join-Path $workspaceRoot 'runtime\stream-lab'
    }
    $OutputRoot = Join-Path $streamLabDirectory 'receiver-results'
} elseif (Get-Command Resolve-StreamLabConfiguredPath -ErrorAction SilentlyContinue) {
    $OutputRoot = Resolve-StreamLabConfiguredPath -Value $OutputRoot -BasePath $repoRoot
}

$runDirectory = Join-Path $OutputRoot $RunId
$baseReport = @{
    run_id = $RunId
    mode = $Mode
    duration_seconds = $DurationSeconds
    expected_width = $ExpectedWidth
    expected_height = $ExpectedHeight
    expected_fps = $ExpectedFps
    probe_monitor_index = $ProbeMonitorIndex
    frame_diagnostics_mode = $FrameDiagnosticsMode
    created_utc = (Get-Date).ToUniversalTime().ToString('o')
    diagnostic_contract = 'docs/architecture/calls-streaming-audio/stream-receiver-diagnostic-contract.md'
    notes = @(
        'This runner enforces the receiver-lab contract only.',
        'It does not tune sender capture, bitrate, fallback, TURN, LiveKit server policy, receiver quality policy, stream profiles, Vulkan, or DX12.',
        'LiveKit tokens must be delivered through protected local IPC by a SERVER-owned flow; command-line token arguments are intentionally unsupported.'
    )
    required_outputs = @(
        'receiver-summary.json',
        'receiver-summary.md',
        'events.jsonl',
        'local-preview-freshness.json for local-preview mode',
        'decoded-freshness.json',
        'rendered-freshness.json for render mode'
    )
}

if ($Mode -eq 'InProcessDecodeOnly' -or $Mode -eq 'InProcessRender' -or $Mode -eq 'InProcessLocalPreview') {
    if ([string]::IsNullOrWhiteSpace($InProcessEventsPath)) {
        $report = $baseReport.Clone()
        $report.status = 'blocked_missing_in_process_events'
        $report.blocking_reason = 'Run with -InProcessEventsPath pointing to redacted in-process receiver probe events.'
        Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
        Write-ReceiverRunError -Message $report.blocking_reason
        exit 2
    }

    $events = @(Read-ReceiverProbeEvents -Path $InProcessEventsPath |
        Where-Object { (Get-EventValue -Event $_ -Name 'marker' -DefaultValue '') -eq 'intergalactic_stream_view_probe' })
    $decodeEvents = @($events | Where-Object { (Get-EventValue -Event $_ -Name 'lane' -DefaultValue '') -eq 'remote_decode' })
    $renderEvents = @($events | Where-Object { Test-ReceiverRendererCallbackLane -Event $_ })
    $localPreviewEvents = @($events | Where-Object { (Get-EventValue -Event $_ -Name 'lane' -DefaultValue '') -eq 'local_preview' })
    $targetEvents = @(
        if ($Mode -eq 'InProcessRender') {
            $renderEvents
        } elseif ($Mode -eq 'InProcessLocalPreview') {
            $localPreviewEvents
        } else {
            $decodeEvents
        }
    )
    $latestTarget = if ($targetEvents.Count -gt 0) { $targetEvents[-1] } else { $null }
    $uniqueFpsValue = Get-EventValue -Event $latestTarget -Name 'unique_fps' -DefaultValue $null
    $uniqueFps = if ($null -eq $uniqueFpsValue) { $null } else { [double]$uniqueFpsValue }
    $freshnessSource = Get-EventValue -Event $latestTarget -Name 'freshness_source' -DefaultValue $null

    $status = if ($Mode -eq 'InProcessLocalPreview') {
        'completed_local_preview_probe_events'
    } else {
        'completed_receiver_probe_events'
    }
    $reason = ''
    if ($events.Count -eq 0) {
        $status = 'inconclusive_no_receiver_probe_events'
        $reason = 'No intergalactic_stream_view_probe events were present in the in-process event file.'
    } elseif ($Mode -eq 'InProcessLocalPreview' -and $localPreviewEvents.Count -eq 0) {
        $status = 'inconclusive_missing_local_preview_events'
        $reason = 'No local_preview probe events were present.'
    } elseif ($Mode -ne 'InProcessLocalPreview' -and $decodeEvents.Count -eq 0) {
        $status = 'inconclusive_missing_remote_decode_events'
        $reason = 'No remote_decode receiver events were present.'
    } elseif ($Mode -eq 'InProcessRender' -and $renderEvents.Count -eq 0) {
        $status = 'inconclusive_missing_remote_renderer_callback_events'
        $reason = 'Render mode did not produce remote_renderer_callback events.'
    } elseif ($Mode -eq 'InProcessRender' -and -not (
        @($renderEvents | Where-Object {
            [bool](Get-EventValue -Event $_ -Name 'renderer_attached' -DefaultValue $false) -and
            [bool](Get-EventValue -Event $_ -Name 'renderer_visible' -DefaultValue $false)
        }).Count -gt 0
    )) {
        $status = 'invalid_remote_renderer_callback_not_visible'
        $reason = 'Render mode requires renderer_attached=true and renderer_visible=true.'
    } elseif ($null -eq $uniqueFps) {
        $status = 'inconclusive_frame_hash_tap_pending'
        $reason = 'Target events were observed, but frame hash taps did not report unique_fps.'
    } elseif (-not (Test-ReceiverFrameHashFreshnessSource -Source $freshnessSource)) {
        $status = 'inconclusive_frame_hash_tap_pending'
        $reason = 'Target unique_fps was present, but freshness_source was not frame_hash_tap.'
    } elseif ($uniqueFps -lt $MinUniqueFps) {
        $status = 'failed_receiver_freshness_gate'
        $reason = "Target unique_fps $uniqueFps was below required minimum $MinUniqueFps."
    }

    Write-InProcessReceiverOutputs `
        -RunDirectory $runDirectory `
        -Events $events `
        -Status $status `
        -Reason $reason

    $report = $baseReport.Clone()
    $report.status = $status
    $report.blocking_reason = $reason
    $report.receiver_summary = Join-Path $runDirectory 'receiver-summary.json'
    $report.in_process_events = $InProcessEventsPath
    $report.min_unique_fps = $MinUniqueFps
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report

    if (Test-ReceiverSummaryStatusBlocksRun -Status $status) {
        Write-ReceiverRunError -Message $reason
        exit 6
    }

    Write-Host "In-process receiver probe report written to $runDirectory"
    exit 0
}

if ($PlanOnly -or $Mode -eq 'Plan') {
    $report = $baseReport.Clone()
    $report.status = 'planned_receiver_probe_not_implemented'
    $report.lanes = @('local_preview', 'remote_decode', 'remote_renderer_callback')
    $report.validation_order = @(
        'synthetic_local_preview',
        'synthetic_in_process_decode_only',
        'synthetic_in_process_render_visible',
        'dedicated_probe_decode_only',
        'dedicated_probe_render_visible',
        'bg3_after_synthetic_receiver_tooling_is_trustworthy'
    )
    $report.blocking_reason = 'Frame taps, subscribe-only receiver connection, dedicated probe executable, and SERVER-owned protected token handoff are not implemented yet.'
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-Host "Receiver probe plan written to $runDirectory"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ProbeExe)) {
    $report = $baseReport.Clone()
    $report.status = 'blocked_missing_probe_executable'
    $report.blocking_reason = 'Run with -ProbeExe after tools/stream-receiver-probe is implemented.'
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 2
}

$resolvedProbe = Resolve-Path -Path $ProbeExe -ErrorAction SilentlyContinue
if ($null -eq $resolvedProbe) {
    $report = $baseReport.Clone()
    $report.status = 'blocked_probe_executable_not_found'
    $report.blocking_reason = "Probe executable was not found: $ProbeExe"
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 2
}

if ([string]::IsNullOrWhiteSpace($ProbeControlPipe)) {
    $ProbeControlPipe = $env:INTERGALACTIC_RECEIVER_PROBE_CONTROL_PIPE
}

if ([string]::IsNullOrWhiteSpace($ProbeControlPipe)) {
    $report = $baseReport.Clone()
    $report.status = 'blocked_missing_protected_ipc'
    $report.blocking_reason = 'Set -ProbeControlPipe or INTERGALACTIC_RECEIVER_PROBE_CONTROL_PIPE. Tokens are not accepted on the command line.'
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 2
}

New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$probeMode = if ($Mode -eq 'Render') { 'render' } else { 'decode-only' }
$probeExtension = [System.IO.Path]::GetExtension($resolvedProbe.Path)
if ($probeExtension -ieq '.ps1') {
    $powerShellCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $powerShellCommand) {
        $powerShellCommand = Get-Command powershell.exe -ErrorAction Stop
    }

    $probeFilePath = $powerShellCommand.Source
    $probeArgs = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $resolvedProbe.Path,
        '-Mode',
        $probeMode,
        '-RunId',
        $RunId,
        '-DurationSeconds',
        $DurationSeconds.ToString(),
        '-ExpectedWidth',
        $ExpectedWidth.ToString(),
        '-ExpectedHeight',
        $ExpectedHeight.ToString(),
        '-ExpectedFps',
        $ExpectedFps.ToString(),
        '-OutputDir',
        $runDirectory,
        '-ControlPipe',
        $ProbeControlPipe,
        '-FrameDiagnosticsMode',
        $FrameDiagnosticsMode
    )
    if (-not [string]::IsNullOrWhiteSpace($ProbeAppExe)) {
        $probeArgs += @('-AppExe', $ProbeAppExe)
    }
    if ($ProbeMonitorIndex -ge 0) {
        $probeArgs += @('-RenderMonitorIndex', $ProbeMonitorIndex.ToString())
    }
    if ($VisualFrameMarker) {
        $probeArgs += @('-VisualFrameMarker')
    }
} else {
    $probeFilePath = $resolvedProbe.Path
    $probeArgs = @(
        '--mode', $probeMode,
        '--run-id', $RunId,
        '--duration-seconds', $DurationSeconds.ToString(),
        '--expected-width', $ExpectedWidth.ToString(),
        '--expected-height', $ExpectedHeight.ToString(),
        '--expected-fps', $ExpectedFps.ToString(),
        '--output-dir', $runDirectory,
        '--control-pipe', $ProbeControlPipe,
        '--frame-diagnostics-mode', $FrameDiagnosticsMode
    )
    if ($ProbeMonitorIndex -ge 0) {
        $probeArgs += @('--render-monitor-index', $ProbeMonitorIndex.ToString())
    }
    if ($VisualFrameMarker) {
        $probeArgs += @('--visual-frame-marker')
    }
}

$process = Start-Process `
    -FilePath $probeFilePath `
    -ArgumentList $probeArgs `
    -WorkingDirectory $runDirectory `
    -WindowStyle Hidden `
    -PassThru
$completed = $false
try {
    Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
    $completed = $true
} catch {
    $completed = $false
}

if (-not $completed) {
    Stop-ProcessTree -RootProcessId $process.Id
    $report = $baseReport.Clone()
    $report.status = 'blocked_probe_timeout'
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.blocking_reason = "Probe process exceeded timeout of $TimeoutSeconds seconds and was terminated by the runner."
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 3
}

$process.Refresh()

$summaryPath = Join-Path $runDirectory 'receiver-summary.json'
if (-not (Test-Path $summaryPath)) {
    $report = $baseReport.Clone()
    $report.status = 'inconclusive_missing_receiver_summary'
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.probe_exit_code = $process.ExitCode
    $report.blocking_reason = 'Probe exited without receiver-summary.json.'
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 4
}

$summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
$summaryStatus = Get-ObjectPropertyOrDefault -Object $summary -Name 'status' -DefaultValue ''
if (Test-ReceiverSummaryStatusBlocksRun -Status $summaryStatus) {
    $report = $baseReport.Clone()
    $report.status = $summaryStatus.ToString()
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.probe_exit_code = $process.ExitCode
    $report.receiver_summary = $summaryPath
    $report.blocking_reason = Get-ObjectPropertyOrDefault `
        -Object $summary `
        -Name 'blocking_reason' `
        -DefaultValue 'Probe reported a non-passing receiver-lab status.'
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 6
}

if ($Mode -eq 'Render') {
    $rendererAttached = [bool](Get-ObjectPropertyOrDefault -Object $summary -Name 'renderer_attached' -DefaultValue $false)
    $rendererVisible = [bool](Get-ObjectPropertyOrDefault -Object $summary -Name 'renderer_visible' -DefaultValue $false)
    if (-not $rendererAttached -or -not $rendererVisible) {
        $report = $baseReport.Clone()
        $report.status = 'invalid_remote_renderer_callback_not_visible'
        $report.external_process = $true
        $report.probe_process_id = $process.Id
        $report.probe_exit_code = $process.ExitCode
        $report.blocking_reason = 'Render mode requires renderer_attached=true and renderer_visible=true.'
        Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
        Write-ReceiverRunError -Message $report.blocking_reason
        exit 5
    }
}

$statsOnlyFrameDiagnostics = $FrameDiagnosticsMode -eq 'stats-only'
if ($statsOnlyFrameDiagnostics) {
    $finalReport = $baseReport.Clone()
    $finalReport.status = if ($process.ExitCode -eq 0) {
        'completed_external_receiver_probe_stats_only_events'
    } else {
        'probe_failed'
    }
    $finalReport.external_process = $true
    $finalReport.probe_process_id = $process.Id
    $finalReport.probe_exit_code = $process.ExitCode
    $finalReport.receiver_summary = $summaryPath
    $finalReport.frame_diagnostics_mode = $FrameDiagnosticsMode
    $finalReport.freshness_source = Get-ObjectPropertyOrDefault `
        -Object $summary `
        -Name 'freshness_source' `
        -DefaultValue $null
    $finalReport.notes = @($finalReport.notes) + @(
        'Frame hash diagnostics were intentionally disabled; use receiver-window screen-present visual evidence for freshness gating.'
    )
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $finalReport

    if ($process.ExitCode -ne 0) {
        exit $process.ExitCode
    }

    Write-Host "Receiver probe stats-only run written to $runDirectory"
    exit 0
}

$gate = Get-ReceiverGateSummary -Summary $summary -Mode $Mode
if ($null -eq $gate.unique_fps) {
    $report = $baseReport.Clone()
    $report.status = 'inconclusive_frame_hash_tap_pending'
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.probe_exit_code = $process.ExitCode
    $report.receiver_summary = $summaryPath
    $report.blocking_reason =
        "External $($gate.lane) probe summary did not report unique_fps."
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 6
}

if (-not (Test-ReceiverFrameHashFreshnessSource -Source $gate.freshness_source)) {
    $report = $baseReport.Clone()
    $report.status = 'inconclusive_frame_hash_tap_pending'
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.probe_exit_code = $process.ExitCode
    $report.receiver_summary = $summaryPath
    $report.blocking_reason =
        "External $($gate.lane) probe reported unique_fps, but freshness_source was not frame_hash_tap."
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 6
}

if ($gate.unique_fps -lt $MinUniqueFps) {
    $report = $baseReport.Clone()
    $report.status = 'failed_receiver_freshness_gate'
    $report.external_process = $true
    $report.probe_process_id = $process.Id
    $report.probe_exit_code = $process.ExitCode
    $report.receiver_summary = $summaryPath
    $report.min_unique_fps = $MinUniqueFps
    $report.observed_unique_fps = $gate.unique_fps
    $report.blocking_reason =
        "External $($gate.lane) unique_fps $($gate.unique_fps) was below required minimum $MinUniqueFps."
    Write-ReceiverRunReport -RunDirectory $runDirectory -Report $report
    Write-ReceiverRunError -Message $report.blocking_reason
    exit 6
}

$finalReport = $baseReport.Clone()
$finalReport.status = if ($process.ExitCode -eq 0) {
    'completed_external_receiver_probe_events'
} else {
    'probe_failed'
}
$finalReport.external_process = $true
$finalReport.probe_process_id = $process.Id
$finalReport.probe_exit_code = $process.ExitCode
$finalReport.receiver_summary = $summaryPath
$finalReport.min_unique_fps = $MinUniqueFps
$finalReport.observed_unique_fps = $gate.unique_fps
$finalReport.freshness_source = $gate.freshness_source
$finalReport.freshness_lane = $gate.lane
Write-ReceiverRunReport -RunDirectory $runDirectory -Report $finalReport

if ($process.ExitCode -ne 0) {
    exit $process.ExitCode
}

Write-Host "Receiver probe run written to $runDirectory"
exit 0
