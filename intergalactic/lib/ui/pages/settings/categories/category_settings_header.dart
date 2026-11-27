import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CategorySettingsHeader extends StatelessWidget {
  const CategorySettingsHeader({
    required this.name,
    required this.roomCountLabel,
    required this.collapsed,
    required this.actions,
    super.key,
  });

  static const _compactBreakpoint = 520.0;

  final String name;
  final String roomCountLabel;
  final bool collapsed;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBreakpoint;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryIdentity(
                name: name,
                roomCountLabel: roomCountLabel,
                collapsed: collapsed,
                showCountBelowName: true,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(alignment: WrapAlignment.end, children: actions),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _CategoryIdentity(
                name: name,
                roomCountLabel: roomCountLabel,
                collapsed: collapsed,
                showCountBelowName: false,
              ),
            ),
            const SizedBox(width: 8),
            ...actions,
          ],
        );
      },
    );
  }
}

class _CategoryIdentity extends StatelessWidget {
  const _CategoryIdentity({
    required this.name,
    required this.roomCountLabel,
    required this.collapsed,
    required this.showCountBelowName,
  });

  final String name;
  final String roomCountLabel;
  final bool collapsed;
  final bool showCountBelowName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameText = Text(
      name,
      maxLines: showCountBelowName ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            collapsed ? Icons.folder_outlined : Icons.folder_open_outlined,
            size: 20,
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: showCountBelowName
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nameText,
                    const SizedBox(height: 2),
                    tiamat.Text.labelLow(roomCountLabel),
                  ],
                )
              : nameText,
        ),
        if (!showCountBelowName) ...[
          const SizedBox(width: 8),
          tiamat.Text.labelLow(roomCountLabel),
        ],
      ],
    );
  }
}
