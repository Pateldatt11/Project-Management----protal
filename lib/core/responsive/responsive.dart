import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class Responsive {
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= AppConstants.desktopBreakpoint;
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppConstants.tabletBreakpoint && width < AppConstants.desktopBreakpoint;
  }
  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < AppConstants.tabletBreakpoint;
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minTileWidth = 240, this.spacing = 16});

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: children
              .map((child) => SizedBox(
                    width: (constraints.maxWidth - spacing * (count - 1)) / count,
                    child: child,
                  ))
              .toList(),
        );
      },
    );
  }
}
