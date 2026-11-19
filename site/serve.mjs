#!/usr/bin/env node
// Builds the gallery and serves site/dist for local viewing.
//
//   node site/serve.mjs                 # http://127.0.0.1:4310
//   PORT=8080 HOST=0.0.0.0 node site/serve.mjs
//
// This is a development preview server only; it serves static files and rebuilds on start.

import { execFileSync } from 'node:child_process';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteDir = dirname(fileURLToPath(import.meta.url));
const distDir = join(siteDir, 'dist');
const port = Number(process.env.PORT ?? 4310);
const host = process.env.HOST ?? '127.0.0.1';

execFileSync(process.execPath, [join(siteDir, 'build.mjs')], { stdio: 'inherit' });

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.json': 'application/json; charset=utf-8',
};

createServer((request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost');
  let path = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
  if (path === '' || path.endsWith(sep)) path = join(path, 'index.html');
  const file = join(distDir, path);
  if (!file.startsWith(distDir + sep) || !existsSync(file) || !statSync(file).isFile()) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }
  response.writeHead(200, {
    'content-type': TYPES[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'no-cache',
  });
  createReadStream(file).pipe(response);
}).listen(port, host, () => {
  console.log(`Refract gallery: http://${host === '0.0.0.0' ? 'localhost' : host}:${port}/`);
});
