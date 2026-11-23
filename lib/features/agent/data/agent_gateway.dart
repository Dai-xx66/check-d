import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/agent_models.dart';

abstract interface class AgentGateway {
  Future<AgentProposal> propose({
    required String request,
    required AgentContext context,
    required List<AgentChatMessage> history,
    List<AgentAttachment> attachments = const [],
  });
  Future<String> diagnose();
}

Map<String, Object?> _requestBody(
  String request,
  AgentContext context,
  List<AgentChatMessage> history,
  List<AgentAttachment> attachments,
) {
  if (request.trim().isEmpty) throw const AgentException('请先写下想让智能体帮忙的事。');
  if (request.length > 12000) {
    throw const AgentException('单次要求最多12000字，请拆成几次发送。');
  }
  if (attachments.length > 6 ||
      attachments.fold(0, (int n, a) => n + a.images.length) > 12) {
    throw const AgentException('每次最多6个附件、12张图片或扫描页。');
  }
  if (attachments.fold(0, (int n, a) => n + a.text.length) > 60000) {
    throw const AgentException('附件正文超过60000字，请拆分发送；附件会保留。');
  }
  if (attachments.fold<int>(0, (n, a) => n + a.encodedSize) >
      17 * 1024 * 1024) {
    throw const AgentException('这组附件处理后仍过大，请减少图片或扫描页，分批发送；附件会保留。');
  }
  final recent = history.length > 12
      ? history.sublist(history.length - 12)
      : history;
  return {
    'request': request.trim(),
    'context': context.toJson(),
    'history': recent
        .map(
          (m) => {
            'role': m.role == 'user' ? 'user' : 'assistant',
            'text': m.text,
          },
        )
        .toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };
}

AgentException _safeError(Object? data, int status) {
  final error = data is Map ? data['error'] : null;
  final code = error is Map ? error['code']?.toString() : null;
  final message = switch (code) {
    'auth_required' => '请先登录CheckD后使用云端智能体。',
    'model_not_configured' => '管理员尚未配置模型密钥。',
    'quota_exceeded' => '请求较频繁或今日额度已用完，请稍后再试。',
    'model_busy' => '模型服务繁忙，请稍后重试。',
    'model_timeout' => '模型响应超时，请保留输入后重试。',
    'origin_not_allowed' => '当前网页来源尚未被云端允许，请联系管理员。',
    'vision_unavailable' => '当前模型不支持图片，请先提取正文。',
    'truncated_proposal' => '模型回复被截断，未修改数据。请缩小计划范围后重试。',
    'invalid_proposal' ||
    'protected_field' ||
    'unsupported_operation' => '模型提案未通过校验，未修改数据，请重试。',
    _ => status == 401 ? '登录状态已失效，请重新登录。' : '智能体服务暂不可用，请保留输入后重试。',
  };
  return AgentException(message, code: code ?? 'http_$status');
}

class SupabaseAgentGateway implements AgentGateway {
  SupabaseAgentGateway(this.client);
  final SupabaseClient? client;

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final current = client;
    if (current == null) {
      throw const AgentException(
        '尚未配置云端连接，请联系管理员。',
        code: 'cloud_unconfigured',
      );
    }
    if (current.auth.currentSession == null) {
      throw const AgentException('请先登录后使用云端智能体。', code: 'auth_required');
    }
    final owner = current.auth.currentUser?.id;
    try {
      final response = await current.functions
          .invoke('checkd-agent', body: body)
          .timeout(const Duration(seconds: 100));
      if (current.auth.currentUser?.id != owner) {
        throw const AgentException('账号已切换，已丢弃旧账号的回复。', code: 'account_changed');
      }
      if (response.status < 200 || response.status >= 300) {
        throw _safeError(response.data, response.status);
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (error) {
      throw _safeError(error.details, error.status);
    } on TimeoutException {
      throw const AgentException('模型响应超时，请保留输入后重试。', code: 'model_timeout');
    } on AgentException {
      rethrow;
    } catch (_) {
      throw const AgentException('无法连接云端，请检查网络后重试。', code: 'network_error');
    }
  }

  @override
  Future<AgentProposal> propose({
    required String request,
    required AgentContext context,
    required List<AgentChatMessage> history,
    List<AgentAttachment> attachments = const [],
  }) async => AgentProposal.fromJson(
    await _invoke(_requestBody(request, context, history, attachments)),
  );
  @override
  Future<String> diagnose() async =>
      (await _invoke({'mode': 'diagnose'}))['reply'] as String? ?? '云端连接可用。';
}

/// Development bridge only. The temporary local token is not a model API key.
class LocalAgentGateway implements AgentGateway {
  LocalAgentGateway({
    required this.endpoint,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (!{'127.0.0.1', 'localhost', '::1'}.contains(endpoint.host) ||
        !{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        token.length < 16) {
      throw ArgumentError('本机联调仅允许带临时令牌的localhost接口。');
    }
  }
  final Uri endpoint;
  final String token;
  final http.Client _client;
  Future<Map<String, dynamic>> _send(Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'x-checkd-dev-token': token,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 100));
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        throw const AgentException('本机服务返回格式错误，请重试。');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _safeError(decoded, response.statusCode);
      }
      return Map<String, dynamic>.from(decoded as Map);
    } on TimeoutException {
      throw const AgentException('模型响应超时，请重试。', code: 'model_timeout');
    } on AgentException {
      rethrow;
    } catch (_) {
      throw const AgentException('本机联调服务未启动或网络不可用。', code: 'network_error');
    }
  }

  @override
  Future<AgentProposal> propose({
    required String request,
    required AgentContext context,
    required List<AgentChatMessage> history,
    List<AgentAttachment> attachments = const [],
  }) async => AgentProposal.fromJson(
    await _send(_requestBody(request, context, history, attachments)),
  );
  @override
  Future<String> diagnose() async =>
      (await _send({'mode': 'diagnose'}))['reply'] as String? ?? '本机模型连接可用。';
}

/// Explicit offline preview; never selected as a silent cloud-error fallback.
class DemoAgentGateway implements AgentGateway {
  const DemoAgentGateway();
  @override
  Future<String> diagnose() async => '本地演练模式：未调用云端模型。';
  @override
  Future<AgentProposal> propose({
    required String request,
    required AgentContext context,
    required List<AgentChatMessage> history,
    List<AgentAttachment> attachments = const [],
  }) async => AgentProposal(
    id: const Uuid().v4(),
    reply: '这是本地演练，未调用模型。你可以先填写目标与可用时间，再连接云端生成真实方案。',
    contextRevision: context.revision,
    warnings: const ['演练不会假装生成真实模型计划。'],
  );
}
