import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.trendLabel,
    this.trendUp = true,
  });

  final String title;
  final String value;
  final String? subtitle;
  final String? trendLabel;
  final bool trendUp;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trendColor = trendUp ? AppTheme.success : AppTheme.danger;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(.11),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                if (trendLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: trendColor.withOpacity(.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: trendColor.withOpacity(.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(trendUp ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: trendColor),
                        const SizedBox(width: 4),
                        Text(
                          trendLabel!,
                          style: TextStyle(color: trendColor, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  Icon(Icons.more_horiz_rounded, color: Theme.of(context).colorScheme.outline),
              ],
            ),
            const SizedBox(height: 18),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 28)),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
