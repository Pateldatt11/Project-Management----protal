import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

/// Small live timer chip for task deadline countdowns.
///
/// Stability note: this widget used to create one Timer per visible task card.
/// On SDUI pages with many task cards that caused many second-by-second rebuilds
/// and could crash low-RAM emulators/APKs after short use. All chips now share one
/// bounded ticker and rebuild at a lighter cadence.
class DeadlineCountdownChip extends StatefulWidget {
  const DeadlineCountdownChip({
    super.key,
    required this.deadline,
    this.completed = false,
    this.compact = false,
  });

  final DateTime deadline;
  final bool completed;
  final bool compact;

  @override
  State<DeadlineCountdownChip> createState() => _DeadlineCountdownChipState();
}

class _DeadlineCountdownChipState extends State<DeadlineCountdownChip> {
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _DeadlineTicker.add(_onTick);
  }

  @override
  void dispose() {
    _DeadlineTicker.remove(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() => _now = _DeadlineTicker.now.value);
  }

  @override
  Widget build(BuildContext context) {
    final info = _deadlineInfo(widget.deadline, _now, widget.completed);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 9 : 11, vertical: widget.compact ? 6 : 8),
      decoration: BoxDecoration(
        color: info.color.withOpacity(.08),
        border: Border.all(color: info.color.withOpacity(.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: widget.compact ? 14 : 16, color: info.color),
          const SizedBox(width: 6),
          Text(
            info.label,
            style: TextStyle(
              fontSize: widget.compact ? 11 : 12,
              color: info.color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static _DeadlineInfo _deadlineInfo(DateTime deadline, DateTime now, bool completed) {
    if (completed) {
      return const _DeadlineInfo(label: 'Completed', color: AppTheme.success, icon: Icons.check_circle_rounded);
    }
    final difference = deadline.difference(now);
    final overdue = difference.isNegative;
    final duration = overdue ? now.difference(deadline) : difference;
    final label = overdue ? 'Overdue ${_formatDuration(duration)}' : '${_formatDuration(duration)} left';
    final color = overdue
        ? AppTheme.danger
        : duration.inHours < 24
            ? AppTheme.warning
            : AppTheme.blue;
    return _DeadlineInfo(label: label, color: color, icon: overdue ? Icons.warning_amber_rounded : Icons.timer_rounded);
  }

  static String _formatDuration(Duration duration) {
    if (duration.inDays >= 2) return '${duration.inDays}d ${duration.inHours.remainder(24)}h';
    if (duration.inDays == 1) return '1d ${duration.inHours.remainder(24)}h';
    if (duration.inHours >= 1) return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    if (duration.inMinutes >= 1) return '${duration.inMinutes}m left';
    return '<1m';
  }
}

class _DeadlineTicker {
  static final ValueNotifier<DateTime> now = ValueNotifier<DateTime>(DateTime.now());
  static Timer? _timer;
  static int _listenerCount = 0;

  static void add(VoidCallback listener) {
    _listenerCount += 1;
    now.addListener(listener);
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      now.value = DateTime.now();
    });
  }

  static void remove(VoidCallback listener) {
    now.removeListener(listener);
    _listenerCount = ((_listenerCount - 1).clamp(0, 1 << 20)).toInt();
    if (_listenerCount == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

class _DeadlineInfo {
  const _DeadlineInfo({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;
}
