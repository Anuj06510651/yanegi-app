class PollOption {
  const PollOption({
    required this.id,
    required this.text,
    this.voterIds = const [],
  });

  final String id;
  final String text;
  final List<String> voterIds;

  bool hasVoted(String uid) => voterIds.contains(uid);

  PollOption withVoters(List<String> voters) =>
      PollOption(id: id, text: text, voterIds: voters);

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'voterIds': voterIds,
      };

  static PollOption fromMap(Map<String, dynamic> m) => PollOption(
        id: (m['id'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        voterIds: (m['voterIds'] as List? ?? [])
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
}

class PollData {
  const PollData({
    required this.question,
    required this.options,
    this.allowMultipleVotes = false,
    this.createdBy = '',
  });

  final String question;
  final List<PollOption> options;
  final bool allowMultipleVotes;
  final String createdBy;

  int get totalVotes =>
      options.fold(0, (sum, o) => sum + o.voterIds.length);

  /// UIDs of users who voted for [optionId].
  List<String> votersFor(String optionId) =>
      options.firstWhere((o) => o.id == optionId,
              orElse: () => const PollOption(id: '', text: ''))
          .voterIds;

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': options.map((o) => o.toMap()).toList(),
        'allowMultipleVotes': allowMultipleVotes,
        'createdBy': createdBy,
      };

  static PollData fromMap(Map<String, dynamic> m) => PollData(
        question: (m['question'] ?? '').toString(),
        options: (m['options'] as List? ?? [])
            .whereType<Map>()
            .map((o) => PollOption.fromMap(Map<String, dynamic>.from(o)))
            .where((o) => o.id.isNotEmpty)
            .toList(),
        allowMultipleVotes: m['allowMultipleVotes'] == true,
        createdBy: (m['createdBy'] ?? '').toString(),
      );
}
