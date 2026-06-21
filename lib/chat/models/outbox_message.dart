class OutboxMessage {
  OutboxMessage({
    required this.localId,
    required this.chatId,
    required this.text,
    required this.senderId,
    required this.createdAt,
    required this.status,
    this.senderName = '',
    this.eventId,
    this.participantIds = const <String>[],
    DateTime? lastUpdatedAt,
    DateTime? nextAttemptAt,
    this.retryCount = 0,
    this.failureReason = '',
    this.inFlight = false,
    this.replyToMessageId,
    this.replyToPreviewText = '',
    this.replyToSenderName = '',
  })  : lastUpdatedAt = lastUpdatedAt ?? createdAt,
        nextAttemptAt = nextAttemptAt ?? createdAt;

  final String localId;
  final String chatId;
  final String text;
  final String senderId;
  final String senderName;
  final String? eventId;
  final List<String> participantIds;
  final DateTime createdAt;
  String status; // sending | failed | sent
  DateTime lastUpdatedAt;
  DateTime nextAttemptAt;
  int retryCount;
  String failureReason;
  bool inFlight;
  final String? replyToMessageId;
  final String replyToPreviewText;
  final String replyToSenderName;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'localId': localId,
      'chatId': chatId,
      'text': text,
      'senderId': senderId,
      'senderName': senderName,
      'eventId': eventId,
      'participantIds': participantIds,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
      'nextAttemptAt': nextAttemptAt.toIso8601String(),
      'retryCount': retryCount,
      'failureReason': failureReason,
      'inFlight': inFlight,
      'replyToMessageId': replyToMessageId,
      'replyToPreviewText': replyToPreviewText,
      'replyToSenderName': replyToSenderName,
    };
  }

  factory OutboxMessage.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
        DateTime.now();

    final rawReplyId = (map['replyToMessageId'] ?? '').toString().trim();

    return OutboxMessage(
      localId: (map['localId'] ?? '').toString(),
      chatId: (map['chatId'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      senderId: (map['senderId'] ?? '').toString(),
      senderName: (map['senderName'] ?? '').toString(),
      eventId: (map['eventId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['eventId'] ?? '').toString(),
      participantIds: ((map['participantIds'] as List?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: createdAt,
      status: (map['status'] ?? 'sending').toString(),
      lastUpdatedAt:
          DateTime.tryParse((map['lastUpdatedAt'] ?? '').toString()) ??
              createdAt,
      nextAttemptAt:
          DateTime.tryParse((map['nextAttemptAt'] ?? '').toString()) ??
              DateTime.now(),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      failureReason: (map['failureReason'] ?? '').toString(),
      inFlight: map['inFlight'] == true,
      replyToMessageId: rawReplyId.isEmpty ? null : rawReplyId,
      replyToPreviewText: (map['replyToPreviewText'] ?? '').toString(),
      replyToSenderName: (map['replyToSenderName'] ?? '').toString(),
    );
  }
}
