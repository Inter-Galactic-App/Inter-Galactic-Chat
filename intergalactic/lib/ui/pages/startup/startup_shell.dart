import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/windows/desktop_window_chrome.dart';

enum StartupPhase {
  preparing,
  preferences,
  localServices,
  storage,
  accounts,
  appServices,
  openingInterface,
}

extension StartupPhaseText on StartupPhase {
  String get title {
    return switch (this) {
      StartupPhase.preparing => "Preparing workspace",
      StartupPhase.preferences => "Loading preferences",
      StartupPhase.localServices => "Starting local services",
      StartupPhase.storage => "Opening app data",
      StartupPhase.accounts => "Restoring accounts",
      StartupPhase.appServices => "Preparing notifications",
      StartupPhase.openingInterface => "Opening Inter Galactic",
    };
  }

  String get detail {
    return switch (this) {
      StartupPhase.preparing => "Checking app startup.",
      StartupPhase.preferences => "Restoring your local app settings.",
      StartupPhase.localServices =>
        "Preparing privacy, audio, and activity helpers.",
      StartupPhase.storage => "Connecting local storage and configuration.",
      StartupPhase.accounts => "Loading saved Matrix sessions.",
      StartupPhase.appServices => "Starting app services.",
      StartupPhase.openingInterface => "Handing off to your chats.",
    };
  }
}

class StartupShell extends StatelessWidget {
  const StartupShell({
    super.key,
    required this.phaseListenable,
    required this.themeListenable,
  });

  static const String _appIconAsset =
      "assets/images/app_icon/app_icon_transparent_cropped.png";

  final ValueListenable<StartupPhase> phaseListenable;
  final ValueListenable<ThemeData> themeListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
      valueListenable: themeListenable,
      builder: (context, theme, child) {
        return MaterialApp(
          title: BuildConfig.app,
          theme: theme,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => DesktopWindowFrame(
            showNavigation: false,
            showHelp: false,
            child: child ?? const SizedBox.shrink(),
          ),
          home: ValueListenableBuilder<StartupPhase>(
            valueListenable: phaseListenable,
            builder: (context, phase, child) {
              return _StartupShellBody(phase: phase);
            },
          ),
        );
      },
    );
  }
}

class _StartupShellBody extends StatelessWidget {
  const _StartupShellBody({required this.phase});

  final StartupPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return _StartupMobileIntro(phase: phase);
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Semantics(
                container: true,
                liveRegion: true,
                label:
                    "${BuildConfig.app} is starting. ${phase.title}. ${phase.detail}",
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.18
                              : 0.08,
                        ),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.36,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Image.asset(
                                    StartupShell._appIconAsset,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        color: scheme.primary,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    BuildConfig.app,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Starting up",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        _StartupPhaseText(phase: phase),
                        const SizedBox(height: 18),
                        _StartupProgress(phase: phase),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupMobileIntro extends StatelessWidget {
  const _StartupMobileIntro({required this.phase});

  final StartupPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Semantics(
        container: true,
        liveRegion: true,
        label:
            "${BuildConfig.app} is starting. ${phase.title}. ${phase.detail}",
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.36),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(
                          alpha: theme.brightness == Brightness.dark
                              ? 0.18
                              : 0.08,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Image.asset(
                        StartupShell._appIconAsset,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: scheme.primary,
                            size: 52,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 96,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(999),
                    backgroundColor: scheme.outlineVariant.withValues(
                      alpha: 0.42,
                    ),
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupPhaseText extends StatelessWidget {
  const _StartupPhaseText({required this.phase});

  final StartupPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          phase.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          phase.detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StartupProgress extends StatelessWidget {
  const _StartupProgress({required this.phase});

  final StartupPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeIndex = StartupPhase.values.indexOf(phase);

    return Row(
      children: [
        for (var index = 0; index < StartupPhase.values.length; index++) ...[
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: index <= activeIndex
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox(height: 4),
            ),
          ),
          if (index != StartupPhase.values.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
