import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/bug_report/bug_report_service.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

Future<void> showReportBugDialog(
  BuildContext context, {
  BugReportTemplate template = BugReportTemplate.genericAppBug,
  String? initialTitle,
  String? initialReproductionSteps,
  String? initialExpectedBehavior,
  String? initialActualBehavior,
  BugReportSeverity initialSeverity = BugReportSeverity.medium,
  bool includeLogs = true,
  bool includeDiagnostics = true,
  Map<String, Object?> additionalMetadata = const {},
  List<BugReportAttachmentSummary> additionalAttachments = const [],
  String? reportNotice,
}) async {
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
        initialIncludeLogs: includeLogs,
        initialIncludeDiagnostics: includeDiagnostics,
        initialAdditionalMetadata: additionalMetadata,
        initialAdditionalAttachments: additionalAttachments,
        initialReportNotice: reportNotice,
      );

      if (!Layout.desktop) {
        return page;
      }

      final mediaQuery = MediaQuery.of(context);
      final availableWidth = mediaQuery.size.width -
          mediaQuery.viewPadding.horizontal -
          mediaQuery.viewInsets.horizontal;
      final availableHeight = mediaQuery.size.height -
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
    this.initialIncludeLogs = true,
    this.initialIncludeDiagnostics = true,
    this.initialAdditionalMetadata = const {},
    this.initialAdditionalAttachments = const [],
    this.initialReportNotice,
    super.key,
  });

  final BugReportService? service;
  final String? initialTitle;
  final String? initialReproductionSteps;
  final String? initialExpectedBehavior;
  final String? initialActualBehavior;
  final BugReportTemplate initialTemplate;
  final BugReportSeverity initialSeverity;
  final bool initialIncludeLogs;
  final bool initialIncludeDiagnostics;
  final Map<String, Object?> initialAdditionalMetadata;
  final List<BugReportAttachmentSummary> initialAdditionalAttachments;
  final String? initialReportNotice;

  @override
  State<ReportBugPage> createState() => _ReportBugPageState();
}

class _ReportBugPageState extends State<ReportBugPage> {
  static const List<BugReportSeverity> _severityOptions = [
    BugReportSeverity.critical,
    BugReportSeverity.high,
    BugReportSeverity.medium,
    BugReportSeverity.low,
  ];

  late final BugReportService _service;
  late final bool _ownsService;
  late final TextEditingController _titleController;
  late final TextEditingController _stepsController;
  late final TextEditingController _expectedController;
  late final TextEditingController _actualController;
  late final BugReportTemplate _template;

  bool _includeLogs = true;
  bool _includeDiagnostics = true;
  late BugReportSeverity _severity;
  bool _buildingPreview = false;
  bool _submitting = false;
  BugReportPayload? _payload;
  BugReportSubmissionResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? BugReportService();
    _template = widget.initialTemplate;
    _includeLogs = widget.initialIncludeLogs;
    _includeDiagnostics = widget.initialIncludeDiagnostics;
    _severity = widget.initialSeverity;
    _titleController = TextEditingController(
      text: widget.initialTitle ?? _template.defaultTitle,
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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _stepsController.dispose();
    _expectedController.dispose();
    _actualController.dispose();
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
    return _ReportBugSection(
      title: _template.formSectionTitle,
      children: [
        if (_template.usesFixedDetails) ...[
          _TemplateStaticField(
            label: 'Template',
            value: _template.label,
          ),
          const SizedBox(height: 10),
          _TemplateStaticField(
            label: 'Title',
            value: _titleController.text,
          ),
          const SizedBox(height: 10),
          _TemplateStaticField(
            label: 'Report body',
            value: _reportBodyPreview(),
          ),
        ] else ...[
          tiamat.TextInput(
            label: 'Title',
            placeholder: 'Short summary',
            controller: _titleController,
            maxLength: 120,
          ),
          const SizedBox(height: 10),
          _buildSeveritySelector(),
          const SizedBox(height: 10),
          tiamat.TextInput(
            label: 'Reproduction steps',
            placeholder: '1. Open...\n2. Tap...\n3. See...',
            controller: _stepsController,
            minLines: 4,
            maxLines: 8,
            maxLength: 2500,
          ),
          const SizedBox(height: 10),
          tiamat.TextInput(
            label: 'Expected behavior',
            placeholder: 'Optional',
            controller: _expectedController,
            minLines: 2,
            maxLines: 5,
            maxLength: 1200,
          ),
          const SizedBox(height: 10),
          tiamat.TextInput(
            label: 'Actual behavior',
            placeholder: 'Optional',
            controller: _actualController,
            minLines: 2,
            maxLines: 5,
            maxLength: 1200,
          ),
        ],
        if (_template.usesFixedDetails) ...[
          const SizedBox(height: 10),
          _buildSeveritySelector(),
        ],
        if (widget.initialReportNotice != null &&
            widget.initialReportNotice!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _StatusBanner(
            icon: Icons.attach_file_outlined,
            text: widget.initialReportNotice!.trim(),
          ),
        ],
        if (_isMobileKeyboardPlatform) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button.secondary(
              text: 'Dismiss Keyboard',
              onTap: _dismissKeyboard,
            ),
          ),
        ],
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: tiamat.Button(
            text: _buildingPreview ? 'Preparing...' : 'Preview Report',
            isLoading: _buildingPreview,
            onTap: _buildingPreview ? null : _previewReport,
          ),
        ),
      ],
    );
  }

  Widget _buildSeveritySelector() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const tiamat.Text.labelLow('Severity'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
          child: tiamat.DropdownSelector<BugReportSeverity>(
            color: theme.colorScheme.surfaceContainer,
            items: _severityOptions,
            itemBuilder: (severity) => tiamat.Text.label(severity.label),
            onItemSelected: (severity) {
              if (severity == null) {
                return;
              }
              setState(() {
                _severity = severity;
                _payload = null;
                _error = null;
              });
            },
            value: _severity,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    final payload = _payload;
    final error = _error;

    return _ReportBugSection(
      title: 'Preview and submit',
      children: [
        if (payload == null && error == null)
          tiamat.Text.body(
            _template.previewEmptyText,
            softwrap: true,
          ),
        if (error != null) ...[
          _StatusBanner(
            icon: Icons.error_outline,
            text: error,
            isError: true,
          ),
          const SizedBox(height: 12),
        ],
        if (payload != null) ...[
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

  BugReportInput _input() {
    return BugReportInput(
      title: _titleController.text,
      reproductionSteps: _stepsController.text,
      template: _template,
      severity: _severity,
      expectedBehavior: _expectedController.text,
      actualBehavior: _actualController.text,
      includeLogs: _includeLogs,
      includeDiagnostics: _includeDiagnostics,
      additionalMetadata: widget.initialAdditionalMetadata,
      additionalAttachments: widget.initialAdditionalAttachments,
      reportNotice: widget.initialReportNotice,
    );
  }

  Future<void> _previewReport() async {
    _dismissKeyboard();
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
          _SummaryRow(
            label: 'Report hash',
            value: reportHash,
          ),
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
  const _TemplateStaticField({
    required this.label,
    required this.value,
  });

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
  const _SummaryRow({
    required this.label,
    required this.value,
  });

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
          Expanded(
            child: tiamat.Text.label(value, softwrap: true),
          ),
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
          Expanded(
            child: tiamat.Text.label(text, softwrap: true),
          ),
        ],
      ),
    );
  }
}

class _ReportBugSection extends StatelessWidget {
  const _ReportBugSection({
    required this.title,
    required this.children,
  });

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
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
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
        'Create an app diagnostic report for Inter Galactic. Nothing is sent until you preview the exact payload and confirm submission.',
      BugReportTemplate.callStreamLogs =>
        'Create a call/stream log report for Inter Galactic support. Recent logs and diagnostics stay redacted and previewable before submission.',
    };
  }

  String get formSectionTitle {
    return switch (this) {
      BugReportTemplate.genericAppBug => 'Bug details',
      BugReportTemplate.callStreamLogs => 'Call/stream log details',
    };
  }

  String get previewEmptyText {
    return switch (this) {
      BugReportTemplate.genericAppBug =>
        'Build a preview to see exactly what will leave this device.',
      BugReportTemplate.callStreamLogs =>
        'Build a preview to confirm the call/stream log payload and template tag before anything leaves this device.',
    };
  }
}
