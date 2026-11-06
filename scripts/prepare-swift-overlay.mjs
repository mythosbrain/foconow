import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';

// Some upgraded CLT installations contain both an old and a new SwiftBridging
// module map. Hide the duplicate from this build via a virtual filesystem;
// the installed compiler and its SDK are never modified.
const directory = resolve(process.argv[2]);
const compiler = execFileSync('xcrun', ['--find', 'swiftc'], { encoding: 'utf8' }).trim();
const includes = resolve(dirname(compiler), '../include/swift');
const oldMap = join(includes, 'module.modulemap');
const newMap = join(includes, 'bridging.modulemap');
let duplicate = false;
try { duplicate = [oldMap, newMap].every(path => /module SwiftBridging\s*\{/.test(readFileSync(path, 'utf8'))); } catch {}
if (duplicate) {
  mkdirSync(directory, { recursive: true });
  const emptyMap = join(directory, 'empty.modulemap');
  const overlay = join(directory, 'overlay.json');
  writeFileSync(emptyMap, '// Replaced stale duplicate map for this build only.\n');
  writeFileSync(overlay, JSON.stringify({ version: 0, 'case-sensitive': 'true', roots: [{ type: 'file', name: oldMap, 'external-contents': emptyMap }] }));
  console.log(overlay);
}
