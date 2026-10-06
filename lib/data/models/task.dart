import '../../core/constants/app_enums.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';
import 'file_attachment.dart';

class ProjectTask {
  const ProjectTask({
    required this.taskId,
    required this.companyId,
    required this.projectId,
    required this.teamId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.assignedToIds,
    required this.createdBy,
    required this.dueDate,
    required this.kanbanRank,
    this.startDate,
    this.reporterId,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.attachmentsCount = 0,
    this.commentsCount = 0,
    this.estimatedHours = 0,
    this.loggedHours = 0,
    this.activeWorkTimerUserId,
    this.activeWorkTimerStartedAt,
    this.tags = const [],
    this.dependencyTaskIds = const [],
    this.baselineStartDate,
    this.baselineDueDate,
    this.isMilestone = false,
    this.progressPercent,
    this.riskLevel = 'normal',
    this.attachments = const [],
    this.attachmentNames = const [],
  });

  final String taskId;
  final String companyId;
  final String projectId;
  final String teamId;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final List<String> assignedToIds;
  final String createdBy;
  final String? reporterId;
  final DateTime dueDate;
  final String kanbanRank;
  final DateTime? startDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final int attachmentsCount;
  final int commentsCount;
  final num estimatedHours;
  final num loggedHours;
  final String? activeWorkTimerUserId;
  final DateTime? activeWorkTimerStartedAt;
  final List<String> tags;
  final List<String> dependencyTaskIds;
  final DateTime? baselineStartDate;
  final DateTime? baselineDueDate;
  final bool isMilestone;
  final int? progressPercent;
  final String riskLevel;
  final List<FileAttachment> attachments;
  final List<String> attachmentNames;

  bool get isOverdue => status != TaskStatus.completed && dueDate.isBefore(DateTime.now());
  bool get isCompleted => status == TaskStatus.completed;
  bool get hasDependencies => dependencyTaskIds.isNotEmpty;
  bool get hasBaseline => baselineStartDate != null || baselineDueDate != null;
  bool get isWorkTimerRunning =>
      (activeWorkTimerUserId ?? '').trim().isNotEmpty && activeWorkTimerStartedAt != null;

  Duration get activeWorkDuration {
    final startedAt = activeWorkTimerStartedAt;
    if (!isWorkTimerRunning || startedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  num get liveLoggedHours {
    if (!isWorkTimerRunning) return loggedHours;
    final live = loggedHours.toDouble() + activeWorkDuration.inSeconds / 3600.0;
    return double.parse(live.toStringAsFixed(2));
  }

  double get effortUsage => estimatedHours == 0 ? 0 : (liveLoggedHours / estimatedHours).clamp(0, 1).toDouble();

  ProjectTask copyWith({
    String? title,
    String? description,
    String? projectId,
    String? teamId,
    TaskStatus? status,
    TaskPriority? priority,
    List<String>? assignedToIds,
    String? kanbanRank,
    DateTime? dueDate,
    DateTime? startDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    int? attachmentsCount,
    int? commentsCount,
    num? estimatedHours,
    num? loggedHours,
    String? activeWorkTimerUserId,
    DateTime? activeWorkTimerStartedAt,
    bool clearActiveWorkTimer = false,
    List<String>? tags,
    List<String>? dependencyTaskIds,
    DateTime? baselineStartDate,
    DateTime? baselineDueDate,
    bool clearBaseline = false,
    bool? isMilestone,
    int? progressPercent,
    bool clearProgressPercent = false,
    String? riskLevel,
    List<FileAttachment>? attachments,
    List<String>? attachmentNames,
  }) {
    final updatedAttachments = attachments ?? this.attachments;
    final updatedAttachmentNames = attachmentNames ??
        (attachments != null ? attachments.map((a) => a.fileName).toList() : this.attachmentNames);

    return ProjectTask(
      taskId: taskId,
      companyId: companyId,
      projectId: projectId ?? this.projectId,
      teamId: teamId ?? this.teamId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignedToIds: assignedToIds ?? this.assignedToIds,
      createdBy: createdBy,
      reporterId: reporterId,
      dueDate: dueDate ?? this.dueDate,
      kanbanRank: kanbanRank ?? this.kanbanRank,
      startDate: startDate ?? this.startDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      attachmentsCount: attachmentsCount ??
          (updatedAttachments.isNotEmpty
              ? updatedAttachments.length
              : (updatedAttachmentNames.isNotEmpty ? updatedAttachmentNames.length : this.attachmentsCount)),
      commentsCount: commentsCount ?? this.commentsCount,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      loggedHours: loggedHours ?? this.loggedHours,
      activeWorkTimerUserId: clearActiveWorkTimer ? null : activeWorkTimerUserId ?? this.activeWorkTimerUserId,
      activeWorkTimerStartedAt: clearActiveWorkTimer ? null : activeWorkTimerStartedAt ?? this.activeWorkTimerStartedAt,
      tags: tags ?? this.tags,
      dependencyTaskIds: dependencyTaskIds ?? this.dependencyTaskIds,
      baselineStartDate: clearBaseline ? null : baselineStartDate ?? this.baselineStartDate,
      baselineDueDate: clearBaseline ? null : baselineDueDate ?? this.baselineDueDate,
      isMilestone: isMilestone ?? this.isMilestone,
      progressPercent: clearProgressPercent ? null : progressPercent ?? this.progressPercent,
      riskLevel: riskLevel ?? this.riskLevel,
      attachments: updatedAttachments,
      attachmentNames: updatedAttachmentNames,
    );
  }

  factory ProjectTask.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    List<FileAttachment> parsedAttachments = [];
    if (rawAttachments is List) {
      parsedAttachments = rawAttachments
          .whereType<Map>()
          .map((item) => FileAttachment.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    final parsedAttachmentNames = JsonValue.stringList(
      json['attachmentNames'] ?? json['fileNames'],
    );

    final combinedNames = parsedAttachments.isNotEmpty
        ? parsedAttachments.map((a) => a.fileName).toList()
        : parsedAttachmentNames;

    return ProjectTask(
      taskId: JsonValue.string(json['taskId'] ?? json['id']),
      companyId: JsonValue.string(json['companyId']),
      projectId: JsonValue.string(json['projectId'] ?? json['project']),
      teamId: JsonValue.string(json['teamId'] ?? json['team']),
      title: JsonValue.string(json['title'] ?? json['taskTitle'] ?? json['name'], fallback: 'Untitled task'),
      description: JsonValue.string(json['description'] ?? json['details']),
      status: TaskStatusX.fromValue(JsonValue.string(json['status'], fallback: TaskStatus.backlog.value)),
      priority: TaskPriorityX.fromValue(JsonValue.string(json['priority'], fallback: TaskPriority.medium.value)),
      assignedToIds: JsonValue.stringList(json['assignedToIds'] ?? json['assignees'] ?? json['assignedTo'] ?? json['memberIds']),
      createdBy: JsonValue.string(json['createdBy'] ?? json['creatorId']),
      reporterId: JsonValue.optionalString(json['reporterId']),
      dueDate: DateText.parse(json['dueDate'] ?? json['deadline']) ?? DateTime.now(),
      kanbanRank: JsonValue.string(json['kanbanRank'] ?? json['rank'], fallback: 'm0001'),
      startDate: DateText.parse(json['startDate'] ?? json['timelineStartDate'] ?? json['plannedStart']),
      createdAt: DateText.parse(json['createdAt']),
      updatedAt: DateText.parse(json['updatedAt']),
      completedAt: DateText.parse(json['completedAt']),
      attachmentsCount: JsonValue.integer(
        json['attachmentsCount'] ?? json['fileCount'],
        fallback: parsedAttachments.isNotEmpty ? parsedAttachments.length : combinedNames.length,
      ),
      commentsCount: JsonValue.integer(json['commentsCount'] ?? json['commentCount'], fallback: 0),
      estimatedHours: JsonValue.number(json['estimatedHours'], fallback: 0),
      loggedHours: JsonValue.number(json['loggedHours'], fallback: 0),
      activeWorkTimerUserId: JsonValue.optionalString(json['activeWorkTimerUserId'] ?? json['workTimerUserId'] ?? json['timerUserId']),
      activeWorkTimerStartedAt: DateText.parse(json['activeWorkTimerStartedAt'] ?? json['workTimerStartedAt'] ?? json['timerStartedAt']),
      tags: JsonValue.stringList(json['tags']),
      dependencyTaskIds: JsonValue.stringList(json['dependencyTaskIds'] ?? json['dependencies'] ?? json['predecessorIds']),
      baselineStartDate: DateText.parse(json['baselineStartDate'] ?? json['plannedBaselineStart']),
      baselineDueDate: DateText.parse(json['baselineDueDate'] ?? json['plannedBaselineEnd']),
      isMilestone: JsonValue.boolean(json['isMilestone'] ?? json['milestone'], fallback: false),
      progressPercent: json['progressPercent'] == null && json['progress'] == null
          ? null
          : JsonValue.integer(json['progressPercent'] ?? json['progress']).clamp(0, 100).toInt(),
      riskLevel: JsonValue.string(json['riskLevel'] ?? json['scheduleRisk'], fallback: 'normal'),
      attachments: parsedAttachments,
      attachmentNames: combinedNames,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskId': taskId,
        'companyId': companyId,
        'projectId': projectId,
        'teamId': teamId,
        'title': title,
        'description': description,
        'status': status.value,
        'priority': priority.value,
        'assignedToIds': assignedToIds,
        'createdBy': createdBy,
        'reporterId': reporterId,
        'dueDate': dueDate.toIso8601String(),
        'kanbanRank': kanbanRank,
        'startDate': startDate?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'attachmentsCount': attachments.isNotEmpty
            ? attachments.length
            : (attachmentNames.isNotEmpty ? attachmentNames.length : attachmentsCount),
        'commentsCount': commentsCount,
        'estimatedHours': estimatedHours,
        'loggedHours': loggedHours,
        'activeWorkTimerUserId': activeWorkTimerUserId,
        'activeWorkTimerStartedAt': activeWorkTimerStartedAt?.toIso8601String(),
        'tags': tags,
        'dependencyTaskIds': dependencyTaskIds,
        'baselineStartDate': baselineStartDate?.toIso8601String(),
        'baselineDueDate': baselineDueDate?.toIso8601String(),
        'isMilestone': isMilestone,
        'progressPercent': progressPercent,
        'riskLevel': riskLevel,
        'attachmentNames': attachments.isNotEmpty
            ? attachments.map((a) => a.fileName).toList()
            : attachmentNames,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}