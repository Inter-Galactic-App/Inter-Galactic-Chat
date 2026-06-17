import 'package:intergalactic/config/custom_theme_definition.dart';

class ThemeTokenUsage {
  const ThemeTokenUsage({
    required this.targetId,
    required this.label,
  });

  final String targetId;
  final String label;
}

class ThemePreviewTarget {
  const ThemePreviewTarget({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

const String previewTargetFoundation = 'foundation';
const String previewTargetSidebar = 'sidebar';
const String previewTargetSelectedRoom = 'selected-room';
const String previewTargetUnreadBadge = 'unread-badge';
const String previewTargetHeader = 'room-header';
const String previewTargetPrimaryButton = 'primary-button';
const String previewTargetSecondaryChip = 'secondary-chip';
const String previewTargetComposer = 'composer';
const String previewTargetReceivedMessage = 'received-message';
const String previewTargetSentMessage = 'sent-message';
const String previewTargetLink = 'link';
const String previewTargetCodeBlock = 'code-block';
const String previewTargetSettingsTile = 'settings-tile';
const String previewTargetWarning = 'warning-card';
const String previewTargetAvatar = 'avatar';

const List<ThemePreviewTarget> themePreviewTargets = [
  ThemePreviewTarget(id: previewTargetFoundation, label: 'App background'),
  ThemePreviewTarget(id: previewTargetSidebar, label: 'Room list'),
  ThemePreviewTarget(id: previewTargetSelectedRoom, label: 'Selected room'),
  ThemePreviewTarget(id: previewTargetUnreadBadge, label: 'Unread badge'),
  ThemePreviewTarget(id: previewTargetHeader, label: 'Room header'),
  ThemePreviewTarget(id: previewTargetPrimaryButton, label: 'Primary button'),
  ThemePreviewTarget(id: previewTargetSecondaryChip, label: 'Reaction chip'),
  ThemePreviewTarget(id: previewTargetComposer, label: 'Composer'),
  ThemePreviewTarget(id: previewTargetReceivedMessage, label: 'Message bubble'),
  ThemePreviewTarget(id: previewTargetSentMessage, label: 'Sent message'),
  ThemePreviewTarget(id: previewTargetLink, label: 'Link'),
  ThemePreviewTarget(id: previewTargetCodeBlock, label: 'Code block'),
  ThemePreviewTarget(id: previewTargetSettingsTile, label: 'Settings tile'),
  ThemePreviewTarget(id: previewTargetWarning, label: 'Warning card'),
  ThemePreviewTarget(id: previewTargetAvatar, label: 'Avatar'),
];

const Map<String, List<ThemeTokenUsage>> themeTokenUsageMap = {
  'primary': [
    ThemeTokenUsage(
      targetId: previewTargetPrimaryButton,
      label: 'Primary button fill',
    ),
    ThemeTokenUsage(
      targetId: previewTargetHeader,
      label: 'Room header icon',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSelectedRoom,
      label: 'Selected room accent',
    ),
    ThemeTokenUsage(
      targetId: previewTargetUnreadBadge,
      label: 'Unread badge fill',
    ),
  ],
  'onPrimary': [
    ThemeTokenUsage(
      targetId: previewTargetPrimaryButton,
      label: 'Primary button text',
    ),
    ThemeTokenUsage(
      targetId: previewTargetUnreadBadge,
      label: 'Unread badge text',
    ),
  ],
  'primaryContainer': [
    ThemeTokenUsage(
      targetId: previewTargetSelectedRoom,
      label: 'Selected room background',
    ),
    ThemeTokenUsage(
      targetId: previewTargetAvatar,
      label: 'Avatar background',
    ),
  ],
  'onPrimaryContainer': [
    ThemeTokenUsage(
      targetId: previewTargetSelectedRoom,
      label: 'Selected room text',
    ),
    ThemeTokenUsage(
      targetId: previewTargetAvatar,
      label: 'Avatar initials',
    ),
  ],
  'secondary': [
    ThemeTokenUsage(
      targetId: previewTargetHeader,
      label: 'Call icon accent',
    ),
    ThemeTokenUsage(
      targetId: previewTargetComposer,
      label: 'Composer icon accent',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSecondaryChip,
      label: 'Reaction chip accent',
    ),
  ],
  'onSecondary': [
    ThemeTokenUsage(
      targetId: previewTargetSecondaryChip,
      label: 'Reaction chip icon',
    ),
  ],
  'secondaryContainer': [
    ThemeTokenUsage(
      targetId: previewTargetSecondaryChip,
      label: 'Reaction chip background',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSentMessage,
      label: 'Sent message sample',
    ),
  ],
  'onSecondaryContainer': [
    ThemeTokenUsage(
      targetId: previewTargetSecondaryChip,
      label: 'Reaction chip text',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSentMessage,
      label: 'Sent message text',
    ),
  ],
  'tertiary': [
    ThemeTokenUsage(
      targetId: previewTargetWarning,
      label: 'Status accent',
    ),
  ],
  'links': [
    ThemeTokenUsage(
      targetId: previewTargetLink,
      label: 'Message links',
    ),
  ],
  'codeHighlight': [
    ThemeTokenUsage(
      targetId: previewTargetCodeBlock,
      label: 'Code highlight',
    ),
  ],
  'surface': [
    ThemeTokenUsage(
      targetId: previewTargetSettingsTile,
      label: 'Settings card',
    ),
    ThemeTokenUsage(
      targetId: previewTargetReceivedMessage,
      label: 'Message bubble sample',
    ),
  ],
  'onSurface': [
    ThemeTokenUsage(
      targetId: previewTargetHeader,
      label: 'Main text',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSettingsTile,
      label: 'Settings text',
    ),
    ThemeTokenUsage(
      targetId: previewTargetReceivedMessage,
      label: 'Message text',
    ),
  ],
  'surfaceContainerLowest': [
    ThemeTokenUsage(
      targetId: previewTargetFoundation,
      label: 'Lowest app layer',
    ),
    ThemeTokenUsage(
      targetId: previewTargetReceivedMessage,
      label: 'Chat background',
    ),
  ],
  'surfaceContainerLow': [
    ThemeTokenUsage(
      targetId: previewTargetSidebar,
      label: 'Room list surface',
    ),
    ThemeTokenUsage(
      targetId: previewTargetComposer,
      label: 'Composer surface',
    ),
  ],
  'surfaceContainer': [
    ThemeTokenUsage(
      targetId: previewTargetHeader,
      label: 'Room header surface',
    ),
    ThemeTokenUsage(
      targetId: previewTargetReceivedMessage,
      label: 'Message card surface',
    ),
  ],
  'surfaceContainerHigh': [
    ThemeTokenUsage(
      targetId: previewTargetComposer,
      label: 'Input field surface',
    ),
    ThemeTokenUsage(
      targetId: previewTargetWarning,
      label: 'Raised status card',
    ),
  ],
  'surfaceContainerHighest': [
    ThemeTokenUsage(
      targetId: previewTargetSettingsTile,
      label: 'Raised settings surface',
    ),
  ],
  'outline': [
    ThemeTokenUsage(
      targetId: previewTargetSidebar,
      label: 'Room list border',
    ),
    ThemeTokenUsage(
      targetId: previewTargetHeader,
      label: 'Header divider',
    ),
    ThemeTokenUsage(
      targetId: previewTargetComposer,
      label: 'Input border',
    ),
    ThemeTokenUsage(
      targetId: previewTargetSettingsTile,
      label: 'Card border',
    ),
  ],
  'foundationColor': [
    ThemeTokenUsage(
      targetId: previewTargetFoundation,
      label: 'Main app background',
    ),
  ],
};

List<ThemeTokenUsage> usageForThemeToken(String tokenId) {
  return themeTokenUsageMap[tokenId] ?? const [];
}

Set<String> targetIdsForThemeToken(String? tokenId) {
  if (tokenId == null) {
    return const {};
  }

  return usageForThemeToken(tokenId).map((usage) => usage.targetId).toSet();
}

List<String> tokenIdsForPreviewTarget(String targetId) {
  return themeTokenUsageMap.entries
      .where(
        (entry) => entry.value.any((usage) => usage.targetId == targetId),
      )
      .map((entry) => entry.key)
      .toList();
}

String? primaryTokenForPreviewTarget(String targetId) {
  for (final entry in themeTokenUsageMap.entries) {
    if (entry.value.any((usage) => usage.targetId == targetId)) {
      return entry.key;
    }
  }

  return null;
}

String labelForPreviewTarget(String targetId) {
  for (final target in themePreviewTargets) {
    if (target.id == targetId) {
      return target.label;
    }
  }

  return 'Preview section';
}

String abbreviationForThemeToken(String tokenId) {
  return switch (tokenId) {
    'primary' => 'P',
    'onPrimary' => 'PA',
    'primaryContainer' => 'PC',
    'onPrimaryContainer' => 'PCA',
    'secondary' => 'S',
    'onSecondary' => 'SA',
    'secondaryContainer' => 'SC',
    'onSecondaryContainer' => 'SCA',
    'tertiary' => 'T',
    'links' => 'LN',
    'codeHighlight' => 'CH',
    'surface' => 'SF',
    'onSurface' => 'ST',
    'surfaceContainerLowest' => 'SC5',
    'surfaceContainerLow' => 'SC4',
    'surfaceContainer' => 'SC3',
    'surfaceContainerHigh' => 'SC2',
    'surfaceContainerHighest' => 'SC1',
    'outline' => 'OL',
    'foundationColor' => 'BG',
    _ => tokenId.substring(0, tokenId.length < 3 ? tokenId.length : 3),
  };
}

List<CustomThemeColorField> filterThemeTokenFields(
  Iterable<CustomThemeColorField> fields,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return fields.toList();
  }

  return fields.where((field) {
    final usage = usageForThemeToken(field.id);
    return field.id.toLowerCase().contains(normalized) ||
        field.label.toLowerCase().contains(normalized) ||
        field.group.toLowerCase().contains(normalized) ||
        usage.any((item) => item.label.toLowerCase().contains(normalized)) ||
        usage.any((item) => item.targetId.toLowerCase().contains(normalized));
  }).toList();
}
