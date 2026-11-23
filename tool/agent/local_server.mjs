// Local-only bridge. The provider secret is read from a file outside this repo.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createAgentHandler } from '../../supabase/functions/checkd-agent/core.mjs';

export async function loadConfig(path) {
  const values = {};
  for (const line of (await readFile(path, 'utf8')).split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (!match) continue;
    values[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  if (!values.DEEPSEEK_API_KEY?.trim()) throw new Error('配置文件尚未填写模型密钥。');
  return {
    apiKey: values.DEEPSEEK_API_KEY.trim(),
    baseUrl: values.DEEPSEEK_BASE_URL || 'https://api.deepseek.com',
    model: values.DEEPSEEK_MODEL || 'deepseek-flash',
    supportsImages: values.DEEPSEEK_SUPPORTS_IMAGES
      ? values.DEEPSEEK_SUPPORTS_IMAGES === 'true'
      : (values.DEEPSEEK_MODEL || 'deepseek-flash') === 'deepseek-flash',
  };
}

export async function startLocalServer({ secretPath, runtimePath, port = 8766, webPort = 8767 }) {
  const config = await loadConfig(secretPath);
  const token = randomBytes(32).toString('hex');
  const tokenBytes = Buffer.from(token);
  const handler = createAgentHandler({
    config: { ...config, allowedOrigins: `http://127.0.0.1:${webPort},http://localhost:${webPort}` },
    authenticate: async request => {
      const supplied = Buffer.from(request.headers.get('x-checkd-dev-token') || '');
      return supplied.length === tokenBytes.length && timingSafeEqual(supplied, tokenBytes)
        ? { id: 'local-evaluation' } : null;
    },
    // This is intentionally a local bridge, not a substitute for production JWT/quota.
    reserveQuota: async () => true,
  });
  const server = createServer(async (incoming, outgoing) => {
    try {
      if (incoming.url === '/health' && incoming.method === 'GET') {
        outgoing.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
        outgoing.end(JSON.stringify({ status: 'ready', scope: 'loopback-only' })); return;
      }
      if (incoming.url !== '/agent') { outgoing.writeHead(404); outgoing.end(); return; }
      const request = new Request(`http://127.0.0.1:${port}/agent`, {
        method: incoming.method,
        headers: incoming.headers,
        ...(incoming.method !== 'GET' && incoming.method !== 'HEAD'
          ? { body: incoming, duplex: 'half' } : {}),
      });
      const response = await handler(request);
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      outgoing.writeHead(500, { 'content-type': 'application/json' });
      outgoing.end(JSON.stringify({ error: { code: 'local_bridge_error', message: '本机连接失败。' } }));
    }
  });
  await new Promise((accept, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', accept); });
  try {
    await mkdir(dirname(runtimePath), { recursive: true });
    await writeFile(runtimePath, JSON.stringify({ endpoint: `http://127.0.0.1:${port}/agent`, token, webPort }), { mode: 0o600 });
  } catch (error) {
    await new Promise(accept => server.close(accept));
    throw error;
  }
  console.log(`本机模型服务已启动（127.0.0.1:${port}）；密钥未输出。`);
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const secretPath = process.argv[2] || resolve(homedir(), '.codex/secrets/checkd-agent.env');
  const runtimePath = process.argv[3] || resolve(homedir(), '.codex/tmp/checkd-agent-runtime.json');
  startLocalServer({ secretPath, runtimePath }).catch(() => {
    console.error('本机模型服务未启动，请检查仓库外配置文件或端口。密钥未输出。'); process.exitCode = 1;
  });
}
