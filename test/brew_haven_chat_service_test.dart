import 'package:flutter_test/flutter_test.dart';
import 'package:project_management_dashboard/core/services/brew_haven_chat_service.dart';

void main() {
  test('chat message history is converted to API payload shape', () {
    final history = [
      BrewHavenChatMessage(role: 'user', content: 'hello'),
      BrewHavenChatMessage(role: 'assistant', content: 'hi there'),
    ];

    final payload = BrewHavenChatService.buildRequestBody(
      message: 'How much is a cappuccino?',
      history: history,
    );

    expect(payload?['message'], 'How much is a cappuccino?');
    expect(payload['history'], isA<List>());
    expect(payload['history'][0]['role'], 'user');
    expect(payload['history'][1]['content'], 'hi there');
  });
}

extension on Object? {
  operator [](String other) {}
}
