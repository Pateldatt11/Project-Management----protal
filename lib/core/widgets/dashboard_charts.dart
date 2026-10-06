import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class TrendPoint {
  const TrendPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class BarMetric {
  const BarMetric({required this.label, required this.value, this.total, this.color});
  final String label;
  final double value;
  final double? total;
  final Color? color;
}

class StatusSegment {
  const StatusSegment({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
}

class CompletionDonutChart extends StatelessWidget {
  const CompletionDonutChart({super.key, required this.completed, required this.total, this.size = 188});

  final int completed;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : completed / total;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: percent.clamp(0, 1)),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, animatedPercent, _) => SizedBox(
        height: size,
        width: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _CompletionDonutPainter(percent: animatedPercent, color: AppTheme.blue),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${(animatedPercent * 100).round()}%', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 34)),
                const SizedBox(height: 4),
                Text('$completed of $total done', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionDonutPainter extends CustomPainter {
  const _CompletionDonutPainter({required this.percent, required this.color});
  final double percent;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .105;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.slate200;
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(center, radius, basePaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, math.pi * 2 * percent.clamp(0, 1), false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _CompletionDonutPainter oldDelegate) => oldDelegate.percent != percent || oldDelegate.color != color;
}

class StatusDonutChart extends StatelessWidget {
  const StatusDonutChart({super.key, required this.segments});

  final List<StatusSegment> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, item) => sum + item.value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final chart = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) => SizedBox(
            height: 210,
            width: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(210),
                  painter: _StatusDonutPainter(segments: segments, progress: progress),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$total', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 30)),
                    Text('Tasks', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        );
        final legend = _StatusLegend(segments: segments, total: total);
        if (compact) {
          return Column(children: [chart, const SizedBox(height: 14), legend]);
        }
        return Row(children: [chart, const SizedBox(width: 18), Expanded(child: legend)]);
      },
    );
  }
}

class _StatusDonutPainter extends CustomPainter {
  const _StatusDonutPainter({required this.segments, required this.progress});
  final List<StatusSegment> segments;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<int>(0, (sum, item) => sum + item.value);
    final stroke = 24.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = AppTheme.slate200;
    canvas.drawCircle(center, radius, basePaint);
    if (total == 0) return;

    var start = -math.pi / 2;
    for (final segment in segments.where((segment) => segment.value > 0)) {
      final sweep = (segment.value / total) * math.pi * 2 * progress.clamp(0, 1);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = segment.color;
      final drawSweep = math.max(0.0, sweep - .035);
      if (drawSweep > 0) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, drawSweep, false, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StatusDonutPainter oldDelegate) => oldDelegate.segments != segments || oldDelegate.progress != progress;
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend({required this.segments, required this.total});
  final List<StatusSegment> segments;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: segments.map((segment) {
        final percentage = total == 0 ? 0 : ((segment.value / total) * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: segment.color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(segment.label, style: const TextStyle(fontWeight: FontWeight.w800))),
              Text('${segment.value}', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text('$percentage%', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class TrendLineChart extends StatelessWidget {
  const TrendLineChart({super.key, required this.points, this.height = 240});

  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TrendLinePainter(points: points, color: AppTheme.blue, textColor: AppTheme.muted, progress: progress),
        ),
      ),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({required this.points, required this.color, required this.textColor, required this.progress});
  final List<TrendPoint> points;
  final Color color;
  final Color textColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = const EdgeInsets.fromLTRB(36, 16, 18, 34);
    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );

    final gridPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
    }

    if (points.isEmpty) return;
    final maxValue = points.map((point) => point.value).fold<double>(1, (a, b) => a > b ? a : b);
    final stepX = points.length == 1 ? 0 : chartRect.width / (points.length - 1);

    Offset offsetFor(int index) {
      final value = points[index].value * progress.clamp(0, 1);
      final x = chartRect.left + stepX * index;
      final y = chartRect.bottom - (value / maxValue) * chartRect.height;
      return Offset(x, y);
    }

    final linePath = Path()..moveTo(offsetFor(0).dx, offsetFor(0).dy);
    for (var i = 1; i < points.length; i++) {
      final previous = offsetFor(i - 1);
      final current = offsetFor(i);
      final cp1 = Offset(previous.dx + stepX * .45, previous.dy);
      final cp2 = Offset(current.dx - stepX * .45, current.dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(chartRect.right, chartRect.bottom)
      ..lineTo(chartRect.left, chartRect.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(.22), color.withOpacity(.02)],
        ).createShader(chartRect),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    for (var i = 0; i < points.length; i++) {
      final point = offsetFor(i);
      final pointFill = Paint()..color = Colors.white;
      final pointStroke = Paint()
        ..color = color.withOpacity(.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(point, 4.5, pointFill);
      canvas.drawCircle(point, 4.5, pointStroke);
      _drawText(canvas, points[i].label, Offset(point.dx, chartRect.bottom + 16), textColor, 11, alignCenter: true);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double size, {bool alignCenter = false}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(alignCenter ? offset.dx - painter.width / 2 : offset.dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) => oldDelegate.points != points || oldDelegate.progress != progress;
}

class ProfessionalBarChart extends StatelessWidget {
  const ProfessionalBarChart({super.key, required this.items, this.valueSuffix = '', this.showPercentOfTotal = false});

  final List<BarMetric> items;
  final String valueSuffix;
  final bool showPercentOfTotal;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.map((item) => item.total ?? item.value).fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: items.map((item) {
        final color = item.color ?? Theme.of(context).colorScheme.primary;
        final percent = ((item.value / (item.total ?? maxValue).clamp(1, double.infinity)) * 100).clamp(0, 100);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(
                    showPercentOfTotal ? '${percent.round()}%' : '${item.value.round()}$valueSuffix',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Container(height: 12, color: AppTheme.slate200),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: (item.value / maxValue).clamp(0, 1)),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, widthFactor, _) => FractionallySizedBox(
                        widthFactor: widthFactor,
                        child: Container(height: 12, color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({super.key, required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.14)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
