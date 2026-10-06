import 'package:project_management_dashboard/core/services/brew_haven_chat_service.dart';

class BrewHavenChatMessage {
  final String role;
  final String content;

  BrewHavenChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

class BrewHavenChatService {
  /// Builds the request body payload for chat API requests.
  static Map<String, dynamic> buildRequestBody({
    required String message,
    required List<BrewHavenChatMessage> history,
  }) {
    return {
      'message': message,
      'history': history.map((msg) => msg.toJson()).toList(),
    };
  }
}