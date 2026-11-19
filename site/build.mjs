#!/usr/bin/env node
// Builds the Refract component gallery into site/dist.
//
// The gallery is a static, dependency-free site. Its data comes straight from the repository: every case listed in
// Fixtures/Corpus.json (Swift input, expected Kotlin and ArkTS, mapping, string catalogs, expected diagnostics) and the
// mapping tables in docs/subset.md. Nothing here is part of the generator or of any generated application.

import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(siteDir, '..');
const srcDir = join(siteDir, 'src');
const distDir = join(siteDir, 'dist');

const TEXT_EXTENSIONS = new Set(['.swift', '.kt', '.ets', '.json', '.json5', '.xml', '.txt', '.md', '.diagnostics']);
const MAX_TEXT_BYTES = 256 * 1024;

// Orders the files of one case so the most useful ones come first in the browser.
const FILE_ORDER = ['Input.swift', 'Expected.kt', 'Expected.ets', 'Expected.diagnostics', 'refract.json'];

function posix(path) {
  return path.split(sep).join('/');
}

function listFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listFiles(full));
    } else if (entry.isFile()) {
      out.push(full);
    }
  }
  return out;
}

function fileRank(name) {
  const index = FILE_ORDER.indexOf(name);
  if (index >= 0) return index;
  if (name.endsWith('.swift')) return 10;
  if (name.endsWith('.kt') || name.endsWith('.ets')) return 20;
  return 30;
}

function readCase(path, implementationStatus) {
  const caseDir = join(repoRoot, 'Fixtures', path);
  const files = [];
  const binaries = [];
  for (const full of listFiles(caseDir)) {
    const name = posix(relative(caseDir, full));
    const size = statSync(full).size;
    if (!TEXT_EXTENSIONS.has(extname(full)) || size > MAX_TEXT_BYTES) {
      binaries.push({ name, size });
      continue;
    }
    files.push({ name, content: readFileSync(full, 'utf8') });
  }
  files.sort((a, b) => fileRank(a.name) - fileRank(b.name) || a.name.localeCompare(b.name));
  binaries.sort((a, b) => a.name.localeCompare(b.name));

  const names = new Set(files.map((file) => file.name));
  const kind = names.has('Expected.diagnostics') ? 'rejected' : 'accepted';
  const diagnostics = [];
  const diagnosticsFile = files.find((file) => file.name === 'Expected.diagnostics');
  if (diagnosticsFile) {
    for (const line of diagnosticsFile.content.split('\n')) {
      const match = line.match(/^(.+?):(\d+):(\d+): (error|warning) \[([^\]]+)\]: (.*)$/);
      if (!match) continue;
      const [, file, lineNumber, column, severity, code, rest] = match;
      const split = rest.indexOf(' Suggestion: ');
      diagnostics.push({
        file,
        line: Number(lineNumber),
        column: Number(column),
        severity,
        code,
        message: split >= 0 ? rest.slice(0, split) : rest,
        suggestion: split >= 0 ? rest.slice(split + ' Suggestion: '.length) : '',
      });
    }
  }
  return { path, implementationStatus, kind, files, binaries, diagnostics };
}

// Parses the four-column "SwiftUI | Compose | ArkUI | Semantics" tables in docs/subset.md, keeping each table's
// nearest heading so the reference page can group rows the same way the contract does.
function readSubsetTables() {
  const lines = readFileSync(join(repoRoot, 'docs', 'subset.md'), 'utf8').split('\n');
  const tables = [];
  let heading = '';
  let current = null;
  const cells = (line) =>
    line
      .trim()
      .replace(/^\|/, '')
      .replace(/\|$/, '')
      .split(/(?<!\\)\|/)
      .map((cell) => cell.trim());
  for (const line of lines) {
    const headingMatch = line.match(/^#{2,4} (.*)$/);
    if (headingMatch) {
      heading = headingMatch[1];
      current = null;
      continue;
    }
    if (!line.trim().startsWith('|')) {
      current = null;
      continue;
    }
    const row = cells(line);
    if (row.every((cell) => /^:?-+:?$/.test(cell))) continue;
    if (!current) {
      current = { heading, columns: row, rows: [] };
      tables.push(current);
      continue;
    }
    current.rows.push(row);
  }
  return tables.filter((table) => /SwiftUI/.test(table.columns[0] ?? ''));
}

function build() {
  const corpus = JSON.parse(readFileSync(join(repoRoot, 'Fixtures', 'Corpus.json'), 'utf8'));
  const cases = corpus.cases.map((entry) => readCase(entry.path, entry.implementationStatus));
  const revision = (() => {
    try {
      return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: repoRoot, encoding: 'utf8' }).trim();
    } catch {
      return null;
    }
  })();

  rmSync(distDir, { recursive: true, force: true });
  mkdirSync(distDir, { recursive: true });
  for (const name of readdirSync(srcDir)) {
    copyFileSync(join(srcDir, name), join(distDir, name));
  }

  const data = {
    schemaVersion: corpus.schemaVersion,
    revision,
    cases,
    subsetTables: readSubsetTables(),
  };
  writeFileSync(join(distDir, 'data.js'), `window.REFRACT_DATA = ${JSON.stringify(data)};\n`);

  const accepted = cases.filter((entry) => entry.kind === 'accepted').length;
  console.log(
    `Built ${posix(relative(repoRoot, distDir))}: ${cases.length} fixture cases ` +
      `(${accepted} accepted, ${cases.length - accepted} rejected), ${data.subsetTables.length} subset tables.`,
  );
}

build();
