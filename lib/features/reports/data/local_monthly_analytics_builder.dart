import '../../../core/constants/app_enums.dart';
import '../../../data/models/member.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';
import '../../../data/models/project.dart';
import '../../../data/models/task.dart';

/// Browser-safe analytics generator used by the local Flutter Web admin build.
///
/// It does not require Cloud Functions. It builds the same report snapshot shape
/// from the workspace data already loaded in memory, so PDF generation remains
/// available on localhost, Firebase Hosting, and the Oracle-backed deployment.
class LocalMonthlyAnalyticsBuilder {
  const LocalMonthlyAnalyticsBuilder();

  MonthlyAnalyticsSnapshot build({
    required String companyId,
    required String monthId,
    required List<Project> projects,
    required List<ProjectTask> tasks,
    required List<Member> members,
    String? projectId,
  }) {
    final range = _monthRange(monthId);
    final now = DateTime.now();
    final cutoff = now.isBefore(range.end)
        ? now
        : range.end.subtract(const Duration(milliseconds: 1));
    final cleanProjectId = (projectId ?? '').trim();

    final scopedProjects = projects
        .where((project) => cleanProjectId.isEmpty || project.projectId == cleanProjectId)
        .toList(growable: false);
    final projectIds = scopedProjects.map((project) => project.projectId).toSet();
    final scopedTasks = tasks
        .where(
          (task) =>
              (cleanProjectId.isEmpty || projectIds.contains(task.projectId)) &&
              _taskOverlapsMonth(task, range.start, range.end),
        )
        .toList(growable: false);

    final relatedMemberIds = <String>{};
    for (final task in scopedTasks) {
      relatedMemberIds.addAll(task.assignedToIds);
    }
    for (final project in scopedProjects) {
      relatedMemberIds.addAll(project.managerIds);
    }
    final scopedMembers = members
        .where(
          (member) =>
              cleanProjectId.isEmpty ||
              relatedMemberIds.contains(member.uid) ||
              member.projectIds.contains(cleanProjectId),
        )
        .toList(growable: false);

    final completedCount = scopedTasks.where((task) => task.isCompleted).length;
    final overdueCount = scopedTasks.where((task) => _isOverdueAt(task, cutoff)).length;
    final estimatedHours = scopedTasks.fold<num>(0, (sum, task) => sum + task.estimatedHours);
    final loggedHours = scopedTasks.fold<num>(0, (sum, task) => sum + task.liveLoggedHours);
    final appraisalScores = scopedMembers
        .map((member) => member.appraisalScore)
        .where((score) => score > 0)
        .toList(growable: false);
    final appraisalAverage = appraisalScores.isEmpty
        ? 0
        : (appraisalScores.reduce((a, b) => a + b) / appraisalScores.length).round();

    final statusDistribution = <String, int>{};
    final priorityDistribution = <String, int>{};
    for (final task in scopedTasks) {
      statusDistribution[task.status.value] =
          (statusDistribution[task.status.value] ?? 0) + 1;
      priorityDistribution[task.priority.value] =
          (priorityDistribution[task.priority.value] ?? 0) + 1;
    }

    final projectBreakdown = scopedProjects.map((project) {
      final projectTasks = scopedTasks
          .where((task) => task.projectId == project.projectId)
          .toList(growable: false);
      final projectCompleted = projectTasks.where((task) => task.isCompleted).length;
      final completionRate = projectTasks.isEmpty
          ? project.progress
          : ((projectCompleted * 100) / projectTasks.length).round();
      return <String, dynamic>{
        'projectId': project.projectId,
        'name': project.name,
        'status': project.status.value,
        'priority': project.priority.value,
        'tasks': projectTasks.length,
        'completed': projectCompleted,
        'overdue': projectTasks.where((task) => _isOverdueAt(task, cutoff)).length,
        'completionRate': completionRate,
        'estimatedHours': projectTasks.fold<num>(0, (sum, task) => sum + task.estimatedHours),
        'loggedHours': projectTasks.fold<num>(0, (sum, task) => sum + task.liveLoggedHours),
        'dueDate': project.dueDate.toIso8601String(),
      };
    }).toList(growable: false);

    final employeeBreakdown = scopedMembers.map((member) {
      final assigned = scopedTasks
          .where((task) => task.assignedToIds.contains(member.uid))
          .toList(growable: false);
      final employeeCompleted = assigned.where((task) => task.isCompleted).length;
      return <String, dynamic>{
        'uid': member.uid,
        'name': member.displayName,
        'email': member.email,
        'role': member.role.value,
        'department': member.effectiveDepartment,
        'jobTitle': member.effectiveJobTitle,
        'assigned': assigned.length,
        'completed': employeeCompleted,
        'overdue': assigned.where((task) => _isOverdueAt(task, cutoff)).length,
        'completionRate': assigned.isEmpty
            ? 0
            : ((employeeCompleted * 100) / assigned.length).round(),
        'loggedHours': assigned.fold<num>(0, (sum, task) => sum + task.liveLoggedHours),
        'appraisalScore': member.appraisalScore,
        'previousAppraisalScore': member.previousAppraisalScore,
        'appraisalStatus': member.appraisalStatus,
        'appraisalPeriod': member.appraisalPeriod,
        'appraisalTemplateId': member.appraisalTemplateId,
        'appraisalCompetencyScores': member.appraisalCompetencyScores,
      };
    }).toList(growable: false);

    final taskBreakdown = scopedTasks
        .map(
          (task) => <String, dynamic>{
            'taskId': task.taskId,
            'projectId': task.projectId,
            'teamId': task.teamId,
            'title': task.title,
            'status': task.status.value,
            'priority': task.priority.value,
            'assignedToIds': task.assignedToIds,
            'dueDate': task.dueDate.toIso8601String(),
            'completedAt': task.completedAt?.toIso8601String(),
            'estimatedHours': task.estimatedHours,
            'loggedHours': task.liveLoggedHours,
            'overdue': _isOverdueAt(task, cutoff),
            'riskLevel': task.riskLevel,
            'progressPercent': task.progressPercent,
          },
        )
        .toList(growable: false);

    final generationId = 'local_web_${DateTime.now().millisecondsSinceEpoch}';
    final metrics = <String, dynamic>{
      'projectCount': scopedProjects.length,
      'activeProjectCount': scopedProjects.where((project) => project.isActiveWork).length,
      'projectsDelayed': scopedProjects.where((project) => project.dueDate.isBefore(cutoff) && project.isOpenWork).length,
      'taskCount': scopedTasks.length,
      'tasksCompleted': completedCount,
      'tasksOverdue': overdueCount,
      'completionRate': scopedTasks.isEmpty ? 0 : ((completedCount * 100) / scopedTasks.length).round(),
      'estimatedHours': estimatedHours,
      'loggedHours': loggedHours,
      'memberCount': scopedMembers.length,
      'appraisalCount': appraisalScores.length,
      'appraisalAverage': appraisalAverage,
      'employmentActionCount': 0,
      'statusDistribution': statusDistribution,
      'priorityDistribution': priorityDistribution,
      'reportScope': cleanProjectId.isEmpty ? 'all' : 'project',
      'scopeProjectId': cleanProjectId.isEmpty ? null : cleanProjectId,
      'generationSource': 'local_flutter_web',
      'minimumPdfPages': 8,
    };

    return MonthlyAnalyticsSnapshot(
      monthId: monthId,
      companyId: companyId,
      periodStart: range.start,
      periodEnd: range.end,
      generatedAt: now,
      reportingCutoff: cutoff,
      finalizedAt: range.end.isBefore(now) ? now : null,
      isFinalized: range.end.isBefore(now),
      schemaVersion: 2,
      generationId: generationId,
      breakdownStorage: 'inline',
      detailCounts: <String, dynamic>{
        'projects': projectBreakdown.length,
        'employees': employeeBreakdown.length,
        'tasks': taskBreakdown.length,
        'employmentActions': 0,
      },
      metrics: metrics,
      projectBreakdown: projectBreakdown,
      employeeBreakdown: employeeBreakdown,
      taskBreakdown: taskBreakdown,
      employmentActionBreakdown: const <Map<String, dynamic>>[],
    );
  }

  bool _taskOverlapsMonth(ProjectTask task, DateTime start, DateTime end) {
    final touchDates = <DateTime?>[
      task.createdAt,
      task.updatedAt,
      task.completedAt,
    ];
    if (touchDates.whereType<DateTime>().any((date) => !date.isBefore(start) && date.isBefore(end))) {
      return true;
    }
    final lifecycleStart = task.startDate ?? task.createdAt ?? start;
    final lifecycleEnd = task.completedAt ?? task.dueDate;
    return lifecycleStart.isBefore(end) && !lifecycleEnd.isBefore(start);
  }

  bool _isOverdueAt(ProjectTask task, DateTime cutoff) {
    return !task.isCompleted && task.dueDate.isBefore(cutoff);
  }

  _MonthRange _monthRange(String monthId) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthId.trim());
    if (match == null) {
      final now = DateTime.now();
      return _MonthRange(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    }
    final year = int.tryParse(match.group(1) ?? '') ?? DateTime.now().year;
    final month = (int.tryParse(match.group(2) ?? '') ?? DateTime.now().month).clamp(1, 12).toInt();
    return _MonthRange(DateTime(year, month), DateTime(year, month + 1));
  }
}

class _MonthRange {
  const _MonthRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}
