import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKeyDontAsk = 'app_rating_dont_ask';
const _prefKeyLastAsked = 'app_rating_last_asked_ms';
const _playStoreId = 'com.yanegi.app';

/// Returns true if we should show the rating dialog.
Future<bool> shouldShowAppRating() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_prefKeyDontAsk) == true) return false;
  final last = prefs.getInt(_prefKeyLastAsked) ?? 0;
  // Don't ask more than once every 7 days
  final daysSince = (DateTime.now().millisecondsSinceEpoch - last) / 86400000;
  return daysSince >= 7;
}

Future<void> _markAsked() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
      _prefKeyLastAsked, DateTime.now().millisecondsSinceEpoch);
}

Future<void> _markDontAsk() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKeyDontAsk, true);
}

/// Shows the app rating bottom sheet.
/// Call after first event is successfully created.
void showAppRatingSheet(BuildContext context) {
  _markAsked();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AppRatingSheet(),
  );
}

class _AppRatingSheet extends StatefulWidget {
  const _AppRatingSheet();

  @override
  State<_AppRatingSheet> createState() => _AppRatingSheetState();
}

class _AppRatingSheetState extends State<_AppRatingSheet> {
  int _stars = 0;

  Future<void> _rateNow() async {
    HapticFeedback.mediumImpact();
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing(appStoreId: _playStoreId);
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _maybeLater() {
    Navigator.of(context).pop();
  }

  Future<void> _dontAsk() async {
    await _markDontAsk();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, bottom + 24),
      decoration: const BoxDecoration(
        color: Color(0xFF141926),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // App icon + confetti feel
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B82F6), Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withAlpha(80),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Text('🎉', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'You just dropped your first event!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Loving Yanegi? A quick rating helps us reach more people.',
            style: TextStyle(
              color: Colors.white.withAlpha(160),
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 5-star selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _stars = i + 1);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 40,
                    color: filled
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withAlpha(60),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),

          // Rate Now button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _stars > 0 ? _rateNow : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                disabledBackgroundColor: Colors.white.withAlpha(20),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _stars > 0 ? 'Rate on Play Store ★' : 'Tap a star first',
                style: TextStyle(
                  color: _stars > 0 ? Colors.white : Colors.white.withAlpha(80),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Maybe Later + Don't Ask
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _maybeLater,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withAlpha(130),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Maybe later'),
                ),
              ),
              Container(
                  width: 1, height: 20, color: Colors.white.withAlpha(20)),
              Expanded(
                child: TextButton(
                  onPressed: _dontAsk,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withAlpha(80),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Don't ask again"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
