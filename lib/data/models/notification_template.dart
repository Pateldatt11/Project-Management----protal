class NotificationTemplate {
  final String id;
  final String label;
  final String titleTemplate;
  final String bodyTemplate;
  final String badgeText;

  const NotificationTemplate({
    required this.id,
    required this.label,
    required this.titleTemplate,
    required this.bodyTemplate,
    required this.badgeText,
  });

  /// Format title replacing task and priority tags
  String formatTitle({
    required String taskTitle,
    required String priority,
  }) {
    final cleanTitle = taskTitle.trim().isEmpty ? 'Untitled Task' : taskTitle.trim();
    return titleTemplate
        .replaceAll('{task_title}', cleanTitle)
        .replaceAll('{priority}', priority);
  }

  /// Format body replacing all dynamic form variables.
  /// Meeting Link and Admin Meeting Access are appended dynamically only when provided.
  String formatBody({
    required String taskTitle,
    required String adminName,
    required String projectName,
    required String dueDate,
    required String assigneeName,
    required String priority,
    required String estimatedHours,
    required String teamName,
    required String description,
    String? meetingLink,
    bool adminMeetingAccess = true,
    bool isSenderAdmin = true,
  }) {
    final cleanTask = taskTitle.trim().isEmpty ? 'Task' : taskTitle.trim();
    final cleanAdmin = adminName.trim().isEmpty ? 'Admin' : adminName.trim();
    final cleanProject = projectName.trim().isEmpty ? 'General' : projectName.trim();
    final cleanAssignee = assigneeName.trim().isEmpty ? 'Assignee' : assigneeName.trim();
    final cleanHours = estimatedHours.trim().isEmpty ? '0' : estimatedHours.trim();
    final cleanDesc = description.trim().isEmpty ? 'No description' : description.trim();
    final cleanTeam = teamName.trim().isEmpty ? 'General' : teamName.trim();
    final cleanMeeting = (meetingLink ?? '').trim();

    var formatted = bodyTemplate
        .replaceAll('{task_title}', cleanTask)
        .replaceAll('{admin_name}', cleanAdmin)
        .replaceAll('{project_name}', cleanProject)
        .replaceAll('{due_date}', dueDate)
        .replaceAll('{assignee_name}', cleanAssignee)
        .replaceAll('{priority}', priority)
        .replaceAll('{estimated_hours}', cleanHours)
        .replaceAll('{team_name}', cleanTeam)
        .replaceAll('{description}', cleanDesc);

    // Append Meeting Link only when provided
    if (cleanMeeting.isNotEmpty) {
      formatted += '\nMeeting Link: $cleanMeeting';

      // Append Admin Meeting Access only when meeting link exists and sender is admin
      if (isSenderAdmin) {
        formatted += '\nAdmin Meeting Access: ${adminMeetingAccess ? '(Checkbox checked in form)' : '(Disabled)'}';
      }
    }

    return formatted;
  }
}

/// Built-in notification preset templates matching the preview card structure
class NotificationPresets {
  const NotificationPresets._();

  static const List<NotificationTemplate> templates = [
    NotificationTemplate(
      id: 'standard',
      label: 'Standard',
      badgeText: 'Assignment',
      titleTemplate: 'Task Assigned: {task_title} [{priority}]',
      bodyTemplate:
          '{admin_name} assigned {task_title} to {assignee_name} in {project_name}.\n'
          'Description: {description}\n'
          'Est. Time: {estimated_hours}h | Due Date: {due_date}\n'
          'Team: {team_name}',
    ),
    NotificationTemplate(
      id: 'urgent',
      label: 'Urgent',
      badgeText: 'High Priority',
      titleTemplate: '🚨 Urgent [{priority}]: {task_title}',
      bodyTemplate:
          '{admin_name} assigned an urgent task in {project_name} to {assignee_name}.\n'
          'Description: {description}\n'
          'Est. Time: {estimated_hours}h | Due Date: {due_date}\n'
          'Team: {team_name}',
    ),
    NotificationTemplate(
      id: 'qa_review',
      label: 'QA / Review',
      badgeText: 'Review',
      titleTemplate: 'Review Needed: {task_title}',
      bodyTemplate:
          '{assignee_name}, please review {task_title} in {project_name}.\n'
          'Description: {description}\n'
          'Est. Time: {estimated_hours}h | Due Date: {due_date}\n'
          'Team: {team_name}',
    ),
    NotificationTemplate(
      id: 'client_feedback',
      label: 'Client Feedback',
      badgeText: 'Revision',
      titleTemplate: 'Client Feedback: {task_title}',
      bodyTemplate:
          'Client requested updates on {task_title} for {assignee_name}.\n'
          'Description: {description}\n'
          'Est. Time: {estimated_hours}h | Due Date: {due_date}\n'
          'Team: {team_name}',
    ),
    NotificationTemplate(
      id: 'discussion',
      label: 'Discussion',
      badgeText: 'Sync',
      titleTemplate: 'Task Sync: {task_title}',
      bodyTemplate:
          '{admin_name} requested a discussion with {assignee_name} on {task_title}.\n'
          'Description: {description}\n'
          'Est. Time: {estimated_hours}h | Due Date: {due_date}\n'
          'Team: {team_name}',
    ),
  ];
}