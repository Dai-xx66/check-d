import 'dart:convert';

/// The model proposes these bounded actions; existing repositories execute them.
/// No action accepts SQL, code, account identifiers, or fabricated timer facts.
const agentActions = <String>{
  'create_task',
  'update_task',
  'archive_task',
  'reschedule_task',
  'create_course',
  'update_course',
  'archive_course',
  'update_course_day',
  'create_plan',
  'update_plan',
  'archive_plan',
  'create_tag',
  'update_tag',
  'archive_tag',
  'upsert_goal',
  'archive_goal',
  'update_profile',
  'add_busy_period',
  'remove_busy_period',
  'record_feedback',
  'save_review',
};

class AgentOperation {
  const AgentOperation({
    required this.action,
    this.entityId,
    this.data = const {},
  });
  final String action;
  final String? entityId;
  final Map<String, Object?> data;

  factory AgentOperation.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => !{'action', 'entityId', 'data'}.contains(key)) ||
        !agentActions.contains(json['action']) ||
        (json['entityId'] != null && json['entityId'] is! String) ||
        (json['data'] != null && json['data'] is! Map)) {
      throw const FormatException('智能体返回了不支持的操作，请重试或补充要求。');
    }
    return AgentOperation(
      action: json['action'] as String,
      entityId: json['entityId'] as String?,
      data: Map<String, Object?>.from(json['data'] as Map? ?? const {}),
    );
  }
  Map<String, Object?> toJson() => {
    'action': action,
    if (entityId != null) 'entityId': entityId,
    'data': data,
  };
}

class AgentProposal {
  const AgentProposal({
    required this.id,
    required this.reply,
    required this.contextRevision,
    this.operations = const [],
    this.questions = const [],
    this.warnings = const [],
  });
  final String id, reply, contextRevision;
  final List<AgentOperation> operations;
  final List<String> questions, warnings;
  bool get hasChanges => operations.isNotEmpty;

  factory AgentProposal.fromJson(Map<String, dynamic> json) {
    final operations = json['operations'] as List? ?? const [];
    if (operations.length > 80 ||
        json['reply'] is! String ||
        json['id'] is! String ||
        json['contextRevision'] is! String) {
      throw const FormatException('智能体提案格式不完整，尚未修改数据。');
    }
    return AgentProposal(
      id: json['id'] as String,
      reply: json['reply'] as String,
      contextRevision: json['contextRevision'] as String,
      operations: operations
          .map(
            (item) =>
                AgentOperation.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      questions: (json['questions'] as List? ?? const []).cast<String>(),
      warnings: (json['warnings'] as List? ?? const []).cast<String>(),
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'reply': reply,
    'contextRevision': contextRevision,
    'operations': operations.map((op) => op.toJson()).toList(),
    'questions': questions,
    'warnings': warnings,
  };
}

class AgentChatMessage {
  const AgentChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });
  final String role, text;
  final DateTime createdAt;
  factory AgentChatMessage.fromJson(Map<String, dynamic> json) =>
      AgentChatMessage(
        role: json['role'] == 'user' ? 'user' : 'assistant',
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
  Map<String, Object?> toJson() => {
    'role': role,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };
}

class AgentWorkspace {
  const AgentWorkspace({
    this.profile = const {},
    this.goals = const [],
    this.messages = const [],
    this.busyPeriods = const [],
    this.feedback = const [],
    this.history = const [],
    this.notices = const [],
    this.taskLinks = const [],
  });
  final Map<String, Object?> profile;
  final List<Map<String, Object?>> goals,
      busyPeriods,
      feedback,
      history,
      notices,
      taskLinks;
  final List<AgentChatMessage> messages;
  factory AgentWorkspace.fromJson(Map<String, dynamic> json) {
    List<Map<String, Object?>> maps(String key) =>
        (json[key] as List? ?? const [])
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList();
    return AgentWorkspace(
      profile: Map<String, Object?>.from(json['profile'] as Map? ?? const {}),
      goals: maps('goals'),
      busyPeriods: maps('busyPeriods'),
      feedback: maps('feedback'),
      history: maps('history'),
      notices: maps('notices'),
      taskLinks: maps('taskLinks'),
      messages: (json['messages'] as List? ?? const [])
          .map(
            (row) => AgentChatMessage.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
  Map<String, Object?> toJson() => {
    'profile': profile,
    'goals': goals,
    'busyPeriods': busyPeriods,
    'feedback': feedback,
    'history': history,
    'notices': notices,
    'taskLinks': taskLinks,
    'messages': messages.map((message) => message.toJson()).toList(),
  };
  AgentWorkspace copyWith({
    Map<String, Object?>? profile,
    List<Map<String, Object?>>? goals,
    List<AgentChatMessage>? messages,
    List<Map<String, Object?>>? busyPeriods,
    List<Map<String, Object?>>? feedback,
    List<Map<String, Object?>>? history,
    List<Map<String, Object?>>? notices,
    List<Map<String, Object?>>? taskLinks,
  }) => AgentWorkspace(
    profile: profile ?? this.profile,
    goals: goals ?? this.goals,
    messages: messages ?? this.messages,
    busyPeriods: busyPeriods ?? this.busyPeriods,
    feedback: feedback ?? this.feedback,
    history: history ?? this.history,
    notices: notices ?? this.notices,
    taskLinks: taskLinks ?? this.taskLinks,
  );
}

class AgentContext {
  const AgentContext({
    required this.ownerId,
    required this.revision,
    required this.data,
    this.cloudData,
  });
  final String ownerId, revision;
  final Map<String, Object?> data;

  /// Full local facts remain available for deterministic validation. Only the
  /// bounded selection is sent to the model when supplied by the repository.
  final Map<String, Object?>? cloudData;
  Map<String, Object?> toJson() => {
    ...(cloudData ?? data),
    'revision': revision,
  };
}

class AgentAttachment {
  const AgentAttachment({
    required this.name,
    required this.kind,
    this.text = '',
    this.images = const [],
    this.note = '',
  });
  final String name, kind, text, note;
  final List<String> images;
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind,
    'text': text,
    'images': images,
    'note': note,
  };
  int get encodedSize => utf8.encode(jsonEncode(toJson())).length;
}

class AgentApplyResult {
  const AgentApplyResult({
    required this.summary,
    required this.changedCount,
    this.alreadyApplied = false,
  });
  final String summary;
  final int changedCount;
  final bool alreadyApplied;
}

class AgentException implements Exception {
  const AgentException(this.message, {this.code = 'agent_error'});
  final String message, code;
  @override
  String toString() => message;
}
