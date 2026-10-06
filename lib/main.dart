import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'app/app.dart';
import 'app/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable verbose logging for debugging
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

  // Initialize OneSignal (replace with your actual App ID)
  OneSignal.initialize("e2475e54-448e-4067-9ceb-08cb4b8ff968");

  // Prompt for push notification permission
  OneSignal.Notifications.requestPermission(true);

  // Handle foreground notifications
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    event.notification.display();
  });

  // Handle notification click events
  OneSignal.Notifications.addClickListener((event) {
    debugPrint("Notification clicked data: ${event.notification.additionalData}");
  });

  return runProjectWorkspaceApp(child: const ProjectManagementDashboardApp());
}