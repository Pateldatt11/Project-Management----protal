import 'package:flutter/material.dart';

import '../lib/employee_app/server_driven/sdui_firestore_config_service.dart';
import '../lib/employee_app/server_driven/sdui_floating_native_shell.dart';

/// Example integration only.
/// Replace the child Container with your real SDUI-rendered current tab body.
class MobileUiShellExample extends StatefulWidget {
  const MobileUiShellExample({
    super.key,
    required this.companyId,
  });

  final String companyId;

  @override
  State<MobileUiShellExample> createState() => _MobileUiShellExampleState();
}

class _MobileUiShellExampleState extends State<MobileUiShellExample> {
  late final SduiFirestoreConfigService _service;
  String _tab = 'home';

  @override
  void initState() {
    super.initState();
    _service = SduiFirestoreConfigService(companyId: widget.companyId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _service.watchActiveConfig(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Failed to load mobile UI config: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: Text('Mobile UI config not found.')));
        }

        final config = snapshot.data!;

        return SduiFloatingNativeShell(
          config: config,
          currentTab: _tab,
          unreadCount: 0,
          onTabSelected: (tab) => setState(() => _tab = tab),
          onActiveTabRetap: () {},
          onAction: (action) {},
          child: Container(), // Replace with your SDUI-rendered current tab body.
        );
      },
    );
  }
}
