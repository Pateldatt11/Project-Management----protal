import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/platform/browser_download/browser_download.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/employment_action.dart';
import '../../../data/models/member.dart';
import '../../../data/models/task.dart';
import '../data/appraisal_template_catalog.dart';
import '../data/career_progression_service.dart';

class AppraisalScreen extends ConsumerStatefulWidget {
  const AppraisalScreen({super.key});

  @override
  ConsumerState<AppraisalScreen> createState() => _AppraisalScreenState();
}

class _AppraisalScreenState extends ConsumerState<AppraisalScreen> {
  final TextEditingController _searchController = TextEditingController();
  final CareerProgressionService _careerService = CareerProgressionService();
  String _query = '';
  UserRole? _roleFilter;
  String? _selectedMemberId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final actor = state.currentMember;
    final canEdit = PermissionService.canEditAppraisal(actor);
    final records = _appraisalRecords(state, canEdit: canEdit).where((record) {
      if (_roleFilter != null && record.member.role != _roleFilter) return false;
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return '${record.member.displayName} ${record.member.email} ${record.member.role.label} ${record.member.effectiveDepartment} ${record.member.effectiveJobTitle} ${record.member.effectiveIndustryDiscipline}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final selected = records.isEmpty ? null : _selectedRecord(records, _selectedMemberId);

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1020;
            final pagePadding = constraints.maxWidth < 720 ? 10.0 : 18.0;
            return Padding(
              padding: EdgeInsets.all(pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AppraisalToolbar(
                    queryController: _searchController,
                    canEdit: canEdit,
                    roleFilter: _roleFilter,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onRoleChanged: (value) => setState(() => _roleFilter = value),
                    onClear: () => setState(() {
                      _query = '';
                      _roleFilter = null;
                      _searchController.clear();
                    }),
                    onExport: () => _copyAppraisalCsv(context, records),
                  ),
                  const SizedBox(height: 12),
                  _AppraisalSummaryStrip(records: records, actor: actor),
                  const SizedBox(height: 12),
                  Expanded(
                    child: records.isEmpty
                        ? const _EmptyAppraisalState()
                        : compact
                            ? _CompactAppraisalView(
                                records: records,
                                selected: selected!,
                                actor: actor,
                                companyId: state.company.companyId,
                                members: state.members,
                                careerService: _careerService,
                                onSelect: (memberId) => setState(() => _selectedMemberId = memberId),
                                onSave: _saveAppraisal,
                              )
                            : Row(
                                children: [
                                  SizedBox(
                                    width: math.min(430, math.max(340, constraints.maxWidth * .30)),
                                    child: _AppraisalEmployeeList(
                                      records: records,
                                      selectedMemberId: selected!.member.uid,
                                      onSelect: (memberId) => setState(() => _selectedMemberId = memberId),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _AppraisalDetailPanel(
                                      key: ValueKey(selected!.member.uid),
                                      record: selected,
                                      actor: actor,
                                      companyId: state.company.companyId,
                                      members: state.members,
                                      careerService: _careerService,
                                      onSave: _saveAppraisal,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyAppraisalCsv(BuildContext context, List<_AppraisalRecord> records) async {
    final rows = <String>[
      'Employee,Role,Department,Discipline,Grade,Assigned,Completed,Late,Completion,Appraisal Score,Previous Score,Status,Template,Period,Notes',
    ];
    for (final record in records) {
      rows.add(<String>[
        _csv(record.member.displayName),
        _csv(record.member.role.label),
        _csv(record.member.effectiveDepartment),
        _csv(record.member.effectiveIndustryDiscipline),
        _csv(record.member.grade),
        '${record.assignedCount}',
        '${record.completedCount}',
        '${record.lateCount}',
        '${record.completionRate}%',
        '${record.score}',
        '${record.member.previousAppraisalScore}',
        _csv(record.statusLabel),
        _csv(AppraisalTemplateCatalog.forMember(record.member).name),
        _csv(record.member.appraisalPeriod),
        _csv(record.notes),
      ].join(','));
    }
    final csv = rows.join('\n');
    final downloaded = await downloadTextFile(
      fileName: 'appraisals_${_monthId(DateTime.now())}.csv',
      content: csv,
      mimeType: 'text/csv;charset=utf-8',
    );
    if (!downloaded) {
      await Clipboard.setData(ClipboardData(text: csv));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(downloaded ? 'Appraisal CSV downloaded.' : 'Appraisal CSV copied to clipboard.')),
    );
  }

  void _saveAppraisal(_AppraisalSaveRequest request) {
    ref.read(workspaceProvider.notifier).updateMemberAppraisalDetails(
          memberId: request.record.member.uid,
          score: request.score,
          notes: request.notes,
          status: request.status,
          templateId: request.templateId,
          competencyScores: request.competencyScores,
          selfReview: request.selfReview,
          managerReview: request.managerReview,
          peerReview: request.peerReview,
          appraisalPeriod: request.appraisalPeriod,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${request.record.member.displayName} appraisal saved for ${request.appraisalPeriod}.')),
    );
  }
}

class _AppraisalToolbar extends StatelessWidget {
  const _AppraisalToolbar({
    required this.queryController,
    required this.canEdit,
    required this.roleFilter,
    required this.onQueryChanged,
    required this.onRoleChanged,
    required this.onClear,
    required this.onExport,
  });

  final TextEditingController queryController;
  final bool canEdit;
  final UserRole? roleFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<UserRole?> onRoleChanged;
  final VoidCallback onClear;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final searchWidth = width < 260 ? width : math.min(width < 760 ? width : 390.0, width);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDCE6F3)),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x120F172A), blurRadius: 20, offset: Offset(0, 12))],
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                height: 44,
                child: TextField(
                  controller: queryController,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search employee, department, discipline or grade',
                    prefixIcon: const Icon(Icons.manage_search_rounded, size: 21),
                    suffixIcon: queryController.text.trim().isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClear),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4)),
                  ),
                ),
              ),
              PopupMenuButton<UserRole?>(
                tooltip: 'Role filter',
                onSelected: onRoleChanged,
                itemBuilder: (context) => <PopupMenuEntry<UserRole?>>[
                  const PopupMenuItem<UserRole?>(value: null, child: Text('All roles')),
                  ...UserRole.values.map((role) => PopupMenuItem<UserRole?>(value: role, child: Text(role.label))),
                ],
                child: _ToolbarChip(icon: Icons.badge_rounded, label: roleFilter?.label ?? 'All roles'),
              ),
              _ToolbarButton(
                icon: canEdit ? Icons.verified_user_rounded : Icons.visibility_rounded,
                label: canEdit ? 'Appraisal editor' : 'View only',
                active: canEdit,
                onTap: () {},
              ),
              _ToolbarButton(icon: Icons.tune_rounded, label: 'Clear', active: false, onTap: onClear),
              _ToolbarButton(icon: Icons.file_download_outlined, label: 'Export CSV', active: false, onTap: onExport),
            ],
          ),
        );
      },
    );
  }
}

class _AppraisalSummaryStrip extends StatelessWidget {
  const _AppraisalSummaryStrip({required this.records, required this.actor});

  final List<_AppraisalRecord> records;
  final Member actor;

  @override
  Widget build(BuildContext context) {
    final average = records.isEmpty ? 0 : (records.fold<int>(0, (sum, record) => sum + record.score) / records.length).round();
    final promotionReady = records.where((record) => record.member.appraisalStatus == 'promotionReady').length;
    final improvement = records.where((record) => record.member.appraisalStatus == 'improvementPlan').length;
    final reviewed = records.where((record) => record.member.appraisalStatus != 'notReviewed').length;
    final cards = <Widget>[
      _AccessCard(actor: actor),
      _SummaryCard(icon: Icons.groups_rounded, label: 'Employees', value: '${records.length}', color: const Color(0xFF2563EB)),
      _SummaryCard(icon: Icons.insights_rounded, label: 'Average score', value: '$average%', color: const Color(0xFF7C3AED)),
      _SummaryCard(icon: Icons.workspace_premium_rounded, label: 'Promotion ready', value: '$promotionReady', color: const Color(0xFF16A34A)),
      _SummaryCard(icon: Icons.trending_down_rounded, label: 'Improvement plans', value: '$improvement', color: const Color(0xFFF97316)),
      _SummaryCard(icon: Icons.fact_check_rounded, label: 'Reviewed', value: '$reviewed/${records.length}', color: const Color(0xFF0F766E)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth >= 1150) {
          return Row(
            children: [
              Expanded(flex: 2, child: cards.first),
              for (final card in cards.skip(1)) ...<Widget>[const SizedBox(width: 10), Expanded(child: card)],
            ],
          );
        }
        final columns = maxWidth < 620 ? 1 : maxWidth < 900 ? 2 : 3;
        final width = (maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      },
    );
  }
}

class _CompactAppraisalView extends StatelessWidget {
  const _CompactAppraisalView({
    required this.records,
    required this.selected,
    required this.actor,
    required this.companyId,
    required this.members,
    required this.careerService,
    required this.onSelect,
    required this.onSave,
  });

  final List<_AppraisalRecord> records;
  final _AppraisalRecord selected;
  final Member actor;
  final String companyId;
  final List<Member> members;
  final CareerProgressionService careerService;
  final ValueChanged<String> onSelect;
  final ValueChanged<_AppraisalSaveRequest> onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: selected.member.uid,
          decoration: const InputDecoration(labelText: 'Employee', filled: true, fillColor: Colors.white, border: OutlineInputBorder()),
          items: records
              .map((record) => DropdownMenuItem<String>(value: record.member.uid, child: Text('${record.member.displayName} • ${record.member.role.label}')))
              .toList(),
          onChanged: (value) {
            if (value != null) onSelect(value);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _AppraisalDetailPanel(
            key: ValueKey(selected.member.uid),
            record: selected,
            actor: actor,
            companyId: companyId,
            members: members,
            careerService: careerService,
            onSave: onSave,
          ),
        ),
      ],
    );
  }
}

class _AppraisalEmployeeList extends StatelessWidget {
  const _AppraisalEmployeeList({required this.records, required this.selectedMemberId, required this.onSelect});

  final List<_AppraisalRecord> records;
  final String selectedMemberId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F3)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x100F172A), blurRadius: 18, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final record = records[index];
          return _EmployeeTile(
            record: record,
            selected: record.member.uid == selectedMemberId,
            onTap: () => onSelect(record.member.uid),
          );
        },
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({required this.record, required this.selected, required this.onTap});

  final _AppraisalRecord record;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(record.score);
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: record.member.role.color.withOpacity(.13),
                child: Text(_initial(record.member.displayName), style: TextStyle(color: record.member.role.color, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.member.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(
                      _memberIdentityLine(record.member),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 7),
                    LinearProgressIndicator(value: record.score / 100, minHeight: 5, borderRadius: BorderRadius.circular(999), color: color, backgroundColor: const Color(0xFFE2E8F0)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ScorePill(score: record.score, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AppraisalSection { overview, competencies, career, history }

class _AppraisalDetailPanel extends StatefulWidget {
  const _AppraisalDetailPanel({
    super.key,
    required this.record,
    required this.actor,
    required this.companyId,
    required this.members,
    required this.careerService,
    required this.onSave,
  });

  final _AppraisalRecord record;
  final Member actor;
  final String companyId;
  final List<Member> members;
  final CareerProgressionService careerService;
  final ValueChanged<_AppraisalSaveRequest> onSave;

  @override
  State<_AppraisalDetailPanel> createState() => _AppraisalDetailPanelState();
}

class _AppraisalDetailPanelState extends State<_AppraisalDetailPanel> {
  late int _score;
  late String _status;
  late String _templateId;
  late Map<String, int> _competencyScores;
  late String _appraisalPeriod;
  late TextEditingController _notesController;
  late TextEditingController _selfReviewController;
  late TextEditingController _managerReviewController;
  late TextEditingController _peerReviewController;
  _AppraisalSection _section = _AppraisalSection.overview;

  bool get _canEdit => PermissionService.canEditAppraisal(widget.actor);
  bool get _canRecommend => PermissionService.canRecommendCareerAction(widget.actor);
  bool get _canApprove => PermissionService.canApproveCareerAction(widget.actor);
  bool get _canReview => PermissionService.canReviewCareerAction(widget.actor);

  @override
  void initState() {
    super.initState();
    _resetFromRecord();
  }

  void _resetFromRecord() {
    final member = widget.record.member;
    final template = AppraisalTemplateCatalog.forMember(member);
    _score = widget.record.score;
    _status = widget.record.status;
    _templateId = member.appraisalTemplateId.trim().isEmpty ? template.id : member.appraisalTemplateId;
    _competencyScores = <String, int>{
      for (final competency in AppraisalTemplateCatalog.byId(_templateId).competencies)
        competency.id: member.appraisalCompetencyScores[competency.id] ?? widget.record.computedScore.clamp(45, 95).toInt(),
    };
    _appraisalPeriod = member.appraisalPeriod.trim().isEmpty ? _monthId(DateTime.now()) : member.appraisalPeriod;
    _notesController = TextEditingController(text: member.appraisalNotes);
    _selfReviewController = TextEditingController(text: member.appraisalSelfReview);
    _managerReviewController = TextEditingController(text: member.appraisalManagerReview);
    _peerReviewController = TextEditingController(text: member.appraisalPeerReview);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _selfReviewController.dispose();
    _managerReviewController.dispose();
    _peerReviewController.dispose();
    super.dispose();
  }

  int get _competencyAverage {
    final template = AppraisalTemplateCatalog.byId(_templateId);
    if (template.competencies.isEmpty) return 0;
    var weighted = 0.0;
    var totalWeight = 0.0;
    for (final competency in template.competencies) {
      weighted += (_competencyScores[competency.id] ?? 0) * competency.weight;
      totalWeight += competency.weight;
    }
    return totalWeight == 0 ? 0 : (weighted / totalWeight).round().clamp(0, 100).toInt();
  }

  int get _recommendedScore => ((widget.record.computedScore * .55) + (_competencyAverage * .45)).round().clamp(0, 100).toInt();

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final color = _scoreColor(_score);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F3)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x100F172A), blurRadius: 18, offset: Offset(0, 10))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              children: [
                _EmployeeHero(record: record, score: _score, color: color),
                const SizedBox(height: 14),
                _SectionSelector(section: _section, onChanged: (section) => setState(() => _section = section)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: switch (_section) {
                _AppraisalSection.overview => _buildOverview(record, color),
                _AppraisalSection.competencies => _buildCompetencies(record),
                _AppraisalSection.career => _buildCareer(record),
                _AppraisalSection.history => _buildHistory(record),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(_AppraisalRecord record, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PerformanceMetrics(record: record),
        const SizedBox(height: 18),
        _InsightBanner(
          icon: Icons.auto_awesome_rounded,
          title: 'Evidence-based recommendation: $_recommendedScore%',
          message: 'Calculated from monthly task delivery (55%) and weighted ${AppraisalTemplateCatalog.byId(_templateId).name} competencies (45%). A manager still owns the final decision.',
          color: const Color(0xFF2563EB),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Text('Final appraisal score', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155)))),
            TextButton.icon(
              onPressed: _canEdit ? () => setState(() => _score = _recommendedScore) : null,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
              label: const Text('Use recommendation'),
            ),
          ],
        ),
        Slider(
          value: _score.toDouble(),
          min: 0,
          max: 100,
          divisions: 100,
          label: '$_score%',
          activeColor: color,
          onChanged: _canEdit ? (value) => setState(() => _score = value.round()) : null,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;
            final fields = <Widget>[
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Appraisal status', border: OutlineInputBorder()),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'notReviewed', child: Text('Not reviewed')),
                  DropdownMenuItem(value: 'reviewed', child: Text('Reviewed')),
                  DropdownMenuItem(value: 'promotionReady', child: Text('Promotion ready')),
                  DropdownMenuItem(value: 'improvementPlan', child: Text('Improvement plan')),
                ],
                onChanged: _canEdit ? (value) => setState(() => _status = value ?? _status) : null,
              ),
              TextFormField(
                initialValue: _appraisalPeriod,
                readOnly: !_canEdit,
                decoration: const InputDecoration(labelText: 'Appraisal period (YYYY-MM)', border: OutlineInputBorder()),
                onChanged: (value) => _appraisalPeriod = value.trim(),
              ),
            ];
            return compact
                ? Column(children: <Widget>[fields[0], const SizedBox(height: 12), fields[1]])
                : Row(children: <Widget>[Expanded(child: fields[0]), const SizedBox(width: 12), Expanded(child: fields[1])]);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _managerReviewController,
          minLines: 3,
          maxLines: 6,
          readOnly: !_canEdit,
          decoration: const InputDecoration(labelText: 'Manager review', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _selfReviewController,
          minLines: 3,
          maxLines: 6,
          readOnly: !_canEdit,
          decoration: const InputDecoration(labelText: 'Employee self-review', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _peerReviewController,
          minLines: 2,
          maxLines: 5,
          readOnly: !_canEdit,
          decoration: const InputDecoration(labelText: 'Peer / 360° feedback', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          minLines: 3,
          maxLines: 6,
          readOnly: !_canEdit,
          decoration: const InputDecoration(labelText: 'Development notes and next actions', alignLabelWithHint: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (record.member.appraisalUpdatedAt != null)
              Text('Last updated ${DateText.compact(record.member.appraisalUpdatedAt!)}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            if (_canEdit)
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.cloud_done_rounded), label: const Text('Save appraisal'))
            else
              const _ViewOnlyNotice(),
          ],
        ),
      ],
    );
  }

  Widget _buildCompetencies(_AppraisalRecord record) {
    final template = AppraisalTemplateCatalog.byId(_templateId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _templateId,
                    decoration: const InputDecoration(labelText: 'Industry / discipline template', border: OutlineInputBorder()),
                    items: AppraisalTemplateCatalog.templates
                        .map((item) => DropdownMenuItem<String>(value: item.id, child: Text('${item.name} • ${item.industry}')))
                        .toList(),
                    onChanged: _canEdit
                        ? (value) {
                            if (value == null) return;
                            final next = AppraisalTemplateCatalog.byId(value);
                            setState(() {
                              _templateId = value;
                              _competencyScores = <String, int>{
                                for (final competency in next.competencies)
                                  competency.id: record.member.appraisalCompetencyScores[competency.id] ?? _recommendedScore.clamp(45, 95).toInt(),
                              };
                            });
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                _ScorePill(score: _competencyAverage, color: _scoreColor(_competencyAverage), large: true),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _InsightBanner(
          icon: Icons.domain_rounded,
          title: '${template.name} competency model',
          message: 'Works for Civil, Mechanical, Electrical, IT, QA, HR, Sales, Finance, and general operations. Scores are weighted and saved per employee.',
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(height: 14),
        for (final competency in template.competencies) ...<Widget>[
          _CompetencyCard(
            competency: competency,
            value: _competencyScores[competency.id] ?? 0,
            enabled: _canEdit,
            onChanged: (value) => setState(() => _competencyScores[competency.id] = value),
          ),
          const SizedBox(height: 10),
        ],
        if (_canEdit)
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: const Text('Save competency appraisal'))),
      ],
    );
  }

  Widget _buildCareer(_AppraisalRecord record) {
    final member = record.member;
    return StreamBuilder<List<EmploymentAction>>(
      stream: widget.careerService.watchActions(
        companyId: widget.companyId,
        employeeId: member.uid,
      ),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
        final actions = snapshot.data ?? const <EmploymentAction>[];
        final blockingAction = _firstBlockingEmploymentAction(actions);
        final workflowVerified = !isLoading && !snapshot.hasError;
        final employeeActive = member.status.trim().toLowerCase() == 'active';
        final gradeConfigured = member.grade.trim().isNotEmpty;
        final levelConfigured = member.employmentLevel.trim().isNotEmpty;
        final promotionProfileReady = gradeConfigured && levelConfigured;

        final canStartBase = _canRecommend &&
            workflowVerified &&
            employeeActive &&
            blockingAction == null;
        final canRecommendPromotionOrDemotion = canStartBase && promotionProfileReady;
        final canRecommendTransfer = canStartBase;

        String baseDisabledReason() {
          if (!_canRecommend) {
            return 'Your role cannot create employment-action recommendations.';
          }
          if (isLoading) {
            return 'Checking the current employment-action workflow.';
          }
          if (snapshot.hasError) {
            return 'The workflow state could not be verified. Refresh and try again.';
          }
          if (!employeeActive) {
            return 'Career actions can only be created for an active employee.';
          }
          if (blockingAction != null) {
            return 'Complete the existing ${blockingAction.actionType.label.toLowerCase()} workflow (${blockingAction.status.label.toLowerCase()}) first.';
          }
          return '';
        }

        final baseReason = baseDisabledReason();
        final promotionReason = baseReason.isNotEmpty
            ? baseReason
            : !promotionProfileReady
                ? 'Configure the employee grade and employment level before creating a promotion or demotion recommendation.'
                : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CareerProfileCard(member: member),
            if (!promotionProfileReady) ...<Widget>[
              const SizedBox(height: 12),
              const _InsightBanner(
                icon: Icons.manage_accounts_rounded,
                title: 'Career profile setup required',
                message: 'Grade and employment level are not configured. Update the employee profile before creating a promotion or demotion recommendation. Transfer and role-change workflows remain available.',
                color: Color(0xFFF97316),
              ),
            ],
            if (blockingAction != null) ...<Widget>[
              const SizedBox(height: 12),
              _InsightBanner(
                icon: Icons.pending_actions_rounded,
                title: 'An employment action is already in progress',
                message: '${blockingAction.actionType.label} is currently ${blockingAction.status.label.toLowerCase()}. Finish, reject, cancel, or apply it before creating another recommendation.',
                color: const Color(0xFF7C3AED),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Tooltip(
                  message: canRecommendPromotionOrDemotion ? 'Create a promotion recommendation' : promotionReason,
                  child: FilledButton.icon(
                    onPressed: canRecommendPromotionOrDemotion
                        ? () => _openCareerAction(EmploymentActionType.promotion)
                        : null,
                    icon: const Icon(Icons.trending_up_rounded),
                    label: const Text('Recommend promotion'),
                  ),
                ),
                Tooltip(
                  message: canRecommendPromotionOrDemotion ? 'Create a demotion recommendation' : promotionReason,
                  child: OutlinedButton.icon(
                    onPressed: canRecommendPromotionOrDemotion
                        ? () => _openCareerAction(EmploymentActionType.demotion)
                        : null,
                    icon: const Icon(Icons.trending_down_rounded),
                    label: const Text('Recommend demotion'),
                  ),
                ),
                Tooltip(
                  message: canRecommendTransfer ? 'Create a transfer or role-change recommendation' : baseReason,
                  child: OutlinedButton.icon(
                    onPressed: canRecommendTransfer
                        ? () => _openCareerAction(EmploymentActionType.departmentTransfer)
                        : null,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Transfer / role change'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Employment action workflow', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (snapshot.hasError)
              _InsightBanner(
                icon: Icons.cloud_off_rounded,
                title: 'Career action history could not be loaded',
                message: '${snapshot.error}',
                color: const Color(0xFFEF4444),
              )
            else if (actions.isEmpty)
              const _InsightBanner(
                icon: Icons.history_toggle_off_rounded,
                title: 'No employment action has been created',
                message: 'Create a recommendation to start the audited HR review, approval, rejection, scheduling, and employment-history workflow.',
                color: Color(0xFF64748B),
              )
            else
              Column(
                children: actions
                    .map(
                      (action) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EmploymentActionCard(
                          action: action,
                          canReview: _canReview,
                          canApprove: _canApprove,
                          onReview: () => _reviewAction(action),
                          onApprove: () => _approveAction(action),
                          onReject: () => _rejectAction(action),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHistory(_AppraisalRecord record) {
    final member = record.member;
    final delta = member.previousAppraisalScore == 0 ? 0 : member.appraisalScore - member.previousAppraisalScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 650 ? 2 : 4;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _SmallMetric(width: width, label: 'Current score', value: '${member.appraisalScore}%', color: const Color(0xFF2563EB)),
                _SmallMetric(width: width, label: 'Previous score', value: '${member.previousAppraisalScore}%', color: const Color(0xFF7C3AED)),
                _SmallMetric(width: width, label: 'Score change', value: '${delta >= 0 ? '+' : ''}$delta', color: delta >= 0 ? const Color(0xFF16A34A) : const Color(0xFFEF4444)),
                _SmallMetric(width: width, label: 'Review period', value: member.appraisalPeriod.isEmpty ? '-' : member.appraisalPeriod, color: const Color(0xFFF97316)),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _AppraisalTrendCard(current: member.appraisalScore, previous: member.previousAppraisalScore, computed: record.computedScore, competency: _competencyAverage),
        const SizedBox(height: 14),
        _InsightBanner(
          icon: Icons.lock_clock_rounded,
          title: 'Monthly evidence and immutable career history',
          message: 'Finalized monthly analytics preserve project, task, workload, appraisal, promotion, and demotion metrics. Approved employment actions are also copied to the employee employment-history subcollection.',
          color: const Color(0xFF0F766E),
        ),
      ],
    );
  }

  void _save() {
    final cleanPeriod = RegExp(r'^\d{4}-\d{2}$').hasMatch(_appraisalPeriod.trim()) ? _appraisalPeriod.trim() : _monthId(DateTime.now());
    widget.onSave(_AppraisalSaveRequest(
      record: widget.record,
      score: _score,
      notes: _notesController.text,
      status: _status,
      templateId: _templateId,
      competencyScores: Map<String, int>.unmodifiable(_competencyScores),
      selfReview: _selfReviewController.text,
      managerReview: _managerReviewController.text,
      peerReview: _peerReviewController.text,
      appraisalPeriod: cleanPeriod,
    ));
  }

  Future<void> _openCareerAction(EmploymentActionType initialType) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _CareerActionDialog(
        companyId: widget.companyId,
        employee: widget.record.member,
        actor: widget.actor,
        members: widget.members,
        service: widget.careerService,
        initialType: initialType,
        appraisalPeriod: _appraisalPeriod,
        appraisalScore: _score,
      ),
    );
    if (!mounted || created != true) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employment action recommendation created.')));
  }

  Future<void> _reviewAction(EmploymentAction action) async {
    final comments = await _promptText(title: 'HR review comments', hint: 'Review notes, checks, or conditions');
    if (comments == null) return;
    await _guarded(() => widget.careerService.markUnderReview(companyId: widget.companyId, action: action, actor: widget.actor, hrComments: comments), 'Action moved to HR review.');
  }

  Future<void> _approveAction(EmploymentAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Approve ${action.actionType.label}?'),
        content: const Text('This updates the employee role/profile fields, writes immutable employment history, creates an audit log, and notifies the employee.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guarded(() => widget.careerService.approve(companyId: widget.companyId, action: action, actor: widget.actor), '${action.actionType.label} approved.');
  }

  Future<void> _rejectAction(EmploymentAction action) async {
    final reason = await _promptText(title: 'Reject ${action.actionType.label}', hint: 'Required rejection reason');
    if (reason == null) return;
    await _guarded(() => widget.careerService.reject(companyId: widget.companyId, action: action, actor: widget.actor, reason: reason), 'Employment action rejected.');
  }

  Future<String?> _promptText({required String title, required String hint}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, minLines: 3, maxLines: 6, decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.trim().isEmpty ? null : result.trim();
  }

  Future<void> _guarded(Future<void> Function() action, String successMessage) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _CareerActionDialog extends StatefulWidget {
  const _CareerActionDialog({
    required this.companyId,
    required this.employee,
    required this.actor,
    required this.members,
    required this.service,
    required this.initialType,
    required this.appraisalPeriod,
    required this.appraisalScore,
  });

  final String companyId;
  final Member employee;
  final Member actor;
  final List<Member> members;
  final CareerProgressionService service;
  final EmploymentActionType initialType;
  final String appraisalPeriod;
  final int appraisalScore;

  @override
  State<_CareerActionDialog> createState() => _CareerActionDialogState();
}

class _CareerActionDialogState extends State<_CareerActionDialog> {
  late EmploymentActionType _type = widget.initialType;
  UserRole? _proposedRole;
  DateTime? _effectiveDate;
  String? _managerId;
  bool _saving = false;
  late final TextEditingController _departmentController = TextEditingController(text: widget.employee.effectiveDepartment);
  late final TextEditingController _titleController = TextEditingController(text: widget.employee.effectiveJobTitle);
  late final TextEditingController _gradeController = TextEditingController(text: widget.employee.grade);
  late final TextEditingController _salaryBandController = TextEditingController(text: widget.employee.salaryBand);
  late final TextEditingController _reasonController = TextEditingController();
  late final TextEditingController _recommendationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_type == EmploymentActionType.promotion) {
      _proposedRole = widget.employee.role == UserRole.employee ? UserRole.teamLead : null;
    } else if (_type == EmploymentActionType.demotion) {
      _proposedRole = widget.employee.role == UserRole.teamLead || widget.employee.role == UserRole.projectManager ? UserRole.employee : null;
    }
  }

  @override
  void dispose() {
    _departmentController.dispose();
    _titleController.dispose();
    _gradeController.dispose();
    _salaryBandController.dispose();
    _reasonController.dispose();
    _recommendationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Employment action recommendation'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InsightBanner(
                icon: Icons.verified_user_rounded,
                title: '${widget.employee.displayName} • ${widget.employee.effectiveJobTitle}',
                message: 'Recommendations do not change employee access until HR/Admin approval. All transitions are audited.',
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<EmploymentActionType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Action type', border: OutlineInputBorder()),
                items: EmploymentActionType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.label))).toList(),
                onChanged: _saving ? null : (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole?>(
                value: _proposedRole,
                decoration: const InputDecoration(labelText: 'Proposed portal role (optional)', border: OutlineInputBorder()),
                items: <DropdownMenuItem<UserRole?>>[
                  const DropdownMenuItem<UserRole?>(value: null, child: Text('Keep current role')),
                  ...UserRole.values
                      .where((role) => role != UserRole.superAdmin)
                      .map((role) => DropdownMenuItem<UserRole?>(value: role, child: Text(role.label))),
                ],
                onChanged: _saving ? null : (value) => setState(() => _proposedRole = value),
              ),
              const SizedBox(height: 12),
              _ResponsiveFieldRow(children: [
                TextField(controller: _departmentController, decoration: const InputDecoration(labelText: 'Proposed department', border: OutlineInputBorder())),
                TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Proposed job title', border: OutlineInputBorder())),
              ]),
              const SizedBox(height: 12),
              _ResponsiveFieldRow(children: [
                TextField(controller: _gradeController, decoration: const InputDecoration(labelText: 'Proposed grade', border: OutlineInputBorder())),
                TextField(controller: _salaryBandController, decoration: const InputDecoration(labelText: 'Proposed salary band', border: OutlineInputBorder())),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _managerId,
                decoration: const InputDecoration(labelText: 'Proposed reporting manager (optional)', border: OutlineInputBorder()),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(value: null, child: Text('Keep current manager')),
                  ...widget.members
                      .where((member) => member.uid != widget.employee.uid && member.status == 'active')
                      .map((member) => DropdownMenuItem<String?>(value: member.uid, child: Text('${member.displayName} • ${member.role.label}'))),
                ],
                onChanged: _saving ? null : (value) => setState(() => _managerId = value),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _saving
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                          initialDate: _effectiveDate ?? DateTime.now().add(const Duration(days: 7)),
                        );
                        if (picked != null) setState(() => _effectiveDate = picked);
                      },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Effective date', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month_rounded)),
                  child: Text(_effectiveDate == null ? 'Select date' : DateText.compact(_effectiveDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _reasonController, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Business reason', alignLabelWithHint: true, border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _recommendationController, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Manager recommendation and evidence', alignLabelWithHint: true, border: OutlineInputBorder())),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
          label: const Text('Create recommendation'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.createRecommendation(
        companyId: widget.companyId,
        employee: widget.employee,
        actor: widget.actor,
        actionType: _type,
        proposedRole: _proposedRole,
        proposedDepartment: _departmentController.text,
        proposedJobTitle: _titleController.text,
        proposedGrade: _gradeController.text,
        proposedSalaryBand: _salaryBandController.text,
        proposedReportingManagerId: _managerId,
        effectiveDate: _effectiveDate,
        reason: _reasonController.text,
        managerRecommendation: _recommendationController.text,
        appraisalPeriod: widget.appraisalPeriod,
        appraisalScore: widget.appraisalScore,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: <Widget>[children.first, const SizedBox(height: 12), children.last]);
        }
        return Row(children: <Widget>[Expanded(child: children.first), const SizedBox(width: 12), Expanded(child: children.last)]);
      },
    );
  }
}

class _EmploymentActionCard extends StatelessWidget {
  const _EmploymentActionCard({required this.action, required this.canReview, required this.canApprove, required this.onReview, required this.onApprove, required this.onReject});

  final EmploymentAction action;
  final bool canReview;
  final bool canApprove;
  final VoidCallback onReview;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final color = switch (action.status) {
      EmploymentActionStatus.approved => const Color(0xFF16A34A),
      EmploymentActionStatus.scheduled => const Color(0xFF0F9F91),
      EmploymentActionStatus.rejected => const Color(0xFFEF4444),
      EmploymentActionStatus.error => const Color(0xFFDC2626),
      EmploymentActionStatus.underReview => const Color(0xFF7C3AED),
      _ => const Color(0xFF2563EB),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(.055), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.20))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(label: action.actionType.label, color: color),
              _StatusPill(label: action.status.label, color: color),
              if (action.effectiveDate != null) _StatusPill(label: 'Effective ${DateText.compact(action.effectiveDate)}', color: const Color(0xFF0F766E)),
            ],
          ),
          const SizedBox(height: 10),
          Text(action.reason, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF334155))),
          if (action.managerRecommendation.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(action.managerRecommendation, style: const TextStyle(color: Color(0xFF64748B))),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (action.proposedRole != null) _DetailChip(icon: Icons.security_rounded, text: 'Role: ${action.proposedRole!.label}'),
              if ((action.proposedDepartment ?? '').isNotEmpty) _DetailChip(icon: Icons.account_tree_rounded, text: action.proposedDepartment!),
              if ((action.proposedJobTitle ?? '').isNotEmpty) _DetailChip(icon: Icons.badge_rounded, text: action.proposedJobTitle!),
              if ((action.proposedGrade ?? '').isNotEmpty) _DetailChip(icon: Icons.stairs_rounded, text: 'Grade ${action.proposedGrade}'),
            ],
          ),
          if (!action.isTerminal && (canReview || canApprove)) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canReview && action.status != EmploymentActionStatus.underReview)
                  OutlinedButton.icon(onPressed: onReview, icon: const Icon(Icons.rate_review_rounded), label: const Text('Review')),
                if (canApprove)
                  FilledButton.icon(onPressed: onApprove, icon: const Icon(Icons.verified_rounded), label: const Text('Approve')),
                if (canApprove)
                  TextButton.icon(onPressed: onReject, icon: const Icon(Icons.block_rounded), label: const Text('Reject')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeeHero extends StatelessWidget {
  const _EmployeeHero({required this.record, required this.score, required this.color});
  final _AppraisalRecord record;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final member = record.member;
    final identityParts = _memberIdentityParts(member);
    final primaryIdentity = identityParts.take(2).join(' • ');
    final secondaryIdentity = _uniqueDisplayValues(<String?>[
      ...identityParts.skip(2),
      member.grade.trim().isEmpty ? null : 'Grade ${member.grade.trim()}',
      member.appraisalPeriod.trim().isEmpty ? null : 'Period ${member.appraisalPeriod.trim()}',
      record.statusLabel,
    ]).join(' • ');

    return Wrap(
      spacing: 14,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: member.role.color.withOpacity(.15),
          child: Text(
            _initial(member.displayName),
            style: TextStyle(color: member.role.color, fontWeight: FontWeight.w900, fontSize: 22),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                primaryIdentity.isEmpty ? member.role.label : primaryIdentity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Text(
                secondaryIdentity.isEmpty ? record.statusLabel : secondaryIdentity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        Tooltip(
          message: '${record.statusLabel} appraisal score${member.appraisalPeriod.trim().isEmpty ? '' : ' for ${member.appraisalPeriod.trim()}'}',
          child: _ScorePill(score: score, color: color, large: true),
        ),
      ],
    );
  }
}

class _SectionSelector extends StatelessWidget {
  const _SectionSelector({required this.section, required this.onChanged});
  final _AppraisalSection section;
  final ValueChanged<_AppraisalSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(_AppraisalSection, IconData, String)>[
      (_AppraisalSection.overview, Icons.dashboard_customize_rounded, 'Overview'),
      (_AppraisalSection.competencies, Icons.radar_rounded, 'Competencies'),
      (_AppraisalSection.career, Icons.trending_up_rounded, 'Career actions'),
      (_AppraisalSection.history, Icons.history_rounded, 'History'),
    ];
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = item.$1 == section;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selected,
                onSelected: (_) => onChanged(item.$1),
                avatar: Icon(item.$2, size: 17, color: selected ? const Color(0xFF2563EB) : const Color(0xFF64748B)),
                label: Text(item.$3),
                labelStyle: TextStyle(fontWeight: FontWeight.w900, color: selected ? const Color(0xFF2563EB) : const Color(0xFF475569)),
                selectedColor: const Color(0xFFEFF6FF),
                backgroundColor: const Color(0xFFF8FAFC),
                side: BorderSide(color: selected ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PerformanceMetrics extends StatelessWidget {
  const _PerformanceMetrics({required this.record});
  final _AppraisalRecord record;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 640 ? 2 : 4;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SmallMetric(width: width, label: 'Assigned', value: '${record.assignedCount}', color: const Color(0xFF2563EB)),
            _SmallMetric(width: width, label: 'Completed', value: '${record.completedCount}', color: const Color(0xFF16A34A)),
            _SmallMetric(width: width, label: 'Late', value: '${record.lateCount}', color: const Color(0xFFEF4444)),
            _SmallMetric(width: width, label: 'Completion', value: '${record.completionRate}%', color: const Color(0xFF7C3AED)),
          ],
        );
      },
    );
  }
}

class _CompetencyCard extends StatelessWidget {
  const _CompetencyCard({required this.competency, required this.value, required this.enabled, required this.onChanged});
  final AppraisalCompetency competency;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(.045), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.16))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(competency.label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E293B)))),
              _ScorePill(score: value, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text('${competency.description} • Weight ${competency.weight.toStringAsFixed(1)}×', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          Slider(value: value.toDouble(), min: 0, max: 100, divisions: 20, label: '$value%', activeColor: color, onChanged: enabled ? (next) => onChanged(next.round()) : null),
        ],
      ),
    );
  }
}

class _CareerProfileCard extends StatelessWidget {
  const _CareerProfileCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final title = _firstDisplayValue(
      <String?>[member.effectiveJobTitle, member.role.label],
      fallback: 'Role not configured',
    );
    final subtitle = _uniqueDisplayValues(
      <String?>[
        member.role.label,
        _memberDepartmentForDisplay(member),
        member.effectiveIndustryDiscipline,
      ],
      excludedValues: <String>[title],
    ).join(' • ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: <Color>[Color(0xFF0F172A), Color(0xFF1D4ED8)]),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x332563EB), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(Icons.military_tech_rounded, color: Colors.white),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.isEmpty ? 'Career profile details' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFDCEBFF), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          _DarkMetric(label: 'Grade', value: _configuredValue(member.grade)),
          _DarkMetric(label: 'Level', value: _configuredValue(member.employmentLevel)),
          _DarkMetric(label: 'Salary band', value: _configuredValue(member.salaryBand)),
        ],
      ),
    );
  }
}

class _AppraisalTrendCard extends StatelessWidget {
  const _AppraisalTrendCard({required this.current, required this.previous, required this.computed, required this.competency});
  final int current;
  final int previous;
  final int computed;
  final int competency;

  @override
  Widget build(BuildContext context) {
    final values = <(String, int, Color)>[
      ('Previous', previous, const Color(0xFF94A3B8)),
      ('Task evidence', computed, const Color(0xFF2563EB)),
      ('Competencies', competency, const Color(0xFF7C3AED)),
      ('Final', current, const Color(0xFF16A34A)),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance evidence comparison', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          for (final item in values) ...<Widget>[
            Row(children: [SizedBox(width: 105, child: Text(item.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF475569)))), Expanded(child: LinearProgressIndicator(value: item.$2 / 100, minHeight: 10, borderRadius: BorderRadius.circular(999), color: item.$3, backgroundColor: const Color(0xFFE2E8F0))), const SizedBox(width: 10), SizedBox(width: 40, child: Text('${item.$2}%', style: const TextStyle(fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.actor});
  final Member actor;

  @override
  Widget build(BuildContext context) {
    final canEdit = PermissionService.canEditAppraisal(actor);
    final color = canEdit ? const Color(0xFF15803D) : const Color(0xFF2563EB);
    return _CardShell(
      child: Row(
        children: [
          CircleAvatar(radius: 20, backgroundColor: color.withOpacity(.10), child: Icon(canEdit ? Icons.edit_calendar_rounded : Icons.visibility_rounded, color: color, size: 20)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(canEdit ? 'Appraisal & career access' : 'View-only appraisal', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                Text('${actor.displayName} • ${actor.role.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => _CardShell(
        child: Row(
          children: [
            CircleAvatar(radius: 19, backgroundColor: color.withOpacity(.10), child: Icon(icon, color: color, size: 19)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 11))])),
          ],
        ),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(height: 72, padding: const EdgeInsets.symmetric(horizontal: 13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDCE6F3))), child: child);
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.width, required this.label, required this.value, required this.color});
  final double width;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.16))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 3), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 11))]),
        ),
      );
}

class _InsightBanner extends StatelessWidget {
  const _InsightBanner({required this.icon, required this.title, required this.message, required this.color});
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.18))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 19, backgroundColor: color.withOpacity(.12), child: Icon(icon, color: color, size: 19)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(message, style: const TextStyle(color: Color(0xFF475569), height: 1.35))])),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 13), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFE2E8F0))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: const Color(0xFF334155)), const SizedBox(width: 8), Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155)))]));
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(13), border: Border.all(color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: active ? const Color(0xFF2563EB) : const Color(0xFF334155)), const SizedBox(width: 7), Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: active ? const Color(0xFF2563EB) : const Color(0xFF334155)))])),
      );
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.color, this.large = false});
  final int score;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 9 : 6), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.22))), child: Text('$score%', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: large ? 16 : 12)));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.18))), child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)));
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFE2E8F0))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: const Color(0xFF64748B)), const SizedBox(width: 5), Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w800))]));
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 92, maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _ViewOnlyNotice extends StatelessWidget {
  const _ViewOnlyNotice();

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFBFDBFE))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF2563EB)), SizedBox(width: 7), Text('View only for this role', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900))]));
}

class _EmptyAppraisalState extends StatelessWidget {
  const _EmptyAppraisalState();

  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.workspace_premium_rounded, color: Color(0xFF94A3B8), size: 48), SizedBox(height: 12), Text('No appraisal records found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 6), Text('Employee appraisals appear after workspace data sync.') ]));
}

class _AppraisalRecord {
  const _AppraisalRecord({
    required this.member,
    required this.assignedCount,
    required this.completedCount,
    required this.lateCount,
    required this.completionRate,
    required this.computedScore,
    required this.score,
    required this.status,
    required this.notes,
  });

  final Member member;
  final int assignedCount;
  final int completedCount;
  final int lateCount;
  final int completionRate;
  final int computedScore;
  final int score;
  final String status;
  final String notes;

  String get statusLabel => switch (status) {
        'promotionReady' => 'Promotion ready',
        'improvementPlan' => 'Improvement plan',
        'reviewed' => 'Reviewed',
        _ => 'Not reviewed',
      };
}

class _AppraisalSaveRequest {
  const _AppraisalSaveRequest({
    required this.record,
    required this.score,
    required this.notes,
    required this.status,
    required this.templateId,
    required this.competencyScores,
    required this.selfReview,
    required this.managerReview,
    required this.peerReview,
    required this.appraisalPeriod,
  });

  final _AppraisalRecord record;
  final int score;
  final String notes;
  final String status;
  final String templateId;
  final Map<String, int> competencyScores;
  final String selfReview;
  final String managerReview;
  final String peerReview;
  final String appraisalPeriod;
}

List<_AppraisalRecord> _appraisalRecords(WorkspaceState state, {required bool canEdit}) {
  final members = canEdit ? state.activePortalMembers : <Member>[state.currentMember];
  final records = <_AppraisalRecord>[];
  for (final member in members.where((member) => member.role != UserRole.clientViewer)) {
    final assigned = state.tasks.where((task) => task.assignedToIds.contains(member.uid)).toList();
    final completed = assigned.where((task) => task.status == TaskStatus.completed).length;
    final late = assigned.where((task) => task.isOverdue).length;
    final completion = assigned.isEmpty ? 0 : ((completed / assigned.length) * 100).round();
    final computedScore = _computedScore(assignedCount: assigned.length, completedCount: completed, lateCount: late, completionRate: completion, available: member.available);
    final storedScore = member.appraisalScore.clamp(0, 100).toInt();
    final score = storedScore > 0 ? storedScore : computedScore;
    records.add(_AppraisalRecord(member: member, assignedCount: assigned.length, completedCount: completed, lateCount: late, completionRate: completion, computedScore: computedScore, score: score, status: member.appraisalStatus, notes: member.appraisalNotes));
  }
  records.sort((a, b) => b.score.compareTo(a.score));
  return records;
}

_AppraisalRecord _selectedRecord(List<_AppraisalRecord> records, String? memberId) {
  if (records.isEmpty) throw StateError('No appraisal record selected.');
  if (memberId != null) {
    for (final record in records) {
      if (record.member.uid == memberId) return record;
    }
  }
  return records.first;
}

int _computedScore({required int assignedCount, required int completedCount, required int lateCount, required int completionRate, required bool available}) {
  var score = 50 + (completionRate * .38).round();
  if (assignedCount > 0) score += 8;
  if (available) score += 4;
  score -= lateCount * 9;
  return score.clamp(0, 100).toInt();
}

Color _scoreColor(int score) {
  if (score >= 85) return const Color(0xFF16A34A);
  if (score >= 70) return const Color(0xFF2563EB);
  if (score >= 55) return const Color(0xFFF97316);
  return const Color(0xFFEF4444);
}

EmploymentAction? _firstBlockingEmploymentAction(List<EmploymentAction> actions) {
  for (final action in actions) {
    if (<EmploymentActionStatus>{
      EmploymentActionStatus.draft,
      EmploymentActionStatus.recommended,
      EmploymentActionStatus.underReview,
      EmploymentActionStatus.scheduled,
    }.contains(action.status)) {
      return action;
    }
  }
  return null;
}

List<String> _memberIdentityParts(Member member) {
  return _uniqueDisplayValues(<String?>[
    member.effectiveJobTitle,
    _memberDepartmentForDisplay(member),
    member.effectiveIndustryDiscipline,
    member.role.label,
  ]);
}

String _memberDepartmentForDisplay(Member member) {
  final department = member.effectiveDepartment.trim();
  final normalizedDepartment = _normalizeDisplayValue(department);
  final normalizedTitle = _normalizeDisplayValue(member.effectiveJobTitle);
  final normalizedRole = _normalizeDisplayValue(member.role.label);
  if (normalizedDepartment.isEmpty ||
      normalizedDepartment == normalizedTitle ||
      normalizedDepartment == normalizedRole) {
    return member.role.department;
  }
  return department;
}

String _memberIdentityLine(Member member) {
  final values = _memberIdentityParts(member);
  return values.isEmpty ? member.role.label : values.take(2).join(' • ');
}

List<String> _uniqueDisplayValues(
  Iterable<String?> values, {
  Iterable<String> excludedValues = const <String>[],
}) {
  final seen = <String>{
    for (final excluded in excludedValues)
      if (_normalizeDisplayValue(excluded).isNotEmpty) _normalizeDisplayValue(excluded),
  };
  final output = <String>[];
  for (final raw in values) {
    final clean = (raw ?? '').trim();
    final normalized = _normalizeDisplayValue(clean);
    if (clean.isEmpty || normalized.isEmpty || _isPlaceholderValue(normalized) || seen.contains(normalized)) {
      continue;
    }
    seen.add(normalized);
    output.add(clean);
  }
  return output;
}

String _firstDisplayValue(Iterable<String?> values, {required String fallback}) {
  final unique = _uniqueDisplayValues(values);
  return unique.isEmpty ? fallback : unique.first;
}

String _configuredValue(String? value) {
  final clean = (value ?? '').trim();
  return clean.isEmpty || _isPlaceholderValue(_normalizeDisplayValue(clean)) ? 'Not configured' : clean;
}

String _normalizeDisplayValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool _isPlaceholderValue(String normalized) =>
    <String>{'na', 'none', 'null', 'undefined', 'notconfigured', 'unknown'}.contains(normalized);

String _monthId(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
String _initial(String value) => value.trim().isEmpty ? '?' : value.trim().substring(0, 1).toUpperCase();
String _csv(String value) => '"${value.replaceAll('"', '""')}"';
