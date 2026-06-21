part of '../../../screens/chat/chat_thread_screen.dart';

class _SeenInitialBubble extends StatelessWidget {
  const _SeenInitialBubble({required this.name});

  final String name;

  /// Deterministic color from the name — same name always yields same color.
  Color _colorForName(String n) {
    const palette = [
      Color(0xFF5C6BC0), // indigo
      Color(0xFF26A69A), // teal
      Color(0xFF8D6E63), // brown
      Color(0xFF42A5F5), // blue
      Color(0xFF66BB6A), // green
      Color(0xFFAB47BC), // purple
      Color(0xFFEF5350), // red
      Color(0xFFFF7043), // deep orange
      Color(0xFF78909C), // blue-grey
      Color(0xFFD4E157), // lime (darkened for readability)
    ];
    if (n.isEmpty) return const Color(0xFF546E7A);
    final hash = n.codeUnits.fold(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }

  String _initial(String n) {
    final trimmed = n.trim();
    if (trimmed.isEmpty) return '?';
    // Takes the first visible character, works with emoji and non-Latin scripts.
    final runes = trimmed.runes.toList();
    return String.fromCharCode(runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _colorForName(name);
    final initial = _initial(name);

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: const Color(0xFF22E7A2), // Yanegi teal — "seen"
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
