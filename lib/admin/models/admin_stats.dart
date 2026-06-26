/// Snapshot of platform-level metrics shown on the dashboard home.
/// All fields are integers from Firestore count() aggregations.
class AdminStats {
  final int totalUsers;
  final int usersToday;
  final int activeUsers24h;
  final int eventsToday;
  final int activeEvents;
  final int communities;
  final int reportsPending;

  const AdminStats({
    required this.totalUsers,
    required this.usersToday,
    required this.activeUsers24h,
    required this.eventsToday,
    required this.activeEvents,
    required this.communities,
    required this.reportsPending,
  });

  static const AdminStats zero = AdminStats(
    totalUsers: 0,
    usersToday: 0,
    activeUsers24h: 0,
    eventsToday: 0,
    activeEvents: 0,
    communities: 0,
    reportsPending: 0,
  );
}
