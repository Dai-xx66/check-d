import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/agent_gateway.dart';
import '../data/agent_repository.dart';
import '../domain/agent_models.dart';

final agentAuthEventsProvider = StreamProvider<String?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client?.auth.currentUser?.id;
  if (client != null) {
    yield* client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  }
});

final agentOwnerProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth.status == AuthStatus.offline) return 'offline-user';
  final session = ref.watch(agentAuthEventsProvider);
  final current = ref.watch(supabaseClientProvider)?.auth.currentUser?.id;
  return (session.hasValue ? session.value : current) ?? 'offline-user';
});

final agentOwnerGuardProvider = Provider<bool Function(String)>((ref) {
  return (owner) {
    if (owner != ref.read(agentOwnerProvider)) return false;
    final offline =
        ref.read(authControllerProvider).status == AuthStatus.offline;
    final client = ref.read(supabaseClientProvider);
    final actual = offline
        ? 'offline-user'
        : client?.auth.currentUser?.id ?? 'offline-user';
    return owner == actual;
  };
});

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  final owner = ref.watch(agentOwnerProvider);
  final guard = ref.watch(agentOwnerGuardProvider);
  return AgentRepository(
    database: ref.watch(appDatabaseProvider),
    userId: owner,
    isCurrentOwner: () => guard(owner),
  );
});

final agentWorkspaceProvider = StreamProvider<AgentWorkspace>(
  (ref) => ref.watch(agentRepositoryProvider).watchWorkspace(),
);

final agentGatewayProvider = Provider<AgentGateway>((ref) {
  const localUrl = String.fromEnvironment('CHECKD_AGENT_DEV_URL');
  const localToken = String.fromEnvironment('CHECKD_AGENT_DEV_TOKEN');
  if (localUrl.isNotEmpty) {
    return LocalAgentGateway(endpoint: Uri.parse(localUrl), token: localToken);
  }
  return SupabaseAgentGateway(ref.watch(supabaseClientProvider));
});

final agentUsesLocalGatewayProvider = Provider<bool>(
  (ref) => const String.fromEnvironment('CHECKD_AGENT_DEV_URL').isNotEmpty,
);

class AgentInteractionState {
  const AgentInteractionState({
    this.busy = false,
    this.error,
    this.pending,
    this.attachments = const [],
    this.connection,
    this.entityNames = const {},
    this.appliedSummary,
  });
  final bool busy;
  final String? error, connection;
  final AgentProposal? pending;
  final List<AgentAttachment> attachments;
  final Map<String, String> entityNames;
  final String? appliedSummary;
  AgentInteractionState copyWith({
    bool? busy,
    String? error,
    bool clearError = false,
    AgentProposal? pending,
    bool clearPending = false,
    List<AgentAttachment>? attachments,
    String? connection,
    Map<String, String>? entityNames,
    String? appliedSummary,
    bool clearAppliedSummary = false,
  }) => AgentInteractionState(
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
    pending: clearPending ? null : pending ?? this.pending,
    attachments: attachments ?? this.attachments,
    connection: connection ?? this.connection,
    entityNames: entityNames ?? this.entityNames,
    appliedSummary: clearAppliedSummary
        ? null
        : appliedSummary ?? this.appliedSummary,
  );
}

final agentInteractionProvider =
    NotifierProvider<AgentInteractionController, AgentInteractionState>(
      AgentInteractionController.new,
    );

class AgentInteractionController extends Notifier<AgentInteractionState> {
  var _generation = 0;
  @override
  AgentInteractionState build() {
    ref.watch(agentOwnerProvider);
    _generation++;
    return const AgentInteractionState();
  }

  bool _current(int generation, String owner) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(agentOwnerGuardProvider)(owner);

  void addAttachments(List<AgentAttachment> added) {
    if (state.busy) return;
    final next = [...state.attachments, ...added];
    if (next.length > 6 ||
        next.fold<int>(0, (n, item) => n + item.images.length) > 12) {
      state = state.copyWith(error: '每次最多 6 个附件、合计 12 张图片或 PDF 页面。');
      return;
    }
    state = state.copyWith(attachments: next, clearError: true);
  }

  void removeAttachment(int index) {
    if (state.busy) return;
    final next = [...state.attachments]..removeAt(index);
    state = state.copyWith(attachments: next);
  }

  void dismissProposal() =>
      state = state.copyWith(clearPending: true, clearError: true);

  Future<bool> send(String input) async {
    final request = input.trim();
    if (state.busy || request.isEmpty) return false;
    final generation = _generation;
    final owner = ref.read(agentOwnerProvider);
    final repository = ref.read(agentRepositoryProvider);
    final gateway = ref.read(agentGatewayProvider);
    final attachments = [...state.attachments];
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearPending: true,
      clearAppliedSummary: true,
    );
    try {
      final workspace = await repository.loadWorkspace();
      final context = await repository.buildContext();
      if (!_current(generation, owner)) return false;
      // The current message is supplied separately to the gateway, not twice in history.
      await repository.appendMessage(
        AgentChatMessage(
          role: 'user',
          text: request,
          createdAt: DateTime.now(),
        ),
      );
      if (!_current(generation, owner)) return false;
      final proposal = await gateway.propose(
        request: request,
        context: context,
        history: workspace.messages,
        attachments: attachments,
      );
      if (!_current(generation, owner)) return false;
      final prepared = proposal.hasChanges
          ? await repository.prepareProposal(proposal)
          : proposal;
      if (!_current(generation, owner)) return false;
      AgentApplyResult? automaticResult;
      final automatic =
          prepared.hasChanges &&
          workspace.profile['autoApply'] == true &&
          prepared.questions.isEmpty &&
          !prepared.operations.any(
            (operation) => operation.action.contains('course'),
          );
      await repository.appendMessage(
        AgentChatMessage(
          role: 'assistant',
          text: [
            prepared.reply,
            ...prepared.questions,
            if (!prepared.hasChanges)
              ...prepared.warnings.map((warning) => '提醒：$warning'),
          ].where((part) => part.isNotEmpty).join('\n'),
          createdAt: DateTime.now(),
        ),
      );
      if (!_current(generation, owner)) return false;
      if (automatic) {
        // Retain an inspectable proposal when a stale/conflict write is refused.
        state = state.copyWith(
          pending: prepared,
          entityNames: _names(context.data),
        );
        automaticResult = await repository.applyProposal(prepared);
        if (!_current(generation, owner)) return false;
      }
      state = state.copyWith(
        busy: false,
        pending: prepared.hasChanges && automaticResult == null
            ? prepared
            : null,
        clearPending: !prepared.hasChanges || automaticResult != null,
        entityNames: _names(context.data),
        appliedSummary: automaticResult?.summary,
        attachments: automaticResult == null ? null : const [],
      );
      return true;
    } on Object catch (error) {
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, error: _readable(error));
      }
      return false;
    }
  }

  Future<void> preview(List<AgentOperation> operations, String reply) async {
    if (state.busy) return;
    final generation = _generation;
    final owner = ref.read(agentOwnerProvider);
    final repository = ref.read(agentRepositoryProvider);
    state = state.copyWith(busy: true, clearError: true);
    try {
      final context = await repository.buildContext();
      final proposal = await repository.prepareProposal(
        AgentProposal(
          id: const Uuid().v4(),
          reply: reply,
          contextRevision: context.revision,
          operations: operations,
        ),
      );
      if (_current(generation, owner)) {
        state = state.copyWith(
          busy: false,
          pending: proposal,
          entityNames: _names(context.data),
        );
      }
    } on Object catch (error) {
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, error: _readable(error));
      }
    }
  }

  Future<AgentApplyResult?> apply() async {
    final proposal = state.pending;
    if (state.busy || proposal == null) return null;
    final generation = _generation;
    final owner = ref.read(agentOwnerProvider);
    final repository = ref.read(agentRepositoryProvider);
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await repository.applyProposal(proposal);
      if (!_current(generation, owner)) return null;
      state = state.copyWith(
        busy: false,
        clearPending: true,
        attachments: const [],
        appliedSummary: result.summary,
      );
      return result;
    } on Object catch (error) {
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, error: _readable(error));
      }
      return null;
    }
  }

  Future<AgentApplyResult?> undo() async {
    if (state.busy) return null;
    final generation = _generation;
    final owner = ref.read(agentOwnerProvider);
    final repository = ref.read(agentRepositoryProvider);
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await repository.undoLast();
      if (!_current(generation, owner)) return null;
      state = state.copyWith(
        busy: false,
        clearPending: true,
        clearAppliedSummary: true,
      );
      return result;
    } on Object catch (error) {
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, error: _readable(error));
      }
      return null;
    }
  }

  Future<void> diagnose() async {
    if (state.busy) return;
    final generation = _generation;
    final owner = ref.read(agentOwnerProvider);
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await ref.read(agentGatewayProvider).diagnose();
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, connection: result);
      }
    } on Object catch (error) {
      if (_current(generation, owner)) {
        state = state.copyWith(busy: false, error: _readable(error));
      }
    }
  }

  String _readable(Object error) => error is AgentException
      ? error.message
      : error is FormatException
      ? error.message
      : '这次操作没有完成，请重试。输入和附件已保留。';

  Map<String, String> _names(Object? value) {
    final result = <String, String>{};
    void visit(Object? item) {
      if (item is Map) {
        final id = item['id'];
        final title = item['name'] ?? item['title'];
        if (id is String && title is String) result[id] = title;
        item.values.forEach(visit);
      } else if (item is List) {
        item.forEach(visit);
      }
    }

    visit(value);
    return result;
  }
}
