class DashboardStats {
  const DashboardStats({
    required this.totalProjects,
    required this.activeProjects,
    required this.completedProjects,
    required this.delayedProjects,
    required this.totalTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.teamProductivity,
  });

  final int totalProjects;
  final int activeProjects;
  final int completedProjects;
  final int delayedProjects;
  final int totalTasks;
  final int completedTasks;
  final int overdueTasks;
  final int teamProductivity;
}
