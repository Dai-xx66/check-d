import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';

const root = resolve('build/web');
const types = { '.html': 'text/html', '.js': 'application/javascript', '.mjs': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf' };
createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://127.0.0.1:8767');
    let path = resolve(root, '.' + decodeURIComponent(url.pathname));
    if (path !== root && !path.startsWith(root + sep)) { response.writeHead(403); response.end(); return; }
    if (path === root || (await stat(path)).isDirectory()) path = resolve(path, 'index.html');
    const bytes = await readFile(path);
    response.writeHead(200, { 'content-type': types[extname(path)] || 'application/octet-stream', 'cache-control': 'no-store' }); response.end(bytes);
  } catch { response.writeHead(404); response.end('Not found'); }
}).listen(8767, '127.0.0.1', () => console.log('CheckD本机预览 http://127.0.0.1:8767'));
