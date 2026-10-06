import '../../core/utils/json_value.dart';

class Team {
  const Team({
    required this.teamId,
    required this.name,
    required this.leadId,
    required this.memberIds,
    required this.activeProjectIds,
    this.description = '',
  });

  final String teamId;
  final String name;
  final String leadId;
  final List<String> memberIds;
  final List<String> activeProjectIds;
  final String description;

  Team copyWith({
    String? name,
    String? leadId,
    List<String>? memberIds,
    List<String>? activeProjectIds,
    String? description,
  }) =>
      Team(
        teamId: teamId,
        name: name ?? this.name,
        leadId: leadId ?? this.leadId,
        memberIds: memberIds ?? this.memberIds,
        activeProjectIds: activeProjectIds ?? this.activeProjectIds,
        description: description ?? this.description,
      );

  factory Team.fromJson(Map<String, dynamic> json) => Team(
        teamId: JsonValue.string(json['teamId'] ?? json['id']),
        name: JsonValue.string(json['name'] ?? json['title'], fallback: 'Team'),
        leadId: JsonValue.string(json['leadId'] ?? json['lead']),
        memberIds: JsonValue.stringList(json['memberIds'] ?? json['members']),
        activeProjectIds: JsonValue.stringList(json['activeProjectIds'] ?? json['projectIds'] ?? json['projects']),
        description: JsonValue.string(json['description']),
      );

  Map<String, dynamic> toJson() => {
        'teamId': teamId,
        'name': name,
        'leadId': leadId,
        'memberIds': memberIds,
        'activeProjectIds': activeProjectIds,
        'description': description,
      };
}
