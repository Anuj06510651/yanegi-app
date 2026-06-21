import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'tutorial_v1_seen';

Future<bool> shouldShowTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefKey) != true;
}

Future<void> markTutorialSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKey, true);
}

class FirstLaunchTutorial extends StatefulWidget {
  final VoidCallback onDone;
  const FirstLaunchTutorial({super.key, required this.onDone});

  @override
  State<FirstLaunchTutorial> createState() => _FirstLaunchTutorialState();
}

class _FirstLaunchTutorialState extends State<FirstLaunchTutorial>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  static const _steps = [
    _TutorialStep(
      emoji: '🗺️',
      title: 'Your social map',
      body:
          'Events near you appear as emoji pins. Tap any pin to see what\'s happening and join in.',
      anchorAlignment: Alignment.center,
      spotlightOffset: Offset(0, -0.05),
    ),
    _TutorialStep(
      emoji: '➕',
      title: 'Create an event',
      body:
          'Tap the blue + button at the bottom to drop your own event on the map — a game, a hangout, anything.',
      anchorAlignment: Alignment.bottomCenter,
      spotlightOffset: Offset(0, 0.38),
    ),
    _TutorialStep(
      emoji: '🧭',
      title: 'Explore nearby',
      body:
          'The compass tab shows ranked events around you. Scroll, filter, and join with one tap.',
      anchorAlignment: Alignment.bottomCenter,
      spotlightOffset: Offset(-0.25, 0.38),
    ),
    _TutorialStep(
      emoji: '👤',
      title: 'Your profile',
      body:
          'Set up your profile so others know who\'s coming. Tap the person icon to get started.',
      anchorAlignment: Alignment.bottomCenter,
      spotlightOffset: Offset(0.35, 0.38),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _next() async {
    await _anim.reverse();
    if (!mounted) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      _anim.forward();
    } else {
      await markTutorialSeen();
      widget.onDone();
    }
  }

  void _skip() async {
    await markTutorialSeen();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final size = MediaQuery.of(context).size;
    final isLast = _step == _steps.length - 1;

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Dark scrim
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(160)),
          ),

          // Spotlight glow around the anchored element
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                center: Offset(
                  size.width * 0.5 +
                      step.spotlightOffset.dx * size.width * 0.5,
                  size.height * 0.5 +
                      step.spotlightOffset.dy * size.height * 0.5,
                ),
                radius: 54,
              ),
            ),
          ),

          // Card — anchored based on step
          Positioned(
            left: 20,
            right: 20,
            bottom: step.anchorAlignment == Alignment.bottomCenter
                ? size.height * 0.18
                : null,
            top: step.anchorAlignment == Alignment.center
                ? size.height * 0.28
                : null,
            child: _TutorialCard(
              step: step,
              stepIndex: _step,
              totalSteps: _steps.length,
              isLast: isLast,
              onNext: _next,
              onSkip: _skip,
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  final _TutorialStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF161C2A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(step.emoji, style: const TextStyle(fontSize: 28)),
              const Spacer(),
              // Step dots
              Row(
                children: List.generate(totalSteps, (i) {
                  final active = i == stepIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF3B82F6)
                          : Colors.white.withAlpha(50),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: TextStyle(
              color: Colors.white.withAlpha(190),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (!isLast)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withAlpha(130),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Skip'),
                ),
              const Spacer(),
              GestureDetector(
                onTap: onNext,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    isLast ? 'Get started 🚀' : 'Next',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset center;
  final double radius;
  const _SpotlightPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3B82F6).withAlpha(55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(center, radius, paint);
    // Bright ring
    final ring = Paint()
      ..color = const Color(0xFF3B82F6).withAlpha(120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 4, ring);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}

class _TutorialStep {
  final String emoji;
  final String title;
  final String body;
  final Alignment anchorAlignment;
  final Offset spotlightOffset;

  const _TutorialStep({
    required this.emoji,
    required this.title,
    required this.body,
    required this.anchorAlignment,
    required this.spotlightOffset,
  });
}
