import 'package:flutter/material.dart';

enum SettingsStatusTone {
  neutral,
  accent,
  warning,
  danger,
}

class SettingsStatusChip extends StatelessWidget {
  const SettingsStatusChip({
    required this.icon,
    required this.label,
    this.compactLabel,
    this.semanticLabel,
    this.tone = SettingsStatusTone.neutral,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? compactLabel;
  final String? semanticLabel;
  final SettingsStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _toneColor(theme.colorScheme, tone);
    final compact =
        compactLabel != null && MediaQuery.sizeOf(context).width < 420;
    final displayedLabel = compact ? compactLabel! : label;
    final maxLabelWidth = compact ? 132.0 : 240.0;

    return Semantics(
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: tone == SettingsStatusTone.neutral
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.7)
                  : color.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  displayedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsStatePanel extends StatelessWidget {
  const SettingsStatePanel({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.tone = SettingsStatusTone.neutral,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  final SettingsStatusTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _toneColor(theme.colorScheme, tone);

    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: tone == SettingsStatusTone.neutral
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.8)
                : iconColor.withValues(alpha: 0.38),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 480;
              final body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: iconColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (action == null) {
                return body;
              }

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: action!,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: body),
                  const SizedBox(width: 16),
                  action!,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class SettingsActionChoiceCard extends StatelessWidget {
  const SettingsActionChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.detail,
    required this.action,
    this.tone = SettingsStatusTone.neutral,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String detail;
  final Widget action;
  final SettingsStatusTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _toneColor(theme.colorScheme, tone);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: tone == SettingsStatusTone.neutral
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.8)
              : iconColor.withValues(alpha: 0.38),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 520;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: iconColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: action,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: content),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 150),
                  child: action,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _toneColor(ColorScheme scheme, SettingsStatusTone tone) {
  return switch (tone) {
    SettingsStatusTone.neutral => scheme.onSurfaceVariant,
    SettingsStatusTone.accent => scheme.primary,
    SettingsStatusTone.warning => scheme.tertiary,
    SettingsStatusTone.danger => scheme.error,
  };
}
