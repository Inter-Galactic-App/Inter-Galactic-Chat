import 'package:flutter/material.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/theme_token_usage_map.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ThemePreviewPanel extends StatelessWidget {
  const ThemePreviewPanel({
    super.key,
    required this.highlightedTargetIds,
    required this.selectedTargetId,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final String? selectedTargetId;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foundationColor =
        Theme.of(context).extension<FoundationSettings>()?.color ??
        colorScheme.surfaceContainerLowest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;

        return Container(
          key: const ValueKey('theme-preview-panel'),
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            color: foundationColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.42),
            ),
          ),
          child: compact ? _buildCompact(context) : _buildDesktop(context),
        );
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewHeader(
          highlightedTargetIds: highlightedTargetIds,
          selectedTargetId: selectedTargetId,
          onTargetSelected: onTargetSelected,
        ),
        Expanded(
          child: Row(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 220,
                child: _PreviewSidebar(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
              ),
              Expanded(
                child: _PreviewChat(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
              ),
            ],
          ),
        ),
        _PreviewSettingsTile(
          highlightedTargetIds: highlightedTargetIds,
          onTargetSelected: onTargetSelected,
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        spacing: 10,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewHeader(
            highlightedTargetIds: highlightedTargetIds,
            selectedTargetId: selectedTargetId,
            onTargetSelected: onTargetSelected,
          ),
          TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: const [
              Tab(text: 'Rooms'),
              Tab(text: 'Chat'),
              Tab(text: 'Settings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PreviewSidebar(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
                _PreviewChat(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
                SingleChildScrollView(
                  child: Column(
                    spacing: 10,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PreviewSettingsTile(
                        highlightedTargetIds: highlightedTargetIds,
                        onTargetSelected: onTargetSelected,
                      ),
                      _PreviewLinkAndCodeRow(
                        highlightedTargetIds: highlightedTargetIds,
                        onTargetSelected: onTargetSelected,
                      ),
                      _PreviewWarningCard(
                        highlightedTargetIds: highlightedTargetIds,
                        onTargetSelected: onTargetSelected,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.highlightedTargetIds,
    required this.selectedTargetId,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final String? selectedTargetId;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Live app preview',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _PreviewTargetShell(
              targetId: previewTargetUnreadBadge,
              label: 'Unread badge',
              highlightedTargetIds: highlightedTargetIds,
              onTargetSelected: onTargetSelected,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '4',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (selectedTargetId != null)
          _PreviewTargetSwatchStrip(targetId: selectedTargetId!),
      ],
    );
  }
}

class _PreviewTargetSwatchStrip extends StatelessWidget {
  const _PreviewTargetSwatchStrip({required this.targetId});

  final String targetId;

  @override
  Widget build(BuildContext context) {
    final tokenIds = tokenIdsForPreviewTarget(targetId);
    if (tokenIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.32)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${labelForPreviewTarget(targetId)} swatches',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            for (final tokenId in tokenIds) ...[
              _PreviewTokenSwatch(tokenId: tokenId),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewTokenSwatch extends StatelessWidget {
  const _PreviewTokenSwatch({required this.tokenId});

  final String tokenId;

  @override
  Widget build(BuildContext context) {
    final color = _previewTokenColor(context, tokenId);
    final label = abbreviationForThemeToken(tokenId);

    return tiamat.Tooltip(
      text: _themeFieldLabel(tokenId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.78)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 0.7,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSidebar extends StatelessWidget {
  const _PreviewSidebar({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _PreviewTargetShell(
      targetId: previewTargetSidebar,
      label: 'Room list',
      highlightedTargetIds: highlightedTargetIds,
      onTargetSelected: onTargetSelected,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rooms',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _RoomPreviewRow(
              title: 'Bridge Crew',
              subtitle: 'Active now',
              selected: true,
              highlightedTargetIds: highlightedTargetIds,
              onTargetSelected: onTargetSelected,
            ),
            const SizedBox(height: 8),
            _RoomPreviewRow(
              title: 'Media Lab',
              subtitle: '2 mentions',
              selected: false,
              highlightedTargetIds: highlightedTargetIds,
              onTargetSelected: onTargetSelected,
            ),
            const SizedBox(height: 8),
            _RoomPreviewRow(
              title: 'Design',
              subtitle: 'Drafts',
              selected: false,
              highlightedTargetIds: highlightedTargetIds,
              onTargetSelected: onTargetSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPreviewRow extends StatelessWidget {
  const _RoomPreviewRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final row = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.36))
            : null,
      ),
      child: Row(
        children: [
          _PreviewTargetShell(
            targetId: previewTargetAvatar,
            label: 'Avatar',
            highlightedTargetIds: highlightedTargetIds,
            onTargetSelected: onTargetSelected,
            compact: true,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: selected
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer,
              child: Text(
                selected ? 'B' : title.substring(0, 1),
                style: TextStyle(
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.74)
                        : colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!selected) {
      return row;
    }

    return _PreviewTargetShell(
      targetId: previewTargetSelectedRoom,
      label: 'Selected room',
      highlightedTargetIds: highlightedTargetIds,
      onTargetSelected: onTargetSelected,
      child: row,
    );
  }
}

class _PreviewChat extends StatelessWidget {
  const _PreviewChat({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.32)),
      ),
      child: Column(
        children: [
          _PreviewTargetShell(
            targetId: previewTargetHeader,
            label: 'Room header',
            highlightedTargetIds: highlightedTargetIds,
            onTargetSelected: onTargetSelected,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tag, color: colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bridge Crew',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.call, color: colorScheme.secondary, size: 18),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _MessageBubblePreview(
                  targetId: previewTargetReceivedMessage,
                  label: 'Message bubble',
                  sender: 'Mira',
                  body: 'Primary colors should feel clear in active states.',
                  outgoing: false,
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
                const SizedBox(height: 8),
                _MessageBubblePreview(
                  targetId: previewTargetSentMessage,
                  label: 'Sent message',
                  sender: 'You',
                  body: 'Secondary containers can preview sent messages.',
                  outgoing: true,
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
                const SizedBox(height: 8),
                _PreviewLinkAndCodeRow(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
                const SizedBox(height: 8),
                _PreviewWarningCard(
                  highlightedTargetIds: highlightedTargetIds,
                  onTargetSelected: onTargetSelected,
                ),
              ],
            ),
          ),
          _PreviewComposer(
            highlightedTargetIds: highlightedTargetIds,
            onTargetSelected: onTargetSelected,
          ),
        ],
      ),
    );
  }
}

class _MessageBubblePreview extends StatelessWidget {
  const _MessageBubblePreview({
    required this.targetId,
    required this.label,
    required this.sender,
    required this.body,
    required this.outgoing,
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final String targetId;
  final String label;
  final String sender;
  final String body;
  final bool outgoing;
  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = outgoing
        ? colorScheme.secondaryContainer
        : colorScheme.surface;
    final foreground = outgoing
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.72,
        child: _PreviewTargetShell(
          targetId: targetId,
          label: label,
          highlightedTargetIds: highlightedTargetIds,
          onTargetSelected: onTargetSelected,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: outgoing ? foreground : colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewLinkAndCodeRow extends StatelessWidget {
  const _PreviewLinkAndCodeRow({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final extraColors =
        Theme.of(context).extension<ExtraColors>() ??
        ExtraColors.fromScheme(colorScheme);

    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: _PreviewTargetShell(
            targetId: previewTargetLink,
            label: 'Link',
            highlightedTargetIds: highlightedTargetIds,
            onTargetSelected: onTargetSelected,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Open link',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: extraColors.linkColor,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _PreviewTargetShell(
            targetId: previewTargetCodeBlock,
            label: 'Code block',
            highlightedTargetIds: highlightedTargetIds,
            onTargetSelected: onTargetSelected,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: extraColors.codeHighlight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'final theme',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _bestForeground(extraColors.codeHighlight),
                  fontFamily: 'RobotoCustom',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewWarningCard extends StatelessWidget {
  const _PreviewWarningCard({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _PreviewTargetShell(
      targetId: previewTargetWarning,
      label: 'Warning card',
      highlightedTargetIds: highlightedTargetIds,
      onTargetSelected: onTargetSelected,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.tertiary.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: colorScheme.tertiary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Save checks call out text and surface conflicts.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewComposer extends StatelessWidget {
  const _PreviewComposer({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _PreviewTargetShell(
      targetId: previewTargetComposer,
      label: 'Composer',
      highlightedTargetIds: highlightedTargetIds,
      onTargetSelected: onTargetSelected,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.48),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, color: colorScheme.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Message Bridge Crew',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.send, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _PreviewSettingsTile extends StatelessWidget {
  const _PreviewSettingsTile({
    required this.highlightedTargetIds,
    required this.onTargetSelected,
  });

  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _PreviewTargetShell(
      targetId: previewTargetSettingsTile,
      label: 'Settings tile',
      highlightedTargetIds: highlightedTargetIds,
      onTargetSelected: onTargetSelected,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.36),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.tune, color: colorScheme.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings tile',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Surfaces, text, and outlines together.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _PreviewTargetShell(
              targetId: previewTargetPrimaryButton,
              label: 'Primary button',
              highlightedTargetIds: highlightedTargetIds,
              onTargetSelected: onTargetSelected,
              compact: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Apply',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ),
    );
  }
}

class _PreviewTargetShell extends StatelessWidget {
  const _PreviewTargetShell({
    required this.targetId,
    required this.label,
    required this.highlightedTargetIds,
    required this.onTargetSelected,
    required this.child,
    this.compact = false,
  });

  final String targetId;
  final String label;
  final Set<String> highlightedTargetIds;
  final ValueChanged<String> onTargetSelected;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final highlighted = highlightedTargetIds.contains(targetId);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      key: ValueKey('preview-target-$targetId'),
      borderRadius: BorderRadius.circular(compact ? 999 : 14),
      onTap: () => onTargetSelected(targetId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: highlighted && !compact
            ? const EdgeInsets.all(3)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 999 : 14),
          border: highlighted
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.24),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (highlighted && !compact)
              Positioned(
                top: -8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _bestForeground(Color background) {
  return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

Color _previewTokenColor(BuildContext context, String tokenId) {
  for (final field in editableThemeColorFields) {
    if (field.id == tokenId) {
      return field.themeColor(Theme.of(context));
    }
  }

  return Theme.of(context).colorScheme.primary;
}

String _themeFieldLabel(String tokenId) {
  for (final field in editableThemeColorFields) {
    if (field.id == tokenId) {
      return field.label;
    }
  }

  return tokenId;
}
