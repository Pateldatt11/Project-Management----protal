import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../app/workspace_state.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/platform/browser_download/browser_download.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';
import '../../../data/models/project.dart';
import '../../../data/models/report.dart';
import '../data/local_monthly_analytics_builder.dart';
import '../data/monthly_analytics_service.dart';
import '../data/oracle_report_backend_service.dart';
import '../data/report_runtime_config.dart';
import '../html/dynamic_report_html_builder.dart';
import '../html/report_html_printer.dart';
import '../pdf/dynamic_report_pdf_builder.dart';
import 'pdf_preview_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final MonthlyAnalyticsService _analyticsService = MonthlyAnalyticsService();
  final LocalMonthlyAnalyticsBuilder _localAnalyticsBuilder = const LocalMonthlyAnalyticsBuilder();
  final OracleReportBackendService _reportBackendService = OracleReportBackendService();
  late String _selectedMonthId = _monthId(DateTime.now());
  bool _refreshing = false;
  String? _buildingPdfReportId;
  MonthlyAnalyticsSnapshot? _localSnapshot;

  @override
  void dispose() {
    _reportBackendService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final canGenerate = PermissionService.canGenerateReports(state.currentMember);
    final registeredCompanyName = state.company.name.isNotEmpty && state.company.name != 'Company Workspace'
        ? state.company.name
        : 'Company Workspace';

    final liveLocalSnapshot = _localAnalyticsBuilder.build(
      companyId: state.company.companyId,
      monthId: _selectedMonthId,
      projects: state.visibleProjects,
      tasks: state.visibleTasks,
      members: state.members,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportsHero(
            monthId: _selectedMonthId,
            canGenerate: canGenerate,
            refreshing: _refreshing,
            companyName: registeredCompanyName,
            onMonthChanged: (value) => setState(() {
              _selectedMonthId = value;
              _localSnapshot = null;
            }),
            onRefresh: canGenerate ? () => _refreshSnapshot(state) : null,
            onGenerate: canGenerate ? () => _showGenerateDialog(context, state, registeredCompanyName) : null,
          ),
          const SizedBox(height: 14),
          StreamBuilder<MonthlyAnalyticsSnapshot?>(
            stream: _analyticsService.watchMonth(companyId: state.company.companyId, monthId: _selectedMonthId),
            builder: (context, snapshot) {
              final effectiveSnapshot = _localSnapshot?.monthId == _selectedMonthId
                  ? _localSnapshot
                  : snapshot.data ?? liveLocalSnapshot;
              return _MonthlySnapshotPanel(
                snapshot: effectiveSnapshot,
                loading: effectiveSnapshot == null && snapshot.connectionState == ConnectionState.waiting,
                hasError: effectiveSnapshot == null && snapshot.hasError,
              );
            },
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Generated reports',
            subtitle: 'Reports feature entity name "$registeredCompanyName" and remain downloadable as multi-page PDFs[cite: 1].',
            child: state.reports.isEmpty
                ? const _EmptyReports()
                : Column(
                    children: state.reports
                        .map(
                          (report) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _GeneratedReportCard(
                              report: report,
                              building: _buildingPdfReportId == report.reportId,
                              onPreview: () => _buildAndOpenPdf(
                                report: report,
                                state: state,
                                registeredCompanyName: registeredCompanyName,
                                openPreview: true,
                              ),
                              onExportCsv: () => _exportReportCsv(report: report, state: state),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSnapshot(WorkspaceState state) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final local = _localAnalyticsBuilder.build(
        companyId: state.company.companyId,
        monthId: _selectedMonthId,
        projects: state.visibleProjects,
        tasks: state.visibleTasks,
        members: state.members,
      );
      var effective = local;
      var sourceLabel = 'locally';
      if (_reportBackendService.canAttempt) {
        try {
          effective = await _reportBackendService.rebuildMonthlyAnalytics(
            companyId: state.company.companyId,
            monthId: _selectedMonthId,
          );
          sourceLabel = 'through the Oracle Admin SDK backend';
        } catch (_) {
          // Local generation fallback
        }
      }
      if (!mounted) return;
      setState(() => _localSnapshot = effective);
      _show('Monthly analytics rebuilt $sourceLabel for $_selectedMonthId.');
    } catch (error) {
      if (!mounted) return;
      _show('Local monthly analytics refresh failed: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _showGenerateDialog(BuildContext context, WorkspaceState state, String registeredCompanyName) async {
    final types = <String>[
      'Monthly Company Report',
      'Employee Performance',
      'Project Summary',
      'Team Productivity',
      'Workload Report',
      'Timeline & Risk Report',
      'Appraisal & Career Report',
    ];
    var selectedType = types.first;
    var selectedMonth = _selectedMonthId;
    var selectedProjectId = 'all';
    var previewPdf = true;
    var busy = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Generate report for $registeredCompanyName'),
            content: SizedBox(
              width: math.min(560, MediaQuery.sizeOf(context).width - 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Report type', border: OutlineInputBorder()),
                    items: types.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: busy ? null : (value) => setDialogState(() => selectedType = value ?? selectedType),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMonth,
                    decoration: const InputDecoration(labelText: 'Reporting month', border: OutlineInputBorder()),
                    items: _recentMonthIds(18).map((month) => DropdownMenuItem(value: month, child: Text(_monthLabel(month)))).toList(),
                    onChanged: busy ? null : (value) => setDialogState(() => selectedMonth = value ?? selectedMonth),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProjectId,
                    decoration: const InputDecoration(labelText: 'Project scope', border: OutlineInputBorder()),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem(value: 'all', child: Text('All projects')),
                      ...state.visibleProjects.map((project) => DropdownMenuItem(value: project.projectId, child: Text(project.name))),
                    ],
                    onChanged: busy ? null : (value) => setDialogState(() => selectedProjectId = value ?? 'all'),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(13)),
                    child: Text(
                      'Reports are generated locally for "$registeredCompanyName" from projects, tasks, employees, and appraisals loaded in this session.',
                      style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.w700, height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: previewPdf,
                    title: Text(kIsWeb
                        ? 'Open browser print preview after generation'
                        : 'Open PDF preview after generation'),
                    subtitle: Text(kIsWeb
                        ? "Uses browser print preview. Save as PDF to retain design."
                        : 'Local generation completed securely.'),
                    onChanged: busy ? null : (value) => setDialogState(() => previewPdf = value),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() {
                          busy = true;
                          errorText = null;
                        });
                        try {
                          final snapshot = _localAnalyticsBuilder.build(
                            companyId: state.company.companyId,
                            monthId: selectedMonth,
                            projectId: selectedProjectId == 'all' ? null : selectedProjectId,
                            projects: state.visibleProjects,
                            tasks: state.visibleTasks,
                            members: state.members,
                          );
                          final selectedProject = selectedProjectId == 'all' ? null : _projectById(state.visibleProjects, selectedProjectId);
                          final reportMetrics = <String, dynamic>{
                            ...snapshot.metrics,
                            'reportScope': selectedProjectId == 'all' ? 'all' : 'project',
                            'Report scope': selectedProjectId == 'all' ? 'All Projects' : (selectedProject?.name ?? 'Selected Project'),
                            'Scope project ID': selectedProjectId,
                            'companyName': registeredCompanyName,
                            if (selectedProject != null) 'projectName': selectedProject.name,
                            if (selectedProjectId != 'all') 'projectMetrics': snapshot.projectMetrics(selectedProjectId) ?? const <String, dynamic>{},
                            'snapshotGenerationId': snapshot.generationId,
                            'minimumPdfPages': 8,
                          };
                          final report = ref.read(workspaceProvider.notifier).generateReport(
                                selectedType,
                                monthId: selectedMonth,
                                projectId: selectedProjectId == 'all' ? null : selectedProjectId,
                                metrics: reportMetrics,
                                snapshotGeneratedAt: snapshot.generatedAt,
                                isSnapshotFinalized: snapshot.isFinalized,
                              );
                          if (report == null) {
                            throw StateError('The report record could not be created for this role.');
                          }
                          if (!mounted) return;
                          setState(() {
                            _selectedMonthId = selectedMonth;
                            _localSnapshot = snapshot;
                          });
                          Navigator.of(dialogContext).pop();
                          _show('$selectedType record created. Building PDF...');
                          await _buildAndOpenPdf(
                            report: report,
                            state: ref.read(workspaceProvider),
                            registeredCompanyName: registeredCompanyName,
                            openPreview: previewPdf,
                            snapshot: snapshot,
                          );
                        } catch (error) {
                          setDialogState(() {
                            busy = false;
                            errorText = '$error';
                          });
                        }
                      },
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(busy ? 'Building locally…' : 'Generate'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _buildAndOpenPdf({
    required ReportModel report,
    required WorkspaceState state,
    required String registeredCompanyName,
    required bool openPreview,
    MonthlyAnalyticsSnapshot? snapshot,
  }) async {
    if (_buildingPdfReportId != null) {
      _show('Another PDF is already being generated.');
      return;
    }
    setState(() => _buildingPdfReportId = report.reportId);
    try {
      final reportMonth = report.monthId.isEmpty ? report.period : report.monthId;
      final loadedSnapshot = snapshot ??
          await _analyticsService.loadMonth(
            companyId: state.company.companyId,
            monthId: reportMonth,
          ) ??
          _localAnalyticsBuilder.build(
            companyId: state.company.companyId,
            monthId: reportMonth,
            projectId: report.projectId,
            projects: state.visibleProjects,
            tasks: state.visibleTasks,
            members: state.members,
          );
      final projectId = (report.projectId ?? '').trim();
      final scopedProjects = projectId.isEmpty
          ? state.visibleProjects
          : state.visibleProjects.where((project) => project.projectId == projectId).toList(growable: false);
      final scopedTasks = projectId.isEmpty
          ? state.visibleTasks
          : state.visibleTasks.where((task) => task.projectId == projectId).toList(growable: false);
      final memberIds = <String>{};
      for (final task in scopedTasks) {
        memberIds.addAll(task.assignedToIds);
      }
      for (final project in scopedProjects) {
        memberIds.addAll(project.managerIds);
      }
      final scopedMembers = projectId.isEmpty
          ? state.members
          : state.members
              .where(
                (member) =>
                    memberIds.contains(member.uid) ||
                    member.projectIds.contains(projectId),
              )
              .toList(growable: false);

      final reportTitle =
          '${report.reportType}_${report.monthId.isEmpty ? report.period : report.monthId}';

      if (kIsWeb) {
        final reportHtml = const DynamicReportHtmlBuilder().build(
          report: report,
          projects: scopedProjects,
          tasks: scopedTasks,
          members: scopedMembers,
          monthlySnapshot: loadedSnapshot,
          minPages: 8,
        );

        if (openPreview) {
          final opened = await ReportHtmlPrinter.printHtml(
            title: reportTitle,
            html: reportHtml,
          );
          if (!opened && mounted) {
            _show('The browser print preview could not be opened.');
          }
        } else if (mounted) {
          _show('HTML/CSS report generated locally for $registeredCompanyName.');
        }
        return;
      }

      final bytes = await const DynamicReportPdfBuilder().build(
        report: report,
        projects: scopedProjects,
        tasks: scopedTasks,
        members: scopedMembers,
        monthlySnapshot: loadedSnapshot,
        minPages: 8,
      );

      String? uploadWarning;
      final storagePath = (report.pdfPath ?? '').trim();
      if (ReportRuntimeConfig.uploadPdfToFirebaseStorage && storagePath.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(storagePath).putData(
                bytes,
                SettableMetadata(
                  contentType: 'application/pdf',
                  customMetadata: <String, String>{
                    'reportId': report.reportId,
                    'companyName': registeredCompanyName,
                    'monthId': report.monthId.isEmpty ? report.period : report.monthId,
                    'projectScope': report.projectScope,
                  },
                ),
              );
        } catch (error) {
          uploadWarning = 'PDF preview ready, but Firebase Storage upload failed: $error';
        }
      }

      if (!mounted) return;
      if (uploadWarning != null) _show(uploadWarning);
      if (openPreview) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfPreviewScreen(
              title: reportTitle,
              pdfBytes: bytes,
            ),
          ),
        );
      } else {
        _show('PDF generated successfully for $registeredCompanyName.');
      }
    } catch (error) {
      if (mounted) _show('PDF generation failed: $error');
    } finally {
      if (mounted) setState(() => _buildingPdfReportId = null);
    }
  }

  Future<void> _exportReportCsv({
    required ReportModel report,
    required WorkspaceState state,
  }) async {
    final monthId = report.monthId.isEmpty ? report.period : report.monthId;
    final snapshot = _localAnalyticsBuilder.build(
      companyId: state.company.companyId,
      monthId: monthId,
      projectId: report.projectId,
      projects: state.visibleProjects,
      tasks: state.visibleTasks,
      members: state.members,
    );
    final rows = <String>[
      'Report Type,Month,Scope,Generated At',
      <String>[
        _csvCell(report.reportType),
        _csvCell(monthId),
        _csvCell(report.projectScope),
        _csvCell(snapshot.generatedAt.toIso8601String()),
      ].join(','),
      '',
      'Metric,Value',
      ...snapshot.metrics.entries.map((entry) => '${_csvCell(entry.key)},${_csvCell(entry.value)}'),
    ];
    final downloaded = await downloadTextFile(
      fileName: '${_safeFilePart(report.reportType)}_${_safeFilePart(monthId)}.csv',
      content: rows.join('\n'),
      mimeType: 'text/csv;charset=utf-8',
    );
    if (!mounted) return;
    _show(downloaded ? 'Report CSV downloaded.' : 'CSV download is available in Flutter Web.');
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GeneratedReportCard extends StatelessWidget {
  const _GeneratedReportCard({
    required this.report,
    required this.building,
    required this.onPreview,
    required this.onExportCsv,
  });

  final ReportModel report;
  final bool building;
  final VoidCallback onPreview;
  final VoidCallback onExportCsv;

  @override
  Widget build(BuildContext context) {
    final scope = report.projectScope == 'project'
        ? (report.metrics['projectName']?.toString() ?? 'Single project')
        : 'All projects';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.reportType, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      '${report.monthId.isEmpty ? report.period : report.monthId} • $scope • Created ${DateText.compact(report.createdAt)}',
                      style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        StatusBadge(label: report.status, color: Colors.green),
                        StatusBadge(
                          label: report.isSnapshotFinalized ? 'Finalized snapshot' : 'Live snapshot',
                          color: report.isSnapshotFinalized ? Colors.teal : Colors.blue,
                        ),
                        const StatusBadge(label: '8+ pages', color: Colors.deepPurple),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: building ? null : onPreview,
                icon: building
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(kIsWeb ? Icons.print_rounded : Icons.preview_rounded),
                label: Text(building ? 'Building PDF' : kIsWeb ? 'Print / Save PDF' : 'Preview PDF'),
              ),
              OutlinedButton.icon(
                onPressed: onExportCsv,
                icon: const Icon(Icons.download_for_offline_rounded),
                label: const Text('Download CSV'),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 14), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 14),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({
    required this.monthId,
    required this.canGenerate,
    required this.refreshing,
    required this.companyName,
    required this.onMonthChanged,
    required this.onRefresh,
    required this.onGenerate,
  });

  final String monthId;
  final bool canGenerate;
  final bool refreshing;
  final String companyName;
  final ValueChanged<String> onMonthChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF07152E), Color(0xFF173B73)]),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x3307152E), blurRadius: 24, offset: Offset(0, 14))],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 185,
                child: DropdownButtonFormField<String>(
                  initialValue: monthId,
                  dropdownColor: const Color(0xFF102544),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    labelText: 'Reporting month',
                    labelStyle: const TextStyle(color: Color(0xFFBFDBFE)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(.08),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(.18))),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: _recentMonthIds(18).map((month) => DropdownMenuItem(value: month, child: Text(_monthLabel(month)))).toList(),
                  onChanged: (value) {
                    if (value != null) onMonthChanged(value);
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: onRefresh,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(.35)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                icon: refreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync_rounded),
                label: Text(refreshing ? 'Refreshing' : 'Refresh month'),
              ),
              FilledButton.icon(
                onPressed: onGenerate,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                icon: const Icon(Icons.add_chart_rounded),
                label: const Text('Generate Report'),
              ),
            ],
          );
          return constraints.maxWidth < 820
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_heroText(companyName), const SizedBox(height: 18), controls])
              : Row(children: [Expanded(child: _heroText(companyName)), controls]);
        },
      ),
    );
  }

  Widget _heroText(String companyName) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reporting intelligence • $companyName', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          const Text(
            'Local current-month analytics, optional Oracle-backed canonical snapshots, all-project or single-project scope, and downloadable PDF/CSV reports.',
            style: TextStyle(color: Color(0xFFC7D2E4), fontWeight: FontWeight.w700, height: 1.4),
          ),
        ],
      );
}

class _MonthlySnapshotPanel extends StatelessWidget {
  const _MonthlySnapshotPanel({required this.snapshot, required this.loading, required this.hasError});

  final MonthlyAnalyticsSnapshot? snapshot;
  final bool loading;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    if (loading && snapshot == null) {
      return const SectionCard(title: 'Monthly snapshot', subtitle: 'Loading analytics…', child: LinearProgressIndicator());
    }
    if (hasError) {
      return const SectionCard(title: 'Monthly snapshot', subtitle: 'The Firestore snapshot could not be loaded.', child: Text('Use Refresh month to rebuild locally, or start the Oracle backend for a canonical snapshot.'));
    }
    if (snapshot == null) {
      return const SectionCard(
        title: 'Monthly snapshot not built yet',
        subtitle: 'Use Refresh month or Generate Report.',
        child: Text('No snapshot document is available for this month.'),
      );
    }
    final data = snapshot!;
    final metrics = <({String label, String value, IconData icon, Color color})>[
      (label: 'Projects', value: '${data.metricInt('activeProjectCount')}', icon: Icons.folder_rounded, color: const Color(0xFF7C3AED)),
      (label: 'Tasks', value: '${data.metricInt('taskCount')}', icon: Icons.task_alt_rounded, color: const Color(0xFF2563EB)),
      (label: 'Completed', value: '${data.metricInt('tasksCompleted')}', icon: Icons.verified_rounded, color: const Color(0xFF16A34A)),
      (label: 'Overdue', value: '${data.metricInt('tasksOverdue')}', icon: Icons.warning_amber_rounded, color: const Color(0xFFEF4444)),
      (label: 'Completion', value: '${data.metricInt('completionRate')}%', icon: Icons.auto_graph_rounded, color: const Color(0xFF0F9F91)),
      (label: 'Appraisal avg', value: '${data.metricInt('appraisalAverage')}%', icon: Icons.workspace_premium_rounded, color: const Color(0xFFF59E0B)),
    ];
    return SectionCard(
      title: data.isFinalized ? 'Finalized monthly snapshot' : 'Live monthly snapshot',
      subtitle: 'Data through ${DateText.compact(data.reportingCutoff ?? data.generatedAt)} • updated ${DateText.compact(data.generatedAt)}',
      trailing: StatusBadge(label: data.isFinalized ? 'Finalized' : 'Live draft', color: data.isFinalized ? Colors.green : Colors.blue),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 520 ? 2 : constraints.maxWidth < 920 ? 3 : 6;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics.map((item) => SizedBox(width: width, child: _SnapshotMetric(item: item))).toList(),
          );
        },
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  const _SnapshotMetric({required this.item});

  final ({String label, String value, IconData icon, Color color}) item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const SizedBox(height: 9),
          Text(item.value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(child: Text('No generated reports yet.')),
    );
  }
}

Project? _projectById(List<Project> projects, String projectId) {
  for (final project in projects) {
    if (project.projectId == projectId) return project;
  }
  return null;
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  final escaped = text.replaceAll('\"', '\"\"');
  return '"$escaped"';
}

String _safeFilePart(String value) {
  final clean = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return clean.isEmpty ? 'report' : clean;
}

String _monthId(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

List<String> _recentMonthIds(int count) {
  final now = DateTime.now();
  return List<String>.generate(count, (index) => _monthId(DateTime(now.year, now.month - index, 1)));
}

String _monthLabel(String monthId) {
  final parts = monthId.split('-');
  final year = int.tryParse(parts.first) ?? DateTime.now().year;
  final month = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
  const names = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${names[(month - 1).clamp(0, 11)]} $year';
}