import 'dart:convert';

enum BugReportSeverity {
  critical,
  high,
  medium,
  low,
  unknown;

  String get wireValue => name;

  String get label {
    return switch (this) {
      BugReportSeverity.critical => 'Critical',
      BugReportSeverity.high => 'High',
      BugReportSeverity.medium => 'Medium',
      BugReportSeverity.low => 'Low',
      BugReportSeverity.unknown => 'Unknown',
    };
  }

  /// Plain-language label shown in the guided form so users do not have to
  /// interpret unexplained P0/P1-style severity terms. Wire values are
  /// unchanged for backward compatibility with the support intake.
  String get plainLabel {
    return switch (this) {
      BugReportSeverity.critical => 'Crash or data concern',
      BugReportSeverity.high => 'Blocking',
      BugReportSeverity.medium => 'Disruptive',
      BugReportSeverity.low => 'Minor',
      BugReportSeverity.unknown => 'Not sure',
    };
  }

  String get plainDescription {
    return switch (this) {
      BugReportSeverity.critical =>
        'The app closes, freezes, or content may be missing.',
      BugReportSeverity.high => 'I cannot use the affected feature.',
      BugReportSeverity.medium =>
        'The problem makes a feature difficult to use.',
      BugReportSeverity.low =>
        'The app still works, but something looks or behaves incorrectly.',
      BugReportSeverity.unknown => 'Severity is unknown.',
    };
  }
}

/// How often the user sees the problem. Stable [value]s are sent in the payload
/// so support can filter by reproducibility without an exact repro count.
enum BugReportFrequency {
  always,
  usually,
  sometimes,
  once,
  unknown;

  String get value => name;

  String get label {
    return switch (this) {
      BugReportFrequency.always => 'Every time',
      BugReportFrequency.usually => 'Most of the time',
      BugReportFrequency.sometimes => 'Sometimes',
      BugReportFrequency.once => 'Only happened once',
      BugReportFrequency.unknown => 'Not sure',
    };
  }
}

/// A small category-specific follow-up question. When [options] is empty the
/// form renders a short text field; otherwise it renders a single-select so the
/// user picks a stable answer instead of typing free text.
class BugReportCategoryQuestion {
  const BugReportCategoryQuestion({
    required this.id,
    required this.prompt,
    this.options = const [],
  });

  final String id;
  final String prompt;
  final List<String> options;

  bool get isChoice => options.isNotEmpty;
}

/// A troubleshooting action the user may have already tried. Selected [id]s are
/// stored in the payload as structured values plus an optional free-text note.
class BugReportTroubleshootingOption {
  const BugReportTroubleshootingOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// The affected area of the app. The stable [id] is stored separately from the
/// displayed [label] so wording can change without breaking support routing.
enum BugReportCategory {
  callAudio,
  callVideo,
  streaming,
  messagesRooms,
  notifications,
  mediaUpload,
  stories,
  emotesStickers,
  accounts,
  encryption,
  settingsAccessibility,
  performanceCrash,
  desktopWindows,
  other;

  String get id {
    return switch (this) {
      BugReportCategory.callAudio => 'call_audio',
      BugReportCategory.callVideo => 'call_video',
      BugReportCategory.streaming => 'streaming',
      BugReportCategory.messagesRooms => 'messages_rooms',
      BugReportCategory.notifications => 'notifications',
      BugReportCategory.mediaUpload => 'media_upload',
      BugReportCategory.stories => 'stories',
      BugReportCategory.emotesStickers => 'emotes_stickers',
      BugReportCategory.accounts => 'accounts',
      BugReportCategory.encryption => 'encryption',
      BugReportCategory.settingsAccessibility => 'settings_accessibility',
      BugReportCategory.performanceCrash => 'performance_crash',
      BugReportCategory.desktopWindows => 'desktop_windows',
      BugReportCategory.other => 'other',
    };
  }

  String get label {
    return switch (this) {
      BugReportCategory.callAudio => 'Calls and audio',
      BugReportCategory.callVideo => 'Video calls and camera',
      BugReportCategory.streaming => 'Screen sharing and streaming',
      BugReportCategory.messagesRooms => 'Messages and rooms',
      BugReportCategory.notifications => 'Notifications',
      BugReportCategory.mediaUpload => 'Photos, videos, and file uploads',
      BugReportCategory.stories => 'Stories',
      BugReportCategory.emotesStickers => 'Emojis, stickers, and emoticons',
      BugReportCategory.accounts => 'Login, registration, and accounts',
      BugReportCategory.encryption => 'Encryption and message recovery',
      BugReportCategory.settingsAccessibility =>
        'Settings, themes, and accessibility',
      BugReportCategory.performanceCrash => 'Performance, freezing, or crashes',
      BugReportCategory.desktopWindows => 'Desktop windows and popouts',
      BugReportCategory.other => 'Other',
    };
  }

  static BugReportCategory? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final category in BugReportCategory.values) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  /// Heading for the contextual troubleshooting card shown after selection.
  String get troubleshootingTitle {
    return switch (this) {
      BugReportCategory.callAudio => 'Having call audio trouble?',
      BugReportCategory.callVideo => 'Having video or camera trouble?',
      BugReportCategory.streaming => 'Having screen sharing trouble?',
      BugReportCategory.messagesRooms => 'Having messaging trouble?',
      BugReportCategory.notifications => 'Not getting the right notifications?',
      BugReportCategory.mediaUpload => 'Having trouble with photos or files?',
      BugReportCategory.stories => 'Having trouble with stories?',
      BugReportCategory.emotesStickers =>
        'Having trouble with emojis or stickers?',
      BugReportCategory.accounts => 'Having trouble signing in?',
      BugReportCategory.encryption =>
        'Missing encrypted messages or recovery prompts?',
      BugReportCategory.settingsAccessibility =>
        'Having trouble with settings or appearance?',
      BugReportCategory.performanceCrash => 'App freezing, closing, or slow?',
      BugReportCategory.desktopWindows =>
        'Having trouble with app windows or popouts?',
      BugReportCategory.other => 'Before you submit',
    };
  }

  /// Short, self-contained inline tips. These never block submission and never
  /// link to pages that do not exist. Categories without in-app troubleshooting
  /// routes are tracked as documentation follow-ups.
  List<String> get troubleshootingTips {
    return switch (this) {
      BugReportCategory.callAudio => const [
        'Check the selected speaker and microphone in call settings.',
        'Leave and rejoin the call.',
        'Confirm the participant is not muted or set to zero volume.',
      ],
      BugReportCategory.callVideo => const [
        'Turn the camera off and back on.',
        'Confirm the camera is not in use by another app.',
        'Rejoin the call if a remote video stays black.',
      ],
      BugReportCategory.streaming => const [
        'Try a lower quality preset if the stream is choppy.',
        'Restart the share if viewers see a black screen.',
        'Confirm the correct window or display is selected.',
      ],
      BugReportCategory.messagesRooms => const [
        'Open and close the affected room to refresh it.',
        'Check your network connection.',
        'Confirm the room is not still loading history.',
      ],
      BugReportCategory.notifications => const [
        'Check notification permissions for Inter Galactic.',
        'Confirm the room is not muted.',
        'Check battery or background restrictions on mobile.',
      ],
      BugReportCategory.mediaUpload => const [
        'Try a smaller or different file.',
        'Check storage and photo permissions.',
        'Retry on a different network.',
      ],
      BugReportCategory.stories => const [
        'Retry the capture or upload.',
        'Confirm camera and microphone permissions.',
        'Try a shorter clip if uploads fail.',
      ],
      BugReportCategory.emotesStickers => const [
        'Restart the app if custom emotes fail to load.',
        'Confirm the emote pack is still available in the space.',
      ],
      BugReportCategory.accounts => const [
        'Confirm the homeserver address is correct.',
        'Check your network connection.',
        'Try again in a moment if the server is busy.',
      ],
      BugReportCategory.encryption => const [
        'Open the affected room to trigger a decrypt retry.',
        'Confirm this session is verified in Security settings.',
        'Enter your recovery key if prompted.',
      ],
      BugReportCategory.settingsAccessibility => const [
        'Reopen the settings screen.',
        'Restart the app after changing a theme.',
      ],
      BugReportCategory.performanceCrash => const [
        'Restart the app.',
        'Check for an app update.',
        'Note what you were doing right before it happened.',
      ],
      BugReportCategory.desktopWindows => const [
        'Close and reopen the affected window or popout.',
        'Restart the app if a window is stuck off-screen.',
      ],
      BugReportCategory.other => const [
        'Restart the app and check for an update before submitting.',
      ],
    };
  }

  /// Category-specific troubleshooting actions appended to the universal list.
  List<BugReportTroubleshootingOption> get troubleshootingOptions {
    return switch (this) {
      BugReportCategory.callAudio => const [
        BugReportTroubleshootingOption(
          id: 'call_left_rejoined',
          label: 'Left and rejoined the call',
        ),
        BugReportTroubleshootingOption(
          id: 'call_mute_toggle',
          label: 'Muted and unmuted',
        ),
        BugReportTroubleshootingOption(
          id: 'call_changed_device',
          label: 'Changed microphone or speaker',
        ),
        BugReportTroubleshootingOption(
          id: 'call_checked_mic_permission',
          label: 'Checked microphone permissions',
        ),
        BugReportTroubleshootingOption(
          id: 'call_asked_others',
          label: 'Asked another participant if they had the same problem',
        ),
      ],
      BugReportCategory.callVideo => const [
        BugReportTroubleshootingOption(
          id: 'video_toggle_camera',
          label: 'Turned the camera off and on',
        ),
        BugReportTroubleshootingOption(
          id: 'video_checked_camera_permission',
          label: 'Checked camera permissions',
        ),
        BugReportTroubleshootingOption(
          id: 'call_left_rejoined',
          label: 'Left and rejoined the call',
        ),
      ],
      BugReportCategory.streaming => const [
        BugReportTroubleshootingOption(
          id: 'stream_restarted',
          label: 'Restarted the screen share',
        ),
        BugReportTroubleshootingOption(
          id: 'stream_changed_quality',
          label: 'Changed the quality preset',
        ),
        BugReportTroubleshootingOption(
          id: 'stream_changed_source',
          label: 'Changed the shared window or display',
        ),
      ],
      BugReportCategory.notifications => const [
        BugReportTroubleshootingOption(
          id: 'notif_checked_permission',
          label: 'Checked notification permissions',
        ),
        BugReportTroubleshootingOption(
          id: 'notif_toggled',
          label: 'Disabled and re-enabled notifications',
        ),
        BugReportTroubleshootingOption(
          id: 'notif_checked_battery',
          label: 'Checked battery or background restrictions',
        ),
      ],
      BugReportCategory.mediaUpload => const [
        BugReportTroubleshootingOption(
          id: 'media_smaller_file',
          label: 'Tried a smaller file',
        ),
        BugReportTroubleshootingOption(
          id: 'media_different_file',
          label: 'Tried a different file',
        ),
        BugReportTroubleshootingOption(
          id: 'media_checked_permission',
          label: 'Checked storage or photo permissions',
        ),
      ],
      BugReportCategory.encryption => const [
        BugReportTroubleshootingOption(
          id: 'enc_reopened_room',
          label: 'Reopened the affected room',
        ),
        BugReportTroubleshootingOption(
          id: 'enc_entered_recovery',
          label: 'Entered a recovery key',
        ),
        BugReportTroubleshootingOption(
          id: 'enc_verified_session',
          label: 'Verified this session',
        ),
      ],
      _ => const [],
    };
  }

  /// A short number of targeted follow-up questions. Only these are shown for
  /// the selected category, so users are not asked every possible question.
  List<BugReportCategoryQuestion> get questions {
    return switch (this) {
      BugReportCategory.callAudio => const [
        BugReportCategoryQuestion(
          id: 'could_hear_others',
          prompt: 'Could you hear other participants?',
          options: ['Yes', 'No', 'Not sure'],
        ),
        BugReportCategoryQuestion(
          id: 'others_could_hear',
          prompt: 'Could they hear you?',
          options: ['Yes', 'No', 'Not sure'],
        ),
        BugReportCategoryQuestion(
          id: 'scope',
          prompt: 'Was the problem limited to one person or everyone?',
          options: ['One person', 'Everyone', 'Not sure'],
        ),
        BugReportCategoryQuestion(
          id: 'rejoin_helped',
          prompt: 'Did leaving and rejoining temporarily fix it?',
          options: ['Yes', 'No', "Didn't try"],
        ),
        BugReportCategoryQuestion(
          id: 'audio_output',
          prompt: 'Were you using headphones, speakers, or Bluetooth?',
          options: ['Headphones', 'Speakers', 'Bluetooth', 'Not sure'],
        ),
      ],
      BugReportCategory.callVideo => const [
        BugReportCategoryQuestion(
          id: 'whose_camera',
          prompt: 'Was your camera affected or another participant’s?',
          options: ['Mine', 'Another participant', 'Both'],
        ),
        BugReportCategoryQuestion(
          id: 'video_symptom',
          prompt: 'Was the video frozen, black, delayed, or low quality?',
          options: ['Frozen', 'Black', 'Delayed', 'Low quality'],
        ),
        BugReportCategoryQuestion(
          id: 'toggle_helped',
          prompt: 'Did turning the camera off and on help?',
          options: ['Yes', 'No', "Didn't try"],
        ),
      ],
      BugReportCategory.streaming => const [
        BugReportCategoryQuestion(
          id: 'what_shared',
          prompt: 'What were you sharing?',
          options: ['A game', 'A window', 'A full display'],
        ),
        BugReportCategoryQuestion(
          id: 'visible_to',
          prompt: 'Was the problem visible to you, viewers, or both?',
          options: ['Me', 'Viewers', 'Both'],
        ),
        BugReportCategoryQuestion(
          id: 'stream_symptom',
          prompt:
              'Was the issue low frame rate, poor quality, black screen, crop, or no audio?',
          options: [
            'Low frame rate',
            'Poor quality',
            'Black screen',
            'Cropped',
            'No audio',
          ],
        ),
      ],
      BugReportCategory.notifications => const [
        BugReportCategoryQuestion(
          id: 'notif_symptom',
          prompt:
              'Were notifications missing, delayed, duplicated, or opening the wrong room?',
          options: ['Missing', 'Delayed', 'Duplicated', 'Wrong room'],
        ),
        BugReportCategoryQuestion(
          id: 'app_state',
          prompt:
              'Did the problem occur while the app was open, closed, or in the background?',
          options: ['Open', 'Closed', 'Background'],
        ),
        BugReportCategoryQuestion(
          id: 'notif_type',
          prompt:
              'Was this a message, call, mention, reaction, or story notification?',
          options: ['Message', 'Call', 'Mention', 'Reaction', 'Story'],
        ),
      ],
      BugReportCategory.messagesRooms => const [
        BugReportCategoryQuestion(
          id: 'message_symptom',
          prompt:
              'Were messages missing, duplicated, delayed, or unable to send?',
          options: ['Missing', 'Duplicated', 'Delayed', 'Could not send'],
        ),
        BugReportCategoryQuestion(
          id: 'room_encrypted',
          prompt: 'Was the room encrypted?',
          options: ['Yes', 'No', 'Not sure'],
        ),
        BugReportCategoryQuestion(
          id: 'room_scope',
          prompt: 'Did the issue affect one room or multiple rooms?',
          options: ['One room', 'Multiple rooms'],
        ),
      ],
      BugReportCategory.mediaUpload => const [
        BugReportCategoryQuestion(
          id: 'file_type',
          prompt: 'What type of file was involved?',
          options: ['Photo', 'Video', 'Other file'],
        ),
        BugReportCategoryQuestion(
          id: 'file_size',
          prompt: 'Approximate file size, if known',
        ),
        BugReportCategoryQuestion(
          id: 'upload_symptom',
          prompt:
              'Did the upload fail, freeze, display incorrectly, or disappear?',
          options: ['Failed', 'Froze', 'Displayed wrong', 'Disappeared'],
        ),
      ],
      BugReportCategory.stories => const [
        BugReportCategoryQuestion(
          id: 'story_stage',
          prompt:
              'Was the problem during capture, trimming, editing, uploading, or viewing?',
          options: ['Capture', 'Trimming', 'Editing', 'Uploading', 'Viewing'],
        ),
        BugReportCategoryQuestion(
          id: 'story_media',
          prompt: 'Was the media a photo or video?',
          options: ['Photo', 'Video'],
        ),
        BugReportCategoryQuestion(
          id: 'story_orientation',
          prompt: 'Was it portrait or landscape?',
          options: ['Portrait', 'Landscape'],
        ),
      ],
      BugReportCategory.performanceCrash => const [
        BugReportCategoryQuestion(
          id: 'crash_symptom',
          prompt: 'Did the app freeze, close, or become unresponsive?',
          options: ['Froze', 'Closed', 'Unresponsive'],
        ),
        BugReportCategoryQuestion(
          id: 'crash_recovered',
          prompt: 'Did the app recover by itself?',
          options: ['Yes', 'No'],
        ),
        BugReportCategoryQuestion(
          id: 'crash_reproducible',
          prompt: 'Can you make it happen again?',
          options: ['Yes', 'No', 'Not sure'],
        ),
      ],
      BugReportCategory.desktopWindows => const [
        BugReportCategoryQuestion(
          id: 'which_window',
          prompt: 'Which window was affected?',
          options: [
            'Main app',
            'Call popout',
            'Transparent call window',
            'Picture-in-picture',
          ],
        ),
        BugReportCategoryQuestion(
          id: 'window_symptom',
          prompt:
              'Was the issue position, border, transparency, resizing, focus, or controls?',
          options: [
            'Position',
            'Border',
            'Transparency',
            'Resizing',
            'Focus',
            'Controls',
          ],
        ),
      ],
      _ => const [],
    };
  }
}

/// Universal troubleshooting actions offered for every category.
const List<BugReportTroubleshootingOption> kUniversalTroubleshootingOptions = [
  BugReportTroubleshootingOption(
    id: 'reopened_screen',
    label: 'Closed and reopened the affected screen',
  ),
  BugReportTroubleshootingOption(
    id: 'restarted_app',
    label: 'Restarted the app',
  ),
  BugReportTroubleshootingOption(
    id: 'signed_out_in',
    label: 'Signed out and signed back in',
  ),
  BugReportTroubleshootingOption(
    id: 'restarted_device',
    label: 'Restarted the device',
  ),
  BugReportTroubleshootingOption(
    id: 'checked_update',
    label: 'Checked for an app update',
  ),
  BugReportTroubleshootingOption(
    id: 'tried_network',
    label: 'Tried a different network',
  ),
  BugReportTroubleshootingOption(
    id: 'changed_setting',
    label: 'Changed the relevant setting',
  ),
  BugReportTroubleshootingOption(
    id: 'fixed_itself',
    label: 'The problem fixed itself temporarily',
  ),
  BugReportTroubleshootingOption(id: 'nothing_yet', label: 'Nothing yet'),
];

enum BugReportTemplate {
  genericAppBug,
  callStreamLogs;

  String get tag {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'generic_app_bug',
      BugReportTemplate.callStreamLogs => 'call_stream_logs',
    };
  }

  String get label {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Generic app bug',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  bool get usesFixedDetails => this == BugReportTemplate.callStreamLogs;

  /// The generic template uses the guided diagnostic interview; fixed templates
  /// keep their static details block.
  bool get usesGuidedInterview => this == BugReportTemplate.genericAppBug;

  String get defaultTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  String get defaultReproductionSteps {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs =>
        'Call/stream logs template.\n\n'
            'Opened from Call Diagnostics > stream logs. Recent redacted logs '
            'include the current call diagnostics snapshot for support review.',
    };
  }

  String get defaultExpectedBehavior {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs =>
        'Call and stream diagnostics should include enough route, sender, '
            'receiver, stream-test, and recent redacted log context to classify '
            'the issue without changing the active media path.',
    };
  }

  String get defaultActualBehavior {
    return switch (this) {
      BugReportTemplate.genericAppBug => '',
      BugReportTemplate.callStreamLogs =>
        'The current call diagnostics snapshot was written into recent '
            'redacted logs. Keep logs enabled to attach that snapshot with this '
            'call/stream report.',
    };
  }
}

class BugReportInput {
  const BugReportInput({
    required this.title,
    required this.reproductionSteps,
    this.template = BugReportTemplate.genericAppBug,
    this.severity = BugReportSeverity.medium,
    this.category,
    this.whatHappened = '',
    this.frequency,
    this.expectedBehavior = '',
    this.actualBehavior = '',
    this.troubleshootingTried = const [],
    this.troubleshootingNote = '',
    this.categoryAnswers = const {},
    this.additionalDetails = '',
    this.includeLogs = true,
    this.includeDiagnostics = true,
    this.additionalMetadata = const {},
    this.additionalAttachments = const [],
    this.reportNotice,
  });

  final String title;

  /// What the user was doing right before the problem (formerly framed as
  /// "reproduction steps").
  final String reproductionSteps;
  final BugReportTemplate template;
  final BugReportSeverity severity;

  /// Affected area of the app. Required by the guided form (enforced in the UI)
  /// but nullable so fixed-template and programmatic callers stay valid.
  final BugReportCategory? category;

  /// The primary, plain-language "What happened?" description.
  final String whatHappened;

  /// How often the problem happens.
  final BugReportFrequency? frequency;

  /// What the user expected to happen instead.
  final String expectedBehavior;

  /// Legacy field. New guided reports store the primary description in
  /// [whatHappened]; this remains for fixed templates and older callers.
  final String actualBehavior;

  /// Stable ids of troubleshooting actions the user already tried.
  final List<String> troubleshootingTried;
  final String troubleshootingNote;

  /// Category-specific follow-up answers keyed by question id.
  final Map<String, String> categoryAnswers;
  final String additionalDetails;

  final bool includeLogs;
  final bool includeDiagnostics;
  final Map<String, Object?> additionalMetadata;
  final List<BugReportAttachmentSummary> additionalAttachments;
  final String? reportNotice;

  /// The effective primary description: the guided [whatHappened] when present,
  /// otherwise the legacy [actualBehavior] so older callers keep working.
  String get effectiveWhatHappened {
    final happened = whatHappened.trim();
    return happened.isNotEmpty ? whatHappened : actualBehavior;
  }

  bool get requestsCallStreamDiagnostics {
    if (!includeDiagnostics) {
      return false;
    }
    if (template == BugReportTemplate.callStreamLogs) {
      return true;
    }
    return category == BugReportCategory.callAudio ||
        category == BugReportCategory.callVideo ||
        category == BugReportCategory.streaming;
  }

  /// Model-level validation, kept backward compatible: a title plus at least
  /// one description field. Category/frequency requirements are enforced by the
  /// guided form so programmatic and fixed-template callers are unaffected.
  String? validate() {
    if (title.trim().isEmpty) {
      return 'Enter a title for the bug report.';
    }
    if (reproductionSteps.trim().isEmpty &&
        effectiveWhatHappened.trim().isEmpty) {
      return 'Describe what happened before previewing the report.';
    }
    return null;
  }
}

class BugReportFeatureDiagnostics {
  const BugReportFeatureDiagnostics({
    required this.scope,
    required this.data,
    required this.logSummary,
  });

  final String scope;
  final Map<String, Object?> data;

  /// A compact, identifier-free line written before recent logs are collected.
  final String logSummary;

  Map<String, Object?> toJson() => {'scope': scope, 'data': data};
}

class BugReportAttachmentSummary {
  const BugReportAttachmentSummary({
    required this.field,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.contentBase64,
  });

  final String field;
  final String name;
  final String contentType;
  final int sizeBytes;
  final String contentBase64;

  Map<String, Object?> toJson() => {
    'name': name,
    'mimeType': contentType,
    'contentBase64': contentBase64,
  };
}

class BugReportPayload {
  const BugReportPayload({required this.data, required this.attachments});

  final Map<String, Object?> data;
  final List<BugReportAttachmentSummary> attachments;

  int get sizeBytes => utf8.encode(toCompactJson()).length;

  String toCompactJson() => jsonEncode(data);

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(data);
}

class BugReportSubmissionResult {
  const BugReportSubmissionResult({
    this.reportId,
    required this.message,
    this.responseBody,
  });

  final String? reportId;
  final String message;
  final Map<String, Object?>? responseBody;
}

class BugReportSubmissionException implements Exception {
  const BugReportSubmissionException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}
