import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/theme_preview_panel.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/theme_token_usage_map.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const double _themeWorkshopDesktopBreakpoint = 960;
const double _themeWorkshopDesktopMaxWidth = 1680;
const double _themeWorkshopDesktopMaxHeight = 980;

Future<CustomThemeDraft?> showCustomThemeEditor(
  BuildContext context, {
  required CustomThemeDraft draft,
}) {
  final title = draft.id == null ? 'Create Custom Theme' : 'Edit Custom Theme';
  final barrierLabel =
      '${MaterialLocalizations.of(context).modalBarrierDismissLabel} $title';
  final useDesktop =
      MediaQuery.sizeOf(context).width >= _themeWorkshopDesktopBreakpoint;

  if (!useDesktop) {
    return showModalBottomSheet<CustomThemeDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      elevation: 0,
      barrierLabel: barrierLabel,
      requestFocus: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _ThemeWorkshopRouteFrame(
                child: CustomThemeEditorPage(initialDraft: draft, title: title),
              ),
            ),
          ),
        );
      },
    );
  }

  return showGeneralDialog<CustomThemeDraft>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    pageBuilder: (context, _, __) {
      final media = MediaQuery.sizeOf(context);
      final width = math.min(media.width * 0.92, _themeWorkshopDesktopMaxWidth);
      final height = math.min(
        media.height * 0.9,
        _themeWorkshopDesktopMaxHeight,
      );

      return SafeArea(
        child: Center(
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            elevation: 0,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _ThemeWorkshopRouteFrame(
                  child: CustomThemeEditorPage(
                    initialDraft: draft,
                    title: title,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ThemeWorkshopRouteFrame extends StatelessWidget {
  const _ThemeWorkshopRouteFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class CustomThemeEditorPage extends StatefulWidget {
  const CustomThemeEditorPage({
    super.key,
    required this.initialDraft,
    this.title,
    this.onSave,
    this.onCancel,
  });

  final CustomThemeDraft initialDraft;
  final String? title;
  final ValueChanged<CustomThemeDraft>? onSave;
  final VoidCallback? onCancel;

  @override
  State<CustomThemeEditorPage> createState() => _CustomThemeEditorPageState();
}

class _CustomThemeEditorPageState extends State<CustomThemeEditorPage> {
  late final TextEditingController nameController;
  late final TextEditingController searchController;
  late final PageController mobilePageController;
  late String base;
  late Map<String, Color> colors;
  String searchQuery = '';
  String? selectedTokenId;
  String? selectedPreviewTargetId;
  int mobilePageIndex = 0;
  String? nameErrorText;
  bool _saving = false;

  ThemeData get baseTheme => defaultThemeForCustomBase(base);

  String get pageTitle =>
      widget.title ??
      (widget.initialDraft.id == null
          ? 'Create Custom Theme'
          : 'Edit Custom Theme');

  CustomThemeDraft get currentDraft {
    return CustomThemeDraft(
      id: widget.initialDraft.id,
      name: nameController.text.trim().isEmpty
          ? widget.initialDraft.name
          : nameController.text.trim(),
      base: base,
      colors: Map<String, Color>.from(colors),
      sourceJson: widget.initialDraft.sourceJson,
    );
  }

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialDraft.name);
    searchController = TextEditingController();
    mobilePageController = PageController();
    base = widget.initialDraft.base;
    colors = Map<String, Color>.from(widget.initialDraft.colors);
    selectedTokenId = editableThemeColorFields.isNotEmpty
        ? editableThemeColorFields.first.id
        : null;
    selectedPreviewTargetId = _firstTargetIdForToken(selectedTokenId);
  }

  @override
  void dispose() {
    nameController.dispose();
    searchController.dispose();
    mobilePageController.dispose();
    super.dispose();
  }

  Color colorForField(CustomThemeColorField field) {
    return colors[field.id] ?? field.themeColor(baseTheme);
  }

  Future<void> pickColor(CustomThemeColorField field) async {
    selectToken(field.id);
    final selected = await showCustomThemeColorPicker(
      context,
      title: field.label,
      initialColor: colorForField(field),
      defaultColor: field.themeColor(baseTheme),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      colors[field.id] = selected;
    });
  }

  void resetColor(CustomThemeColorField field) {
    setState(() {
      selectedTokenId = field.id;
      selectedPreviewTargetId = _firstTargetIdForToken(field.id);
      colors[field.id] = field.themeColor(baseTheme);
    });
  }

  void selectToken(String tokenId) {
    setState(() {
      selectedTokenId = tokenId;
      selectedPreviewTargetId = _firstTargetIdForToken(tokenId);
    });
  }

  void selectPreviewTarget(String targetId) {
    final tokenId = primaryTokenForPreviewTarget(targetId);
    setState(() {
      selectedPreviewTargetId = targetId;
      selectedTokenId = tokenId ?? selectedTokenId;
    });
  }

  bool get _hasTokenEditsFromBase {
    final selectedBaseTheme = defaultThemeForCustomBase(base);
    for (final field in editableThemeColorFields) {
      if (colors[field.id] != field.themeColor(selectedBaseTheme)) {
        return true;
      }
    }

    return false;
  }

  void _applyBaseColors(String value) {
    base = value;
    final selectedBaseTheme = defaultThemeForCustomBase(value);
    for (final field in editableThemeColorFields) {
      colors[field.id] = field.themeColor(selectedBaseTheme);
    }
  }

  Future<void> changeBase(String value) async {
    if (value == base && !_hasTokenEditsFromBase) {
      return;
    }

    if (_hasTokenEditsFromBase) {
      final label = labelForCustomThemeBase(value);
      final startOver = await AdaptiveDialog.confirmation(
        context,
        title: 'Save changes first?',
        prompt:
            'Changing the starting point to **$label** replaces the '
            'current token edits with the default colors for that theme. '
            'Keep editing if you want to save this draft first, or start over '
            'to discard the token edits.',
        confirmationText: 'Start over',
        cancelText: 'Keep editing',
        dangerous: true,
      );

      if (startOver != true || !mounted) {
        return;
      }
    }

    setState(() {
      _applyBaseColors(value);
    });
  }

  Future<void> save() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        setState(() {
          nameErrorText = 'Theme name is required';
        });
        return;
      }

      final draft = CustomThemeDraft(
        id: widget.initialDraft.id,
        name: name,
        base: base,
        colors: Map<String, Color>.from(colors),
        sourceJson: widget.initialDraft.sourceJson,
      );

      final contrastIssues = contrastIssuesForCustomThemeDraft(draft);
      if (contrastIssues.isNotEmpty) {
        final shouldSave = await _showContrastWarning(contrastIssues);
        if (shouldSave != true || !mounted) {
          return;
        }
      }

      _completeSave(draft);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _completeSave(CustomThemeDraft draft) {
    if (widget.onSave != null) {
      widget.onSave!(draft);
      return;
    }

    Navigator.of(context).pop(draft);
  }

  Future<bool?> _showContrastWarning(List<CustomThemeContrastIssue> issues) {
    return AdaptiveDialog.show<bool>(
      context,
      title: 'Contrast warning',
      scrollable: false,
      builder: (context) {
        final visibleIssues = issues.take(6).toList();
        return SizedBox(
          width: 540,
          child: _ContrastWarningContent(
            issues: visibleIssues,
            extraCount: issues.length - visibleIssues.length,
          ),
        );
      },
    );
  }

  void cancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final previewTheme = previewThemeForCustomDraft(currentDraft);
    final highlightedTargets = targetIdsForThemeToken(selectedTokenId);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media.size.width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media.size.height;
        final isDesktop = availableWidth >= _themeWorkshopDesktopBreakpoint;

        return SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: Column(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWorkshopHeader(
                context,
                isDesktop: isDesktop,
                availableWidth: availableWidth,
              ),
              Expanded(
                child: isDesktop
                    ? Row(
                        spacing: 14,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 430,
                            child: _buildEditorPane(context, isDesktop: true),
                          ),
                          Expanded(
                            child: Theme(
                              data: previewTheme,
                              child: ThemePreviewPanel(
                                highlightedTargetIds: highlightedTargets,
                                selectedTargetId: selectedPreviewTargetId,
                                onTargetSelected: selectPreviewTarget,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildMobileWorkshop(
                        context,
                        previewTheme,
                        highlightedTargets,
                      ),
              ),
              _WorkshopFooter(
                onCancel: cancel,
                onSave: _saving ? null : () => unawaited(save()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkshopHeader(
    BuildContext context, {
    required bool isDesktop,
    required double availableWidth,
  }) {
    final titleStyle =
        (isDesktop
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w900);
    final title = Text(
      pageTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );

    if (!isDesktop) {
      return title;
    }

    final searchWidth = math.min(420.0, math.max(280.0, availableWidth * 0.34));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        SizedBox(width: searchWidth, child: _buildTokenSearchField()),
      ],
    );
  }

  Widget _buildMobileWorkshop(
    BuildContext context,
    ThemeData previewTheme,
    Set<String> highlightedTargets,
  ) {
    return Column(
      spacing: 10,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileModeSelector(
          selectedIndex: mobilePageIndex,
          onChanged: (value) {
            mobilePageController.animateToPage(
              value,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          },
        ),
        Expanded(
          child: PageView(
            controller: mobilePageController,
            onPageChanged: (value) {
              setState(() {
                mobilePageIndex = value;
              });
            },
            children: [
              _buildEditorPane(context, isDesktop: false),
              Theme(
                data: previewTheme,
                child: ThemePreviewPanel(
                  highlightedTargetIds: highlightedTargets,
                  selectedTargetId: selectedPreviewTargetId,
                  onTargetSelected: selectPreviewTarget,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _firstTargetIdForToken(String? tokenId) {
    if (tokenId == null) {
      return null;
    }

    final usages = usageForThemeToken(tokenId);
    return usages.isEmpty ? null : usages.first.targetId;
  }

  Widget _buildEditorPane(BuildContext context, {required bool isDesktop}) {
    final groupedFields = _groupFilteredFields(searchQuery);
    final identityControls = isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildNameField()),
              const SizedBox(width: 12),
              SizedBox(
                width: 188,
                child: _BaseSelector(
                  value: base,
                  onChanged: (value) {
                    unawaited(changeBase(value));
                  },
                ),
              ),
            ],
          )
        : Column(
            spacing: 10,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNameField(),
              _BaseSelector(
                value: base,
                onChanged: (value) {
                  unawaited(changeBase(value));
                },
              ),
              _buildTokenSearchField(),
            ],
          );
    final tokenGroups = <Widget>[
      if (groupedFields.isEmpty)
        const SizedBox(
          height: 180,
          child: Center(child: Text('No tokens found')),
        )
      else
        for (final group in groupedFields.entries) ...[
          tiamat.Panel(
            header: group.key,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
              children: [
                for (var i = 0; i < group.value.length; i++) ...[
                  ThemeTokenEditorRow(
                    field: group.value[i],
                    color: colorForField(group.value[i]),
                    defaultColor: group.value[i].themeColor(baseTheme),
                    helperText: helperTextForThemeField(group.value[i].id),
                    usages: usageForThemeToken(group.value[i].id),
                    selected: selectedTokenId == group.value[i].id,
                    onSelect: () => selectToken(group.value[i].id),
                    onPick: () => pickColor(group.value[i]),
                    onReset: () => resetColor(group.value[i]),
                  ),
                  if (i != group.value.length - 1) const tiamat.Seperator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
    ];

    if (!isDesktop) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          identityControls,
          const SizedBox(height: 10),
          ...tokenGroups,
        ],
      );
    }

    return Column(
      spacing: 10,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        identityControls,
        Expanded(
          child: groupedFields.isEmpty
              ? const Center(child: Text('No tokens found'))
              : ListView(children: tokenGroups),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: nameController,
      decoration: InputDecoration(
        labelText: 'Theme Name',
        hintText: 'Inter Galactic Midnight',
        errorText: nameErrorText,
      ),
      onChanged: (_) {
        if (nameErrorText != null) {
          setState(() {
            nameErrorText = null;
          });
        } else {
          setState(() {});
        }
      },
    );
  }

  Widget _buildTokenSearchField() {
    return TextField(
      key: const ValueKey('theme-token-search'),
      controller: searchController,
      decoration: const InputDecoration(
        labelText: 'Search tokens',
        hintText: 'Try composer, link, selected room...',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (value) {
        setState(() {
          searchQuery = value;
        });
      },
    );
  }
}

Map<String, List<CustomThemeColorField>> _groupFilteredFields(String query) {
  final filtered = filterThemeTokenFields(editableThemeColorFields, query);
  final result = <String, List<CustomThemeColorField>>{};

  for (final groupName in _themeWorkshopGroupOrder) {
    final fields = filtered.where(
      (field) => _themeWorkshopGroupForField(field.id) == groupName,
    );
    if (fields.isNotEmpty) {
      result[groupName] = fields.toList();
    }
  }

  return result;
}

class CustomThemeContrastIssue {
  const CustomThemeContrastIssue({
    required this.contextLabel,
    required this.textTokenId,
    required this.textTokenLabel,
    required this.surfaceTokenId,
    required this.surfaceTokenLabel,
    required this.contrastRatio,
    required this.minimumContrastRatio,
  });

  final String contextLabel;
  final String textTokenId;
  final String textTokenLabel;
  final String surfaceTokenId;
  final String surfaceTokenLabel;
  final double contrastRatio;
  final double minimumContrastRatio;
}

class _CustomThemeContrastCheck {
  const _CustomThemeContrastCheck({
    required this.contextLabel,
    required this.textTokenId,
    required this.textTokenLabel,
    required this.surfaceTokenId,
    required this.surfaceTokenLabel,
  });

  final String contextLabel;
  final String textTokenId;
  final String textTokenLabel;
  final String surfaceTokenId;
  final String surfaceTokenLabel;
  double get minimumContrastRatio => 4.5;
}

const List<_CustomThemeContrastCheck> _customThemeContrastChecks = [
  _CustomThemeContrastCheck(
    contextLabel: 'Space rail labels and icons',
    textTokenId: 'onSurface',
    textTokenLabel: 'Surface Text',
    surfaceTokenId: 'surfaceContainerLowest',
    surfaceTokenLabel: 'Surface Container Lowest',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Room list text',
    textTokenId: 'onSurface',
    textTokenLabel: 'Surface Text',
    surfaceTokenId: 'surfaceContainerLow',
    surfaceTokenLabel: 'Surface Container Low',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Settings and standard panels',
    textTokenId: 'onSurface',
    textTokenLabel: 'Surface Text',
    surfaceTokenId: 'surfaceContainer',
    surfaceTokenLabel: 'Surface Container',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Raised controls and popovers',
    textTokenId: 'onSurface',
    textTokenLabel: 'Surface Text',
    surfaceTokenId: 'surfaceContainerHigh',
    surfaceTokenLabel: 'Surface Container High',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Highest raised surfaces',
    textTokenId: 'onSurface',
    textTokenLabel: 'Surface Text',
    surfaceTokenId: 'surfaceContainerHighest',
    surfaceTokenLabel: 'Surface Container Highest',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Primary buttons and unread badges',
    textTokenId: 'onPrimary',
    textTokenLabel: 'Primary Text',
    surfaceTokenId: 'primary',
    surfaceTokenLabel: 'Primary',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Selected room text',
    textTokenId: 'onPrimaryContainer',
    textTokenLabel: 'Primary Container Text',
    surfaceTokenId: 'primaryContainer',
    surfaceTokenLabel: 'Primary Container',
  ),
  _CustomThemeContrastCheck(
    contextLabel: 'Sent messages and reaction chips',
    textTokenId: 'onSecondaryContainer',
    textTokenLabel: 'Secondary Container Text',
    surfaceTokenId: 'secondaryContainer',
    surfaceTokenLabel: 'Secondary Container',
  ),
];

List<CustomThemeContrastIssue> contrastIssuesForCustomThemeDraft(
  CustomThemeDraft draft,
) {
  final theme = previewThemeForCustomDraft(draft);
  final issues = <CustomThemeContrastIssue>[];

  for (final check in _customThemeContrastChecks) {
    final textColor = _themeTokenColor(theme, check.textTokenId);
    final surfaceColor = _themeTokenColor(theme, check.surfaceTokenId);
    final ratio = _contrastRatio(textColor, surfaceColor);

    if (ratio >= check.minimumContrastRatio) {
      continue;
    }

    issues.add(
      CustomThemeContrastIssue(
        contextLabel: check.contextLabel,
        textTokenId: check.textTokenId,
        textTokenLabel: check.textTokenLabel,
        surfaceTokenId: check.surfaceTokenId,
        surfaceTokenLabel: check.surfaceTokenLabel,
        contrastRatio: ratio,
        minimumContrastRatio: check.minimumContrastRatio,
      ),
    );
  }

  return issues;
}

Color _themeTokenColor(ThemeData theme, String tokenId) {
  final scheme = theme.colorScheme;
  return switch (tokenId) {
    'primary' => scheme.primary,
    'onPrimary' => scheme.onPrimary,
    'primaryContainer' => scheme.primaryContainer,
    'onPrimaryContainer' => scheme.onPrimaryContainer,
    'secondaryContainer' => scheme.secondaryContainer,
    'onSecondaryContainer' => scheme.onSecondaryContainer,
    'surfaceContainerLowest' => scheme.surfaceContainerLowest,
    'surfaceContainerLow' => scheme.surfaceContainerLow,
    'surfaceContainer' => scheme.surfaceContainer,
    'surfaceContainerHigh' => scheme.surfaceContainerHigh,
    'surfaceContainerHighest' => scheme.surfaceContainerHighest,
    'onSurface' => scheme.onSurface,
    _ => scheme.onSurface,
  };
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = math.max(foregroundLuminance, backgroundLuminance);
  final darker = math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

const List<String> _themeWorkshopGroupOrder = [
  'Accent',
  'Surfaces',
  'Text',
  'Messages',
  'Extras',
];

String _themeWorkshopGroupForField(String id) {
  return switch (id) {
    'surface' ||
    'surfaceContainerLowest' ||
    'surfaceContainerLow' ||
    'surfaceContainer' ||
    'surfaceContainerHigh' ||
    'surfaceContainerHighest' ||
    'outline' => 'Surfaces',
    'onSurface' => 'Text',
    'secondaryContainer' || 'onSecondaryContainer' => 'Messages',
    'links' || 'codeHighlight' || 'foundationColor' => 'Extras',
    _ => 'Accent',
  };
}

class _BaseSelector extends StatelessWidget {
  const _BaseSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedOption =
        customThemeBaseOptionFor(value) ??
        customThemeBaseOptionFor('dark_matter') ??
        customThemeBaseOptions.first;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Text(
            'Starting Point',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: tiamat.DropdownSelector<CustomThemeBaseOption>(
            key: const ValueKey('theme-base-selector'),
            value: selectedOption,
            items: customThemeBaseOptions,
            itemBuilder: (option) => Text(option.label),
            onItemSelected: (option) {
              if (option == null) {
                return;
              }

              onChanged(option.id);
            },
          ),
        ),
      ],
    );
  }
}

class _ContrastWarningContent extends StatelessWidget {
  const _ContrastWarningContent({
    required this.issues,
    required this.extraCount,
  });

  final List<CustomThemeContrastIssue> issues;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Some text colors are too close to the surfaces they appear on. '
          'You can save anyway, but these parts of the app may be hard to read.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final issue in issues) ...[
                  _ContrastWarningIssue(issue: issue),
                  const SizedBox(height: 8),
                ],
                if (extraCount > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+$extraCount more contrast conflicts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        tiamat.Button.secondary(
          text: 'Change Colors',
          onTap: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(height: 8),
        tiamat.Button(
          text: 'Save Anyway',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class _ContrastWarningIssue extends StatelessWidget {
  const _ContrastWarningIssue({required this.issue});

  final CustomThemeContrastIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            issue.contextLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${issue.textTokenLabel} on ${issue.surfaceTokenLabel} is '
            '${issue.contrastRatio.toStringAsFixed(1)}:1. '
            'Use at least ${issue.minimumContrastRatio.toStringAsFixed(1)}:1.',
            style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
          ),
        ],
      ),
    );
  }
}

class ThemeTokenEditorRow extends StatelessWidget {
  const ThemeTokenEditorRow({
    super.key,
    required this.field,
    required this.color,
    required this.defaultColor,
    required this.helperText,
    required this.usages,
    required this.selected,
    required this.onSelect,
    required this.onPick,
    required this.onReset,
  });

  final CustomThemeColorField field;
  final Color color;
  final Color defaultColor;
  final String helperText;
  final List<ThemeTokenUsage> usages;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _themeWorkshopDesktopBreakpoint;
    final borderColor = Theme.of(context).colorScheme.outline;
    final selectedColor = Theme.of(context).colorScheme.primary;
    final swatch = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderColor),
      ),
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: selected ? Border.all(color: selectedColor, width: 1.5) : null,
        color: selected
            ? selectedColor.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                swatch,
                const SizedBox(width: 12),
                Expanded(child: _rowText(context)),
                const SizedBox(width: 12),
                _rowActions(context),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    swatch,
                    const SizedBox(width: 12),
                    Expanded(child: _rowText(context)),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _rowActions(context),
                ),
              ],
            ),
    );

    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          onSelect();
        }
      },
      child: MouseRegion(
        onEnter: (_) => onSelect(),
        child: InkWell(
          key: ValueKey('theme-token-${field.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onSelect,
          child: content,
        ),
      ),
    );
  }

  Widget _rowText(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          helperText,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final usage in usages.take(3)) _UsageChip(label: usage.label),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _AbbreviationChip(
              label: abbreviationForThemeToken(field.id),
              color: color,
            ),
            const SizedBox(width: 7),
            Text(
              colorToHex(color).toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: mutedColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rowActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.Button.secondary(text: 'Pick', onTap: onPick),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Reset to Base Theme',
          child: tiamat.CircleButton(
            icon: Icons.restart_alt,
            onPressed: onReset,
          ),
        ),
      ],
    );
  }
}

class _AbbreviationChip extends StatelessWidget {
  const _AbbreviationChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _UsageChip extends StatelessWidget {
  const _UsageChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MobileModeSelector extends StatelessWidget {
  const _MobileModeSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Edit'),
          selected: selectedIndex == 0,
          onSelected: (_) => onChanged(0),
        ),
        ChoiceChip(
          label: const Text('Preview'),
          selected: selectedIndex == 1,
          onSelected: (_) => onChanged(1),
        ),
      ],
    );
  }
}

class _WorkshopFooter extends StatelessWidget {
  const _WorkshopFooter({required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: tiamat.Button.secondary(text: 'Cancel', onTap: onCancel),
        ),
        Expanded(
          child: tiamat.Button(text: 'Save Theme', onTap: onSave),
        ),
      ],
    );
  }
}

String helperTextForThemeField(String id) {
  return switch (id) {
    'primary' => 'Buttons, active toggles, selected rooms, and strong accents.',
    'onPrimary' => 'Text and icons drawn on primary accent fills.',
    'primaryContainer' => 'Selected room backgrounds and elevated accents.',
    'onPrimaryContainer' => 'Text and icons on primary container surfaces.',
    'secondary' => 'Composer icons, reactions, and supporting accents.',
    'onSecondary' => 'Text and icons drawn on secondary accent fills.',
    'secondaryContainer' => 'Reaction chips and sent-message preview surfaces.',
    'onSecondaryContainer' => 'Text on secondary containers and sent messages.',
    'tertiary' => 'Status accents and occasional tertiary highlights.',
    'links' => 'Links in messages and settings copy.',
    'codeHighlight' => 'Highlighted code snippets and inline code emphasis.',
    'surface' => 'Default cards, settings tiles, and message surfaces.',
    'onSurface' => 'Main text and icons on cards, panels, and messages.',
    'surfaceContainerLowest' => 'Lowest app layer behind panels.',
    'surfaceContainerLow' => 'Room lists, composer frames, and subtle panels.',
    'surfaceContainer' => 'Standard panels, headers, and message cards.',
    'surfaceContainerHigh' => 'Raised panels, composer fields, and popovers.',
    'surfaceContainerHighest' => 'Highest elevation dialogs and overlays.',
    'outline' => 'Borders, dividers, input strokes, and card outlines.',
    'foundationColor' => 'Main app background behind the panels.',
    _ => 'Preview how this color is used in the app.',
  };
}

Future<Color?> showCustomThemeColorPicker(
  BuildContext context, {
  required String title,
  required Color initialColor,
  required Color defaultColor,
}) {
  return AdaptiveDialog.show<Color>(
    context,
    title: title,
    scrollable: false,
    builder: (context) => _CustomThemeColorPickerDialog(
      initialColor: initialColor,
      defaultColor: defaultColor,
    ),
  );
}

class _CustomThemeColorPickerDialog extends StatefulWidget {
  const _CustomThemeColorPickerDialog({
    required this.initialColor,
    required this.defaultColor,
  });

  final Color initialColor;
  final Color defaultColor;

  @override
  State<_CustomThemeColorPickerDialog> createState() =>
      _CustomThemeColorPickerDialogState();
}

class _CustomThemeColorPickerDialogState
    extends State<_CustomThemeColorPickerDialog> {
  late HSVColor selectedHsv;
  late TextEditingController hexController;

  Color get selectedColor => selectedHsv.toColor();

  @override
  void initState() {
    super.initState();
    selectedHsv = HSVColor.fromColor(widget.initialColor);
    hexController = TextEditingController(text: colorToHex(selectedColor));
  }

  @override
  void dispose() {
    hexController.dispose();
    super.dispose();
  }

  void updateColor(Color color) {
    setState(() {
      selectedHsv = HSVColor.fromColor(color);
      hexController.text = colorToHex(color);
    });
  }

  void updateHsv(HSVColor hsvColor) {
    setState(() {
      selectedHsv = hsvColor;
      hexController.text = colorToHex(hsvColor.toColor());
    });
  }

  void updateFromHex() {
    final parsed = parseHexColor(hexController.text);
    if (parsed != null) {
      updateColor(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _themeWorkshopDesktopBreakpoint;
    final borderColor = Theme.of(context).colorScheme.outline;

    return SizedBox(
      width: isDesktop ? 480 : null,
      child: Column(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 88,
            decoration: BoxDecoration(
              color: selectedColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
          ),
          TextField(
            controller: hexController,
            decoration: const InputDecoration(
              labelText: 'Hex',
              hintText: '#FF6A8D',
            ),
            onChanged: (_) => updateFromHex(),
          ),
          _ColorSlider(
            label: 'Hue',
            min: 0,
            max: 360,
            value: selectedHsv.hue,
            onChanged: (value) {
              updateHsv(selectedHsv.withHue(value));
            },
          ),
          _ColorSlider(
            label: 'Saturation',
            min: 0,
            max: 1,
            value: selectedHsv.saturation,
            onChanged: (value) {
              updateHsv(selectedHsv.withSaturation(value));
            },
          ),
          _ColorSlider(
            label: 'Brightness',
            min: 0,
            max: 1,
            value: selectedHsv.value,
            onChanged: (value) {
              updateHsv(selectedHsv.withValue(value));
            },
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: tiamat.Button.secondary(
                  text: 'Reset',
                  onTap: () => updateColor(widget.defaultColor),
                ),
              ),
              Expanded(
                child: tiamat.Button.secondary(
                  text: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: tiamat.Button(
                  text: 'Apply',
                  onTap: () => Navigator.of(context).pop(selectedColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label ${value.toStringAsFixed(max > 1 ? 0 : 2)}'),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
