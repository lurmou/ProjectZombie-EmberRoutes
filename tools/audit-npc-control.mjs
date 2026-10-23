#!/usr/bin/env node
// Read-only call-site inventory, not a parser or proof of runtime ownership.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('node tools/audit-npc-control.mjs [--changed] [--json]\n'
    + 'Lists Lua/Java NPC control call sites without loading the game.\n'
    + '--changed includes tracked changes against HEAD and untracked source files.\n'
    + 'Text matching only: inspect results; multiline/indirect calls can be missed.');
  process.exit(0);
}
if (args.some(arg => !['--changed', '--json'].includes(arg))) {
  console.error('Unknown option. Use --help.');
  process.exit(2);
}
const groups = [
  ['owned', /\b(?:body|\w+\.body)\.(?:move|stop|add|clear|requestStop)\s*\(/],
  ['control', /\bEmberRoutesProbeJava\.(?:acquireBodyControl|releaseBodyControl|moveWithControl|stopWithControl|freezeBodyControl|thawBodyControl|retireBodyControl|removeIdleCarrier)\s*\(/],
  ['move', /\b(?:Driver\.move|EmberRoutesProbeJava\.(?:commandFor|command)|(?:\w+\.)?moveTo)\s*\(/],
  ['stop', /\b(?:Driver\.stop|EmberRoutesProbeJava\.stopCarrier|(?:\w+\.)?(?:stopProbe|StopAllActionQueue))\s*\(/],
  ['queue', /\bISTimedActionQueue\.(?:add|addAfter|clear|queueActions)\s*\(|\bISTimedActionQueue\.queues\s*\[/],
  ['cancel', /\bProbe\.(?:cancelAll|cancelEvery|cancelWork|cancelCompanion|pauseAllWork)\s*\(/],
  ['recovery', /\b(?:Production\.(?:afterSave|tickPending)|Companion\.restoreState|Persistence\.(?:restore|save)|EmberRoutesProbeJava\.(?:saveCheckpointFor|saveCheckpoint|restoreCheckpoint))\s*\(/],
];
const changed = new Set();
if (args.includes('--changed')) {
  for (const command of [
    ['diff', '--name-only', '-z', 'HEAD', '--'],
    ['ls-files', '--others', '--exclude-standard', '-z'],
  ]) {
    const output = execFileSync('git', ['-c', 'core.safecrlf=false', ...command], { cwd: root, encoding: 'utf8' });
    for (const file of output.split('\0').filter(Boolean)) changed.add(file.replaceAll('\\', '/'));
  }
}
const rows = [];
let scanned = 0;
function walk(directory) {
  if (!fs.existsSync(directory)) return;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) { walk(absolute); continue; }
    if (!entry.isFile() || !/\.(lua|java)$/.test(entry.name)) continue;
    const file = path.relative(root, absolute).replaceAll('\\', '/');
    if (args.includes('--changed') && !changed.has(file)) continue;
    scanned++;
    fs.readFileSync(absolute, 'utf8').split(/\r?\n/).forEach((source, index) => {
      const text = source.trim();
      if (!text || /^(?:--|\/\/|\/\*|\*)/.test(text)) return;
      for (const [kind, pattern] of groups) {
        if (pattern.test(text)) rows.push({ kind, file, line: index + 1, text });
      }
    });
  }
}
walk(path.join(root, 'Contents/mods/EmberRoutesProbe/42/media/lua'));
walk(path.join(root, 'java/src/main/java'));
rows.sort((a, b) => a.kind.localeCompare(b.kind) || a.file.localeCompare(b.file) || a.line - b.line);
const counts = Object.fromEntries(groups.map(([kind]) => [kind, rows.filter(row => row.kind === kind).length]));
const report = { mode: args.includes('--changed') ? 'changed' : 'all', scanned, counts,
  limitation: 'Text inventory only; includes definitions and may miss multiline or indirect calls. No game execution.', rows };
if (args.includes('--json')) console.log(JSON.stringify(report, null, 2));
else {
  console.log(`Scanned ${scanned} source files (${report.mode}); ${rows.length} matches. No game execution.`);
  console.log(Object.entries(counts).map(([kind, count]) => `${kind}=${count}`).join('  '));
  for (const row of rows) console.log(`[${row.kind}] ${row.file}:${row.line}  ${row.text}`);
  console.log(report.limitation);
}
