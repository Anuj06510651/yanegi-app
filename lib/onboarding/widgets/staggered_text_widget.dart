import 'package:flutter/material.dart';
import 'package:yanegi/theme/yanegi_theme.dart';
import 'dart:async';

class StaggeredTextWidget extends StatefulWidget {
  final List<String> lines;
  final Duration lineDelay;
  final Duration animationDuration;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry linePadding;
  final CrossAxisAlignment crossAxisAlignment;

  const StaggeredTextWidget(
    this.lines, {
    super.key,
    this.lineDelay = const Duration(milliseconds: 400),
    this.animationDuration = const Duration(milliseconds: 300),
    this.textStyle,
    this.linePadding = const EdgeInsets.only(bottom: 6),
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  State<StaggeredTextWidget> createState() => _StaggeredTextWidgetState();
}

class _StaggeredTextWidgetState extends State<StaggeredTextWidget> {
  late List<bool> _visibleLines;
  Timer? _revealTimer;
  int _nextRevealIndex = 0;

  @override
  void initState() {
    super.initState();
    _visibleLines = List<bool>.filled(widget.lines.length, false);
    _startReveal();
  }

  @override
  void didUpdateWidget(covariant StaggeredTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines != widget.lines) {
      _revealTimer?.cancel();
      _nextRevealIndex = 0;
      _visibleLines = List<bool>.filled(widget.lines.length, false);
      _startReveal();
    }
  }

  void _startReveal() {
    if (widget.lines.isEmpty) return;

    _revealTimer = Timer.periodic(widget.lineDelay, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_nextRevealIndex >= widget.lines.length) {
        timer.cancel();
        return;
      }

      setState(() {
        _visibleLines[_nextRevealIndex] = true;
      });

      _nextRevealIndex++;
      if (_nextRevealIndex >= widget.lines.length) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = widget.textStyle ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: YanegiColors.textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w500,
            );

    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: List.generate(widget.lines.length, (index) {
        final visible = _visibleLines[index];
        return Padding(
          padding: widget.linePadding,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.3),
            duration: widget.animationDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: widget.animationDuration,
              curve: Curves.easeOutCubic,
              child: Text(
                widget.lines[index],
                style: resolvedStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }),
    );
  }
}
