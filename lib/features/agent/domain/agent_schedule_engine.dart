import 'dart:math' as math;
import 'dart:convert';

import 'agent_models.dart';
import '../../calendar/domain/calendar_occurrence_builder.dart';
import '../../courses/domain/course_models.dart';
import '../../schedule/domain/day_schedule_models.dart';
import '../../tasks/domain/task_models.dart' show WeekdayMask;

/// Deterministic planning constraints. The model cannot grant itself more time
/// or silently move completed work by wording a persuasive response.
class AgentScheduleEngine {
  static AgentProposal prepare({
    required AgentContext context,
    required AgentWorkspace workspace,
    required AgentProposal proposal,
    required DateTime now,
  }) {
    if (proposal.operations.isEmpty) return proposal;
    final profile = <String, Object?>{
      'learningShare': .2,
      'sleepStartMinute': 0,
      'sleepEndMinute': 450,
      'livingMinutesPerDay': 180,
      ...workspace.profile,
    };
    for (final op in proposal.operations.where(
      (op) => op.action == 'update_profile',
    )) {
      profile.addAll(op.data);
    }
    if (profile['sleepStartMinute'] == profile['sleepEndMinute']) {
      throw const AgentException('睡眠开始和结束不能相同，请确认真实睡眠时段。');
    }
    final days = <String, _Day>{};
    for (final row in _maps(context.data['calendarDays'])) {
      final date = row['date']?.toString();
      if (date == null) continue;
      if (!_isKnown(date, profile)) continue;
      days[date] = _Day(
        date,
        _maps(row['events']).map(_Slot.fromJson).whereType<_Slot>().toList(),
        row['unknownDuration'] == true,
      );
    }
    final tasks = {
      for (final row in _maps(context.data['tasks']))
        row['id']?.toString(): row,
    };
    final managed = {
      for (final link in workspace.taskLinks) link['taskId']?.toString(): link,
    };
    final operations = <AgentOperation>[];
    final warnings = [...proposal.warnings];
    final today = _key(now);
    final minuteNow = now.hour * 60 + now.minute;
    var needsReflow = proposal.operations.any(
      (op) =>
          op.action == 'remove_busy_period' || op.action == 'update_profile',
    );
    final changedIds = <String>{};

    // First project calendar replacements and explicit moves so validation uses
    // the proposed state, not the now-obsolete occupied intervals.
    for (final op in proposal.operations) {
      final data = Map<String, Object?>.from(op.data);
      if (op.action == 'create_course' ||
          op.action == 'archive_course' ||
          (op.action == 'update_course' &&
              data.keys.any(
                {
                  'rules',
                  'semesterId',
                  'semesterStartsOn',
                  'semesterEndsOn',
                }.contains,
              ))) {
        _projectCourse(context, days, op, now);
        needsReflow = true;
      } else if (op.action == 'update_course_day') {
        final date = _dateKey(data['date']);
        _knownDay(date, profile, days, today);
        final day = days[date]!;
        final ruleId = data['ruleId'];
        final existing = day.slots
            .where(
              (slot) =>
                  slot.type == 'course' &&
                  slot.id == op.entityId &&
                  (ruleId == null || slot.ruleId == ruleId),
            )
            .toList();
        if (date == today && existing.any((slot) => slot.start < minuteNow)) {
          throw const AgentException('已经开始的课程不自动改写，请仅调整未来安排。');
        }
        if (data['action'] != 'extraCourse') {
          day.slots.removeWhere((slot) => existing.contains(slot));
        }
        if (data['action'] != 'skip') {
          day.slots.add(
            _Slot(
              op.entityId ?? 'course-change-${day.slots.length}',
              'course',
              _minute(data['startMinute']),
              _minute(data['endMinute'], end: true),
              false,
              false,
              title: existing.firstOrNull?.title ?? '课程',
              ruleId: ruleId?.toString(),
              proposed: true,
            ),
          );
        }
        needsReflow = true;
      } else if (op.action == 'add_busy_period') {
        if (data['date'] == null &&
            data['startsAt'] is String &&
            data['endsAt'] is String) {
          final start = DateTime.tryParse(
            data['startsAt'] as String,
          )?.toLocal();
          final end = DateTime.tryParse(data['endsAt'] as String)?.toLocal();
          if (start == null || end == null || _key(start) != _key(end)) {
            throw const AgentException('临时占用日期无效，跨夜请分成两天。');
          }
          data['date'] = _key(start);
          data['startMinute'] = start.hour * 60 + start.minute;
          data['durationMinutes'] = end.difference(start).inMinutes;
        }
        final date = _dateKey(data['date']);
        final start = _minute(data['startMinute']);
        final duration = data['durationMinutes'];
        if (duration is! int ||
            duration < 5 ||
            duration > 480 ||
            start + duration > 1440) {
          throw const AgentException('临时事项应为5–480分钟，跨夜请分成两天。');
        }
        if (date.compareTo(today) < 0 || (date == today && start < minuteNow)) {
          throw const AgentException('临时占用不能追溯修改已经过去的时段。');
        }
        final known = days[date];
        if (known == null || known.unknownDuration) {
          warnings.add('临时占用已登记；该日课表或占用范围尚未确认，暂不自动重排。');
          operations.add(
            AgentOperation(
              action: op.action,
              entityId: op.entityId,
              data: data,
            ),
          );
          continue;
        }
        known.slots.add(
          _Slot(
            op.entityId ?? 'busy-new-${operations.length}',
            'busy',
            start,
            start + duration,
            false,
            false,
            title: data['reason']?.toString() ?? '临时事项',
          ),
        );
        needsReflow = true;
      }
      if (op.entityId != null &&
          {
            'reschedule_task',
            'archive_task',
            'update_task',
          }.contains(op.action)) {
        final moving =
            op.action == 'archive_task' ||
            op.action == 'reschedule_task' ||
            data.keys.any(
              {
                'scheduledAt',
                'date',
                'startMinute',
                'endMinute',
                'scheduledMinuteOfDay',
                'weekdays',
                'startsOn',
                'endsOn',
                'durationMinutes',
                'targetDurationSeconds',
              }.contains,
            );
        if (!moving) {
          operations.add(op);
          continue;
        }
        changedIds.add(op.entityId!);
        for (final day in days.values) {
          final matching = day.slots.where(
            (slot) => slot.id == op.entityId && slot.type == 'task',
          );
          if (moving &&
              matching.any(
                (slot) =>
                    slot.completed ||
                    (day.date == today && slot.start < minuteNow),
              )) {
            throw const AgentException('已经开始或完成的学习不自动改写。');
          }
          day.slots.removeWhere(
            (slot) => slot.id == op.entityId && slot.type == 'task',
          );
        }
      }
      operations.add(
        AgentOperation(action: op.action, entityId: op.entityId, data: data),
      );
    }
    final removedBusy = proposal.operations
        .where((op) => op.action == 'remove_busy_period')
        .map((op) => op.entityId)
        .toSet();
    for (final busy in workspace.busyPeriods) {
      if (removedBusy.contains(busy['id'])) continue;
      final date = busy['date']?.toString();
      if (!days.containsKey(date)) continue;
      final start = busy['startMinute'];
      final duration = busy['durationMinutes'];
      if (start is int && duration is int) {
        days[date]!.slots.add(
          _Slot(
            busy['id']?.toString() ?? 'busy',
            'busy',
            start,
            start + duration,
            false,
            false,
          ),
        );
      }
    }
    for (final day in days.values) {
      final start = profile['sleepStartMinute'] as int? ?? 0;
      final end = profile['sleepEndMinute'] as int? ?? 450;
      if (start < end) {
        day.slots.add(_Slot('sleep', 'sleep', start, end, false, false));
      } else if (start > end) {
        day.slots.add(_Slot('sleep-early', 'sleep', 0, end, false, false));
        day.slots.add(_Slot('sleep-late', 'sleep', start, 1440, false, false));
      }
    }

    // Normalize precise study blocks to the existing CheckD task contract.
    for (var index = 0; index < operations.length; index++) {
      final op = operations[index];
      if (!{
        'create_task',
        'update_task',
        'reschedule_task',
      }.contains(op.action)) {
        continue;
      }
      final data = Map<String, Object?>.from(op.data);
      if (data['unscheduled'] == true) continue;
      if (op.action == 'update_task' &&
          !data.keys.any(
            {
              'scheduledAt',
              'date',
              'startMinute',
              'endMinute',
              'scheduledMinuteOfDay',
              'weekdays',
              'startsOn',
              'endsOn',
              'durationMinutes',
              'targetDurationSeconds',
            }.contains,
          )) {
        continue;
      }
      final old = tasks[op.entityId];
      final isRecurring = (data['kind'] ?? old?['kind']) == 'recurring';
      final recurringStart = data.containsKey('scheduledMinuteOfDay')
          ? data['scheduledMinuteOfDay']
          : old?['scheduledMinuteOfDay'];
      if (isRecurring && recurringStart != null) {
        final weekdays =
            (data['weekdays'] as List? ??
                    (old?['weekdaysMask'] is int
                        ? WeekdayMask.toDays(
                            old!['weekdaysMask'] as int,
                          ).toList()
                        : const [1, 2, 3, 4, 5, 6, 7]))
                .cast<int>();
        final start = _minute(recurringStart);
        final duration = _duration({
          if (old?['targetDurationSeconds'] != null)
            'targetDurationSeconds': old!['targetDurationSeconds'],
          ...data,
        }, managed[op.entityId]);
        final startDate = data['startsOn'] ?? old?['startsOn'];
        final endDate = data.containsKey('endsOn')
            ? data['endsOn']
            : old?['endsOn'];
        final startsOn = startDate == null ? today : _dateKey(startDate);
        final endsOn = endDate == null ? null : _dateKey(endDate);
        for (final day in days.values) {
          if (day.date.compareTo(startsOn) < 0 ||
              (endsOn != null && day.date.compareTo(endsOn) > 0) ||
              !weekdays.contains(DateTime.parse(day.date).weekday)) {
            continue;
          }
          _knownDay(day.date, profile, days, today);
          if (day.unknownDuration) {
            throw const AgentException('这天有未注明时长的事项，请先补齐占用时间再自动排程。');
          }
          if (day.date == today && start < minuteNow) continue;
          day.slots.add(
            _Slot(
              op.entityId ?? 'new-$index',
              'task',
              start,
              start + duration,
              true,
              false,
              proposed: true,
            ),
          );
        }
        continue;
      }
      String? date;
      int? start, end;
      if (data['date'] != null && data['startMinute'] != null) {
        date = _dateKey(data['date']);
        start = _minute(data['startMinute']);
        end = data['endMinute'] == null
            ? start + _duration(data, managed[op.entityId])
            : _minute(data['endMinute'], end: true);
      } else if (data['scheduledAt'] != null) {
        final at = DateTime.tryParse(data['scheduledAt'].toString())?.toLocal();
        if (at == null) throw const AgentException('任务开始时间格式不正确。');
        date = _key(at);
        start = at.hour * 60 + at.minute;
        end = start + _duration(data, managed[op.entityId]);
      } else if (op.action == 'update_task' &&
          !data.containsKey('scheduledAt')) {
        // A title-only edit retains its prior occupied interval.
        final at = old?['scheduledAt'];
        if (at != null) {
          final parsed = DateTime.tryParse(at.toString())?.toLocal();
          if (parsed != null) {
            date = _key(parsed);
            start = parsed.hour * 60 + parsed.minute;
            end = start + _duration(data, managed[op.entityId]);
          }
        }
      }
      if (date == null || start == null || end == null) continue;
      _knownDay(date, profile, days, today);
      if (start >= end || end > 1440) {
        throw const AgentException('时间块须在同一天内，且结束晚于开始。');
      }
      if (date == today && start < minuteNow && op.action != 'update_task') {
        throw const AgentException('不能把新安排放到已经过去的时间。');
      }
      if (days[date]!.unknownDuration) {
        throw const AgentException('这天有未注明时长的事项，请先补齐占用时间再自动排程。');
      }
      if (op.action != 'reschedule_task') {
        final day = DateTime.parse(date);
        data['scheduledAt'] = DateTime(
          day.year,
          day.month,
          day.day,
          start ~/ 60,
          start % 60,
        ).toIso8601String();
        data['durationMinutes'] = end - start;
        data['date'] = date;
        data['startMinute'] = start;
        data['endMinute'] = end;
      }
      operations[index] = AgentOperation(
        action: op.action,
        entityId: op.entityId,
        data: data,
      );
      days[date]!.slots.add(
        _Slot(
          op.entityId ?? 'new-$index',
          'task',
          start,
          end,
          true,
          false,
          proposed: true,
        ),
      );
    }

    if (needsReflow) {
      final displaced = <(_Day, _Slot)>[];
      for (final link in workspace.taskLinks.where(
        (link) =>
            link['needsScheduling'] == true || link['unscheduled'] == true,
      )) {
        final id = link['taskId']?.toString();
        final task = tasks[id];
        if (id == null ||
            task == null ||
            task['status'] == 'archived' ||
            task['completedAt'] != null ||
            changedIds.contains(id) ||
            days.isEmpty) {
          continue;
        }
        displaced.add((
          days.values.first,
          _Slot(
            id,
            'task',
            0,
            _duration(const {}, link),
            true,
            false,
            title: task['name']?.toString() ?? '学习事项',
          ),
        ));
      }
      for (final day in days.values) {
        for (final slot in [...day.slots]) {
          if (!slot.managed || slot.proposed || changedIds.contains(slot.id)) {
            continue;
          }
          final conflict = day.slots.any(
            (other) =>
                !identical(other, slot) &&
                !other.managed &&
                slot.overlaps(other),
          );
          if (!conflict) continue;
          if (slot.completed ||
              day.date.compareTo(today) < 0 ||
              (day.date == today && slot.start < minuteNow)) {
            throw const AgentException('新占用与已经发生或完成的学习冲突，不能移动历史事实。');
          }
          day.slots.remove(slot);
          displaced.add((day, slot));
        }
      }
      // A new course may also reduce the weekly shared budget without directly
      // overlapping a study block. Move only future managed, unfinished blocks.
      for (final week in _weekGroups(days.values).values) {
        var excess = _used(week) - _budget(week, profile);
        if (excess <= 0) continue;
        final candidates = [
          for (final day in week)
            for (final slot in day.slots)
              if (slot.managed &&
                  !slot.proposed &&
                  !slot.completed &&
                  !changedIds.contains(slot.id) &&
                  (day.date != today || slot.start >= minuteNow))
                (day, slot),
        ]..sort((a, b) => b.$1.date.compareTo(a.$1.date));
        for (final candidate in candidates) {
          if (excess <= 0) break;
          candidate.$1.slots.remove(candidate.$2);
          displaced.add(candidate);
          excess -= candidate.$2.duration;
        }
      }
      for (final item in displaced) {
        final slot = item.$2;
        final candidates =
            days.values
                .where(
                  (day) =>
                      day.date.compareTo(today) >= 0 &&
                      _isKnown(day.date, profile) &&
                      !day.unknownDuration,
                )
                .toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        _Day? destination;
        int? newStart;
        for (final day in candidates) {
          final group = _weekGroups(days.values)[_week(day.date)]!;
          if (_used(group) + slot.duration > _budget(group, profile)) continue;
          for (
            var start = day.date == today ? ((minuteNow + 4) ~/ 5) * 5 : 0;
            start + slot.duration <= 1440;
            start += 5
          ) {
            final trial = _Slot(
              slot.id,
              'task',
              start,
              start + slot.duration,
              true,
              false,
            );
            if (day.slots.every((other) => !trial.overlaps(other))) {
              destination = day;
              newStart = start;
              break;
            }
          }
          if (destination != null) break;
        }
        if (destination == null || newStart == null) {
          operations.add(
            AgentOperation(
              action: 'reschedule_task',
              entityId: slot.id,
              data: const {'unscheduled': true},
            ),
          );
          warnings.add(
            '“${slot.title.isEmpty ? '学习事项' : slot.title}”暂时排不下，已保留为待安排，不会删除。',
          );
        } else {
          destination.slots.add(
            _Slot(
              slot.id,
              'task',
              newStart,
              newStart + slot.duration,
              true,
              false,
              proposed: true,
              title: slot.title,
            ),
          );
          operations.add(
            AgentOperation(
              action: 'reschedule_task',
              entityId: slot.id,
              data: {
                'date': destination.date,
                'startMinute': newStart,
                'endMinute': newStart + slot.duration,
              },
            ),
          );
        }
      }
    }

    for (final day in days.values) {
      for (final slot in day.slots.where((slot) => slot.proposed)) {
        if (day.slots.any(
          (other) => !identical(slot, other) && slot.overlaps(other),
        )) {
          throw AgentException('${day.date} 的安排与课程、睡眠、占用或其他目标冲突，请重新生成。');
        }
      }
    }
    for (final group in _weekGroups(days.values).values) {
      if (_used(group) > _budget(group, profile) &&
          group.any((day) => day.slots.any((slot) => slot.proposed))) {
        throw const AgentException('所有目标合计超过了本周共享空闲预算，请减少安排或补充真实可用时间。');
      }
    }
    if (operations.length > 80) {
      throw const AgentException('重排影响超过80项，请缩小调整范围。');
    }
    return AgentProposal(
      id: proposal.id,
      reply: proposal.reply,
      contextRevision: proposal.contextRevision,
      operations: operations,
      questions: proposal.questions,
      warnings: warnings.toSet().toList(),
    );
  }

  static int availableBudgetMinutes({
    required List<Map<String, Object?>> calendarDays,
    required Map<String, Object?> profile,
    List<Map<String, Object?>> busyPeriods = const [],
  }) {
    if ((profile['sleepStartMinute'] ?? 0) ==
        (profile['sleepEndMinute'] ?? 450)) {
      throw const AgentException('睡眠开始和结束不能相同，请确认真实睡眠时段。');
    }
    final days = calendarDays
        .where(
          (row) =>
              row['date'] is String &&
              _isKnown(row['date'] as String, profile) &&
              row['unknownDuration'] != true,
        )
        .map(
          (row) => _Day(
            row['date'] as String,
            _maps(
              row['events'],
            ).map(_Slot.fromJson).whereType<_Slot>().toList(),
            false,
          ),
        )
        .toList();
    final start = profile['sleepStartMinute'] as int? ?? 0,
        end = profile['sleepEndMinute'] as int? ?? 450;
    for (final day in days) {
      for (final busy in busyPeriods.where(
        (busy) => busy['date'] == day.date,
      )) {
        if (busy['startMinute'] is int && busy['durationMinutes'] is int) {
          final minute = busy['startMinute'] as int;
          day.slots.add(
            _Slot(
              busy['id']?.toString() ?? 'busy',
              'busy',
              minute,
              minute + (busy['durationMinutes'] as int),
              false,
              false,
            ),
          );
        }
      }
      if (start < end) {
        day.slots.add(_Slot('sleep', 'sleep', start, end, false, false));
      } else if (start > end) {
        day.slots.add(_Slot('sleep', 'sleep', 0, end, false, false));
        day.slots.add(_Slot('sleep', 'sleep', start, 1440, false, false));
      }
    }
    return _budget(days, profile);
  }

  static void _projectCourse(
    AgentContext context,
    Map<String, _Day> days,
    AgentOperation op,
    DateTime now,
  ) {
    final existing = _maps(
      context.data['courses'],
    ).where((row) => row['id'] == op.entityId).firstOrNull;
    if (op.action != 'create_course' && existing == null) {
      throw const AgentException('所选课程不存在。');
    }
    final data = <String, Object?>{...?existing, ...op.data};
    final id = op.entityId ?? 'new-course-${op.hashCode}';
    for (final day in days.values) {
      day.slots.removeWhere((slot) => slot.type == 'course' && slot.id == id);
    }
    if (op.action == 'archive_course') return;
    final oldRules = _maps(
      existing?['rules'],
    ).where((rule) => rule['deletedAt'] == null).toList();
    final incoming = _maps(op.data['rules']);
    final replacedIds = incoming
        .map((rule) => rule['id'])
        .whereType<String>()
        .toSet();
    final rulesData = [
      if (op.data['replaceRules'] != true)
        ...oldRules.where((r) => !replacedIds.contains(r['id'])),
      ...incoming,
    ];
    final rules = <CourseScheduleRule>[];
    for (var i = 0; i < rulesData.length; i++) {
      final rule = rulesData[i];
      final type = CourseWeekRuleType.values
          .where((v) => v.name == (rule['weekRuleType'] ?? 'everyWeek'))
          .firstOrNull;
      if (type == null) throw const AgentException('课程周次规则无效。');
      Object? weeks = rule['weekNumbers'] ?? rule['weekNumbersJson'];
      if (weeks is String) weeks = jsonDecode(weeks);
      Object? sections = rule['sectionIds'] ?? rule['sectionIdsJson'];
      if (sections is String) sections = jsonDecode(sections);
      rules.add(
        CourseScheduleRule(
          id: rule['id']?.toString() ?? '$id-rule-$i',
          courseId: id,
          weekday: _minute(rule['weekday']),
          weekRuleType: type,
          startsAtMinute: _minute(rule['startsAtMinute']),
          endsAtMinute: _minute(rule['endsAtMinute'], end: true),
          createdAt: now,
          updatedAt: now,
          startWeek: rule['startWeek'] as int?,
          endWeek: rule['endWeek'] as int?,
          intervalWeeks: rule['intervalWeeks'] as int?,
          weekNumbers: (weeks is List ? weeks.cast<int>() : const <int>[])
              .toSet(),
          scheduleTemplateId: rule['scheduleTemplateId'] as String?,
          sectionIds: (sections is List
              ? sections.cast<String>()
              : const <String>[]),
          timeMode: rule['timeMode'] == 'periods'
              ? CourseScheduleTimeMode.periods
              : CourseScheduleTimeMode.customTime,
        ),
      );
    }
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    final course = CourseDetails(
      id: id,
      name: data['name']?.toString() ?? '课程',
      colorValue: data['colorValue'] as int? ?? 0xFF8BA9F0,
      status: CourseStatus.active,
      createdAt: now,
      updatedAt: now,
      rules: rules,
      semesterId: data['semesterId'] as String?,
      semesterStartsOn: date(data['semesterStartsOn']),
      semesterEndsOn: date(data['semesterEndsOn']),
    );
    final semesters = [
      for (final row in _maps(context.data['semesters']))
        SemesterDetails(
          id: row['id'] as String,
          name: row['name']?.toString() ?? '学期',
          firstWeekStartDate: date(row['firstWeekStartDate'])!,
          totalWeeks: row['totalWeeks'] as int,
          isCurrent: row['isCurrent'] == true,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final templates = [
      for (final row in _maps(context.data['templates']))
        ScheduleTemplateDetails(
          id: row['id'] as String,
          name: row['name']?.toString() ?? '作息',
          timezone: 'Asia/Shanghai',
          isDefault: false,
          createdAt: now,
          updatedAt: now,
          segments: [
            for (final segment in _maps(row['segments']))
              ScheduleTemplateSegment(
                id: segment['id'] as String,
                templateId: row['id'] as String,
                name: segment['name']?.toString() ?? '课时',
                startsAtMinute: segment['startsAtMinute'] as int,
                endsAtMinute: segment['endsAtMinute'] as int,
                segmentType: ScheduleSegmentType.classTime,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
          ],
        ),
    ];
    final overrides = [
      for (final row in _maps(
        context.data['overrides'],
      ).where((r) => r['itemType'] == 'course' && r['deletedAt'] == null))
        DailyItemOverride(
          id: row['id'] as String,
          itemType: DayItemType.course,
          itemId: row['itemId'] as String,
          localDate: DateTime.parse(row['localDate'] as String),
          action: DayOverrideAction.values.byName(row['action'] as String),
          createdAt: now,
          updatedAt: now,
          plannedStartMinute: row['plannedStartMinute'] as int?,
          plannedEndMinute: row['plannedEndMinute'] as int?,
        ),
    ];
    for (final day in days.values) {
      for (final occurrence in buildCourseOccurrencesForDate(
        date: DateTime.parse(day.date),
        courses: [course],
        overrides: overrides,
        templates: templates,
        semesters: semesters,
      )) {
        day.slots.add(
          _Slot(
            id,
            'course',
            occurrence.startMinute!,
            occurrence.endMinute!,
            false,
            false,
            title: course.name,
            ruleId: occurrence.courseRule?.id,
            proposed: true,
          ),
        );
      }
    }
  }
}

class _Day {
  _Day(this.date, this.slots, this.unknownDuration);
  final String date;
  final List<_Slot> slots;
  final bool unknownDuration;
}

class _Slot {
  _Slot(
    this.id,
    this.type,
    this.start,
    this.end,
    this.managed,
    this.completed, {
    this.proposed = false,
    this.title = '',
    this.ruleId,
  }) {
    if (start < 0 || end > 1440 || end <= start) {
      throw const AgentException('日程中存在无效起止时间，请先修正。');
    }
  }
  final String id, type, title;
  final String? ruleId;
  final int start, end;
  final bool managed, completed, proposed;
  int get duration => end - start;
  bool overlaps(_Slot other) => start < other.end && end > other.start;
  static _Slot? fromJson(Map<String, Object?> row) {
    final start = row['startMinute'], end = row['endMinute'];
    if (start is! int || end is! int) return null;
    return _Slot(
      (row['entityId'] ?? row['id'] ?? 'item').toString(),
      row['type']?.toString() ?? 'task',
      start,
      end,
      row['managed'] == true,
      row['completed'] == true,
      title: row['title']?.toString() ?? '',
      ruleId: row['ruleId']?.toString(),
    );
  }
}

List<Map<String, Object?>> _maps(Object? value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
String _key(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _dateKey(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const AgentException('请明确YYYY-MM-DD格式的日期。');
  }
  final date = DateTime.tryParse(value);
  if (date == null || _key(date) != value) throw const AgentException('日期无效。');
  return value;
}

int _minute(Object? value, {bool end = false}) {
  if (value is! int || value < 0 || value > (end ? 1440 : 1439)) {
    throw const AgentException('请填写有效的分钟数时间。');
  }
  return value;
}

bool _isKnown(String date, Map<String, Object?> profile) {
  final from = profile['confirmedFrom'], through = profile['confirmedThrough'];
  return from is String &&
      through is String &&
      date.compareTo(from) >= 0 &&
      date.compareTo(through) <= 0;
}

void _knownDay(
  String date,
  Map<String, Object?> profile,
  Map<String, _Day> days,
  String today,
) {
  if (date.compareTo(today) < 0) throw const AgentException('不能自动改写过去日期的安排。');
  if (!_isKnown(date, profile) || !days.containsKey(date)) {
    throw const AgentException('该日期的课表或空闲范围尚未确认，请先补充课表范围。');
  }
}

int _duration(Map<String, Object?> data, Map<String, Object?>? link) {
  final value =
      data['durationMinutes'] ??
      link?['durationMinutes'] ??
      (data['targetDurationSeconds'] is int
          ? ((data['targetDurationSeconds'] as int) / 60).ceil()
          : 30);
  if (value is! int || value <= 0 || value > 720) {
    throw const AgentException('请提供1–720分钟的预计时长。');
  }
  return value;
}

String _week(String day) {
  final date = DateTime.parse(day);
  return _key(date.subtract(Duration(days: date.weekday - 1)));
}

Map<String, List<_Day>> _weekGroups(Iterable<_Day> days) {
  final result = <String, List<_Day>>{};
  for (final day in days) {
    if (day.unknownDuration) continue;
    (result[_week(day.date)] ??= []).add(day);
  }
  return result;
}

int _used(Iterable<_Day> days) => days.fold(
  0,
  (total, day) =>
      total +
      day.slots
          .where((slot) => slot.managed)
          .fold(0, (n, slot) => n + slot.duration),
);
int _budget(Iterable<_Day> days, Map<String, Object?> profile) {
  var free = 0;
  for (final day in days) {
    final fixed = day.slots.where((slot) => !slot.managed).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var occupied = 0, start = -1, end = -1;
    for (final slot in fixed) {
      if (start < 0) {
        start = slot.start;
        end = slot.end;
      } else if (slot.start <= end) {
        end = math.max(end, slot.end);
      } else {
        occupied += end - start;
        start = slot.start;
        end = slot.end;
      }
    }
    if (start >= 0) occupied += end - start;
    free += math.max(
      0,
      1440 - occupied - (profile['livingMinutesPerDay'] as int? ?? 180),
    );
  }
  final share = profile['learningShare'] as num? ?? .2;
  if (!share.isFinite || share <= 0 || share > 1) {
    throw const AgentException('共享学习比例须大于0且不超过100%。');
  }
  return (free * share).floor();
}
