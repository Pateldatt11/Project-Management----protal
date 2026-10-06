import '../../data/models/member.dart';
import '../constants/app_enums.dart';

class PermissionService {

  static bool isAdminDashboardRole(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.hrManager,
      ].contains(member.role);

  static bool isEmployeeWorkspaceRole(Member member) => [
        UserRole.developer,
        UserRole.qaTester,
        UserRole.designer,
        UserRole.devOps,
        UserRole.employee,
        UserRole.clientViewer,
      ].contains(member.role);

  static bool shouldUseEmployeeWorkspace(Member member) => isEmployeeWorkspaceRole(member);

  static bool canManageCompany(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
      ].contains(member.role);

  static bool canManageInfrastructure(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
        UserRole.devOps,
      ].contains(member.role);

  static bool canManageProjects(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
      ].contains(member.role);

  static bool canManageTaskForces(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canEditProject(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canCreateTasks(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canAssignTasks(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canCreateMeetings(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canUpdateOwnTask(Member member) => ![UserRole.clientViewer, UserRole.hrManager].contains(member.role);

  static bool canMoveKanban(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.developer,
        UserRole.qaTester,
        UserRole.designer,
        UserRole.devOps,
        UserRole.employee,
      ].contains(member.role);


  static bool canEditTimeline(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canEditAppraisal(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canRecommendCareerAction(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canReviewCareerAction(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canApproveCareerAction(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canManageAppraisalTemplates(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.hrManager,
      ].contains(member.role);


  static bool canViewFullProjectProgress(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
        UserRole.projectManager,
        UserRole.teamLead,
      ].contains(member.role);

  static bool canViewReports(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
        UserRole.projectManager,
        UserRole.teamLead,
        UserRole.hrManager,
        UserRole.clientViewer,
      ].contains(member.role);

  static bool canGenerateReports(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.projectManager,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canManagePeople(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canInviteMembers(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.hrManager,
      ].contains(member.role);

  static bool canViewAuditLogs(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
      ].contains(member.role);

  static bool canManageSettings(Member member) => [
        UserRole.superAdmin,
        UserRole.admin,
        UserRole.itAdmin,
      ].contains(member.role);

  static bool canAccessSection(Member member, MainSection section) {
    return switch (section) {
      MainSection.dashboard => true,
      MainSection.projects => member.role != UserRole.hrManager,
      MainSection.tasks => ![UserRole.hrManager, UserRole.clientViewer].contains(member.role),
      MainSection.kanban => ![UserRole.hrManager, UserRole.clientViewer, UserRole.itAdmin].contains(member.role),
      MainSection.timeline => member.role != UserRole.clientViewer,
      MainSection.appraisals => member.role != UserRole.clientViewer,
      MainSection.meetings => canCreateMeetings(member),
      MainSection.teams => [
          UserRole.superAdmin,
          UserRole.admin,
          UserRole.projectManager,
          UserRole.teamLead,
          UserRole.hrManager,
        ].contains(member.role),
      MainSection.employees => [
          UserRole.superAdmin,
          UserRole.admin,
          UserRole.itAdmin,
          UserRole.projectManager,
          UserRole.teamLead,
          UserRole.hrManager,
        ].contains(member.role),
      MainSection.reports => canViewReports(member),
      MainSection.notifications => true,
      MainSection.settings => canManageSettings(member),
      MainSection.profile => true,
    };
  }

  static String sectionLockReason(Member member, MainSection section) {
    if (canAccessSection(member, section)) return '';
    return '${member.role.label} does not have access to ${section.label}.';
  }
}
