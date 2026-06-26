/// Extended growth and platform metrics for the founder dashboard.
class AdminGrowthStats {
  final int totalUsers;
  final int usersToday;
  final int usersThisWeek;
  final int activeUsers24h;
  final int eventsToday;
  final int eventsThisWeek;
  final int activeEvents;
  final int communities;
  final int reportsPending;
  final int reportsThisWeek;

  const AdminGrowthStats({
    required this.totalUsers,
    required this.usersToday,
    required this.usersThisWeek,
    required this.activeUsers24h,
    required this.eventsToday,
    required this.eventsThisWeek,
    required this.activeEvents,
    required this.communities,
    required this.reportsPending,
    required this.reportsThisWeek,
  });

  static const AdminGrowthStats zero = AdminGrowthStats(
    totalUsers: 0,
    usersToday: 0,
    usersThisWeek: 0,
    activeUsers24h: 0,
    eventsToday: 0,
    eventsThisWeek: 0,
    activeEvents: 0,
    communities: 0,
    reportsPending: 0,
    reportsThisWeek: 0,
  );
}
