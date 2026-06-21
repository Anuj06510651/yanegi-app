import 'package:flutter/material.dart';

import '../services/arrival_status_service.dart';

/// Three-pill row pinned above the composer for event group chats.
/// Tap → write status to participant doc (debounced inside the service).
/// Visual state echoes the current selection so users don't have to wait
/// for the participants snapshot to round-trip.
class ArrivalStatusStrip extends StatefulWidget {
  const ArrivalStatusStrip({
    super.key,
    required this.eventId,
    required this.currentStatus,
    this.service,
  });

  final String eventId;
  final ArrivalStatus currentStatus;
  final ArrivalStatusService? service;

  @override
  State<ArrivalStatusStrip> createState() => _ArrivalStatusStripState();
}

class _ArrivalStatusStripState extends State<ArrivalStatusStrip> {
  late ArrivalStatusService _service;
  ArrivalStatus? _optimistic;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ArrivalStatusService();
  }

  @override
  void didUpdateWidget(covariant ArrivalStatusStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the live participants snapshot catches up, drop the optimistic tint.
    if (_optimistic != null && widget.currentStatus == _optimistic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _optimistic = null);
      });
    }
  }

  ArrivalStatus get _effective => _optimistic ?? widget.currentStatus;

  Future<void> _tap(ArrivalStatus next) async {
    // Toggle off if user taps the active pill.
    final target = _effective == next ? ArrivalStatus.none : next;
    setState(() => _optimistic = target);
    await _service.setStatus(eventId: widget.eventId, status: target);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _effective;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _StatusPill(
              emoji: '🚶',
              label: 'On my way',
              selected: selected == ArrivalStatus.onMyWay,
              onTap: () => _tap(ArrivalStatus.onMyWay),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatusPill(
              emoji: '📍',
              label: 'Reached',
              selected: selected == ArrivalStatus.arrived,
              onTap: () => _tap(ArrivalStatus.arrived),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatusPill(
              emoji: '⏳',
              label: 'Late',
              selected: selected == ArrivalStatus.runningLate,
              onTap: () => _tap(ArrivalStatus.runningLate),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? accent.withAlpha(48) : Colors.white.withAlpha(14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent.withAlpha(180) : Colors.white.withAlpha(30),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white.withAlpha(200),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
