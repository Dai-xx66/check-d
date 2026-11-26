import 'agent_models.dart';

enum AgentReminderKind { start, followUp, weeklyReview }

/// A delivery window is independent of learning, reading, or completion facts.
class AgentReminder {
  const AgentReminder({
    required this.key,
    required this.kind,
    required this.when,
    required this.validUntil,
    required this.title,
    required this.body,
    this.occurrenceId,
    this.request = '',
    this.expiresAtEnd = false,
  });
  final String key, title, body;
  final String? occurrenceId;
  final String request;
  final bool expiresAtEnd;
  final AgentReminderKind kind;
  final DateTime when, validUntil;
  bool isDue(DateTime now) =>
      !now.isBefore(when) &&
      (expiresAtEnd ? now.isBefore(validUntil) : !now.isAfter(validUntil));
  int get notificationId {
    var hash = 0x811c9dc5;
    for (final code in 'agent:$key'.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

class AgentReminderEngine {
  const AgentReminderEngine();

  List<AgentReminder> build(
    AgentContext context, {
    required DateTime now,
    int horizonDays = 14,
  }) {
    final profile = context.data['profile'];
    if (profile is! Map || profile['remindersEnabled'] != true) return const [];
    final local = beijingWallTime(now);
    final first = DateTime.utc(local.year, local.month, local.day);
    final through = first.add(Duration(days: horizonDays));
    final result = <AgentReminder>[];
    final feedback = context.data['feedback'] as List? ?? const [];
    final links = {
      for (final row in context.data['taskLinks'] as List? ?? const [])
        if (row is Map && row['taskId'] is String) row['taskId']: row,
    };
    for (final day in context.data['calendarDays'] as List? ?? const []) {
      if (day is! Map) continue;
      final date = DateTime.tryParse('${day['date']}');
      if (date == null) continue;
      final wallDay = DateTime.utc(date.year, date.month, date.day);
      if (wallDay.isBefore(first) || !wallDay.isBefore(through)) continue;
      final events =
          (day['events'] as List? ?? const [])
              .whereType<Map>()
              .where(
                (event) =>
                    event['managed'] == true &&
                    event['type'] == 'task' &&
                    event['startMinute'] is int &&
                    event['endMinute'] is int &&
                    (event['startMinute'] as int) >= 0 &&
                    (event['endMinute'] as int) >
                        (event['startMinute'] as int) &&
                    (event['endMinute'] as int) <= 1440,
              )
              .toList()
            ..sort(
              (a, b) =>
                  (a['endMinute'] as int).compareTo(b['endMinute'] as int),
            );
      for (final event in events) {
        if (event['managed'] != true ||
            event['type'] != 'task' ||
            event['completed'] == true) {
          continue;
        }
        final start = event['startMinute'], end = event['endMinute'];
        final segment = event['id'];
        if (segment is! String ||
            start is! int ||
            end is! int ||
            start < 0 ||
            end <= start ||
            end > 1440) {
          continue;
        }
        final key = '${context.ownerId}:${day['date']}:$segment';
        final title = '${event['title'] ?? '学习安排'}';
        final begins = _instant(wallDay.add(Duration(minutes: start)));
        final ends = _instant(wallDay.add(Duration(minutes: end)));
        final link = links[event['entityId']];
        final standard =
            '${event['standard'] ?? link?['standard'] ?? '请先确认本段完成标准'}';
        final remaining = ends.difference(now).inSeconds;
        final delayed = now.isAfter(begins) && now.isBefore(ends);
        final timing = delayed
            ? '现在开始${_time(local.hour * 60 + local.minute)}—${_time(end)}，实际剩余${(remaining / 60).ceil()}分钟，无需补足原计划'
            : '现在开始${_time(start)}—${_time(end)}，共${end - start}分钟';
        final material = '${event['materials'] ?? link?['materials'] ?? ''}';
        final url = RegExp(
          r'https?://[^\s\]\)]+',
        ).firstMatch(material)?.group(0);
        final isLast = identical(event, events.last);
        final body = _clip(
          '$timing；任务：${_clip(title, 36)}；完成标准：${_clip(standard, 54)}'
          '${url == null ? '' : '；材料：${_clip(url, 60)}'}'
          '${isLast ? '；结束后可回复：日期｜实际分钟｜完成内容｜结果或卡点' : ''}',
          180,
        );
        result.add(
          AgentReminder(
            key: '$key:start',
            occurrenceId: segment,
            kind: AgentReminderKind.start,
            when: begins,
            validUntil: end - start <= 5
                ? ends
                : begins.add(const Duration(minutes: 5)),
            expiresAtEnd: end - start <= 5,
            title: '该开始$title了',
            body: body,
            request:
                '请帮我核对${day['date']} ${_time(start)}—${_time(end)}的“$title”，完成标准是：$standard。',
          ),
        );
        final reported = feedback.any(
          (row) =>
              row is Map &&
              row['date'] == day['date'] &&
              (row['taskId'] == null ||
                  row['segmentId'] == segment ||
                  row['taskId'] == event['entityId']),
        );
        if (isLast && !reported && end + 10 < 1440) {
          result.add(
            AgentReminder(
              key: '$key:followUp',
              kind: AgentReminderKind.followUp,
              when: _instant(wallDay.add(Duration(minutes: end + 10))),
              validUntil: _instant(wallDay.add(const Duration(days: 1))),
              title: '今天的学习进展如何？',
              body: '一行反馈即可：日期｜实际分钟｜完成内容｜结果或卡点。未反馈不等于未学习。',
              request:
                  '我想反馈${day['date']}的学习进展。请按“日期｜实际分钟｜完成内容｜结果或卡点”核对，不要自动记为完成。',
            ),
          );
        }
      }
    }
    for (
      var day = first;
      day.isBefore(through);
      day = day.add(const Duration(days: 1))
    ) {
      if (day.weekday != DateTime.sunday) continue;
      final lastSunday = day.add(const Duration(days: 7)).month != day.month;
      final stageReview = _stageDue(context, day);
      final extra =
          '${lastSunday ? '同时收集下月课表与固定事项。' : ''}'
          '${stageReview ? '本周已到已确认起点的三个月阶段复核，请重新评估目标与共享预算。' : ''}';
      result.add(
        AgentReminder(
          key:
              '${context.ownerId}:${day.toIso8601String().substring(0, 10)}:weekly',
          kind: AgentReminderKind.weeklyReview,
          when: _instant(day.add(const Duration(hours: 20, minutes: 30))),
          validUntil: _instant(day.add(const Duration(hours: 21))),
          title: '一起看看这一周',
          body: '打开智能体后发送请求，用真实计时和反馈复盘，再调整下一周。$extra',
          request:
              '请根据本周真实计时、完成记录和自报反馈做周复盘，分别标明数据来源与未反馈，给出下周最多三个重点。$extra'
              '${lastSunday ? '请给我简短收集模板：下月课表覆盖日期｜课程变动｜固定事项起止｜未知时段。' : ''}'
              '${stageReview ? '阶段复核与相关学习活动仍须占用当前共享预算，不额外加量。' : ''}',
        ),
      );
    }
    result.sort((a, b) => a.when.compareTo(b.when));
    return result;
  }

  /// UTC fields deliberately represent Beijing wall-clock fields here.
  static DateTime beijingWallTime(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));
  static DateTime _instant(DateTime wall) =>
      wall.subtract(const Duration(hours: 8));

  String _time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String _clip(String value, int length) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= length ? text : '${text.substring(0, length - 1)}…';
  }

  bool _stageDue(AgentContext context, DateTime sunday) {
    final profile = context.data['profile'] as Map? ?? const {};
    final anchors = [
      profile['planningStartedOn'],
      for (final goal in context.data['goals'] as List? ?? const [])
        if (goal is Map && goal['archived'] != true)
          goal['startsOn'] ?? goal['startedOn'] ?? goal['startDate'],
    ];
    for (final value in anchors) {
      final start = DateTime.tryParse('$value');
      if (start == null) continue;
      final months =
          (sunday.year - start.year) * 12 + sunday.month - start.month;
      if (months < 3) continue;
      final dueMonth = start.month + (months ~/ 3) * 3;
      final lastDay = DateTime.utc(start.year, dueMonth + 1, 0).day;
      final due = DateTime.utc(
        start.year,
        dueMonth,
        start.day > lastDay ? lastDay : start.day,
      );
      if (!due.isAfter(sunday) &&
          !due.isBefore(sunday.subtract(const Duration(days: 6)))) {
        return true;
      }
    }
    return false;
  }
}
