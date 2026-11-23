// Explicit opt-in: flutter test --no-pub tool/agent/live_workflow_test.dart
// The local bridge must already be running. All business data is in-memory.
import 'dart:convert';
import 'dart:io';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/features/agent/data/agent_gateway.dart';
import 'package:check_d/features/agent/data/agent_repository.dart';
import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'live model proposal → preview → confirm → update → archive → safe undo',
    () async {
      final runtime =
          jsonDecode(
                await File(
                  '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}/.codex/tmp/checkd-agent-runtime.json',
                ).readAsString(),
              )
              as Map;
      final gateway = LocalAgentGateway(
        endpoint: Uri.parse(runtime['endpoint'] as String),
        token: runtime['token'] as String,
      );
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final agent = AgentRepository(
        database: database,
        userId: 'live-test-owner',
      );

      Future<AgentProposal> propose(String text) async {
        final context = await agent.buildContext();
        final result = await gateway.propose(
          request: text,
          context: context,
          history: (await agent.loadWorkspace()).messages,
        );
        return agent.prepareProposal(result);
      }

      final created = await propose(
        '添加一个不安排时间的单次事项“联调资料整理”，非计时，备注“先列目录”。只添加这一个事项，不要创建档案或改作息。',
      );
      expect(created.operations.map((o) => o.action), ['create_task']);
      expect(
        await database.select(database.localTasks).get(),
        isEmpty,
        reason: 'model and preview never write business data',
      );
      await agent.applyProposal(created);
      final task = (await database.select(database.localTasks).get()).single;
      expect(task.name, '联调资料整理');
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );

      final renamed = await propose('仅把“联调资料整理”改名为“联调资料归类”，不要改时间、类型或其他资料。');
      expect(renamed.operations.single.entityId, task.id);
      await agent.applyProposal(renamed);
      expect(
        (await database.select(database.localTasks).get()).single.name,
        '联调资料归类',
      );

      final archived = await propose('删除“联调资料归类”，保留历史。不要修改其他数据。');
      expect(archived.operations.single.action, 'archive_task');
      await agent.applyProposal(archived);
      expect(
        (await database.select(database.localTasks).get()).single.status ==
            'archived',
        true,
      );
      await agent.undoLast();
      final restored =
          (await database.select(database.localTasks).get()).single;
      expect(restored.id, task.id);
      expect(restored.status == 'archived', false);
      expect(restored.name, '联调资料归类');
      expect(
        await database.select(database.timerSessionRecords).get(),
        isEmpty,
      );
      expect(
        await database.select(database.taskCompletionRecords).get(),
        isEmpty,
      );

      final query = await propose('我现在有哪些事项？仅查询。');
      expect(query.operations, isEmpty);
      expect(query.reply, contains('联调资料归类'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
