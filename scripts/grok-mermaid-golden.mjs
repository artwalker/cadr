#!/usr/bin/env node
/**
 * Goal 19 Part A golden generator.
 *
 * Locks the baseline renderer `grok-mermaid@0.2.2` output for a fixed corpus
 * into `test/fixtures/mermaid-golden/reference.json`. The golden is the
 * authority for the pure-Lisp port (Part B): every corpus entry must render
 * byte-identical in cadr, and null/width/warnings must match exactly.
 *
 * Reproducibility: the fixture tarball is verified against the recorded
 * SHA-256 before unpacking, and the renderer is deterministic (no RNG, no
 * clock), so re-running this script on the same corpus and fixture rewrites
 * an identical reference.json.
 *
 * Usage: node scripts/grok-mermaid-golden.mjs
 */

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, renameSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE = join(ROOT, 'test/fixtures/mermaid-golden/grok-mermaid-0.2.2.tgz');
const CORPUS = join(ROOT, 'test/fixtures/mermaid-golden/corpus.json');
const OUTPUT = join(ROOT, 'test/fixtures/mermaid-golden/reference.json');

// Recorded from the refetch at /tmp/gm-refetch and the upstream
// package-lock.json integrity entry; must match the fixture on disk.
const ARTIFACT_SHA256 = '61f98236a93be5f0b4f8caeb9956a728dc22b275d012b190639d3c03ae942934';
const ARTIFACT_VERSION = '0.2.2';

function sha256(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

const actual = sha256(FIXTURE);
if (actual !== ARTIFACT_SHA256) {
  console.error(
    `artifact SHA-256 mismatch: expected ${ARTIFACT_SHA256}, got ${actual} ` +
      `(${FIXTURE})`,
  );
  process.exit(1);
}

const work = mkdtempSync(join(tmpdir(), 'gm-golden-'));
try {
  execFileSync('tar', ['-xzf', FIXTURE, '-C', work], { stdio: 'pipe' });
  const { render } = await import(pathToFileURL(join(work, 'package/dist/index.js')).href);

  const corpus = JSON.parse(readFileSync(CORPUS, 'utf8'));
  const results = corpus.map(({ id, src }) => {
    const art = render(src);
    if (art === null) {
      return { id, input: src, null: true };
    }
    return {
      id,
      input: src,
      null: false,
      width: art.width,
      warnings: art.warnings,
      plain: art.plain,
      styled: art.styled.map((row) => row.map(({ text, cls }) => [text, cls])),
    };
  });

  const reference = {
    generator: `grok-mermaid@${ARTIFACT_VERSION}`,
    artifactSha256: ARTIFACT_SHA256,
    generatorScript: 'scripts/grok-mermaid-golden.mjs',
    corpus: 'test/fixtures/mermaid-golden/corpus.json',
    results,
  };

  const tmp = `${OUTPUT}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(reference, null, 2)}\n`, 'utf8');
  renameSync(tmp, OUTPUT);

  const nulls = results.filter((r) => r.null).length;
  const withWarnings = results.filter((r) => !r.null && r.warnings.length > 0).length;
  console.log(
    `reference.json: ${results.length} cases (${nulls} null, ` +
      `${withWarnings} with warnings) <- grok-mermaid@${ARTIFACT_VERSION} ` +
      `sha256=${actual}`,
  );
} finally {
  rmSync(work, { recursive: true, force: true });
}
