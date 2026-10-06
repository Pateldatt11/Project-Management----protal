import 'package:flutter/material.dart';

class ProgressChip extends StatelessWidget {
  const ProgressChip({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(value: value / 100, minHeight: 8),
          ),
        ),
        const SizedBox(width: 8),
        Text('$value%', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
