#!/usr/bin/env node
// Generic UTF-8 text processing; no game-specific patterns or dependencies.
import fs from 'node:fs';
import readline from 'node:readline';

async function main() {
  const args = process.argv.slice(2);
  if (!args.length || args.includes('--help')) {
    console.log('node tools/log-excerpt.mjs <file> [--match text ...] [--before 3] [--after 5]\n'
      + '  [--max-lines 200] [--ignore-case] [--counts]\n'
      + 'Literal OR matching. Prints the latest selected lines with line numbers.\n'
      + 'Without --match, prints the last --max-lines lines. UTF-8 input; read-only.\n'
      + '--counts counts exact matching lines (distinct entries capped by --max-lines).');
    return;
  }
  const file = args.shift();
  const options = { before: 3, after: 5, maxLines: 200, ignoreCase: false, counts: false, match: [] };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--ignore-case') options.ignoreCase = true;
    else if (arg === '--counts') options.counts = true;
    else if (arg === '--match') {
      const value = args[++i];
      if (!value) throw new Error('--match needs nonempty literal text');
      options.match.push(value);
    } else if (['--before', '--after', '--max-lines'].includes(arg)) {
      const value = args[++i];
      if (!/^\d+$/.test(value ?? '') || Number(value) > 10000) throw new Error(`${arg}: expected 0..10000`);
      options[{ '--before': 'before', '--after': 'after', '--max-lines': 'maxLines' }[arg]] = Number(value);
    } else throw new Error(`Unknown option: ${arg}`);
  }
  if (!options.maxLines) throw new Error('--max-lines must be greater than zero');
  if (!fs.statSync(file).isFile()) throw new Error('Input must be a regular file');
  const needles = options.match.map(text => options.ignoreCase ? text.toLowerCase() : text);
  const selected = [], previous = [], counts = new Map();
  let number = 0, after = 0, matches = 0, selectedTotal = 0, lastAdded = 0, uncatalogued = 0;
  const add = row => {
    if (row.number <= lastAdded) return; // Merge overlapping context windows.
    selectedTotal++; lastAdded = row.number;
    selected.push(row);
    if (selected.length > options.maxLines) selected.shift();
  };
  const stream = fs.createReadStream(file, { encoding: 'utf8' });
  const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
  try {
    for await (const text of lines) {
      const row = { number: ++number, text };
      const value = options.ignoreCase ? text.toLowerCase() : text;
      const hit = needles.length && needles.some(needle => value.includes(needle));
      if (!needles.length) add(row);
      else if (hit) {
        matches++;
        for (const context of previous) add(context);
        add(row); after = options.after;
        if (options.counts) {
          if (counts.has(text)) counts.set(text, counts.get(text) + 1);
          else if (counts.size < options.maxLines) counts.set(text, 1);
          else uncatalogued++;
        }
      } else if (after > 0) { add(row); after--; }
      if (needles.length && options.before) {
        previous.push(row);
        if (previous.length > options.before) previous.shift();
      }
    }
  } finally { lines.close(); stream.destroy(); }
  console.log(`Read ${number} lines; ${matches} matches; showing ${selected.length}/${selectedTotal} selected lines.`);
  if (selectedTotal > selected.length) console.log('Earlier selected lines omitted by --max-lines.');
  let last = 0;
  for (const row of selected) {
    if (last && row.number > last + 1) console.log('...');
    console.log(`${row.number}: ${row.text}`); last = row.number;
  }
  if (options.counts) {
    console.log('Exact matching-line counts (entire scanned input):');
    for (const [text, count] of [...counts].sort((a, b) => b[1] - a[1])) console.log(`${count}\t${text}`);
    if (uncatalogued) console.log(`${uncatalogued} additional matches not catalogued: distinct-line limit reached.`);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 2; });
