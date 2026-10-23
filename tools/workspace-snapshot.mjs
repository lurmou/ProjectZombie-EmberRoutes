#!/usr/bin/env node
// Read-only Git/file inventory. No staging, commits, restores or game knowledge.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('node tools/workspace-snapshot.mjs [--save file.json] [--compare file.json] [--json]\n'
      + 'Uses the Git repository containing the current working directory.\n'
      + 'Captures HEAD, branch, status, index identities and SHA-256 of tracked/untracked nonignored files.\n'
      + '--compare reports additions/removals/content or staging changes since a saved snapshot.\n'
      + '--save never overwrites; save under an ignored directory such as build/.\n'
      + 'Metadata only: NOT a backup, author attribution or atomic capture. No repository writes.');
    return;
  }
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--json') options.json = true;
    else if (['--save', '--compare'].includes(args[i])) {
      const key = args[i].slice(2), value = args[++i];
      if (!value || value.startsWith('--')) throw new Error(`--${key} needs a file path`);
      options[key] = path.resolve(value);
    } else throw new Error(`Unknown option: ${args[i]}`);
  }
  const git = (gitArgs, cwd = process.cwd()) => execFileSync('git',
    ['--no-optional-locks', '-c', 'core.safecrlf=false', '-c', 'core.quotepath=false', ...gitArgs],
    { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const root = git(['rev-parse', '--show-toplevel']).trim();
  const startedAt = new Date().toISOString();
  const index = new Map();
  const stageText = git(['ls-files', '--stage', '-z'], root);
  for (const entry of stageText.split('\0').filter(Boolean)) {
    const tab = entry.indexOf('\t'), file = entry.slice(tab + 1);
    if (!index.has(file)) index.set(file, []);
    index.get(file).push(entry.slice(0, tab));
  }
  for (const file of git(['ls-files', '--others', '--exclude-standard', '-z'], root).split('\0').filter(Boolean)) {
    if (!index.has(file)) index.set(file, []);
  }
  const files = Object.create(null);
  for (const file of [...index.keys()].sort()) {
    const absolute = path.join(root, file);
    let item;
    try {
      const stat = fs.lstatSync(absolute);
      if (stat.isSymbolicLink()) item = { kind: 'symlink', target: fs.readlinkSync(absolute) };
      else if (stat.isFile()) {
        const hash = createHash('sha256');
        for await (const chunk of fs.createReadStream(absolute)) hash.update(chunk);
        const after = fs.lstatSync(absolute);
        item = { kind: 'file', sha256: hash.digest('hex'), size: after.size,
          changedDuringRead: stat.size !== after.size || stat.mtimeMs !== after.mtimeMs };
      } else item = { kind: 'directory-or-special' }; // Submodules are identified by their index entry.
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      item = { kind: 'missing' };
    }
    files[file] = { ...item, index: index.get(file) };
  }
  const snapshot = { format: 1, root, startedAt, finishedAt: new Date().toISOString(),
    head: git(['rev-parse', '--verify', 'HEAD'], root).trim(),
    branch: git(['branch', '--show-current'], root).trim() || '(detached)',
    status: git(['status', '--short', '--untracked-files=all'], root).trimEnd(), files };
  let comparison;
  if (options.compare) {
    const old = JSON.parse(fs.readFileSync(options.compare, 'utf8').replace(/^\uFEFF/, ''));
    if (old.format !== 1 || !old.files || typeof old.files !== 'object' || Array.isArray(old.files)) throw new Error('Unsupported snapshot format');
    if (path.resolve(old.root) !== path.resolve(root)) throw new Error('Snapshots belong to different repositories');
    const added = [], removed = [], changed = [];
    for (const file of new Set([...Object.keys(old.files), ...Object.keys(files)])) {
      if (!Object.hasOwn(old.files, file)) added.push(file);
      else if (!Object.hasOwn(files, file)) removed.push(file);
      else if (JSON.stringify(old.files[file]) !== JSON.stringify(files[file])) changed.push(file);
    }
    comparison = { previousHead: old.head, headChanged: old.head !== snapshot.head, added, removed, changed };
  }
  if (options.save) {
    fs.mkdirSync(path.dirname(options.save), { recursive: true });
    fs.writeFileSync(options.save, JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx' });
  }
  if (options.json) console.log(JSON.stringify({ ...snapshot, comparison }, null, 2));
  else {
    console.log(`${snapshot.branch} @ ${snapshot.head}\n${Object.keys(files).length} inventoried paths. Metadata only; not a backup or atomic capture.`);
    if (options.save) console.log(`Saved: ${options.save}`);
    if (comparison) {
      console.log(`HEAD changed: ${comparison.headChanged}; added ${comparison.added.length}, removed ${comparison.removed.length}, changed ${comparison.changed.length}`);
      for (const kind of ['added', 'removed', 'changed']) for (const file of comparison[kind]) console.log(`${kind}\t${file}`);
    } else console.log(snapshot.status || 'Working tree clean.');
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 2; });
