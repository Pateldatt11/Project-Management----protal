import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:project_management_dashboard/app/app.dart';

void main() {
  testWidgets('Project management dashboard opens in demo mode', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ProjectManagementDashboardApp()));
    await tester.pumpAndSettle();
    expect(find.text('Project Management OS'), findsOneWidget);
  });
}
