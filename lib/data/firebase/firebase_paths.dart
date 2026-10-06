class FirebasePaths {
  static String user(String uid) => 'users/$uid';
  static String userMemberships(String uid) => 'users/$uid/memberships';
  static String userFcmTokens(String uid) => 'users/$uid/fcmTokens';

  static String company(String companyId) => 'companies/$companyId';
  static String members(String companyId) => 'companies/$companyId/members';
  static String projects(String companyId) => 'companies/$companyId/projects';
  static String tasks(String companyId) => 'companies/$companyId/tasks';
  static String teams(String companyId) => 'companies/$companyId/teams';
  static String notifications(String companyId) => 'companies/$companyId/notifications';
  static String memberNotifications(String companyId, String uid) => 'companies/$companyId/members/$uid/notifications';
  static String activityLogs(String companyId) => 'companies/$companyId/activityLogs';
  static String auditLogs(String companyId) => 'companies/$companyId/auditLogs';
  static String reports(String companyId) => 'companies/$companyId/reports';
  static String dashboardStats(String companyId) => 'companies/$companyId/dashboardStats';
  static String settings(String companyId) => 'companies/$companyId/settings';
  static String portalPostSettings(String companyId) => 'companies/$companyId/settings/portalPosts';
  static String demoDataSettings(String companyId) => 'companies/$companyId/settings/demoData';
  static String bootstrapSettings(String companyId) => 'companies/$companyId/settings/bootstrap';
  static String uiConfigs(String companyId) => 'companies/$companyId/uiConfigs';
  static String mobileEmployeeUiConfig(String companyId) => 'companies/$companyId/uiConfigs/mobileEmployee';
  static String mobileEmployeeUiConfigDoc(String companyId, String docId) => 'companies/$companyId/uiConfigs/$docId';
  static String mobileEmployeeUiDesign(String companyId) => 'companies/$companyId/uiConfigs/mobileEmployeeDesign';
  static String mobileEmployeeUiDesignDraft(String companyId) => 'companies/$companyId/uiConfigs/mobileEmployeeDesignDraft';
  static String invites(String companyId) => 'companies/$companyId/invites';
  static String invite(String companyId, String inviteId) => 'companies/$companyId/invites/$inviteId';

  static String taskComments(String companyId, String taskId) => 'companies/$companyId/tasks/$taskId/comments';
  static String taskAttachments(String companyId, String taskId) => 'companies/$companyId/tasks/$taskId/attachments';
}
