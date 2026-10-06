import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/workspace_state.dart';
import '../services/brew_haven_chat_service.dart';

class BrewHavenChatLauncher extends StatelessWidget {
  const BrewHavenChatLauncher({super.key}) : topAligned = false;

  const BrewHavenChatLauncher.topAligned({super.key}) : topAligned = true;

  final bool topAligned;

  @override
  Widget build(BuildContext context) {
    if (topAligned) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) => const BrewHavenChatSheet(),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2E8DE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F1B12),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_rounded, color: Color(0xFF557847), size: 19),
                SizedBox(width: 8),
                Text(
                  'Project AI',
                  style: TextStyle(
                    color: Color(0xFF557847),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      scale: 1,
      child: FloatingActionButton.extended(
        heroTag: 'brew_haven_chat_fab',
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (sheetContext) => const BrewHavenChatSheet(),
          );
        },
        icon: const Icon(Icons.smart_toy_rounded),
        label: const Text('Project AI'),
        backgroundColor: const Color(0xFF1B6DFF),
      ),
    );
  }
}

class BrewHavenChatSheet extends ConsumerStatefulWidget {
  const BrewHavenChatSheet({super.key});

  @override
  ConsumerState<BrewHavenChatSheet> createState() =>
      _BrewHavenChatSheetState();
}

class _BrewHavenChatSheetState extends ConsumerState<BrewHavenChatSheet> {
  final TextEditingController _textController = TextEditingController();
  bool _sending = false;

  List<_ChatMessage> get _initialMessages => [
        _ChatMessage(
          role: 'assistant',
          text:
              'Hi! I’m your project assistant. I can help with project status, team workload, task priorities, and deadlines.',
        ),
      ];

  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.addAll(_initialMessages);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    final userMessage = _ChatMessage(role: 'user', text: text);
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _textController.clear();
    });

    final history = _messages
        .where((item) => item.role != 'system')
        .map((item) => BrewHavenChatMessage(
              role: item.role,
              content: item.text,
            ))
        .toList();

    final state = ref.read(workspaceProvider);
    final projectContext = <String, dynamic>{
      'userName': state.currentMember.displayName,
      'role': state.currentMember.role.name,
      'projectNames':
          state.visibleProjects.take(5).map((project) => project.name).toList(),
      'taskTitles':
          state.visibleTasks.take(5).map((task) => task.title).toList(),
      'summary':
          'Active projects: ${state.visibleProjects.length}. Visible tasks: ${state.visibleTasks.length}. Current member: ${state.currentMember.displayName}.',
    };

    final result = await BrewHavenChatService.sendMessage(
      message: text,
      history: history,
      projectContext: projectContext,
    );

    if (!mounted) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'assistant', text: result.reply));
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInsets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          return Container(
            height: maxHeight * 0.82,
            margin: EdgeInsets.only(
                bottom: keyboardInsets > 0 ? keyboardInsets : 0),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 6,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B6DFF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.assessment_rounded,
                            color: Color(0xFF1B6DFF)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Project AI Assistant',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                            Text(
                              'Tasks, deadlines, workload & project status',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF607080),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.role == 'user';

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF1B6DFF)
                                : const Color(0xFFF3F7FF),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: isUser
                                  ? Colors.white
                                  : const Color(0xFF1D2A39),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        SizedBox(width: 10),
                        Text('Project AI is thinking...',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: InputDecoration(
                            hintText:
                                'Ask about tasks, project status, or deadlines...',
                            filled: true,
                            fillColor: const Color(0xFFF4F7FB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF1B6DFF),
                        ),
                        child: IconButton(
                          onPressed: _sending ? null : _sendMessage,
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;
}
