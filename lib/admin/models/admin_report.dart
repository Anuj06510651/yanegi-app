import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportStatus { pending, resolved, dismissed }

/// Maps the Firestore `reports` collection documents.
/// Compatible with both app_bug reports (report_problem_screen) and
/// safety reports (safety_reporting_screen) — both write to `reports`.
class AdminReport {
  final String id;
  final String reporterId;
  final String reporterName;
  final String reportedUserId;
  final String reportedUserName;
  final String reason;
  final String description;
  final String? screenshotUrl;
  final String? relatedEventId;
  final String? relatedChatId;
  final ReportStatus status;
  final DateTime? createdAt;

  const AdminReport({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.reportedUserId,
    required this.reportedUserName,
    required this.reason,
    required this.description,
    this.screenshotUrl,
    this.relatedEventId,
    this.relatedChatId,
    required this.status,
    this.createdAt,
  });

  factory AdminReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AdminReport(
      id: doc.id,
      reporterId: (data['userId'] ?? '').toString(),
      reporterName: (data['username'] ?? '').toString(),
      reportedUserId: (data['reportedUserId'] ?? '').toString(),
      reportedUserName: (data['reportedUsername'] ?? '').toString(),
      reason: (data['category'] ?? data['reason'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      screenshotUrl: data['screenshotUrl'] as String?,
      relatedEventId: data['eventId'] as String?,
      relatedChatId: data['chatId'] as String?,
      status: _parseStatus(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
          (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  static ReportStatus _parseStatus(dynamic raw) {
    switch (raw?.toString()) {
      case 'resolved':
        return ReportStatus.resolved;
      case 'dismissed':
        return ReportStatus.dismissed;
      default:
        return ReportStatus.pending;
    }
  }

  String get statusLabel {
    switch (status) {
      case ReportStatus.pending:
        return 'Pending';
      case ReportStatus.resolved:
        return 'Resolved';
      case ReportStatus.dismissed:
        return 'Dismissed';
    }
  }
}
