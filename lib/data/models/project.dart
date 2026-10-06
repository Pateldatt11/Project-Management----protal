import '../../core/constants/app_enums.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class Project {
  const Project({
    required this.projectId,
    required this.companyId,
    required this.name,
    required this.description,
    required this.status,
    required this.priority,
    required this.startDate,
    required this.dueDate,
    required this.progress,
    required this.totalTasks,
    required this.completedTasks,
    required this.managerIds,
    required this.teamIds,
    this.budget = 0,
    this.currency = 'INR',
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String projectId;
  final String companyId;
  final String name;
  final String description;
  final ProjectStatus status;
  final TaskPriority priority;
  final DateTime startDate;
  final DateTime dueDate;
  final int progress;
  final int totalTasks;
  final int completedTasks;
  final List<String> managerIds;
  final List<String> teamIds;
  final num budget;
  final String currency;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isClosed => status == ProjectStatus.completed || status == ProjectStatus.cancelled;

  /// True for work that is still live/open in the APK. This is intentionally
  /// broader than the strict `ProjectStatus.active` enum because Firestore
  /// projects in review/planning are still active work until they are completed
  /// or cancelled.
  bool get isOpenWork => !isArchived && !isClosed;

  /// Used by dashboard/project summary Active counters. Delayed projects are
  /// counted separately so Active + Delayed does not double count the same row.
  bool get isActiveWork => isOpenWork && !isDelayed;

  bool get isDelayed => isOpenWork && dueDate.isBefore(DateTime.now());

  Project copyWith({
    String? name,
    String? description,
    ProjectStatus? status,
    TaskPriority? priority,
    DateTime? startDate,
    DateTime? dueDate,
    int? progress,
    int? totalTasks,
    int? completedTasks,
    List<String>? managerIds,
    List<String>? teamIds,
    num? budget,
    String? currency,
    bool? isArchived,
    DateTime? updatedAt,
  }) =>
      Project(
        projectId: projectId,
        companyId: companyId,
        name: name ?? this.name,
        description: description ?? this.description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        startDate: startDate ?? this.startDate,
        dueDate: dueDate ?? this.dueDate,
        progress: progress ?? this.progress,
        totalTasks: totalTasks ?? this.totalTasks,
        completedTasks: completedTasks ?? this.completedTasks,
        managerIds: managerIds ?? this.managerIds,
        teamIds: teamIds ?? this.teamIds,
        budget: budget ?? this.budget,
        currency: currency ?? this.currency,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory Project.fromJson(Map<String, dynamic> json) {
    final status = ProjectStatusX.fromValue(
      JsonValue.string(json['status'] ?? json['projectStatus'] ?? json['state'] ?? json['statusTag'], fallback: ProjectStatus.planning.value),
    );
    final progress = JsonValue.integer(json['progress'] ?? json['completion'] ?? json['percentComplete'], fallback: status.stageProgressFloor).clamp(0, 100).toInt();
    return Project(
      projectId: JsonValue.string(json['projectId'] ?? json['id']),
      companyId: JsonValue.string(json['companyId']),
      name: JsonValue.string(json['name'] ?? json['projectName'] ?? json['title'], fallback: 'Untitled project'),
      description: JsonValue.string(json['description'] ?? json['details']),
      status: status,
      priority: TaskPriorityX.fromValue(JsonValue.string(json['priority'], fallback: TaskPriority.medium.value)),
      startDate: DateText.parse(
            json['startDate'] ??
                json['projectStartDate'] ??
                json['plannedStartDate'] ??
                json['timelineStartDate'] ??
                json['originalStartDate'] ??
                json['createdAt'],
          ) ??
          DateTime.now(),
      dueDate: DateText.parse(
            json['dueDate'] ??
                json['projectDueDate'] ??
                json['plannedDueDate'] ??
                json['plannedEndDate'] ??
                json['timelineEndDate'] ??
                json['originalDueDate'] ??
                json['deadline'] ??
                json['endDate'],
          ) ??
          DateTime.now(),
      progress: progress,
      totalTasks: JsonValue.integer(json['totalTasks'] ?? json['taskCount'], fallback: 0),
      completedTasks: JsonValue.integer(json['completedTasks'] ?? json['completedTaskCount'] ?? json['doneTasks'] ?? json['doneTaskCount'], fallback: 0),
      managerIds: JsonValue.stringList(json['managerIds'] ?? json['managers'] ?? json['ownerIds']),
      teamIds: JsonValue.stringList(json['teamIds'] ?? json['teams']),
      budget: JsonValue.number(json['budget'], fallback: 0),
      currency: JsonValue.string(json['currency'], fallback: 'INR'),
      isArchived: JsonValue.boolean(json['isArchived'] ?? json['archived'], fallback: false),
      createdAt: DateText.parse(json['createdAt']),
      updatedAt: DateText.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'companyId': companyId,
        'name': name,
        'description': description,
        'status': status.value,
        'priority': priority.value,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'progress': progress,
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'managerIds': managerIds,
        'teamIds': teamIds,
        'budget': budget,
        'currency': currency,
        'isArchived': isArchived,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}
