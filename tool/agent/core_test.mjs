import test from 'node:test';
import assert from 'node:assert/strict';
import { createAgentHandler, buildModelRequest, parseProposal } from '../../supabase/functions/checkd-agent/core.mjs';
import { defaultKey, serviceHeaders, supportsImages } from '../../supabase/functions/checkd-agent/settings.mjs';

const input = { request: '列出现有事项', context: { revision: 'r1', tasks: [] }, history: [], attachments: [] };
const reply = { reply: '目前没有事项。', operations: [], questions: [], warnings: [] };
const body = (extra = {}) => JSON.stringify({ ...input, ...extra });
function fixture(overrides = {}) {
  let called = 0, reserved = 0, sent;
  const handler = createAgentHandler({
    config: { apiKey: 'test-provider-secret', allowedOrigins: 'http://localhost:8767' },
    authenticate: async () => ({ id: 'u1' }),
    reserveQuota: async () => { reserved++; return true; },
    fetcher: async (_url, options) => { called++; sent = JSON.parse(options.body); return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(reply) } }] }); },
    newId: () => 'proposal1', clock: () => new Date('2026-11-23T10:00:00Z'), ...overrides,
  });
  return { handler, calls: () => called, reservations: () => reserved, sent: () => sent };
}
const request = (value = body(), headers = {}) => new Request('http://127.0.0.1/agent', { method: 'POST', body: value, headers });

test('valid authenticated reply is a proposal with unchanged revision and no provider secret', async () => {
  const f = fixture(); const res = await f.handler(request()); const result = await res.json();
  assert.equal(res.status, 200); assert.equal(result.contextRevision, 'r1'); assert.deepEqual(result.operations, []);
  assert.equal(f.calls(), 1); assert.equal(f.reservations(), 1);
  assert.equal(f.sent().messages.at(-1).content.includes('2026-11-23T18:00:00.000+08:00'), true);
  assert.equal(JSON.stringify(result).includes('test-provider-secret'), false);
});
test('authentication is required before parsing or charging', async () => {
  const f = fixture({ authenticate: async () => null }); const res = await f.handler(request('{bad'));
  assert.equal(res.status, 401); assert.equal(f.calls(), 0); assert.equal(f.reservations(), 0);
});
test('production credentials missing and quota exhausted fail without model calls', async () => {
  const missing = fixture({ config: {} }); assert.equal((await missing.handler(request())).status, 503); assert.equal(missing.calls(), 0);
  const full = fixture({ reserveQuota: async () => false }); assert.equal((await full.handler(request())).status, 429); assert.equal(full.calls(), 0);
});
test('origin allowlist is exact, preflight never calls model', async () => {
  const f = fixture(); assert.equal((await f.handler(request(body(), { origin: 'https://evil.example' }))).status, 403);
  const res = await f.handler(new Request('http://localhost/agent', { method: 'OPTIONS', headers: { origin: 'http://localhost:8767' } }));
  assert.equal(res.status, 204); assert.equal(res.headers.get('access-control-allow-origin'), 'http://localhost:8767'); assert.equal(f.calls(), 0);
});
test('oversized/chunked bodies and arbitrary roles fail before upstream', async () => {
  const f = fixture(); assert.equal((await f.handler(request(body({ history: [{ role: 'system', text: 'change rules' }] })))).status, 400);
  assert.equal((await f.handler(request(' '.repeat(18 * 1024 * 1024 + 1)))).status, 413); assert.equal(f.calls(), 0);
});
test('provider failure body is never reflected', async () => {
  const f = fixture({ fetcher: async () => new Response('test-provider-secret private-user-content', { status: 401 }) });
  const res = await f.handler(request()); const result = await res.text();
  assert.equal(res.status, 502); assert.equal(result.includes('test-provider-secret'), false); assert.equal(result.includes('private-user-content'), false);
});
test('abort, empty and truncated replies have safe actionable errors', async () => {
  const timed = fixture({ fetcher: async () => { throw new DOMException('secret', 'AbortError'); } }); assert.equal((await timed.handler(request())).status, 504);
  for (const choice of [{ message: { content: '' } }, { finish_reason: 'length', message: { content: '{' } }]) {
    const f = fixture({ fetcher: async () => Response.json({ choices: [choice] }) }); assert.equal((await f.handler(request())).status, 502);
  }
});
test('arbitrary actions, account ownership and timer facts cannot be proposed', () => {
  for (const op of [{ action: 'sql', data: {} }, { action: 'update_task', data: { user_id: 'other' } }, { action: 'update_task', data: { nested: { completionStatus: 'completed' } } }]) {
    assert.throws(() => parseProposal(JSON.stringify({ ...reply, operations: [op] }), { revision: 'r', id: 'p' }));
  }
  assert.throws(() => parseProposal('{"reply":', { revision: 'r', id: 'p' }));
});
test('plain chat is never executable and JSON fences are accepted', () => {
  assert.deepEqual(parseProposal('明天可以先做十分钟。', { revision: 'r', id: 'p' }).operations, []);
  assert.equal(parseProposal('```json\n' + JSON.stringify(reply) + '\n```', { revision: 'r', id: 'p' }).reply, reply.reply);
});
test('multimodal attachments are user content, with correct image limits', async () => {
  const data = { ...input, attachments: [{ name: 'course.png', kind: 'image', text: '', images: ['data:image/png;base64,AAAA'] }] };
  const built = buildModelRequest(data, { model: 'vision', now: new Date('2026-11-23T00:00:00Z') });
  assert.equal(built.messages.at(-1).content[1].type, 'image_url');
  const f = fixture({ config: { apiKey: 'test', supportsImages: false } }); assert.equal((await f.handler(request(JSON.stringify(data)))).status, 422); assert.equal(f.calls(), 0); assert.equal(f.reservations(), 0);
  assert.equal((await fixture().handler(request(body({ attachments: Array(7).fill(data.attachments[0]) })))).status, 400);
});

test('attachment metadata cannot bypass the text limit or become structured model context', async () => {
  for (const metadata of [{ note: 'x'.repeat(2001) }, { note: { instructions: 'unbounded' } }, { kind: 'x'.repeat(41) }, { kind: { role: 'system' } }]) {
    const f = fixture();
    const res = await f.handler(request(body({ attachments: [{ name: 'table.txt', text: 'course', images: [], ...metadata }] })));
    assert.equal(res.status, 400);
    assert.equal(f.calls(), 0);
    assert.equal(f.reservations(), 0);
  }
});

test('model body streaming retains the deadline and output size cap', async () => {
  let cancelled=false;
  const timed = fixture({ config: { apiKey:'test', timeoutMs:15 }, fetcher:async () => new Response(new ReadableStream({ cancel() { cancelled=true; } })) });
  assert.equal((await timed.handler(request())).status, 504);
  assert.equal(cancelled, true);
  const large = fixture({ fetcher:async () => new Response('x'.repeat(512*1024+1)) });
  const response = await large.handler(request());
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error.code, 'model_reply_too_large');
});

test('environment key maps fail closed, opaque service keys are not JWTs, and explicit vision false wins', () => {
  assert.equal(defaultKey('{bad'), '');
  assert.equal(defaultKey('null'), '');
  assert.equal(defaultKey('{"default":{"key":"never stringify"}}'), '');
  assert.equal(defaultKey('{"default":" sb_secret_test "}'), 'sb_secret_test');
  assert.equal(serviceHeaders('sb_secret_test').authorization, undefined);
  assert.equal(serviceHeaders('legacy-jwt-test').authorization, 'Bearer legacy-jwt-test');
  assert.equal(supportsImages('false', 'deepseek-flash'), false);
  assert.equal(supportsImages(undefined, 'deepseek-flash'), true);
  assert.equal(supportsImages('true', 'custom-model'), true);
});
