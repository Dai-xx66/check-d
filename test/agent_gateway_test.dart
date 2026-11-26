import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:check_d/features/agent/data/agent_gateway.dart';
import 'package:check_d/features/agent/domain/agent_models.dart';

void main() {
  final context = AgentContext(
    ownerId: 'private-owner',
    revision: 'r1',
    data: const {'tasks': []},
  );
  const token = 'temporary-local-token';
  LocalAgentGateway gateway(MockClient client) => LocalAgentGateway(
    endpoint: Uri.parse('http://127.0.0.1:8766/agent'),
    token: token,
    client: client,
  );

  test(
    'loopback bridge sends only scoped context and last twelve messages',
    () async {
      final bridge = gateway(
        MockClient((request) async {
          expect(request.headers['x-checkd-dev-token'], token);
          final sent = jsonDecode(request.body) as Map;
          expect(sent['context']['revision'], 'r1');
          expect(sent['context'].containsKey('ownerId'), false);
          expect((sent['history'] as List).length, 12);
          expect(sent['history'][0]['text'], 'message 2');
          expect(request.body.contains('apiKey'), false);
          return http.Response(
            jsonEncode({
              'id': 'p1',
              'reply': '只有查询，没有改动。',
              'contextRevision': 'r1',
              'operations': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final proposal = await bridge.propose(
        request: '查询',
        context: context,
        history: [
          for (var i = 0; i < 14; i++)
            AgentChatMessage(
              role: 'user',
              text: 'message $i',
              createdAt: DateTime(2026, 11, 23),
            ),
        ],
      );
      expect(proposal.hasChanges, false);
    },
  );
  test(
    'provider bodies and credentials never become user-facing errors',
    () async {
      final bridge = gateway(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'model_not_configured',
                'message': 'private-provider-body',
              },
            }),
            503,
          ),
        ),
      );
      await expectLater(
        bridge.propose(request: '查询', context: context, history: []),
        throwsA(
          isA<AgentException>().having(
            (e) => e.message,
            'safe message',
            '管理员尚未配置模型密钥。',
          ),
        ),
      );
    },
  );
  test(
    'oversized attachment text fails before sending and leaves caller data intact',
    () async {
      var sent = false;
      final bridge = gateway(
        MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
      );
      final attachments = [
        AgentAttachment(name: 'notes.txt', kind: 'text', text: '字' * 60001),
      ];
      await expectLater(
        bridge.propose(
          request: '分析',
          context: context,
          history: [],
          attachments: attachments,
        ),
        throwsA(isA<AgentException>()),
      );
      expect(sent, false);
      expect(attachments.single.text.length, 60001);
    },
  );
  test(
    'invalid model actions are rejected instead of treated as executable proposals',
    () async {
      final bridge = gateway(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 'p',
              'reply': '操作',
              'contextRevision': 'r1',
              'operations': [
                {
                  'action': 'execute',
                  'data': {'sql': 'anything'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        bridge.propose(request: '查询', context: context, history: []),
        throwsFormatException,
      );
    },
  );
  test(
    'local configuration cannot accidentally send context to a public server',
    () {
      expect(
        () => LocalAgentGateway(
          endpoint: Uri.parse('https://example.com/agent'),
          token: token,
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalAgentGateway(
          endpoint: Uri.parse('http://localhost/agent?token=private'),
          token: token,
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalAgentGateway(
          endpoint: Uri.parse('http://localhost/agent'),
          token: 'short',
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'unconfigured production fails clearly instead of silently simulating success',
    () async {
      await expectLater(
        SupabaseAgentGateway(null).diagnose(),
        throwsA(
          isA<AgentException>().having(
            (e) => e.code,
            'code',
            'cloud_unconfigured',
          ),
        ),
      );
    },
  );
}
