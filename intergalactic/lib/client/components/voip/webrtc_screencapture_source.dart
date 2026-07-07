import 'package:intergalactic/client/components/voip/android_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/screen_capture_source_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tiamat/atoms/popup_dialog.dart';

class WebrtcScreencaptureSource implements ScreenCaptureSource {
  static const _thumbnailWarmupTimeout = Duration(milliseconds: 700);
  static const _thumbnailWarmupPoll = Duration(milliseconds: 75);

  DesktopCapturerSource source;

  WebrtcScreencaptureSource(this.source);

  static Future<WebrtcScreencaptureSource?> findAnyWindowPlaceholder({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (PlatformUtils.isAndroid || PlatformUtils.displayServer == "wayland") {
      return null;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: ThumbnailSize(1, 1),
      );
      if (sources.isNotEmpty) {
        return WebrtcScreencaptureSource(sources.first);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  static Future<ScreenCaptureSource?> findWindowByTitle(
    String title, {
    Duration timeout = const Duration(seconds: 5),
    bool shareAudio = false,
  }) async {
    if (PlatformUtils.isAndroid ||
        PlatformUtils.displayServer == "wayland" ||
        title.trim().isEmpty) {
      return null;
    }

    final normalizedTitle = _normalizeWindowTitle(title);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      var sources = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: ThumbnailSize(360, 220),
      );
      sources = _filterShareableSourcesForPicker(sources);
      for (final source in sources) {
        final normalizedSourceName = _normalizeWindowTitle(source.name);
        if (normalizedSourceName == normalizedTitle ||
            normalizedSourceName.startsWith('$normalizedTitle |')) {
          final videoSource = WebrtcScreencaptureSource(source);
          final shareSession = await ShareSession.forDesktopCapturerSource(
            source,
            shareAudio: shareAudio,
          );
          _logSelectedShareSession(shareSession);
          return ShareCaptureSource(
            videoSource: videoSource,
            shareSession: shareSession,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  static Future<ScreenCaptureSource?> findWindowByProcessId(
    int processId, {
    Duration timeout = const Duration(seconds: 5),
    bool shareAudio = false,
  }) async {
    if (PlatformUtils.isAndroid ||
        PlatformUtils.displayServer == "wayland" ||
        processId <= 0) {
      return null;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      var sources = await desktopCapturer.getSources(
        types: [SourceType.Window],
        thumbnailSize: ThumbnailSize(360, 220),
      );
      sources = _filterShareableSourcesForPicker(sources);
      for (final source in sources) {
        final shareSession = await ShareSession.forDesktopCapturerSource(
          source,
          shareAudio: shareAudio,
        );
        if (shareSession.target.processId == processId) {
          _logSelectedShareSession(shareSession);
          return ShareCaptureSource(
            videoSource: WebrtcScreencaptureSource(source),
            shareSession: shareSession,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  static Future<ScreenCaptureSource?> showSelectSourcePrompt(
      BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      return WebrtcAndroidScreencaptureSource.getCaptureSource(context);
    }

    bool isWayland = PlatformUtils.displayServer == "wayland";

    var sources = await desktopCapturer.getSources(
      types: [if (!isWayland) SourceType.Window, SourceType.Screen],
      thumbnailSize: ThumbnailSize(360, 220),
    );
    sources = _filterShareableSourcesForPicker(sources);
    await _warmInitialThumbnails(
      sources,
      types: [if (!isWayland) SourceType.Window, SourceType.Screen],
    );
    _logSourcePickerDiagnostics(sources);

    if (isWayland && sources.isNotEmpty) {
      final videoSource = WebrtcScreencaptureSource(sources.first);
      final shareSession = await ShareSession.forDesktopCapturerSource(
        sources.first,
        shareAudio: true,
      );
      _logSelectedShareSession(shareSession);
      return ShareCaptureSource(
        videoSource: videoSource,
        shareSession: shareSession,
      );
    }

    if (context.mounted) {
      var result = await PopupDialog.show<ScreenCaptureSourceSelection>(context,
          content: ScreenCaptureSourceDialog(
              sources, desktopCapturer.onThumbnailChanged.stream),
          title: "Screen Share");

      if (result != null) {
        final videoSource = WebrtcScreencaptureSource(result.source);
        final shareSession = await ShareSession.forDesktopCapturerSource(
          result.source,
          shareAudio: result.shareAudio,
        );
        _logSelectedShareSession(shareSession);
        return ShareCaptureSource(
          videoSource: videoSource,
          shareSession: shareSession,
        );
      }
    }

    return null;
  }

  static void _logSelectedShareSession(ShareSession shareSession) {
    Log.i(
      'Selected desktop share source: '
      '${shareSession.diagnosticsSummary(
            includeTitle: preferences.developerMode.value &&
                preferences.showCallStreamStats.value,
          ).toLogLine()}',
    );
  }

  static Future<void> _warmInitialThumbnails(
    List<DesktopCapturerSource> sources, {
    required List<SourceType> types,
  }) async {
    await _waitForInitialThumbnails(sources);
    if (_thumbnailCount(sources) > 0) {
      return;
    }

    try {
      await desktopCapturer.updateSources(types: types);
      await _waitForInitialThumbnails(sources);
    } catch (_) {
      // Keep the picker usable even when a desktop backend cannot refresh
      // thumbnails on demand.
    }
  }

  static Future<void> _waitForInitialThumbnails(
    List<DesktopCapturerSource> sources,
  ) async {
    if (sources.isEmpty || _thumbnailCount(sources) > 0) {
      return;
    }

    final deadline = DateTime.now().add(_thumbnailWarmupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_thumbnailWarmupPoll);
      if (_thumbnailCount(sources) > 0) {
        return;
      }
    }
  }

  static int _thumbnailCount(List<DesktopCapturerSource> sources) {
    return sources
        .where((source) =>
            source.thumbnail != null && source.thumbnail!.isNotEmpty)
        .length;
  }

  static void _logSourcePickerDiagnostics(
    List<DesktopCapturerSource> sources,
  ) {
    final windows = sources
        .where((source) => source.type == SourceType.Window)
        .toList(growable: false);
    final screens = sources
        .where((source) => source.type == SourceType.Screen)
        .toList(growable: false);
    final windowThumbnails = windows
        .where((source) =>
            source.thumbnail != null && source.thumbnail!.isNotEmpty)
        .length;
    final screenThumbnails = screens
        .where((source) =>
            source.thumbnail != null && source.thumbnail!.isNotEmpty)
        .length;

    Log.i(
      'Screen share picker sources: '
      'windows=${windows.length} thumbnails=$windowThumbnails '
      'screens=${screens.length} thumbnails=$screenThumbnails',
    );

    if (!preferences.developerMode.value ||
        !preferences.showCallStreamStats.value) {
      return;
    }

    final sourceLines = sources.take(12).map((source) {
      final thumbnailBytes = source.thumbnail?.length ?? 0;
      return '${source.type.name}#${_shortSourceId(source.id)} '
          'thumb=${thumbnailBytes}B title="${_truncate(source.name)}"';
    }).join('; ');
    if (sourceLines.isNotEmpty) {
      Log.i('Screen share picker source detail: $sourceLines');
    }
  }

  static List<DesktopCapturerSource> _filterShareableSourcesForPicker(
    List<DesktopCapturerSource> sources,
  ) {
    final filtered =
        sources.where(_isShareablePickerSource).toList(growable: false);
    final filteredCount = sources.length - filtered.length;
    if (filteredCount > 0) {
      Log.i(
        'Screen share picker filtered $filteredCount '
        'desktop widget/overlay window source(s)',
      );
    }
    return filtered;
  }

  static bool _isShareablePickerSource(DesktopCapturerSource source) {
    if (source.type != SourceType.Window) {
      return true;
    }

    final normalizedName = _normalizeWindowTitle(source.name);
    if (normalizedName.isEmpty) {
      return true;
    }

    if (_desktopWidgetOverlayWindowTitles.contains(normalizedName)) {
      return false;
    }

    return !_desktopWidgetOverlayWindowTitleFragments.any(
      normalizedName.contains,
    );
  }

  static String _normalizeWindowTitle(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static const Set<String> _desktopWidgetOverlayWindowTitles = {
    'action center',
    'desktop',
    'desktopwindowxamlsource',
    'discord overlay',
    'game bar',
    'geforce experience overlay',
    'microsoft text input application',
    'nvidia geforce overlay',
    'notification center',
    'program manager',
    'quick settings',
    'rzmonitorforegroundwindow',
    'search',
    'searchhost',
    'shell experience host',
    'shellexperiencehost',
    'start',
    'startmenuexperiencehost',
    'steam overlay',
    'task switching',
    'task view',
    'taskbar',
    'textinputhost',
    'vksts',
    'widgets',
    'windows input experience',
    'windows shell experience host',
    'xbox game bar',
  };

  static const Set<String> _desktopWidgetOverlayWindowTitleFragments = {
    r'\rainmeter\skins\',
    '/rainmeter/skins/',
  };

  static String _shortSourceId(String value) {
    return shortShareSourceIdHash(value);
  }

  static String _truncate(String value, {int maxLength = 80}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}...';
  }
}

class IosReplaykitScreencaptureSource implements ScreenCaptureSource {
  const IosReplaykitScreencaptureSource();
}
