import '../models/activity_log.dart';
import '../models/app_notification.dart';
import '../models/audit_log.dart';
import '../models/file_attachment.dart';
import '../models/member.dart';
import '../models/mobile_ui_config.dart';
import '../models/mobile_ui_design.dart';
import '../models/project.dart';
import '../models/report.dart';
import '../models/task.dart';
import '../models/task_comment.dart';
import '../models/team.dart';

abstract class WorkspaceRepository {
  Stream<List<Project>> watchProjects(String companyId, {String? currentUid, bool canViewFullProgress = false, List<String> projectIds = const [], List<String> teamIds = const []});
  Stream<List<ProjectTask>> watchTasks(String companyId, {String? currentUid, bool canViewFullProgress = false, List<String> projectIds = const [], List<String> teamIds = const []});
  Stream<List<Member>> watchMembers(String companyId, {String? currentUid, bool canViewFullProgress = false, List<String> projectIds = const [], List<String> teamIds = const []});
  Stream<List<Team>> watchTeams(String companyId, {String? currentUid, bool canViewFullProgress = false, List<String> projectIds = const [], List<String> teamIds = const []});
  Stream<List<AppNotification>> watchMyNotifications(String companyId, String uid);
  Stream<List<ActivityLog>> watchActivity(String companyId);
  Stream<List<AuditLog>> watchAuditLogs(String companyId);
  Stream<List<ReportModel>> watchReports(String companyId);
  Stream<List<TaskComment>> watchComments(String companyId);
  Stream<List<FileAttachment>> watchAttachments(String companyId);
  Stream<MobileUiConfig> watchMobileUiConfig(String companyId);
  Stream<MobileUiDesign> watchMobileUiDesign(String companyId);


  Future<void> saveProject(Project project);
  Future<void> saveTask(ProjectTask task);
  Future<void> saveTeam(Team team);
  Future<void> saveMember(Member member);
  Future<void> saveNotification(AppNotification notification);
  Future<void> saveActivity(ActivityLog log);
  Future<void> saveAuditLog(AuditLog log);
  Future<void> saveReport(ReportModel report);
  Future<void> saveMobileUiConfig(String companyId, MobileUiConfig config, {String? updatedBy});
  Future<void> saveMobileUiDesign(String companyId, MobileUiDesign design, {String? updatedBy});
  Future<void> saveComment(String companyId, TaskComment comment);
  Future<void> saveAttachment(String companyId, FileAttachment attachment);
  Future<void> deleteTask(String companyId, String taskId);
}
