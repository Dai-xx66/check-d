import 'dart:convert';
import 'dart:io';

import 'package:check_d/features/agent_scheduler/domain/schedule_contract.dart';
import 'package:check_d/features/agent_scheduler/domain/schedule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// 固定周一，保证测试与运行时无关。
final DateTime _monday = DateTime(2026, 11, 2);

/// 去掉行注释，让模块边界守卫只检查真正的代码。
String stripComments(String source) => source
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

DateTime _at(int dayOffset, int hour, [int minute = 0]) =>
    DateTime(_monday.year, _monday.month, _monday.day + dayOffset, hour, minute);

ScheduleWindow _window(int dayOffset, int startHour, int endHour) =>
    ScheduleWindow(startAt: _at(dayOffset, startHour), endAt: _at(dayOffset, endHour));

bool _overlapsAny(ProposedBlock block, List<ScheduleFixedBlock> blocks) {
  return blocks.map((fixed) => fixed.window).any(block.window.overlaps);
}

bool _endsSameDay(ProposedBlock block) {
  final nextDay = scheduleDayOnly(block.startAt).add(const Duration(days: 1));
  return block.endAt.isBefore(nextDay) ||
      block.endAt.isAtSameMomentAs(nextDay);
}

void main() {
  group('generateSchedule 硬避让', () {
    test('任务必须绕开固定课程', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [_window(0, 8, 22)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-1',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 14),
            endAt: _at(0, 16),
            title: '高等数学',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-review',
            title: '复习线性代数',
            requiredMinutes: 90,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, hasLength(1));
      expect(proposal.unplannedTasks, isEmpty);
      final block = proposal.blocks.single;
      expect(block.startAt, _at(0, 8));
      expect(block.endAt, _at(0, 9, 30));
      expect(_overlapsAny(block, input.fixedBlocks), isFalse);
    });

    test('多个课程之间依次避让且不重叠', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [_window(0, 8, 22)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-1',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 9),
            endAt: _at(0, 11),
            title: '大学英语',
          ),
          ScheduleFixedBlock(
            ownerId: 'course-2',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 14),
            endAt: _at(0, 16),
            title: '数据结构',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'report',
            title: '写实验报告',
            requiredMinutes: 120,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final block = proposal.blocks.single;
      expect(_overlapsAny(block, input.fixedBlocks), isFalse);
      expect(block.minutes, 120);
    });
  });

  group('截止语义', () {
    test('精确截止已过则不再排入', () {
      final input = ScheduleInput(
        now: _at(0, 12),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [_window(0, 8, 22)],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-overdue',
            title: '提交作业',
            requiredMinutes: 60,
            deadline: ScheduleDeadline.exact(_at(0, 10)),
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, isEmpty);
      expect(proposal.unplannedTasks, hasLength(1));
      expect(
        proposal.unplannedTasks.single.reason,
        UnplannedReason.pastDeadline,
      );
      expect(
        proposal.unplannedTasks.single.reason.code,
        'PAST_DEADLINE',
      );
    });

    test('日期型截止整天宽限，不能被当成 23:59 处理', () {
      final input = ScheduleInput(
        now: _at(0, 23, 30),
        horizonStart: _at(0, 0),
        horizonEnd: _at(1, 0),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 0), endAt: _at(1, 0)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-tonight',
            title: '背单词',
            requiredMinutes: 15,
            deadline: ScheduleDeadline.dateOnly(_at(0, 0)),
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.unplannedTasks, isEmpty);
      expect(proposal.blocks, hasLength(1));
      expect(proposal.blocks.single.startAt, _at(0, 23, 30));
      expect(proposal.blocks.single.endAt, _at(0, 23, 45));
    });

    test('ScheduleDeadline 两种形态互斥且语义不同', () {
      final dateOnly = ScheduleDeadline.dateOnly(_at(0, 0));
      final exact = ScheduleDeadline.exact(_at(0, 10));

      expect(dateOnly.isDateOnly, isTrue);
      expect(exact.hasTime, isTrue);
      expect(() => dateOnly.isPast(_at(0, 23, 59)), returnsNormally);
      expect(dateOnly.isPast(_at(0, 23, 59)), isFalse);
      expect(dateOnly.isPast(_at(1, 0)), isTrue);
      expect(exact.isPast(_at(0, 10)), isTrue);
      expect(exact.isPast(_at(0, 9, 59)), isFalse);
      expect(dateOnly.latestEndAt.day, _monday.day);
    });
  });

  group('容量与冲突处理', () {
    test('可用时间不足时给出未安排量与机器可读原因', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 8, 30),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 8, 30)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-long',
            title: '读文献',
            requiredMinutes: 120,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, isEmpty);
      expect(proposal.unplannedTasks, hasLength(1));
      final unplanned = proposal.unplannedTasks.single;
      expect(unplanned.remainingMinutes, 120);
      expect(unplanned.reason, UnplannedReason.windowInsufficient);
      expect(unplanned.reason.code, 'WINDOW_INSUFFICIENT');
    });

    test('固定项相互重叠时不会通过移动它们来消解冲突', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [_window(0, 8, 22)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-1',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 14),
            endAt: _at(0, 16),
            title: '编译原理',
          ),
          ScheduleFixedBlock(
            ownerId: 'event-1',
            ownerType: ScheduleOwnerType.event,
            startAt: _at(0, 15),
            endAt: _at(0, 17),
            title: '班会',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-report',
            title: '写报告',
            requiredMinutes: 60,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      // 提案里只能出现柔性任务，绝不能出现被搬动的课程或会议。
      expect(proposal.blocks.map((block) => block.taskId), [
        'task-report',
      ]);
      expect(
        proposal.notes.map((note) => note.message).join(),
        contains('重叠'),
      );
      for (final block in proposal.blocks) {
        expect(_overlapsAny(block, input.fixedBlocks), isFalse);
      }
    });

    test('开放时段被占满时报 OVERLAPS_FIXED', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 12),
        baseVersion: 'v1',
        availability: [_window(0, 8, 12)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-1',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 8),
            endAt: _at(0, 12),
            title: '体育课',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-x',
            title: '自习',
            requiredMinutes: 60,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, isEmpty);
      expect(
        proposal.unplannedTasks.single.reason,
        UnplannedReason.overlapsFixed,
      );
    });
  });

  group('确定性与边界', () {
    test('相同输入必须得到完全相同的输出', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 7),
        horizonEnd: _at(1, 20),
        baseVersion: 'v1',
        availability: [_window(0, 8, 22), _window(1, 8, 20)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-1',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 10),
            endAt: _at(0, 12),
            title: '高等数学',
          ),
          ScheduleFixedBlock(
            ownerId: 'event-1',
            ownerType: ScheduleOwnerType.event,
            startAt: _at(0, 15),
            endAt: _at(0, 16, 30),
            title: '社团活动',
          ),
          ScheduleFixedBlock(
            ownerId: 'course-2',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(1, 9),
            endAt: _at(1, 10, 30),
            title: '计算机网络',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'a-report',
            title: '拆报告框架',
            requiredMinutes: 60,
            deadline: ScheduleDeadline.exact(_at(1, 18)),
            priority: 2,
          ),
          ScheduleTaskDemand(
            taskId: 'b-review',
            title: '复习',
            requiredMinutes: 90,
          ),
          ScheduleTaskDemand(
            taskId: 'c-run',
            title: '跑步',
            requiredMinutes: 45,
            deadline: ScheduleDeadline.dateOnly(_at(0, 0)),
            priority: 1,
          ),
          ScheduleTaskDemand(
            taskId: 'd-read',
            title: '读论文',
            requiredMinutes: 120,
            priority: 3,
          ),
        ],
      );

      final first = generateSchedule(input);
      final second = generateSchedule(input);

      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('排出来的块不跨自然日', () {
      final input = ScheduleInput(
        now: _at(0, 21),
        horizonStart: _at(0, 21),
        horizonEnd: _at(1, 2),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 22), endAt: _at(1, 2)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'short',
            title: '短任务',
            requiredMinutes: 90,
          ),
          ScheduleTaskDemand(
            taskId: 'long',
            title: '长任务',
            requiredMinutes: 180,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      for (final block in proposal.blocks) {
        expect(_endsSameDay(block), isTrue);
      }
      // 180 分钟无法塞进单个自然日的剩余窗口，必须如实报未安排。
      expect(
        proposal.unplannedTasks.map((task) => task.taskId),
        contains('long'),
      );
    });
  });

  group('repairSchedule 最小扰动重排', () {
    test('插入会议只移动冲突的柔性块', () {
      final previous = ScheduleProposal(
        blocks: [
          ProposedBlock(
            taskId: 'task-a',
            title: '背单词',
            startAt: _at(0, 9),
            endAt: _at(0, 10),
          ),
          ProposedBlock(
            taskId: 'task-b',
            title: '写报告',
            startAt: _at(0, 14),
            endAt: _at(0, 15),
          ),
        ],
      );

      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v2',
        availability: [_window(0, 8, 22)],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'event-1',
            ownerType: ScheduleOwnerType.event,
            startAt: _at(0, 13, 30),
            endAt: _at(0, 15),
            title: '临时会议',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-a',
            title: '背单词',
            requiredMinutes: 60,
          ),
          ScheduleTaskDemand(
            taskId: 'task-b',
            title: '写报告',
            requiredMinutes: 60,
          ),
        ],
      );

      final repaired = repairSchedule(input, previous);

      final kept = repaired.blocks.firstWhere((b) => b.taskId == 'task-a');
      final moved = repaired.blocks.firstWhere((b) => b.taskId == 'task-b');

      expect(kept.startAt, _at(0, 9));
      expect(kept.movedFromPreviousPlan, isFalse);
      expect(moved.movedFromPreviousPlan, isTrue);
      expect(moved.minutes, 60);
      expect(_overlapsAny(moved, input.fixedBlocks), isFalse);
      expect(
        repaired.notes.map((note) => note.message).join(),
        contains('共移动 1 处安排'),
      );
    });

    test('无可排位置时返回未安排量与理由', () {
      final previous = ScheduleProposal(
        blocks: [
          ProposedBlock(
            taskId: 'task-c',
            title: '大扫除',
            startAt: _at(0, 18),
            endAt: _at(0, 20),
          ),
        ],
      );

      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 9),
        baseVersion: 'v2',
        availability: [
          ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 9)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-c',
            title: '大扫除',
            requiredMinutes: 120,
          ),
        ],
      );

      final repaired = repairSchedule(input, previous);

      expect(repaired.blocks, isEmpty);
      expect(repaired.unplannedTasks, hasLength(1));
      expect(repaired.unplannedTasks.single.remainingMinutes, 120);
      expect(
        repaired.unplannedTasks.single.reason,
        UnplannedReason.windowInsufficient,
      );
    });

    test('上一版未排进去的任务在重排时会被重新尝试', () {
      final previous = ScheduleProposal(
        unplannedTasks: [
          UnplannedTask(
            taskId: 'task-d',
            title: '预习',
            remainingMinutes: 60,
            reason: UnplannedReason.windowInsufficient,
            reasonText: '旧窗口不足',
          ),
        ],
      );

      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v2',
        availability: [_window(0, 8, 22)],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-d',
            title: '预习',
            requiredMinutes: 60,
          ),
        ],
      );

      final repaired = repairSchedule(input, previous);

      expect(repaired.blocks.map((b) => b.taskId), ['task-d']);
      expect(repaired.unplannedTasks, isEmpty);
    });
  });

  group('与 M0 v1 契约对齐', () {
    ScheduleInput mixedInput() => ScheduleInput(
      now: _at(0, 7),
      horizonStart: _at(0, 8),
      horizonEnd: _at(0, 22),
      baseVersion: 'v1',
      availability: [_window(0, 8, 22)],
      demands: [
        ScheduleTaskDemand(
          taskId: 'one-time',
          title: '提交作业',
          requiredMinutes: 60,
          taskKind: ScheduleTaskKind.oneTime,
        ),
        ScheduleTaskDemand(
          taskId: 'recurring',
          title: '背单词',
          requiredMinutes: 30,
          taskKind: ScheduleTaskKind.recurring,
        ),
      ],
    );

    test('单次事项与周期任务分别产出各自的白名单变更', () {
      final proposal = generateSchedule(mixedInput());

      expect(proposal.blocks, hasLength(2));
      expect(proposal.changes, hasLength(2));
      expect(
        proposal.changes.map((change) => change.type),
        unorderedEquals(['schedule_one_time', 'upsert_daily_override']),
      );

      final oneTime = proposal.changes.firstWhere(
        (change) => change is ScheduleOneTimeChange,
      ) as ScheduleOneTimeChange;
      expect(oneTime.taskId, 'one-time');
      expect(oneTime.plannedDate, _at(0, 0));
      expect(oneTime.scheduledAt, _at(0, 8));

      final override = proposal.changes.firstWhere(
        (change) => change is UpsertDailyOverrideChange,
      ) as UpsertDailyOverrideChange;
      expect(override.itemKind, ScheduleTaskKind.recurring);
      expect(override.itemId, 'recurring');
      expect(override.action, 'reschedule');
      expect(override.localDate, _at(0, 0));
      expect(override.plannedStartMinute, 9 * 60);
      expect(override.plannedEndMinute, 9 * 60 + 30);
      expect(override.existingOverrideId, isNull);
    });

    test('提案 JSON 字段与契约第 5.7 节一致', () {
      final json = generateSchedule(mixedInput()).toJson();

      // 方案 A：status 属服务端字段，M2 不输出。
      expect(json.containsKey('status'), isFalse);
      for (final key in [
        'blocks',
        'changes',
        'unplanned_tasks',
        'explanations',
      ]) {
        expect(json.containsKey(key), isTrue, reason: key);
      }

      final block = (json['blocks'] as List).first as Map<String, dynamic>;
      for (final key in [
        'block_id',
        'task_id',
        'task_kind',
        'start_at',
        'end_at',
        'source',
        'persistable_as',
        'duration_source',
        'duration_seconds',
      ]) {
        expect(block.containsKey(key), isTrue, reason: key);
      }
      expect(block['source'], 'proposal');
      expect(block['persistable_as'], 'one_time_schedule');

      final change = (json['changes'] as List).first as Map<String, dynamic>;
      expect(change['change_id'], isA<String>());
      expect(change['type'], 'schedule_one_time');
    });

    test('未显式给出可用窗口时用 preferences 逐日推导', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(1, 20),
        baseVersion: 'v1',
        preferences: const SchedulePreferences(
          dayStartMinute: 9 * 60,
          dayEndMinute: 17 * 60,
        ),
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-p',
            title: '自习',
            requiredMinutes: 60,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, hasLength(1));
      expect(proposal.blocks.single.startAt, _at(0, 9));
      expect(proposal.blocks.single.endAt, _at(0, 10));
    });

    test('小于最小块长度的碎片不参与排程', () {
      final input = ScheduleInput(
        now: _at(0, 7),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        preferences: const SchedulePreferences(minimumBlockMinutes: 60),
        availability: [
          ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 8, 45)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-m',
            title: '零碎任务',
            requiredMinutes: 30,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, isEmpty);
      expect(proposal.unplannedTasks, hasLength(1));
    });
  });

  group('冻结目标守卫', () {
    test('时长优先级：任务自带目标优先于调用方给出的时长', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-target',
            title: '练琴',
            // 调用方说 60 分钟，但任务自带目标是 30 分钟。
            requiredMinutes: 60,
            targetDurationSeconds: 1800,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final block = proposal.blocks.single;

      expect(block.minutes, 30);
      expect(block.durationSource, 'task_target');
      expect(
        jsonDecode(jsonEncode(proposal.toJson()))['blocks'].first['duration_seconds'],
        1800,
      );
    });

    test('时长兜底为 max(minimum_block_minutes, 30)，且一律算估算', () {
      ScheduleTaskDemand noDuration(String id) => ScheduleTaskDemand(
        taskId: id,
        title: '无目标也无估算：$id',
        // 既没有 duration_target_seconds，服务端也没给估算。
        requiredMinutes: 0,
      );

      // 偏好给 15 分钟，但契约第三级的地板值固定是 30 分钟。
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        preferences: const SchedulePreferences(minimumBlockMinutes: 15),
        demands: [noDuration('fallback-floor')],
      );

      final block = generateSchedule(input).blocks.single;
      expect(
        block.minutes,
        30,
        reason: '偏好低于 30 分钟时兜底仍取 30，契约第 5.6 节已写死该 floor',
      );
      expect(block.durationSource, 'scheduler_estimate');

      // 偏好高于 30 分钟时按偏好值兜底。
      final higher = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        preferences: const SchedulePreferences(minimumBlockMinutes: 45),
        demands: [noDuration('fallback-higher')],
      );

      final blockHigher = generateSchedule(higher).blocks.single;
      expect(blockHigher.minutes, 45);
      expect(blockHigher.durationSource, 'scheduler_estimate');
    });

    test('remaining_minutes_today 为 0 时不再排程，且不算未安排', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12))],
        demands: [
          ScheduleTaskDemand(
            taskId: 'done',
            title: '背单词',
            requiredMinutes: 60,
            // 当天已经做完：不准再排，也不准报成排不下。
            remainingMinutesToday: 0,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      expect(proposal.blocks, isEmpty);
      expect(proposal.unplannedTasks, isEmpty);
      // 契约允许 track 它发生了什么：这里用一条 code 化的说明交代原因。
      expect(
        proposal.notes.map((note) => note.code),
        contains('ALREADY_DONE_TODAY'),
      );
    });

    test('remaining_minutes_today 非空时优先于完整目标', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12))],
        demands: [
          ScheduleTaskDemand(
            taskId: 'half-done',
            title: '刷题',
            requiredMinutes: 120,
            targetDurationSeconds: 3600,
            // 当天只剩 30 分钟：只排 30 分钟，且必须标 task_target。
            remainingMinutesToday: 30,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final block = proposal.blocks.single;

      expect(block.minutes, 30);
      expect(block.durationSource, 'task_target');
    });

    test('P3 样例一：remaining_minutes_today=0 不排程、不算未安排、产出 ALREADY_DONE_TODAY', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        demands: [
          ScheduleTaskDemand(
            taskId: 'done-today',
            title: '背单词',
            // 完整目标 120 分钟，但当天已经做完。
            requiredMinutes: 120,
            targetDurationSeconds: 7200,
            remainingMinutesToday: 0,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final codes = proposal.notes.map((note) => note.code).toList();

      expect(proposal.blocks, isEmpty);
      expect(proposal.unplannedTasks, isEmpty);
      expect(codes, contains('ALREADY_DONE_TODAY'));
      expect(kPublicExplanationCodes, contains('ALREADY_DONE_TODAY'));
      // = 0 是「已做完」而非「没有时长依据」，绝不能落到兜底去排 30 分钟。
      expect(codes, isNot(contains('SCHEDULED')));
      expect(codes, isNot(contains('ESTIMATED_DURATION')));
    });

    test('P3 样例二：remaining_minutes_today=40 时只排 40 分钟且标 task_target', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        demands: [
          ScheduleTaskDemand(
            taskId: 'partial-done',
            title: '刷题',
            // 完整目标 120 分钟、快照估算 120 分钟，但当天只剩 40 分钟。
            requiredMinutes: 120,
            targetDurationSeconds: 7200,
            remainingMinutesToday: 40,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final block = proposal.blocks.single;

      expect(block.minutes, 40);
      // 判据用精确秒数（2400s），不用「40 分钟」文字（C 的 G2 口径）。
      expect(block.durationSeconds, 2400);
      expect(block.durationSource, 'task_target');
    });

    test('horizon 起止会改变输出，因此 input_digest 必须覆盖它', () {
      ScheduleInput build(DateTime horizonEnd) => ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: horizonEnd,
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        demands: [
          ScheduleTaskDemand(taskId: 'a', title: '任务甲', requiredMinutes: 60),
          ScheduleTaskDemand(taskId: 'b', title: '任务乙', requiredMinutes: 60),
          ScheduleTaskDemand(taskId: 'c', title: '任务丙', requiredMinutes: 60),
        ],
      );

      // 窄 horizon 只到 10:30：三条 60 分钟需求里只有第一条排得下。
      final narrow = generateSchedule(build(_at(0, 10, 30)));
      final wide = generateSchedule(build(_at(0, 22)));

      // 只差 horizonEnd，输出就不同 —— 摘要不覆盖 horizon 的话，
      // 两个不同提案会拿到同一个 input_digest，validate 察觉不到。
      expect(jsonEncode(narrow.toJson()), isNot(jsonEncode(wide.toJson())));
      expect(wide.blocks.length, greaterThan(narrow.blocks.length));
    });

    test('时区只作为可规范化字段携带，M2 不做时区转换', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12))],
        demands: [
          ScheduleTaskDemand(taskId: 'tz', title: '时区用例', requiredMinutes: 30),
        ],
      );

      // 契约要求的时区标识在输入上，服务端规范化摘要时要把它算进去。
      expect(input.timezone, 'Asia/Shanghai');
      // 如实标注局限：M2 直接用 Dart DateTime，不转换时区，
      // 假设服务端传入的已是 +08:00。时区解析归 M0。
      expect(generateSchedule(input).blocks.single.startAt, _at(0, 9));
    });

    test('B19：remaining_minutes_today 三态语义（null / 0 / 正数）', () {
      ScheduleInput build(int? remaining) => ScheduleInput(
            now: _at(0, 8),
            horizonStart: _at(0, 8),
            horizonEnd: _at(0, 22),
            baseVersion: 'v1',
            availability: [
              ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22)),
            ],
            demands: [
              ScheduleTaskDemand(
                taskId: 'recurring-three-state',
                title: '每日练琴',
                requiredMinutes: 120,
                targetDurationSeconds: 7200,
                remainingMinutesToday: remaining,
                taskKind: ScheduleTaskKind.recurring,
              ),
            ],
          );

      // null：没有当日口径，按完整目标 120 分钟排，标 task_target。
      final asNull = generateSchedule(build(null));
      expect(asNull.blocks.single.minutes, 120);
      expect(asNull.blocks.single.durationSource, 'task_target');

      // 0：当天已做完 —— 不排、不计未安排、产出 ALREADY_DONE_TODAY。
      final asZero = generateSchedule(build(0));
      expect(asZero.blocks, isEmpty);
      expect(asZero.unplannedTasks, isEmpty);
      expect(asZero.notes.map((note) => note.code), contains('ALREADY_DONE_TODAY'));

      // 正数：当日剩余就是本次要排的量，完整目标 120 被折算为 40。
      final asForty = generateSchedule(build(40));
      expect(asForty.blocks.single.minutes, 40);
      expect(asForty.blocks.single.durationSource, 'task_target');

      // 三态都排在第三级兜底之前：绝不退化成 30 分钟兜底，也不标估算。
      for (final proposal in <ScheduleProposal>[asNull, asZero, asForty]) {
        final codes = proposal.notes.map((note) => note.code).toList();
        expect(codes, isNot(contains('ESTIMATED_DURATION')));
      }
    });

    test('时区标签不改变 M2 输出（M2 不做时区转换）', () {
      ScheduleInput build(String timezone) => ScheduleInput(
            now: _at(0, 8),
            horizonStart: _at(0, 8),
            horizonEnd: _at(0, 22),
            baseVersion: 'v1',
            timezone: timezone,
            availability: [
              ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
            ],
            demands: [
              ScheduleTaskDemand(
                taskId: 'tz-digest',
                title: '时区摘要用例',
                requiredMinutes: 30,
              ),
            ],
          );

      final shanghai = generateSchedule(build('Asia/Shanghai'));
      final utc = generateSchedule(build('UTC'));

      // M2 完全无视时区标签：两个不同时区拿到逐字节相同的排程。
      expect(jsonEncode(shanghai.toJson()), jsonEncode(utc.toJson()));
      expect(shanghai.blocks.single.startAt, _at(0, 9));

      // 撤回「digest 必须纳入时区」的结论（C 指正）：契约把 timezone 固定为
      // Asia/Shanghai、不接受其他值，纳入 digest 永远不产生区分度。
      // 真正要防的是 horizon，见上一条用例。
    });

    test('内部调度 DTO 递归不含任何服务端字段', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 10)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'internal-dto',
            title: '内部 DTO 用例',
            requiredMinutes: 60,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      const serverFields = <String>{
        'proposal_id',
        'snapshot_ref',
        'input_digest',
        'generated_at',
        'expires_at',
        'base_version',
        'status',
      };

      void walk(Object? node) {
        if (node is Map) {
          for (final entry in node.entries) {
            expect(
              serverFields,
              isNot(contains(entry.key)),
              reason: '${entry.key} 是服务端字段，方案 A 下不得出现在 M2 输出里',
            );
            walk(entry.value);
          }
        } else if (node is List) {
          for (final value in node) {
            walk(value);
          }
        }
      }

      walk(jsonDecode(jsonEncode(proposal.toJson())));
    });

    test('explanations 码必须落在 v1 公共枚举内，repair 专用码不得外泄', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 22))],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-x',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 10),
            endAt: _at(0, 12),
            title: '编译原理',
          ),
        ],
        demands: [
          // 无目标无估算 → 走第三级兜底，必然带 ESTIMATED_DURATION。
          ScheduleTaskDemand(taskId: 'estimated', title: '整理笔记', requiredMinutes: 0),
        ],
      );

      final proposal = generateSchedule(input);

      // generateSchedule 的每一条解释都必须能进 v1 远程响应。
      expect(proposal.notes, isNotEmpty);
      for (final note in proposal.notes) {
        expect(
          note.isPublic,
          isTrue,
          reason: '${note.code} 不在 v1 公共枚举内，服务端必须过滤或补进枚举',
        );
      }
      // 这次输入必然覆盖到枚举里的两个「新」码。
      final codes = proposal.notes.map((note) => note.code).toList();
      expect(codes, contains('PRESERVED_FIXED_EVENTS'));
      expect(codes, contains('ESTIMATED_DURATION'));

      // repair 结果允许带 repair 专用码，但只允许那两个。
      final repaired = repairSchedule(input, proposal);
      for (final note in repaired.notes) {
        expect(
          note.isPublic || kRepairOnlyExplanationCodes.contains(note.code),
          isTrue,
          reason: '${note.code} 既不是公共码也不是已登记的 repair 专用码',
        );
      }

      // 服务端按 publicExplanations 序列化时，repair 专用码被滤掉。
      final publicCodes = repaired.publicExplanations.map((note) => note.code);
      for (final code in kRepairOnlyExplanationCodes) {
        expect(publicCodes, isNot(contains(code)));
      }
    });

    test('未安排项带 reason_code、remaining_minutes 与 message', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 9),
        baseVersion: 'v1',
        availability: [ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 8, 20))],
        demands: [
          ScheduleTaskDemand(taskId: 'no-room', title: '长任务', requiredMinutes: 45),
        ],
      );

      final proposal = generateSchedule(input);
      final json = jsonDecode(jsonEncode(proposal.toJson())) as Map<String, dynamic>;
      final items = json['unplanned_tasks'] as List<dynamic>;

      expect(items, hasLength(1));
      final item = items.first as Map<String, dynamic>;
      expect(item['task_id'], 'no-room');
      expect(item['reason_code'], 'WINDOW_INSUFFICIENT');
      expect(item['remaining_minutes'], 45);
      expect(item['message'], isA<String>());
    });

    test('写入次数可推算：每 block 恰一条白名单变更，change_id 唯一，状态恒为 draft', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(2, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
          ScheduleWindow(startAt: _at(1, 9), endAt: _at(1, 12)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'recurring-write',
            title: '周期：每日练琴',
            requiredMinutes: 60,
            taskKind: ScheduleTaskKind.recurring,
          ),
          ScheduleTaskDemand(
            taskId: 'onetime-write',
            title: '单次：交报告',
            requiredMinutes: 45,
            taskKind: ScheduleTaskKind.oneTime,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      // C 的判定项之一：期望写入次数可直接由提案推算，不必先执行。
      expect(proposal.changes, hasLength(proposal.blocks.length));

      final ids = proposal.changes.map((change) => change.toJson()['change_id']);
      expect(ids.toSet(), hasLength(ids.length));

      // 契约第 5.7 节白名单只有两种 change type。
      final allowedTypes = {'schedule_one_time', 'upsert_daily_override'};
      for (final change in proposal.changes) {
        final json = change.toJson();
        expect(allowedTypes, contains(json['type']), reason: json.toString());
        // Open Question 5 未定之前，最小权限只输出 reschedule。
        final action = json['action'];
        if (action != null) expect(action, 'reschedule');
      }

      // 「状态」判定项：纯函数不得产生终态，也不得自己构造服务端字段。
      // 方案 A：M2 只输出内部四部分，status/snapshot_ref/input_digest 均不序列化。
      expect(proposal.toJson().containsKey('status'), isFalse);
      expect(proposal.toJson().containsKey('snapshot_ref'), isFalse);
      expect(proposal.toJson().containsKey('input_digest'), isFalse);
    });

    test('周期任务同一本地日最多一个 block，且同一 (任务, 日期) 只产出一条变更', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(2, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
          ScheduleWindow(startAt: _at(1, 9), endAt: _at(1, 12)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'recurring-one',
            title: '每日复现练琴',
            requiredMinutes: 60,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);

      final keyed = <String>{};
      for (final change in proposal.changes) {
        final json = change.toJson();
        final key = '${json['item_id'] ?? json['task_id']}@'
            '${json['local_date'] ?? json['planned_date']}';
        expect(keyed.add(key), isTrue, reason: '同一任务同一日期重复： $key');
      }
      // 本次只排首日：同一 proposal 内不会自动把同一周期任务铺开到多天。
      expect(keyed, hasLength(1));
      expect(proposal.changes.single.toJson()['change_id'], isNotNull);
    });

    test('DTO 键集合与契约逐字对齐：不多不少，服务端字段除外', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 10)),
        ],
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-x',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 10),
            endAt: _at(0, 12),
            title: '编译原理',
          ),
          ScheduleFixedBlock(
            ownerId: 'event-y',
            ownerType: ScheduleOwnerType.event,
            startAt: _at(0, 11),
            endAt: _at(0, 13),
            title: '临时会议',
          ),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'recurring-dto',
            title: '周期：每日练琴',
            requiredMinutes: 20,
            taskKind: ScheduleTaskKind.recurring,
          ),
          ScheduleTaskDemand(
            taskId: 'onetime-dto',
            title: '单次：体检',
            requiredMinutes: 20,
            taskKind: ScheduleTaskKind.oneTime,
          ),
          // 这个必然排不下，用来检查 unplanned_tasks 的形状。
          ScheduleTaskDemand(
            taskId: 'recurring-too-long',
            title: '周期：写大论文',
            requiredMinutes: 600,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final json = jsonDecode(jsonEncode(proposal.toJson())) as Map<String, dynamic>;

      // 顶层：方案 A 下 M2 只输出内部四部分，服务端权威字段一律不出现。
      const allowedTopLevelKeys = <String>{
        'blocks',
        'changes',
        'unplanned_tasks',
        'explanations',
      };
      for (final key in json.keys) {
        expect(allowedTopLevelKeys, contains(key),
            reason: '方案 A 下 M2 不得输出该顶层字段：$key');
      }
      for (final key in const [
        'blocks',
        'changes',
        'unplanned_tasks',
        'explanations',
      ]) {
        expect(json.containsKey(key), isTrue, reason: '缺少 M2 内部结果字段 $key');
      }

      // 展示块：§5.6 的九个字段，一个不多一个不少。
      const expectedBlockKeys = <String>{
        'block_id',
        'task_id',
        'task_kind',
        'start_at',
        'end_at',
        'source',
        'persistable_as',
        'duration_source',
        'duration_seconds',
      };
      final blocks = json['blocks'] as List<dynamic>;
      expect(blocks, isNotEmpty);
      for (final item in blocks) {
        expect((item as Map<String, dynamic>).keys.toSet(), expectedBlockKeys);
      }

      // 两种白名单 change 的键集合分别严格相等。
      final changes = json['changes'] as List<dynamic>;
      expect(changes, isNotEmpty);
      for (final item in changes) {
        final map = item as Map<String, dynamic>;
        final keys = map.keys.toSet();
        if (map['type'] == 'schedule_one_time') {
          expect(keys, {'change_id', 'type', 'task_id', 'planned_date', 'scheduled_at'});
        } else {
          expect(keys, {
            'change_id',
            'type',
            'item_type',
            'item_id',
            'local_date',
            'action',
            'planned_start_minute',
            'planned_end_minute',
          });
        }
      }

      // 未安排项：§5.7 只允许这四个键，`title` 不得混进 JSON。
      final unplanned = json['unplanned_tasks'] as List<dynamic>;
      expect(unplanned, isNotEmpty);
      for (final item in unplanned) {
        expect(
          (item as Map<String, dynamic>).keys.toSet(),
          {'task_id', 'remaining_minutes', 'reason_code', 'message'},
        );
      }

      // 解释：对象数组，键集合 ⊆ {code, message, related_task_ids}。
      final explanations = json['explanations'] as List<dynamic>;
      expect(explanations, isNotEmpty);
      for (final item in explanations) {
        final map = item as Map<String, dynamic>;
        for (final key in map.keys) {
          expect({'code', 'message', 'related_task_ids'}, contains(key));
        }
        expect(map.containsKey('code'), isTrue);
        expect(map.containsKey('message'), isTrue);
      }
    });

    test('单次事项必须显式带与 planned_date 同日的 scheduled_at', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(2, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'onetime-guarded',
            title: '单次：体检预约',
            requiredMinutes: 45,
            taskKind: ScheduleTaskKind.oneTime,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final oneTime = proposal.changes.whereType<ScheduleOneTimeChange>().toList();

      expect(oneTime, isNotEmpty);
      for (final change in oneTime) {
        final json = change.toJson();
        // 契约第 5.7 节：省略 scheduled_at 表示保留现值，保留后的值若与新的
        // planned_date 不同日必须以 PROPOSAL_INVALID 拒绝，否则会出现
        // "写入成功但有效计划日期仍来自旧 scheduled_at"的假成功。
        // M2 一律显式给出同一本地日的 scheduled_at，从源头不留这条路径。
        expect(json['scheduled_at'], isNotNull, reason: json.toString());
        final scheduledAt = DateTime.parse(json['scheduled_at'] as String);
        expect(
          scheduleDayOnly(scheduledAt),
          scheduleDayOnly(change.plannedDate),
          reason: 'scheduled_at 必须与 planned_date 同属一个本地日',
        );
      }
    });

    test('单日例外变更字段齐全、分钟合法，且同一唯一键在提案内只出现一次', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 9), endAt: _at(0, 12)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'recurring-override-a',
            title: '周期：每日练琴',
            requiredMinutes: 60,
            taskKind: ScheduleTaskKind.recurring,
          ),
          ScheduleTaskDemand(
            taskId: 'recurring-override-b',
            title: '周期：每日阅读',
            requiredMinutes: 30,
            taskKind: ScheduleTaskKind.recurring,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final overrides =
          proposal.changes.whereType<UpsertDailyOverrideChange>().toList();

      expect(overrides, hasLength(2));

      // 契约第 6.7 节：这七个字段缺一不可，否则回读必然失败。
      const requiredKeys = <String>{
        'change_id',
        'type',
        'item_type',
        'item_id',
        'local_date',
        'action',
        'planned_start_minute',
        'planned_end_minute',
      };

      final uniqueKeys = <String>{};
      for (final change in overrides) {
        final json = change.toJson();
        for (final key in requiredKeys) {
          expect(json.containsKey(key), isTrue, reason: '$key 缺失 → $json');
        }
        // 不允许借用单日例外去改课程。
        expect({'recurring', 'one_time'}, contains(json['item_type']));
        expect(json['type'], 'upsert_daily_override');
        expect(json['action'], 'reschedule');

        final start = json['planned_start_minute'] as int;
        final end = json['planned_end_minute'] as int;
        expect(start, greaterThanOrEqualTo(0));
        expect(start, lessThan(1440));
        // 契约第 5.7 节：结束分钟必须晚于开始分钟。
        expect(end, greaterThan(start), reason: json.toString());
        expect(end, lessThanOrEqualTo(1440));

        // existing_override_id 只能来自可信读取，模型不得猜测。
        expect(json['existing_override_id'], isNull);

        // (user, item_type, item_id, local_date) 在提案内不得重复，
        // 否则服务端会撞第 5.7 节的唯一键冲突并触发零写入。
        expect(
          uniqueKeys.add(
            '${json['item_type']}|${json['item_id']}|${json['local_date']}',
          ),
          isTrue,
          reason: json.toString(),
        );
      }
    });

    test('reason_code 取值必须落在封闭枚举内', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 9),
        baseVersion: 'v1',
        availability: [
          ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 8, 10)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'too-long',
            title: '放不下的任务',
            requiredMinutes: 120,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final allowed = UnplannedReason.values.map((reason) => reason.code).toSet();

      for (final task in proposal.unplannedTasks) {
        expect(allowed, contains(task.reason.code), reason: task.taskId);
      }
      expect(proposal.unplannedTasks, isNotEmpty);
    });

    test('explanations 元素结构统一，且不带额外字段', () {
      final input = ScheduleInput(
        now: _at(0, 8),
        horizonStart: _at(0, 8),
        horizonEnd: _at(0, 22),
        baseVersion: 'v1',
        // 两条硬约束互相重叠，用于产生一条解释。
        fixedBlocks: [
          ScheduleFixedBlock(
            ownerId: 'course-a',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 9),
            endAt: _at(0, 10),
          ),
          ScheduleFixedBlock(
            ownerId: 'course-b',
            ownerType: ScheduleOwnerType.course,
            startAt: _at(0, 9, 30),
            endAt: _at(0, 10, 30),
          ),
        ],
        availability: [
          ScheduleWindow(startAt: _at(0, 8), endAt: _at(0, 22)),
        ],
        demands: [
          ScheduleTaskDemand(
            taskId: 'task-note',
            title: '复习',
            requiredMinutes: 30,
          ),
        ],
      );

      final proposal = generateSchedule(input);
      final json = jsonDecode(jsonEncode(proposal.toJson())) as Map<String, dynamic>;
      final explanations = json['explanations'] as List<dynamic>;

      expect(explanations, isNotEmpty);
      for (final item in explanations) {
        final map = item as Map<String, dynamic>;
        // 契约第 5.7 节：对象数组，每项含 code 与 message，可选 related_task_ids，
        // 不再允许字符串与对象混用。
        expect(map.containsKey('code'), isTrue);
        expect(map.containsKey('message'), isTrue);
        final allowedExplanationKeys = {
          'code',
          'message',
          'related_task_ids',
        };
        for (final key in map.keys) {
          expect(allowedExplanationKeys, contains(key));
        }
        expect(map['code'], isA<String>());
        expect(map['message'], isA<String>());
      }
    });
  });

  group('模块边界', () {
    test('调度模块不得访问数据库或任何应用层代码', () {
      for (final path in [
        'lib/features/agent_scheduler/domain/schedule_contract.dart',
        'lib/features/agent_scheduler/domain/schedule_engine.dart',
      ]) {
        // 只扫描代码：本模块的文档注释里本就会出现这些名字（用于说明"不得依赖"），
        // 若连注释一起匹配，守卫会被自己绊倒。
        final code = stripComments(File(path).readAsStringSync());
        expect(code, isNot(contains('package:drift')), reason: path);
        expect(code, isNot(contains('package:supabase')), reason: path);
        expect(code, isNot(contains('task_repository')), reason: path);
        expect(code, isNot(contains('app_database')), reason: path);
        expect(code, isNot(contains('DateTime.now()')), reason: path);
      }
    });
  });
}
