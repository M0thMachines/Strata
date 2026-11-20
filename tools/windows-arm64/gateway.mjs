#!/usr/bin/env node
// strata-openai-gateway — native Windows-on-Arm bridge: OpenAI HTTP <-> Strata engine stdio (--serve).
// Tokenizes with the pack's own vocab/merges (llama.cpp QWEN35 pretoken), streams "T id" lines -> SSE deltas.
// Zero npm dependencies; runs on the rig's native arm64 Node.
import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const PACK = arg('--pack', 'C:\\strata-woa\\packs\\iq3_s');
const ENGINE = arg('--engine', 'C:\\woa\\engine-build\\Release\\strata.exe');
const PORT = Number(arg('--port', '18500'));
const sep = argv.indexOf('--');
const engineArgs = sep >= 0 ? argv.slice(sep + 1) : [];

// ---------------- tokenizer (pack format: vocab.json + merges.txt + tokenizer.json) ----------------
const TDIR = join(PACK, 'tokenizer');
const vocab = JSON.parse(readFileSync(join(TDIR, 'vocab.json'), 'utf8'));
const mergeLines = readFileSync(join(TDIR, 'merges.txt'), 'utf8').split(/\r?\n/).slice(1).filter(Boolean);
const meta = JSON.parse(readFileSync(join(TDIR, 'tokenizer.json'), 'utf8'));
const bytesOf = t => { const b = []; for (const ch of t) { const v = unicodeToByte.get(ch); if (v !== undefined) b.push(v); else b.push(...new TextEncoder().encode(ch)); } return b; };
const END = vocab['<|im_end|>'] ?? meta.special_ids?.['tokenizer.ggml.eos_token_id'];
const SPECIAL_RE = /(<\|im_start\|>|<\|im_end\|>|<\|endoftext\|>)/;

function bytesToUnicode() { // gpt2 byte -> visible codepoint map
  const out = new Array(256); let n = 0;
  for (let b = 0; b < 256; b++) {
    const vis = (33 <= b && b <= 126) || (161 <= b && b <= 172) || (174 <= b && b <= 255);
    out[b] = vis ? b : 256 + n++;
  }
  return out;
}
const byteToUnicode = bytesToUnicode();
const unicodeToByte = new Map(byteToUnicode.map((u, b) => [String.fromCodePoint(u), b]));
const byteDecoder = new TextDecoder('utf-8', { fatal: false });
const idToBytes = new Map(Object.entries(vocab).map(([t, id]) => [id, bytesOf(t)]));
// merges keyed by byte-pair canonical form so both sides compare as byte arrays
const rank = new Map(mergeLines.map((m, i) => { const sp = m.indexOf(' '); return [bytesOf(m.slice(0, sp)).join('\u0000') + '\u0000' + bytesOf(m.slice(sp + 1)).join('\u0000'), i]; }));
// llama.cpp LLAMA_VOCAB_PRE_TYPE_QWEN35 (third_party/strata-llama src/llama-vocab.cpp L396)
const PRE = /(?:'[sS]|'[tT]|'[rR][eE]|'[vV][eE]|'[mM]|'[lL][lL]|'[dD])|[^\r\n\p{L}\p{N}]?[\p{L}\p{M}]+|\p{N}| ?[^\s\p{L}\p{M}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+/gu;
function encodePiece(piece) {
  const flat = [];
  for (const ch of piece) { const v = unicodeToByte.get(ch); if (v !== undefined) flat.push(v); else flat.push(...new TextEncoder().encode(ch)); }
  let syms = flat.map(b => [b]);
  for (;;) {
    let best = -1, bi = -1;
    for (let i = 0; i < syms.length - 1; i++) {
      const r = rank.get(syms[i].join('\u0000') + '\u0000' + syms[i + 1].join('\u0000'));
      if (r !== undefined && (best < 0 || r < best)) { best = r; bi = i; }
    }
    if (bi < 0) break;
    syms.splice(bi, 2, [...syms[bi], ...syms[bi + 1]]);
  }
  const ids = [];
  for (const sym of syms) {
    const t = sym.map(b => String.fromCodePoint(byteToUnicode[b])).join('');
    const id = vocab[t];
    if (id !== undefined) ids.push(id);
    else for (const b of sym) { const c = vocab[String.fromCodePoint(byteToUnicode[b])]; if (c !== undefined) ids.push(c); }
  }
  return ids;
}
function encode(text) {
  const ids = [];
  for (const part of text.split(SPECIAL_RE)) {
    if (!part) continue;
    if (part.startsWith('<|') && vocab[part] !== undefined) { ids.push(vocab[part]); continue; }
    for (const m of part.matchAll(PRE)) ids.push(...encodePiece(m[0]));
  }
  return ids;
}
function renderChat(messages) {
  let s = '';
  for (const m of messages) s += `<|im_start|>${m.role}\n${typeof m.content === 'string' ? m.content : ''}<|im_end|>\n`;
  return s + '<|im_start|>assistant\n';
}
function decodeIds(ids) { const b = []; for (const id of ids) b.push(...(idToBytes.get(id) ?? [])); return byteDecoder.decode(Uint8Array.from(b)); }

// ---------------- engine supervisor (one GEN at a time, FIFO) ----------------
let child = null, ready = null, outBuf = '', pending = null, busy = false;
const queue = [];
const perf = { history: [] };
let readyResolve;
function startEngine() {
  child = spawn(ENGINE, [...engineArgs, '--serve'], { cwd: join(ENGINE, '..'), stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', d => process.stderr.write('[engine] ' + d));
  child.on('exit', code => {
    console.log('engine exited', code);
    ready = null;
    if (pending) { pending.fail('engine exited ' + code); pending = null; busy = false; }
  });
  child.stdout.on('data', chunk => {
    outBuf += chunk;
    let nl;
    while ((nl = outBuf.indexOf('\n')) >= 0) {
      const line = outBuf.slice(0, nl).replace(/\r$/, '');
      outBuf = outBuf.slice(nl + 1);
      handleLine(line);
    }
  });
  ready = new Promise(res => { readyResolve = res; });
}
function handleLine(line) {
  if (!line) return;
  if (line.startsWith('READY')) { readyResolve?.(true); return; }
  if (!pending) return;
  if (line === 'DONE' || line.startsWith('DONE ')) {
    const f = line.split(' ');
    perf.history.push({ at: Date.now(), tokens: pending.count ?? 0, maxNew: pending.maxNew, field3: +f[3] || 0 });
    if (perf.history.length > 100) perf.history.shift();
    pending.finish();
    pending = null; busy = false; drain();
  } else if (line.startsWith('ERR ')) {
    pending.fail(line); pending = null; busy = false; drain();
  } else if (line.startsWith('T ')) {
    const tid = +line.slice(2);
    pending.count = (pending.count ?? 0) + 1;
    pending.onToken(tid);
  }
}
function drain() {
  const r = queue.shift();
  if (!r) return;
  busy = true; pending = r;
  child.stdin.write(r.line + '\n');
}
function enqueue(ids, maxNew, opts) {
  const keys = [];
  if (opts.temperature > 0) {
    keys.push('temperature=' + opts.temperature);
    if (opts.top_p != null) keys.push('top_p=' + opts.top_p);
    if (opts.top_k != null) keys.push('top_k=' + opts.top_k);
    if (opts.seed) keys.push('seed=' + opts.seed);
  }
  if (opts.logit_bias) keys.push('logit_bias=' + opts.logit_bias);
  const line = ('GEN ' + maxNew + ' ' + keys.join(' ') + ' ' + ids.join(',')).replace(/\s+/g, ' ').trim();
  const r = { line, maxNew, count: 0, parts: [], done: false };
  r.promise = new Promise((res, rej) => { r.resolveFn = res; r.rejectFn = rej; });
  r.onToken = tid => { if (tid !== END) r.parts.push(tid); };
  r.finish = () => { if (!r.done) { r.done = true; r.resolveFn(decodeIds(r.parts)); } };
  r.fail = msg => { if (!r.done) { r.done = true; r.rejectFn(new Error(msg)); } };
  queue.push(r);
  if (!busy) drain();
  return r;
}

// ---------------- HTTP ----------------
const modelId = 'qwen3.8-flash-next-iq3_s';
const json = (res, code, obj) => { res.writeHead(code, { 'content-type': 'application/json', 'access-control-allow-origin': '*' }); res.end(JSON.stringify(obj)); };
async function readBody(req) { let b = ''; for await (const c of req) b += c; return b ? JSON.parse(b) : {}; }

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') { res.writeHead(204, { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }); return res.end(); }
  if (url.pathname === '/v1/models' || url.pathname === '/models') return json(res, 200, { object: 'list', data: [{ id: modelId, object: 'model', owned_by: 'strata-woa' }] });
  if (url.pathname === '/v1/status' || url.pathname === '/health') return json(res, 200, { ok: !!child && !!ready, model: modelId, engine: ENGINE, queued: queue.length, busy, last: perf.history.at(-1) ?? null });
  if (url.pathname === '/metrics') return json(res, 200, { history: perf.history });
  if (url.pathname === '/v1/chat/completions' || url.pathname === '/chat/completions') {
    let body; try { body = await readBody(req); } catch { return json(res, 400, { error: 'bad json' }); }
    if (!ready) { startEngine(); return json(res, 503, { error: 'engine starting; retry' }); }
    const ids = encode(renderChat(body.messages ?? []));
    const maxNew = body.max_tokens ?? 1024;
    const opts = {
      temperature: body.temperature ?? 0.7, top_p: body.top_p, top_k: body.top_k, seed: body.seed,
      logit_bias: body.logit_bias ? Object.entries(body.logit_bias).map(([t, b]) => `${vocab[t] ?? t}:${b}`).join(',') : null,
    };
    const id = 'chatcmpl-' + Date.now(), created = Math.floor(Date.now() / 1000);
    const r = enqueue(ids, maxNew, opts);
    if (body.stream) {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
      let carry = [];
      const send = t => res.write(`data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created, model: modelId, choices: [{ index: 0, delta: { content: t }, finish_reason: null }] })}\n\n`);
      r.onToken = tid => {
        if (tid === END) return;
        carry.push(...(idToBytes.get(tid) ?? []));
        for (let i = carry.length; i > 0; i--) {
          const t = byteDecoder.decode(Uint8Array.from(carry.slice(0, i)));
          if (t && !t.includes('\uFFFD')) { send(t); carry = carry.slice(i); return; }
        }
      };
      r.resolveFn = () => {
        if (carry.length) send(byteDecoder.decode(Uint8Array.from(carry)));
        res.write(`data: ${JSON.stringify({ id, object: 'chat.completion.chunk', created, model: modelId, choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] })}\n\n`);
        res.write('data: [DONE]\n\n'); res.end();
      };
      r.rejectFn = e => { res.write(`data: ${JSON.stringify({ error: String(e.message ?? e) })}\n\n`); res.end(); };
      return;
    }
    try {
      const text = await r.promise;
      return json(res, 200, { id, object: 'chat.completion', created, model: modelId, choices: [{ index: 0, message: { role: 'assistant', content: text }, finish_reason: 'stop' }], usage: { prompt_tokens: ids.length, completion_tokens: r.count, total_tokens: ids.length + r.count } });
    } catch (e) { return json(res, 500, { error: String(e.message ?? e) }); }
  }
  json(res, 404, { error: 'not found' });
});
server.listen(PORT, () => console.log(`strata-openai-gateway :${PORT} pack=${PACK} engine=${ENGINE}`));

export { encode, decodeIds, renderChat, END };
