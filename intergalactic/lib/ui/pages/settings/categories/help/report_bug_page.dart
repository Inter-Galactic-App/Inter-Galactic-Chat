import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/bug_report/bug_report_service.dart';
import 'package:intergalactic/client/bug_report/call_stream_bug_report_diagnostics.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

Future<void> showReportBugDialog(
  BuildContext context, {
  BugReportTemplate template = BugReportTemplate.genericAppBug,
  String? initialTitle,
  String? initialReproductionSteps,
  String? initialExpectedBehavior,
  String? initialActualBehavior,
  BugReportSeverity initialSeverity = BugReportSeverity.medium,
  BugReportCategory? initialCategory,
  bool includeLogs = true,
  bool includeDiagnostics = true,
  Map<String, Object?> additionalMetadata = const {},
  List<BugReportAttachmentSummary> additionalAttachments = const [],
  String? reportNotice,
}) async {
  BugReportFeatureDiagnosticsLoader? featureDiagnosticsLoader;
  try {
    final clientManager = Provider.of<ClientManager>(context, listen: false);
    featureDiagnosticsLoader = CallStreamBugReportDiagnostics(
      clientManager.callManager,
    ).collect;
  } on ProviderNotFoundException {
    // Startup/fatal fallback contexts can open without the normal app provider.
  }

  await AdaptiveDialog.show<Object?>(
    context,
    title: template.dialogTitle,
    scrollable: !Layout.desktop,
    contentPadding: Layout.desktop ? 0 : 8,
    builder: (context) {
      final page = ReportBugPage(
        initialTemplate: template,
        initialTitle: initialTitle,
        initialReproductionSteps: initialReproductionSteps,
        initialExpectedBehavior: initialExpectedBehavior,
        initialActualBehavior: initialActualBehavior,
        initialSeverity: initialSeverity,
        initialCategory: initialCategory,
        initialIncludeLogs: includeLogs,
        initialIncludeDiagnostics: includeDiagnostics,
        initialAdditionalMetadata: additionalMetadata,
        initialAdditionalAttachments: additionalAttachments,
        initialReportNotice: reportNotice,
        featureDiagnosticsLoader: featureDiagnosticsLoader,
      );

      if (!Layout.desktop) {
        return page;
      }

      final mediaQuery = MediaQuery.of(context);
      final availableWidth =
          mediaQuery.size.width -
          mediaQuery.viewPadding.horizontal -
          mediaQuery.viewInsets.horizontal;
      final availableHeight =
          mediaQuery.size.height -
          mediaQuery.viewPadding.vertical -
          mediaQuery.viewInsets.vertical;
      final width = (availableWidth * 0.96).clamp(0.0, 760.0).toDouble();
      final height = (availableHeight * 0.96).clamp(0.0, 760.0).toDouble();
      return SizedBox(
        width: width,
        height: height,
        child: SingleChildScrollView(child: page),
      );
    },
  );
}

class ReportBugPage extends StatefulWidget {
  const ReportBugPage({
    this.service,
    this.initialTitle,
    this.initialReproductionSteps,
    this.initialExpectedBehavior,
    this.initialActualBehavior,
    this.initialTemplate = BugReportTemplate.genericAppBug,
    this.initialSeverity = BugReportSeverity.medium,
    this.initialCategory,
    this.initialIncludeLogs = true,
    this.initialIncludeDiagnostics = true,
    this.initialAdditionalMetadata = const {},
    this.initialAdditionalAttachments = const [],
    this.initialReportNotice,
    this.featureDiagnosticsLoader,
    super.key,
  });

  final BugReportService? service;
  final String? initialTitle;
  final String? initialReproductionSteps;
  final String? initialExpectedBehavior;
  final String? initialActualBehavior;
  final BugReportTemplate initialTemplate;
  final BugReportSeverity initialSeverity;
  final BugReportCategory? initialCategory;
  final bool initialIncludeLogs;
  final bool initialIncludeDiagnostics;
  final Map<String, Object?> initialAdditionalMetadata;
  final List<BugReportAttachmentSummary> initialAdditionalAttachments;
  final String? initialReportNotice;
  final BugReportFeatureDiagnosticsLoader? featureDiagnosticsLoader;

  @override
  State<ReportBugPage> createState() => _ReportBugPageState();
}

class _ReportBugPageState extends State<ReportBugPage> {
  static const List<BugReportSeverity> _severityOptions = [
    BugReportSeverity.low,
    BugReportSeverity.medium,
    BugReportSeverity.high,
    BugReportSeverity.critical,
  ];

  late final BugReportService _service;
  late final bool _ownsService;
  late final TextEditingController _titleController;
  late final TextEditingController _whatHappenedController;
  late final TextEditingController _stepsController;
  late final TextEditingController _expectedController;
  late final TextEditingController _actualController;
  late final TextEditingController _detailsController;
  late final TextEditingController _troubleshootNoteController;
  final Map<String, TextEditingController> _categoryTextControllers = {};
  late final BugReportTemplate _template;

  BugReportCategory? _category;
  BugReportFrequency? _frequency;
  final Set<String> _troubleshootingSelected = {};
  final Map<String, String> _choiceAnswers = {};
  bool _showTroubleshootingTips = false;

  bool _includeLogs = true;
  bool _includeDiagnostics = true;
  late BugReportSeverity _severity;
  bool _buildingPreview = false;
  bool _submitting = false;
  BugReportPayload? _payload;
  BugReportSubmissionResult? _result;
  String? _error;

  bool get _guided => _template.usesGuidedInterview;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service =
        widget.service ??
        BugReportService(
          featureDiagnosticsLoader: widget.featureDiagnosticsLoader,
        );
    _template = widget.initialTemplate;
    _category = widget.initialCategory;
    _includeLogs = widget.initialIncludeLogs;
    _includeDiagnostics = widget.initialIncludeDiagnostics;
    _severity = widget.initialSeverity;
    _titleController = TextEditingController(
      text: widget.initialTitle ?? _template.defaultTitle,
    );
    // In the guided form the primary description lives in "What happened?"; a
    // prefilled actual-behavior seed (crash handoff, Developer Logs) flows in
    // there so nothing is lost.
    _whatHappenedController = TextEditingController(
      text: _guided ? (widget.initialActualBehavior ?? '') : '',
    );
    _stepsController = TextEditingController(
      text:
          widget.initialReproductionSteps ?? _template.defaultReproductionSteps,
    );
    _expectedController = TextEditingController(
      text: widget.initialExpectedBehavior ?? _template.defaultExpectedBehavior,
    );
    _actualController = TextEditingController(
      text: widget.initialActualBehavior ?? _template.defaultActualBehavior,
    );
    _detailsController = TextEditingController();
    _troubleshootNoteController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _whatHappenedController.dispose();
    _stepsController.dispose();
    _expectedController.dispose();
    _actualController.dispose();
    _detailsController.dispose();
    _troubleshootNoteController.dispose();
    for (final controller in _categoryTextControllers.values) {
      controller.dispose();
    }
    if (_ownsService) {
      _service.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboardInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        _template.pageTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  if (_isMobileKeyboardPlatform)
                    IconButton(
                      tooltip: 'Dismiss keyboard',
                      icon: const Icon(Icons.keyboard_hide_rounded),
                      onPressed: _dismissKeyboard,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _template.introText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              if (result != null)
                _ReportBugSection(
                  title: 'Report sent',
                  children: [
                    tiamat.Text.body(
                      result.reportId == null
                          ? result.message
                          : '${result.message} Report ID: ${result.reportId}',
                      softwrap: true,
                    ),
                    const SizedBox(height: 12),
                    tiamat.Button.secondary(
                      text: 'Send another report',
                      onTap: _resetForAnotherReport,
                    ),
                  ],
                )
              else ...[
                _buildFormSection(),
                const SizedBox(height: 16),
                _buildPreviewSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    if (_template.usesFixedDetails) {
      return _buildFixedDetailsForm();
    }
    return _buildGuidedForm();
  }

  // ---------------------------------------------------------------------------
  // Guided diagnostic interview (generic app bug)
  // ---------------------------------------------------------------------------

  Widget _buildGuidedForm() {
    final category = _category;
    return _ReportBugSection(
      title: _template.formSectionTitle,
      children: [
        _FieldLabel(label: 'What part of the app is affected?', required: true),
        const SizedBox(height: 6),
        _buildCategorySelector(),
        if (category != null) ...[
          const SizedBox(height: 12),
          _TroubleshootingCard(
            category: category,
            expanded: _showTroubleshootingTips,
            onToggle: () => setState(
              () => _showTroubleshootingTips = !_showTroubleshootingTips,
            ),
          ),
        ],
        const SizedBox(height: 14),
        tiamat.TextInput(
          label: 'What happened? (required)',
          placeholder:
              'Describe what you saw or heard. Include any error message, '
              'unexpected behavior, missing content, or visual problem.',
          controller: _whatHappenedController,
          minLines: 3,
          maxLines: 7,
          maxLength: 2500,
        ),
        const SizedBox(height: 14),
        tiamat.TextInput(
          label: 'What were you doing right before it happened?',
          placeholder:
              '1. I joined the room call.\n'
              '2. Someone else joined after me.\n'
              '3. I changed their volume.',
          controller: _stepsController,
          minLines: 3,
          maxLines: 7,
          maxLength: 2500,
        ),
        _HelperText(
          'List the actions in order. You do not need to use technical '
          'language.',
        ),
        const SizedBox(height: 14),
        _FieldLabel(label: 'How often does it happen?', required: true),
        const SizedBox(height: 6),
        _buildFrequencySelector(),
        const SizedBox(height: 14),
        tiamat.TextInput(
          label: 'What should have happened instead?',
          placeholder: 'Optional, but it helps.',
          controller: _expectedController,
          minLines: 2,
          maxLines: 4,
          maxLength: 1200,
        ),
        _HelperText('Briefly describe the result you expected.'),
        if (category != null && category.questions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _FieldLabel(label: 'A few questions about ${category.label}'),
          const SizedBox(height: 6),
          ..._buildCategoryQuestions(category),
        ],
        const SizedBox(height: 16),
        _FieldLabel(label: 'What have you already tried?'),
        const SizedBox(height: 6),
        ..._buildTroubleshootingOptions(category),
        const SizedBox(height: 8),
        tiamat.TextInput(
          label: 'Other troubleshooting (optional)',
          placeholder: 'Anything else you tried',
          controller: _troubleshootNoteController,
          minLines: 1,
          maxLines: 3,
          maxLength: 500,
        ),
        const SizedBox(height: 16),
        _FieldLabel(label: 'How serious is it?'),
        const SizedBox(height: 6),
        _buildSeveritySelector(),
        const SizedBox(height: 16),
        tiamat.TextInput(
          label: 'Anything else that might help?',
          placeholder: 'Optional',
          controller: _detailsController,
          minLines: 2,
          maxLines: 4,
          maxLength: 1200,
        ),
        _HelperText(
          'Examples: who else was affected, whether it began after an update, '
          'the room type, or anything unusual you noticed.',
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: tiamat.TextInput(
                label: 'Short summary (required)',
                placeholder:
                    'Cannot hear one participant after they join the call',
                controller: _titleController,
                maxLength: 120,
              ),
            ),
            const SizedBox(width: 8),
            tiamat.Button.secondary(text: 'Suggest', onTap: _suggestTitle),
          ],
        ),
        _buildReportNotice(),
        _buildKeyboardDismiss(),
        const SizedBox(height: 12),
        _buildIncludeToggles(),
        const SizedBox(height: 12),
        _buildPreviewButton(),
      ],
    );
  }

  Widget _buildCategorySelector() {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Affected area of the app, required',
      child: DropdownButtonFormField<BugReportCategory>(
        initialValue: _category,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          fillColor: theme.colorScheme.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.48),
            ),
          ),
        ),
        hint: const Text('Choose the affected area'),
        items: [
          for (final category in BugReportCategory.values)
            DropdownMenuItem<BugReportCategory>(
              value: category,
              child: Text(category.label),
            ),
        ],
        onChanged: (category) {
          setState(() {
            _category = category;
            _choiceAnswers.clear();
            // Drop troubleshooting selections belonging to the previous
            // category: their checkboxes are no longer rendered, so a stale
            // selection would be invisible yet still submitted (with a raw id
            // as its label). Universal options stay valid across categories, so
            // keep any the user already checked.
            _troubleshootingSelected.removeWhere(
              (id) => !kUniversalTroubleshootingOptions.any(
                (option) => option.id == id,
              ),
            );
            _showTroubleshootingTips = false;
            _payload = null;
            _error = null;
          });
        },
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return _ChoiceWrap(
      semanticLabel: 'How often the problem happens, required',
      options: [
        for (final frequency in BugReportFrequency.values)
          _ChoiceOption(value: frequency.value, label: frequency.label),
      ],
      selected: _frequency?.value,
      onSelected: (value) {
        setState(() {
          _frequency = BugReportFrequency.values.firstWhere(
            (frequency) => frequency.value == value,
          );
          _payload = null;
          _error = null;
        });
      },
    );
  }

  List<Widget> _buildCategoryQuestions(BugReportCategory category) {
    final widgets = <Widget>[];
    for (final question in category.questions) {
      if (question.isChoice) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: tiamat.Text.labelLow(question.prompt, softwrap: true),
          ),
        );
        widgets.add(
          _ChoiceWrap(
            semanticLabel: question.prompt,
            options: [
              for (final option in question.options)
                _ChoiceOption(value: option, label: option),
            ],
            selected: _choiceAnswers[question.id],
            onSelected: (value) {
              setState(() {
                if (_choiceAnswers[question.id] == value) {
                  _choiceAnswers.remove(question.id);
                } else {
                  _choiceAnswers[question.id] = value;
                }
                _payload = null;
                _error = null;
              });
            },
          ),
        );
      } else {
        widgets.add(
          tiamat.TextInput(
            label: question.prompt,
            placeholder: 'Optional',
            controller: _categoryTextControllerFor(question.id),
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
          ),
        );
      }
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  List<Widget> _buildTroubleshootingOptions(BugReportCategory? category) {
    final options = <BugReportTroubleshootingOption>[
      ...kUniversalTroubleshootingOptions,
      if (category != null) ...category.troubleshootingOptions,
    ];
    return [
      for (final option in options)
        CheckboxListTile(
          value: _troubleshootingSelected.contains(option.id),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: tiamat.Text.label(option.label, softwrap: true),
          onChanged: (checked) {
            setState(() {
              if (checked ?? false) {
                _troubleshootingSelected.add(option.id);
              } else {
                _troubleshootingSelected.remove(option.id);
              }
              _payload = null;
              _error = null;
            });
          },
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Fixed-detail template (call/stream logs)
  // ---------------------------------------------------------------------------

  Widget _buildFixedDetailsForm() {
    return _ReportBugSection(
      title: _template.formSectionTitle,
      children: [
        _TemplateStaticField(label: 'Template', value: _template.label),
        const SizedBox(height: 10),
        _TemplateStaticField(label: 'Title', value: _titleController.text),
        const SizedBox(height: 10),
        _TemplateStaticField(label: 'Report body', value: _reportBodyPreview()),
        const SizedBox(height: 10),
        _FieldLabel(label: 'How serious is it?'),
        const SizedBox(height: 6),
        _buildSeveritySelector(),
        _buildReportNotice(),
        _buildKeyboardDismiss(),
        const SizedBox(height: 12),
        _buildIncludeToggles(),
        const SizedBox(height: 12),
        _buildPreviewButton(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared form pieces
  // ---------------------------------------------------------------------------

  Widget _buildReportNotice() {
    final notice = widget.initialReportNotice?.trim();
    if (notice == null || notice.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _StatusBanner(icon: Icons.attach_file_outlined, text: notice),
    );
  }

  Widget _buildKeyboardDismiss() {
    if (!_isMobileKeyboardPlatform) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: tiamat.Button.secondary(
          text: 'Dismiss Keyboard',
          onTap: _dismissKeyboard,
        ),
      ),
    );
  }

  Widget _buildIncludeToggles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: _includeLogs,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const tiamat.Text.label('Include recent redacted logs'),
          subtitle: const tiamat.Text.labelLow(
            'Logs are redacted before preview and upload.',
            softwrap: true,
          ),
          onChanged: (value) {
            setState(() {
              _includeLogs = value ?? false;
              _payload = null;
              _error = null;
            });
          },
        ),
        CheckboxListTile(
          value: _includeDiagnostics,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const tiamat.Text.label('Include device diagnostics'),
          subtitle: const tiamat.Text.labelLow(
            'Adds app build, platform, OS, and redacted device information.',
            softwrap: true,
          ),
          onChanged: (value) {
            setState(() {
              _includeDiagnostics = value ?? false;
              _payload = null;
              _error = null;
            });
          },
        ),
      ],
    );
  }

  Widget _buildPreviewButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: tiamat.Button(
        text: _buildingPreview ? 'Preparing...' : 'Preview Report',
        isLoading: _buildingPreview,
        onTap: _buildingPreview ? null : _previewReport,
      ),
    );
  }

  Widget _buildSeveritySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final severity in _severityOptions)
          RadioListTile<BugReportSeverity>(
            value: severity,
            groupValue: _severity,
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: tiamat.Text.label(severity.plainLabel),
            subtitle: tiamat.Text.labelLow(
              severity.plainDescription,
              softwrap: true,
            ),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _severity = value;
                _payload = null;
                _error = null;
              });
            },
          ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    final payload = _payload;
    final error = _error;

    return _ReportBugSection(
      title: 'Review and submit',
      children: [
        if (payload == null && error == null)
          tiamat.Text.body(_template.previewEmptyText, softwrap: true),
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: _StatusBanner(
              icon: Icons.error_outline,
              text: error,
              isError: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (payload != null) ...[
          _ReviewSummary(payload: payload),
          const SizedBox(height: 12),
          const _PrivacyCaution(),
          const SizedBox(height: 12),
          _PayloadSummary(payload: payload),
          const SizedBox(height: 12),
          _PayloadPreview(text: payload.toPrettyJson()),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              tiamat.Button.secondary(
                text: 'Copy Payload',
                onTap: () => Clipboard.setData(
                  ClipboardData(text: payload.toPrettyJson()),
                ),
              ),
              tiamat.Button(
                text: _submitting ? 'Uploading...' : 'Submit Report',
                isLoading: _submitting,
                onTap: _submitting ? null : _submitReport,
              ),
            ],
          ),
        ],
      ],
    );
  }

  TextEditingController _categoryTextControllerFor(String questionId) {
    return _categoryTextControllers.putIfAbsent(
      questionId,
      TextEditingController.new,
    );
  }

  BugReportInput _input() {
    final category = _category;
    final answers = <String, String>{};
    if (category != null) {
      for (final question in category.questions) {
        if (question.isChoice) {
          final value = _choiceAnswers[question.id];
          if (value != null && value.isNotEmpty) {
            answers[question.id] = value;
          }
        } else {
          final value = _categoryTextControllers[question.id]?.text ?? '';
          if (value.trim().isNotEmpty) {
            answers[question.id] = value;
          }
        }
      }
    }

    return BugReportInput(
      title: _titleController.text,
      reproductionSteps: _stepsController.text,
      template: _template,
      severity: _severity,
      category: _guided ? _category : null,
      whatHappened: _guided ? _whatHappenedController.text : '',
      frequency: _guided ? _frequency : null,
      expectedBehavior: _expectedController.text,
      actualBehavior: _guided ? '' : _actualController.text,
      troubleshootingTried: _guided
          ? _troubleshootingSelected.toList()
          : const [],
      troubleshootingNote: _guided ? _troubleshootNoteController.text : '',
      categoryAnswers: answers,
      additionalDetails: _guided ? _detailsController.text : '',
      includeLogs: _includeLogs,
      includeDiagnostics: _includeDiagnostics,
      additionalMetadata: widget.initialAdditionalMetadata,
      additionalAttachments: widget.initialAdditionalAttachments,
      reportNotice: widget.initialReportNotice,
    );
  }

  /// Guided form validation. Returns a user-facing message for the first
  /// missing required answer, or null when the report is ready to preview.
  String? _guidedValidationError() {
    if (!_guided) {
      return null;
    }
    if (_category == null) {
      return 'Select which part of the app is affected.';
    }
    if (_whatHappenedController.text.trim().isEmpty) {
      return 'Describe what happened before previewing the report.';
    }
    if (_frequency == null) {
      return 'Choose how often the problem happens.';
    }
    if (_titleController.text.trim().isEmpty) {
      return 'Add a short summary, or use Suggest to generate one.';
    }
    return null;
  }

  void _suggestTitle() {
    final happened = _whatHappenedController.text.trim();
    final firstLine = happened.isEmpty
        ? ''
        : happened
              .split('\n')
              .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    var summary = firstLine.trim();
    if (summary.length > 90) {
      summary = '${summary.substring(0, 87).trimRight()}...';
    }
    if (summary.isEmpty) {
      summary = _category?.label ?? '';
    }
    if (summary.isEmpty) {
      return;
    }
    setState(() {
      _titleController.text = summary;
      _payload = null;
      _error = null;
    });
  }

  Future<void> _previewReport() async {
    _dismissKeyboard();
    final guidedError = _guidedValidationError();
    if (guidedError != null) {
      setState(() {
        _error = guidedError;
        _payload = null;
      });
      return;
    }

    final input = _input();
    final validationError = input.validate();
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _payload = null;
      });
      return;
    }

    setState(() {
      _buildingPreview = true;
      _error = null;
      _payload = null;
    });

    try {
      final payload = await _service.buildPayload(input);
      if (!mounted) {
        return;
      }
      setState(() {
        _payload = payload;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to build report preview: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _buildingPreview = false;
        });
      }
    }
  }

  Future<void> _submitReport() async {
    _dismissKeyboard();
    final payload = _payload;
    if (payload == null) {
      return;
    }

    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Submit bug report?',
      prompt:
          'Send the previewed report payload to Inter Galactic support now?',
      confirmationText: 'Submit',
      cancelText: 'Cancel',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _service.submit(payload);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      // Preserve the previewed payload and entered form data so the user can
      // retry the same report without re-entering anything.
      setState(() {
        _error = 'Upload failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _resetForAnotherReport() {
    setState(() {
      _result = null;
      _payload = null;
      _error = null;
    });
  }

  bool get _isMobileKeyboardPlatform =>
      PlatformUtils.isAndroid || PlatformUtils.isIOS;

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _reportBodyPreview() {
    final sections = <String>[
      'Reproduction steps:\n${_stepsController.text}',
      if (_expectedController.text.trim().isNotEmpty)
        'Expected behavior:\n${_expectedController.text}',
      if (_actualController.text.trim().isNotEmpty)
        'Actual behavior:\n${_actualController.text}',
    ];
    return sections.join('\n\n').trim();
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
          if (required) ...[
            const SizedBox(width: 6),
            Text(
              '(required)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 11,
          height: 1.25,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ChoiceOption {
  const _ChoiceOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Accessible single-select chip row. Each chip exposes its selected state to
/// screen readers via [ChoiceChip].
///
/// Tapping always forwards the tapped value to the callback; whether tapping an
/// already-selected chip clears it is up to that callback. The category
/// question deselects on repeat tap, the frequency selector does not.
class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
  });

  final List<_ChoiceOption> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final wrap = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.label),
            selected: selected == option.value,
            onSelected: (_) => onSelected(option.value),
          ),
      ],
    );
    if (semanticLabel == null) {
      return wrap;
    }
    return Semantics(label: semanticLabel, container: true, child: wrap);
  }
}

class _TroubleshootingCard extends StatelessWidget {
  const _TroubleshootingCard({
    required this.category,
    required this.expanded,
    required this.onToggle,
  });

  final BugReportCategory category;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: tiamat.Text.label(
                    category.troubleshootingTitle,
                    softwrap: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          tiamat.Text.labelLow(
            'These may help. You can still report the issue if they do not.',
            softwrap: true,
          ),
          const SizedBox(height: 8),
          if (expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tip in category.troubleshootingTips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: tiamat.Text.label(tip, softwrap: true)),
                      ],
                    ),
                  ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggle,
              child: Text(
                expanded ? 'Hide troubleshooting tips' : 'View troubleshooting',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.payload});

  final BugReportPayload payload;

  @override
  Widget build(BuildContext context) {
    final report = payload.data['report'];
    final data = report is Map ? report : const <Object?, Object?>{};

    final rows = <_SummaryRow>[
      if (data['category_label'] is String)
        _SummaryRow(label: 'Category', value: data['category_label'] as String),
      if (data['frequency_label'] is String)
        _SummaryRow(
          label: 'Frequency',
          value: data['frequency_label'] as String,
        ),
      if (data['severity_label'] is String)
        _SummaryRow(label: 'Severity', value: data['severity_label'] as String),
    ];

    final included = payload.data['included'];
    final attachments = <String>[
      if (included is Map && included['logs'] == true) 'Redacted logs',
      if (included is Map && included['diagnostics'] == true)
        'App version, platform, and diagnostics',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: tiamat.Text.label('Report summary')),
        const SizedBox(height: 8),
        ...rows,
        if (attachments.isNotEmpty)
          _SummaryRow(
            label: 'Diagnostics attached',
            value: attachments.join(', '),
          ),
      ],
    );
  }
}

class _PrivacyCaution extends StatelessWidget {
  const _PrivacyCaution();

  @override
  Widget build(BuildContext context) {
    return const _StatusBanner(
      icon: Icons.shield_outlined,
      text:
          'Do not include passwords, access tokens, recovery keys, or highly '
          'personal information.',
    );
  }
}

class _PayloadSummary extends StatelessWidget {
  const _PayloadSummary({required this.payload});

  final BugReportPayload payload;

  @override
  Widget build(BuildContext context) {
    final attachments = payload.attachments;
    final reportHash = payload.data['report_hash'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryRow(
          label: 'Template',
          value: (payload.data['template_label'] as String?) ?? 'App bug',
        ),
        _SummaryRow(
          label: 'Payload size',
          value: TextUtils.readableFileSize(payload.sizeBytes),
        ),
        if (reportHash is String && reportHash.isNotEmpty)
          _SummaryRow(label: 'Report hash', value: reportHash),
        _SummaryRow(
          label: 'Attachment fields',
          value: attachments.isEmpty ? 'None' : attachments.length.toString(),
        ),
        for (final attachment in attachments)
          _SummaryRow(
            label: attachment.name,
            value:
                '${TextUtils.readableFileSize(attachment.sizeBytes)} in ${attachment.field}',
          ),
      ],
    );
  }
}

class _TemplateStaticField extends StatelessWidget {
  const _TemplateStaticField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(label),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.48),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _PayloadPreview extends StatefulWidget {
  const _PayloadPreview({required this.text});

  final String text;

  @override
  State<_PayloadPreview> createState() => _PayloadPreviewState();
}

class _PayloadPreviewState extends State<_PayloadPreview> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
      ),
      child: Scrollbar(
        controller: _verticalController,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.vertical,
        child: SingleChildScrollView(
          controller: _verticalController,
          padding: const EdgeInsets.all(12),
          child: Scrollbar(
            controller: _horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'Code',
                  fontSize: 12,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: tiamat.Text.labelLow(label, softwrap: true),
          ),
          const SizedBox(width: 10),
          Expanded(child: tiamat.Text.label(value, softwrap: true)),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: tiamat.Text.label(text, softwrap: true)),
        ],
      ),
    );
  }
}

class _ReportBugSection extends StatelessWidget {
  const _ReportBugSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

extension _BugReportTemplateView on BugReportTemplate {
  String get dialogTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Report a Bug',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  String get pageTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Report a Bug',
      BugReportTemplate.callStreamLogs => 'Call/stream logs',
    };
  }

  String get introText {
    return switch (this) {
      BugReportTemplate.genericAppBug =>
        'Answer a few plain-language questions so support can understand the '
            'problem. Nothing is sent until you preview the exact payload and '
            'confirm submission.',
      BugReportTemplate.callStreamLogs =>
        'Create a call/stream log report for Inter Galactic support. Recent logs '
            'and diagnostics stay redacted and previewable before submission.',
    };
  }

  String get formSectionTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Tell us what happened',
      BugReportTemplate.callStreamLogs => 'Call/stream log details',
    };
  }

  String get previewEmptyText {
    return switch (this) {
      BugReportTemplate.genericAppBug =>
        'Build a preview to review exactly what will leave this device.',
      BugReportTemplate.callStreamLogs =>
        'Build a preview to confirm the call/stream log payload and template tag before anything leaves this device.',
    };
  }
}
