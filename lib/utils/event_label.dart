/// Returns a consistent, seed-based synonym for the word "event".
///
/// Using the [eventId] as a seed means the same gathering always gets the
/// same label across every screen, notification, and chat message — so "Your
/// hangout starts tomorrow" and "This hangout has ended" always agree.
///
/// Call [EventLabel.of] wherever UI copy currently says "event".
/// Call [EventLabel.capitalized] for title-case contexts (badges, buttons).
abstract class EventLabel {
  static const List<String> _words = [
    'hangout',
    'meetup',
    'gathering',
    'outing',
    'get-together',
    'catch-up',
    'link-up',
    'session',
    'rendezvous',
    'adventure',
    'plan',
    'sesh',
  ];

  /// Lowercase synonym, consistent for the same [eventId].
  static String of(String eventId) {
    if (eventId.trim().isEmpty) return 'event';
    final hash = eventId.codeUnits.fold(0, (int acc, int c) => acc + c);
    return _words[hash % _words.length];
  }

  /// Title-case synonym ("Hangout", "Meetup", …).
  static String capitalized(String eventId) {
    final w = of(eventId);
    return w[0].toUpperCase() + w.substring(1);
  }
}
