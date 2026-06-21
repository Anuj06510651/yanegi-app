import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/event_label.dart';

/// Ice-breaker prompt chips shown on an empty DM thread.
///
/// Derives up to 3 contextual conversation starters by checking:
///   1. Shared active events (both users are participants)
///   2. A mutual friend name
/// Remaining slots are filled from a curated generic pool.
///
/// Tapping a chip calls [onPromptSelected] so the parent can fill the
/// composer — no navigation, no backend write.
class IceBreakerPrompts extends StatefulWidget {
  const IceBreakerPrompts({
    super.key,
    required this.currentUserId,
    required this.peerUserId,
    required this.peerName,
    required this.onPromptSelected,
  });

  final String currentUserId;
  final String peerUserId;
  final String peerName;
  final void Function(String text) onPromptSelected;

  @override
  State<IceBreakerPrompts> createState() => _IceBreakerPromptsState();
}

class _IceBreakerPromptsState extends State<IceBreakerPrompts> {
  late Future<List<_Prompt>> _future;

  @override
  void initState() {
    super.initState();
    _future = _buildPrompts();
  }

  @override
  void didUpdateWidget(IceBreakerPrompts old) {
    super.didUpdateWidget(old);
    if (old.peerUserId != widget.peerUserId ||
        old.currentUserId != widget.currentUserId) {
      setState(() => _future = _buildPrompts());
    }
  }

  // ── Data fetching ──────────────────────────────────────────────────────────

  Future<List<_Prompt>> _buildPrompts() async {
    // Run all Firestore reads in parallel.
    final results = await Future.wait([
      _fetchActiveEventIds(widget.currentUserId),
      _fetchActiveEventIds(widget.peerUserId),
      _fetchFriendIds(widget.currentUserId),
      _fetchFriendIds(widget.peerUserId),
    ]);

    final myEventIds   = results[0];
    final peerEventIds = results[1];
    final myFriendIds  = results[2];
    final peerFriendIds = results[3];

    final sharedEventIds = myEventIds.intersection(peerEventIds);
    final mutualFriendIds = myFriendIds.intersection(peerFriendIds)
      ..remove(widget.currentUserId)
      ..remove(widget.peerUserId);

    final prompts = <_Prompt>[];

    // 1 — shared event prompt (fetch title of first shared event).
    if (sharedEventIds.isNotEmpty && prompts.length < 3) {
      final eventId = sharedEventIds.first;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .get();
        final title = (snap.data()?['title'] ?? '').toString().trim();
        if (title.isNotEmpty) {
          final label = EventLabel.of(eventId);
          prompts.add(_Prompt(
            emoji: '🎉',
            text: 'Hey! Going to $title too?',
            fillText: 'Hey! Going to $title too? 🎉',
          ));
          // Optionally add a second event-based prompt if we have room.
          if (prompts.length < 3) {
            prompts.add(_Prompt(
              emoji: '📍',
              text: 'See you at the $label?',
              fillText: 'See you at the $label? 👋',
            ));
          }
        }
      } catch (_) { /* non-fatal */ }
    }

    // 2 — mutual friend prompt.
    if (mutualFriendIds.isNotEmpty && prompts.length < 3) {
      try {
        final friendSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(mutualFriendIds.first)
            .get();
        final name = (friendSnap.data()?['name'] ??
                friendSnap.data()?['username'] ??
                '')
            .toString()
            .trim()
            .split(' ')
            .first;
        if (name.isNotEmpty) {
          prompts.add(_Prompt(
            emoji: '👀',
            text: 'I see we both know $name!',
            fillText: 'Hey! I see we both know $name — small world! 👀',
          ));
        }
      } catch (_) { /* non-fatal */ }
    }

    // 3 — fill remaining slots with generic starters.
    final generics = _genericPrompts(widget.peerName);
    // Shuffle generics deterministically using peerUserId as seed so the
    // same pair always sees the same generic prompts.
    final seed = widget.peerUserId.codeUnits.fold(0, (a, b) => a + b);
    final rng = math.Random(seed);
    generics.shuffle(rng);

    for (final g in generics) {
      if (prompts.length >= 3) break;
      // Don't add a duplicate fill-text.
      if (prompts.any((p) => p.fillText == g.fillText)) continue;
      prompts.add(g);
    }

    return prompts.take(3).toList();
  }

  Future<Set<String>> _fetchActiveEventIds(String uid) async {
    if (uid.isEmpty) return {};
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('users')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: const ['joined', 'active'])
          .limit(20)
          .get();
      return snap.docs
          .map((d) => d.reference.parent.parent?.id ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _fetchFriendIds(String uid) async {
    if (uid.isEmpty) return {};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friends')
          .doc(uid)
          .collection('list')
          .limit(50)
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }

  List<_Prompt> _genericPrompts(String peerName) {
    final first = peerName.split(' ').first;
    final hasName = first.isNotEmpty;
    return [
      _Prompt(emoji: '👋', text: hasName ? 'Hey $first!' : 'Hey there!',
          fillText: hasName ? 'Hey $first! 👋' : 'Hey there! 👋'),
      _Prompt(emoji: '🤙', text: "What's up?",
          fillText: "What's up? 🤙"),
      _Prompt(emoji: '✨', text: 'Nice to connect!',
          fillText: 'Nice to connect! ✨'),
      _Prompt(emoji: '😊', text: "How's it going?",
          fillText: "How's it going? 😊"),
      _Prompt(emoji: '🙌', text: "Let's link up!",
          fillText: "Let's link up! 🙌"),
      _Prompt(emoji: '🔥', text: "What are you up to?",
          fillText: "What are you up to? 🔥"),
    ];
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Prompt>>(
      future: _future,
      builder: (context, snapshot) {
        final prompts =
            snapshot.hasData ? snapshot.data! : const <_Prompt>[];

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wave icon
                const Text('👋', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  'Say hello!',
                  style: TextStyle(
                    color: Colors.white.withAlpha(220),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap a starter below or type your own',
                  style: TextStyle(
                    color: Colors.white.withAlpha(110),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Prompt chips — show shimmer placeholders while loading
                if (snapshot.connectionState == ConnectionState.waiting)
                  ..._buildShimmerChips()
                else
                  ...prompts.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PromptChip(
                        prompt: p,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onPromptSelected(p.fillText);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildShimmerChips() => List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _Prompt {
  const _Prompt({
    required this.emoji,
    required this.text,
    required this.fillText,
  });

  /// Short label shown on the chip.
  final String emoji;
  final String text;

  /// Full text inserted into the composer when tapped.
  final String fillText;
}

// ─────────────────────────────────────────────────────────────────────────────

class _PromptChip extends StatefulWidget {
  const _PromptChip({required this.prompt, required this.onTap});
  final _Prompt prompt;
  final VoidCallback onTap;

  @override
  State<_PromptChip> createState() => _PromptChipState();
}

class _PromptChipState extends State<_PromptChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.reverse(),
        onTapUp: (_) {
          _ctrl.forward();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.forward(),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF171D2A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF7C7AFF).withAlpha(60),
            ),
          ),
          child: Row(
            children: [
              Text(widget.prompt.emoji,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.prompt.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: const Color(0xFF7C7AFF).withAlpha(160),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
