class PendingUpload {
  PendingUpload({
    required this.id,
    required this.filePath,
    required this.storagePath,
    required this.type,
    required this.retryCount,
    required this.nextRetryAt,
  });

  final String id;
  final String filePath;
  final String storagePath;
  final String type; // profile, banner, event
  int retryCount;
  DateTime nextRetryAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'filePath': filePath,
      'storagePath': storagePath,
      'type': type,
      'retryCount': retryCount,
      'nextRetryAt': nextRetryAt.toIso8601String(),
    };
  }

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      id: (json['id'] ?? '').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      storagePath: (json['storagePath'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: DateTime.tryParse((json['nextRetryAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
