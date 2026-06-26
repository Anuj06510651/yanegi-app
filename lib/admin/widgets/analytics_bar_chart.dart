import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/yanegi_theme.dart';
import '../models/admin_daily_stat.dart';
import 'admin_empty_state.dart';

/// A self-contained bar chart for daily stat data.
/// Implemented with CustomPainter — no external chart library required.
class AdminBarChart extends StatelessWidget {
  final List<AdminDailyStat> data;
  final String label;
  final Color barColor;

  const AdminBarChart({
    super.key,
    required this.data,
    required this.label,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return AdminEmptyState(message: 'No data for $label');
    }

    final maxVal = data.map((s) => s.count).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: YanegiColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _BarPainter(
              data: data,
              maxVal: maxVal == 0 ? 1 : maxVal,
              barColor: barColor,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        _XAxisLabels(data: data),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<AdminDailyStat> data;
  final int maxVal;
  final Color barColor;

  const _BarPainter({
    required this.data,
    required this.maxVal,
    required this.barColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = data.length;
    if (n == 0) return;

    final slotW = size.width / n;
    final barW = slotW * 0.55;
    final availH = size.height - 20; // reserve 20px for top labels

    final labelStyle = TextStyle(
      color: YanegiColors.textTertiary.withAlpha(200),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Horizontal gridline at max value
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 0), Offset(size.width, 0), gridPaint);

    for (var i = 0; i < n; i++) {
      final barH = (data[i].count / maxVal) * availH;
      final x = i * slotW + (slotW - barW) / 2;
      final y = size.height - barH;

      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, y, barW, barH),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );

      // Bar fill with gradient
      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [barColor, barColor.withAlpha(160)],
        ).createShader(Rect.fromLTWH(x, y, barW, barH))
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rrect, gradientPaint);

      // Value label above bar (only if > 0)
      if (data[i].count > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${data[i].count}', style: labelStyle),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x + barW / 2 - tp.width / 2, y - tp.height - 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.data != data || old.maxVal != maxVal || old.barColor != barColor;
}

class _XAxisLabels extends StatelessWidget {
  final List<AdminDailyStat> data;

  const _XAxisLabels({required this.data});

  @override
  Widget build(BuildContext context) {
    // Show every other label if there are many data points to avoid crowding
    final showEvery = data.length > 7 ? 2 : 1;

    return Row(
      children: List.generate(data.length, (i) {
        final label = i % showEvery == 0
            ? DateFormat('d/M').format(data[i].date)
            : '';
        return Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: YanegiColors.textTertiary,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    );
  }
}
