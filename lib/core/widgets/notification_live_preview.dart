import 'package:flutter/material.dart';

class NotificationLivePreview extends StatelessWidget {
  final String appName;
  final String timeLabel;
  final String taskTitle;
  final String priority;
  final String badgeLabel;
  final String assignerName;
  final String assigneeName;
  final String projectName;
  final String teamName;
  final String description;
  final String estimatedHours;
  final String dueDate;
  final String? meetingLink;
  final bool adminMeetingAccess;
  final bool isSenderAdmin;

  const NotificationLivePreview({
    super.key,
    this.appName = 'SyncTask',
    this.timeLabel = 'Just now',
    required this.taskTitle,
    required this.priority,
    this.badgeLabel = 'Assignment',
    required this.assignerName,
    required this.assigneeName,
    required this.projectName,
    required this.teamName,
    required this.description,
    required this.estimatedHours,
    required this.dueDate,
    this.meetingLink,
    this.adminMeetingAccess = true,
    this.isSenderAdmin = true,
  });

  Color _getPriorityColor(String prio) {
    switch (prio.toLowerCase()) {
      case 'urgent':
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      case 'low':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanTitle = taskTitle.trim().isEmpty ? 'Untitled Task' : taskTitle.trim();
    final cleanDesc = description.trim().isEmpty ? 'No description provided' : description.trim();
    final cleanHours = estimatedHours.trim().isEmpty ? '0' : estimatedHours.trim();
    final cleanDueDate = dueDate.trim().isEmpty ? 'No date' : dueDate.trim();
    final cleanTeam = teamName.trim().isEmpty ? 'General' : teamName.trim();
    final hasMeeting = (meetingLink ?? '').trim().isNotEmpty;
    final priorityColor = _getPriorityColor(priority);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F131C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Icon + App Name + Timestamp + Chevron
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• $timeLabel',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.white38),
            ],
          ),
          const SizedBox(height: 16),

          // Title & Priority Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: priorityColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    children: [
                      TextSpan(text: '$badgeLabel: '),
                      TextSpan(text: cleanTitle),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '[$priority]',
                        style: TextStyle(color: priorityColor, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Assignment Context Line
          Text(
            '$assignerName assigned $cleanTitle to $assigneeName in $projectName.',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),

          // Description Line
          Text(
            'Description: $cleanDesc',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),

          // Est. Time & Due Date Cards
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                      ),
                      child: const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Est. Time', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        Text('${cleanHours}h', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                      ),
                      child: const Icon(Icons.calendar_today_rounded, size: 15, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Due Date', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        Text(cleanDueDate, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Team Line
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13.5, color: Colors.white),
              children: [
                const TextSpan(text: 'Team: ', style: TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(
                  text: cleanTeam,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Meeting Link (Only if entered)
          if (hasMeeting) ...[
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13.5, color: Colors.white),
                children: [
                  const TextSpan(text: 'Meeting Link: ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                    text: meetingLink!.trim(),
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Admin Access (Only if meeting exists & sender is admin)
          if (hasMeeting && isSenderAdmin) ...[
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13.5, color: Colors.white),
                children: [
                  const TextSpan(text: 'Admin Meeting Access: ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                    text: adminMeetingAccess ? '(Checkbox checked in form)' : '(Disabled)',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Buttons
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181C26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.reply_rounded, size: 16, color: Colors.white70),
                      SizedBox(width: 8),
                      Text('Reply', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility_outlined, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Text('View Task', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Spacer(),
                      Icon(Icons.auto_awesome, size: 16, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}