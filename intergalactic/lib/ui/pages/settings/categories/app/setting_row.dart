import 'package:flutter/material.dart';

class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    required this.title,
    this.description,
    this.trailing,
    this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
    super.key,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackTrailing = trailing != null && constraints.maxWidth < 520;
          final Widget? trailingWidget = trailing == null
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: trailing!,
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stackTrailing)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsRowLabel(
                      title: title,
                      description: description,
                    ),
                    const SizedBox(height: 10),
                    trailingWidget!,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _SettingsRowLabel(
                        title: title,
                        description: description,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 24),
                      trailingWidget!,
                    ],
                  ],
                ),
              if (child != null) ...[
                const SizedBox(height: 12),
                child!,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SettingsRowLabel extends StatelessWidget {
  const _SettingsRowLabel({
    required this.title,
    required this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
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
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    this.showDivider = true,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
          ...children,
          if (showDivider)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Divider(
                color: theme.colorScheme.outline.withValues(alpha: 1),
                height: 1,
                thickness: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}
