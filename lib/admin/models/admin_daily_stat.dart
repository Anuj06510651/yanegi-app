/// A single data point for analytics charts: a date + count.
class AdminDailyStat {
  final DateTime date;
  final int count;

  const AdminDailyStat({required this.date, required this.count});
}

/// Aggregated analytics data fetched client-side from existing collections.
/// All lists are sorted ascending by date and cover the last N days.
class AdminAnalyticsData {
  final List<AdminDailyStat> newUsers;
  final List<AdminDailyStat> activeUsers;
  final List<AdminDailyStat> newEvents;
  final List<AdminDailyStat> newCommunities;

  const AdminAnalyticsData({
    required this.newUsers,
    required this.activeUsers,
    required this.newEvents,
    required this.newCommunities,
  });

  static const AdminAnalyticsData empty = AdminAnalyticsData(
    newUsers: [],
    activeUsers: [],
    newEvents: [],
    newCommunities: [],
  );
}
