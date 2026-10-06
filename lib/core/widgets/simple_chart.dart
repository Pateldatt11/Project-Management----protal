import 'package:flutter/material.dart';

class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({super.key, required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          final heightFactor = values[index] / maxValue;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: heightFactor,
                        widthFactor: .78,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(.82),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(labels[index], style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
