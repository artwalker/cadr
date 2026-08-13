#!/usr/bin/env node
/**
 * Goal 19 Part C golden generator.
 *
 * Recreates packages/coding-agent/src/modes/interactive/components/mermaid.ts
 * against marked@18.0.5 + grok-mermaid@0.2.2 and writes
 * test/fixtures/mermaid-golden/transform-reference.json.
 *
 * Theme is omitted (plain lines) so the golden is independent of ANSI
 * palette / color-mode.  Lisp tests lock theme mapping separately.
 */

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, renameSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GM_TGZ = join(ROOT, 'test/fixtures/mermaid-golden/grok-mermaid-0.2.2.tgz');
const MARKED_TGZ = join(ROOT, 'test/fixtures/mermaid-golden/marked-18.0.5.tgz');
const CORPUS = join(ROOT, 'test/fixtures/mermaid-golden/transform-corpus.json');
const OUTPUT = join(ROOT, 'test/fixtures/mermaid-golden/transform-reference.json');

const GM_SHA = '61f98236a93be5f0b4f8caeb9956a728dc22b275d012b190639d3c03ae942934';
const MARKED_SHA = '7d0ea56f8c29c0e6dec5665e62ad8089136819ca7028612e52301c2ba279dac2';

function sha256(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

for (const [file, expected, label] of [
  [GM_TGZ, GM_SHA, 'grok-mermaid'],
  [MARKED_TGZ, MARKED_SHA, 'marked'],
]) {
  const actual = sha256(file);
  if (actual !== expected) {
    throw new Error(`${label} SHA-256 mismatch: ${actual} != ${expected}`);
  }
}

const tmp = mkdtempSync(join(tmpdir(), 'cadr-mermaid-transform-'));
try {
  execFileSync('tar', ['-xzf', GM_TGZ, '-C', tmp]);
  const markedDir = join(tmp, 'marked');
  execFileSync('mkdir', ['-p', markedDir]);
  execFileSync('tar', ['-xzf', MARKED_TGZ, '-C', markedDir]);

  const { render } = await import(pathToFileURL(join(tmp, 'package/dist/index.js')).href);
  const { Marked } = await import(pathToFileURL(join(markedDir, 'package/lib/marked.esm.js')).href);
  const parser = new Marked();

  function isMermaid(token) {
    return token.type === 'code' && token.lang?.trim().split(/\s+/, 1)[0]?.toLowerCase() === 'mermaid';
  }

  function codeSpan(line) {
    const content = line || '\u00a0';
    const longestBacktickRun = Math.max(0, ...Array.from(content.matchAll(/`+/g), (match) => match[0].length));
    const fence = '`'.repeat(longestBacktickRun + 1);
    const padding = content.startsWith('`') || content.endsWith('`') ? ' ' : '';
    return `${fence}${padding}${content}${padding}${fence}`;
  }

  function transform(markdown, context) {
    const mode = context.mode;
    if (mode === 'off' || context.messageType === 'assistant-thinking' || (context.isStreaming && mode !== 'streaming')) {
      return markdown;
    }
    return parser.lexer(markdown).map((token) => {
      if (!isMermaid(token)) return token.raw;
      const art = render(token.text);
      if (!art || art.width > context.availableWidth) return token.raw;
      if (!context.isStreaming && art.warnings.length > 0) {
        const suffix = art.warnings.length > 1 ? ` (+${art.warnings.length - 1} more)` : '';
        const warning = `Mermaid diagram not rendered: ${art.warnings[0]}${suffix}`;
        return `${token.raw}\n${codeSpan(warning)}  \n`;
      }
      return `${art.plain.map(codeSpan).join('  \n')}\n`;
    }).join('');
  }

  const corpus = JSON.parse(readFileSync(CORPUS, 'utf8'));
  const results = corpus.map((entry) => {
    const out = transform(entry.src, {
      mode: entry.mode,
      messageType: entry.messageType,
      isStreaming: entry.isStreaming,
      availableWidth: entry.availableWidth,
    });
    return {
      id: entry.id,
      src: entry.src,
      mode: entry.mode,
      messageType: entry.messageType,
      isStreaming: entry.isStreaming,
      availableWidth: entry.availableWidth,
      expected: out,
    };
  });

  const payload = {
    generatedBy: 'scripts/mermaid-transform-golden.mjs',
    marked: '18.0.5',
    grokMermaid: '0.2.2',
    results,
  };
  const tmpOut = OUTPUT + '.tmp';
  writeFileSync(tmpOut, JSON.stringify(payload, null, 2) + '\n');
  renameSync(tmpOut, OUTPUT);
  console.log(`wrote ${results.length} transform goldens to ${OUTPUT}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
