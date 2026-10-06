import 'package:flutter/material.dart';

import 'sdui_editorial_preview_body.dart';
import 'sdui_floating_native_shell.dart';
import 'sdui_mobile_ui_config.dart';

/// Example only. Use this to verify the v62 shell before wiring real screens.
class SduiV62ExampleScreen extends StatefulWidget {
  const SduiV62ExampleScreen({super.key, required this.configJson});

  final Map<String, dynamic> configJson;

  @override
  State<SduiV62ExampleScreen> createState() => _SduiV62ExampleScreenState();
}

class _SduiV62ExampleScreenState extends State<SduiV62ExampleScreen> {
  String _tab = 'home';

  @override
  Widget build(BuildContext context) {
    final config = SduiMobileUiConfig.fromFirestore(widget.configJson);

    return SduiFloatingNativeShell(
      config: config,
      currentTab: _tab,
      unreadCount: 3,
      userInitials: 'D',
      onTabSelected: (tab) => setState(() => _tab = tab),
      onActiveTabRetap: () {
        // Connect this to your current tab ScrollController.animateTo(0).
      },
      onAction: (action) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action)));
      },
      child: SduiEditorialPreviewBody(config: config, currentTab: _tab),
    );
  }
}
