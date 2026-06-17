import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut_room_options.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class KeyboardHookShortcutsSettingsPage extends StatefulWidget {
  const KeyboardHookShortcutsSettingsPage({super.key});

  @override
  State<KeyboardHookShortcutsSettingsPage> createState() =>
      _KeyboardHookShortcutsSettingsPageState();

  static String get labelConfigureKeyboardShortcuts => Intl.message(
        "Configure Shortcuts",
        name: "labelConfigureKeyboardShortcuts",
        desc:
            "Label for the tile containing settings to configure system wide keyboard shortcuts, for muting, unmuting etc",
      );
}

class _KeyboardHookShortcutsSettingsPageState
    extends State<KeyboardHookShortcutsSettingsPage> {
  String get promptShortcutsPressAKeyCombination => Intl.message(
        "Press a key combination",
        name: "promptShortcutsPressAKeyCombination",
        desc:
            "Prompt the user to input a key combination, which is recorded and used to activate a shortcut",
      );

  String get promptShortcutsClearKeyboardShortcut => Intl.message(
        "Clear Shortcut",
        name: "promptShortcutsClearKeyboardShortcut",
        desc: "Prompt the user to clear a key combination shortcut",
      );

  String get promptKeyboardHookWarningTitle => Intl.message(
        "Warning",
        name: "promptKeyboardHookWarningTitle",
        desc: "Title for the Linux keyboard shortcut warning dialog",
      );

  String get promptKeyboardHookLinuxWarningBody => Intl.message(
        "Hotkeys using 'Shift' as a modifier may be unreliable on Linux, consider using a different key combination",
        name: "promptKeyboardHookLinuxWarningBody",
        desc:
            "Warning shown when a Linux keyboard shortcut uses Shift as a modifier",
      );

  String get promptKeyboardHookWarningOkButton => Intl.message(
        "Okay!",
        name: "promptKeyboardHookWarningOkButton",
        desc: "Dismiss button text for the Linux keyboard shortcut warning",
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildBuiltInShortcutsSection(),
        buildComposerTypingSection(),
        buildNavigationShortcutsSection(),
      ],
    );
  }

  Widget buildBuiltInShortcutsSection() {
    return SettingsSection(
      title: KeyboardHookShortcutsSettingsPage.labelConfigureKeyboardShortcuts,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var shortcut in SystemWideShortcuts.shortcuts.entries)
                buildShortcutTile(
                  title: shortcut.value.getDisplayName(),
                  hotkey: shortcut.value.hotkey,
                  icon: Icons.keyboard_command_key_rounded,
                  onTap: () => editBuiltInShortcut(shortcut),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildComposerTypingSection() {
    return SettingsSection(
      title: 'Composer Typing',
      children: [
        BooleanPreferenceToggle(
          preference: preferences.composerBracketTyping,
          title: 'Auto-close brackets',
        ),
      ],
    );
  }

  Widget buildNavigationShortcutsSection() {
    final definitions = SystemWideShortcuts.customNavigationShortcuts;

    return SettingsSection(
      title: 'Room and Space Shortcuts',
      showDivider: false,
      children: [
        SettingsControlRow(
          title: 'Custom navigation shortcuts',
          description:
              'Create system shortcuts for joined rooms, room IDs, room aliases, space IDs, or Matrix links. Use account scope only when the same target may exist on multiple signed-in accounts.',
          trailing: tiamat.Button(
            text: 'Add shortcut',
            onTap: () => editNavigationShortcut(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (definitions.isEmpty)
                buildEmptyNavigationShortcutCard()
              else
                for (final definition in definitions)
                  buildNavigationShortcutCard(definition),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildEmptyNavigationShortcutCard() {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'No custom room or space shortcuts yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 12,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget buildNavigationShortcutCard(NavigationShortcutDefinition definition) {
    final shortcut =
        SystemWideShortcuts.customShortcuts[definition.shortcutKey];
    final accountLabel = definition.clientId == null
        ? 'Any signed-in account'
        : 'Account: ${definition.clientId}';

    return buildShortcutTile(
      title: definition.displayLabel,
      description:
          '${definition.targetType.label}: ${definition.targetAddress}\n$accountLabel',
      hotkey: shortcut?.hotkey,
      icon: definition.targetType == NavigationShortcutTargetType.room
          ? Icons.tag_rounded
          : Icons.hub_rounded,
      onTap: () => editNavigationShortcut(definition: definition),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit shortcut',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => editNavigationShortcut(definition: definition),
          ),
          IconButton(
            tooltip: 'Delete shortcut',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => removeNavigationShortcut(definition),
          ),
        ],
      ),
    );
  }

  Widget buildShortcutTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    String? description,
    HotKey? hotkey,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            spacing: 12,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hotkey != null) HotKeyVirtualView(hotKey: hotkey),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget buildNavigationHotKeyPicker({
    required BuildContext context,
    required HotKey? hotkey,
    required VoidCallback onRecord,
    required VoidCallback onClear,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            'Shortcut keybind',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          Text(
            'Keyboard input is only captured after you press Record shortcut.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hotkey != null)
                HotKeyVirtualView(hotKey: hotkey)
              else
                Text(
                  'No shortcut set',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
              if (hotkey != null)
                tiamat.Button.secondary(text: 'Clear', onTap: onClear),
              tiamat.Button(text: 'Record shortcut', onTap: onRecord),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> editBuiltInShortcut(
    MapEntry<String, AppShortcut> shortcut,
  ) async {
    final key = await showHotKeyDialog(shortcut.value.hotkey);
    if (!mounted) return;

    await maybeWarnAboutLinuxShift(key);

    if (key != null) {
      await shortcut.value.setHotkey(key);
    } else {
      await shortcut.value.clearHotkey();
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<HotKey?> showHotKeyDialog(HotKey? initialHotKey) {
    return AdaptiveDialog.show<HotKey>(
      context,
      dismissible: false,
      builder: (context) {
        HotKey? hotkey = initialHotKey;

        return Column(
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.largeTitle(promptShortcutsPressAKeyCombination),
            SizedBox(
              height: 50,
              child: Center(
                child: HotKeyRecorder(
                  initalHotKey: hotkey,
                  onHotKeyRecorded: (k) {
                    hotkey = k;
                  },
                ),
              ),
            ),
            tiamat.Button(
              text: CommonStrings.promptSubmit,
              onTap: () => Navigator.of(context).pop(hotkey),
            ),
            tiamat.Button.secondary(
              text: promptShortcutsClearKeyboardShortcut,
              onTap: () => Navigator.of(context).pop(null),
            ),
          ],
        );
      },
    );
  }

  Future<void> editNavigationShortcut({
    NavigationShortcutDefinition? definition,
  }) async {
    final result = await showNavigationShortcutDialog(definition: definition);
    if (result == null) {
      return;
    }

    if (result.remove) {
      await removeNavigationShortcut(result.definition);
      return;
    }

    if (!mounted) return;
    await maybeWarnAboutLinuxShift(result.hotkey);
    await SystemWideShortcuts.saveNavigationShortcut(
      result.definition,
      hotkey: result.hotkey,
      clearHotkey: result.clearHotkey,
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> removeNavigationShortcut(
    NavigationShortcutDefinition definition,
  ) async {
    await SystemWideShortcuts.removeNavigationShortcut(definition);
    if (!mounted) return;
    setState(() {});
  }

  Future<_NavigationShortcutEditResult?> showNavigationShortcutDialog({
    NavigationShortcutDefinition? definition,
  }) {
    final labelController = TextEditingController(text: definition?.label);
    final targetController = TextEditingController(
      text: definition?.targetAddress,
    );
    var targetType =
        definition?.targetType ?? NavigationShortcutTargetType.room;
    var clientId = definition?.clientId ?? '';
    var hotkey =
        SystemWideShortcuts.customShortcuts[definition?.shortcutKey]?.hotkey;
    var selectedRoomKey = '';
    var resolvedInitialRoomSelection = false;
    String? errorText;

    return AdaptiveDialog.show<_NavigationShortcutEditResult>(
      context,
      dismissible: true,
      builder: (context) {
        final clients = clientManager?.clients ?? const [];
        final knownClientIds =
            clients.map((client) => client.identifier).toSet();
        final roomOptions =
            buildNavigationShortcutRoomOptions(clients: clients);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!resolvedInitialRoomSelection) {
              selectedRoomKey = findNavigationShortcutRoomOptionForTarget(
                    options: roomOptions,
                    targetAddress: targetController.text,
                    clientId: clientId,
                  )?.key ??
                  '';
              resolvedInitialRoomSelection = true;
            }

            if (selectedRoomKey.isNotEmpty &&
                findNavigationShortcutRoomOptionByKey(
                      roomOptions,
                      selectedRoomKey,
                    ) ==
                    null) {
              selectedRoomKey = '';
            }

            _NavigationShortcutEditResult? buildResult({
              required bool clearHotkey,
            }) {
              final targetAddress = targetController.text.trim();
              if (targetAddress.isEmpty) {
                setDialogState(() {
                  errorText =
                      'Enter a room or space ID, alias, or Matrix link.';
                });
                return null;
              }

              if (errorText != null) {
                setDialogState(() {
                  errorText = null;
                });
              }

              return _NavigationShortcutEditResult(
                definition: NavigationShortcutDefinition(
                  id: definition?.id ??
                      NavigationShortcutDefinition.generateId(),
                  targetType: targetType,
                  targetAddress: targetAddress,
                  label: labelController.text.trim(),
                  clientId: clientId.isEmpty ? null : clientId,
                ),
                hotkey: clearHotkey ? null : hotkey,
                clearHotkey: clearHotkey,
              );
            }

            Future<void> recordNavigationHotkey() async {
              final recordedHotkey = await showHotKeyDialog(hotkey);
              if (!context.mounted) {
                return;
              }

              setDialogState(() {
                hotkey = recordedHotkey;
              });
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tiamat.Text.largeTitle(
                    definition == null ? 'Add shortcut' : 'Edit shortcut',
                  ),
                  DropdownButtonFormField<NavigationShortcutTargetType>(
                    initialValue: targetType,
                    decoration: inputDecoration('Shortcut type'),
                    items: const [
                      DropdownMenuItem(
                        value: NavigationShortcutTargetType.room,
                        child: Text('Room'),
                      ),
                      DropdownMenuItem(
                        value: NavigationShortcutTargetType.space,
                        child: Text('Space'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        targetType = value;
                        if (targetType != NavigationShortcutTargetType.room) {
                          selectedRoomKey = '';
                        }
                      });
                    },
                  ),
                  TextField(
                    controller: labelController,
                    decoration: inputDecoration(
                      'Label',
                      hintText: 'Open project room',
                    ),
                  ),
                  if (targetType == NavigationShortcutTargetType.room)
                    buildJoinedRoomPicker(
                      roomOptions: roomOptions,
                      selectedRoomKey: selectedRoomKey,
                      onChanged: (value) {
                        final selected = findNavigationShortcutRoomOptionByKey(
                          roomOptions,
                          value ?? '',
                        );
                        setDialogState(() {
                          final previous =
                              findNavigationShortcutRoomOptionByKey(
                            roomOptions,
                            selectedRoomKey,
                          );
                          selectedRoomKey = selected?.key ?? '';
                          if (selected == null) {
                            return;
                          }

                          final label = labelController.text.trim();
                          final shouldReplaceLabel = label.isEmpty ||
                              (previous != null &&
                                  label == previous.displayName);
                          targetController.text = selected.targetAddress;
                          clientId = selected.clientId;
                          if (shouldReplaceLabel) {
                            labelController.text = selected.displayName;
                          }
                          errorText = null;
                        });
                      },
                    ),
                  TextField(
                    controller: targetController,
                    decoration: inputDecoration(
                      targetType == NavigationShortcutTargetType.room
                          ? 'Room ID, alias, or Matrix link'
                          : 'Space ID, alias, or Matrix link',
                      hintText: targetType == NavigationShortcutTargetType.room
                          ? '#room:example.com'
                          : '#space:example.com',
                    ),
                    onChanged: (value) {
                      final selected = findNavigationShortcutRoomOptionByKey(
                        roomOptions,
                        selectedRoomKey,
                      );
                      if (selected == null ||
                          selected.targetAddress == value.trim()) {
                        return;
                      }

                      setDialogState(() {
                        selectedRoomKey = '';
                      });
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('account-scope-$clientId'),
                    initialValue: clientId,
                    decoration: inputDecoration('Account scope'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Any signed-in account'),
                      ),
                      if (clientId.isNotEmpty &&
                          !knownClientIds.contains(clientId))
                        DropdownMenuItem(
                          value: clientId,
                          child: Text('$clientId (not signed in)'),
                        ),
                      for (final client in clients)
                        DropdownMenuItem(
                          value: client.identifier,
                          child: Text(
                            client.self?.identifier ?? client.identifier,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        clientId = value ?? '';
                      });
                    },
                  ),
                  buildNavigationHotKeyPicker(
                    context: context,
                    hotkey: hotkey,
                    onRecord: recordNavigationHotkey,
                    onClear: () {
                      setDialogState(() {
                        hotkey = null;
                      });
                    },
                  ),
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (definition != null)
                    tiamat.Button.secondary(
                      text: 'Delete shortcut',
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_NavigationShortcutEditResult.remove(definition)),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: tiamat.Button.secondary(
                          text: CommonStrings.promptCancel,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: tiamat.Button(
                          text: 'Save shortcut',
                          onTap: () {
                            final result = buildResult(
                              clearHotkey: hotkey == null,
                            );
                            if (result == null) return;
                            Navigator.of(context).pop(result);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration inputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget buildJoinedRoomPicker({
    required List<NavigationShortcutRoomOption> roomOptions,
    required String selectedRoomKey,
    required ValueChanged<String?> onChanged,
  }) {
    if (roomOptions.isEmpty) {
      return InputDecorator(
        decoration: inputDecoration('Joined room'),
        child: Text(
          'No joined rooms available. Enter a room address manually.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                letterSpacing: 0,
              ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: ValueKey('joined-room-$selectedRoomKey-${roomOptions.length}'),
      initialValue: selectedRoomKey,
      decoration: inputDecoration('Joined room'),
      isExpanded: true,
      itemHeight: 64,
      selectedItemBuilder: (context) {
        return [
          const Text(
            'Type room manually',
            overflow: TextOverflow.ellipsis,
          ),
          for (final option in roomOptions)
            Text(
              option.selectedLabel,
              overflow: TextOverflow.ellipsis,
            ),
        ];
      },
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text('Type room manually'),
        ),
        for (final option in roomOptions)
          DropdownMenuItem(
            value: option.key,
            child: Row(
              spacing: 10,
              children: [
                const Icon(Icons.tag_rounded, size: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        option.secondaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                              letterSpacing: 0,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> maybeWarnAboutLinuxShift(HotKey? key) async {
    if (!mounted || !PlatformUtils.isLinux) {
      return;
    }

    if (key?.modifiers?.contains(HotKeyModifier.shift) != true) {
      return;
    }

    await AdaptiveDialog.show(
      context,
      title: promptKeyboardHookWarningTitle,
      builder: (_) => SizedBox(
        width: 500,
        child: Column(
          children: [
            tiamat.Text.label(promptKeyboardHookLinuxWarningBody),
            tiamat.Button.secondary(
              text: promptKeyboardHookWarningOkButton,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationShortcutEditResult {
  const _NavigationShortcutEditResult({
    required this.definition,
    this.hotkey,
    this.clearHotkey = false,
    this.remove = false,
  });

  factory _NavigationShortcutEditResult.remove(
    NavigationShortcutDefinition definition,
  ) {
    return _NavigationShortcutEditResult(definition: definition, remove: true);
  }

  final NavigationShortcutDefinition definition;
  final HotKey? hotkey;
  final bool clearHotkey;
  final bool remove;
}
