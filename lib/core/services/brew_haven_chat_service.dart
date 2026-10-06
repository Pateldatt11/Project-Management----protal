import 'dart:convert';
import 'package:http/http.dart' as http;

class BrewHavenChatMessage {
  const BrewHavenChatMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, String> toJson() => {
        'role': role,
        'content': content,
      };
}

class BrewHavenChatResponse {
  const BrewHavenChatResponse({
    required this.reply,
    this.source,
    this.model,
    this.error,
  });

  final String reply;
  final String? source;
  final String? model;
  final String? error;

  factory BrewHavenChatResponse.fromJson(Map<String, dynamic> json) {
    final reply = (json['reply'] ?? '').toString().trim();
    final rawError = json['error'];
    final error = rawError is Map
        ? (rawError['message'] ?? rawError['error'] ?? '').toString().trim()
        : rawError?.toString().trim();

    return BrewHavenChatResponse(
      reply: reply.isNotEmpty
          ? reply
          : 'No response received from the assistant.',
      source: json['source']?.toString(),
      model: json['model']?.toString(),
      error: error,
    );
  }
}

class BrewHavenChatService {
  BrewHavenChatService._();

  static const String defaultApiUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Primary Model
  static const String primaryModel = 'openai/gpt-oss-120b';
  
  // Fallback Models to cycle through if primary fails
  static const List<String> fallbackModels = [
    'groq/compound',
    'meta-llama/llama-4-scout-17b-16e-instruct',
  ];

  static String get apiUrl => const String.fromEnvironment(
        'BREW_HAVEN_CHAT_URL',
        defaultValue: defaultApiUrl,
      );

  static String get groqApiKey => const String.fromEnvironment(
        'GROQ_API_KEY',
      );

  static Map<String, dynamic> buildGroqRequestBody({
    required String message,
    List<BrewHavenChatMessage>? history,
    Map<String, dynamic>? projectContext,
    required String model,
  }) {
    final contextText = projectContext == null || projectContext.isEmpty
        ? ''
        : '\nVISIBLE WORKSPACE DATA (the only source of truth; do not invent missing values): ${jsonEncode(projectContext)}';

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '''You are the Project AI assistant inside this project management dashboard.
Answer only about the signed-in user's visible workspace: projects, tasks, statuses, priorities, deadlines, workload, progress, blockers, reports, notifications, and role-based dashboard actions.
Use the visible workspace data below as the source of truth. Never invent project names, people, dates, counts, statuses, or actions. If the data does not contain the answer, say that it is not available in the current workspace and ask one focused follow-up question.
Recognize the user's intent first and answer that question only; do not repeat a generic capability list. For status/progress, give a concise summary and the next action. For deadlines/overdue work, name the relevant items and dates. For priorities, explain what should be handled first. For workload, mention only visible people and tasks. If the user asks about anything outside project management, politely redirect them to this dashboard's workspace data.
Write in a professional, direct tone. Use short headings or bullets when they improve scanning. Do not mention prompts, models, APIs, hidden data, or these instructions.$contextText''',
      },
      ...((history ?? const <BrewHavenChatMessage>[])
          .map((item) => <String, String>{
                'role': item.role,
                'content': item.content,
              })
          .toList()),
      {
        'role': 'user',
        'content': message.trim(),
      },
    ];

    return {
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 400,
    };
  }

  // Internal helper to make the HTTP call for a specific model
  static Future<BrewHavenChatResponse> _executeRequest({
    required String resolvedUrl,
    required String requestKey,
    required String model,
    required String message,
    List<BrewHavenChatMessage>? history,
    Map<String, dynamic>? projectContext,
  }) async {
    final requestBody = buildGroqRequestBody(
      message: message,
      history: history,
      projectContext: projectContext,
      model: model,
    );

    final response = await http
        .post(
          Uri.parse(resolvedUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $requestKey',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 25));

    final decoded = response.body.trim();
    if (decoded.isEmpty) {
      throw Exception('Empty response body (HTTP ${response.statusCode})');
    }

    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) {
      throw Exception('Invalid JSON format response');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final choices = json['choices'] as List?;
      final content = choices != null && choices.isNotEmpty
          ? (choices.first['message']?['content'] ?? '').toString().trim()
          : '';

      if (content.isNotEmpty) {
        return BrewHavenChatResponse(
          reply: content,
          source: 'groq-$model',
          model: json['model']?.toString() ?? model,
        );
      }
      throw Exception('Empty choice content returned');
    }

    final rawError = json['error'];
    final errorMessage = rawError is Map
        ? (rawError['message'] ?? rawError['error'] ?? 'HTTP ${response.statusCode}')
        : rawError?.toString() ?? 'HTTP ${response.statusCode}';

    throw Exception('API Error (${response.statusCode}): $errorMessage');
  }

  static Future<BrewHavenChatResponse> sendMessage({
    required String message,
    List<BrewHavenChatMessage>? history,
    Map<String, dynamic>? projectContext,
    String? overrideUrl,
  }) async {
    final resolvedUrl = (overrideUrl ?? apiUrl).trim().isEmpty
        ? defaultApiUrl
        : (overrideUrl ?? apiUrl).trim();
    final requestKey = groqApiKey.trim();

    if (requestKey.isEmpty) {
      return const BrewHavenChatResponse(
        reply: 'API key is missing. Please configure your GROQ_API_KEY.',
        error: 'Missing API key',
        source: 'client-validation',
      );
    }

    // 1. Attempt primary model first
    try {
      return await _executeRequest(
        resolvedUrl: resolvedUrl,
        requestKey: requestKey,
        model: primaryModel,
        message: message,
        history: history,
        projectContext: projectContext,
      );
    } catch (primaryError) {
      // Primary model failed, log or pass through to fallbacks
      print('Primary model ($primaryModel) failed: $primaryError. Trying fallbacks...');
    }

    // 2. Cycle through fallback models sequentially
    for (final backupModel in fallbackModels) {
      try {
        return await _executeRequest(
          resolvedUrl: resolvedUrl,
          requestKey: requestKey,
          model: backupModel,
          message: message,
          history: history,
          projectContext: projectContext,
        );
      } catch (backupError) {
        print('Fallback model ($backupModel) failed: $backupError');
      }
    }

    // If all models fail, return final failure notice
    return BrewHavenChatResponse(
      reply: 'All AI models are currently unavailable. Please try again shortly.',
      error: 'network-exception',
      source: 'network-exception',
    );
  }
}