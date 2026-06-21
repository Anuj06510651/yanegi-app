import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// The five emojis shown in the quick-pick bar.
const List<String> kQuickReactionEmojis = ['❤️', '😂', '😮', '😢', '👍'];

// Full emoji set organized by category for the expanded picker sheet.
const Map<String, List<String>> kEmojiCategories = {
  'Smileys': [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😚', '😋',
    '😛', '😝', '😜', '🤪', '🤓', '😎', '🤩', '🥳', '😏', '😒',
    '😞', '😔', '😟', '😕', '🙁', '☹️', '😣', '😖', '😫', '😩',
    '🥺', '😢', '😭', '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵',
    '🥶', '😱', '😨', '😰', '😥', '😓', '🤗', '🤔', '🤭', '🤫',
    '🤥', '😶', '😐', '😑', '😬', '🙄', '😯', '😦', '😧', '😮',
    '😲', '🥱', '😴', '🤤', '😪', '😵', '🤐', '🥴', '🤢', '🤮',
    '🤧', '😷', '🤒', '🤕',
  ],
  'Gestures': [
    '👍', '👎', '👊', '✊', '🤛', '🤜', '🤞', '✌️', '🤟', '🤘',
    '🤙', '👈', '👉', '👆', '👇', '☝️', '👋', '🤚', '🖐', '✋',
    '🖖', '👌', '🤌', '🤏', '✍️', '🙏', '🤝', '👏', '🙌', '💪',
    '🦾', '🖕',
  ],
  'Hearts': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️',
  ],
  'Animals': [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐔', '🐧',
    '🐦', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝',
    '🐛', '🦋', '🐌', '🐞', '🐜',
  ],
  'Food': [
    '🍎', '🍊', '🍋', '🍇', '🍓', '🫐', '🍒', '🍑', '🥭', '🍍',
    '🥥', '🥝', '🍅', '🍆', '🥑', '🌽', '🌶️', '🍕', '🍔', '🍟',
    '🌮', '🌯', '🍜', '🍣', '🍺', '🥂', '🍷', '☕', '🧋', '🍰',
    '🎂', '🍩', '🍦',
  ],
  'Activities': [
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🎱', '🏓', '🏸',
    '🥊', '🏆', '🥇', '🎮', '🎯', '🎲', '🎭', '🎬', '🎤', '🎸',
    '🎹', '🎺', '🥁', '🎻',
  ],
  'Symbols': [
    '✅', '❌', '❓', '❗', '💯', '🔥', '⭐', '✨', '💥', '🎉',
    '🎊', '💢', '💦', '💨', '🌈', '☀️', '🌙', '⚡', '❄️', '🌊',
    '💤', '🔔', '📢', '📣', '🚀', '💡', '🔑', '💎', '🏠',
  ],
};

/// Inserts a floating reaction picker above or below [anchorOffset].
///
/// Returns the [OverlayEntry] so the caller can remove it at any time.
/// The entry removes itself after a successful emoji selection, after the
/// user taps the "+" button, or when the user taps the translucent barrier.
OverlayEntry insertReactionPicker({
  required BuildContext context,
  required Offset anchorOffset,
  required Size anchorSize,
  required Set<String> currentUserReactions,
  required void Function(String emoji) onEmojiSelected,
  required void Function() onMorePressed,
  required void Function() onDismiss,
}) {
  final screenSize = MediaQuery.of(context).size;
  final screenPadding = MediaQuery.of(context).viewPadding;

  // Picker dimensions (6 buttons × 48 px + horizontal padding)
  const pickerW = 316.0;
  const pickerH = 60.0;
  const gap = 6.0;

  // Center picker on the bubble, clamped to screen edges.
  double dx = anchorOffset.dx + anchorSize.width / 2 - pickerW / 2;
  dx = dx.clamp(8.0, screenSize.width - pickerW - 8.0);

  // Show above when the bubble is in the lower 55 % of the viewport.
  final double centerY = anchorOffset.dy + anchorSize.height / 2;
  final bool showAbove = centerY > screenSize.height * 0.55;

  double dy = showAbove
      ? anchorOffset.dy - pickerH - gap
      : anchorOffset.dy + anchorSize.height + gap;
  dy = dy.clamp(
    screenPadding.top + 8.0,
    screenSize.height - pickerH - 8.0,
  );

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ReactionPickerLayout(
      left: dx,
      top: dy,
      pickerWidth: pickerW,
      pickerHeight: pickerH,
      currentUserReactions: currentUserReactions,
      onEmojiSelected: (emoji) {
        entry.remove();
        onEmojiSelected(emoji);
      },
      onMorePressed: () {
        entry.remove();
        onMorePressed();
      },
      onBarrierTap: () {
        entry.remove();
        onDismiss();
      },
    ),
  );
  return entry;
}

class _ReactionPickerLayout extends StatefulWidget {
  const _ReactionPickerLayout({
    required this.left,
    required this.top,
    required this.pickerWidth,
    required this.pickerHeight,
    required this.currentUserReactions,
    required this.onEmojiSelected,
    required this.onMorePressed,
    required this.onBarrierTap,
  });

  final double left;
  final double top;
  final double pickerWidth;
  final double pickerHeight;
  final Set<String> currentUserReactions;
  final void Function(String emoji) onEmojiSelected;
  final VoidCallback onMorePressed;
  final VoidCallback onBarrierTap;

  @override
  State<_ReactionPickerLayout> createState() => _ReactionPickerLayoutState();
}

class _ReactionPickerLayoutState extends State<_ReactionPickerLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Barrier — full screen, dismisses picker on tap.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onBarrierTap,
              child: const SizedBox.expand(),
            ),
          ),

          // Floating picker card.
          Positioned(
            left: widget.left,
            top: widget.top,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  width: widget.pickerWidth,
                  height: widget.pickerHeight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2536),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(120),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withAlpha(22),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in kQuickReactionEmojis)
                        _EmojiButton(
                          emoji: emoji,
                          isActive:
                              widget.currentUserReactions.contains(emoji),
                          onTap: () => widget.onEmojiSelected(emoji),
                        ),
                      _MoreButton(onTap: widget.onMorePressed),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  final String emoji;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? const Color(0xFF7C7AFF).withAlpha(50)
              : Colors.transparent,
          border: isActive
              ? Border.all(color: const Color(0xFF7C7AFF), width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(18),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.add_rounded,
          color: Colors.white.withAlpha(200),
          size: 22,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full emoji picker — shown as a bottom sheet when user taps "+".
// ---------------------------------------------------------------------------

void showFullEmojiPicker({
  required BuildContext context,
  required Set<String> currentUserReactions,
  required void Function(String emoji) onEmojiSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FullEmojiSheet(
      currentUserReactions: currentUserReactions,
      onEmojiSelected: (emoji) {
        Navigator.of(context).pop();
        onEmojiSelected(emoji);
      },
    ),
  );
}

class _FullEmojiSheet extends StatefulWidget {
  const _FullEmojiSheet({
    required this.currentUserReactions,
    required this.onEmojiSelected,
  });

  final Set<String> currentUserReactions;
  final void Function(String emoji) onEmojiSelected;

  @override
  State<_FullEmojiSheet> createState() => _FullEmojiSheetState();
}

class _FullEmojiSheetState extends State<_FullEmojiSheet> {
  String _search = '';

  List<String> get _filteredEmojis {
    if (_search.isEmpty) return const [];
    final q = _search.toLowerCase();
    return kEmojiCategories.values
        .expand((e) => e)
        .where((e) => e.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.62,
      decoration: const BoxDecoration(
        color: Color(0xFF151C2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              autofocus: false,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search emoji…',
                hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                filled: true,
                fillColor: const Color(0xFF1E2536),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                prefixIcon:
                    Icon(Icons.search, color: Colors.white.withAlpha(120)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          Expanded(
            child: _search.isNotEmpty
                ? _buildSearchResults()
                : _buildCategoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filteredEmojis;
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No emoji found',
          style: TextStyle(color: Colors.white.withAlpha(120)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) => _EmojiGridCell(
        emoji: results[i],
        isActive: widget.currentUserReactions.contains(results[i]),
        onTap: () => widget.onEmojiSelected(results[i]),
      ),
    );
  }

  Widget _buildCategoryList() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final entry in kEmojiCategories.entries)
          _CategorySection(
            label: entry.key,
            emojis: entry.value,
            currentUserReactions: widget.currentUserReactions,
            onEmojiSelected: widget.onEmojiSelected,
          ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.label,
    required this.emojis,
    required this.currentUserReactions,
    required this.onEmojiSelected,
  });

  final String label;
  final List<String> emojis;
  final Set<String> currentUserReactions;
  final void Function(String emoji) onEmojiSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(140),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(
            spacing: 0,
            runSpacing: 0,
            children: [
              for (final emoji in emojis)
                _EmojiGridCell(
                  emoji: emoji,
                  isActive: currentUserReactions.contains(emoji),
                  onTap: () => onEmojiSelected(emoji),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmojiGridCell extends StatelessWidget {
  const _EmojiGridCell({
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  final String emoji;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: isActive
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C7AFF).withAlpha(45),
                border:
                    Border.all(color: const Color(0xFF7C7AFF), width: 1.2),
              )
            : null,
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
