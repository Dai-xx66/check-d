import 'dart:async';

import 'package:check_d/core/database/app_database.dart';
import 'package:check_d/core/theme/app_skin.dart';
import 'package:check_d/core/theme/app_theme.dart';
import 'package:check_d/features/agent/application/agent_providers.dart';
import 'package:check_d/features/agent/data/agent_gateway.dart';
import 'package:check_d/features/agent/data/agent_repository.dart';
import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:check_d/features/agent/presentation/agent_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'agent fits original app theme at $width and keeps changes pending',
      (tester) async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        final repository = _FakeRepository(database);
        final gateway = _FakeGateway();
        addTearDown(() async {
          await repository.close();
          await database.close();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_host(repository, gateway));
        await tester.pumpAndSettle();
        expect(find.text('CheckD 智能体'), findsOneWidget);
        expect(find.text('先说说，你想完成什么？'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(
          find.byKey(const ValueKey('agent-composer')),
          '创建一个学习事项',
        );
        await tester.tap(find.byKey(const ValueKey('agent-send')));
        await tester.pumpAndSettle();
        expect(gateway.calls, 1);
        expect(repository.applies, 0);
        expect(find.textContaining('待确认的改动'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('agent-confirm')));
        await tester.tap(find.byKey(const ValueKey('agent-confirm')));
        await tester.pumpAndSettle();
        expect(repository.applies, 1);
        expect(find.byKey(const ValueKey('agent-confirm')), findsNothing);
        expect(find.text('已创建学习事项'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed request retains composer and locally added attachment', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _FakeRepository(database);
    final gateway = _FakeGateway()..fail = true;
    addTearDown(() async {
      await repository.close();
      await database.close();
    });
    await tester.pumpWidget(_host(repository, gateway));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AgentPage)),
    );
    container.read(agentInteractionProvider.notifier).addAttachments([
      const AgentAttachment(name: '课程说明.txt', kind: 'TXT', text: '资料只作为数据'),
    ]);
    await tester.pump();
    expect(gateway.calls, 0);
    await tester.enterText(
      find.byKey(const ValueKey('agent-composer')),
      '请先看看这些资料',
    );
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pumpAndSettle();
    expect(find.text('课程说明.txt'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('agent-composer')))
          .controller!
          .text,
      '请先看看这些资料',
    );
    expect(repository.applies, 0);
    expect(find.text('服务暂时不可用，请重试。'), findsOneWidget);
    gateway.fail = false;
    await tester.tap(find.byKey(const ValueKey('agent-send')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 2);
    expect(repository.applies, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ordinary response never offers apply and preserves clarification material',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = _FakeRepository(database);
      final gateway = _FakeGateway()
        ..operations = const []
        ..warnings = const ['课表覆盖范围尚未确认。'];
      addTearDown(() async {
        await repository.close();
        await database.close();
      });
      await tester.pumpWidget(_host(repository, gateway));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentPage)),
      );
      container.read(agentInteractionProvider.notifier).addAttachments([
        const AgentAttachment(name: '日期待确认.txt', kind: 'TXT', text: '等待日期'),
      ]);
      await tester.enterText(
        find.byKey(const ValueKey('agent-composer')),
        '帮我核对课表',
      );
      await tester.tap(find.byKey(const ValueKey('agent-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-confirm')), findsNothing);
      expect(find.text('日期待确认.txt'), findsOneWidget);
      expect(find.textContaining('提醒：课表覆盖范围尚未确认。'), findsOneWidget);
      expect(repository.applies, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('phone composer remains visible above keyboard', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = _FakeRepository(database);
    addTearDown(() async {
      await repository.close();
      await database.close();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(_host(repository, _FakeGateway()));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('agent-send'))).bottom,
      lessThanOrEqualTo(544),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'late response after owner changes cannot save reply or apply a proposal',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = _FakeRepository(database);
      final gateway = _FakeGateway()..completion = Completer<AgentProposal>();
      var ownerValid = true;
      final container = ProviderContainer(
        overrides: [
          agentOwnerProvider.overrideWithValue('owner-a'),
          agentOwnerGuardProvider.overrideWithValue((_) => ownerValid),
          agentRepositoryProvider.overrideWithValue(repository),
          agentGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.close();
        await database.close();
      });
      final action = container
          .read(agentInteractionProvider.notifier)
          .send('更新日程');
      await Future<void>.delayed(Duration.zero);
      ownerValid = false;
      gateway.completion!.complete(
        const AgentProposal(
          id: 'late',
          reply: '不应写入',
          contextRevision: 'r1',
          operations: [
            AgentOperation(action: 'create_task', data: {'name': '不应创建'}),
          ],
        ),
      );
      expect(await action, isFalse);
      expect(
        repository.workspace.messages.where((m) => m.role == 'assistant'),
        isEmpty,
      );
      expect(repository.applies, 0);
      expect(container.read(agentInteractionProvider).pending, isNull);
    },
  );

  testWidgets(
    'switching account closes private forms and clears draft materials',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = _FakeRepository(database);
      addTearDown(() async {
        await repository.close();
        await database.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentOwnerProvider.overrideWith(
              (ref) => ref.watch(_testOwnerProvider),
            ),
            agentOwnerGuardProvider.overrideWithValue((_) => true),
            agentRepositoryProvider.overrideWithValue(repository),
            agentGatewayProvider.overrideWithValue(_FakeGateway()),
          ],
          child: MaterialApp(
            theme: AppTheme.build(AppSkin.slate),
            home: const AgentPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentPage)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('agent-composer')),
        '账号A的私有草稿',
      );
      container.read(agentInteractionProvider.notifier).addAttachments([
        const AgentAttachment(name: '账号A.txt', kind: 'TXT', text: '私有内容'),
      ]);
      await tester.tap(find.byTooltip('智能体选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作息与时间预算'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      container.read(_testOwnerProvider.notifier).change('owner-b');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('账号A.txt'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('agent-composer')))
            .controller!
            .text,
        isEmpty,
      );
      expect(repository.applies, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in ['apply', 'course', 'questions', 'failure']) {
    test('optional automatic apply is bounded: $scenario', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = _FakeRepository(database)
        ..workspace = const AgentWorkspace(profile: {'autoApply': true})
        ..failApply = scenario == 'failure';
      final gateway = _FakeGateway();
      if (scenario == 'course') {
        gateway.operations = const [
          AgentOperation(action: 'create_course', data: {'name': '英语'}),
        ];
      }
      if (scenario == 'questions') gateway.questions = const ['请先确认日期'];
      final container = ProviderContainer(
        overrides: [
          agentOwnerProvider.overrideWithValue('owner-a'),
          agentOwnerGuardProvider.overrideWithValue((_) => true),
          agentRepositoryProvider.overrideWithValue(repository),
          agentGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.close();
        await database.close();
      });
      final controller = container.read(agentInteractionProvider.notifier);
      controller.addAttachments([
        const AgentAttachment(name: '材料.txt', kind: 'TXT', text: '保留'),
      ]);
      final success = await controller.send('安排学习');
      final result = container.read(agentInteractionProvider);
      expect(repository.applies, scenario == 'apply' ? 1 : 0);
      expect(result.pending == null, scenario == 'apply');
      expect(result.appliedSummary != null, scenario == 'apply');
      expect(success, scenario != 'failure');
      if (scenario == 'failure') expect(result.attachments, hasLength(1));
    });
  }

  testWidgets(
    'structured feedback can link its learning task without applying it',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = _FakeRepository(database)
        ..workspace = const AgentWorkspace(
          taskLinks: [
            {'taskId': 'listening', 'title': '听力训练'},
          ],
        );
      addTearDown(() async {
        await repository.close();
        await database.close();
      });
      await tester.pumpWidget(_host(repository, _FakeGateway()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('反馈进度'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('听力训练').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(2), '完成一套听力，定位题较难');
      await tester.tap(find.text('查看记录预览'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentPage)),
      );
      expect(
        container
            .read(agentInteractionProvider)
            .pending
            ?.operations
            .single
            .data['taskId'],
        'listening',
      );
      expect(repository.applies, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final _testOwnerProvider = NotifierProvider<_TestOwner, String>(_TestOwner.new);

class _TestOwner extends Notifier<String> {
  @override
  String build() => 'owner-a';
  void change(String value) => state = value;
}

Widget _host(_FakeRepository repository, _FakeGateway gateway) => ProviderScope(
  overrides: [
    agentOwnerProvider.overrideWithValue('owner-a'),
    agentOwnerGuardProvider.overrideWithValue((_) => true),
    agentRepositoryProvider.overrideWithValue(repository),
    agentGatewayProvider.overrideWithValue(gateway),
  ],
  child: MaterialApp(
    theme: AppTheme.build(AppSkin.slate),
    home: const AgentPage(),
  ),
);

class _FakeRepository extends AgentRepository {
  _FakeRepository(AppDatabase database)
    : super(database: database, userId: 'owner-a');
  AgentWorkspace workspace = const AgentWorkspace();
  final _changes = StreamController<AgentWorkspace>.broadcast();
  int applies = 0;
  bool failApply = false;
  void _emit() {
    if (!_changes.isClosed) _changes.add(workspace);
  }

  Future<void> close() => _changes.close();
  @override
  Future<AgentWorkspace> loadWorkspace() async => workspace;
  @override
  Stream<AgentWorkspace> watchWorkspace() async* {
    yield workspace;
    yield* _changes.stream;
  }

  @override
  Future<AgentContext> buildContext() async =>
      const AgentContext(ownerId: 'owner-a', revision: 'r1', data: {});
  @override
  Future<void> appendMessage(AgentChatMessage message) async {
    workspace = workspace.copyWith(messages: [...workspace.messages, message]);
    _emit();
  }

  @override
  Future<AgentProposal> prepareProposal(AgentProposal proposal) async =>
      proposal;
  @override
  Future<AgentApplyResult> applyProposal(AgentProposal proposal) async {
    if (failApply) throw const AgentException('数据已变化，请重新预览。');
    applies++;
    return const AgentApplyResult(summary: '已创建学习事项', changedCount: 1);
  }
}

class _FakeGateway implements AgentGateway {
  bool fail = false;
  int calls = 0;
  Completer<AgentProposal>? completion;
  List<String> warnings = const [];
  List<String> questions = const [];
  List<AgentOperation> operations = const [
    AgentOperation(
      action: 'create_task',
      data: {'name': '阅读练习', 'kind': 'oneTime'},
    ),
  ];
  @override
  Future<String> diagnose() async => '连接正常';
  @override
  Future<AgentProposal> propose({
    required String request,
    required AgentContext context,
    required List<AgentChatMessage> history,
    List<AgentAttachment> attachments = const [],
  }) async {
    calls++;
    if (fail) throw const AgentException('服务暂时不可用，请重试。');
    if (completion != null) return completion!.future;
    return AgentProposal(
      id: 'proposal-1',
      reply: '已核对。请先确认下面的改动。',
      contextRevision: context.revision,
      operations: operations,
      warnings: warnings,
      questions: questions,
    );
  }
}
